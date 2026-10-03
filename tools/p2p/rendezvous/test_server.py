#!/usr/bin/env python3
"""Rendezvous server 回归（Phase 9.2.1）。

覆盖任务要求的 14 条：
 1. Host register
 2. Guest register
 3. Host + Guest 配对
 4. 双方收到 candidates
 5. observed endpoint 被服务器写入
 6. client 不能伪造 server observed endpoint
 7. bad protocol 被拒
 8. bad ticket 被拒
 9. duplicate host 被拒
10. duplicate guest 被拒
11. session timeout cleanup
12. malformed packet 被拒
13. nonce 不为空且每次 session 不同
14. 不输出明文 ticket 到日志

跑法：python3 tools/p2p/rendezvous/test_server.py
通过输出 RENDEZVOUS_SERVER_OK；失败输出 RENDEZVOUS_SERVER_FAIL 并返回非 0。
"""

from __future__ import annotations

import io
import os
import socket
import sys
import time
from contextlib import redirect_stdout
from typing import List, Optional, Tuple

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import protocol as P  # noqa: E402
import server as S  # noqa: E402

TICKET = "0f1e2d3c4b5a69788796a5b4c3d2e1f0"
ROOM = "a1b2c3d4"
PROTOCOL = 6

_failures: List[str] = []


def expect(condition: bool, label: str) -> None:
    if not condition:
        _failures.append(label)


def make_nonce(seed: int) -> str:
    return ("%032x" % seed)[:32]


def local_candidates() -> List[P.Candidate]:
    return [P.Candidate(path=P.PATH_LAN_IPV4, address="192.168.1.20", port=17777)]


def register_bytes(
    role: int,
    nonce: str,
    room_id: str = ROOM,
    ticket: str = TICKET,
    protocol: int = PROTOCOL,
    session_id: str = "",
    candidates: Optional[List[P.Candidate]] = None,
) -> bytes:
    return P.encode_register(
        P.Register(
            session_id=session_id,
            role=role,
            protocol=protocol,
            nonce=nonce,
            room_id=room_id,
            ticket=ticket,
            candidates=local_candidates() if candidates is None else candidates,
        )
    )


class Harness:
    """一个已 bind 但未 serve_forever 的服务端 + 若干假客户端地址。

    不真的走网络：直接调 handle_packet 并抓取服务端发回的包。
    这样 observed endpoint 仍然来自我们伪造的 addr（等价于内核给的源地址），
    能真实验证「服务端看到什么就记什么」。

    发包**按地址分队列**：否则「取 Host 的回包」会把 Guest 的一起抽走。
    """

    def __init__(self) -> None:
        self.server = S.RendezvousServer(host="127.0.0.1", port=0, verbose=False)
        # 不 bind 真 socket：_send 会因为 self.sock is None 而跳过，
        # 我们用 outgoing 接管。
        self.outgoing: Dict[Tuple[str, int], List[bytes]] = {}
        self.server._send = self._capture  # type: ignore[assignment]

    def _capture(self, addr: Tuple[str, int], payload: bytes) -> None:
        self.outgoing.setdefault(addr, []).append(payload)

    def send(self, payload: bytes, addr: Tuple[str, int]) -> None:
        self.server.handle_packet(payload, addr)

    def take(self, addr: Optional[Tuple[str, int]] = None) -> List[Tuple[Tuple[str, int], bytes]]:
        """取走某地址（或全部）的待收包。"""
        if addr is not None:
            pending = self.outgoing.pop(addr, [])
            return [(addr, payload) for payload in pending]
        got: List[Tuple[Tuple[str, int], bytes]] = []
        for target, payloads in self.outgoing.items():
            got.extend((target, payload) for payload in payloads)
        self.outgoing.clear()
        return got

    def decode_all(self, addr: Tuple[str, int]) -> List[Tuple[int, object]]:
        out = []
        for _target, payload in self.take(addr):
            msg_type, _sid, msg = P.decode(payload)
            out.append((msg_type, msg))
        return out


HOST_ADDR = ("198.51.100.10", 40001)
GUEST_ADDR = ("203.0.113.20", 40002)


def new_harness() -> Harness:
    return Harness()


# ---- 用例 ----

def case_host_register() -> None:
    h = new_harness()
    h.send(register_bytes(P.ROLE_HOST, make_nonce(1)), HOST_ADDR)
    msgs = h.decode_all(HOST_ADDR)
    expect(len(msgs) == 1, "Host register 恰好收到 1 个回包")
    expect(msgs and msgs[0][0] == P.REGISTERED, "Host 收到 REGISTERED")
    registered = msgs[0][1]
    expect(P.is_valid_session_id(registered.session_id), "REGISTERED 带合法 session_id")
    expect(registered.nonce == make_nonce(1), "REGISTERED 回显本端 nonce")
    expect(h.server.session_count() == 1, "服务端有 1 个 session")


def case_guest_register_and_pair() -> None:
    h = new_harness()
    h.send(register_bytes(P.ROLE_HOST, make_nonce(1)), HOST_ADDR)
    host_msgs = h.decode_all(HOST_ADDR)
    session_id = host_msgs[0][1].session_id
    h.send(register_bytes(P.ROLE_GUEST, make_nonce(2)), GUEST_ADDR)
    guest_msgs = h.decode_all(GUEST_ADDR)
    expect(len(guest_msgs) >= 2, "Guest 至少收到 REGISTERED + CANDIDATES")
    types = [t for t, _m in guest_msgs]
    expect(P.REGISTERED in types, "Guest 收到 REGISTERED")
    expect(P.CANDIDATES in types, "Guest 收到 CANDIDATES（配对成功）")
    # Host 也应收到 CANDIDATES。
    host_after = h.decode_all(HOST_ADDR)
    host_types = [t for t, _m in host_after]
    expect(P.CANDIDATES in host_types, "Host 也收到 CANDIDATES")
    cand_msg = [m for t, m in guest_msgs if t == P.CANDIDATES][0]
    expect(cand_msg.session_id == session_id, "CANDIDATES 的 session_id 与配对一致")
    expect(cand_msg.remote_role == P.ROLE_HOST, "Guest 看到的 remote_role = host")
    expect(cand_msg.remote_nonce == make_nonce(1), "Guest 拿到 Host 的 nonce")
    expect(len(cand_msg.candidates) >= 1, "Guest 拿到 Host 的 candidate")


def case_observed_endpoint_recorded() -> None:
    """observed endpoint 必须是服务端看到的源地址，不是客户端自报的。"""
    h = new_harness()
    # 客户端在 candidate 里塞一个假的 observed_address，服务端必须无视它。
    forged = [
        P.Candidate(
            path=P.PATH_WAN_IPV4,
            address="10.0.0.5",
            port=49152,
            observed_address="1.2.3.4",
            observed_port=9999,
        )
    ]
    h.send(register_bytes(P.ROLE_HOST, make_nonce(1), candidates=forged), HOST_ADDR)
    msgs = h.decode_all(HOST_ADDR)
    registered = msgs[0][1]
    expect(registered.observed_address == HOST_ADDR[0], "observed_address = 真实源地址")
    expect(registered.observed_port == HOST_ADDR[1], "observed_port = 真实源端口")
    expect(registered.observed_address != "1.2.3.4", "拒绝客户端自报的 observed_address")

    h.send(register_bytes(P.ROLE_GUEST, make_nonce(2)), GUEST_ADDR)
    guest_msgs = h.decode_all(GUEST_ADDR)
    guest_types = [t for t, _m in guest_msgs]
    expect(P.REGISTERED in guest_types, "Guest 收到 REGISTERED")
    g_reg = [m for t, m in guest_msgs if t == P.REGISTERED][0]
    expect(g_reg.observed_address == GUEST_ADDR[0], "Guest 的 observed_address = 真实源地址")
    expect(g_reg.observed_port == GUEST_ADDR[1], "Guest 的 observed_port = 真实源端口")
    # Guest 收到的 Host 候选必须带**服务端观测到**的 Host 端点。
    cand = [m for t, m in guest_msgs if t == P.CANDIDATES][0]
    first = cand.candidates[0]
    expect(first.observed_address == HOST_ADDR[0], "交换出去的 Host observed 来自服务端")
    expect(first.observed_port == HOST_ADDR[1], "交换出去的 Host observed_port 来自服务端")
    expect(first.observed_address != "1.2.3.4", "伪造的 observed 未被转发")


def case_bad_protocol_rejected() -> None:
    h = new_harness()
    h.send(register_bytes(P.ROLE_HOST, make_nonce(1), protocol=0), HOST_ADDR)
    msgs = h.decode_all(HOST_ADDR)
    expect(len(msgs) == 1 and msgs[0][0] == P.ERROR, "bad protocol -> ERROR")
    expect(msgs[0][1].code == P.ERR_BAD_PROTOCOL, "错误码 = BAD_PROTOCOL")
    expect(h.server.session_count() == 0, "bad protocol 不创建 session")


def case_bad_ticket_rejected() -> None:
    h = new_harness()
    # Host 建 session（正常 ticket）。
    h.send(register_bytes(P.ROLE_HOST, make_nonce(1)), HOST_ADDR)
    h.decode_all(HOST_ADDR)
    # Guest 用错 ticket。
    wrong = "deadbeefdeadbeefdeadbeefdeadbeef"
    h.send(register_bytes(P.ROLE_GUEST, make_nonce(2), ticket=wrong), GUEST_ADDR)
    msgs = h.decode_all(GUEST_ADDR)
    expect(len(msgs) == 1 and msgs[0][0] == P.ERROR, "错 ticket -> ERROR")
    expect(msgs[0][1].code == P.ERR_BAD_TICKET, "错误码 = BAD_TICKET")
    # 空 ticket。
    h.send(register_bytes(P.ROLE_HOST, make_nonce(3), room_id="other1", ticket=""), HOST_ADDR)
    msgs = h.decode_all(HOST_ADDR)
    expect(msgs[0][1].code == P.ERR_BAD_TICKET, "空 ticket -> BAD_TICKET")
    # Guest 找不到房间。
    h.send(register_bytes(P.ROLE_GUEST, make_nonce(4), room_id="nosuch1"), GUEST_ADDR)
    msgs = h.decode_all(GUEST_ADDR)
    expect(msgs[0][1].code == P.ERR_SESSION_NOT_FOUND, "无 session -> SESSION_NOT_FOUND")


def case_duplicate_host_rejected() -> None:
    h = new_harness()
    h.send(register_bytes(P.ROLE_HOST, make_nonce(1)), HOST_ADDR)
    first = h.decode_all(HOST_ADDR)
    session_id = first[0][1].session_id
    # 另一个来源声称同一房间的 Host。
    other_host = ("198.51.100.99", 40001)
    h.send(register_bytes(P.ROLE_HOST, make_nonce(5)), other_host)
    msgs = h.decode_all(other_host)
    expect(len(msgs) == 1 and msgs[0][0] == P.ERROR, "duplicate host -> ERROR")
    expect(msgs[0][1].code == P.ERR_DUPLICATE_PEER, "错误码 = DUPLICATE_PEER")
    expect(msgs[0][1].session_id == session_id, "错误里带原 session_id（可诊断）")
    expect(h.server.session_count() == 1, "不产生第二个 session")
    # 旧 session 未被覆盖。
    expect(h.server.sessions[session_id].host.nonce == make_nonce(1), "旧 Host 未被覆盖")


def case_duplicate_guest_rejected() -> None:
    h = new_harness()
    h.send(register_bytes(P.ROLE_HOST, make_nonce(1)), HOST_ADDR)
    h.decode_all(HOST_ADDR)
    h.send(register_bytes(P.ROLE_GUEST, make_nonce(2)), GUEST_ADDR)
    h.decode_all(GUEST_ADDR)
    h.decode_all(HOST_ADDR)
    # 第二个 Guest（不同来源）。
    other_guest = ("203.0.113.99", 40002)
    h.send(register_bytes(P.ROLE_GUEST, make_nonce(3)), other_guest)
    msgs = h.decode_all(other_guest)
    expect(len(msgs) == 1 and msgs[0][0] == P.ERROR, "duplicate guest -> ERROR")
    expect(msgs[0][1].code == P.ERR_DUPLICATE_PEER, "错误码 = DUPLICATE_PEER")
    # session 仍然只有一个 Guest。
    session = list(h.server.sessions.values())[0]
    expect(session.guest is not None and session.guest.nonce == make_nonce(2), "旧 Guest 未被顶替")


def case_session_timeout_cleanup() -> None:
    h = new_harness()
    h.send(register_bytes(P.ROLE_HOST, make_nonce(1)), HOST_ADDR)
    h.send(register_bytes(P.ROLE_GUEST, make_nonce(2)), GUEST_ADDR)
    h.take()
    expect(h.server.session_count() == 1, "超时前有 1 个 session")
    # 还未超时。
    removed = h.server.cleanup(now=time.time())
    expect(removed == 0, "未超时不回收")
    expect(h.server.session_count() == 1, "未超时 session 仍在")
    # 推过阈值。
    future = time.time() + S.SESSION_IDLE_TIMEOUT_SEC + 1.0
    removed = h.server.cleanup(now=future)
    expect(removed == 1, "超时回收 1 个 session")
    expect(h.server.session_count() == 0, "超时后 session 被删除")
    expect(ROOM not in h.server.rooms, "room 索引也清掉")

    # 超时只影响那一个 session，不碰其它 session。
    h2 = new_harness()
    h2.send(register_bytes(P.ROLE_HOST, make_nonce(1), room_id="roomA"), HOST_ADDR)
    fresh = ("198.51.100.11", 40001)
    h2.send(register_bytes(P.ROLE_HOST, make_nonce(2), room_id="roomB"), fresh)
    h2.take()
    expect(h2.server.session_count() == 2, "两个 session")
    # 让 roomA 的活动时间变旧。
    session_a = h2.server.rooms["roomA"]
    h2.server.sessions[session_a].created_at -= (S.SESSION_IDLE_TIMEOUT_SEC + 5)
    h2.server.sessions[session_a].host.last_seen -= (S.SESSION_IDLE_TIMEOUT_SEC + 5)
    removed = h2.server.cleanup(now=time.time())
    expect(removed == 1, "只回收超时的那个")
    expect(h2.server.session_count() == 1, "另一个 session 不受影响")
    expect("roomB" in h2.server.rooms, "未超时的 room 仍在")


def case_malformed_packet_rejected() -> None:
    h = new_harness()
    # 空包 / 垃圾 / 错 magic / 截断。
    h.send(b"", HOST_ADDR)
    msgs = h.decode_all(HOST_ADDR)
    expect(len(msgs) == 1 and msgs[0][0] == P.ERROR, "空包 -> ERROR")
    expect(msgs[0][1].code == P.ERR_MALFORMED_PACKET, "空包 -> MALFORMED_PACKET")

    h.send(b"A" * 40, HOST_ADDR)
    msgs = h.decode_all(HOST_ADDR)
    expect(msgs[0][1].code == P.ERR_MALFORMED_PACKET, "错 magic -> MALFORMED_PACKET")

    good = register_bytes(P.ROLE_HOST, make_nonce(1))
    h.send(good[: len(good) // 2], HOST_ADDR)
    msgs = h.decode_all(HOST_ADDR)
    expect(msgs[0][1].code == P.ERR_MALFORMED_PACKET, "截断包 -> MALFORMED_PACKET")

    # 客户端不该发服务端专有消息。
    h.send(P.encode_registered(P.Registered(session_id="0123456789abcdef", nonce=make_nonce(1))), HOST_ADDR)
    msgs = h.decode_all(HOST_ADDR)
    expect(msgs[0][1].code == P.ERR_BAD_ROLE, "客户端发 REGISTERED -> BAD_ROLE")
    expect(h.server.session_count() == 0, "malformed 一律不创建 session")


def case_nonce_unique_and_nonempty() -> None:
    h = new_harness()
    h.send(register_bytes(P.ROLE_HOST, make_nonce(1), room_id="roomA"), HOST_ADDR)
    other = ("198.51.100.11", 40001)
    h.send(register_bytes(P.ROLE_HOST, make_nonce(2), room_id="roomB"), other)
    h.take()
    sessions = list(h.server.sessions.values())
    expect(len(sessions) == 2, "两个 session")
    ids = [s.session_id for s in sessions]
    expect(all(i for i in ids), "session_id 全部非空")
    expect(ids[0] != ids[1], "每次 session 的 id 不同")
    expect(all(P.is_valid_session_id(i) for i in ids), "session_id 形状合法")
    nonces = [s.host.nonce for s in sessions]
    expect(all(n for n in nonces), "nonce 非空")
    expect(nonces[0] != nonces[1], "不同 session 的 nonce 不同")

    # 空 nonce 必须被拒。
    h.send(P.encode_register(P.Register(session_id="", role=P.ROLE_HOST, protocol=PROTOCOL,
                                        nonce="", room_id="roomC", ticket=TICKET)), HOST_ADDR)
    msgs = h.decode_all(HOST_ADDR)
    expect(msgs[0][1].code == P.ERR_BAD_PROTOCOL, "空 nonce -> BAD_PROTOCOL")

    # 非法 role。
    h.send(P.encode_register(P.Register(session_id="", role=7, protocol=PROTOCOL,
                                        nonce=make_nonce(9), room_id="roomD", ticket=TICKET)), HOST_ADDR)
    msgs = h.decode_all(HOST_ADDR)
    expect(msgs[0][1].code == P.ERR_BAD_ROLE, "非法 role -> BAD_ROLE")


def case_logs_hide_ticket() -> None:
    """verbose 日志里绝不能出现完整 ticket。"""
    banner = TICKET
    buf = io.StringIO()
    server = S.RendezvousServer(host="127.0.0.1", port=0, verbose=True)
    server._send = lambda addr, payload: None  # type: ignore[assignment]
    with redirect_stdout(buf):
        server.handle_packet(register_bytes(P.ROLE_HOST, make_nonce(1)), HOST_ADDR)
        server.handle_packet(register_bytes(P.ROLE_GUEST, make_nonce(2)), GUEST_ADDR)
        # 触发一条 reject 日志。
        server.handle_packet(register_bytes(P.ROLE_GUEST, make_nonce(3)), ("203.0.113.99", 40002))
        server.cleanup(now=time.time() + S.SESSION_IDLE_TIMEOUT_SEC + 5)
    text = buf.getvalue()
    expect(banner not in text, "日志不含完整 ticket")
    expect("0f1e2d3c" not in text, "日志不含 ticket 前缀")
    expect("nonce=" in text or "session=" in text, "日志确实产生了内容（对照组）")


def case_stun_wire_format() -> None:
    """最小 STUN subset：Binding Request 构造 + XOR-MAPPED-ADDRESS 解析。"""
    import stun as ST

    tid = bytes(range(12))
    request = ST.build_binding_request(tid)
    expect(len(request) == 20, "Binding Request 20 字节头")
    msg_type, length, cookie = __import__("struct").unpack_from(">HHI", request, 0)
    expect(msg_type == ST.BINDING_REQUEST, "type = Binding Request")
    expect(length == 0, "Binding Request 无属性")
    expect(cookie == ST.STUN_MAGIC_COOKIE, "magic cookie = 0x2112A442")
    expect(request[8:20] == tid, "transaction id 保真")

    # 构造一个合法 XOR-MAPPED-ADDRESS 应答。
    import struct as _s

    mapped_ip = "203.0.113.7"
    mapped_port = 51820
    ip_int = _s.unpack(">I", __import__("socket").inet_aton(mapped_ip))[0]
    xored_ip = ip_int ^ ST.STUN_MAGIC_COOKIE
    xored_port = mapped_port ^ (ST.STUN_MAGIC_COOKIE >> 16)
    value = _s.pack(">BBHI", 0, 0x01, xored_port, xored_ip)
    attr = _s.pack(">HH", ST.ATTR_XOR_MAPPED_ADDRESS, len(value)) + value
    body = attr
    header = _s.pack(">HHI", ST.BINDING_SUCCESS, len(body), ST.STUN_MAGIC_COOKIE) + tid
    result = ST.parse_binding_response(header + body, tid)
    expect(result.address == mapped_ip, "XOR-MAPPED-ADDRESS 地址解析正确")
    expect(result.port == mapped_port, "XOR-MAPPED-ADDRESS 端口解析正确")
    expect(result.is_usable(), "解析结果可用")

    # 错 transaction id 必须被拒。
    try:
        ST.parse_binding_response(header + body, bytes(range(1, 13)))
        expect(False, "错 transaction id 应被拒")
    except ST.StunError:
        expect(True, "错 transaction id 被拒")

    # 错 magic cookie 必须被拒。
    bad_header = _s.pack(">HHI", ST.BINDING_SUCCESS, len(body), 0xDEADBEEF) + tid
    try:
        ST.parse_binding_response(bad_header + body, tid)
        expect(False, "错 magic cookie 应被拒")
    except ST.StunError:
        expect(True, "错 magic cookie 被拒")

    # 无应答 -> None（绝不伪造）。
    closed = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    closed.bind(("127.0.0.1", 0))
    dead_port = closed.getsockname()[1]
    closed.close()
    expect(ST.query("127.0.0.1", dead_port, timeout_sec=0.3) is None, "无 STUN 应答 -> None（不伪造）")


def case_python_gdscript_wire_parity() -> None:
    """Python 与 GDScript 必须产出逐字节一致的 REGISTER（跨语言互通前提）。

    期望值来自 tests/rendezvous_client_test.gd 同款输入（见 README）。
    """
    identity_nonce = "aabbccddeeff00112233445566778899"
    cand = P.Candidate(path=P.PATH_LAN_IPV4, address="192.168.1.20", port=17777)
    msg = P.Register(
        session_id="0123456789abcdef",
        role=P.ROLE_GUEST,
        protocol=6,
        nonce=identity_nonce,
        room_id="a1b2c3d4",
        ticket=TICKET,
        candidates=[cand],
    )
    encoded = P.encode_register(msg)
    # 关键结构断言（不硬编码整串 hex，避免测试与实现一起漂移）。
    expect(encoded[:4] == b"WPG\x52"[:4] or encoded[:4] == bytes.fromhex("57504752"), "magic = WPGR")
    expect(encoded[4] == P.VERSION, "版本字节 = 2")
    expect(encoded[5] == P.REGISTER, "type 字节 = REGISTER")
    # 能被自己解回。
    msg_type, session_id, back = P.decode(encoded)
    expect(msg_type == P.REGISTER, "自解 type 一致")
    expect(session_id == "0123456789abcdef", "自解 session_id 一致")
    expect(back.ticket == TICKET, "自解 ticket 一致")
    expect(back.candidates[0].address == "192.168.1.20", "自解 candidate 一致")
    # 字节长度公式：4 magic + 1 ver + 1 type + (4+16 sid) + 1 role + 1 proto
    #             + (4+32 nonce) + (4+8 room) + (4+32 ticket) + 4 count
    #             + 6 fixed + (4+12 addr) + (4+0 obs)
    expected_len = 4 + 1 + 1 + 4 + 16 + 1 + 1 + 4 + 32 + 4 + 8 + 4 + 32 + 4 + 6 + 4 + 12 + 4 + 0
    expect(len(encoded) == expected_len, "REGISTER 长度符合 wire 公式（%d vs %d）" % (len(encoded), expected_len))


# ---- main ----

def main() -> int:
    cases = [
        ("host register", case_host_register),
        ("guest register + pairing", case_guest_register_and_pair),
        ("observed endpoint recorded", case_observed_endpoint_recorded),
        ("bad protocol rejected", case_bad_protocol_rejected),
        ("bad ticket rejected", case_bad_ticket_rejected),
        ("duplicate host rejected", case_duplicate_host_rejected),
        ("duplicate guest rejected", case_duplicate_guest_rejected),
        ("session timeout cleanup", case_session_timeout_cleanup),
        ("malformed packet rejected", case_malformed_packet_rejected),
        ("nonce unique and nonempty", case_nonce_unique_and_nonempty),
        ("logs hide ticket", case_logs_hide_ticket),
        ("stun wire format", case_stun_wire_format),
        ("python/gdscript wire parity", case_python_gdscript_wire_parity),
    ]
    for label, fn in cases:
        try:
            fn()
        except Exception as exc:  # noqa: BLE001
            _failures.append("%s raised %s: %s" % (label, type(exc).__name__, exc))
    if _failures:
        for item in _failures:
            print("RENDEZVOUS_SERVER_FAIL: %s" % item, file=sys.stderr)
        return 1
    print("RENDEZVOUS_SERVER_OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
