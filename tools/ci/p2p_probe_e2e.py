#!/usr/bin/env python3
"""P2P Hole Punch E2E（Phase 9.2.2 R2）：真双进程 + 真 UDP + **真 P2PHolePunch**。

流程：
    1. Host 进程：创建 production P2PHolePunch，绑定固定端口，发一轮 probe。
    2. 注入 stale ACK（错误 source）+ Guest 进程从自己的真实 socket 注入 probe_id 不匹配的 ACK。
    3. 双方同时 tick，用真实 probe encode/decode/path establishment 完成双向打洞。
    4. 校验 validated endpoint / probe target / source matching / probe_id correlation。

**不允许** 用 PacketPeerUDP 手写 probe/ACK 协议冒充 P2PHolePunch：
两个进程里的探测、解码、路径确认全部由 `lobby/p2p_hole_punch.gd` 执行。

通过输出 P2P_HOLE_PUNCH_E2E_OK；失败输出 P2P_HOLE_PUNCH_E2E_FAIL 并返回非 0。
"""

from __future__ import annotations

import argparse
import secrets
import socket
import struct
import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from wpg_common import LOG_DIR, ROOT, emit, find_godot, godot_log_args  # noqa: E402

HOST_SCRIPT = "tools/ci/p2p_probe_host.gd"
GUEST_SCRIPT = "tools/ci/p2p_probe_guest.gd"

BOOT_TIMEOUT_SEC = 30.0
PEER_TIMEOUT_SEC = 30.0

# 与 lobby/p2p_udp_probe.gd 完全一致的 wire format（仅用于注入 stale ACK 做负向测试）。
PROBE_MAGIC = 0x50505242
PROBE_VERSION = 2
MSG_ACK = 1
ROLE_HOST = 0
ROLE_GUEST = 1


def _out_dir() -> Path:
    path = LOG_DIR / "p2p_probe_e2e"
    path.mkdir(parents=True, exist_ok=True)
    return path


def _peer_cmd(godot: Path, script: str, args: list, log: Path) -> list:
    return [
        str(godot),
        "--headless",
        "--path",
        str(ROOT),
        *godot_log_args(log),
        "--script",
        script,
        "--",
        *[str(a) for a in args],
    ]


def _read(path: Path) -> str:
    try:
        return path.read_text().strip()
    except OSError:
        return ""


def _put_string(buf: bytearray, value: str) -> None:
    data = value.encode("utf-8")
    buf += struct.pack(">I", len(data))
    buf += data


def encode_ack(session_id: str, nonce: str, role: int, timestamp_ms: int, original_ms: int, probe_id: int) -> bytes:
    buf = bytearray()
    buf += struct.pack(">I", PROBE_MAGIC)
    buf += struct.pack(">B", PROBE_VERSION)
    buf += struct.pack(">B", MSG_ACK)
    _put_string(buf, session_id)
    _put_string(buf, nonce)
    buf += struct.pack(">B", role)
    buf += struct.pack(">Q", timestamp_ms)
    buf += struct.pack(">Q", original_ms)
    buf += struct.pack(">I", probe_id)
    return bytes(buf)


def _free_port() -> int:
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.bind(("127.0.0.1", 0))
    port = sock.getsockname()[1]
    sock.close()
    return port


def main() -> int:
    parser = argparse.ArgumentParser(description="WPG P2P Hole Punch E2E")
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
    host_bound = Path(str(host_result) + ".bound")
    guest_bound = Path(str(guest_result) + ".bound")
    go_file = out / "go"
    host_log = LOG_DIR / "p2p-punch-host.log"
    guest_log = LOG_DIR / "p2p-punch-guest.log"
    for path in (host_result, guest_result, host_bound, guest_bound, go_file):
        path.unlink(missing_ok=True)

    host_port = args.host_port if args.host_port > 0 else _free_port()
    guest_port = args.guest_port if args.guest_port > 0 else _free_port()
    session_id = secrets.token_hex(8)
    host_nonce = secrets.token_hex(16)
    guest_nonce = secrets.token_hex(16)

    emit("INFO", "hole punch E2E: host_port=%d guest_port=%d session=%s" % (host_port, guest_port, session_id))

    host = subprocess.Popen(
        _peer_cmd(godot, HOST_SCRIPT, [host_port, guest_port, session_id, host_nonce, guest_nonce, "host", host_result, go_file], host_log),
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
    guest = None
    try:
        if not _wait_file(host_bound, host, BOOT_TIMEOUT_SEC):
            emit("FAIL", "Host 未绑定端口（见 %s）" % host_log)
            return 1

        # 负向测试 1：错误 source 的 stale ACK（probe_id 也不匹配）。
        stale = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        stale.bind(("127.0.0.1", 0))
        stale.sendto(
            encode_ack(session_id, guest_nonce, ROLE_GUEST, int(time.time() * 1000), int(time.time() * 1000), 0x7FFFFFF0),
            ("127.0.0.1", host_port),
        )
        stale.close()
        emit("INFO", "已注入错误 source 的 stale ACK")

        guest = subprocess.Popen(
            _peer_cmd(godot, GUEST_SCRIPT, [guest_port, host_port, session_id, guest_nonce, host_nonce, "guest", guest_result, go_file, "stale"], guest_log),
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
        )
        if not _wait_file(guest_bound, guest, BOOT_TIMEOUT_SEC):
            emit("FAIL", "Guest 未绑定端口（见 %s）" % guest_log)
            return 1
        # Guest 已从自己的真实 socket 注入了 probe_id 不匹配的 stale ACK。
        time.sleep(0.3)

        # 双方同时开始 tick。
        go_file.write_text("go")

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
    finally:
        for proc in (guest, host):
            if proc is not None and proc.poll() is None:
                proc.kill()

    host_text = _read(host_result)
    guest_text = _read(guest_result)

    problems = []
    if not host_text.startswith("OK"):
        problems.append("Host: %s" % (host_text or host_out.strip()[-400:] or "无结果"))
    if not guest_text.startswith("OK"):
        problems.append("Guest: %s" % (guest_text or guest_out.strip()[-400:] or "无结果"))

    # 两侧都必须真的完成双向打洞，并且 validated endpoint = 对端真实绑定端口。
    if host_text.startswith("OK") and "validated=127.0.0.1:%d" % guest_port not in host_text:
        problems.append("Host: validated endpoint 不是 Guest 的真实端口：%s" % host_text)
    if guest_text.startswith("OK") and "validated=127.0.0.1:%d" % host_port not in guest_text:
        problems.append("Guest: validated endpoint 不是 Host 的真实端口：%s" % guest_text)
    # target 必须等于 validated（打洞目标来自 observed，且就是最终验证的端点）。
    if host_text.startswith("OK") and host_text.count("target=127.0.0.1:%d" % guest_port) != 1:
        problems.append("Host: probe target 与 validated 不一致：%s" % host_text)
    if guest_text.startswith("OK") and guest_text.count("target=127.0.0.1:%d" % host_port) != 1:
        problems.append("Guest: probe target 与 validated 不一致：%s" % guest_text)
    # 两个进程各自拥有自己的 socket（E2E 中不是 shared 模式）。
    if host_text.startswith("OK") and "owns=1" not in host_text:
        problems.append("Host: 未报告 owns=1")
    if guest_text.startswith("OK") and "owns=1" not in guest_text:
        problems.append("Guest: 未报告 owns=1")
    # stale ACK 不得让 Host 用错误 source 建立路径。
    if "10.255.255" in host_text or "10.255.255" in guest_text:
        problems.append("打洞目标错误地使用了 advertised 私网地址（应为 observed）")

    if problems:
        for problem in problems:
            emit("FAIL", problem)
        print("P2P_HOLE_PUNCH_E2E_FAIL", flush=True)
        return 1

    emit("PASS", "Host/Guest 用真实 P2PHolePunch 完成双向打洞")
    emit("PASS", "Host  %s" % host_text)
    emit("PASS", "Guest %s" % guest_text)
    print("P2P_HOLE_PUNCH_E2E_OK", flush=True)
    return 0


def _wait_file(path: Path, proc: subprocess.Popen, timeout_sec: float) -> bool:
    deadline = time.time() + timeout_sec
    while time.time() < deadline:
        if path.is_file():
            return True
        if proc.poll() is not None:
            return False
        time.sleep(0.05)
    return path.is_file()


if __name__ == "__main__":
    sys.exit(main())
