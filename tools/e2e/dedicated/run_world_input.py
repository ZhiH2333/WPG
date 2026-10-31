#!/usr/bin/env python3
"""Phase 2D.1：真实 InputMap → 沙盒 flush → DS 权威移动（禁止测试侧 send_input）。

用法：python3 tools/e2e/dedicated/run_world_input.py
通过输出 WORLD_INPUT_E2E_OK。
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
CLIENT_SCRIPT = E2E_DIR / "world_input_client.gd"
PORT = 24688
TIMEOUT_SEC = 60.0


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
    cmd = [
        str(godot),
        "--headless",
        "--path",
        str(ROOT),
        *godot_log_args(log_path),
        "--script",
        str(script),
    ]
    full_env = os.environ.copy()
    full_env.update(env)
    return subprocess.Popen(
        cmd,
        cwd=str(ROOT),
        env=full_env,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )


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


def main() -> int:
    godot = find_godot()
    if godot is None:
        emit("FAIL", "Missing Godot")
        return 1

    out = LOG_DIR / "e2e-world-input"
    out.mkdir(parents=True, exist_ok=True)
    ready = out / "server.ready"
    server_result = out / "server.result"
    release = out / "server.release"
    client_a = out / "client_a.result"
    client_b = out / "client_b.result"
    for path in [ready, server_result, release, client_a, client_b]:
        path.unlink(missing_ok=True)

    server = _spawn(
        godot,
        SERVER_SCRIPT,
        {
            "RESULT_FILE": str(server_result),
            "READY_FILE": str(ready),
            "RELEASE_FILE": str(release),
            "STAY_UP": "1",
            "GAME_PORT": str(PORT),
            "MAX_PLAYERS": "4",
            "EXPECT_PLAYERS": "2",
            "DEV_TOKEN": "world-input-token",
            "MATCH_ID": "world_input_match",
            "DEADLINE_SEC": "50",
            "WPG_ONLINE_INPUT_DIAG": "1",
        },
        out / "server.log",
    )
    if not _wait_file(ready, 12.0):
        emit("FAIL", "server ready missing")
        _terminate(server)
        return 1

    clients: list[subprocess.Popen] = []
    for name, result, action in (
        ("A", client_a, "move_right"),
        ("B", client_b, "move_left"),
    ):
        clients.append(
            _spawn(
                godot,
                CLIENT_SCRIPT,
                {
                    "RESULT_FILE": str(result),
                    "GAME_HOST": "127.0.0.1",
                    "GAME_PORT": str(PORT),
                    "DISPLAY_NAME": f"input-{name}",
                    "DEV_TOKEN": "world-input-token",
                    "CLAIMED_MATCH_ID": "world_input_match",
                    "MOVE_ACTION": action,
                    "DEADLINE_SEC": "40",
                    "WPG_ONLINE_INPUT_DIAG": "1",
                },
                out / f"client_{name.lower()}.log",
            )
        )

    deadline = time.time() + TIMEOUT_SEC
    ok = False
    while time.time() < deadline:
        if client_a.is_file() and client_b.is_file():
            ra = _parse_result(client_a)
            rb = _parse_result(client_b)
            if ra.get("STATUS") and rb.get("STATUS"):
                ok = True
                break
        time.sleep(0.1)

    release.write_text("done\n", encoding="utf-8")
    time.sleep(0.6)
    for proc in clients:
        _terminate(proc)
    _terminate(server)

    ra = _parse_result(client_a)
    rb = _parse_result(client_b)
    if not ok:
        emit("FAIL", "timeout waiting input clients")
        emit("INFO", f"A={ra} B={rb}")
        return 1

    checks = [
        (ra.get("STATUS") == "CLIENT_OK", "A OK"),
        (rb.get("STATUS") == "CLIENT_OK", "B OK"),
        (ra.get("PEER_ALIVE_AFTER_HANDOFF") == "1", "A peer survived LobbyNet teardown"),
        (rb.get("PEER_ALIVE_AFTER_HANDOFF") == "1", "B peer survived LobbyNet teardown"),
        (ra.get("ENTERED") == "1", "A entered sandbox"),
        (rb.get("ENTERED") == "1", "B entered sandbox"),
        (ra.get("SAW_TWO_PAWNS") == "1", "A saw two world pawns"),
        (rb.get("SAW_TWO_PAWNS") == "1", "B saw two world pawns"),
        (ra.get("LOCAL_MOVED") == "1", "A local pawn moved via InputMap flush"),
        (rb.get("LOCAL_MOVED") == "1", "B local pawn moved via InputMap flush"),
        (ra.get("REMOTE_MOVED") == "1", "A saw remote move"),
        (rb.get("REMOTE_MOVED") == "1", "B saw remote move"),
        (ra.get("SEAT") != rb.get("SEAT"), "distinct seats"),
    ]
    failed = [label for cond, label in checks if not cond]
    if failed:
        emit("FAIL", f"world input checks failed: {failed}")
        emit("INFO", f"A={ra}")
        emit("INFO", f"B={rb}")
        return 1

    emit("PASS", "WORLD_INPUT_E2E_OK")
    print("WORLD_INPUT_E2E_OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
