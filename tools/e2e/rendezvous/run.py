#!/usr/bin/env python3
"""Rendezvous E2E（Phase 9.2.1）：真服务端 + 真双进程 + 真 UDP。

流程：
    启动 rendezvous server（本机随机端口）
    Host 进程  -> REGISTER(role=host)
    Guest 进程 -> REGISTER(role=guest)
    server     -> 配对，把双方候选 + observed endpoint 交换出去
    Host       -> 收到 guest candidate
    Guest      -> 收到 host candidate

通过输出 RENDEZVOUS_E2E_OK；失败输出 RENDEZVOUS_E2E_FAIL 并返回非 0。

**注意**：本阶段不要求两个 Godot 进程通过 NAT 直连成功 ——
只证明「公网 rendezvous 可以真实把双方连接信息交换出去」。

不需要公网：server 跑在 127.0.0.1，观测到的端点就是本机回环端点。
若需要验证公网 STUN，用 --stun-probe；沙箱内失败时明确标记
PUBLIC_STUN_E2E_SKIPPED，绝不伪造结果。
"""

from __future__ import annotations

import argparse
import secrets
import socket
import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from wpg_common import LOG_DIR, ROOT, emit, find_godot, godot_log_args  # noqa: E402

E2E_DIR = Path(__file__).resolve().parent
RENDEZVOUS_DIR = ROOT / "tools" / "p2p" / "rendezvous"
HOST_SCRIPT = str(E2E_DIR / "host.gd")
GUEST_SCRIPT = str(E2E_DIR / "guest.gd")
SERVER_SCRIPT = "tools/p2p/rendezvous/server.py"

BOOT_TIMEOUT_SEC = 20.0
PEER_TIMEOUT_SEC = 40.0


def _free_port() -> int:
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.bind(("127.0.0.1", 0))
    port = sock.getsockname()[1]
    sock.close()
    return port


def _out_dir() -> Path:
    path = LOG_DIR / "e2e" / "rendezvous"
    path.mkdir(parents=True, exist_ok=True)
    return path


def _peer_cmd(godot: Path, script: str, port: int, room: str, ticket: str, result: Path, log: Path) -> list:
    return [
        str(godot),
        "--headless",
        "--path",
        str(ROOT),
        *godot_log_args(log),
        "--script",
        script,
        "--",
        str(port),
        room,
        ticket,
        str(result),
    ]


def _read(path: Path) -> str:
    try:
        return path.read_text().strip()
    except OSError:
        return ""


def _stun_probe() -> int:
    """尝试公网 STUN；失败明确标记 SKIPPED，不伪造。"""
    sys.path.insert(0, str(RENDEZVOUS_DIR))
    try:
        import stun  # noqa: WPS433
    except Exception as exc:  # noqa: BLE001
        emit("INFO", "STUN 模块不可用：%s" % exc)
        return 1
    result = stun.query_first(stun.DEFAULT_STUN_SERVERS, timeout_sec=1.5)
    if result is None or not result.is_usable():
        print("PUBLIC_STUN_E2E_SKIPPED（无法访问公网 STUN，未伪造结果）", flush=True)
        return 1
    emit("PASS", "公网 STUN observed endpoint = %s:%d" % (result.address, result.port))
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="WPG rendezvous E2E")
    parser.add_argument("--stun-probe", action="store_true", help="额外尝试一次公网 STUN")
    args = parser.parse_args()

    godot = find_godot()
    if godot is None:
        emit("FAIL", "找不到 Godot 可执行文件")
        return 1

    out = _out_dir()
    host_result = out / "host.result"
    guest_result = out / "guest.result"
    host_ready = Path(str(host_result) + ".ready")
    server_log = out / "server.log"
    for path in (host_result, guest_result, host_ready, server_log):
        path.unlink(missing_ok=True)

    port = _free_port()
    room = secrets.token_hex(4)
    ticket = secrets.token_hex(16)
    # 日志 / 输出里绝不带完整 ticket。
    emit("INFO", "rendezvous port=%d room=%s ticket=<redacted>" % (port, room))

    server = subprocess.Popen(
        [sys.executable, str(SERVER_SCRIPT), "--port", str(port)],
        stdout=server_log.open("w"),
        stderr=subprocess.STDOUT,
    )
    host = None
    guest = None
    try:
        # 等服务端真的 bind 上。
        deadline = time.time() + BOOT_TIMEOUT_SEC
        bound = False
        while time.time() < deadline:
            if server.poll() is not None:
                break
            probe = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            try:
                # UDP 无连接：能 sendto 不代表 bind 成功；改看日志里那句 listening。
                if server_log.exists() and "listening on" in server_log.read_text(errors="replace"):
                    bound = True
                    break
            finally:
                probe.close()
            time.sleep(0.1)
        if not bound:
            emit("FAIL", "rendezvous server 未进入监听（见 %s）" % server_log)
            return 1

        host_log = out / "host.log"
        host = subprocess.Popen(
            _peer_cmd(godot, HOST_SCRIPT, port, room, ticket, host_result, host_log),
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
        )
        # 等 Host 发出 REGISTER，再起 Guest，避免 Guest 先到 -> SESSION_NOT_FOUND。
        deadline = time.time() + BOOT_TIMEOUT_SEC
        while time.time() < deadline:
            if host_ready.is_file():
                break
            if host.poll() is not None:
                break
            time.sleep(0.1)
        if not host_ready.is_file():
            host_out = host.communicate(timeout=10)[0] or ""
            emit("FAIL", "Host 未完成注册：%s" % host_out.strip()[-400:])
            return 1

        guest_log = out / "guest.log"
        guest = subprocess.Popen(
            _peer_cmd(godot, GUEST_SCRIPT, port, room, ticket, guest_result, guest_log),
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
    finally:
        for proc in (guest, host, server):
            if proc is not None and proc.poll() is None:
                proc.kill()

    host_text = _read(host_result)
    guest_text = _read(guest_result)

    problems = []
    if not host_text.startswith("OK"):
        problems.append("Host: %s" % (host_text or host_out.strip()[-400:] or "无结果"))
    if not guest_text.startswith("OK"):
        problems.append("Guest: %s" % (guest_text or guest_out.strip()[-400:] or "无结果"))
    # 双方都必须真的拿到 observed endpoint。
    if host_text.startswith("OK") and "observed=" not in host_text:
        problems.append("Host: 结果里没有 observed endpoint")
    if guest_text.startswith("OK") and "observed=" not in guest_text:
        problems.append("Guest: 结果里没有 observed endpoint")

    if problems:
        for problem in problems:
            emit("FAIL", problem)
        print("RENDEZVOUS_E2E_FAIL", flush=True)
        return 1

    emit("PASS", "Host/Guest REGISTER -> 配对 -> 双方收到 candidates + observed endpoint")
    emit("PASS", "Host  %s" % host_text)
    emit("PASS", "Guest %s" % guest_text)
    print("RENDEZVOUS_E2E_OK", flush=True)

    if args.stun_probe:
        _stun_probe()
    return 0


if __name__ == "__main__":
    sys.exit(main())
