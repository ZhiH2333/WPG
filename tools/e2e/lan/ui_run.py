#!/usr/bin/env python3
"""LAN Start UI 换场 E2E：真双进程 + 真 ENet + 真 MainMenu/LanOverlay -> CombatSandbox。

与 tests/lan_e2e_test.gd 的分工：
  那个 E2E 只驱动 LobbyManager，断言到 Room.room_state == STARTING 为止，
  所以它在「bind_lobby 漏连 match_started」这个 bug 存在时**依然通过**。
  这里补上缺失的一环：两个真进程各自加载 ui/main_menu.tscn，
  Host 真实按 START、Guest 真实按 READY，最后只认 current_scene 变成 CombatSandbox。

用法：python3 tools/e2e/lan/ui_run.py
通过输出 LAN_START_UI_OK；失败输出 LAN_START_UI_FAIL 并返回非 0。
"""

from __future__ import annotations

import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from wpg_common import LOG_DIR, ROOT, emit, find_godot, godot_log_args  # noqa: E402

E2E_DIR = Path(__file__).resolve().parent
HOST_SCRIPT = str(E2E_DIR / "ui_host.gd")
GUEST_SCRIPT = str(E2E_DIR / "ui_guest.gd")
BOOT_TIMEOUT_SEC = 25.0
PEER_TIMEOUT_SEC = 60.0


def _out_dir() -> Path:
    path = LOG_DIR / "e2e" / "lan_start_ui"
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
        return 1

    out = _out_dir()
    host_result = out / "host.result"
    guest_result = out / "guest.result"
    host_ready = Path(str(host_result) + ".ready")
    ## 协议 6：Host 还会写 invite（含 ticket），Guest 必须读到它才能进房。
    host_invite = Path(str(host_result) + ".invite")
    for path in (host_result, guest_result, host_ready, host_invite):
        path.unlink(missing_ok=True)

    host_log = out / "host.log"
    guest_log = out / "guest.log"

    host = subprocess.Popen(
        _peer_cmd(godot, HOST_SCRIPT, host_result, host_log),
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
    try:
        ## 等 Host 写出 .ready（监听已建立）再起 Guest，避免抢跑连不上。
        deadline = time.time() + BOOT_TIMEOUT_SEC
        while time.time() < deadline:
            if host_ready.is_file():
                break
            if host.poll() is not None:
                break
            time.sleep(0.1)
        if not host_ready.is_file():
            host_output = host.communicate(timeout=10)[0] or ""
            emit("FAIL", "Host 未进入监听：%s" % host_output.strip()[-400:])
            return 1

        guest = subprocess.Popen(
            _peer_cmd(godot, GUEST_SCRIPT, guest_result, guest_log),
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
            return 1
        try:
            host_output = host.communicate(timeout=PEER_TIMEOUT_SEC)[0] or ""
        except subprocess.TimeoutExpired:
            host.kill()
            host_output = host.communicate()[0] or ""
            emit("FAIL", "Host 进程超时")
            return 1
    finally:
        for proc in (host,):
            if proc.poll() is None:
                proc.kill()

    host_text = _read(host_result)
    guest_text = _read(guest_result)

    problems = []
    if host_text != "OK":
        problems.append("Host: %s" % (host_text or host_output.strip()[-400:] or "无结果"))
    if guest_text != "OK":
        problems.append("Guest: %s" % (guest_text or guest_output.strip()[-400:] or "无结果"))

    if problems:
        for problem in problems:
            emit("FAIL", problem)
        print("LAN_START_UI_FAIL")
        return 1

    emit("PASS", "Host Create Room -> Guest Join/READY -> Host START -> 双方 CombatSandbox")
    print("LAN_START_UI_OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
