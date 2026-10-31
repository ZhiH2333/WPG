#!/usr/bin/env python3
"""Phase 2D Dedicated world-sync E2E（权威移动 + 双向可见 + Leave 清理）。

证明（协议层，headless 双客户端）：
  1) 两名玩家准入同一 match，DS 创建两个不同 seat 状态
  2) A 移动后 B 的 snapshot 含 A 的新位置
  3) B 移动后 A 的 snapshot 含 B 的新位置
  4) A 离开后 B 收到 peer_left / 人数下降
  5) 无效身份不能伪造他人状态（由 unit 覆盖；此处断言双方 seat 不同）

用法：python3 tools/e2e/dedicated/run_world_sync.py
通过输出 WORLD_SYNC_E2E_OK。
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
CLIENT_SCRIPT = E2E_DIR / "world_sync_client.gd"
PORT = 24677
TIMEOUT_SEC = 50.0


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

    out = LOG_DIR / "e2e-world-sync"
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
            "DEV_TOKEN": "world-sync-token",
            "MATCH_ID": "world_sync_match",
            "DEADLINE_SEC": "40",
        },
        out / "server.log",
    )
    if not _wait_file(ready, 10.0):
        emit("FAIL", "server ready missing")
        _terminate(server)
        return 1

    clients: list[subprocess.Popen] = []
    ## A 移动后主动 Leave；B 等待 peer_left / snapshot 清理。
    for name, result, move_x, wait_peer_left in (
        ("A", client_a, "1.0", "0"),
        ("B", client_b, "-1.0", "1"),
    ):
        clients.append(
            _spawn(
                godot,
                CLIENT_SCRIPT,
                {
                    "RESULT_FILE": str(result),
                    "GAME_HOST": "127.0.0.1",
                    "GAME_PORT": str(PORT),
                    "DISPLAY_NAME": f"world-{name}",
                    "DEV_TOKEN": "world-sync-token",
                    "CLAIMED_MATCH_ID": "world_sync_match",
                    "MOVE_X": move_x,
                    "MOVE_Y": "0.0",
                    "EXPECT_REMOTE": "1",
                    "WAIT_PEER_LEFT": wait_peer_left,
                    "LEAVE_AFTER_MOVE": "1" if name == "A" else "0",
                    "DEADLINE_SEC": "30",
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
        emit("FAIL", "timeout waiting client results")
        emit("INFO", f"A={ra} B={rb}")
        return 1

    checks = [
        (ra.get("STATUS") == "CLIENT_OK", "client A OK"),
        (rb.get("STATUS") == "CLIENT_OK", "client B OK"),
        (ra.get("SEAT") != rb.get("SEAT"), "distinct seats"),
        (ra.get("SAW_REMOTE") == "1", "A saw remote"),
        (rb.get("SAW_REMOTE") == "1", "B saw remote"),
        (ra.get("REMOTE_MOVED") == "1", "A saw B move"),
        (rb.get("REMOTE_MOVED") == "1", "B saw A move"),
        (rb.get("PEER_LEFT") == "1", "B saw A leave"),
        (int(ra.get("PLAYER_COUNT_PEAK", "0")) >= 2, "A peak players >= 2"),
        (int(rb.get("PLAYER_COUNT_PEAK", "0")) >= 2, "B peak players >= 2"),
    ]
    failed = [label for cond, label in checks if not cond]
    if failed:
        emit("FAIL", f"world sync checks failed: {failed}")
        emit("INFO", f"A={ra}")
        emit("INFO", f"B={rb}")
        return 1

    emit("PASS", "WORLD_SYNC_E2E_OK")
    print("WORLD_SYNC_E2E_OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
