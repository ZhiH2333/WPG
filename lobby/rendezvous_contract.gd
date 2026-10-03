extends RefCounted
class_name RendezvousContract

## Rendezvous 协议 contract（Phase 9.1）。
##
## 职责边界（严格）：
## - **只定义数据**：会话身份、候选、会话状态。不做 IO、不建 ENet、不碰 socket。
## - rendezvous **只负责发现 / 交换连接信息**；
## - rendezvous **不承载游戏流量**（不是 Relay）；
## - **NetSession 不接手 rendezvous**（那是 Combat 的）；
## - **UI 不接触 rendezvous packet format**（UI 只读状态与文案）。
##
## 本阶段只落地 contract + 编解码 + 单测，**不接真实公网服务器、不做 NAT 打洞**。
## 因此这里刻意做「最小、版本化、可测试」，不发明复杂 JSON 大协议。

## 协议版本。与 GameLaunch.NET_PROTOCOL（游戏协议）**分开**：
## rendezvous 是独立服务，可以自己演进，不该被游戏协议号绑死。
const VERSION: int = 1

## 消息类型。
enum MsgType {
	REGISTER,
	REGISTERED,
	CANDIDATES,
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

## 魔术字：挡掉「随便一段字节被当 rendezvous 包」。
const MAGIC: int = 0x57504752  ## "WPGR"
## nonce 长度（16 字节 = 128 bit，与 ticket 同源强度）。
const NONCE_BYTES: int = 16

## 传输类型。extend 用：本阶段只声明 UDP 直连，为后续 NAT 穿透留位。
enum Transport { UDP }

# ---- 数据结构 ----

## 一个候选端点。
class Candidate extends RefCounted:
	var transport: int = Transport.UDP
	## 连接路径（复用 LobbyPlayer.Path，避免第二套 path 枚举）。
	var path: int = LobbyPlayer.Path.LAN_IPV4
	## 可达地址与端口（对端应尝试连的地址）。
	var address: String = ""
	var port: int = 0
	## 观察到的公网端点（NAT 穿透预留字段）。本阶段可以为空 ——
	## 没有 STUN 就没有真实观测值，**绝不用本地地址伪造**。
	var observed_address: String = ""
	var observed_port: int = 0

	func is_usable() -> bool:
		if address.is_empty():
			return false
		if port < 1 or port > 65535:
			return false
		return true

	## 是否带公网观测端点（后续打洞用）。
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
	## rendezvous 服务分配的会话 id（本阶段可为空，本地模式不需要）。
	var rendezvous_id: String = ""
	## 本端 nonce（与 identity.nonce 一致）。
	var local_nonce: String = ""
	## 对端 nonce（交换后才有）。
	var remote_nonce: String = ""
	var local_candidates: Array[Candidate] = []
	var remote_candidates: Array[Candidate] = []

	func has_remote_candidates() -> bool:
		return not remote_candidates.is_empty()

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
		}

# ---- 工具 ----

## 生成 nonce（128 bit hex）。与 JoinInvite.generate_token 同源强度，
## 但语义不同：nonce 只用于关联，不是门票、不是身份。
static func generate_nonce() -> String:
	return Crypto.new().generate_random_bytes(NONCE_BYTES).hex_encode()

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

# ---- 编解码（最小二进制，非 JSON 大协议）----
#
# 包格式（大端）：
#   u32 magic | u8 version | u8 type | <payload>
#
# REGISTER   payload: u8 role | u8 protocol | u32 nonce_len | nonce | u32 room_len | room_id
#                      | u32 ticket_len | ticket | u32 n | (candidates...)
# REGISTERED payload: u32 nonce_len | nonce | u32 n | (candidates...)
# CANDIDATES payload: u32 nonce_len | nonce | u32 n | (candidates...)
# BYE        payload: (empty)
#
# candidate: u8 transport | u8 path | u16 port | u16 obs_port
#            | u32 addr_len | address | u32 obs_addr_len | observed_address

static func encode(msg_type: int, identity: SessionIdentity, candidates: Array) -> PackedByteArray:
	var buf: StreamPeerBuffer = StreamPeerBuffer.new()
	buf.big_endian = true
	buf.put_u32(MAGIC)
	buf.put_u8(VERSION)
	buf.put_u8(msg_type)
	match msg_type:
		MsgType.REGISTER:
			if identity == null:
				return PackedByteArray()
			buf.put_u8(identity.role)
			buf.put_u8(identity.protocol)
			_put_string(buf, identity.nonce)
			_put_string(buf, identity.room_id)
			_put_string(buf, identity.ticket)
			_put_candidates(buf, candidates)
		MsgType.REGISTERED, MsgType.CANDIDATES:
			if identity == null:
				return PackedByteArray()
			_put_string(buf, identity.nonce)
			_put_candidates(buf, candidates)
		MsgType.BYE:
			pass
		_:
			return PackedByteArray()
	return buf.data_array

## 解码结果：ok + type + identity + candidates + error。
class Decoded extends RefCounted:
	var error: int = DecodeError.OK
	var msg_type: int = -1
	var identity: SessionIdentity = null
	var candidates: Array[Candidate] = []

	func is_ok() -> bool:
		return error == DecodeError.OK

static func decode(raw: PackedByteArray) -> Decoded:
	var out: Decoded = Decoded.new()
	if raw.is_empty():
		out.error = DecodeError.EMPTY
		return out
	var buf: StreamPeerBuffer = StreamPeerBuffer.new()
	buf.big_endian = true
	buf.data_array = raw
	buf.seek(0)
	if raw.size() < 6:
		out.error = DecodeError.TRUNCATED
		return out
	if buf.get_u32() != MAGIC:
		out.error = DecodeError.BAD_MAGIC
		return out
	var version: int = buf.get_u8()
	if version != VERSION:
		out.error = DecodeError.BAD_VERSION
		return out
	var msg_type: int = buf.get_u8()
	out.msg_type = msg_type
	match msg_type:
		MsgType.REGISTER:
			var identity: SessionIdentity = SessionIdentity.new()
			identity.role = buf.get_u8()
			identity.protocol = buf.get_u8()
			identity.nonce = _get_string(buf)
			identity.room_id = _get_string(buf)
			identity.ticket = _get_string(buf)
			var candidates: Array[Candidate] = _get_candidates(buf)
			if candidates.is_empty() and buf.get_position() != raw.size():
				out.error = DecodeError.TRUNCATED
				return out
			out.identity = identity
			out.candidates = candidates
		MsgType.REGISTERED, MsgType.CANDIDATES:
			var identity: SessionIdentity = SessionIdentity.new()
			identity.nonce = _get_string(buf)
			out.identity = identity
			out.candidates = _get_candidates(buf)
		MsgType.BYE:
			pass
		_:
			out.error = DecodeError.BAD_TYPE
			return out
	## 越界读取会让 StreamPeerBuffer 打错误标记，统一反映为 TRUNCATED。
	if buf.get_available_bytes() < 0:
		out.error = DecodeError.TRUNCATED
		return out
	return out

static func _put_string(buf: StreamPeerBuffer, value: String) -> void:
	var bytes: PackedByteArray = value.to_utf8_buffer()
	buf.put_u32(bytes.size())
	if not bytes.is_empty():
		buf.put_data(bytes)

static func _get_string(buf: StreamPeerBuffer) -> String:
	var size: int = buf.get_u32()
	if size <= 0 or size > 4096:
		return ""
	var data: PackedByteArray = buf.get_data(size)[1]
	return data.get_string_from_utf8()

static func _put_candidates(buf: StreamPeerBuffer, candidates: Array) -> void:
	buf.put_u32(candidates.size())
	for candidate: Candidate in candidates:
		buf.put_u8(candidate.transport)
		buf.put_u8(candidate.path)
		buf.put_u16(candidate.port)
		buf.put_u16(candidate.observed_port)
		_put_string(buf, candidate.address)
		_put_string(buf, candidate.observed_address)

static func _get_candidates(buf: StreamPeerBuffer) -> Array[Candidate]:
	var out: Array[Candidate] = []
	var count: int = buf.get_u32()
	if count > 32:
		return out
	for _i: int in count:
		var candidate: Candidate = Candidate.new()
		candidate.transport = buf.get_u8()
		candidate.path = buf.get_u8()
		candidate.port = buf.get_u16()
		candidate.observed_port = buf.get_u16()
		candidate.address = _get_string(buf)
		candidate.observed_address = _get_string(buf)
		out.append(candidate)
	return out

static func msg_type_name(value: int) -> String:
	match value:
		MsgType.REGISTER:
			return "register"
		MsgType.REGISTERED:
			return "registered"
		MsgType.CANDIDATES:
			return "candidates"
		MsgType.BYE:
			return "bye"
		_:
			return "unknown"

static func role_name(value: int) -> String:
	return "host" if value == Role.HOST else "guest"
