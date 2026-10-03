extends RefCounted
class_name P2PUDPProbe

## UDP 探针包（Phase 9.2）：仅用于「证明双向 UDP 可达」。
##
## 职责：
## - 编解码 probe packet（二进制，非 JSON）
## - 发送 / 接收 probe
## - 校验 session_id + nonce + expected remote role
## - 计算 RTT
## - **不**创建 ENet、不接管 SceneTree.multiplayer、不处理 Lobby/Combat
##
## 包格式（大端）：
##   u32 magic          = 0x50505242 ("PPRB" = P2P Probe)
##   u8  version        = 1
##   u8  msg_type       = PROBE / ACK
##   u32 session_id_len | session_id (hex)
##   u32 nonce_len      | nonce (hex)
##   u8  role           = sender role (HOST=0 / GUEST=1)
##   u64 timestamp_ms   = 发送时刻（毫秒，用于 RTT）
##   u8  reserved       = 0（对齐/扩展）
##
## msg_type:
##   PROBE = 0  （主动探测）
##   ACK   = 1  （收到 probe 后回复，携带原 probe 的 timestamp）
##
## 魔术字与版本号与 rendezvous 协议**完全独立**，避免误收。

const MAGIC: int = 0x50505242  # "PPRB"
const VERSION: int = 1
const NONCE_BYTES: int = 16

enum MsgType {
	PROBE = 0,
	ACK = 1,
}

enum Role {
	HOST = 0,
	GUEST = 1,
}

enum DecodeError {
	OK,
	EMPTY,
	BAD_MAGIC,
	BAD_VERSION,
	BAD_TYPE,
	TRUNCATED,
	BAD_FIELD,
	INVALID_SESSION_ID,
	INVALID_NONCE,
	INVALID_ROLE,
}

class Decoded extends RefCounted:
	var error: int = DecodeError.OK
	var msg_type: int = -1
	var session_id: String = ""
	var nonce: String = ""
	var role: int = Role.GUEST
	var timestamp_ms: int = 0
	var original_timestamp_ms: int = 0  # ACK 携带的原 probe 时间戳

	func is_ok() -> bool:
		return error == DecodeError.OK

	func is_probe() -> bool:
		return msg_type == MsgType.PROBE

	func is_ack() -> bool:
		return msg_type == MsgType.ACK

## 编码 PROBE 包。
static func encode_probe(
	session_id: String,
	nonce: String,
	role: int,
	timestamp_ms: int
) -> PackedByteArray:
	var buf: StreamPeerBuffer = StreamPeerBuffer.new()
	buf.big_endian = true
	buf.put_u32(MAGIC)
	buf.put_u8(VERSION)
	buf.put_u8(MsgType.PROBE)
	_put_string(buf, session_id)
	_put_string(buf, nonce)
	buf.put_u8(role)
	buf.put_u64(timestamp_ms)
	buf.put_u8(0)  # reserved
	return buf.data_array

## 编码 ACK 包（回显原 probe 的 timestamp）。
static func encode_ack(
	session_id: String,
	nonce: String,
	role: int,
	timestamp_ms: int,
	original_timestamp_ms: int
) -> PackedByteArray:
	var buf: StreamPeerBuffer = StreamPeerBuffer.new()
	buf.big_endian = true
	buf.put_u32(MAGIC)
	buf.put_u8(VERSION)
	buf.put_u8(MsgType.ACK)
	_put_string(buf, session_id)
	_put_string(buf, nonce)
	buf.put_u8(role)
	buf.put_u64(timestamp_ms)
	buf.put_u64(original_timestamp_ms)
	return buf.data_array

static func _put_string(buf: StreamPeerBuffer, value: String) -> void:
	var bytes: PackedByteArray = value.to_utf8_buffer()
	buf.put_u32(bytes.size())
	if not bytes.is_empty():
		buf.put_data(bytes)

## 解码 probe / ack 包。
static func decode(raw: PackedByteArray) -> Decoded:
	var out: Decoded = Decoded.new()
	_truncated = false
	if raw.is_empty():
		out.error = DecodeError.EMPTY
		return out
	if raw.size() < 10:  # magic + version + type + sid_len(4) 至少
		out.error = DecodeError.TRUNCATED
		return out
	var buf: StreamPeerBuffer = StreamPeerBuffer.new()
	buf.big_endian = true
	buf.data_array = raw
	buf.seek(0)
	if buf.get_u32() != MAGIC:
		out.error = DecodeError.BAD_MAGIC
		return out
	if buf.get_u8() != VERSION:
		out.error = DecodeError.BAD_VERSION
		return out
	var msg_type: int = buf.get_u8()
	if msg_type != MsgType.PROBE and msg_type != MsgType.ACK:
		out.error = DecodeError.BAD_TYPE
		return out
	out.msg_type = msg_type
	out.session_id = _get_string(buf)
	if not _is_valid_session_id(out.session_id):
		out.error = DecodeError.INVALID_SESSION_ID
		return out
	out.nonce = _get_string(buf)
	if not _is_valid_nonce(out.nonce):
		out.error = DecodeError.INVALID_NONCE
		return out
	out.role = buf.get_u8()
	if out.role != Role.HOST and out.role != Role.GUEST:
		out.error = DecodeError.INVALID_ROLE
		return out
	out.timestamp_ms = buf.get_u64()
	if msg_type == MsgType.ACK:
		if buf.get_available_bytes() < 8:
			_truncated = true
			out.error = DecodeError.TRUNCATED
			return out
		out.original_timestamp_ms = buf.get_u64()
	if _truncated or buf.get_available_bytes() < 0 or buf.get_position() > raw.size():
		out.error = DecodeError.TRUNCATED
		return out
	out.error = DecodeError.OK
	return out

static var _truncated: bool = false

static func _get_string(buf: StreamPeerBuffer) -> String:
	if buf.get_available_bytes() < 4:
		_truncated = true
		return ""
	var size: int = buf.get_u32()
	if size < 0 or size > 4096:
		_truncated = true
		return ""
	if size == 0:
		return ""
	if buf.get_available_bytes() < size:
		_truncated = true
		return ""
	var data: PackedByteArray = buf.get_data(size)[1]
	return data.get_string_from_utf8()

static func _is_valid_session_id(value: String) -> bool:
	if value.length() != 16:
		return false
	return _is_hex(value)

static func _is_valid_nonce(value: String) -> bool:
	if value.length() != NONCE_BYTES * 2:
		return false
	return _is_hex(value)

static func _is_hex(value: String) -> bool:
	for i: int in value.length():
		var c: int = value.unicode_at(i)
		var is_digit: bool = c >= 48 and c <= 57
		var is_lower: bool = c >= 97 and c <= 102
		var is_upper: bool = c >= 65 and c <= 70
		if not (is_digit or is_lower or is_upper):
			return false
	return not value.is_empty()

## 校验 decoded 是否符合预期（session_id + nonce + 期望的对端 role）。
##
## Host 预期 remote_role = GUEST
## Guest 预期 remote_role = HOST
static func validate_expectation(decoded: Decoded, expected_session_id: String, expected_nonce: String, expected_remote_role: int) -> bool:
	if not decoded.is_ok():
		return false
	if decoded.session_id != expected_session_id:
		return false
	if decoded.nonce != expected_nonce:
		return false
	if decoded.role != expected_remote_role:
		return false
	return true

## 计算 RTT（毫秒）：now_ms - original_timestamp_ms。
static func calculate_rtt(now_ms: int, original_timestamp_ms: int) -> int:
	var rtt: int = now_ms - original_timestamp_ms
	return maxi(rtt, 0)

## 探针套接字管理器：bind / send / receive / close。
class ProbeSocket extends RefCounted:
	var _udp: PacketPeerUDP = null
	var _bound_port: int = 0

	func bind(port: int = 0) -> bool:
		close()
		_udp = PacketPeerUDP.new()
		var err: Error = _udp.bind(port)
		if err != OK:
			_udp = null
			return false
		_bound_port = _udp.get_local_port()
		return true

	func get_local_port() -> int:
		return _bound_port

	func send_to(address: String, port: int, packet: PackedByteArray) -> bool:
		if _udp == null:
			return false
		_udp.set_dest_address(address, port)
		_udp.put_packet(packet)
		return true

	func receive() -> Array:
		## 返回 [packet: PackedByteArray, src_address: String, src_port: int]
		## PacketPeerUDP 不直接给源地址，需用到 PacketPeerUDP.get_packet_with_address()
		## 但 Godot 4 的 PacketPeerUDP 只有 get_packet()；需用到更底层的 API 或近似处理。
		## 这里用近似：若只有一个对端，get_packet() 足够；多对端场景由上层区分。
		## 真实场景下，打洞是一对一，故可行。
		if _udp == null:
			return []
		if _udp.get_available_packet_count() == 0:
			return []
		var packet: PackedByteArray = _udp.get_packet()
		if packet.is_empty():
			return []
		## 注意：Godot 4.2+ 可用 get_packet_with_address()，这里兼容写法
		## 暂时返回空地址，由上层根据已知对端地址匹配
		return [packet, "", 0]

	func close() -> void:
		if _udp != null:
			_udp.close()
			_udp = null
		_bound_port = 0

	func is_open() -> bool:
		return _udp != null

## 日志安全摘要（不含完整 nonce/ticket）。
static func safe_summary(decoded: Decoded) -> String:
	var role_str: String = "host" if decoded.role == Role.HOST else "guest"
	var type_str: String = "probe" if decoded.msg_type == MsgType.PROBE else "ack"
	return "type=%s session=%s nonce=%s role=%s ts=%d" % [
		type_str,
		decoded.session_id if not decoded.session_id.is_empty() else "-",
		RendezvousContract.nonce_summary(decoded.nonce),
		role_str,
		decoded.timestamp_ms,
	]