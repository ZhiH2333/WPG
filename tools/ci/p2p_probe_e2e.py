#!/usr/bin/env python3
"""P2P UDP Probe E2E（Phase 9.2）：真双进程 + 真 UDP。

流程：
    启动 Host 进程 -> bind UDP, 发送 probe
    启动 Guest 进程 -> bind UDP, 接收 probe, 回复 ACK
    Host 接收 ACK -> 双向确认

通过输出 P2P_PROBE_E2E_OK；失败输出 P2P_PROBE_E2E_FAIL 并返回非 0。

**必须是真 UDP**。不要 monkeypatch 成 fake success。
"""

from __future__ import annotations

import argparse
import secrets
import socket
import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from wpg_common import LOG_DIR, ROOT, emit, find_godot, godot_log_args  # noqa: E402

HOST_SCRIPT = "tools/ci/p2p_probe_host.gd"
GUEST_SCRIPT = "tools/ci/p2p_probe_guest.gd"

BOOT_TIMEOUT_SEC = 15.0
PEER_TIMEOUT_SEC = 20.0


def _out_dir() -> Path:
    path = LOG_DIR / "p2p_probe_e2e"
    path.mkdir(parents=True, exist_ok=True)
    return path


def _peer_cmd(godot: Path, script: str, local_port: int, remote_port: int, session_id: str, local_nonce: str, remote_nonce: str, role: str, result: Path, log: Path) -> list:
    return [
        str(godot),
        "--headless",
        "--path",
        str(ROOT),
        *godot_log_args(log),
        "--script",
        script,
        "--",
        str(local_port),
        str(remote_port),
        session_id,
        local_nonce,
        remote_nonce,
        role,
        str(result),
    ]


def _read(path: Path) -> str:
    try:
        return path.read_text().strip()
    except OSError:
        return ""


def main() -> int:
    parser = argparse.ArgumentParser(description="WPG P2P UDP Probe E2E")
    parser.add_argument("--host-port", type=int, default=0, help="Host bind port (0 = auto)")
    parser.add_argument("--guest-port", type=int, default=0, help="Guest bind port (0 = auto)")
    args = parser.parse_args()

    godot = find_godot()
    if godot is None:
        emit("FAIL", "找不到 Godot 可执行文件")
        return 1

    out = _out_dir()
    host_result = out / "host.result"
    guest_result = out / "guest.result"
    host_log = LOG_DIR / "p2p-probe-host.log"
    guest_log = LOG_DIR / "p2p-probe-guest.log"
    for path in (host_result, guest_result):
        path.unlink(missing_ok=True)

    # 使用固定端口避免端口交换问题
    host_port = args.host_port if args.host_port > 0 else 50000
    guest_port = args.guest_port if args.guest_port > 0 else 50001
    session_id = secrets.token_hex(8)  # 16 hex chars
    host_nonce = secrets.token_hex(16)  # Host 的 nonce，发在 probe 里
    guest_nonce = secrets.token_hex(16)  # Guest 的 nonce，发在 ack 里

    emit("INFO", "p2p probe E2E: host_port=%d guest_port=%d session=%s" % (host_port, guest_port, session_id))

    # 先起 Host（bind 端口）
    host = subprocess.Popen(
        _peer_cmd(godot, HOST_SCRIPT, host_port, guest_port, session_id, host_nonce, guest_nonce, "host", host_result, host_log),
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
    # 等 Host 真正 bind 好（通过日志判断）
    deadline = time.time() + BOOT_TIMEOUT_SEC
    host_bound = False
    while time.time() < deadline:
        if host.poll() is not None:
            break
        if host_log.exists() and "bound on port" in host_log.read_text(errors="replace"):
            host_bound = True
            break
        time.sleep(0.1)
    if not host_bound:
        host_out = host.communicate(timeout=5)[0] or ""
        emit("FAIL", "Host 未 bind 成功：%s" % host_out.strip()[-400:])
        return 1
    
    # 等一小会儿确保 Host 准备好
    time.sleep(0.5)

    # 起 Guest
    guest = subprocess.Popen(
        _peer_cmd(godot, GUEST_SCRIPT, guest_port, host_port, session_id, guest_nonce, host_nonce, "guest", guest_result, guest_log),
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )

    try:
        guest_out = guest.communicate(timeout=PEER_TIMEOUT_SEC)[0] or ""
    except subprocess.TimeoutExpired:
        guest.kill()
        guest_out = guest.communicate()[0] or ""
        emit("FAIL", "Guest 进程超时")
        return 1

    try:
        host_out = host.communicate(timeout=PEER_TIMEOUT_SEC)[0] or ""
    except subprocess.TimeoutExpired:
        host.kill()
        host_out = host.communicate()[0] or ""
        emit("FAIL", "Host 进程超时")
        return 1

    host_text = _read(host_result)
    guest_text = _read(guest_result)

    problems = []
    if not host_text.startswith("OK"):
        problems.append("Host: %s" % (host_text or host_out.strip()[-400:] or "无结果"))
    if not guest_text.startswith("OK"):
        problems.append("Guest: %s" % (guest_text or guest_out.strip()[-400:] or "无结果"))

    # 双方都必须真的完成双向 probe
    if host_text.startswith("OK") and "bidirectional" not in host_text:
        problems.append("Host: 结果里没有 bidirectional 确认")
    if guest_text.startswith("OK") and "replied" not in guest_text:
        problems.append("Guest: 结果里没有回复确认")

    if problems:
        for problem in problems:
            emit("FAIL", problem)
        print("P2P_PROBE_E2E_FAIL", flush=True)
        return 1

    emit("PASS", "Host/Guest UDP probe 双向成功")
    emit("PASS", "Host  %s" % host_text)
    emit("PASS", "Guest %s" % guest_text)
    print("P2P_PROBE_E2E_OK", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())