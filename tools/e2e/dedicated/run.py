#!/usr/bin/env python3
"""Dedicated Server E2E（Phase 2A）。

用例：
  1) 1 个 headless DS + 2 个客户端：准入、权威快照、输入驱动位移
  2) 第 5 个客户端被 FULL 拒绝（Online 上限 4；前 4 个保持在线）

用法：python3 tools/e2e/dedicated/run.py
通过输出 DEDICATED_E2E_OK。
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
PORT = 24667
TIMEOUT_SEC = 45.0


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


def _run_two_clients(godot: Path, out: Path) -> bool:
    ready = out / "server.ready"
    server_result = out / "server.result"
    client_results = [out / "client_a.result", out / "client_b.result"]
    for path in [ready, server_result, *client_results]:
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
            "DEV_TOKEN": "e2e-token",
            "DEADLINE_SEC": "25",
        },
        out / "server.log",
    )
    if not _wait_file(ready, 10.0):
        emit("FAIL", "server ready file missing")
        _terminate(server)
        return False

    clients: list[subprocess.Popen] = []
    for idx, result in enumerate(client_results):
        clients.append(
            _spawn(
                godot,
                CLIENT_SCRIPT,
                {
                    "RESULT_FILE": str(result),
                    "GAME_HOST": "127.0.0.1",
                    "GAME_PORT": str(PORT),
                    "DISPLAY_NAME": "client_%s" % ("ab"[idx]),
                    "DEV_TOKEN": "e2e-token",
                    "DEADLINE_SEC": "20",
                },
                out / ("client_%s.log" % ("ab"[idx])),
            )
        )

    deadline = time.time() + TIMEOUT_SEC
    while time.time() < deadline:
        if all(path.is_file() for path in [server_result, *client_results]):
            break
        if server.poll() is not None and not server_result.is_file():
            break
        time.sleep(0.1)

    server_data = _parse_result(server_result)
    client_data = [_parse_result(path) for path in client_results]
    ok = (
        server_data.get("STATUS") == "SERVER_OK"
        and server_data.get("AUTHORITATIVE") == "1"
        and int(server_data.get("PEAK_OCCUPIED", server_data.get("OCCUPIED", "0"))) >= 2
        and all(data.get("STATUS") == "CLIENT_OK" for data in client_data)
        and all(int(data.get("MOVED", "0")) == 1 for data in client_data)
        and {int(data.get("SEAT", "0")) for data in client_data} == {1, 2}
    )
    if not ok:
        emit("FAIL", "two-client DS path failed")
        print("  server:", server_data)
        print("  clients:", client_data)
    else:
        emit("PASS", "2 clients admitted; server-authoritative movement replicated")

    for proc in clients:
        _terminate(proc)
    _terminate(server)
    return ok


def _run_fifth_rejected(godot: Path, out: Path) -> bool:
    """线上准入满员拒绝：用 max_players=4 占满后再连第 5 个。

    为降低本机同时开 6 个 Godot 的不稳定，占座客户端 HOLD；溢出客户端只验证 FULL。
    """
    ready = out / "full.ready"
    server_result = out / "full_server.result"
    release = out / "full_release"
    admit_files = [out / ("full_admit_%d.txt" % i) for i in range(4)]
    hold_results = [out / ("full_hold_%d.result" % i) for i in range(4)]
    fifth_result = out / "full_fifth.result"
    for path in [ready, server_result, release, fifth_result, *admit_files, *hold_results]:
        path.unlink(missing_ok=True)

    server = _spawn(
        godot,
        SERVER_SCRIPT,
        {
            "RESULT_FILE": str(server_result),
            "READY_FILE": str(ready),
            "RELEASE_FILE": str(release),
            "STAY_UP": "1",
            "GAME_PORT": str(PORT + 1),
            "MAX_PLAYERS": "4",
            "EXPECT_PLAYERS": "4",
            "DEV_TOKEN": "e2e-token",
            "DEADLINE_SEC": "40",
        },
        out / "full_server.log",
    )
    if not _wait_file(ready, 10.0):
        emit("FAIL", "full-case server ready missing")
        _terminate(server)
        return False

    holders: list[subprocess.Popen] = []
    for i in range(4):
        holders.append(
            _spawn(
                godot,
                CLIENT_SCRIPT,
                {
                    "RESULT_FILE": str(hold_results[i]),
                    "ADMIT_FILE": str(admit_files[i]),
                    "HOLD_AFTER_ADMIT": "1",
                    "HOLD_RELEASE_FILE": str(release),
                    "GAME_HOST": "127.0.0.1",
                    "GAME_PORT": str(PORT + 1),
                    "DISPLAY_NAME": "hold%d" % i,
                    "DEV_TOKEN": "e2e-token",
                    "DEADLINE_SEC": "35",
                },
                out / ("full_hold_%d.log" % i),
            )
        )
        time.sleep(0.25)

    if not all(_wait_file(path, 20.0) for path in admit_files):
        emit("FAIL", "failed to seat 4 holding clients")
        print("  admits:", [path.is_file() for path in admit_files])
        release.write_text("go\n", encoding="utf-8")
        for proc in holders:
            _terminate(proc)
        _terminate(server)
        return False

    ## 占座稳定后再挤第 5 个，避免握手风暴。
    time.sleep(0.5)
    fifth = _spawn(
        godot,
        CLIENT_SCRIPT,
        {
            "RESULT_FILE": str(fifth_result),
            "GAME_HOST": "127.0.0.1",
            "GAME_PORT": str(PORT + 1),
            "DISPLAY_NAME": "overflow",
            "DEV_TOKEN": "e2e-token",
            "DEADLINE_SEC": "15",
        },
        out / "full_fifth.log",
    )
    if not _wait_file(fifth_result, 15.0):
        emit("FAIL", "fifth client produced no result")
        release.write_text("go\n", encoding="utf-8")
        for proc in holders:
            _terminate(proc)
        _terminate(fifth)
        _terminate(server)
        return False

    fifth_data = _parse_result(fifth_result)
    full_ok = (
        fifth_data.get("STATUS") == "CLIENT_REJECTED"
        and int(fifth_data.get("REJECT_REASON", "-1")) == 3
    )
    release.write_text("go\n", encoding="utf-8")
    deadline = time.time() + 10.0
    while time.time() < deadline and not all(path.is_file() for path in hold_results):
        time.sleep(0.1)

    if not full_ok:
        emit("FAIL", "fifth client was not rejected with FULL")
        print("  fifth:", fifth_data)
    else:
        emit("PASS", "Online admission rejects 5th player (FULL)")

    for proc in holders:
        _terminate(proc)
    _terminate(fifth)
    _terminate(server)
    return full_ok


def main() -> int:
    godot = find_godot()
    if godot is None:
        emit("FAIL", "找不到 Godot 可执行文件")
        print("DEDICATED_E2E_FAIL")
        return 1

    out = LOG_DIR / "e2e" / "dedicated"
    out.mkdir(parents=True, exist_ok=True)

    two_ok = _run_two_clients(godot, out)
    fifth_ok = _run_fifth_rejected(godot, out)
    if two_ok and fifth_ok:
        print("DEDICATED_E2E_OK")
        return 0
    print("DEDICATED_E2E_FAIL")
    return 1


if __name__ == "__main__":
    sys.exit(main())
