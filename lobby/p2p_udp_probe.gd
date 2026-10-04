extends RefCounted
class_name P2PUDPProbe

## UDP 探针包（Phase 9.2.2）：仅用于「证明双向 UDP 可达」。
##
## 职责：
## - 编解码 probe packet（二进制，非 JSON）
## - 发送 / 接收 probe
## - 校验 session_id + nonce + expected remote role + probe_id
## - 计算 RTT
## - **不**创建 ENet、不接管 SceneTree.multiplayer、不处理 Lobby/Combat
##
## 包格式 v2（大端）：
##   u32 magic          = 0x50505242 ("PPRB" = P2P Probe)
##   u8  version        = 2
##   u8  msg_type       = PROBE / ACK
##   u32 session_id_len | session_id (hex)
##   u32 nonce_len      | nonce (hex)
##   u8  role           = sender role (HOST=0 / GUEST=1)
##   u64 timestamp_ms   = 发送时刻（毫秒，用于 RTT）
##   u32 probe_id       = 探针唯一标识（用于严格 correlation）
##   u8  reserved       = 0（对齐/扩展）
##
## msg_type:
##   PROBE = 0  （主动探测）
##   ACK   = 1  （收到 probe 后回复，携带原 probe 的 timestamp + probe_id）
##
## 魔术字与版本号与 rendezvous 协议**完全独立**，避免误收。

const MAGIC: int = 0x50505242  # "PPRB"
const VERSION: int = 2
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
	var probe_id: int = 0              # 探针唯一标识（v2 新增）

	func is_ok() -> bool:
		return error == DecodeError.OK

	func is_probe() -> bool:
		return msg_type == MsgType.PROBE

	func is_ack() -> bool:
		return msg_type == MsgType.ACK

## 编码 PROBE 包（v2：包含 probe_id）。
static func encode_probe(
	session_id: String,
	nonce: String,
	role: int,
	timestamp_ms: int,
	probe_id: int
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
	buf.put_u32(probe_id)
	buf.put_u8(0)  # reserved
	return buf.data_array

## 编码 ACK 包（回显原 probe 的 timestamp + probe_id）。
static func encode_ack(
	session_id: String,
	nonce: String,
	role: int,
	timestamp_ms: int,
	original_timestamp_ms: int,
	probe_id: int
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
	buf.put_u32(probe_id)
	return buf.data_array

static func _put_string(buf: StreamPeerBuffer, value: String) -> void:
	var bytes: PackedByteArray = value.to_utf8_buffer()
	buf.put_u32(bytes.size())
	if not bytes.is_empty():
		buf.put_data(bytes)

## 解码 probe / ack 包（v2：读取 probe_id）。
static func decode(raw: PackedByteArray) -> Decoded:
	var out: Decoded = Decoded.new()
	_truncated = false
	if raw.is_empty():
		out.error = DecodeError.EMPTY
		return out
	if raw.size() < 14:  # magic + version + type + sid_len(4) + ...
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
	if msg_type == MsgType.PROBE:
		if buf.get_available_bytes() < 4:
			_truncated = true
			out.error = DecodeError.TRUNCATED
			return out
		out.probe_id = buf.get_u32()
	elif msg_type == MsgType.ACK:
		if buf.get_available_bytes() < 12:  # original_timestamp(8) + probe_id(4)
			_truncated = true
			out.error = DecodeError.TRUNCATED
			return out
		out.original_timestamp_ms = buf.get_u64()
		out.probe_id = buf.get_u32()
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

## 校验 decoded 是否符合预期（session_id + nonce + 期望的对端 role + 可选 probe_id）。
##
## Host 预期 remote_role = GUEST
## Guest 预期 remote_role = HOST
## 如果提供 expected_probe_id >= 0，则必须匹配（用于 ACK correlation）。
static func validate_expectation(decoded: Decoded, expected_session_id: String, expected_nonce: String, expected_remote_role: int, expected_probe_id: int = -1) -> bool:
	if not decoded.is_ok():
		return false
	if decoded.session_id != expected_session_id:
		return false
	if decoded.nonce != expected_nonce:
		return false
	if decoded.role != expected_remote_role:
		return false
	if expected_probe_id >= 0 and decoded.probe_id != expected_probe_id:
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
		## 使用 Godot 4.2+ 的 get_packet_with_address() 获取真实源地址端口
		if _udp == null:
			return []
		if _udp.get_available_packet_count() == 0:
			return []
		var result: Dictionary = _udp.get_packet_with_address()
		if not result:
			return []
		var packet: PackedByteArray = result.get("packet", PackedByteArray())
		var src_address: String = result.get("address", "")
		var src_port: int = result.get("port", 0)
		if packet.is_empty():
			return []
		return [packet, src_address, src_port]

	func close() -> void:
		if _udp != null:
			_udp.close()
			_udp = null
		_bound_port = 0

	func is_open() -> bool:
		return _udp != null

	## 允许外部注入已有的 PacketPeerUDP（共享 transport 模式）
	func adopt_existing_udp(udp: PacketPeerUDP) -> bool:
		if _udp != null:
			return false
		if udp == null:
			return false
		_udp = udp
		_bound_port = _udp.get_local_port()
		return true

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