extends RefCounted
class_name RendezvousContract

## Rendezvous 协议 contract（Phase 9.1 定义；Phase 9.2.1 升到 v2）。
##
## 职责边界（严格）：
## - **只定义数据**：会话身份、候选、会话状态。不做 IO、不建 ENet、不碰 socket。
## - rendezvous **只负责发现 / 交换连接信息**；
## - rendezvous **不承载游戏流量**（不是 Relay）；
## - **NetSession 不接手 rendezvous**（那是 Combat 的）；
## - **UI 不接触 rendezvous packet format**（UI 只读状态与文案）。
##
## v2 变更（Phase 9.2.1 接真实公网服务所必需）：
## - 每条消息都带 `session_id`：服务端分配、用于把双方关联到同一会话；
## - 新增 `PEER_READY`（对端已就绪，可以交换候选）与 `ERROR`（可诊断错误码）；
## - `REGISTERED` / `CANDIDATES` 携带**服务端观测到的** observed endpoint；
## - 编码顺序调整，v1 包会被 BAD_VERSION 明确拒绝（不做静默兼容）。
##
## 版本号与 GameLaunch.NET_PROTOCOL（游戏协议）**分开**：
## rendezvous 是独立服务，可以自己演进，不该被游戏协议号绑死。

## 协议版本（v2：session_id + PEER_READY/ERROR + observed endpoint）。
const VERSION: int = 2

## 消息类型。
enum MsgType {
	REGISTER,
	REGISTERED,
	PEER_READY,
	CANDIDATES,
	ERROR,
	BYE,
}

## 角色。与 LobbyManager.Role 语义一致，但这里独立定义避免 rendezvous 依赖大厅域对象。
enum Role { HOST, GUEST }

## 编解码错误码。
enum DecodeError {
	OK,
	EMPTY,
	BAD_MAGIC,
	BAD_VERSION,
	BAD_TYPE,
	TRUNCATED,
	BAD_FIELD,
}

## 服务端 / 客户端共用的错误码。
## 必须可诊断：UI 未来据此显示不同文案，测试据此断言。
enum ErrorCode {
	NONE,
	SESSION_NOT_FOUND,
	SESSION_FULL,
	BAD_PROTOCOL,
	BAD_TICKET,
	BAD_ROLE,
	DUPLICATE_PEER,
	MALFORMED_PACKET,
	TIMEOUT,
	ROOM_MISMATCH,
}

## 魔术字：挡掉「随便一段字节被当 rendezvous 包」。
const MAGIC: int = 0x57504752  ## "WPGR"
## nonce 长度（16 字节 = 128 bit，与 ticket 同源强度）。
const NONCE_BYTES: int = 16
## 服务端分配的 session_id 长度（hex 字符数）。
const SESSION_ID_HEX_LEN: int = 16

## 传输类型。本阶段只声明 UDP 直连；NAT 穿透（9.2.2）仍走同一条。
enum Transport { UDP }

## 三级超时（与 P2PConnectionState / ConnectAttemptRunner 保持同值）。
const RENDEZVOUS_TIMEOUT_SEC: float = 5.0
const OVERALL_JOIN_TIMEOUT_SEC: float = 12.0
## 服务端 session 空闲清理阈值（双方都消失后回收）。
const SESSION_IDLE_TIMEOUT_SEC: float = 30.0

# ---- 数据结构 ----

## 一个候选端点。
class Candidate extends RefCounted:
	var transport: int = Transport.UDP
	## 连接路径（复用 LobbyPlayer.Path，避免第二套 path 枚举）。
	var path: int = LobbyPlayer.Path.LAN_IPV4
	## 可达地址与端口（对端应尝试连的地址）。
	var address: String = ""
	var port: int = 0
	## **服务端观测到的**公网端点。只能由 rendezvous / STUN 填入 ——
	## 绝不用本地地址或客户端自报值伪造。
	var observed_address: String = ""
	var observed_port: int = 0

	func is_usable() -> bool:
		if address.is_empty():
			return false
		if port < 1 or port > 65535:
			return false
		return true

	## 是否带公网观测端点（9.2.2 打洞用）。
	func has_observed_endpoint() -> bool:
		return not observed_address.is_empty() and observed_port >= 1 and observed_port <= 65535

	func key() -> String:
		return "%d|%d|%s|%d" % [transport, path, address, port]

	func to_dict() -> Dictionary:
		return {
			"transport": transport,
			"path": path,
			"address": address,
			"port": port,
			"observed_address": observed_address,
			"observed_port": observed_port,
		}

## 会话身份：谁、进哪间房、用什么协议。
class SessionIdentity extends RefCounted:
	var room_id: String = ""
	## 本会话出示的 ticket（Guest = guest ticket；Host = room ticket）。
	## **不写进日志、不写进 UI 文案**。
	var ticket: String = ""
	## 游戏协议号（GameLaunch.NET_PROTOCOL）。
	var protocol: int = 0
	var role: int = Role.GUEST
	## 本端 nonce：防重放 / 关联请求与响应，**不是身份**。
	var nonce: String = ""

	func is_valid() -> bool:
		if room_id.is_empty() or ticket.is_empty():
			return false
		if protocol <= 0:
			return false
		return not nonce.is_empty()

## 一次 rendezvous 会话的完整状态。
class SessionState extends RefCounted:
	## rendezvous 服务分配的会话 id（真实服务模式下必填）。
	var rendezvous_id: String = ""
	## 本端 nonce（与 identity.nonce 一致）。
	var local_nonce: String = ""
	## 对端 nonce（交换后才有）。
	var remote_nonce: String = ""
	var local_candidates: Array[Candidate] = []
	var remote_candidates: Array[Candidate] = []
	## 服务端观测到的**本端**公网端点（对方要连的就是它）。
	var local_observed_address: String = ""
	var local_observed_port: int = 0
	## 服务端观测到的**对端**公网端点。
	var remote_observed_address: String = ""
	var remote_observed_port: int = 0

	func has_remote_candidates() -> bool:
		return not remote_candidates.is_empty()

	## 本端是否已拿到服务端观测端点。
	func has_local_observed_endpoint() -> bool:
		return not local_observed_address.is_empty() and local_observed_port >= 1 and local_observed_port <= 65535

	## 首个可用远端候选（按到达顺序，不重排 —— 顺序由 Host 给出）。
	func first_usable_remote() -> Candidate:
		for candidate: Candidate in remote_candidates:
			if candidate.is_usable():
				return candidate
		return null

	func to_dict() -> Dictionary:
		var local: Array = []
		for candidate: Candidate in local_candidates:
			local.append(candidate.to_dict())
		var remote: Array = []
		for candidate: Candidate in remote_candidates:
			remote.append(candidate.to_dict())
		return {
			"rendezvous_id": rendezvous_id,
			"local_nonce": local_nonce,
			"remote_nonce": remote_nonce,
			"local_candidates": local,
			"remote_candidates": remote,
			"local_observed_address": local_observed_address,
			"local_observed_port": local_observed_port,
			"remote_observed_address": remote_observed_address,
			"remote_observed_port": remote_observed_port,
		}

# ---- 工具 ----

## 生成 nonce（128 bit hex）。与 JoinInvite.generate_token 同源强度，
## 但语义不同：nonce 只用于关联，不是门票、不是身份。
static func generate_nonce() -> String:
	return Crypto.new().generate_random_bytes(NONCE_BYTES).hex_encode()

## nonce 合法性：定长 hex。服务端与客户端共用同一判定，避免两边标准漂移。
static func is_valid_nonce(value: String) -> bool:
	if value.length() != NONCE_BYTES * 2:
		return false
	return _is_hex(value)

## session_id 合法性：服务端分配，定长 hex。
static func is_valid_session_id(value: String) -> bool:
	if value.length() != SESSION_ID_HEX_LEN:
		return false
	return _is_hex(value)

## room_id 合法性：只允许安全字符（与 JoinInvite 元数据同款约束）。
static func is_valid_room_id(value: String) -> bool:
	if value.is_empty() or value.length() > 32:
		return false
	for i: int in value.length():
		var c: int = value.unicode_at(i)
		var is_digit: bool = c >= 48 and c <= 57
		var is_lower: bool = c >= 97 and c <= 122
		var is_upper: bool = c >= 65 and c <= 90
		if not (is_digit or is_lower or is_upper or c == 45 or c == 95):
			return false
	return true

## ticket 合法性与 JoinInvite 同标准（hex，8..64）。**不是**身份，是门票。
static func is_valid_ticket(value: String) -> bool:
	if value.length() < 8 or value.length() > 64:
		return false
	return _is_hex(value)

static func is_valid_role(value: int) -> bool:
	return value == Role.HOST or value == Role.GUEST

static func _is_hex(value: String) -> bool:
	for i: int in value.length():
		var c: int = value.unicode_at(i)
		var is_digit: bool = c >= 48 and c <= 57
		var is_lower: bool = c >= 97 and c <= 102
		var is_upper: bool = c >= 65 and c <= 70
		if not (is_digit or is_lower or is_upper):
			return false
	return not value.is_empty()

## 由 JoinInvite 装配本端候选：只放 invite 真实提供的路径（缺的不伪造）。
static func candidates_from_invite(invite: JoinInvite) -> Array[Candidate]:
	var out: Array[Candidate] = []
	if invite == null:
		return out
	if not invite.lan_host.is_empty():
		out.append(_make_candidate(LobbyPlayer.Path.LAN_IPV4, invite.lan_host, invite.lan_port))
	if not invite.ipv6.is_empty():
		out.append(_make_candidate(LobbyPlayer.Path.IPV6, invite.ipv6, invite.lan_port))
	if not invite.wan_host.is_empty():
		out.append(_make_candidate(LobbyPlayer.Path.WAN_IPV4, invite.wan_host, invite.wan_port))
	return out

static func _make_candidate(path: int, address: String, port: int) -> Candidate:
	var candidate: Candidate = Candidate.new()
	candidate.transport = Transport.UDP
	candidate.path = path
	candidate.address = address
	candidate.port = port
	return candidate

static func make_identity(
	room_id: String,
	ticket: String,
	protocol: int,
	role: int,
	nonce: String = ""
) -> SessionIdentity:
	var identity: SessionIdentity = SessionIdentity.new()
	identity.room_id = room_id
	identity.ticket = ticket
	identity.protocol = protocol
	identity.role = role
	identity.nonce = nonce if not nonce.is_empty() else generate_nonce()
	return identity

## 日志安全摘要：**绝不输出完整 ticket**。
## 只给 session_id / role / nonce 短摘要 / observed endpoint / msg type / error。
static func safe_summary(
	msg_type: int,
	session_id: String,
	role: int,
	nonce: String,
	observed_address: String = "",
	observed_port: int = 0,
	error_code: int = ErrorCode.NONE
) -> String:
	return "type=%s session=%s role=%s nonce=%s observed=%s:%d error=%s" % [
		msg_type_name(msg_type),
		session_id if not session_id.is_empty() else "-",
		role_name(role),
		nonce_summary(nonce),
		observed_address if not observed_address.is_empty() else "-",
		observed_port,
		error_name(error_code),
	]

## nonce 的短摘要（日志只留前 8 位）。
static func nonce_summary(nonce: String) -> String:
	if nonce.is_empty():
		return "-"
	return nonce.substr(0, 8)

# ---- 编解码（最小二进制，非 JSON 大协议）----
#
# v2 包格式（大端）：
#   u32 magic | u8 version | u8 type | u32 sid_len | session_id | <payload>
#
# REGISTER   payload: u8 role | u8 protocol | str nonce | str room_id | str ticket
#                      | u32 n | (candidates...)
# REGISTERED payload: str nonce | u16 observed_port | str observed_address
#                      | u32 n | (candidates...)
# PEER_READY payload: str nonce | str remote_nonce | u8 remote_role
#                      | u16 observed_port | str observed_address
#                      | u32 n | (candidates...)
# CANDIDATES payload: str nonce | str remote_nonce | u8 remote_role
#                      | u16 observed_port | str observed_address
#                      | u32 n | (remote candidates...)
# ERROR      payload: u8 error_code | str detail
# BYE        payload: (empty)
#
# str = u32 byte_len | utf8 bytes
# candidate: u8 transport | u8 path | u16 port | u16 obs_port
#            | str address | str observed_address

## 编解码结果：ok + type + session_id + identity + candidates + error。
class Decoded extends RefCounted:
	var error: int = DecodeError.OK
	var msg_type: int = -1
	var session_id: String = ""
	var identity: SessionIdentity = null
	var candidates: Array[Candidate] = []
	## ERROR 消息携带。
	var error_code: int = ErrorCode.NONE
	var detail: String = ""
	## 服务端观测到的发送方端点（REGISTERED / PEER_READY / CANDIDATES 携带）。
	var observed_address: String = ""
	var observed_port: int = 0
	## 对端 nonce（PEER_READY / CANDIDATES 携带）。
	var remote_nonce: String = ""
	var remote_role: int = Role.GUEST

	func is_ok() -> bool:
		return error == DecodeError.OK

static func encode_register(
	session_id: String,
	identity: SessionIdentity,
	candidates: Array
) -> PackedByteArray:
	if identity == null:
		return PackedByteArray()
	var buf: StreamPeerBuffer = _begin(MsgType.REGISTER, session_id)
	if buf == null:
		return PackedByteArray()
	buf.put_u8(identity.role)
	buf.put_u8(identity.protocol)
	_put_string(buf, identity.nonce)
	_put_string(buf, identity.room_id)
	_put_string(buf, identity.ticket)
	_put_candidates(buf, candidates)
	return buf.data_array

## 服务端 -> 客户端：已注册，带你自己的 observed endpoint 与对端候选（若已配对）。
static func encode_registered(
	session_id: String,
	nonce: String,
	observed_address: String,
	observed_port: int,
	candidates: Array
) -> PackedByteArray:
	var buf: StreamPeerBuffer = _begin(MsgType.REGISTERED, session_id)
	if buf == null:
		return PackedByteArray()
	_put_string(buf, nonce)
	buf.put_u16(clampi(observed_port, 0, 65535))
	_put_string(buf, observed_address)
	_put_candidates(buf, candidates)
	return buf.data_array

## 服务端 -> 客户端：对端已就绪，交换双方候选与 observed endpoint。
static func encode_candidates(
	session_id: String,
	nonce: String,
	remote_nonce: String,
	remote_role: int,
	observed_address: String,
	observed_port: int,
	remote_candidates: Array
) -> PackedByteArray:
	var buf: StreamPeerBuffer = _begin(MsgType.CANDIDATES, session_id)
	if buf == null:
		return PackedByteArray()
	_put_string(buf, nonce)
	_put_string(buf, remote_nonce)
	buf.put_u8(remote_role)
	buf.put_u16(clampi(observed_port, 0, 65535))
	_put_string(buf, observed_address)
	_put_candidates(buf, remote_candidates)
	return buf.data_array

## 服务端 -> 客户端：对端已就绪（候选尚未齐备时的通知）。
static func encode_peer_ready(
	session_id: String,
	nonce: String,
	remote_nonce: String,
	remote_role: int,
	observed_address: String,
	observed_port: int
) -> PackedByteArray:
	var buf: StreamPeerBuffer = _begin(MsgType.PEER_READY, session_id)
	if buf == null:
		return PackedByteArray()
	_put_string(buf, nonce)
	_put_string(buf, remote_nonce)
	buf.put_u8(remote_role)
	buf.put_u16(clampi(observed_port, 0, 65535))
	_put_string(buf, observed_address)
	return buf.data_array

## 服务端 -> 客户端：可诊断错误。
static func encode_error(session_id: String, error_code: int, detail: String = "") -> PackedByteArray:
	var buf: StreamPeerBuffer = _begin(MsgType.ERROR, session_id)
	if buf == null:
		return PackedByteArray()
	buf.put_u8(error_code)
	_put_string(buf, detail)
	return buf.data_array

static func encode_bye(session_id: String) -> PackedByteArray:
	var buf: StreamPeerBuffer = _begin(MsgType.BYE, session_id)
	if buf == null:
		return PackedByteArray()
	return buf.data_array

static func _begin(msg_type: int, session_id: String) -> StreamPeerBuffer:
	var buf: StreamPeerBuffer = StreamPeerBuffer.new()
	buf.big_endian = true
	buf.put_u32(MAGIC)
	buf.put_u8(VERSION)
	buf.put_u8(msg_type)
	_put_string(buf, session_id)
	return buf

static func decode(raw: PackedByteArray) -> Decoded:
	var out: Decoded = Decoded.new()
	_truncated = false
	if raw.is_empty():
		out.error = DecodeError.EMPTY
		return out
	if raw.size() < 10:
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
	out.msg_type = msg_type
	out.session_id = _get_string(buf)
	match msg_type:
		MsgType.REGISTER:
			var identity: SessionIdentity = SessionIdentity.new()
			identity.role = buf.get_u8()
			identity.protocol = buf.get_u8()
			identity.nonce = _get_string(buf)
			identity.room_id = _get_string(buf)
			identity.ticket = _get_string(buf)
			out.identity = identity
			out.candidates = _get_candidates(buf)
		MsgType.REGISTERED:
			var identity: SessionIdentity = SessionIdentity.new()
			identity.nonce = _get_string(buf)
			out.observed_port = buf.get_u16()
			out.observed_address = _get_string(buf)
			out.identity = identity
			out.candidates = _get_candidates(buf)
		MsgType.PEER_READY, MsgType.CANDIDATES:
			var identity: SessionIdentity = SessionIdentity.new()
			identity.nonce = _get_string(buf)
			out.remote_nonce = _get_string(buf)
			out.remote_role = buf.get_u8()
			out.observed_port = buf.get_u16()
			out.observed_address = _get_string(buf)
			out.identity = identity
			if msg_type == MsgType.CANDIDATES:
				out.candidates = _get_candidates(buf)
		MsgType.ERROR:
			out.error_code = buf.get_u8()
			out.detail = _get_string(buf)
		MsgType.BYE:
			pass
		_:
			out.error = DecodeError.BAD_TYPE
			return out
	## 越界读取会让 get_available_bytes() 变成负数；字符串/候选读取也会打 _truncated 标记。
	if _truncated or buf.get_available_bytes() < 0 or buf.get_position() > raw.size():
		out.error = DecodeError.TRUNCATED
		return out
	return out

static func _put_string(buf: StreamPeerBuffer, value: String) -> void:
	var bytes: PackedByteArray = value.to_utf8_buffer()
	buf.put_u32(bytes.size())
	if not bytes.is_empty():
		buf.put_data(bytes)

## 读字符串：声明长度超出剩余字节 = 包被截断，必须打 _truncated 标记。
## 不能静默返回 ""（那会让半截包被当成合法包接受）。
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

## 解码期间的截断标记（每次 decode() 入口重置）。
## 静态变量在这里是安全的：GDScript 单线程，decode 不重入。
static var _truncated: bool = false

static func _put_candidates(buf: StreamPeerBuffer, candidates: Array) -> void:
	buf.put_u32(candidates.size())
	for candidate: Candidate in candidates:
		buf.put_u8(candidate.transport)
		buf.put_u8(candidate.path)
		buf.put_u16(clampi(candidate.port, 0, 65535))
		buf.put_u16(clampi(candidate.observed_port, 0, 65535))
		_put_string(buf, candidate.address)
		_put_string(buf, candidate.observed_address)

static func _get_candidates(buf: StreamPeerBuffer) -> Array[Candidate]:
	var out: Array[Candidate] = []
	if buf.get_available_bytes() < 4:
		_truncated = true
		return out
	var count: int = buf.get_u32()
	if count < 0 or count > 32:
		_truncated = true
		return out
	for _i: int in count:
		## 每个候选至少需要 transport/path/port/obs_port 四个字段。
		if buf.get_available_bytes() < 6:
			_truncated = true
			return out
		var candidate: Candidate = Candidate.new()
		candidate.transport = buf.get_u8()
		candidate.path = buf.get_u8()
		candidate.port = buf.get_u16()
		candidate.observed_port = buf.get_u16()
		candidate.address = _get_string(buf)
		candidate.observed_address = _get_string(buf)
		if _truncated:
			return out
		out.append(candidate)
	return out

static func msg_type_name(value: int) -> String:
	match value:
		MsgType.REGISTER:
			return "register"
		MsgType.REGISTERED:
			return "registered"
		MsgType.PEER_READY:
			return "peer_ready"
		MsgType.CANDIDATES:
			return "candidates"
		MsgType.ERROR:
			return "error"
		MsgType.BYE:
			return "bye"
		_:
			return "unknown"

static func role_name(value: int) -> String:
	return "host" if value == Role.HOST else "guest"

static func error_name(value: int) -> String:
	match value:
		ErrorCode.SESSION_NOT_FOUND:
			return "SESSION_NOT_FOUND"
		ErrorCode.SESSION_FULL:
			return "SESSION_FULL"
		ErrorCode.BAD_PROTOCOL:
			return "BAD_PROTOCOL"
		ErrorCode.BAD_TICKET:
			return "BAD_TICKET"
		ErrorCode.BAD_ROLE:
			return "BAD_ROLE"
		ErrorCode.DUPLICATE_PEER:
			return "DUPLICATE_PEER"
		ErrorCode.MALFORMED_PACKET:
			return "MALFORMED_PACKET"
		ErrorCode.TIMEOUT:
			return "TIMEOUT"
		ErrorCode.ROOM_MISMATCH:
			return "ROOM_MISMATCH"
		_:
			return "NONE"
