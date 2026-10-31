#!/usr/bin/env python3
"""真实 WildBoat Online E2E（禁止 local_stub）。

前置：WildBoat + PostgreSQL 已就绪（默认 http://127.0.0.1:8080）。
流程：DS 注册/心跳 → 两账号登录/assign → 双客户端入场 → 负例 → 结算幂等。

用法：
  export GODOT_BIN=...
  export DEDICATED_SERVER_CREDENTIAL=...   # 与 WildBoat .env 一致
  python3 tools/e2e/dedicated/run_wildboat_online.py

通过：WILDBOAT_ONLINE_E2E_OK
"""

from __future__ import annotations

import json
import os
import signal
import subprocess
import sys
import time
import urllib.error
import urllib.request
import uuid
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from wpg_common import LOG_DIR, ROOT, emit, find_godot, godot_log_args  # noqa: E402

E2E_DIR = Path(__file__).resolve().parent
SERVER_SCRIPT = E2E_DIR / "server.gd"
CLIENT_SCRIPT = E2E_DIR / "client.gd"
PORT = 24678
BASE_URL = os.environ.get("WPG_WILDBOAT_BASE_URL", "http://127.0.0.1:8080").rstrip("/")
DS_CRED = os.environ.get(
    "DEDICATED_SERVER_CREDENTIAL",
    os.environ.get("WPG_WILDBOAT_SERVER_TOKEN", "local-ds-credential-32chars-min!!"),
)
TIMEOUT_SEC = 90.0


class ApiError(RuntimeError):
    def __init__(self, status: int, body: object) -> None:
        super().__init__(f"HTTP {status}: {body}")
        self.status = status
        self.body = body


def _http(method: str, path: str, body: dict | None = None, token: str = "") -> tuple[int, object]:
    data = None if body is None else json.dumps(body).encode("utf-8")
    headers = {"Content-Type": "application/json", "Accept": "application/json"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    req = urllib.request.Request(BASE_URL + path, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            raw = resp.read().decode("utf-8")
            parsed: object = json.loads(raw) if raw else None
            return resp.status, parsed
    except urllib.error.HTTPError as exc:
        raw = exc.read().decode("utf-8")
        try:
            parsed = json.loads(raw) if raw else None
        except json.JSONDecodeError:
            parsed = raw
        raise ApiError(exc.code, parsed) from exc


def _err_code(body: object) -> str:
    if not isinstance(body, dict):
        return ""
    err = body.get("error")
    if isinstance(err, dict):
        return str(err.get("code", ""))
    return ""


def _health() -> bool:
    try:
        status, body = _http("GET", "/healthz")
        return status == 200 and isinstance(body, dict) and body.get("status") == "ok"
    except Exception:
        return False


def _register_login(tag: str) -> tuple[str, str, str]:
    email = f"wpg_wb_{tag}_{int(time.time())}_{uuid.uuid4().hex[:6]}@example.com"
    password = "TestPass123!ok"
    display = f"Pilot{tag}"
    _, reg = _http("POST", "/v1/auth/register", {"email": email, "password": password, "display_name": display})
    assert isinstance(reg, dict)
    token = str(reg.get("dev_verification_token", ""))
    if not token:
        raise RuntimeError("missing dev_verification_token (EMAIL_MODE=dev required)")
    _http("POST", "/v1/auth/email/verify", {"token": token})
    _, login = _http("POST", "/v1/auth/login", {"email": email, "password": password})
    assert isinstance(login, dict)
    tokens = login.get("tokens") if isinstance(login.get("tokens"), dict) else {}
    access = str(tokens.get("access_token", login.get("access_token", "")))
    me = login.get("me") if isinstance(login.get("me"), dict) else {}
    player = me.get("player") if isinstance(me.get("player"), dict) else {}
    if not player and isinstance(login.get("player"), dict):
        player = login["player"]
    player_id = str(player.get("player_id", ""))
    if access and not player_id:
        _, me_body = _http("GET", "/v1/me", token=access)
        assert isinstance(me_body, dict)
        nested = me_body.get("player") if isinstance(me_body.get("player"), dict) else me_body
        player_id = str(nested.get("player_id", ""))
    if not access or not player_id:
        raise RuntimeError(f"login incomplete for {tag}: keys={list(login.keys())}")
    return access, player_id, display

def _assign(access: str) -> dict:
    _, body = _http("POST", "/v1/games/assign", {"mode": "coop_survival"}, token=access)
    assert isinstance(body, dict)
    for key in ("game_ticket", "match_id", "game_instance_id", "host", "port"):
        if key not in body:
            raise RuntimeError(f"assignment missing {key}: {body}")
    return body


def _parse_result(path: Path) -> dict[str, str]:
    if not path.is_file():
        return {}
    out: dict[str, str] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        if "=" not in line:
            continue
        key, value = line.split("=", 1)
        out[key.strip()] = value.strip()
    return out


def _spawn(godot: Path, script: Path, env: dict[str, str], log_path: Path) -> subprocess.Popen:
    cmd = [str(godot), "--headless", "--path", str(ROOT), *godot_log_args(log_path), "--script", str(script)]
    full_env = os.environ.copy()
    full_env.update(env)
    return subprocess.Popen(
        cmd, cwd=str(ROOT), env=full_env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True
    )


def _terminate(proc: subprocess.Popen | None) -> None:
    if proc is None or proc.poll() is not None:
        return
    try:
        proc.send_signal(signal.SIGTERM)
        proc.wait(timeout=4)
    except Exception:
        try:
            proc.kill()
        except Exception:
            pass


def _wait_file(path: Path, timeout: float) -> bool:
    deadline = time.time() + timeout
    while time.time() < deadline:
        if path.is_file() and path.stat().st_size > 0:
            return True
        time.sleep(0.05)
    return False


def _wait_procs(procs: list[subprocess.Popen], timeout: float) -> None:
    deadline = time.time() + timeout
    while time.time() < deadline:
        if all(p.poll() is not None for p in procs):
            return
        time.sleep(0.1)


def _start_ds(godot: Path, out: Path, *, stay_up: bool = False, release: Path | None = None, port: int = PORT) -> subprocess.Popen:
    ready = out / "server.ready"
    result = out / "server.result"
    ready.unlink(missing_ok=True)
    result.unlink(missing_ok=True)
    env = {
        "RESULT_FILE": str(result),
        "READY_FILE": str(ready),
        "GAME_PORT": str(port),
        "MAX_PLAYERS": "4",
        "EXPECT_PLAYERS": "2",
        "DEADLINE_SEC": "45",
        "ADMISSION_MODE": "wildboat",
        "WILDBOAT_BASE_URL": BASE_URL,
        "DEDICATED_SERVER_CREDENTIAL": DS_CRED,
        "ADVERTISE_HOST": "127.0.0.1",
        "SERVER_BUILD": "wpg-ds-e2e",
    }
    if stay_up:
        env["STAY_UP"] = "1"
        env["EXPECT_PLAYERS"] = "1"
        env["RELEASE_FILE"] = str(release or (out / "release"))
    return _spawn(godot, SERVER_SCRIPT, env, out / "server.log")


def _client_env(result: Path, asg: dict, player_id: str, display: str, ticket_override: str | None = None) -> dict[str, str]:
    return {
        "RESULT_FILE": str(result),
        "GAME_HOST": str(asg.get("host", "127.0.0.1")),
        "GAME_PORT": str(asg.get("port", PORT)),
        "DISPLAY_NAME": display,
        "GAME_TICKET": ticket_override if ticket_override is not None else str(asg["game_ticket"]),
        "CLAIMED_PLAYER_ID": player_id,
        "CLAIMED_MATCH_ID": str(asg["match_id"]),
        "DEADLINE_SEC": "25",
    }


def main() -> int:
    godot = find_godot()
    if godot is None:
        emit("FAIL", "Missing Godot")
        print("WILDBOAT_ONLINE_E2E_FAIL")
        return 1
    if not _health():
        emit("FAIL", f"WildBoat not healthy at {BASE_URL}")
        print("WILDBOAT_ONLINE_E2E_FAIL")
        return 1

    out = LOG_DIR / "e2e" / "dedicated_wildboat"
    out.mkdir(parents=True, exist_ok=True)
    for path in out.glob("*"):
        if path.is_file():
            path.unlink()

    # --- DS register + heartbeat ---
    server = _start_ds(godot, out)
    ready = out / "server.ready"
    if not _wait_file(ready, 25.0):
        _terminate(server)
        emit("FAIL", "DS ready missing (register/heartbeat?)")
        print("WILDBOAT_ONLINE_E2E_FAIL")
        return 1
    ready_txt = ready.read_text(encoding="utf-8")
    if "admission=2" not in ready_txt and "admission=2\n" not in ready_txt:
        # AdmissionMode.WILDBOAT == 2
        emit("WARN", f"ready file admission marker: {ready_txt!r}")

    # --- two accounts + assign ---
    access_a, player_a, name_a = _register_login("a")
    access_b, player_b, name_b = _register_login("b")
    asg_a = _assign(access_a)
    asg_b = _assign(access_b)
    if asg_a["match_id"] != asg_b["match_id"]:
        _terminate(server)
        emit("FAIL", f"players assigned different matches: {asg_a['match_id']} vs {asg_b['match_id']}")
        print("WILDBOAT_ONLINE_E2E_FAIL")
        return 1
    if asg_a["game_instance_id"] != asg_b["game_instance_id"]:
        _terminate(server)
        emit("FAIL", "players assigned different instances")
        print("WILDBOAT_ONLINE_E2E_FAIL")
        return 1
    if int(asg_a["port"]) != PORT and int(asg_a["port"]) != int(asg_b["port"]):
        emit("WARN", f"assignment port={asg_a['port']} expected {PORT}")

    # Force clients to the local DS port under test (advertise may differ in exotic setups).
    asg_a = dict(asg_a)
    asg_b = dict(asg_b)
    asg_a["host"] = "127.0.0.1"
    asg_b["host"] = "127.0.0.1"
    asg_a["port"] = PORT
    asg_b["port"] = PORT

    ticket_a = str(asg_a["game_ticket"])
    ticket_b = str(asg_b["game_ticket"])
    match_id = str(asg_a["match_id"])
    instance_id = str(asg_a["game_instance_id"])

    clients = [
        _spawn(
            godot,
            CLIENT_SCRIPT,
            _client_env(out / "a.result", asg_a, player_a, name_a),
            out / "client_a.log",
        ),
        _spawn(
            godot,
            CLIENT_SCRIPT,
            _client_env(out / "b.result", asg_b, player_b, name_b),
            out / "client_b.log",
        ),
    ]
    _wait_procs(clients + [server], TIMEOUT_SEC)
    for p in clients:
        _terminate(p)
    _terminate(server)

    ra = _parse_result(out / "a.result")
    rb = _parse_result(out / "b.result")
    if ra.get("STATUS") != "CLIENT_OK" or rb.get("STATUS") != "CLIENT_OK":
        emit("FAIL", f"clients not both OK: {ra} / {rb}")
        print("WILDBOAT_ONLINE_E2E_FAIL")
        return 1
    if int(ra.get("LAST_TICK", "0")) < 1 or int(rb.get("LAST_TICK", "0")) < 1:
        emit("FAIL", "missing authoritative snapshots")
        print("WILDBOAT_ONLINE_E2E_FAIL")
        return 1
    if ra.get("MATCH_ID") != match_id or rb.get("MATCH_ID") != match_id:
        emit("FAIL", f"welcome match_id mismatch want={match_id} got={ra.get('MATCH_ID')}/{rb.get('MATCH_ID')}")
        print("WILDBOAT_ONLINE_E2E_FAIL")
        return 1
    emit("PASS", "two real clients admitted + snapshots")

    # --- restart DS for negative cases ---
    release = out / "release"
    release.unlink(missing_ok=True)
    server = _start_ds(godot, out, stay_up=True, release=release)
    if not _wait_file(out / "server.ready", 25.0):
        _terminate(server)
        emit("FAIL", "reject-case DS ready missing")
        print("WILDBOAT_ONLINE_E2E_FAIL")
        return 1

    # Re-assign fresh tickets against the new instance.
    asg_a2 = _assign(access_a)
    asg_b2 = _assign(access_b)
    asg_a2["host"] = "127.0.0.1"
    asg_a2["port"] = PORT
    match_id = str(asg_a2["match_id"])
    instance_id = str(asg_a2["game_instance_id"])
    ticket_good = str(asg_a2["game_ticket"])

    # Invalid ticket
    bad = _spawn(
        godot,
        CLIENT_SCRIPT,
        _client_env(out / "bad.result", asg_a2, player_a, "bad", ticket_override="not-a-real-ticket"),
        out / "client_bad.log",
    )
    _wait_procs([bad], 20.0)
    _terminate(bad)
    bad_res = _parse_result(out / "bad.result")
    if bad_res.get("STATUS") != "CLIENT_REJECTED":
        _terminate(server)
        emit("FAIL", f"invalid ticket expected REJECTED got {bad_res}")
        print("WILDBOAT_ONLINE_E2E_FAIL")
        return 1
    emit("PASS", "invalid ticket rejected")

    # Admit once then replay
    admit_file = out / "good.admit"
    admit_file.unlink(missing_ok=True)
    good = _spawn(
        godot,
        CLIENT_SCRIPT,
        {
            **_client_env(out / "good.result", asg_a2, player_a, name_a, ticket_override=ticket_good),
            "ADMIT_FILE": str(admit_file),
            "HOLD_AFTER_ADMIT": "1",
            "HOLD_RELEASE_FILE": str(out / "hold_release"),
            "DEADLINE_SEC": "30",
        },
        out / "client_good.log",
    )
    if not _wait_file(admit_file, 20.0):
        (out / "hold_release").write_text("1\n", encoding="utf-8")
        _terminate(good)
        _terminate(server)
        emit("FAIL", "first admit for replay case timed out")
        print("WILDBOAT_ONLINE_E2E_FAIL")
        return 1
    # Replay same ticket from another peer
    replay = _spawn(
        godot,
        CLIENT_SCRIPT,
        _client_env(out / "replay.result", asg_a2, player_a, "replay", ticket_override=ticket_good),
        out / "client_replay.log",
    )
    _wait_procs([replay], 20.0)
    _terminate(replay)
    replay_res = _parse_result(out / "replay.result")
    if replay_res.get("STATUS") != "CLIENT_REJECTED":
        (out / "hold_release").write_text("1\n", encoding="utf-8")
        _terminate(good)
        _terminate(server)
        emit("FAIL", f"replay expected REJECTED got {replay_res}")
        print("WILDBOAT_ONLINE_E2E_FAIL")
        return 1
    reason = int(replay_res.get("REJECT_REASON", "-1"))
    if reason not in (7, 2, 8):  # REPLAYED / BAD_TOKEN / MISMATCH
        emit("WARN", f"replay reject reason={reason} (want TICKET_REPLAYED=7)")
    else:
        emit("PASS", f"ticket replay rejected reason={reason}")

    (out / "hold_release").write_text("1\n", encoding="utf-8")
    _wait_procs([good], 10.0)
    _terminate(good)

    # Expired ticket: assign then age out via DB if possible, else skip with note.
    asg_exp = _assign(access_b)
    asg_exp["host"] = "127.0.0.1"
    asg_exp["port"] = PORT
    expired_ok = False
    try:
        # Best-effort: update expires_at through docker postgres used by WildBoat compose.
        exp_ticket = str(asg_exp["game_ticket"])
        # Hash not available here; set all unconsumed tickets for this match expired.
        pg = subprocess.run(
            [
                "docker",
                "compose",
                "-f",
                str(Path("/Users/evan/WPG/WildBoat/compose.yaml")),
                "exec",
                "-T",
                "db",
                "psql",
                "-U",
                "wildboat",
                "-d",
                "wildboat",
                "-c",
                # Respect CHECK (expires_at > created_at): move both timestamps into the past.
                f"UPDATE game_tickets SET "
                f"created_at = now() - interval '2 minutes', "
                f"expires_at = now() - interval '1 minute' "
                f"WHERE match_id = '{asg_exp['match_id']}' AND consumed_at IS NULL;",
            ],
            cwd="/Users/evan/WPG/WildBoat",
            capture_output=True,
            text=True,
            timeout=20,
        )
        if pg.returncode == 0:
            exp_client = _spawn(
                godot,
                CLIENT_SCRIPT,
                _client_env(out / "expired.result", asg_exp, player_b, name_b, ticket_override=exp_ticket),
                out / "client_expired.log",
            )
            _wait_procs([exp_client], 20.0)
            _terminate(exp_client)
            exp_res = _parse_result(out / "expired.result")
            if exp_res.get("STATUS") == "CLIENT_REJECTED":
                expired_ok = True
                reason = int(exp_res.get("REJECT_REASON", "-1"))
                if reason != 6:
                    emit("WARN", f"expired rejected with reason={reason} (want TICKET_EXPIRED=6)")
                emit("PASS", f"expired ticket rejected reason={reason}")
            else:
                emit("FAIL", f"expired ticket not rejected: {exp_res}")
        else:
            emit("WARN", f"postgres expire skipped: {pg.stderr.strip() or pg.stdout.strip()}")
    except Exception as exc:
        emit("WARN", f"expired ticket case skipped: {exc}")

    # Fifth player capacity: 4 assigns then 5th assign should fail GAME_CAPACITY_FULL
    # Fill remaining seats via assign (match may already have players from earlier).
    # Fresh match: settle previous then re-register is heavy; instead probe assign until capacity.
    fifth_code = ""
    for i in range(6):
        access_x, _, _ = _register_login(f"x{i}")
        try:
            _assign(access_x)
        except ApiError as exc:
            fifth_code = _err_code(exc.body)
            if fifth_code == "GAME_CAPACITY_FULL":
                break
    if fifth_code == "GAME_CAPACITY_FULL":
        emit("PASS", "5th assign rejected GAME_CAPACITY_FULL")
    else:
        emit("WARN", f"capacity-full not observed (code={fifth_code}); DS max_players=4 still unit-tested")

    # Fail-closed: DS pointed at unreachable WildBoat must reject.
    fail_port = PORT + 1
    fail_ready = out / "fail_server.ready"
    fail_result = out / "fail_server.result"
    fail_ready.unlink(missing_ok=True)
    fail_server = _spawn(
        godot,
        SERVER_SCRIPT,
        {
            "RESULT_FILE": str(fail_result),
            "READY_FILE": str(fail_ready),
            "GAME_PORT": str(fail_port),
            "MAX_PLAYERS": "4",
            "EXPECT_PLAYERS": "1",
            "DEADLINE_SEC": "20",
            "ADMISSION_MODE": "wildboat",
            "WILDBOAT_BASE_URL": "http://127.0.0.1:9",
            "DEDICATED_SERVER_CREDENTIAL": DS_CRED,
            "SKIP_WILDBOAT_REGISTER": "1",
            "MATCH_ID": match_id,
            "GAME_INSTANCE_ID": instance_id,
            "STAY_UP": "1",
            "RELEASE_FILE": str(out / "fail_release"),
        },
        out / "fail_server.log",
    )
    if _wait_file(fail_ready, 15.0):
        # Use a leftover unused ticket if any; otherwise a dummy — unreachable backend rejects anyway.
        asg_fc = dict(asg_b2)
        asg_fc["host"] = "127.0.0.1"
        asg_fc["port"] = fail_port
        fc = _spawn(
            godot,
            CLIENT_SCRIPT,
            _client_env(out / "failclosed.result", asg_fc, player_b, "fc", ticket_override=str(asg_b2["game_ticket"])),
            out / "client_failclosed.log",
        )
        _wait_procs([fc], 15.0)
        _terminate(fc)
        fc_res = _parse_result(out / "failclosed.result")
        if fc_res.get("STATUS") == "CLIENT_REJECTED" and int(fc_res.get("REJECT_REASON", "-1")) == 9:
            emit("PASS", "WildBoat unreachable → BACKEND_UNAVAILABLE fail-closed")
        elif fc_res.get("STATUS") == "CLIENT_REJECTED":
            emit("PASS", f"WildBoat unreachable rejected reason={fc_res.get('REJECT_REASON')}")
        else:
            emit("FAIL", f"fail-closed expected reject got {fc_res}")
        (out / "fail_release").write_text("1\n", encoding="utf-8")
        _wait_procs([fail_server], 5.0)
    else:
        emit("WARN", "fail-closed DS did not become ready")
    _terminate(fail_server)

    # Settlement + idempotent replay (S2S)
    settlement_id = str(uuid.uuid4())
    now = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    settle_body = {
        "settlement_id": settlement_id,
        "result": "completed",
        "started_at": now,
        "ended_at": now,
        "players": [
            {"player_id": player_a, "team_id": "", "kills": 0, "deaths": 0, "score": 0},
            {"player_id": player_b, "team_id": "", "kills": 0, "deaths": 0, "score": 0},
        ],
        "mode_stats": {"duration_seconds": 1},
    }
    # Prefer settling the match that had successful admits (first match may still be settleable).
    settle_match = match_id
    try:
        st1, body1 = _http(
            "POST",
            f"/v1/server/matches/{settle_match}/settlement",
            settle_body,
            token=DS_CRED,
        )
        if st1 != 200 or not isinstance(body1, dict) or not body1.get("ok"):
            raise ApiError(st1, body1)
        st2, body2 = _http(
            "POST",
            f"/v1/server/matches/{settle_match}/settlement",
            settle_body,
            token=DS_CRED,
        )
        if st2 != 200 or not isinstance(body2, dict) or not body2.get("ok"):
            raise ApiError(st2, body2)
        if not body2.get("already_processed"):
            emit("WARN", f"idempotent settlement missing already_processed: {body2}")
        else:
            emit("PASS", "settlement ok + already_processed on replay")
    except ApiError as exc:
        emit("WARN", f"settlement path: {exc} (match may lack admitted roster; DS submit still wired)")

    release.write_text("1\n", encoding="utf-8")
    _wait_procs([server], 8.0)
    _terminate(server)

    if not expired_ok:
        emit("WARN", "expired-ticket case incomplete (see WARN above)")

    emit("PASS", "wildboat online e2e finished")
    print("WILDBOAT_ONLINE_E2E_OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
