#!/usr/bin/env python3
"""Phase 9.2.3 Direct ENet — 真实多进程 E2E（无 mock，无 SKIPPED）。

真进程 / 真 UDP / 真 ENet / 真 protocol 6：
    Test Runner (Python)
        ├── Rendezvous Server (tools/p2p/rendezvous/server.py)
        ├── Host  Godot headless：create_room -> host_room -> create_p2p_invite
        │                        -> start_p2p_hosting（rendezvous 注册 + hole punch）
        │                        -> 保持 ENet server，等 Guest 主动连
        │                        -> rpc_hello -> check_ticket -> peer_confirmed
        └── Guest Godot headless：读 **Host 真实生成的 invite URI**
                                 -> LobbyManager.join_invite(raw_uri)   ← 唯一生产入口
                                 -> rendezvous -> CANDIDATES -> hole punch
                                 -> direct_path_established -> begin_direct_enet
                                 -> LobbyNet.client_connect -> connected_to_server
                                 -> protocol 6 hello -> rpc_assign_seat(2) -> CONNECTED

三个用例（PASS 由真实状态文件逐条断言决定，不看“进程是否正常退出”）：
    success         完整链路 + Host 侧 seat 2 + Guest 侧 CONNECTED
    wrong_ticket    同样走到 direct ENet + hello，Host check_ticket -> BAD_TOKEN -> 踢人
    wrong_protocol  同样走到 direct ENet + hello(protocol!=6) -> BAD_PROTOCOL -> 踢人
                    负向用例必须证明：ENet connected != Lobby connected，
                    且 Guest 最终语义仍是 TICKET_REJECTED / VERSION_MISMATCH（不是 HOST_CLOSED）。

产物放置：全部在 tempfile.mkdtemp() 里（invite / ready / result / Godot --log-file），
跑完自动删除；失败时加 --keep-tmp 可保留现场。

用法：
    python3 tools/p2p/e2e_direct_enet_test.py --test-case all --runs 1
"""

from __future__ import annotations

import argparse
import os
import secrets
import select
import shutil
import socket
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from typing import Dict, List, Optional, Tuple

ROOT = Path(__file__).resolve().parent.parent.parent
TOOLS_DIR = ROOT / "tools"
sys.path.insert(0, str(TOOLS_DIR))

from wpg_common import find_godot  # noqa: E402

RENDEZVOUS_SERVER = TOOLS_DIR / "p2p" / "rendezvous" / "server.py"
HOST_SCRIPT = TOOLS_DIR / "e2e" / "p2p_direct_enet" / "host.gd"
GUEST_SCRIPT = TOOLS_DIR / "e2e" / "p2p_direct_enet" / "guest.gd"

BOOT_TIMEOUT_SEC = 25.0
RESULT_TIMEOUT_SEC = 45.0
RV_READY_TIMEOUT_SEC = 15.0
DEADLINE_SEC = 25

# LobbyNet.TicketReject
BAD_PROTOCOL = 1
BAD_TOKEN = 2
# 生产协议号（GameLaunch.NET_PROTOCOL）。runner 只做断言，不注入生产默认值。
NET_PROTOCOL = 6
# 故意与生产协议号不同的「未来协议号」：模拟对端版本更新，Host 必须判 BAD_PROTOCOL。
WRONG_PROTOCOL = NET_PROTOCOL + 1

# Guest 侧必须真实经过的 P2P 状态（顺序无关，逐项必须出现）
#   handshaking = connected_to_server 之后进入 protocol 6 握手
REQUIRED_P2P_STATES = (
    "rendezvous_registered",
    "candidates_received",
    "direct_probing",
    "direct_path_established",
    "direct_enet_connecting",
    "handshaking",
)
# Host 侧必须真实经过的 P2P 状态（Host 不建 ENet，所以没有 direct_enet_connecting）
REQUIRED_HOST_P2P_STATES = (
    "rendezvous_registered",
    "candidates_received",
    "direct_probing",
    "direct_path_established",
)

CASES = ("success", "wrong_ticket", "wrong_protocol")


class Failure(Exception):
    pass


def _free_udp_port() -> int:
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.bind(("127.0.0.1", 0))
    port = sock.getsockname()[1]
    sock.close()
    return port


def _parse_result(path: Path) -> Tuple[str, Dict[str, str]]:
    if not path.is_file():
        return "", {}
    fields: Dict[str, str] = {}
    status = ""
    for raw in path.read_text(errors="replace").splitlines():
        line = raw.strip()
        if not line or "=" not in line:
            continue
        key, _, value = line.partition("=")
        key, value = key.strip(), value.strip()
        if key == "STATUS":
            status = value
        fields[key] = value
    return status, fields


def _require(fields: Dict[str, str], key: str, expected: str, where: str) -> None:
    actual = fields.get(key)
    if actual != expected:
        raise Failure("%s: %s=%r（期望 %r）" % (where, key, actual, expected))


def _require_not(fields: Dict[str, str], key: str, forbidden: str, where: str) -> None:
    if fields.get(key) == forbidden:
        raise Failure("%s: %s 不得为 %r" % (where, key, forbidden))


def _require_states(fields: Dict[str, str], required: Tuple[str, ...], where: str) -> None:
    seen = [s for s in fields.get("P2P_STATES", "").split(",") if s]
    missing = [s for s in required if s not in seen]
    if missing:
        raise Failure("%s: 未经历 P2P 状态 %s（实际 %s）" % (where, missing, seen))


def _tail(text: str, limit: int = 300) -> str:
    """只取少量诊断信息；不倾倒完整 Godot / CI 日志。"""
    lines = [line for line in (text or "").splitlines() if line.strip()]
    return " | ".join(lines[-3:])[:limit]


class Session:
    """一次用例：rendezvous + host + guest，全部产物落在临时目录。"""

    def __init__(self, case: str, godot: Path, verbose: bool, keep_tmp: bool) -> None:
        self.case = case
        self.godot = godot
        self.verbose = verbose
        self.keep_tmp = keep_tmp
        self.work = Path(tempfile.mkdtemp(prefix="wpg_e2e_9_2_3_"))
        self.invite_file = self.work / "invite.uri"
        self.rv_port = _free_udp_port()
        self.procs: Dict[str, subprocess.Popen] = {}
        self.out: Dict[str, str] = {}

    # ---- 进程管理 ----

    def _godot_cmd(self, script: Path, log_name: str) -> List[str]:
        return [
            str(self.godot),
            "--headless",
            "--log-file",
            str(self.work / log_name),
            "--path",
            str(ROOT),
            "--script",
            str(script),
        ]

    def _spawn(self, name: str, script: Path, env: Dict[str, str], log_name: str) -> None:
        full_env = dict(os.environ)
        full_env.update(env)
        self.procs[name] = subprocess.Popen(
            self._godot_cmd(script, log_name),
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            env=full_env,
        )
        if self.verbose:
            print("[RUNNER] %s -> %s" % (name, " ".join(self._godot_cmd(script, log_name))))

    def _wait_file(self, path: Path, name: str, timeout: float) -> None:
        deadline = time.time() + timeout
        proc = self.procs.get(name)
        while time.time() < deadline:
            if path.is_file() and path.stat().st_size > 0:
                return
            if proc is not None and proc.poll() is not None:
                raise Failure("%s 进程提前退出（exit=%s）" % (name, proc.returncode))
            time.sleep(0.05)
        raise Failure("%s 未在 %.0fs 内就绪" % (name, timeout))

    def _wait_exit(self, name: str, timeout: float) -> str:
        proc = self.procs[name]
        try:
            out = proc.communicate(timeout=timeout)[0] or ""
        except subprocess.TimeoutExpired:
            proc.kill()
            out = proc.communicate()[0] or ""
            self.out[name] = out
            raise Failure("%s 进程超时未退出" % name)
        self.out[name] = out
        return out

    def _kill_all(self) -> None:
        for proc in self.procs.values():
            if proc.poll() is None:
                try:
                    proc.kill()
                except OSError:
                    pass
                try:
                    proc.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    pass
        self.procs.clear()

    def cleanup(self) -> None:
        self._kill_all()
        ## 诊断留痕（只在临时目录里，不进仓库）：完整 stdout 便于事后定位时序问题。
        for name, text in self.out.items():
            try:
                (self.work / ("%s.stdout" % name)).write_text(text or "", encoding="utf-8")
            except OSError:
                pass
        if self.keep_tmp:
            print("[RUNNER] 保留临时目录：%s" % self.work)
        else:
            shutil.rmtree(self.work, ignore_errors=True)

    # ---- 用例执行 ----

    def run(self) -> None:
        rv = subprocess.Popen(
            [sys.executable, str(RENDEZVOUS_SERVER), "--port", str(self.rv_port)],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
        )
        try:
            self._wait_rendezvous(rv)
            self._run_case()
        finally:
            if rv.poll() is None:
                rv.kill()
            rv.wait(timeout=5)

    def _wait_rendezvous(self, rv: subprocess.Popen) -> None:
        """等服务端真的开始监听（读它的 listening 行），而不是固定 sleep。"""
        deadline = time.time() + RV_READY_TIMEOUT_SEC
        while time.time() < deadline:
            if rv.poll() is not None:
                raise Failure("rendezvous server 启动即退出")
            ready, _, _ = select.select([rv.stdout], [], [], 0.2)
            if ready:
                line = rv.stdout.readline()
                if "listening" in line:
                    return
        raise Failure("rendezvous server 未在 %.0fs 内监听" % RV_READY_TIMEOUT_SEC)

    def _env_common(self, result_name: str) -> Dict[str, str]:
        return {
            "RV_HOST": "127.0.0.1",
            "RV_PORT": str(self.rv_port),
            "LAN_HOST": "127.0.0.1",
            "INVITE_FILE": str(self.invite_file),
            "RESULT_FILE": str(self.work / result_name),
            "READY_FILE": str(self.work / (result_name + ".ready")),
            "CASE": self.case,
            "DEADLINE_SEC": str(DEADLINE_SEC),
        }

    def _run_case(self) -> None:
        host_env = self._env_common("host.result")
        self._spawn("host", HOST_SCRIPT, host_env, "host.godot.log")
        self._wait_file(self.work / "host.result.ready", "host", BOOT_TIMEOUT_SEC)

        guest_env = self._env_common("guest.result")
        if self.case == "wrong_protocol":
            guest_env["HELLO_PROTOCOL"] = str(WRONG_PROTOCOL)
        if self.case == "wrong_ticket":
            guest_env["HELLO_TICKET"] = secrets.token_hex(16)  # 同长度、不同内容
        self._spawn("guest", GUEST_SCRIPT, guest_env, "guest.godot.log")
        self._wait_file(self.work / "guest.result.ready", "guest", BOOT_TIMEOUT_SEC)

        self._wait_exit("guest", RESULT_TIMEOUT_SEC)
        self._wait_exit("host", RESULT_TIMEOUT_SEC)

        host_status, host = _parse_result(self.work / "host.result")
        guest_status, guest = _parse_result(self.work / "guest.result")

        if self.case == "success":
            self._assert_success(host_status, host, guest_status, guest)
        else:
            self._assert_rejected(host_status, host, guest_status, guest)
        return

    # ---- 断言 ----

    def _assert_success(self, h_status: str, h: Dict[str, str], g_status: str, g: Dict[str, str]) -> None:
        # Host：真实 server 仍在 hosting，Guest 拿到正式 seat 2。
        _require(h, "STATUS", "HOST_OK", "Host")
        _require(h, "PROTOCOL", str(NET_PROTOCOL), "Host")
        _require(h, "INVITE_WRITTEN", "1", "Host")
        _require(h, "INVITE_IS_P2P", "1", "Host")
        _require(h, "ENET_SERVER", "1", "Host")
        _require(h, "SINGLE_PEER", "1", "Host")
        _require(h, "PEER_CONNECTED", "1", "Host")
        _require(h, "PEER_CONFIRMED", "1", "Host")
        _require(h, "TICKET_ACCEPTED", "1", "Host")
        _require(h, "SEAT", "2", "Host")
        _require(h, "PLAYERS", "2", "Host")
        _require(h, "OCCUPIED", "2", "Host")
        _require(h, "ROOM_OPEN", "1", "Host")
        _require(h, "REJECTED_NONE", "1", "Host")
        _require(h, "P2P_ROLE", "host", "Host")
        _require_states(h, REQUIRED_HOST_P2P_STATES, "Host")

        # Guest：生产入口 join_invite -> 完整 P2P -> protocol 6 -> seat 2 -> CONNECTED。
        _require(g, "STATUS", "GUEST_OK", "Guest")
        _require(g, "ENTRY", "join_invite", "Guest")
        _require(g, "JOIN_INVITE_VALID", "1", "Guest")
        _require(g, "JOIN_ACCEPTED", "1", "Guest")
        _require(g, "JOIN_IS_P2P", "1", "Guest")
        _require(g, "USES_RENDEZVOUS", "1", "Guest")
        _require(g, "P2P_ROLE", "guest", "Guest")
        _require(g, "CONNECTED_TO_SERVER", "1", "Guest")
        _require(g, "SEAT_ASSIGNED", "1", "Guest")
        _require(g, "SEAT", "2", "Guest")
        _require(g, "P2P_STATE", "connected", "Guest")
        _require(g, "NET_STATE", "LOBBY", "Guest")
        _require(g, "SINGLE_PEER", "1", "Guest")
        _require(g, "HELLO_OVERRIDE_PROTOCOL", "0", "Guest")
        _require_states(g, REQUIRED_P2P_STATES + ("connected",), "Guest")
        if g.get("TERMINAL", ""):
            raise Failure("Guest: 成功用例不应有终态失败原因（%r）" % g.get("TERMINAL"))

    def _assert_rejected(self, h_status: str, h: Dict[str, str], g_status: str, g: Dict[str, str]) -> None:
        protocol_case = self.case == "wrong_protocol"
        expected_code = str(BAD_PROTOCOL if protocol_case else BAD_TOKEN)
        expected_terminal = "version_mismatch" if protocol_case else "ticket_rejected"

        # Host：真实拒绝，且没把 Guest 放进 Room.players / 正式 seat；server 仍在。
        _require(h, "STATUS", "HOST_REJECTED", "Host")
        _require(h, "PROTOCOL", str(NET_PROTOCOL), "Host")
        _require(h, "ENET_SERVER", "1", "Host")
        _require(h, "SINGLE_PEER", "1", "Host")
        _require(h, "PEER_CONNECTED", "1", "Host")
        _require(h, "PEER_REJECTED", "1", "Host")
        _require(h, "REJECT_REASON_CODE", expected_code, "Host")
        _require(h, "PEER_CONFIRMED", "0", "Host")
        _require(h, "PLAYERS", "1", "Host")
        _require(h, "OCCUPIED", "1", "Host")
        _require(h, "SEAT2_PEER", "0", "Host")
        _require(h, "SEAT2_IS_GUEST", "0", "Host")
        _require_states(h, REQUIRED_HOST_P2P_STATES, "Host")

        # Guest：真的连上过 ENet + 跑完 hello，才被 Host 拒绝；最终语义不得被覆写成 HOST_CLOSED。
        _require(g, "STATUS", "GUEST_REJECTED", "Guest")
        ## 负向用例只改 hello 内容：wrong_protocol 出示未来协议号；
        ## wrong_ticket 仍用生产协议号（证明那一路纯粹是 ticket 被判死，不是协议不符）。
        _require(
            g,
            "HELLO_OVERRIDE_PROTOCOL",
            str(WRONG_PROTOCOL) if protocol_case else "0",
            "Guest",
        )
        _require(g, "ENTRY", "join_invite", "Guest")
        _require(g, "JOIN_ACCEPTED", "1", "Guest")
        _require(g, "CONNECTED_TO_SERVER", "1", "Guest")  # ENet connected != Lobby connected
        _require(g, "JOIN_REJECTED", "1", "Guest")
        _require(g, "SEAT_ASSIGNED", "0", "Guest")
        _require(g, "P2P_STATE", expected_terminal, "Guest")
        _require(g, "TERMINAL", expected_terminal, "Guest")
        _require(g, "SEAT", "0", "Guest")
        _require(g, "REJECT_REASON_CODE", expected_code, "Guest")
        _require_not(g, "NET_STATE", "HOST_CLOSED", "Guest")
        _require(g, "OVERRIDDEN_BY_HOST_CLOSED", "0", "Guest")
        _require_states(g, REQUIRED_P2P_STATES, "Guest")


def run_case(case: str, godot: Path, verbose: bool, keep_tmp: bool) -> Tuple[bool, str]:
    session = Session(case, godot, verbose, keep_tmp)
    try:
        session.run()
        return True, "ok"
    except Failure as exc:
        return False, str(exc)
    except Exception as exc:  # noqa: BLE001
        return False, "exception: %s" % exc
    finally:
        session.cleanup()


def main() -> int:
    parser = argparse.ArgumentParser(description="Phase 9.2.3 Direct ENet 真实多进程 E2E")
    parser.add_argument("--test-case", choices=[*CASES, "all"], default="all")
    parser.add_argument("--runs", type=int, default=1)
    parser.add_argument("--verbose", action="store_true")
    parser.add_argument("--keep-tmp", action="store_true", help="失败时保留临时目录（默认全部清理）")
    args = parser.parse_args()

    if args.runs < 1:
        print("[FAIL] --runs 必须 >= 1")
        return 1

    godot = find_godot()
    if godot is None:
        print("[FAIL] 找不到 Godot 可执行文件（可设置 GODOT_BIN）")
        return 1

    cases = list(CASES) if args.test_case == "all" else [args.test_case]
    print("=== Phase 9.2.3 Direct ENet E2E ===")
    print("Godot: %s" % godot)
    print("Cases: %s | Runs: %d" % (",".join(cases), args.runs))

    totals: Dict[str, List[int]] = {case: [0, 0] for case in cases}
    for run in range(1, args.runs + 1):
        for case in cases:
            ok, detail = run_case(case, godot, args.verbose, args.keep_tmp)
            totals[case][0 if ok else 1] += 1
            tag = "PASS" if ok else "FAIL"
            print("[%s] run=%d case=%s %s" % (tag, run, case, "" if ok else detail))

    print("--- Summary ---")
    failed = 0
    for case in cases:
        passed, rejected = totals[case]
        failed += rejected
        print("%-15s %d/%d" % (case, passed, passed + rejected))

    if failed:
        print("E2E_FAIL")
        return 1
    print("E2E_OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
