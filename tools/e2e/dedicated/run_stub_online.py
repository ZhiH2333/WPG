#!/usr/bin/env python3
"""Stub Online E2E：DS admission_mode=stub + 两客户端不同 stub ticket。

用法：python3 tools/e2e/dedicated/run_stub_online.py
通过：STUB_ONLINE_E2E_OK
"""

from __future__ import annotations

import os
import signal
import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from wpg_common import LOG_DIR, ROOT, emit, find_godot, godot_log_args  # noqa: E402

E2E_DIR = Path(__file__).resolve().parent
SERVER_SCRIPT = E2E_DIR / "server.gd"
CLIENT_SCRIPT = E2E_DIR / "client.gd"
PORT = 24677
TIMEOUT_SEC = 40.0


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
    return subprocess.Popen(cmd, cwd=str(ROOT), env=full_env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)


def _terminate(proc: subprocess.Popen | None) -> None:
    if proc is None or proc.poll() is not None:
        return
    try:
        proc.send_signal(signal.SIGTERM)
        proc.wait(timeout=3)
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


def _stub_ticket(player_id: str, nonce: str, exp_offset: int = 120) -> str:
    exp = int(time.time()) + exp_offset
    return f"wpgstub1.{player_id}.dev_match.dev_instance.{exp}.{nonce}"


def main() -> int:
    godot = find_godot()
    if godot is None:
        emit("FAIL", "Missing Godot")
        return 1
    out = LOG_DIR / "e2e" / "dedicated_stub"
    out.mkdir(parents=True, exist_ok=True)
    ready = out / "server.ready"
    server_result = out / "server.result"
    for path in [ready, server_result, out / "a.result", out / "b.result", out / "bad.result"]:
        path.unlink(missing_ok=True)

    server = _spawn(
        godot,
        SERVER_SCRIPT,
        {
            "RESULT_FILE": str(server_result),
            "READY_FILE": str(ready),
            "GAME_PORT": str(PORT),
            "MAX_PLAYERS": "4",
            "EXPECT_PLAYERS": "2",
            "DEADLINE_SEC": "25",
            "ADMISSION_MODE": "stub",
            "MATCH_ID": "dev_match",
            "GAME_INSTANCE_ID": "dev_instance",
        },
        out / "server.log",
    )
    if not _wait_file(ready, 15.0):
        _terminate(server)
        emit("FAIL", "stub server ready missing")
        print("STUB_ONLINE_E2E_FAIL")
        return 1

    clients = []
    for name, ticket in [("a", _stub_ticket("alice", "na")), ("b", _stub_ticket("bob", "nb"))]:
        clients.append(
            _spawn(
                godot,
                CLIENT_SCRIPT,
                {
                    "RESULT_FILE": str(out / f"{name}.result"),
                    "GAME_HOST": "127.0.0.1",
                    "GAME_PORT": str(PORT),
                    "DISPLAY_NAME": name,
                    "GAME_TICKET": ticket,
                    "DEADLINE_SEC": "20",
                },
                out / f"client_{name}.log",
            )
        )

    deadline = time.time() + TIMEOUT_SEC
    while time.time() < deadline:
        if all(p.poll() is not None for p in clients) and server.poll() is not None:
            break
        time.sleep(0.1)
    for p in clients:
        _terminate(p)
    _terminate(server)

    ra = _parse_result(out / "a.result")
    rb = _parse_result(out / "b.result")
    if ra.get("STATUS") != "CLIENT_OK" or rb.get("STATUS") != "CLIENT_OK":
        emit("FAIL", f"clients not both OK: {ra} / {rb}")
        print("STUB_ONLINE_E2E_FAIL")
        return 1
    if int(ra.get("LAST_TICK", "0")) < 1 or int(rb.get("LAST_TICK", "0")) < 1:
        emit("FAIL", "missing snapshots")
        print("STUB_ONLINE_E2E_FAIL")
        return 1

    ## 重启服测无票拒绝
    for path in [ready, server_result, out / "bad.result"]:
        path.unlink(missing_ok=True)
    server = _spawn(
        godot,
        SERVER_SCRIPT,
        {
            "RESULT_FILE": str(server_result),
            "READY_FILE": str(ready),
            "GAME_PORT": str(PORT),
            "MAX_PLAYERS": "4",
            "EXPECT_PLAYERS": "1",
            "DEADLINE_SEC": "15",
            "ADMISSION_MODE": "stub",
            "MATCH_ID": "dev_match",
            "GAME_INSTANCE_ID": "dev_instance",
            "STAY_UP": "1",
            "RELEASE_FILE": str(out / "release"),
        },
        out / "server2.log",
    )
    if not _wait_file(ready, 15.0):
        _terminate(server)
        emit("FAIL", "reject-case server ready missing")
        print("STUB_ONLINE_E2E_FAIL")
        return 1
    bad = _spawn(
        godot,
        CLIENT_SCRIPT,
        {
            "RESULT_FILE": str(out / "bad.result"),
            "GAME_HOST": "127.0.0.1",
            "GAME_PORT": str(PORT),
            "DISPLAY_NAME": "intruder",
            "GAME_TICKET": "not-a-stub",
            "DEADLINE_SEC": "12",
        },
        out / "client_bad.log",
    )
    deadline = time.time() + 15.0
    while time.time() < deadline and bad.poll() is None:
        time.sleep(0.05)
    _terminate(bad)
    (out / "release").write_text("1\n", encoding="utf-8")
    deadline = time.time() + 5.0
    while time.time() < deadline and server.poll() is None:
        time.sleep(0.05)
    _terminate(server)
    bad_res = _parse_result(out / "bad.result")
    if bad_res.get("STATUS") != "CLIENT_REJECTED":
        emit("FAIL", f"expected reject, got {bad_res}")
        print("STUB_ONLINE_E2E_FAIL")
        return 1

    emit("PASS", "stub online two-client + reject")
    print("STUB_ONLINE_E2E_OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
