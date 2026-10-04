extends SceneTree

## RendezvousClient 回归（Phase 9.2.1）。锁定：
## - 客户端**不创建** ENetMultiplayerPeer、**不碰** SceneTree.multiplayer（用 PacketPeerUDP）
## - REGISTERED 记录的是**服务端给**的 observed endpoint，客户端自己绝不伪造
## - 本端候选的 observed 字段在发出前必须为空
## - CANDIDATES 驱动 P2PConnection: RENDEZVOUS_REGISTERED -> CANDIDATES_RECEIVED
## - 协议不符 / ticket 被拒 / 超时都是**明确终态**，且不留下 socket / ENet peer
## - 串台保护：session_id / nonce 不一致的回包一律丢弃
## - 客户端能真实经 UDP 与本地 rendezvous server 通信（由 tools/ci/rendezvous_e2e.py
##   做双进程验证；这里做的是「不依赖 server」的纯本地行为 + 真 UDP socket 绑定）
##
## 跑法：godot --headless --path . --script res://tests/rendezvous_client_test.gd
## 通过输出 RENDEZVOUS_CLIENT_OK；失败逐条 RENDEZVOUS_CLIENT_FAIL 并返回非 0。

const TICKET := "0f1e2d3c4b5a69788796a5b4c3d2e1f0"
const ROOM := "a1b2c3d4"
const SID := "0123456789abcdef"
const HOST_OBSERVED := "203.0.113.7"
const LAN := "192.168.1.20"

var _failures: PackedStringArray = PackedStringArray()

func _initialize() -> void:
	_run_all.call_deferred()

func _run_all() -> void:
	_case_no_enet_and_no_scenetree_peer()
	_case_begin_requires_valid_identity()
	_case_register_payload_carries_no_observed()
	_case_registered_sets_server_observed_endpoint()
	_case_candidates_advance_state_machine()
	_case_version_mismatch_is_terminal()
	_case_ticket_rejected_is_terminal()
	_case_timeout_closes_socket()
	_case_stale_session_id_is_dropped()
	_case_nonce_mismatch_is_dropped()
	_case_client_never_fabricates_observed()
	_case_bad_packet_does_not_change_state()
	_case_close_is_idempotent()
	_case_p2p_connection_uses_rendezvous()
	_finish()

# ---- 用例 ----

## 架构硬约束：客户端只用 PacketPeerUDP，绝不创建 ENet peer。
func _case_no_enet_and_no_scenetree_peer() -> void:
	var source: String = FileAccess.get_file_as_string("res://lobby/rendezvous_client.gd")
	_expect(not source.is_empty(), "能读到 rendezvous_client.gd")
	## 只检查**代码**，不检查注释：注释里会写「禁止 ENetMultiplayerPeer」这类说明。
	var code: String = _strip_comments(source)
	_expect(not code.contains("ENetMultiplayerPeer"), "rendezvous_client 代码不含 ENetMultiplayerPeer")
	_expect(not code.contains("multiplayer."), "rendezvous_client 代码不碰 SceneTree.multiplayer")
	_expect(code.contains("PacketPeerUDP"), "rendezvous_client 用 PacketPeerUDP")
	_expect(not _has_active_peer(), "本测试全程没有 active ENet peer")

## 去掉 GDScript 行注释（与 tools/ci/architecture.py 同款语义）。
func _strip_comments(source: String) -> String:
	var lines: PackedStringArray = PackedStringArray()
	for line: String in source.split("\n"):
		if line.strip_edges().begins_with("#"):
			continue
		lines.append(line)
	return "\n".join(lines)

## identity 不合法（无 room_id / ticket / nonce）时不允许开始。
func _case_begin_requires_valid_identity() -> void:
	var client: RendezvousClient = RendezvousClient.new()
	var bad: RendezvousContract.SessionIdentity = RendezvousContract.SessionIdentity.new()
	_expect(not client.begin("127.0.0.1", RendezvousClient.DEFAULT_PORT, bad, []), "非法 identity 被拒")
	_expect(client.get_state() == RendezvousClient.State.IDLE, "拒绝后仍是 IDLE")
	var no_host: RendezvousContract.SessionIdentity = _identity()
	_expect(not client.begin("", RendezvousClient.DEFAULT_PORT, no_host, []), "空 host 被拒")
	client.reset()

## 发出去的 REGISTER 里，本端候选的 observed 必须为空（只有服务端能填）。
func _case_register_payload_carries_no_observed() -> void:
	var plan: ConnectionPath = ConnectionPath.from_address(LAN, 17777)
	var candidates: Array[RendezvousContract.Candidate] = []
	for entry: ConnectionPath.Candidate in plan.ordered_candidates():
		var candidate: RendezvousContract.Candidate = RendezvousContract.Candidate.new()
		candidate.path = entry.path
		candidate.address = entry.address
		candidate.port = entry.port
		## 故意预填一个假 observed：客户端必须把它清掉。
		candidate.observed_address = "1.2.3.4"
		candidate.observed_port = 9999
		candidates.append(candidate)
	var client: RendezvousClient = RendezvousClient.new()
	## 只验证 clone 逻辑：begin 会真的发 UDP，这里直接看它内部克隆结果。
	var cloned: Array[RendezvousContract.Candidate] = client._clone_candidates(candidates)
	_expect(cloned.size() == 1, "克隆出 1 个候选")
	_expect(cloned[0].observed_address.is_empty(), "发出前 observed_address 被清空")
	_expect(cloned[0].observed_port == 0, "发出前 observed_port 被清空")
	_expect(cloned[0].address == LAN, "真实地址保留")
	client.reset()

## REGISTERED：observed endpoint 来自服务端，客户端照单收下。
func _case_registered_sets_server_observed_endpoint() -> void:
	var client: RendezvousClient = RendezvousClient.new()
	_prepare(client)
	_expect(client.get_state() == RendezvousClient.State.REGISTERING, "开始后是 REGISTERING")
	## 先确认没有观测端点。
	_expect(not client.has_observed_endpoint(), "注册前没有 observed endpoint")
	## 模拟服务端回 REGISTERED。
	_feed(client, RendezvousContract.encode_registered(
		SID, client.get_session().local_nonce, HOST_OBSERVED, 51820,
		[] as Array[RendezvousContract.Candidate]
	))
	_expect(client.get_state() == RendezvousClient.State.REGISTERED, "收到 REGISTERED -> REGISTERED")
	_expect(client.has_observed_endpoint(), "已拿到 observed endpoint")
	var session: RendezvousContract.SessionState = client.get_session()
	_expect(session.local_observed_address == HOST_OBSERVED, "observed_address = 服务端给的值")
	_expect(session.local_observed_port == 51820, "observed_port = 服务端给的值")
	_expect(session.rendezvous_id == SID, "session_id 已记录")
	client.reset()

## CANDIDATES：远端候选 + 远端 observed，驱动状态机。
func _case_candidates_advance_state_machine() -> void:
	var client: RendezvousClient = RendezvousClient.new()
	_prepare(client)
	_feed(client, RendezvousContract.encode_registered(
		SID, client.get_session().local_nonce, HOST_OBSERVED, 51820, [] as Array[RendezvousContract.Candidate]
	))
	var remote: Array[RendezvousContract.Candidate] = []
	var candidate: RendezvousContract.Candidate = RendezvousContract.Candidate.new()
	candidate.path = LobbyPlayer.Path.WAN_IPV4
	candidate.address = "10.0.0.5"
	candidate.port = 49152
	candidate.observed_address = HOST_OBSERVED
	candidate.observed_port = 51820
	remote.append(candidate)
	var seen: Array = [0]
	client.candidates_received.connect(func(_c: Array, _n: String, _r: int) -> void: seen[0] += 1)
	_feed(client, RendezvousContract.encode_candidates(
		SID, client.get_session().local_nonce, "ffffffffffffffffffffffffffffffff",
		RendezvousContract.Role.HOST, HOST_OBSERVED, 51820, remote
	))
	_expect(client.get_state() == RendezvousClient.State.CANDIDATES, "收到 CANDIDATES")
	_expect(int(seen[0]) == 1, "candidates_received 派发一次")
	var session: RendezvousContract.SessionState = client.get_session()
	_expect(session.remote_candidates.size() == 1, "远端候选已记录")
	_expect(session.remote_nonce == "ffffffffffffffffffffffffffffffff", "远端 nonce 已记录")
	_expect(session.remote_observed_address == HOST_OBSERVED, "远端 observed 已记录")
	_expect(session.first_usable_remote() != null, "有可用远端候选")
	client.reset()

## 服务端报协议不符 -> 明确失败，不再是 active。
func _case_version_mismatch_is_terminal() -> void:
	var client: RendezvousClient = RendezvousClient.new()
	_prepare(client)
	var errors: Array = [0]
	client.server_error.connect(func(_code: int, _detail: String) -> void: errors[0] += 1)
	_feed(client, RendezvousContract.encode_error(
		SID, RendezvousContract.ErrorCode.BAD_PROTOCOL, "bad protocol"
	))
	_expect(client.get_state() == RendezvousClient.State.FAILED, "BAD_PROTOCOL -> FAILED")
	_expect(client.is_failed(), "is_failed() == true")
	_expect(int(errors[0]) == 1, "server_error 派发一次")
	_expect(client.last_error() == RendezvousContract.ErrorCode.BAD_PROTOCOL, "错误码已记录")
	_expect(not client.is_active(), "失败后不再 active")
	client.reset()

## 服务端报 ticket 被拒 -> 明确失败。
func _case_ticket_rejected_is_terminal() -> void:
	var client: RendezvousClient = RendezvousClient.new()
	_prepare(client)
	_feed(client, RendezvousContract.encode_error(
		SID, RendezvousContract.ErrorCode.BAD_TICKET, "ticket mismatch"
	))
	_expect(client.get_state() == RendezvousClient.State.FAILED, "BAD_TICKET -> FAILED")
	_expect(client.last_error() == RendezvousContract.ErrorCode.BAD_TICKET, "错误码 = BAD_TICKET")
	client.reset()

## 超时：进入 TIMEOUT、关 socket、不留 ENet peer。
func _case_timeout_closes_socket() -> void:
	var client: RendezvousClient = RendezvousClient.new()
	_prepare(client)
	var fired: Array = [0]
	client.timed_out.connect(func(_reason: String) -> void: fired[0] += 1)
	var did_timeout: bool = client.tick(RendezvousContract.RENDEZVOUS_TIMEOUT_SEC + 0.1)
	_expect(did_timeout, "推进超过 RENDEZVOUS_TIMEOUT 触发超时")
	_expect(client.get_state() == RendezvousClient.State.TIMEOUT, "-> TIMEOUT")
	_expect(int(fired[0]) == 1, "timed_out 派发一次")
	_expect(client._udp == null, "超时后 UDP socket 已关闭")
	_expect(not _has_active_peer(), "超时后没有 active ENet peer")
	## 超时后再推进不应重复触发。
	_expect(not client.tick(1.0), "超时后不再重复触发")
	client.reset()

## 串台保护：session_id 不一致的回包必须丢弃。
func _case_stale_session_id_is_dropped() -> void:
	var client: RendezvousClient = RendezvousClient.new()
	_prepare(client)
	_feed(client, RendezvousContract.encode_registered(
		SID, client.get_session().local_nonce, HOST_OBSERVED, 51820, [] as Array[RendezvousContract.Candidate]
	))
	_expect(client.get_session().rendezvous_id == SID, "先绑定 session_id")
	## 另一个 session 的 CANDIDATES：必须被丢弃。
	var remote: Array[RendezvousContract.Candidate] = []
	var candidate: RendezvousContract.Candidate = RendezvousContract.Candidate.new()
	candidate.address = "10.0.0.9"
	candidate.port = 1111
	remote.append(candidate)
	_feed(client, RendezvousContract.encode_candidates(
		"ffffffffffffffff", client.get_session().local_nonce, "abc", RendezvousContract.Role.HOST,
		"198.51.100.1", 2222, remote
	))
	_expect(client.get_state() == RendezvousClient.State.REGISTERED, "别的 session 的包不改状态")
	_expect(client.get_session().remote_candidates.is_empty(), "别的 session 的候选未被采纳")
	client.reset()

## nonce 不回显自己 -> REGISTERED 必须被丢弃（防串台）。
func _case_nonce_mismatch_is_dropped() -> void:
	var client: RendezvousClient = RendezvousClient.new()
	_prepare(client)
	_feed(client, RendezvousContract.encode_registered(
		SID, "00000000000000000000000000000000", HOST_OBSERVED, 51820,
		[] as Array[RendezvousContract.Candidate]
	))
	_expect(client.get_state() == RendezvousClient.State.REGISTERING, "nonce 不符的 REGISTERED 被丢弃")
	_expect(not client.has_observed_endpoint(), "未采纳伪造的 observed endpoint")
	client.reset()

## 核心约束：客户端绝不自己编造 observed endpoint。
func _case_client_never_fabricates_observed() -> void:
	var client: RendezvousClient = RendezvousClient.new()
	_prepare(client)
	## 没有任何服务端回包时，observed 必须保持为空 —— 哪怕本地地址已知。
	_expect(not client.has_observed_endpoint(), "无服务端应答时没有 observed endpoint")
	var session: RendezvousContract.SessionState = client.get_session()
	_expect(session.local_observed_address.is_empty(), "local_observed_address 为空")
	_expect(session.local_observed_port == 0, "local_observed_port 为 0")
	## 也绝不把本地 LAN 地址当作公网观测值。
	_expect(session.local_observed_address != LAN, "本地地址没有被当成 observed")
	client.reset()

## 坏包 / 空包不改状态、不崩。
func _case_bad_packet_does_not_change_state() -> void:
	var client: RendezvousClient = RendezvousClient.new()
	_prepare(client)
	var before: int = int(client.get_state())
	_feed(client, PackedByteArray())
	var junk: PackedByteArray = PackedByteArray()
	junk.resize(32)
	junk.fill(0x42)
	_feed(client, junk)
	## 版本不符的包。
	var wrong_version: StreamPeerBuffer = StreamPeerBuffer.new()
	wrong_version.big_endian = true
	wrong_version.put_u32(RendezvousContract.MAGIC)
	wrong_version.put_u8(1)
	wrong_version.put_u8(RendezvousContract.MsgType.BYE)
	wrong_version.put_u32(0)
	_feed(client, wrong_version.data_array)
	_expect(int(client.get_state()) == before, "坏包不改状态")
	_expect(not client.is_failed(), "坏包不导致失败")
	client.reset()

## close / reset 可重复调用，不崩、不留 socket。
func _case_close_is_idempotent() -> void:
	var client: RendezvousClient = RendezvousClient.new()
	_prepare(client)
	client.close()
	client.close()
	_expect(client._udp == null, "close 后 socket 为空")
	client.reset()
	client.reset()
	_expect(client.get_state() == RendezvousClient.State.IDLE, "reset 后回到 IDLE")
	_expect(client.get_session() == null, "reset 清空 session")
	_expect(client.get_identity() == null, "reset 清空 identity")

## P2PConnection 接入：真实 rendezvous 驱动
## RENDEZVOUS_CONNECTING -> RENDEZVOUS_REGISTERED -> CANDIDATES_RECEIVED，
## 而不是直接假装 CONNECTED。
func _case_p2p_connection_uses_rendezvous() -> void:
	var client: RendezvousClient = RendezvousClient.new()
	var p2p: P2PConnection = P2PConnection.new()
	p2p.bind_rendezvous(client)
	p2p.bind_transport(_noop_connect, _noop_close)
	_expect(p2p.uses_rendezvous(), "已绑定 rendezvous")
	var invite: JoinInvite = JoinInvite.create(LAN, 17777, TICKET, ROOM, "", "", HOST_OBSERVED, 49152)
	var started: bool = p2p.begin(invite, "127.0.0.1", RendezvousClient.DEFAULT_PORT)
	_expect(started, "begin 成功发起注册")
	_expect(
		p2p.get_state_value() == P2PConnectionState.State.RENDEZVOUS_CONNECTING,
		"状态 = RENDEZVOUS_CONNECTING（**不是**直接 CONNECTED）"
	)
	_expect(not p2p.is_connection_established(), "绝不假装已 CONNECTED")
	## 服务端 REGISTERED。
	_feed(client, RendezvousContract.encode_registered(
		SID, client.get_session().local_nonce, HOST_OBSERVED, 51820, [] as Array[RendezvousContract.Candidate]
	))
	_expect(
		p2p.get_state_value() == P2PConnectionState.State.RENDEZVOUS_REGISTERED,
		"-> RENDEZVOUS_REGISTERED"
	)
	_expect(p2p.get_session().local_observed_address == HOST_OBSERVED, "P2PConnection 拿到本端 observed")
	## 服务端 CANDIDATES。
	var remote: Array[RendezvousContract.Candidate] = []
	var candidate: RendezvousContract.Candidate = RendezvousContract.Candidate.new()
	candidate.path = LobbyPlayer.Path.WAN_IPV4
	candidate.address = "10.0.0.5"
	candidate.port = 49152
	candidate.observed_address = HOST_OBSERVED
	candidate.observed_port = 51820
	remote.append(candidate)
	_feed(client, RendezvousContract.encode_candidates(
		SID, client.get_session().local_nonce, "ffffffffffffffffffffffffffffffff",
		RendezvousContract.Role.HOST, HOST_OBSERVED, 51820, remote
	))
	## Phase 9.2.2 R2：候选到达后自动进入 DIRECT_PROBING（不允许外部忘记调用）。
	_expect(
		p2p.get_state_value() == P2PConnectionState.State.DIRECT_PROBING,
		"-> DIRECT_PROBING（候选取到后自动触发 probing）"
	)
	_expect(p2p.get_session().remote_candidates.size() == 1, "远端候选已进 P2PConnection")
	_expect(p2p.get_session().remote_observed_address == HOST_OBSERVED, "远端 observed 已进 P2PConnection")
	_expect(not p2p.is_connection_established(), "到此仍未 CONNECTED（打洞是 9.2.2）")
	## 共享 UDP ownership：P2PConnection 拥有；client 与 hole punch 都只是引用。
	_expect(p2p.has_shared_udp(), "P2PConnection 创建了共享 UDP")
	_expect(client.owns_udp() == false, "RendezvousClient 不拥有共享 UDP")
	_expect(p2p._hole_punch != null and p2p._hole_punch.owns_socket() == false, "P2PHolePunch 不拥有共享 UDP")
	## client.close() 不得关闭 owner 的共享 socket。
	var shared: PacketPeerUDP = p2p.get_shared_udp()
	client.close_socket()
	_expect(shared.get_local_port() > 0, "client close 不关闭共享 UDP")
	## p2p.cancel() 是真正的 owner，必须关闭它。
	p2p.cancel()
	_expect(not p2p.has_shared_udp(), "cancel 后 owner 关闭共享 UDP")
	## 服务端报 ticket 被拒 -> P2PConnection 终态。
	var p2p2: P2PConnection = P2PConnection.new()
	var client2: RendezvousClient = RendezvousClient.new()
	p2p2.bind_rendezvous(client2)
	p2p2.bind_transport(_noop_connect, _noop_close)
	p2p2.begin(invite, "127.0.0.1", RendezvousClient.DEFAULT_PORT)
	_feed(client2, RendezvousContract.encode_error(
		SID, RendezvousContract.ErrorCode.BAD_TICKET, "ticket mismatch"
	))
	_expect(
		p2p2.get_state_value() == P2PConnectionState.State.TICKET_REJECTED,
		"rendezvous 报 BAD_TICKET -> P2PConnection TICKET_REJECTED"
	)
	p2p2.cancel()
	p2p.reset()
	client.reset()
	client2.reset()

# ---- 辅助 ----

func _identity() -> RendezvousContract.SessionIdentity:
	return RendezvousContract.make_identity(
		ROOM, TICKET, GameLaunch.NET_PROTOCOL, RendezvousContract.Role.GUEST
	)

## 准备一个已 begin 的客户端（真的 bind 了一个 UDP socket，但不真的有 server）。
func _prepare(client: RendezvousClient) -> void:
	var candidates: Array[RendezvousContract.Candidate] = []
	var candidate: RendezvousContract.Candidate = RendezvousContract.Candidate.new()
	candidate.path = LobbyPlayer.Path.LAN_IPV4
	candidate.address = LAN
	candidate.port = 17777
	candidates.append(candidate)
	## 指向一个几乎肯定没人监听的本地端口：begin 只发包不等回。
	client.begin("127.0.0.1", 1, _identity(), candidates)

## 直接注入一个包，绕过真实 UDP（测试状态机与解析行为）。
func _feed(client: RendezvousClient, packet: PackedByteArray) -> void:
	client._handle_packet(packet)

func _noop_connect(_address: String, _port: int, _ticket: String) -> bool:
	return true

func _noop_close() -> void:
	pass

func _has_active_peer() -> bool:
	var peer: MultiplayerPeer = root.multiplayer.multiplayer_peer
	if peer == null:
		return false
	return not (peer is OfflineMultiplayerPeer)

func _expect(condition: bool, label: String) -> void:
	if not condition:
		_failures.append(label)

func _finish() -> void:
	if _failures.is_empty():
		print("RENDEZVOUS_CLIENT_OK")
		quit(0)
		return
	for failure: String in _failures:
		printerr("RENDEZVOUS_CLIENT_FAIL: %s" % failure)
	quit(1)
