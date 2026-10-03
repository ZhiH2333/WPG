extends SceneTree

## Rendezvous contract 回归（Phase 9.1）。锁定：
## - 包格式版本化：magic / version 不符必须被拒
## - 编解码往返一致（identity / candidates / observed endpoint）
## - 候选只从 invite 真实提供的路径产生，缺的不伪造
## - observed/public endpoint 字段存在但**不被本地地址伪造**
## - rendezvous 只交换信息：不碰 ENet、不承载游戏流量
##
## 跑法：godot --headless --path . --script res://tests/rendezvous_contract_test.gd
## 通过输出 RENDEZVOUS_CONTRACT_OK；失败逐条 RENDEZVOUS_CONTRACT_FAIL 并返回非 0。

const ROOM := "a1b2c3d4"
const TICKET := "0f1e2d3c4b5a69788796a5b4c3d2e1f0"
const LAN := "192.168.1.20"
const WAN := "203.0.113.7"
const V6 := "fe80::1c2d:3e4f:5a6b:7c8d"

var _failures: PackedStringArray = PackedStringArray()

func _initialize() -> void:
	_run_all.call_deferred()

func _run_all() -> void:
	_case_version_is_independent()
	_case_magic_and_version_guards()
	_case_register_roundtrip()
	_case_candidates_roundtrip()
	_case_observed_endpoint_is_not_faked()
	_case_candidates_from_invite_only_real_paths()
	_case_candidates_from_invite_ordering()
	_case_session_state_helpers()
	_case_nonce_is_not_identity()
	_case_no_enet_in_contract()
	_finish()

# ---- 用例 ----

## rendezvous 版本与游戏协议号分离：各自演进，不互相绑死。
func _case_version_is_independent() -> void:
	_expect(RendezvousContract.VERSION >= 1, "contract 有版本号")
	_expect(RendezvousContract.MAGIC == 0x57504752, "magic = WPGR")
	_expect(RendezvousContract.NONCE_BYTES == 16, "nonce 128 bit")
	_expect(RendezvousContract.Transport.UDP == 0, "transport 枚举含 UDP")
	_expect(RendezvousContract.role_name(RendezvousContract.Role.HOST) == "host", "role_name 覆盖 host")
	_expect(RendezvousContract.role_name(RendezvousContract.Role.GUEST) == "guest", "role_name 覆盖 guest")

## magic / version / type 三道门必须都能挡住垃圾包。
func _case_magic_and_version_guards() -> void:
	var empty: RendezvousContract.Decoded = RendezvousContract.decode(PackedByteArray())
	_expect(empty.error == RendezvousContract.DecodeError.EMPTY, "空包 -> EMPTY")
	var junk: PackedByteArray = PackedByteArray()
	junk.resize(8)
	junk.fill(0x41)
	var bad_magic: RendezvousContract.Decoded = RendezvousContract.decode(junk)
	_expect(bad_magic.error == RendezvousContract.DecodeError.BAD_MAGIC, "magic 不符 -> BAD_MAGIC")
	## 正确 magic，但版本号 +1。
	var wrong_version: PackedByteArray = PackedByteArray()
	var buf: StreamPeerBuffer = StreamPeerBuffer.new()
	buf.big_endian = true
	buf.put_u32(RendezvousContract.MAGIC)
	buf.put_u8(RendezvousContract.VERSION + 1)
	buf.put_u8(RendezvousContract.MsgType.BYE)
	wrong_version = buf.data_array
	var bad_version: RendezvousContract.Decoded = RendezvousContract.decode(wrong_version)
	_expect(bad_version.error == RendezvousContract.DecodeError.BAD_VERSION, "version 不符 -> BAD_VERSION")
	## 未知消息类型。
	var unknown: PackedByteArray = PackedByteArray()
	var buf2: StreamPeerBuffer = StreamPeerBuffer.new()
	buf2.big_endian = true
	buf2.put_u32(RendezvousContract.MAGIC)
	buf2.put_u8(RendezvousContract.VERSION)
	buf2.put_u8(99)
	unknown = buf2.data_array
	var bad_type: RendezvousContract.Decoded = RendezvousContract.decode(unknown)
	_expect(bad_type.error == RendezvousContract.DecodeError.BAD_TYPE, "未知 type -> BAD_TYPE")

## REGISTER 往返：room_id / ticket / protocol / role / nonce 全部保真。
func _case_register_roundtrip() -> void:
	var identity: RendezvousContract.SessionIdentity = RendezvousContract.make_identity(
		ROOM,
		TICKET,
		GameLaunch.NET_PROTOCOL,
		RendezvousContract.Role.GUEST
	)
	var candidates: Array[RendezvousContract.Candidate] = _sample_candidates()
	var raw: PackedByteArray = RendezvousContract.encode(RendezvousContract.MsgType.REGISTER, identity, candidates)
	_expect(not raw.is_empty(), "REGISTER 编码非空")
	var decoded: RendezvousContract.Decoded = RendezvousContract.decode(raw)
	_expect(decoded.is_ok(), "REGISTER 解码成功")
	_expect(decoded.msg_type == RendezvousContract.MsgType.REGISTER, "type 保真")
	_expect(decoded.identity.room_id == ROOM, "room_id 保真")
	_expect(decoded.identity.ticket == TICKET, "ticket 保真")
	_expect(decoded.identity.protocol == GameLaunch.NET_PROTOCOL, "protocol 保真")
	_expect(decoded.identity.role == RendezvousContract.Role.GUEST, "role 保真")
	_expect(decoded.identity.nonce == identity.nonce, "nonce 保真")
	_expect(decoded.candidates.size() == candidates.size(), "候选数量保真")

## CANDIDATES 往返：transport / path / port / address 全部保真。
func _case_candidates_roundtrip() -> void:
	var identity: RendezvousContract.SessionIdentity = RendezvousContract.make_identity(
		ROOM, TICKET, GameLaunch.NET_PROTOCOL, RendezvousContract.Role.HOST
	)
	var candidates: Array[RendezvousContract.Candidate] = _sample_candidates()
	var raw: PackedByteArray = RendezvousContract.encode(RendezvousContract.MsgType.CANDIDATES, identity, candidates)
	var decoded: RendezvousContract.Decoded = RendezvousContract.decode(raw)
	_expect(decoded.is_ok(), "CANDIDATES 解码成功")
	_expect(decoded.candidates.size() == 3, "三个候选都往返")
	var first: RendezvousContract.Candidate = decoded.candidates[0]
	_expect(first.transport == RendezvousContract.Transport.UDP, "transport 保真")
	_expect(first.path == LobbyPlayer.Path.LAN_IPV4, "path 保真")
	_expect(first.address == LAN, "address 保真")
	_expect(first.port == 17777, "port 保真")

## observed/public endpoint 是为后续 NAT 穿透预留的字段：
## 没有 STUN 就没有真实观测值，**绝不用本地地址伪造**。
func _case_observed_endpoint_is_not_faked() -> void:
	var candidates: Array[RendezvousContract.Candidate] = RendezvousContract.candidates_from_invite(
		JoinInvite.create(LAN, 17777, "", ROOM)
	)
	_expect(candidates.size() == 1, "有一个候选")
	_expect(candidates[0].observed_address.is_empty(), "observed_address 默认空（不伪造）")
	_expect(candidates[0].observed_port == 0, "observed_port 默认 0（不伪造）")
	_expect(not candidates[0].has_observed_endpoint(), "has_observed_endpoint 默认 false")
	## 显式填上观测值后往返保真（9.2 打洞要用）。
	var candidate: RendezvousContract.Candidate = RendezvousContract.Candidate.new()
	candidate.path = LobbyPlayer.Path.WAN_IPV4
	candidate.address = "10.0.0.5"
	candidate.port = 49152
	candidate.observed_address = WAN
	candidate.observed_port = 51820
	_expect(candidate.has_observed_endpoint(), "显式观测端点 -> true")
	var identity: RendezvousContract.SessionIdentity = RendezvousContract.make_identity(
		ROOM, TICKET, GameLaunch.NET_PROTOCOL, RendezvousContract.Role.HOST
	)
	var raw: PackedByteArray = RendezvousContract.encode(
		RendezvousContract.MsgType.CANDIDATES, identity, [candidate] as Array[RendezvousContract.Candidate]
	)
	var decoded: RendezvousContract.Decoded = RendezvousContract.decode(raw)
	_expect(decoded.is_ok(), "带观测端点的包解码成功")
	_expect(decoded.candidates[0].observed_address == WAN, "observed_address 往返保真")
	_expect(decoded.candidates[0].observed_port == 51820, "observed_port 往返保真")

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

## SessionState：首个可用远端候选 / 有无候选。
func _case_session_state_helpers() -> void:
	var session: RendezvousContract.SessionState = RendezvousContract.SessionState.new()
	_expect(not session.has_remote_candidates(), "初始无远端候选")
	_expect(session.first_usable_remote() == null, "无候选时返回 null")
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
	## to_dict 可序列化（诊断用），且不含 ticket。
	var dict: Dictionary = session.to_dict()
	_expect(dict.has("local_nonce") and dict.has("remote_nonce"), "to_dict 含 nonce 字段")
	_expect(not dict.has("ticket"), "SessionState.to_dict 不含 ticket")

## nonce 只是关联用，不是身份、不是 ticket。
func _case_nonce_is_not_identity() -> void:
	var a: String = RendezvousContract.generate_nonce()
	var b: String = RendezvousContract.generate_nonce()
	_expect(a.length() == 32, "nonce 是 32 位 hex（128 bit）")
	_expect(a != b, "两次生成的 nonce 不同")
	_expect(a != TICKET, "nonce 与 ticket 不同源")
	var identity: RendezvousContract.SessionIdentity = RendezvousContract.make_identity(
		ROOM, TICKET, GameLaunch.NET_PROTOCOL, RendezvousContract.Role.GUEST
	)
	_expect(identity.is_valid(), "完整 identity 合法")
	_expect(not identity.nonce.is_empty(), "make_identity 自动生成 nonce")
	_expect(identity.nonce != identity.ticket, "nonce != ticket")
	## nonce 相同不代表身份相同：ticket 才是门票。
	var same_nonce: RendezvousContract.SessionIdentity = RendezvousContract.make_identity(
		ROOM, "deadbeefdeadbeef", GameLaunch.NET_PROTOCOL, RendezvousContract.Role.GUEST, identity.nonce
	)
	_expect(same_nonce.nonce == identity.nonce and same_nonce.ticket != identity.ticket, "nonce 相同但 ticket 不同 = 不同凭据")

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
