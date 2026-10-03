extends SceneTree

## Rendezvous contract 回归（Phase 9.1 定义 / Phase 9.2.1 升 v2）。锁定：
## - 包格式版本化：magic / version 不符必须被拒（v1 包不再被接受）
## - 每条消息带 session_id；PEER_READY / ERROR 存在且可往返
## - 编解码往返一致（identity / candidates / observed endpoint / remote nonce）
## - 候选只从 invite 真实提供的路径产生，缺的不伪造
## - observed/public endpoint **只能由服务端 / STUN 填入**，不伪造
## - 日志安全摘要**绝不输出完整 ticket**
## - rendezvous 只交换信息：不碰 ENet、不承载游戏流量
##
## 跑法：godot --headless --path . --script res://tests/rendezvous_contract_test.gd
## 通过输出 RENDEZVOUS_CONTRACT_OK；失败逐条 RENDEZVOUS_CONTRACT_FAIL 并返回非 0。

const ROOM := "a1b2c3d4"
const TICKET := "0f1e2d3c4b5a69788796a5b4c3d2e1f0"
const LAN := "192.168.1.20"
const WAN := "203.0.113.7"
const V6 := "fe80::1c2d:3e4f:5a6b:7c8d"
const SID := "0123456789abcdef"

var _failures: PackedStringArray = PackedStringArray()

func _initialize() -> void:
	_run_all.call_deferred()

func _run_all() -> void:
	_case_version_is_v2_and_independent()
	_case_packet_guards()
	_case_register_roundtrip()
	_case_registered_carries_observed_endpoint()
	_case_peer_ready_roundtrip()
	_case_candidates_roundtrip()
	_case_error_roundtrip()
	_case_truncated_packet_is_rejected()
	_case_observed_endpoint_is_not_faked()
	_case_candidates_from_invite_only_real_paths()
	_case_candidates_from_invite_ordering()
	_case_session_state_helpers()
	_case_nonce_and_id_validation()
	_case_log_summary_hides_ticket()
	_case_no_enet_in_contract()
	_finish()

# ---- 用例 ----

## v2：session_id + PEER_READY / ERROR；版本号与游戏协议号分离。
func _case_version_is_v2_and_independent() -> void:
	_expect(RendezvousContract.VERSION == 2, "contract 版本 = 2（9.2.1 升版）")
	_expect(RendezvousContract.MAGIC == 0x57504752, "magic = WPGR")
	_expect(RendezvousContract.NONCE_BYTES == 16, "nonce 128 bit")
	_expect(RendezvousContract.SESSION_ID_HEX_LEN == 16, "session_id 16 hex")
	_expect(RendezvousContract.MsgType.PEER_READY == 2, "PEER_READY 存在")
	_expect(RendezvousContract.MsgType.ERROR == 4, "ERROR 存在")
	_expect(RendezvousContract.ErrorCode.DUPLICATE_PEER > 0, "DUPLICATE_PEER 错误码存在")
	_expect(RendezvousContract.error_name(RendezvousContract.ErrorCode.BAD_TICKET) == "BAD_TICKET", "error_name 覆盖 BAD_TICKET")
	_expect(RendezvousContract.error_name(RendezvousContract.ErrorCode.SESSION_FULL) == "SESSION_FULL", "error_name 覆盖 SESSION_FULL")
	_expect(RendezvousContract.role_name(RendezvousContract.Role.HOST) == "host", "role_name 覆盖 host")
	## 与游戏协议号解耦：rendezvous 不该被 NET_PROTOCOL 绑死。
	_expect(RendezvousContract.VERSION != GameLaunch.NET_PROTOCOL, "rendezvous 版本与游戏协议号独立")

## magic / version / type 三道门必须都能挡住垃圾包。
func _case_packet_guards() -> void:
	var empty: RendezvousContract.Decoded = RendezvousContract.decode(PackedByteArray())
	_expect(empty.error == RendezvousContract.DecodeError.EMPTY, "空包 -> EMPTY")
	## 太短。
	var tiny: PackedByteArray = PackedByteArray()
	tiny.resize(4)
	tiny.fill(0)
	_expect(RendezvousContract.decode(tiny).error == RendezvousContract.DecodeError.TRUNCATED, "短包 -> TRUNCATED")
	## 错误 magic。
	var junk: PackedByteArray = PackedByteArray()
	junk.resize(16)
	junk.fill(0x41)
	_expect(RendezvousContract.decode(junk).error == RendezvousContract.DecodeError.BAD_MAGIC, "magic 不符 -> BAD_MAGIC")
	## v1 包（version 1）必须被拒 —— 不做静默兼容。
	var v1: StreamPeerBuffer = StreamPeerBuffer.new()
	v1.big_endian = true
	v1.put_u32(RendezvousContract.MAGIC)
	v1.put_u8(1)
	v1.put_u8(RendezvousContract.MsgType.BYE)
	v1.put_u32(0)
	var decoded_v1: RendezvousContract.Decoded = RendezvousContract.decode(v1.data_array)
	_expect(decoded_v1.error == RendezvousContract.DecodeError.BAD_VERSION, "v1 包 -> BAD_VERSION")
	## 未知消息类型。
	var unknown: StreamPeerBuffer = StreamPeerBuffer.new()
	unknown.big_endian = true
	unknown.put_u32(RendezvousContract.MAGIC)
	unknown.put_u8(RendezvousContract.VERSION)
	unknown.put_u8(99)
	unknown.put_u32(0)
	_expect(RendezvousContract.decode(unknown.data_array).error == RendezvousContract.DecodeError.BAD_TYPE, "未知 type -> BAD_TYPE")

## REGISTER 往返：session_id + room_id / ticket / protocol / role / nonce 全部保真。
func _case_register_roundtrip() -> void:
	var identity: RendezvousContract.SessionIdentity = RendezvousContract.make_identity(
		ROOM, TICKET, GameLaunch.NET_PROTOCOL, RendezvousContract.Role.GUEST
	)
	var candidates: Array[RendezvousContract.Candidate] = _sample_candidates()
	var raw: PackedByteArray = RendezvousContract.encode_register(SID, identity, candidates)
	_expect(not raw.is_empty(), "REGISTER 编码非空")
	var decoded: RendezvousContract.Decoded = RendezvousContract.decode(raw)
	_expect(decoded.is_ok(), "REGISTER 解码成功")
	_expect(decoded.msg_type == RendezvousContract.MsgType.REGISTER, "type 保真")
	_expect(decoded.session_id == SID, "session_id 保真")
	_expect(decoded.identity.room_id == ROOM, "room_id 保真")
	_expect(decoded.identity.ticket == TICKET, "ticket 保真")
	_expect(decoded.identity.protocol == GameLaunch.NET_PROTOCOL, "protocol 保真")
	_expect(decoded.identity.role == RendezvousContract.Role.GUEST, "role 保真")
	_expect(decoded.identity.nonce == identity.nonce, "nonce 保真")
	_expect(decoded.candidates.size() == candidates.size(), "候选数量保真")

## REGISTERED 携带服务端观测到的**本端** observed endpoint。
func _case_registered_carries_observed_endpoint() -> void:
	var raw: PackedByteArray = RendezvousContract.encode_registered(
		SID, "aabbccddeeff00112233445566778899", WAN, 51820, _sample_candidates()
	)
	var decoded: RendezvousContract.Decoded = RendezvousContract.decode(raw)
	_expect(decoded.is_ok(), "REGISTERED 解码成功")
	_expect(decoded.msg_type == RendezvousContract.MsgType.REGISTERED, "type = REGISTERED")
	_expect(decoded.session_id == SID, "session_id 保真")
	_expect(decoded.observed_address == WAN, "observed_address 保真")
	_expect(decoded.observed_port == 51820, "observed_port 保真")
	_expect(decoded.identity.nonce == "aabbccddeeff00112233445566778899", "nonce 保真")

## PEER_READY：对端已就绪，带对端 nonce / role / observed endpoint。
func _case_peer_ready_roundtrip() -> void:
	var raw: PackedByteArray = RendezvousContract.encode_peer_ready(
		SID, "11112222333344445555666677778888", "9999aaaabbbbccccddddeeeeffff0000",
		RendezvousContract.Role.HOST, WAN, 40000
	)
	var decoded: RendezvousContract.Decoded = RendezvousContract.decode(raw)
	_expect(decoded.is_ok(), "PEER_READY 解码成功")
	_expect(decoded.msg_type == RendezvousContract.MsgType.PEER_READY, "type = PEER_READY")
	_expect(decoded.remote_nonce == "9999aaaabbbbccccddddeeeeffff0000", "remote_nonce 保真")
	_expect(decoded.remote_role == RendezvousContract.Role.HOST, "remote_role 保真")
	_expect(decoded.observed_address == WAN and decoded.observed_port == 40000, "对端 observed endpoint 保真")

## CANDIDATES 往返：transport / path / port / address / remote nonce 全部保真。
func _case_candidates_roundtrip() -> void:
	var candidates: Array[RendezvousContract.Candidate] = _sample_candidates()
	var raw: PackedByteArray = RendezvousContract.encode_candidates(
		SID, "11112222333344445555666677778888", "9999aaaabbbbccccddddeeeeffff0000",
		RendezvousContract.Role.HOST, WAN, 40000, candidates
	)
	var decoded: RendezvousContract.Decoded = RendezvousContract.decode(raw)
	_expect(decoded.is_ok(), "CANDIDATES 解码成功")
	_expect(decoded.msg_type == RendezvousContract.MsgType.CANDIDATES, "type = CANDIDATES")
	_expect(decoded.remote_nonce == "9999aaaabbbbccccddddeeeeffff0000", "remote_nonce 保真")
	_expect(decoded.remote_role == RendezvousContract.Role.HOST, "remote_role 保真")
	_expect(decoded.candidates.size() == 3, "三个候选都往返")
	var first: RendezvousContract.Candidate = decoded.candidates[0]
	_expect(first.transport == RendezvousContract.Transport.UDP, "transport 保真")
	_expect(first.path == LobbyPlayer.Path.LAN_IPV4, "path 保真")
	_expect(first.address == LAN, "address 保真")
	_expect(first.port == 17777, "port 保真")

## ERROR 往返：错误码 + 细节可诊断。
func _case_error_roundtrip() -> void:
	var raw: PackedByteArray = RendezvousContract.encode_error(
		SID, RendezvousContract.ErrorCode.DUPLICATE_PEER, "guest already registered"
	)
	var decoded: RendezvousContract.Decoded = RendezvousContract.decode(raw)
	_expect(decoded.is_ok(), "ERROR 解码成功")
	_expect(decoded.msg_type == RendezvousContract.MsgType.ERROR, "type = ERROR")
	_expect(decoded.error_code == RendezvousContract.ErrorCode.DUPLICATE_PEER, "error_code 保真")
	_expect(decoded.detail == "guest already registered", "detail 保真")

## observed/public endpoint 是为 NAT 穿透预留：没有服务端 / STUN 观测就不许填。
func _case_observed_endpoint_is_not_faked() -> void:
	var candidates: Array[RendezvousContract.Candidate] = RendezvousContract.candidates_from_invite(
		JoinInvite.create(LAN, 17777, "", ROOM)
	)
	_expect(candidates.size() == 1, "有一个候选")
	_expect(candidates[0].observed_address.is_empty(), "observed_address 默认空（不伪造）")
	_expect(candidates[0].observed_port == 0, "observed_port 默认 0（不伪造）")
	_expect(not candidates[0].has_observed_endpoint(), "has_observed_endpoint 默认 false")
	## 显式填上观测值后往返保真（9.2.2 打洞要用）。
	var candidate: RendezvousContract.Candidate = RendezvousContract.Candidate.new()
	candidate.path = LobbyPlayer.Path.WAN_IPV4
	candidate.address = "10.0.0.5"
	candidate.port = 49152
	candidate.observed_address = WAN
	candidate.observed_port = 51820
	_expect(candidate.has_observed_endpoint(), "显式观测端点 -> true")
	var raw: PackedByteArray = RendezvousContract.encode_candidates(
		SID, "11112222333344445555666677778888", "9999aaaabbbbccccddddeeeeffff0000",
		RendezvousContract.Role.HOST, WAN, 40000, [candidate] as Array[RendezvousContract.Candidate]
	)
	var decoded: RendezvousContract.Decoded = RendezvousContract.decode(raw)
	_expect(decoded.is_ok(), "带观测端点的包解码成功")
	_expect(decoded.candidates[0].observed_address == WAN, "observed_address 往返保真")
	_expect(decoded.candidates[0].observed_port == 51820, "observed_port 往返保真")

## 半截包必须被拒：不能因为「读不到就返回空串」而把截断包当合法包接受。
func _case_truncated_packet_is_rejected() -> void:
	var identity: RendezvousContract.SessionIdentity = RendezvousContract.make_identity(
		ROOM, TICKET, GameLaunch.NET_PROTOCOL, RendezvousContract.Role.GUEST
	)
	var candidates: Array[RendezvousContract.Candidate] = _sample_candidates()
	var full: PackedByteArray = RendezvousContract.encode_register(SID, identity, candidates)
	_expect(RendezvousContract.decode(full).is_ok(), "完整包正常解析（对照组）")
	for fraction: int in [2, 3, 4]:
		var cut: PackedByteArray = full.slice(0, full.size() * fraction / 5)
		var decoded: RendezvousContract.Decoded = RendezvousContract.decode(cut)
		_expect(
			decoded.error == RendezvousContract.DecodeError.TRUNCATED,
			"截断到 %d/5 的包 -> TRUNCATED" % fraction
		)
		_expect(not decoded.is_ok(), "截断包绝不 is_ok")

## 候选只从 invite 真实提供的路径产生：没给的路径不许伪造。
func _case_candidates_from_invite_only_real_paths() -> void:
	var lan_only: Array[RendezvousContract.Candidate] = RendezvousContract.candidates_from_invite(
		JoinInvite.create(LAN, 17777, "", ROOM)
	)
	_expect(lan_only.size() == 1, "只有 LAN 时只有一个候选")
	_expect(lan_only[0].path == LobbyPlayer.Path.LAN_IPV4, "候选是 LAN_IPV4")
	_expect(lan_only[0].port == 17777, "LAN 候选带端口")
	## 空 invite / null 不产生候选，也不崩。
	_expect(RendezvousContract.candidates_from_invite(null).is_empty(), "null invite -> 无候选")

## 候选顺序 = invite 的固定顺序（LAN -> IPv6 -> WAN），rendezvous 不重排。
func _case_candidates_from_invite_ordering() -> void:
	var invite: JoinInvite = JoinInvite.create(LAN, 17777, "", ROOM, "", V6, WAN, 49152)
	var candidates: Array[RendezvousContract.Candidate] = RendezvousContract.candidates_from_invite(invite)
	_expect(candidates.size() == 3, "三候选都在")
	_expect(candidates[0].path == LobbyPlayer.Path.LAN_IPV4, "顺序 1 = LAN")
	_expect(candidates[1].path == LobbyPlayer.Path.IPV6, "顺序 2 = IPv6")
	_expect(candidates[2].path == LobbyPlayer.Path.WAN_IPV4, "顺序 3 = WAN")
	_expect(candidates[2].port == 49152, "WAN 候选用自己的端口")

## SessionState：首个可用远端候选 / observed endpoint 就绪判定。
func _case_session_state_helpers() -> void:
	var session: RendezvousContract.SessionState = RendezvousContract.SessionState.new()
	_expect(not session.has_remote_candidates(), "初始无远端候选")
	_expect(session.first_usable_remote() == null, "无候选时返回 null")
	_expect(not session.has_local_observed_endpoint(), "初始无 observed endpoint")
	## 放一个不可用候选（端口 0）+ 一个可用候选：必须跳过坏的拿好的。
	var broken: RendezvousContract.Candidate = RendezvousContract.Candidate.new()
	broken.path = LobbyPlayer.Path.LAN_IPV4
	broken.address = LAN
	broken.port = 0
	var good: RendezvousContract.Candidate = RendezvousContract.Candidate.new()
	good.path = LobbyPlayer.Path.WAN_IPV4
	good.address = WAN
	good.port = 49152
	session.remote_candidates.append(broken)
	session.remote_candidates.append(good)
	_expect(session.has_remote_candidates(), "有远端候选")
	var picked: RendezvousContract.Candidate = session.first_usable_remote()
	_expect(picked != null and picked.address == WAN, "跳过不可用候选，取第一个可用的")
	session.local_observed_address = WAN
	session.local_observed_port = 51820
	_expect(session.has_local_observed_endpoint(), "填上观测端点 -> true")
	## to_dict 可序列化（诊断用），且不含 ticket。
	var dict: Dictionary = session.to_dict()
	_expect(dict.has("local_nonce") and dict.has("remote_nonce"), "to_dict 含 nonce 字段")
	_expect(dict.has("local_observed_address"), "to_dict 含 observed 字段")
	_expect(not dict.has("ticket"), "SessionState.to_dict 不含 ticket")

## nonce / session_id / room_id / ticket / role 的合法性判定必须一致且严格。
func _case_nonce_and_id_validation() -> void:
	var a: String = RendezvousContract.generate_nonce()
	var b: String = RendezvousContract.generate_nonce()
	_expect(a.length() == 32, "nonce 是 32 位 hex（128 bit）")
	_expect(a != b, "两次生成的 nonce 不同")
	_expect(a != TICKET, "nonce 与 ticket 不同源")
	_expect(RendezvousContract.is_valid_nonce(a), "合法 nonce 通过")
	_expect(not RendezvousContract.is_valid_nonce(""), "空 nonce 被拒")
	_expect(not RendezvousContract.is_valid_nonce("zzzz"), "非 hex nonce 被拒")
	_expect(not RendezvousContract.is_valid_nonce(a.substr(0, 30)), "长度不足的 nonce 被拒")
	## session_id。
	_expect(RendezvousContract.is_valid_session_id(SID), "合法 session_id 通过")
	_expect(not RendezvousContract.is_valid_session_id(""), "空 session_id 被拒")
	_expect(not RendezvousContract.is_valid_session_id("not-hex-string!"), "非 hex session_id 被拒")
	## room_id：只允许安全字符。
	_expect(RendezvousContract.is_valid_room_id(ROOM), "合法 room_id 通过")
	_expect(not RendezvousContract.is_valid_room_id(""), "空 room_id 被拒")
	_expect(not RendezvousContract.is_valid_room_id("bad room"), "带空格的 room_id 被拒")
	## ticket：hex，8..64；绝不是 identity。
	_expect(RendezvousContract.is_valid_ticket(TICKET), "合法 ticket 通过")
	_expect(not RendezvousContract.is_valid_ticket(""), "空 ticket 被拒")
	_expect(not RendezvousContract.is_valid_ticket("short"), "过短 ticket 被拒")
	## role。
	_expect(RendezvousContract.is_valid_role(RendezvousContract.Role.HOST), "HOST 合法")
	_expect(RendezvousContract.is_valid_role(RendezvousContract.Role.GUEST), "GUEST 合法")
	_expect(not RendezvousContract.is_valid_role(7), "非法 role 被拒")

## 日志安全摘要必须**绝不**含完整 ticket —— 只留 session/role/nonce 短摘要/observed。
func _case_log_summary_hides_ticket() -> void:
	var summary: String = RendezvousContract.safe_summary(
		RendezvousContract.MsgType.REGISTER, SID, RendezvousContract.Role.GUEST,
		"aabbccddeeff00112233445566778899", WAN, 40000
	)
	_expect(not summary.contains(TICKET), "摘要不含完整 ticket")
	_expect(summary.contains(SID), "摘要含 session_id")
	_expect(summary.contains("guest"), "摘要含 role")
	_expect(summary.contains("aabbccdd"), "摘要含 nonce 短摘要")
	_expect(not summary.contains("aabbccddeeff00112233445566778899"), "摘要不含完整 nonce")
	_expect(summary.contains(WAN), "摘要含 observed address")
	## nonce_summary 本身永不返回完整 nonce。
	_expect(RendezvousContract.nonce_summary("aabbccdd11223344") == "aabbccdd", "nonce_summary 只取前 8 位")
	_expect(RendezvousContract.nonce_summary("") == "-", "空 nonce 摘要为 -")

## contract 层不许碰 ENet：它只描述数据。
func _case_no_enet_in_contract() -> void:
	var peer: MultiplayerPeer = root.multiplayer.multiplayer_peer
	var active: bool = peer != null and not (peer is OfflineMultiplayerPeer)
	_expect(not active, "contract 测试全程没有 active peer")

# ---- 辅助 ----

func _sample_candidates() -> Array[RendezvousContract.Candidate]:
	var invite: JoinInvite = JoinInvite.create(LAN, 17777, "", ROOM, "", V6, WAN, 49152)
	return RendezvousContract.candidates_from_invite(invite)

func _expect(condition: bool, label: String) -> void:
	if not condition:
		_failures.append(label)

func _finish() -> void:
	if _failures.is_empty():
		print("RENDEZVOUS_CONTRACT_OK")
		quit(0)
		return
	for failure: String in _failures:
		printerr("RENDEZVOUS_CONTRACT_FAIL: %s" % failure)
	quit(1)
