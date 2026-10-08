#!/usr/bin/env python3
"""失败清理 / 重建 Lobby E2E：错误 ticket 被拒 -> Host 重建 -> 正确 Guest 进 Battle。

真双进程 + 真 ENet + 真 MainMenu/LanOverlay：
  Host   建房 -> 公布 invite
  Guest  篡改 ticket 去连 -> 必须被拒、必须清干净（无残留 peer）
  Host   收到拒绝 -> close_network -> 重新建房（新 invite）-> 仍在 hosting
  Guest  读新 invite -> 正确连接 -> seat 2 -> READY
  Host   START -> 双方 CombatSandbox -> 退回菜单无残留

用法：python3 tools/e2e/lobby_recovery/run.py
通过输出 LOBBY_RECOVERY_OK；失败输出 LOBBY_RECOVERY_FAIL 并返回非 0。
"""

from __future__ import annotations

import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from wpg_common import LOG_DIR, ROOT, emit, find_godot, godot_log_args  # noqa: E402

E2E_DIR = Path(__file__).resolve().parent
HOST_SCRIPT = str(E2E_DIR / "host.gd")
GUEST_SCRIPT = str(E2E_DIR / "guest.gd")
BOOT_TIMEOUT_SEC = 25.0
PEER_TIMEOUT_SEC = 90.0


def _out_dir() -> Path:
    path = LOG_DIR / "e2e" / "lobby_recovery"
    path.mkdir(parents=True, exist_ok=True)
    return path


def _peer_cmd(godot: Path, script: str, result: Path, log: Path) -> list:
    return [
        str(godot),
        "--headless",
        "--path",
        str(ROOT),
        *godot_log_args(log),
        "--script",
        script,
        "--",
        str(result),
    ]


def _read(path: Path) -> str:
    try:
        return path.read_text().strip()
    except OSError:
        return ""


def main() -> int:
    godot = find_godot()
    if godot is None:
        emit("FAIL", "找不到 Godot 可执行文件")
        print("LOBBY_RECOVERY_FAIL")
        return 1

    out = _out_dir()
    host_result = out / "host.result"
    guest_result = out / "guest.result"
    stale = [
        host_result,
        guest_result,
        Path(str(host_result) + ".ready"),
        Path(str(host_result) + ".invite"),
        Path(str(host_result) + ".invite2"),
        Path(str(host_result) + ".recreated"),
        Path(str(host_result) + ".battle"),
        Path(str(guest_result) + ".bad_done"),
        Path(str(guest_result) + ".battle"),
    ]
    for path in stale:
        path.unlink(missing_ok=True)

    host = subprocess.Popen(
        _peer_cmd(godot, HOST_SCRIPT, host_result, out / "host.log"),
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
    host_output = ""
    guest_output = ""
    try:
        deadline = time.time() + BOOT_TIMEOUT_SEC
        host_ready = Path(str(host_result) + ".ready")
        while time.time() < deadline:
            if host_ready.is_file():
                break
            if host.poll() is not None:
                break
            time.sleep(0.1)
        if not host_ready.is_file():
            host_output = host.communicate(timeout=10)[0] or ""
            emit("FAIL", "Host 未进入监听：%s" % host_output.strip()[-400:])
            print("LOBBY_RECOVERY_FAIL")
            return 1

        guest = subprocess.Popen(
            _peer_cmd(godot, GUEST_SCRIPT, guest_result, out / "guest.log"),
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
        )
        try:
            guest_output = guest.communicate(timeout=PEER_TIMEOUT_SEC)[0] or ""
        except subprocess.TimeoutExpired:
            guest.kill()
            guest_output = guest.communicate()[0] or ""
            emit("FAIL", "Guest 进程超时")
            print("LOBBY_RECOVERY_FAIL")
            return 1
        try:
            host_output = host.communicate(timeout=PEER_TIMEOUT_SEC)[0] or ""
        except subprocess.TimeoutExpired:
            host.kill()
            host_output = host.communicate()[0] or ""
            emit("FAIL", "Host 进程超时")
            print("LOBBY_RECOVERY_FAIL")
            return 1
    finally:
        if host.poll() is None:
            host.kill()

    host_text = _read(host_result)
    guest_text = _read(guest_result)

    problems = []
    if not (host_text.startswith("OK") and "rejected=1" in host_text and "recreated=1" in host_text):
        problems.append("Host: %s" % (host_text or host_output.strip()[-400:] or "无结果"))
    if not (guest_text.startswith("OK") and "failed_clean=1" in guest_text and "rejoined=1" in guest_text):
        problems.append("Guest: %s" % (guest_text or guest_output.strip()[-400:] or "无结果"))

    if problems:
        for problem in problems:
            emit("FAIL", problem)
        print("LOBBY_RECOVERY_FAIL")
        return 1

    emit("PASS", "错误 ticket 被拒 -> Host 重启房 -> Guest 重连 seat 2 -> 双方 Battle -> 清场")
    print("LOBBY_RECOVERY_OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
