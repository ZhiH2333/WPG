#!/usr/bin/env python3
"""P2P Direct ENet E2E（Phase 9.2.3）：真双进程 + 真 UDP + 真 ENet + Protocol 6 Handshake。

流程：
    1. Host 进程：创建房间，监听 ENet，启动 rendezvous client，等待 Guest。
    2. Guest 进程：解析 P2P invite，连接 rendezvous，UDP hole punch，validated path，
       发起 Direct ENet 连接，跑通 protocol 6 ticket handshake，拿到 seat_assigned。
    3. 校验 Guest 最终进入 LOBBY 状态，Host 侧 peer_confirmed。

**不允许** 伪造 ENet 连接：两个进程里的建连、握手、座位分配全部由真实 LobbyNet 执行。

通过输出 P2P_DIRECT_ENET_E2E_OK；失败输出 P2P_DIRECT_ENET_E2E_FAIL 并返回非 0。

技术边界说明：
- 当前验证证明 validated P2P path 后可以进入 LobbyNet ENet + protocol 6 handshake
- 不等于已经证明所有公网 NAT 类型都能通过同一 NAT mapping 建立 ENet
- TURN/Relay/对称 NAT 留后续阶段
"""

from __future__ import annotations

import argparse
import secrets
import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from wpg_common import LOG_DIR, ROOT, emit, find_godot, godot_log_args  # noqa: E402

E2E_DIR = Path(__file__).resolve().parent
HOST_SCRIPT = str(E2E_DIR / "host.gd")
GUEST_SCRIPT = str(E2E_DIR / "guest.gd")

BOOT_TIMEOUT_SEC = 60.0
PEER_TIMEOUT_SEC = 60.0


def _out_dir() -> Path:
    path = LOG_DIR / "e2e" / "p2p_direct_enet"
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


def _free_port() -> int:
    import socket
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.bind(("127.0.0.1", 0))
    port = sock.getsockname()[1]
    sock.close()
    return port


def main() -> int:
    parser = argparse.ArgumentParser(description="WPG P2P Direct ENet E2E")
    parser.add_argument("--host-port", type=int, default=0, help="Host ENet listen port (0 = auto)")
    parser.add_argument("--guest-port", type=int, default=0, help="Guest ENet bind port (0 = auto)")
    parser.add_argument("--rendezvous-port", type=int, default=0, help="Rendezvous server port (0 = auto)")
    args = parser.parse_args()

    godot = find_godot()
    if godot is None:
        emit("FAIL", "找不到 Godot 可执行文件")
        return 1

    out = _out_dir()
    host_result = out / "host.result"
    guest_result = out / "guest.result"
    host_ready = Path(str(host_result) + ".ready")
    guest_ready = Path(str(guest_result) + ".ready")
    go_file = out / "go"
    host_log = out / "host.log"
    guest_log = out / "guest.log"
    rendezvous_log = out / "rendezvous.log"
    for path in (host_result, guest_result, host_ready, guest_ready, go_file):
        path.unlink(missing_ok=True)

    # 启动 rendezvous 服务端
    rendezvous_port = args.rendezvous_port if args.rendezvous_port > 0 else _free_port()
    rendezvous_script = str(ROOT / "tools" / "p2p" / "rendezvous" / "server.py")
    rendezvous_proc = subprocess.Popen(
        [sys.executable, rendezvous_script, "--port", str(rendezvous_port)],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
    # 等待服务端真正 ready（监听到端口输出），而非固定 sleep
    _wait_rendezvous_ready(rendezvous_proc, rendezvous_port, BOOT_TIMEOUT_SEC)

    host_enet_port = args.host_port if args.host_port > 0 else _free_port()
    guest_enet_port = args.guest_port if args.guest_port > 0 else _free_port()
    session_id = secrets.token_hex(8)
    host_nonce = secrets.token_hex(16)
    guest_nonce = secrets.token_hex(16)
    room_id = secrets.token_hex(4)
    ticket = secrets.token_hex(16)

    emit("INFO", "direct enet E2E: host_enet=%d guest_enet=%d rendezvous=%d session=%s room=%s" % (
        host_enet_port, guest_enet_port, rendezvous_port, session_id, room_id))

    # 启动 Host 进程
    host = subprocess.Popen(
        _peer_cmd(godot, HOST_SCRIPT, [
            host_enet_port, rendezvous_port, session_id, host_nonce, guest_nonce,
            room_id, ticket, host_result, host_ready, go_file
        ], host_log),
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
    guest = None
    try:
        if not _wait_file(host_ready, host, BOOT_TIMEOUT_SEC):
            emit("FAIL", "Host 未就绪（见 %s）" % host_log)
            return 1

        # 启动 Guest 进程
        guest = subprocess.Popen(
            _peer_cmd(godot, GUEST_SCRIPT, [
                guest_enet_port, rendezvous_port, session_id, guest_nonce, host_nonce,
                room_id, ticket, guest_result, guest_ready, go_file
            ], guest_log),
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
        )
        if not _wait_file(guest_ready, guest, BOOT_TIMEOUT_SEC):
            emit("FAIL", "Guest 未就绪（见 %s）" % guest_log)
            return 1

        time.sleep(0.5)

        # 双方同时开始 tick
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
        for proc in (guest, host, rendezvous_proc):
            if proc is not None and proc.poll() is None:
                proc.kill()
        rendezvous_proc.wait(timeout=5)

    host_text = _read(host_result)
    guest_text = _read(guest_result)

    problems = []
    if not host_text.startswith("OK"):
        problems.append("Host: %s" % (host_text or host_out.strip()[-400:] or "无结果"))
    if not guest_text.startswith("OK"):
        problems.append("Guest: %s" % (guest_text or guest_out.strip()[-400:] or "无结果"))

    # Guest 必须拿到 seat_assigned 并进入 LOBBY
    if guest_text.startswith("OK"):
        if "seat=" not in guest_text:
            problems.append("Guest: 未收到 seat_assigned")
        if "state=LOBBY" not in guest_text:
            problems.append("Guest: 未进入 LOBBY 状态：%s" % guest_text)
    # Host 必须收到 peer_confirmed
    if host_text.startswith("OK"):
        if "peer_confirmed" not in host_text:
            problems.append("Host: 未收到 peer_confirmed")

    if problems:
        for problem in problems:
            emit("FAIL", problem)
        print("P2P_DIRECT_ENET_E2E_FAIL", flush=True)
        return 1

    emit("PASS", "Host/Guest 用真实 P2P + Direct ENet + Protocol 6 完成连接")
    emit("PASS", "Host  %s" % host_text)
    emit("PASS", "Guest %s" % guest_text)
    print("P2P_DIRECT_ENET_E2E_OK", flush=True)
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


def _wait_rendezvous_ready(proc: subprocess.Popen, port: int, timeout_sec: float) -> bool:
    """等待 rendezvous 服务端真正开始监听（通过检查端口占用或日志输出）。"""
    import socket
    deadline = time.time() + timeout_sec
    while time.time() < deadline:
        # 尝试连接 UDP 端口（发空包测试是否有人在听）
        try:
            sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            sock.settimeout(0.2)
            sock.sendto(b"\x00", ("127.0.0.1", port))
            sock.close()
        except OSError:
            pass
        # 检查进程是否还活着
        if proc.poll() is not None:
            return False
        # 简单检查：端口是否可 bind（如果不可 bind 说明有人在听）
        try:
            test_sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            test_sock.bind(("127.0.0.1", port))
            test_sock.close()
            # 如果能 bind 说明没人占用，继续等
        except OSError:
            # 端口被占用 = 服务端已经在听
            return True
        time.sleep(0.05)
    return False


if __name__ == "__main__":
    sys.exit(main())