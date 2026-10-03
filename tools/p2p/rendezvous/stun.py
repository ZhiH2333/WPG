"""最小 STUN Binding Request 客户端（Phase 9.2.1，J 节）。

目的**只有一个**：拿到 NAT 映射后的 observed_address / observed_port，
以便填进 RendezvousContract.Candidate.observed_address / observed_port。

只实现当前需要的最小 subset（RFC 5389）：
- Binding Request（type 0x0001）
- magic cookie 校验
- 12 字节 transaction id
- XOR-MAPPED-ADDRESS（0x0020）与 MAPPED-ADDRESS（0x0001）解析

**明确不做**：完整 STUN server、ICE、TURN、WebRTC、任何第三方 NAT 库。

没有 STUN 应答时必须返回 None —— **绝不**用本地地址伪造 observed endpoint。
"""

from __future__ import annotations

import os
import socket
import struct
from dataclasses import dataclass
from typing import Optional, Tuple

STUN_MAGIC_COOKIE = 0x2112A442
BINDING_REQUEST = 0x0001
BINDING_SUCCESS = 0x0101
ATTR_MAPPED_ADDRESS = 0x0001
ATTR_XOR_MAPPED_ADDRESS = 0x0020
HEADER_LEN = 20
TRANSACTION_ID_LEN = 12
DEFAULT_STUN_PORT = 19302


class StunError(Exception):
    """STUN 应答非法 / 不可用。"""


@dataclass
class StunResult:
    address: str
    port: int

    def is_usable(self) -> bool:
        return bool(self.address) and 1 <= self.port <= 65535


def make_transaction_id() -> bytes:
    """12 字节随机 transaction id。"""
    return os.urandom(TRANSACTION_ID_LEN)


def build_binding_request(transaction_id: Optional[bytes] = None) -> bytes:
    """构造最小 Binding Request。"""
    tid = transaction_id if transaction_id is not None else make_transaction_id()
    if len(tid) != TRANSACTION_ID_LEN:
        raise StunError("transaction id must be 12 bytes")
    # type(2) | length(2) | magic cookie(4) | transaction id(12)
    return struct.pack(">HHI", BINDING_REQUEST, 0, STUN_MAGIC_COOKIE) + tid


def parse_binding_response(data: bytes, transaction_id: bytes) -> StunResult:
    """解析 Binding Success Response，返回观测端点。

    只认 XOR-MAPPED-ADDRESS，回退 MAPPED-ADDRESS。
    任何形状问题都抛 StunError，绝不返回伪造值。
    """
    if len(data) < HEADER_LEN:
        raise StunError("response too short")
    msg_type, length, cookie = struct.unpack_from(">HHI", data, 0)
    if cookie != STUN_MAGIC_COOKIE:
        raise StunError("bad magic cookie")
    if msg_type != BINDING_SUCCESS:
        raise StunError("not a binding success response (0x%04x)" % msg_type)
    if len(data) < HEADER_LEN + length:
        raise StunError("truncated body")
    body_tid = data[8:20]
    if body_tid != transaction_id:
        raise StunError("transaction id mismatch")

    offset = HEADER_LEN
    end = HEADER_LEN + length
    mapped: Optional[StunResult] = None
    xor_mapped: Optional[StunResult] = None
    while offset + 4 <= end:
        attr_type, attr_len = struct.unpack_from(">HH", data, offset)
        offset += 4
        if offset + attr_len > end:
            raise StunError("attribute overruns body")
        value = data[offset : offset + attr_len]
        offset += attr_len
        # 属性按 4 字节对齐。
        if attr_len % 4:
            offset += 4 - (attr_len % 4)
        if attr_type == ATTR_XOR_MAPPED_ADDRESS:
            xor_mapped = _parse_xor_mapped(value)
        elif attr_type == ATTR_MAPPED_ADDRESS:
            mapped = _parse_mapped(value)

    if xor_mapped is not None:
        return xor_mapped
    if mapped is not None:
        return mapped
    raise StunError("no mapped address attribute")


def _parse_xor_mapped(value: bytes) -> StunResult:
    if len(value) < 8:
        raise StunError("xor-mapped too short")
    family = value[1]
    port = struct.unpack_from(">H", value, 2)[0] ^ (STUN_MAGIC_COOKIE >> 16)
    if family == 0x01:  # IPv4
        raw = struct.unpack_from(">I", value, 4)[0] ^ STUN_MAGIC_COOKIE
        address = "%d.%d.%d.%d" % (
            (raw >> 24) & 0xFF,
            (raw >> 16) & 0xFF,
            (raw >> 8) & 0xFF,
            raw & 0xFF,
        )
    elif family == 0x02:  # IPv6
        if len(value) < 20:
            raise StunError("xor-mapped ipv6 too short")
        mask = struct.pack(">I", STUN_MAGIC_COOKIE) + value[4:20]
        xored = bytes(a ^ b for a, b in zip(value[4:20], mask))
        address = ":".join("%02x%02x" % (xored[i], xored[i + 1]) for i in range(0, 16, 2))
    else:
        raise StunError("unknown address family %d" % family)
    return StunResult(address=address, port=port)


def _parse_mapped(value: bytes) -> StunResult:
    if len(value) < 8:
        raise StunError("mapped too short")
    family = value[1]
    port = struct.unpack_from(">H", value, 2)[0]
    if family == 0x01:
        address = socket.inet_ntoa(value[4:8])
    elif family == 0x02:
        if len(value) < 20:
            raise StunError("mapped ipv6 too short")
        address = socket.inet_ntop(socket.AF_INET6, value[4:20])
    else:
        raise StunError("unknown address family %d" % family)
    return StunResult(address=address, port=port)


def query(
    host: str,
    port: int = DEFAULT_STUN_PORT,
    timeout_sec: float = 1.5,
    sock: Optional[socket.socket] = None,
) -> Optional[StunResult]:
    """向 STUN 服务器发一次 Binding Request。

    失败（超时 / 无应答 / 非法应答）返回 **None** —— 调用方必须保持
    observed 字段为空，不得伪造。
    """
    own_sock = sock is None
    sock = sock or socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.settimeout(timeout_sec)
    tid = make_transaction_id()
    try:
        sock.sendto(build_binding_request(tid), (host, port))
        data, _addr = sock.recvfrom(2048)
        return parse_binding_response(data, tid)
    except (OSError, StunError):
        return None
    finally:
        if own_sock:
            sock.close()


def query_first(servers: Tuple[str, ...], timeout_sec: float = 1.5) -> Optional[StunResult]:
    """依次尝试多个 STUN 服务器，第一个成功即返回。全失败返回 None。"""
    for host in servers:
        result = query(host, timeout_sec=timeout_sec)
        if result is not None and result.is_usable():
            return result
    return None


DEFAULT_STUN_SERVERS = (
    "stun.l.google.com",
    "stun1.l.google.com",
)
