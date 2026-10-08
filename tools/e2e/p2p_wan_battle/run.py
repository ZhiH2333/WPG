#!/usr/bin/env python3
"""WAN / P2P 完整闭环 E2E：真 rendezvous + 真 hole punch + 真 ENet + 真 UI -> Battle。

与 Phase 9.2.3（tools/p2p/e2e_direct_enet_test.py）的分工：
  9.2.3 只断言到 Guest seat=2 / CONNECTED（LobbyManager 直调，不实例化 UI）。
  这里在它基础上继续往后跑完整产品闭环：
    Host  MainMenu -> HOST OVER INTERNET（真 UI -> host_room + create_p2p_invite
                     + start_p2p_hosting）-> 公布真 invite
    Guest JOIN 页粘 invite -> LobbyManager.join_invite(raw)（唯一生产入口）
          -> rendezvous -> hole punch -> direct ENet -> protocol 6 -> seat=2
    Host  等 Guest READY -> START -> 双方 current_scene 变成 CombatSandbox
    双方  从 Battle 退回菜单 -> multiplayer_peer == null（无残留）

用法：python3 tools/e2e/p2p_wan_battle/run.py
通过输出 P2P_WAN_BATTLE_OK；失败输出 P2P_WAN_BATTLE_FAIL 并返回非 0。
"""

from __future__ import annotations

import os
import select
import socket
import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from wpg_common import LOG_DIR, ROOT, emit, find_godot, godot_log_args  # noqa: E402

E2E_DIR = Path(__file__).resolve().parent
HOST_SCRIPT = str(E2E_DIR / "host.gd")
GUEST_SCRIPT = str(E2E_DIR / "guest.gd")
RENDEZVOUS_SERVER = ROOT / "tools" / "p2p" / "rendezvous" / "server.py"

RV_READY_TIMEOUT_SEC = 15.0
BOOT_TIMEOUT_SEC = 30.0
PEER_TIMEOUT_SEC = 90.0
RESULT_TIMEOUT_SEC = 90.0


def _free_udp_port() -> int:
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.bind(("127.0.0.1", 0))
    port = sock.getsockname()[1]
    sock.close()
    return port


def _out_dir() -> Path:
    path = LOG_DIR / "e2e" / "p2p_wan_battle"
    path.mkdir(parents=True, exist_ok=True)
    return path


def _peer_cmd(godot: Path, script: str, log: Path) -> list:
    return [
        str(godot),
        "--headless",
        "--path",
        str(ROOT),
        *godot_log_args(log),
        "--script",
        script,
    ]


def _read(path: Path) -> str:
    try:
        return path.read_text().strip()
    except OSError:
        return ""


def _wait_rendezvous(rv: subprocess.Popen, timeout: float) -> bool:
    """等服务端真的开始监听（读 listening 行），而不是固定 sleep。"""
    deadline = time.time() + timeout
    while time.time() < deadline:
        if rv.poll() is not None:
            return False
        ready, _, _ = select.select([rv.stdout], [], [], 0.2)
        if ready:
            line = rv.stdout.readline()
            if "listening" in line:
                return True
    return False


def main() -> int:
    godot = find_godot()
    if godot is None:
        emit("FAIL", "找不到 Godot 可执行文件")
        print("P2P_WAN_BATTLE_FAIL")
        return 1

    out = _out_dir()
    host_result = out / "host.result"
    guest_result = out / "guest.result"
    host_ready = Path(str(host_result) + ".ready")
    invite_file = out / "invite.uri"
    guest_battle = Path(str(guest_result) + ".battle")
    host_battle = Path(str(host_result) + ".battle")
    for path in (host_result, guest_result, host_ready, invite_file, guest_battle, host_battle):
        path.unlink(missing_ok=True)

    rv_port = _free_udp_port()
    rv = subprocess.Popen(
        [sys.executable, str(RENDEZVOUS_SERVER), "--port", str(rv_port)],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
    host = None
    guest = None
    try:
        if not _wait_rendezvous(rv, RV_READY_TIMEOUT_SEC):
            emit("FAIL", "rendezvous 服务端未在 %.0fs 内监听" % RV_READY_TIMEOUT_SEC)
            print("P2P_WAN_BATTLE_FAIL")
            return 1

        env_common = {
            "RV_HOST": "127.0.0.1",
            "RV_PORT": str(rv_port),
            "INVITE_FILE": str(invite_file),
        }
        host_env = dict(os.environ)
        host_env.update(env_common)
        host_env.update({
            "RESULT_FILE": str(host_result),
            "READY_FILE": str(host_ready),
        })
        host = subprocess.Popen(
            _peer_cmd(godot, HOST_SCRIPT, out / "host.log"),
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, env=host_env,
        )
        if not _wait_file(host_ready, host, BOOT_TIMEOUT_SEC):
            _drain_kill(host)
            emit("FAIL", "Host 未进入 P2P hosting：%s" % _read(host_result))
            print("P2P_WAN_BATTLE_FAIL")
            return 1

        guest_env = dict(os.environ)
        guest_env.update(env_common)
        guest_env.update({
            "RESULT_FILE": str(guest_result),
            "READY_FILE": str(Path(str(guest_result) + ".ready")),
        })
        guest = subprocess.Popen(
            _peer_cmd(godot, GUEST_SCRIPT, out / "guest.log"),
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, env=guest_env,
        )

        guest_out = _communicate(guest, RESULT_TIMEOUT_SEC)
        host_out = _communicate(host, RESULT_TIMEOUT_SEC)
    finally:
        for proc in (guest, host):
            if proc is not None and proc.poll() is None:
                proc.kill()
        if rv.poll() is None:
            rv.kill()
        rv.wait(timeout=5)

    host_text = _read(host_result)
    guest_text = _read(guest_result)
    problems = []
    if not host_text.startswith("OK"):
        problems.append("Host: %s" % (host_text or (host_out or "").strip()[-400:] or "无结果"))
    if not guest_text.startswith("OK"):
        problems.append("Guest: %s" % (guest_text or (guest_out or "").strip()[-400:] or "无结果"))

    if problems:
        for problem in problems:
            emit("FAIL", problem)
        print("P2P_WAN_BATTLE_FAIL")
        return 1

    emit("PASS", "WAN P2P: Host invite -> Guest join_invite -> rendezvous/hole punch/direct ENet"
                 " -> protocol 6 -> seat 2 -> Ready -> Start -> 双方 Battle -> 退回菜单清场")
    print("P2P_WAN_BATTLE_OK")
    return 0


def _wait_file(path: Path, proc: subprocess.Popen, timeout: float) -> bool:
    deadline = time.time() + timeout
    while time.time() < deadline:
        if path.is_file() and path.stat().st_size > 0:
            return True
        if proc.poll() is not None:
            return False
        time.sleep(0.1)
    return False


def _communicate(proc: subprocess.Popen, timeout: float) -> str:
    try:
        return proc.communicate(timeout=timeout)[0] or ""
    except subprocess.TimeoutExpired:
        proc.kill()
        return proc.communicate()[0] or ""


def _drain_kill(proc: subprocess.Popen) -> None:
    proc.kill()
    try:
        proc.communicate(timeout=5)
    except Exception:  # noqa: BLE001
        pass


if __name__ == "__main__":
    sys.exit(main())
