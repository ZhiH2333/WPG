#!/usr/bin/env python3
"""最小公网 Rendezvous Service（Phase 9.2.1）。

职责（严格）：
- register / match / candidate exchange / observed endpoint 记录 / session 生命周期
- 最基本的 timeout 与 cleanup

**绝对不做**：
- 游戏流量、Combat、Lobby roster、Ready
- ENet relay、NAT 数据转发、任何形式的转发
- seat 分配、Room.players、GameLaunch

Rendezvous 是「发现 / 交换服务」，**不是 Relay**。

服务端**不拥有**最终准入权威：最终能不能进 Lobby 仍由 Host 的 protocol 6
ticket handshake 决定。这里只做最基础的协议 / 形状 / 配对校验。

用法：
    python3 tools/p2p/rendezvous/server.py --port 17779
    python3 tools/p2p/rendezvous/server.py --port 17779 --verbose
"""

from __future__ import annotations

import argparse
import os
import secrets
import socket
import sys
import time
from dataclasses import dataclass, field
from typing import Dict, List, Optional, Tuple

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import protocol as P  # noqa: E402

# 服务端 session 空闲阈值（双方都静默后回收）。
SESSION_IDLE_TIMEOUT_SEC = 30.0
# 单次 recvfrom 缓冲。
RECV_BUF = 65535
DEFAULT_PORT = 17779


def _log(verbose: bool, message: str) -> None:
    if verbose:
        print(message, flush=True)


@dataclass
class Peer:
    """一个已注册端。observed_* **只能**由 recvfrom 的源地址填入。"""

    role: int
    nonce: str
    ticket: str
    candidates: List[P.Candidate]
    addr: Tuple[str, int]
    observed_address: str
    observed_port: int
    last_seen: float

    def refresh(self, addr: Tuple[str, int], observed_address: str, observed_port: int) -> None:
        self.addr = addr
        self.observed_address = observed_address
        self.observed_port = observed_port
        self.last_seen = time.time()

    def public_candidates(self) -> List[P.Candidate]:
        """给对端的候选：附上**服务端观测到的** observed endpoint。

        只给第一个可用候选挂 observed endpoint —— 打洞（9.2.2）要连的是
        「服务端看到的那个 NAT 映射」，不是客户端自报的本地地址。
        """
        out: List[P.Candidate] = []
        for candidate in self.candidates:
            clone = P.Candidate(
                transport=candidate.transport,
                path=candidate.path,
                address=candidate.address,
                port=candidate.port,
            )
            out.append(clone)
        if out and self.observed_address and self.observed_port:
            out[0].observed_address = self.observed_address
            out[0].observed_port = self.observed_port
        elif not out and self.observed_address and self.observed_port:
            # 客户端没报候选：至少把服务端看到的端点给出去，让对端有机会。
            out.append(
                P.Candidate(
                    transport=P.TRANSPORT_UDP,
                    path=P.PATH_WAN_IPV4,
                    address=self.observed_address,
                    port=self.observed_port,
                    observed_address=self.observed_address,
                    observed_port=self.observed_port,
                )
            )
        return out


@dataclass
class Session:
    session_id: str
    room_id: str
    ticket: str
    created_at: float
    host: Optional[Peer] = None
    guest: Optional[Peer] = None

    def last_activity(self) -> float:
        stamps = [self.created_at]
        for peer in (self.host, self.guest):
            if peer is not None:
                stamps.append(peer.last_seen)
        return max(stamps)

    def is_paired(self) -> bool:
        return self.host is not None and self.guest is not None


class RendezvousServer:
    """UDP rendezvous。纯标准库，无第三方依赖。"""

    def __init__(self, host: str = "0.0.0.0", port: int = DEFAULT_PORT, verbose: bool = False) -> None:
        self.host = host
        self.port = port
        self.verbose = verbose
        # session_id -> Session
        self.sessions: Dict[str, Session] = {}
        # room_id -> session_id（一个房间同时只有一个活动 session）
        self.rooms: Dict[str, str] = {}
        # addr -> (session_id, role)，用于 BYE / 重复注册判定
        self.by_addr: Dict[Tuple[str, int], Tuple[str, int]] = {}
        self.sock: Optional[socket.socket] = None
        self.errors_seen: Dict[int, int] = {}

    # ---- 生命周期 ----

    def bind(self) -> None:
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        sock.bind((self.host, self.port))
        sock.settimeout(0.5)
        self.sock = sock
        print("rendezvous listening on %s:%d" % (self.host, self.port), flush=True)

    def serve_forever(self) -> None:
        assert self.sock is not None
        while True:
            try:
                data, addr = self.sock.recvfrom(RECV_BUF)
            except socket.timeout:
                self.cleanup()
                continue
            except OSError:
                break
            self.handle_packet(data, addr)
            self.cleanup()

    # ---- 收包 ----

    def handle_packet(self, data: bytes, addr: Tuple[str, int]) -> None:
        """处理一个 UDP 包。

        observed endpoint **只**来自这里的 addr —— 即内核告诉我们的真实
        源地址 / 源端口。绝不相信包内自报的 observed 字段。
        """
        observed_address, observed_port = addr[0], addr[1]
        try:
            msg_type, session_id, msg = P.decode(data)
        except P.ProtocolError as exc:
            self._count_error(P.ERR_MALFORMED_PACKET)
            _log(
                self.verbose,
                "[rx] malformed from %s:%d (%s)" % (observed_address, observed_port, exc),
            )
            # session_id 未知时只能回空 session。
            self._send(
                addr,
                P.error_bytes("", P.ERR_MALFORMED_PACKET, "malformed packet"),
            )
            return

        if msg_type == P.REGISTER:
            self._handle_register(msg, addr, observed_address, observed_port)
        elif msg_type == P.BYE:
            self._handle_bye(session_id, addr)
        else:
            # 客户端不该向服务端发服务端专有消息。
            self._count_error(P.ERR_BAD_ROLE)
            self._send(addr, P.error_bytes(session_id, P.ERR_BAD_ROLE, "server-only message type"))
            _log(
                self.verbose,
                "[rx] " + P.safe_summary(msg_type, session_id, error_code=P.ERR_BAD_ROLE),
            )

    # ---- REGISTER ----

    def _handle_register(
        self,
        msg: P.Register,
        addr: Tuple[str, int],
        observed_address: str,
        observed_port: int,
    ) -> None:
        summary = P.safe_summary(
            P.REGISTER, msg.session_id, msg.role, msg.nonce, observed_address, observed_port
        )

        # 1) 基础形状校验：role / protocol / room_id / ticket / nonce。
        if not P.is_valid_role(msg.role):
            self._reject(addr, msg.session_id, P.ERR_BAD_ROLE, "bad role", summary)
            return
        if msg.protocol <= 0:
            self._reject(addr, msg.session_id, P.ERR_BAD_PROTOCOL, "bad protocol", summary)
            return
        if not P.is_valid_room_id(msg.room_id):
            self._reject(addr, msg.session_id, P.ERR_BAD_PROTOCOL, "bad room_id", summary)
            return
        # ticket 是房间门票，不是 rendezvous 身份。空 / 非法形状一律拒绝，
        # 否则「拿 room_id 就能加入」。
        if not P.is_valid_ticket(msg.ticket):
            self._reject(addr, msg.session_id, P.ERR_BAD_TICKET, "bad ticket", summary)
            return
        if not P.is_valid_nonce(msg.nonce):
            self._reject(addr, msg.session_id, P.ERR_BAD_PROTOCOL, "bad nonce", summary)
            return

        # 2) Host：建房（room_id 上不允许已有活动 session）。
        if msg.role == P.ROLE_HOST:
            existing_id = self.rooms.get(msg.room_id)
            if existing_id is not None and existing_id in self.sessions:
                session = self.sessions[existing_id]
                # 同一个 Host 重发 = 幂等刷新；不同来源 = 重复 Host 注册，明确拒绝。
                if session.host is not None and session.host.addr != addr:
                    self._reject(
                        addr,
                        existing_id,
                        P.ERR_DUPLICATE_PEER,
                        "host already registered for room",
                        summary,
                    )
                    return
                if session.host is not None and session.host.nonce != msg.nonce:
                    self._reject(
                        addr,
                        existing_id,
                        P.ERR_DUPLICATE_PEER,
                        "host already registered for room",
                        summary,
                    )
                    return
                session.host.refresh(addr, observed_address, observed_port)
                session.host.candidates = msg.candidates
                _log(self.verbose, "[host] refresh " + summary)
                self._send_registered(session, session.host)
                self._maybe_pair(session)
                return

            session = self._new_session(msg.room_id, msg.ticket)
            session.host = Peer(
                role=P.ROLE_HOST,
                nonce=msg.nonce,
                ticket=msg.ticket,
                candidates=msg.candidates,
                addr=addr,
                observed_address=observed_address,
                observed_port=observed_port,
                last_seen=time.time(),
            )
            self.by_addr[addr] = (session.session_id, P.ROLE_HOST)
            _log(self.verbose, "[host] new " + summary)
            self._send_registered(session, session.host)
            return

        # 3) Guest：加入已存在的 room。
        session_id = self.rooms.get(msg.room_id)
        if session_id is None or session_id not in self.sessions:
            self._reject(
                addr, "", P.ERR_SESSION_NOT_FOUND, "no session for room", summary
            )
            return
        session = self.sessions[session_id]
        # 必须验证 session 是否允许该 ticket。
        if session.ticket != msg.ticket:
            self._reject(
                addr, session.session_id, P.ERR_BAD_TICKET, "ticket mismatch", summary
            )
            return
        # 一个 session 最多一个 Guest。重复 Guest 不创建第二个。
        if session.guest is not None:
            if session.guest.addr == addr and session.guest.nonce == msg.nonce:
                # 同一 Guest 重发 = 幂等刷新。
                session.guest.refresh(addr, observed_address, observed_port)
                session.guest.candidates = msg.candidates
                _log(self.verbose, "[guest] refresh " + summary)
                self._send_registered(session, session.guest)
                self._maybe_pair(session)
                return
            self._reject(
                addr, session.session_id, P.ERR_DUPLICATE_PEER, "guest already registered", summary
            )
            return
        if session.host is None:
            self._reject(
                addr, session.session_id, P.ERR_SESSION_NOT_FOUND, "session has no host", summary
            )
            return

        session.guest = Peer(
            role=P.ROLE_GUEST,
            nonce=msg.nonce,
            ticket=msg.ticket,
            candidates=msg.candidates,
            addr=addr,
            observed_address=observed_address,
            observed_port=observed_port,
            last_seen=time.time(),
        )
        self.by_addr[addr] = (session.session_id, P.ROLE_GUEST)
        _log(self.verbose, "[guest] new " + summary)
        self._send_registered(session, session.guest)
        self._maybe_pair(session)

    # ---- BYE ----

    def _handle_bye(self, session_id: str, addr: Tuple[str, int]) -> None:
        session = self.sessions.get(session_id)
        if session is None:
            _log(self.verbose, "[bye] unknown session " + (session_id or "-"))
            return
        if session.host is not None and session.host.addr == addr:
            session.host = None
        elif session.guest is not None and session.guest.addr == addr:
            session.guest = None
        self.by_addr.pop(addr, None)
        _log(self.verbose, "[bye] session=" + session_id)
        if session.host is None and session.guest is None:
            self._drop_session(session_id)

    # ---- 配对 ----

    def _maybe_pair(self, session: Session) -> None:
        """双方都在时，把各自的候选 + observed endpoint 交换出去。

        **本阶段不执行任何打洞**：只是把真实连接信息交给两侧已有的
        P2PConnection.apply_remote_candidates()。
        """
        if not session.is_paired():
            return
        assert session.host is not None and session.guest is not None
        # Guest 先收到（它刚注册，正在等）。
        self._send_candidates(session, session.guest, session.host)
        self._send_candidates(session, session.host, session.guest)
        _log(self.verbose, "[pair] session=" + session.session_id)

    def _send_candidates(self, session: Session, to_peer: Peer, other: Peer) -> None:
        msg = P.Candidates(
            session_id=session.session_id,
            nonce=to_peer.nonce,
            remote_nonce=other.nonce,
            remote_role=other.role,
            observed_address=other.observed_address,
            observed_port=other.observed_port,
            candidates=other.public_candidates(),
        )
        self._send(to_peer.addr, P.encode_candidates(msg))

    def _send_registered(self, session: Session, peer: Peer) -> None:
        msg = P.Registered(
            session_id=session.session_id,
            nonce=peer.nonce,
            observed_address=peer.observed_address,
            observed_port=peer.observed_port,
            candidates=[],
        )
        self._send(peer.addr, P.encode_registered(msg))

    # ---- 内部 ----

    def _new_session(self, room_id: str, ticket: str) -> Session:
        session_id = secrets.token_hex(P.SESSION_ID_HEX_LEN // 2)
        session = Session(
            session_id=session_id,
            room_id=room_id,
            ticket=ticket,
            created_at=time.time(),
        )
        self.sessions[session_id] = session
        self.rooms[room_id] = session_id
        return session

    def _drop_session(self, session_id: str) -> None:
        session = self.sessions.pop(session_id, None)
        if session is None:
            return
        if self.rooms.get(session.room_id) == session_id:
            self.rooms.pop(session.room_id, None)
        for peer in (session.host, session.guest):
            if peer is not None:
                self.by_addr.pop(peer.addr, None)
        _log(self.verbose, "[cleanup] dropped session=" + session_id)

    def _reject(
        self,
        addr: Tuple[str, int],
        session_id: str,
        code: int,
        detail: str,
        summary: str = "",
    ) -> None:
        self._count_error(code)
        self._send(addr, P.error_bytes(session_id, code, detail))
        _log(
            self.verbose,
            ("[reject] " + summary + " -> " + P.error_name(code)) if summary
            else "[reject] session=%s -> %s" % (session_id or "-", P.error_name(code)),
        )

    def _count_error(self, code: int) -> None:
        self.errors_seen[code] = self.errors_seen.get(code, 0) + 1

    def _send(self, addr: Tuple[str, int], payload: bytes) -> None:
        if self.sock is None or not payload:
            return
        try:
            self.sock.sendto(payload, addr)
        except OSError:
            pass

    # ---- cleanup ----

    def cleanup(self, now: Optional[float] = None) -> int:
        """回收空闲 session。返回被回收的数量。

        只影响超时的那一个 session，不碰其它 session。
        """
        now = time.time() if now is None else now
        stale = [
            sid
            for sid, session in self.sessions.items()
            if now - session.last_activity() >= SESSION_IDLE_TIMEOUT_SEC
        ]
        for session_id in stale:
            session = self.sessions.get(session_id)
            if session is None:
                continue
            # 通知还在线的一侧（通常都已静默，尽力而为）。
            for peer in (session.host, session.guest):
                if peer is not None:
                    self._send(
                        peer.addr,
                        P.error_bytes(session_id, P.ERR_TIMEOUT, "session idle timeout"),
                    )
            self._drop_session(session_id)
        return len(stale)

    def session_count(self) -> int:
        return len(self.sessions)


def main() -> int:
    parser = argparse.ArgumentParser(description="WPG minimal rendezvous service")
    parser.add_argument("--host", default="0.0.0.0")
    parser.add_argument("--port", type=int, default=DEFAULT_PORT)
    parser.add_argument("--verbose", action="store_true")
    args = parser.parse_args()

    server = RendezvousServer(host=args.host, port=args.port, verbose=args.verbose)
    server.bind()
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nrendezvous stopped", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
