"""Rendezvous 协议编解码（Phase 9.2.1）。

本模块是 lobby/rendezvous_contract.gd 的**逐字节镜像**。两边必须保持一致，
否则客户端与服务端无法互通。任何 wire 改动都必须同时改这两处并跑
tools/p2p/rendezvous/test_server.py 与 tests/rendezvous_contract_test.gd。

v2 包格式（大端）：
    u32 magic | u8 version | u8 type | u32 sid_len | session_id | <payload>

    REGISTER   payload: u8 role | u8 protocol | str nonce | str room_id | str ticket
                        | u32 n | (candidates...)
    REGISTERED payload: str nonce | u16 observed_port | str observed_address
                        | u32 n | (candidates...)
    PEER_READY payload: str nonce | str remote_nonce | u8 remote_role
                        | u16 observed_port | str observed_address
    CANDIDATES payload: str nonce | str remote_nonce | u8 remote_role
                        | u16 observed_port | str observed_address
                        | u32 n | (remote candidates...)
    ERROR      payload: u8 error_code | str detail
    BYE        payload: (empty)

    str       = u32 byte_len | utf8 bytes
    candidate = u8 transport | u8 path | u16 port | u16 obs_port
                | str address | str observed_address

设计约束：
- **不使用 ad-hoc JSON**：有明确 message type 与 protocol version。
- 纯标准库、无第三方依赖。
- ticket 是房间门票，不是 rendezvous 的长期身份。
"""

from __future__ import annotations

import struct
from dataclasses import dataclass, field
from typing import List, Optional, Tuple

MAGIC = 0x57504752  # "WPGR"
VERSION = 2
NONCE_BYTES = 16
SESSION_ID_HEX_LEN = 16
MAX_STR_BYTES = 4096
MAX_CANDIDATES = 32

# ---- 消息类型 ----
REGISTER = 0
REGISTERED = 1
PEER_READY = 2
CANDIDATES = 3
ERROR = 4
BYE = 5

MSG_TYPE_NAMES = {
    REGISTER: "register",
    REGISTERED: "registered",
    PEER_READY: "peer_ready",
    CANDIDATES: "candidates",
    ERROR: "error",
    BYE: "bye",
}

# ---- 角色 ----
ROLE_HOST = 0
ROLE_GUEST = 1


def role_name(role: int) -> str:
    return "host" if role == ROLE_HOST else "guest"


# ---- 错误码（必须与 RendezvousContract.ErrorCode 一致）----
ERR_NONE = 0
ERR_SESSION_NOT_FOUND = 1
ERR_SESSION_FULL = 2
ERR_BAD_PROTOCOL = 3
ERR_BAD_TICKET = 4
ERR_BAD_ROLE = 5
ERR_DUPLICATE_PEER = 6
ERR_MALFORMED_PACKET = 7
ERR_TIMEOUT = 8
ERR_ROOM_MISMATCH = 9

ERROR_NAMES = {
    ERR_NONE: "NONE",
    ERR_SESSION_NOT_FOUND: "SESSION_NOT_FOUND",
    ERR_SESSION_FULL: "SESSION_FULL",
    ERR_BAD_PROTOCOL: "BAD_PROTOCOL",
    ERR_BAD_TICKET: "BAD_TICKET",
    ERR_BAD_ROLE: "BAD_ROLE",
    ERR_DUPLICATE_PEER: "DUPLICATE_PEER",
    ERR_MALFORMED_PACKET: "MALFORMED_PACKET",
    ERR_TIMEOUT: "TIMEOUT",
    ERR_ROOM_MISMATCH: "ROOM_MISMATCH",
}


def error_name(code: int) -> str:
    return ERROR_NAMES.get(code, "UNKNOWN")


# ---- 传输类型 ----
TRANSPORT_UDP = 0

# ---- 路径（必须与 LobbyPlayer.Path 一致）----
PATH_LAN_IPV4 = 0
PATH_IPV6 = 1
PATH_WAN_IPV4 = 2


class ProtocolError(Exception):
    """包无法解析。调用方据此回 MALFORMED_PACKET，绝不静默。"""


@dataclass
class Candidate:
    transport: int = TRANSPORT_UDP
    path: int = PATH_LAN_IPV4
    address: str = ""
    port: int = 0
    observed_address: str = ""
    observed_port: int = 0

    def is_usable(self) -> bool:
        return bool(self.address) and 1 <= self.port <= 65535

    def has_observed_endpoint(self) -> bool:
        return bool(self.observed_address) and 1 <= self.observed_port <= 65535


@dataclass
class Register:
    session_id: str = ""
    role: int = ROLE_GUEST
    protocol: int = 0
    nonce: str = ""
    room_id: str = ""
    ticket: str = ""
    candidates: List[Candidate] = field(default_factory=list)


@dataclass
class Registered:
    session_id: str = ""
    nonce: str = ""
    observed_address: str = ""
    observed_port: int = 0
    candidates: List[Candidate] = field(default_factory=list)


@dataclass
class PeerReady:
    session_id: str = ""
    nonce: str = ""
    remote_nonce: str = ""
    remote_role: int = ROLE_GUEST
    observed_address: str = ""
    observed_port: int = 0


@dataclass
class Candidates:
    session_id: str = ""
    nonce: str = ""
    remote_nonce: str = ""
    remote_role: int = ROLE_GUEST
    observed_address: str = ""
    observed_port: int = 0
    candidates: List[Candidate] = field(default_factory=list)


@dataclass
class ErrorMsg:
    session_id: str = ""
    code: int = ERR_NONE
    detail: str = ""


@dataclass
class Bye:
    session_id: str = ""


# ---- 写 ----

def _put_string(value: str) -> bytes:
    raw = value.encode("utf-8")
    if len(raw) > MAX_STR_BYTES:
        raise ProtocolError("string too long")
    return struct.pack(">I", len(raw)) + raw


def _put_candidates(candidates: List[Candidate]) -> bytes:
    if len(candidates) > MAX_CANDIDATES:
        raise ProtocolError("too many candidates")
    out = struct.pack(">I", len(candidates))
    for c in candidates:
        out += struct.pack(
            ">BBHH",
            c.transport & 0xFF,
            c.path & 0xFF,
            max(0, min(65535, c.port)),
            max(0, min(65535, c.observed_port)),
        )
        out += _put_string(c.address)
        out += _put_string(c.observed_address)
    return out


def _begin(msg_type: int, session_id: str) -> bytes:
    return (
        struct.pack(">IBB", MAGIC, VERSION, msg_type)
        + _put_string(session_id)
    )


def encode_register(msg: Register) -> bytes:
    return (
        _begin(REGISTER, msg.session_id)
        + struct.pack(">BB", msg.role & 0xFF, msg.protocol & 0xFF)
        + _put_string(msg.nonce)
        + _put_string(msg.room_id)
        + _put_string(msg.ticket)
        + _put_candidates(msg.candidates)
    )


def encode_registered(msg: Registered) -> bytes:
    return (
        _begin(REGISTERED, msg.session_id)
        + _put_string(msg.nonce)
        + struct.pack(">H", max(0, min(65535, msg.observed_port)))
        + _put_string(msg.observed_address)
        + _put_candidates(msg.candidates)
    )


def encode_peer_ready(msg: PeerReady) -> bytes:
    return (
        _begin(PEER_READY, msg.session_id)
        + _put_string(msg.nonce)
        + _put_string(msg.remote_nonce)
        + struct.pack(">B", msg.remote_role & 0xFF)
        + struct.pack(">H", max(0, min(65535, msg.observed_port)))
        + _put_string(msg.observed_address)
    )


def encode_candidates(msg: Candidates) -> bytes:
    return (
        _begin(CANDIDATES, msg.session_id)
        + _put_string(msg.nonce)
        + _put_string(msg.remote_nonce)
        + struct.pack(">B", msg.remote_role & 0xFF)
        + struct.pack(">H", max(0, min(65535, msg.observed_port)))
        + _put_string(msg.observed_address)
        + _put_candidates(msg.candidates)
    )


def encode_error(msg: ErrorMsg) -> bytes:
    return _begin(ERROR, msg.session_id) + struct.pack(">B", msg.code & 0xFF) + _put_string(msg.detail)


def error_bytes(session_id: str, code: int, detail: str = "") -> bytes:
    """便捷封装：服务端内部大量回错误，避免到处 new ErrorMsg。"""
    return encode_error(ErrorMsg(session_id=session_id, code=code, detail=detail))


def encode_bye(msg: Bye) -> bytes:
    return _begin(BYE, msg.session_id)


# ---- 读 ----

class _Reader:
    def __init__(self, data: bytes) -> None:
        self.data = data
        self.pos = 0

    def remaining(self) -> int:
        return len(self.data) - self.pos

    def u8(self) -> int:
        if self.remaining() < 1:
            raise ProtocolError("truncated u8")
        value = self.data[self.pos]
        self.pos += 1
        return value

    def u16(self) -> int:
        if self.remaining() < 2:
            raise ProtocolError("truncated u16")
        (value,) = struct.unpack_from(">H", self.data, self.pos)
        self.pos += 2
        return value

    def u32(self) -> int:
        if self.remaining() < 4:
            raise ProtocolError("truncated u32")
        (value,) = struct.unpack_from(">I", self.data, self.pos)
        self.pos += 4
        return value

    def string(self) -> str:
        size = self.u32()
        if size > MAX_STR_BYTES:
            raise ProtocolError("string too long")
        if self.remaining() < size:
            raise ProtocolError("truncated string")
        raw = self.data[self.pos : self.pos + size]
        self.pos += size
        return raw.decode("utf-8", errors="replace")

    def candidates(self) -> List[Candidate]:
        count = self.u32()
        if count > MAX_CANDIDATES:
            raise ProtocolError("too many candidates")
        out: List[Candidate] = []
        for _ in range(count):
            if self.remaining() < 6:
                raise ProtocolError("truncated candidate")
            transport = self.u8()
            path = self.u8()
            port = self.u16()
            observed_port = self.u16()
            address = self.string()
            observed_address = self.string()
            out.append(
                Candidate(
                    transport=transport,
                    path=path,
                    address=address,
                    port=port,
                    observed_address=observed_address,
                    observed_port=observed_port,
                )
            )
        return out


def decode(data: bytes) -> Tuple[int, str, object]:
    """返回 (msg_type, session_id, parsed)。解析失败抛 ProtocolError。"""
    r = _Reader(data)
    magic = r.u32()
    if magic != MAGIC:
        raise ProtocolError("bad magic")
    version = r.u8()
    if version != VERSION:
        raise ProtocolError("bad version %d" % version)
    msg_type = r.u8()
    session_id = r.string()

    if msg_type == REGISTER:
        msg = Register(session_id=session_id)
        msg.role = r.u8()
        msg.protocol = r.u8()
        msg.nonce = r.string()
        msg.room_id = r.string()
        msg.ticket = r.string()
        msg.candidates = r.candidates()
        return msg_type, session_id, msg
    if msg_type == REGISTERED:
        msg = Registered(session_id=session_id)
        msg.nonce = r.string()
        msg.observed_port = r.u16()
        msg.observed_address = r.string()
        msg.candidates = r.candidates()
        return msg_type, session_id, msg
    if msg_type == PEER_READY:
        msg = PeerReady(session_id=session_id)
        msg.nonce = r.string()
        msg.remote_nonce = r.string()
        msg.remote_role = r.u8()
        msg.observed_port = r.u16()
        msg.observed_address = r.string()
        return msg_type, session_id, msg
    if msg_type == CANDIDATES:
        msg = Candidates(session_id=session_id)
        msg.nonce = r.string()
        msg.remote_nonce = r.string()
        msg.remote_role = r.u8()
        msg.observed_port = r.u16()
        msg.observed_address = r.string()
        msg.candidates = r.candidates()
        return msg_type, session_id, msg
    if msg_type == ERROR:
        msg = ErrorMsg(session_id=session_id)
        msg.code = r.u8()
        msg.detail = r.string()
        return msg_type, session_id, msg
    if msg_type == BYE:
        return msg_type, session_id, Bye(session_id=session_id)
    raise ProtocolError("bad type %d" % msg_type)


# ---- 校验（与 RendezvousContract 同标准）----

def _is_hex(value: str) -> bool:
    if not value:
        return False
    return all(c in "0123456789abcdefABCDEF" for c in value)


def is_valid_nonce(value: str) -> bool:
    return len(value) == NONCE_BYTES * 2 and _is_hex(value)


def is_valid_session_id(value: str) -> bool:
    return len(value) == SESSION_ID_HEX_LEN and _is_hex(value)


def is_valid_room_id(value: str) -> bool:
    if not value or len(value) > 32:
        return False
    return all(c.isalnum() or c in "-_" for c in value)


def is_valid_ticket(value: str) -> bool:
    return 8 <= len(value) <= 64 and _is_hex(value)


def is_valid_role(value: int) -> bool:
    return value in (ROLE_HOST, ROLE_GUEST)


# ---- 日志安全摘要 ----

def nonce_summary(nonce: str) -> str:
    """日志只能留 nonce 前 8 位 —— 绝不输出完整凭据。"""
    return nonce[:8] if nonce else "-"


def safe_summary(
    msg_type: int,
    session_id: str = "",
    role: int = ROLE_GUEST,
    nonce: str = "",
    observed_address: str = "",
    observed_port: int = 0,
    error_code: int = ERR_NONE,
) -> str:
    """**绝不包含 ticket** 的一行日志。"""
    return (
        "type=%s session=%s role=%s nonce=%s observed=%s:%d error=%s"
        % (
            MSG_TYPE_NAMES.get(msg_type, "unknown"),
            session_id or "-",
            role_name(role),
            nonce_summary(nonce),
            observed_address or "-",
            observed_port,
            error_name(error_code),
        )
    )
