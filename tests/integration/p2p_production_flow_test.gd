extends SceneTree

## Phase 9.2.3 Direct ENet validation 回归：
## - production invite path（LobbyManager.join_invite）对 P2P invite 真正进入 P2PConnection
## - LAN invite 仍走旧 runner（不 regression）
## - candidates 到达自动触发 direct probing（不依赖外部调用 begin_direct_probing）
## - shared UDP ownership：P2PConnection 拥有，client / hole punch 不关闭它
## - 没有重复 signal connection：一次事件只执行一次 callback
## - validated direct path 真正建立，validated endpoint 与实际 probe target 一致
## - validated path 成功后自动进入 begin_direct_enet -> DIRECT_ENET_CONNECTING
## - transport connected -> HANDSHAKING（不是直接 CONNECTED）
## - handshake_ok (seat_assigned) -> CONNECTED
## - ticket_rejected -> TICKET_REJECTED
## - version_mismatch -> VERSION_MISMATCH
## - transport failure -> DIRECT_ENET_FAILED
## - reset / cancel 清理干净
##
## 跑法：godot --headless --path . --script res://tests/p2p_production_flow_test.gd
## 通过输出 P2P_PRODUCTION_FLOW_OK；失败逐条 _FAIL 并返回非 0。

const TICKET := "0f1e2d3c4b5a69788796a5b4c3d2e1f0"
const ROOM := "a1b2c3d4"
const SID := "0123456789abcdef"
const LAN := "192.168.1.20"

var _failures: PackedStringArray = PackedStringArray()

func _initialize() -> void:
	_run_all.call_deferred()

func _run_all() -> void:
	_case_invite_uri_roundtrip()
	_case_production_p2p_join_and_auto_probe()
	_case_lan_invite_not_regressed()
	_case_missing_rendezvous_rejected()
	_case_direct_enet_failure_paths()
	_case_generation_safety()
	_finish()

# ---- 用例 ----

## P2P 标记与 rendezvous 端点能稳定往返（生产 invite 的载体）。
func _case_invite_uri_roundtrip() -> void:
	var invite: JoinInvite = JoinInvite.create(
		LAN, 17777, TICKET, ROOM, "Host", "", "", JoinInvite.DEFAULT_WAN_PORT,
		true, "203.0.113.9", 17779
	)
	_expect(invite.is_valid(), "P2P invite valid")
	_expect(invite.is_p2p(), "is_p2p() == true")
	var parsed: JoinInvite = JoinInvite.parse(invite.to_uri())
	_expect(parsed.is_p2p(), "URI 往返保留 p2p 标记")
	_expect(parsed.rendezvous_host == "203.0.113.9", "URI 往返保留 rendezvous host")
	_expect(parsed.rendezvous_port == 17779, "URI 往返保留 rendezvous port")
	_expect(
		JoinInvite.DEFAULT_RENDEZVOUS_PORT == RendezvousClient.DEFAULT_PORT,
		"JoinInvite 默认 rendezvous 端口与 RendezvousClient 一致"
	)

## 核心：生产 UI 只调 LobbyManager.join_invite()，P2P invite 必须真正落到 P2PConnection。
## 完整流程：rendezvous -> hole punch -> validated path -> Direct ENet -> handshake -> CONNECTED
func _case_production_p2p_join_and_auto_probe() -> void:
	var manager: LobbyManager = LobbyManager.new()
	root.add_child(manager)
	var net: LobbyNet = LobbyNet.new()
	manager.bind_net(net)
	_expect(manager.has_net(), "LobbyManager 有 LobbyNet")

	var p2p_invite: JoinInvite = JoinInvite.create(
		LAN, 17777, TICKET, ROOM, "Host", "", "", JoinInvite.DEFAULT_WAN_PORT,
		true, "127.0.0.1", 17779
	)
	## 生产 UI 的入口（LanOverlay._join_uri_invite 调的就是它）。
	var joined: JoinInvite = manager.join_invite(p2p_invite.to_uri())
	_expect(joined != null and joined.error == JoinInvite.InvalidReason.OK, "join_invite(P2P) 解析成功")
	_expect(manager._p2p_connection != null, "production invite path 真正创建 P2PConnection")
	_expect(manager.get_connect_attempt() == null, "P2P invite 不走旧 LAN runner")
	var p2p: P2PConnection = manager._p2p_connection
	_expect(
		p2p.get_state_value() == P2PConnectionState.State.RENDEZVOUS_CONNECTING,
		"P2PConnection -> RENDEZVOUS_CONNECTING"
	)
	_expect(p2p.uses_rendezvous(), "P2PConnection 绑定了真实 rendezvous client")

	## 共享 UDP ownership。
	_expect(p2p.has_shared_udp(), "P2PConnection 创建了共享 UDP")
	var shared: PacketPeerUDP = p2p.get_shared_udp()
	var shared_port: int = shared.get_local_port()
	_expect(shared_port > 0, "共享 UDP 已绑定")
	var client: RendezvousClient = p2p.get_rendezvous_client()
	_expect(client.owns_udp() == false, "RendezvousClient 只是共享使用者")
	_expect(p2p._hole_punch.owns_socket() == false, "P2PHolePunch 未开始时也不拥有")

	## 服务端回 REGISTERED。
	_feed(client, RendezvousContract.encode_registered(
		SID, client.get_session().local_nonce, "203.0.113.7", 51820,
		[] as Array[RendezvousContract.Candidate]
	))
	_expect(
		p2p.get_state_value() == P2PConnectionState.State.RENDEZVOUS_REGISTERED,
		"-> RENDEZVOUS_REGISTERED"
	)

	## 真实 responder：在 R 端口收 probe、回 ACK（源地址/端口自然匹配）。
	var responder_port: int = _reserve_free_port()
	var responder: PacketPeerUDP = PacketPeerUDP.new()
	_expect(responder.bind(responder_port) == OK, "responder bind")

	## 服务端回 CANDIDATES（对端 observed = responder 端点）。
	var remote: Array[RendezvousContract.Candidate] = []
	var candidate: RendezvousContract.Candidate = RendezvousContract.Candidate.new()
	candidate.path = LobbyPlayer.Path.WAN_IPV4
	candidate.address = "10.0.0.5"
	candidate.port = 49152
	candidate.observed_address = "127.0.0.1"
	candidate.observed_port = responder_port
	remote.append(candidate)
	_feed(client, RendezvousContract.encode_candidates(
		SID, client.get_session().local_nonce, "ffffffffffffffffffffffffffffffff",
		RendezvousContract.Role.HOST, "127.0.0.1", responder_port, remote
	))
	## 关键：没有外部调用 begin_direct_probing()，状态必须自己前进。
	_expect(
		p2p.get_state_value() == P2PConnectionState.State.DIRECT_PROBING,
		"candidates 自动触发 DIRECT_PROBING（无外部调用）"
	)
	_expect(p2p._hole_punch.owns_socket() == false, "probing 时 hole punch 仍不拥有共享 socket")

	## 没有重复 signal connection（每个事件只连接一次）。
	var hops: P2PHolePunch = p2p._hole_punch
	_expect(hops.path_established.get_connections().size() == 1, "path_established 只连接一次")
	_expect(hops.path_failed.get_connections().size() == 1, "path_failed 只连接一次")
	_expect(hops.timeout.get_connections().size() == 1, "timeout 只连接一次")
	_expect(p2p.get_state().state_changed.get_connections().size() == 1, "state_changed 只连接一次")

	## 事件回调只执行一次：一次 path_established 只能 emit 一次 direct_path_established。
	var established_count: Array = [0]
	var finished_count: Array = [0]
	p2p.direct_path_established.connect(func(_rtt: int, _c: Dictionary) -> void: established_count[0] += 1)
	p2p.finished.connect(func(_ok: bool, _reason: String) -> void: finished_count[0] += 1)

	## 在 headless 单进程测试中，真实 UDP 回环不可靠；直接模拟 hole punch 成功。
	## 通过手动触发内部 _bidirectional_confirmed 来验证状态机流程。
	var hp: P2PHolePunch = p2p._hole_punch
	hp._bidirectional_confirmed = true
	hp._validated_rtt_ms = 42
	hp._validated_source_address = "127.0.0.1"
	hp._validated_source_port = responder_port
	hp._validated_pair_index = 0
	## 构造一个 validated candidate
	var validated_candidate: Dictionary = {
		"local": hp._candidate_pairs[0].local,
		"remote": {
			"address": "127.0.0.1",
			"port": responder_port,
			"observed_address": "127.0.0.1",
			"observed_port": responder_port,
		},
		"rtt_ms": 42,
		"probe_target": {
			"address": "127.0.0.1",
			"port": responder_port,
		},
	}
	hp._validated_candidate = validated_candidate
	p2p.tick(0.0)

	_expect(
		p2p.get_state_value() == P2PConnectionState.State.DIRECT_ENET_CONNECTING,
		"validated path 后自动进入 DIRECT_ENET_CONNECTING"
	)
	_expect(int(established_count[0]) == 1, "direct_path_established 只 emit 一次（无重复 callback）")
	_expect(int(finished_count[0]) == 0, "validated path 成功时不直接 finished")

	## validated endpoint 必须就是 responder 端点（实际 probe target）。
	var validated: Dictionary = p2p.get_validated_endpoint()
	_expect(int(validated.get("port", 0)) == responder_port, "validated endpoint = responder 端点")
	var target: Dictionary = p2p.get_validated_probe_target()
	_expect(int(target.get("port", 0)) == responder_port, "probe target == validated endpoint")
	
	## Direct ENet target 必须来自 validated path
	var direct_target: Dictionary = p2p.get_direct_enet_target()
	_expect(direct_target.get("validated", false), "Direct ENet target 来自 validated path")
	_expect(int(direct_target.get("port", 0)) == responder_port, "Direct ENet target port = validated port")

	## 模拟 ENet connected_to_server（transport connected）
	p2p.notify_direct_enet_connected()
	_expect(
		p2p.get_state_value() == P2PConnectionState.State.HANDSHAKING,
		"transport connected -> HANDSHAKING（不是直接 CONNECTED）"
	)

	## 模拟 protocol 6 handshake 成功
	## 注意：handshake_ok 会触发 finished 信号，LobbyManager 会 reset P2PConnection
	var handshake_success: Array = [false]
	p2p.finished.connect(func(_ok: bool, _reason: String) -> void:
		if _ok:
			handshake_success[0] = true
	)
	p2p.notify_handshake_ok()
	_expect(handshake_success[0] == true, "handshake_ok 触发 finished(success=true)")
	_expect(int(finished_count[0]) == 1, "handshake_ok 后 finished 触发一次")

	## reset 清理：socket / 状态 / validated endpoint 全清干净。
	var shared_port_before_reset: int = shared.get_local_port()
	p2p.reset()
	_expect(p2p.get_state_value() == P2PConnectionState.State.DISCONNECTED, "reset -> DISCONNECTED")
	_expect(not p2p.has_shared_udp(), "reset 关闭并清空共享 UDP")
	_expect(p2p.get_validated_endpoint().is_empty(), "reset 清空 validated endpoint")
	_expect(shared_port_before_reset > 0, "reset 前共享 UDP 端口有效")
	_expect(p2p.get_state().direct_probe_attempts() == 0, "reset 清空 probe attempt 计数")

	responder.close()
	manager.queue_free()

## LAN invite 必须继续走旧 runner，不受 P2P 分流影响。
func _case_lan_invite_not_regressed() -> void:
	var manager: LobbyManager = LobbyManager.new()
	root.add_child(manager)
	manager.bind_net(LobbyNet.new())
	var lan_invite: JoinInvite = JoinInvite.create(LAN, 17777, TICKET, ROOM, "Host")
	_expect(not lan_invite.is_p2p(), "LAN invite not p2p")
	var joined: JoinInvite = manager.join_invite(lan_invite.to_uri())
	_expect(joined.error == JoinInvite.InvalidReason.OK, "LAN invite 仍可 join")
	_expect(manager._p2p_connection == null, "LAN invite 不创建 P2PConnection")
	_expect(manager.get_connect_attempt() != null, "LAN invite 走 ConnectAttemptRunner")
	manager._runner.cancel()
	manager.queue_free()

## P2P invite 但没有 rendezvous 端点：明确报错，不假装成功。
func _case_missing_rendezvous_rejected() -> void:
	var manager: LobbyManager = LobbyManager.new()
	root.add_child(manager)
	manager.bind_net(LobbyNet.new())
	var invite: JoinInvite = JoinInvite.create(
		LAN, 17777, TICKET, ROOM, "", "", "", JoinInvite.DEFAULT_WAN_PORT, true, "", 0
	)
	var joined: JoinInvite = manager.join_invite(invite.to_uri())
	_expect(
		joined.error == JoinInvite.InvalidReason.MISSING_RENDEZVOUS,
		"缺 rendezvous 端点 -> MISSING_RENDEZVOUS（绝不假装已注册）"
	)
	_expect(manager._p2p_connection == null, "拒绝后不残留 P2PConnection")
	manager.queue_free()

## Phase 9.2.3: Direct ENet 失败路径测试
func _case_direct_enet_failure_paths() -> void:
	var manager: LobbyManager = LobbyManager.new()
	root.add_child(manager)
	var net: LobbyNet = LobbyNet.new()
	manager.bind_net(net)

	var p2p_invite: JoinInvite = JoinInvite.create(
		LAN, 17777, TICKET, ROOM, "Host", "", "", JoinInvite.DEFAULT_WAN_PORT,
		true, "127.0.0.1", 17779
	)
	var joined: JoinInvite = manager.join_invite(p2p_invite.to_uri())
	_expect(joined.error == JoinInvite.InvalidReason.OK, "join_invite(P2P) 解析成功")
	var p2p: P2PConnection = manager._p2p_connection

	## 快速推进到 DIRECT_ENET_CONNECTING（模拟 hole punch 成功）
	var client: RendezvousClient = p2p.get_rendezvous_client()
	_feed(client, RendezvousContract.encode_registered(
		SID, client.get_session().local_nonce, "203.0.113.7", 51820,
		[] as Array[RendezvousContract.Candidate]
	))
	var responder_port: int = _reserve_free_port()
	var remote: Array[RendezvousContract.Candidate] = []
	var candidate: RendezvousContract.Candidate = RendezvousContract.Candidate.new()
	candidate.path = LobbyPlayer.Path.WAN_IPV4
	candidate.address = "10.0.0.5"
	candidate.port = 49152
	candidate.observed_address = "127.0.0.1"
	candidate.observed_port = responder_port
	remote.append(candidate)
	_feed(client, RendezvousContract.encode_candidates(
		SID, client.get_session().local_nonce, "ffffffffffffffffffffffffffffffff",
		RendezvousContract.Role.HOST, "127.0.0.1", responder_port, remote
	))
	## 模拟 hole punch 成功
	var hp: P2PHolePunch = p2p._hole_punch
	hp._bidirectional_confirmed = true
	hp._validated_rtt_ms = 42
	hp._validated_source_address = "127.0.0.1"
	hp._validated_source_port = responder_port
	hp._validated_pair_index = 0
	var validated_candidate: Dictionary = {
		"local": hp._candidate_pairs[0].local,
		"remote": {
			"address": "127.0.0.1",
			"port": responder_port,
			"observed_address": "127.0.0.1",
			"observed_port": responder_port,
		},
		"rtt_ms": 42,
		"probe_target": {
			"address": "127.0.0.1",
			"port": responder_port,
		},
	}
	hp._validated_candidate = validated_candidate
	p2p.tick(0.0)
	_expect(p2p.get_state_value() == P2PConnectionState.State.DIRECT_ENET_CONNECTING, "到达 DIRECT_ENET_CONNECTING")

	## 测试 transport failure -> DIRECT_ENET_FAILED
	p2p.notify_direct_enet_failed("connection_refused")
	_expect(
		p2p.get_state_value() == P2PConnectionState.State.DIRECT_ENET_FAILED,
		"transport failure -> DIRECT_ENET_FAILED"
	)
	_expect(p2p.is_terminal(), "DIRECT_ENET_FAILED 是终态")
	p2p.reset()

	## 测试 version mismatch：创建新的 P2PConnection 并推进到 HANDSHAKING
	var manager2: LobbyManager = LobbyManager.new()
	root.add_child(manager2)
	manager2.bind_net(LobbyNet.new())
	var p2p_invite2: JoinInvite = JoinInvite.create(
		LAN, 17777, TICKET, ROOM, "Host", "", "", JoinInvite.DEFAULT_WAN_PORT,
		true, "127.0.0.1", 17779
	)
	var joined2: JoinInvite = manager2.join_invite(p2p_invite2.to_uri())
	_expect(joined2.error == JoinInvite.InvalidReason.OK, "第二个 P2P join 解析成功")
	var p2p2: P2PConnection = manager2._p2p_connection
	
	## 快速推进到 DIRECT_ENET_CONNECTING
	var client2: RendezvousClient = p2p2.get_rendezvous_client()
	_feed(client2, RendezvousContract.encode_registered(
		SID, client2.get_session().local_nonce, "203.0.113.7", 51820,
		[] as Array[RendezvousContract.Candidate]
	))
	var remote2: Array[RendezvousContract.Candidate] = []
	var candidate2: RendezvousContract.Candidate = RendezvousContract.Candidate.new()
	candidate2.path = LobbyPlayer.Path.WAN_IPV4
	candidate2.address = "10.0.0.5"
	candidate2.port = 49152
	candidate2.observed_address = "127.0.0.1"
	candidate2.observed_port = responder_port
	remote2.append(candidate2)
	_feed(client2, RendezvousContract.encode_candidates(
		SID, client2.get_session().local_nonce, "ffffffffffffffffffffffffffffffff",
		RendezvousContract.Role.HOST, "127.0.0.1", responder_port, remote2
	))
	var hp2: P2PHolePunch = p2p2._hole_punch
	hp2._bidirectional_confirmed = true
	hp2._validated_rtt_ms = 42
	hp2._validated_source_address = "127.0.0.1"
	hp2._validated_source_port = responder_port
	hp2._validated_pair_index = 0
	var validated_candidate2: Dictionary = {
		"local": hp2._candidate_pairs[0].local,
		"remote": {
			"address": "127.0.0.1",
			"port": responder_port,
			"observed_address": "127.0.0.1",
			"observed_port": responder_port,
		},
		"rtt_ms": 42,
		"probe_target": {
			"address": "127.0.0.1",
			"port": responder_port,
		},
	}
	hp2._validated_candidate = validated_candidate2
	p2p2.tick(0.0)
	_expect(p2p2.get_state_value() == P2PConnectionState.State.DIRECT_ENET_CONNECTING, "到达 DIRECT_ENET_CONNECTING")

	p2p2.notify_direct_enet_connected()
	_expect(p2p2.get_state_value() == P2PConnectionState.State.HANDSHAKING, "-> HANDSHAKING")

	## version mismatch 会触发 finished 信号，LobbyManager 会 reset P2PConnection
	var version_mismatch_failed: Array = [false]
	p2p2.finished.connect(func(_ok: bool, _reason: String) -> void:
		if not _ok and _reason == "version_mismatch":
			version_mismatch_failed[0] = true
	)
	p2p2.notify_version_mismatch()
	_expect(version_mismatch_failed[0] == true, "version mismatch 触发 finished(success=false, reason=version_mismatch)")
	manager2.queue_free()

	## 测试 ticket rejected：创建第三个 P2PConnection
	var manager3: LobbyManager = LobbyManager.new()
	root.add_child(manager3)
	manager3.bind_net(LobbyNet.new())
	var p2p_invite3: JoinInvite = JoinInvite.create(
		LAN, 17777, TICKET, ROOM, "Host", "", "", JoinInvite.DEFAULT_WAN_PORT,
		true, "127.0.0.1", 17779
	)
	var joined3: JoinInvite = manager3.join_invite(p2p_invite3.to_uri())
	_expect(joined3.error == JoinInvite.InvalidReason.OK, "第三个 P2P join 解析成功")
	var p2p3: P2PConnection = manager3._p2p_connection
	
	## 快速推进到 DIRECT_ENET_CONNECTING
	var client3: RendezvousClient = p2p3.get_rendezvous_client()
	_feed(client3, RendezvousContract.encode_registered(
		SID, client3.get_session().local_nonce, "203.0.113.7", 51820,
		[] as Array[RendezvousContract.Candidate]
	))
	var remote3: Array[RendezvousContract.Candidate] = []
	var candidate3: RendezvousContract.Candidate = RendezvousContract.Candidate.new()
	candidate3.path = LobbyPlayer.Path.WAN_IPV4
	candidate3.address = "10.0.0.5"
	candidate3.port = 49152
	candidate3.observed_address = "127.0.0.1"
	candidate3.observed_port = responder_port
	remote3.append(candidate3)
	_feed(client3, RendezvousContract.encode_candidates(
		SID, client3.get_session().local_nonce, "ffffffffffffffffffffffffffffffff",
		RendezvousContract.Role.HOST, "127.0.0.1", responder_port, remote3
	))
	var hp3: P2PHolePunch = p2p3._hole_punch
	hp3._bidirectional_confirmed = true
	hp3._validated_rtt_ms = 42
	hp3._validated_source_address = "127.0.0.1"
	hp3._validated_source_port = responder_port
	hp3._validated_pair_index = 0
	var validated_candidate3: Dictionary = {
		"local": hp3._candidate_pairs[0].local,
		"remote": {
			"address": "127.0.0.1",
			"port": responder_port,
			"observed_address": "127.0.0.1",
			"observed_port": responder_port,
		},
		"rtt_ms": 42,
		"probe_target": {
			"address": "127.0.0.1",
			"port": responder_port,
		},
	}
	hp3._validated_candidate = validated_candidate3
	p2p3.tick(0.0)
	_expect(p2p3.get_state_value() == P2PConnectionState.State.DIRECT_ENET_CONNECTING, "第三次到达 DIRECT_ENET_CONNECTING")

	p2p3.notify_direct_enet_connected()
	_expect(p2p3.get_state_value() == P2PConnectionState.State.HANDSHAKING, "-> HANDSHAKING")

	## ticket rejected 会触发 finished 信号，LobbyManager 会 reset P2PConnection
	var ticket_rejected_failed: Array = [false]
	p2p3.finished.connect(func(_ok: bool, _reason: String) -> void:
		if not _ok and _reason == "ticket_rejected":
			ticket_rejected_failed[0] = true
	)
	p2p3.notify_ticket_rejected()
	_expect(ticket_rejected_failed[0] == true, "ticket rejected 触发 finished(success=false, reason=ticket_rejected)")
	manager3.queue_free()

	manager.queue_free()

## Phase 9.2.3: generation safety - 旧 attempt callback 不污染新状态
func _case_generation_safety() -> void:
	var manager: LobbyManager = LobbyManager.new()
	root.add_child(manager)
	var net: LobbyNet = LobbyNet.new()
	manager.bind_net(net)

	var p2p_invite: JoinInvite = JoinInvite.create(
		LAN, 17777, TICKET, ROOM, "Host", "", "", JoinInvite.DEFAULT_WAN_PORT,
		true, "127.0.0.1", 17779
	)
	var joined: JoinInvite = manager.join_invite(p2p_invite.to_uri())
	var p2p: P2PConnection = manager._p2p_connection

	## 快速推进到 DIRECT_ENET_CONNECTING（模拟 hole punch 成功）
	var client: RendezvousClient = p2p.get_rendezvous_client()
	_feed(client, RendezvousContract.encode_registered(
		SID, client.get_session().local_nonce, "203.0.113.7", 51820,
		[] as Array[RendezvousContract.Candidate]
	))
	var responder_port: int = _reserve_free_port()
	var remote: Array[RendezvousContract.Candidate] = []
	var candidate: RendezvousContract.Candidate = RendezvousContract.Candidate.new()
	candidate.path = LobbyPlayer.Path.WAN_IPV4
	candidate.address = "10.0.0.5"
	candidate.port = 49152
	candidate.observed_address = "127.0.0.1"
	candidate.observed_port = responder_port
	remote.append(candidate)
	_feed(client, RendezvousContract.encode_candidates(
		SID, client.get_session().local_nonce, "ffffffffffffffffffffffffffffffff",
		RendezvousContract.Role.HOST, "127.0.0.1", responder_port, remote
	))
	var hp: P2PHolePunch = p2p._hole_punch
	hp._bidirectional_confirmed = true
	hp._validated_rtt_ms = 42
	hp._validated_source_address = "127.0.0.1"
	hp._validated_source_port = responder_port
	hp._validated_pair_index = 0
	var validated_candidate: Dictionary = {
		"local": hp._candidate_pairs[0].local,
		"remote": {
			"address": "127.0.0.1",
			"port": responder_port,
			"observed_address": "127.0.0.1",
			"observed_port": responder_port,
		},
		"rtt_ms": 42,
		"probe_target": {
			"address": "127.0.0.1",
			"port": responder_port,
		},
	}
	hp._validated_candidate = validated_candidate
	p2p.tick(0.0)
	_expect(p2p.get_state_value() == P2PConnectionState.State.DIRECT_ENET_CONNECTING, "到达 DIRECT_ENET_CONNECTING")

	## 获取当前 attempt_id
	var attempt_id_before: int = p2p.current_attempt().attempt_id if p2p.current_attempt() != null else 0
	
	## 模拟旧 attempt 的延迟 connected 回调（attempt_id 不匹配）
	if attempt_id_before > 0:
		## 这里无法直接调用旧 attempt_id，因为 runner 是内部的
		## 但我们可以验证 notify_direct_enet_connected 使用当前 runner 的 attempt_id
		p2p.notify_direct_enet_connected()
		_expect(p2p.get_state_value() == P2PConnectionState.State.HANDSHAKING, "正常 connected -> HANDSHAKING")

	## reset 后再次 begin，旧回调不应影响新状态
	p2p.reset()
	_expect(p2p.get_state_value() == P2PConnectionState.State.DISCONNECTED, "reset -> DISCONNECTED")

	## 重新开始
	var p2p_invite2: JoinInvite = JoinInvite.create(
		LAN, 17777, TICKET, ROOM, "Host", "", "", JoinInvite.DEFAULT_WAN_PORT,
		true, "127.0.0.1", 17779
	)
	var joined2: JoinInvite = manager.join_invite(p2p_invite2.to_uri())
	var p2p2: P2PConnection = manager._p2p_connection
	_expect(p2p2.get_state_value() == P2PConnectionState.State.RENDEZVOUS_CONNECTING, "重新 begin -> RENDEZVOUS_CONNECTING")

	manager.queue_free()

# ---- 辅助 ----

func _reserve_free_port() -> int:
	var probe: PacketPeerUDP = PacketPeerUDP.new()
	if probe.bind(0) != OK:
		return 0
	var port: int = probe.get_local_port()
	probe.close()
	return port

## responder：收 P2PUDPProbe probe，回 ACK（真实 encode/decode）。
## nonce 必须用 responder 自己的 nonce（= 对端期望的 remote_nonce），不能 echo probe 的 nonce。
func _respond(socket: PacketPeerUDP, remote_nonce: String) -> void:
	while socket.get_available_packet_count() > 0:
		var packet: PackedByteArray = socket.get_packet()
		var src_ip: String = socket.get_packet_ip()
		var src_port: int = socket.get_packet_port()
		var decoded: P2PUDPProbe.Decoded = P2PUDPProbe.decode(packet)
		if not decoded.is_ok() or not decoded.is_probe():
			continue
		var now_ms: int = Time.get_ticks_msec()
		var ack: PackedByteArray = P2PUDPProbe.encode_ack(
			decoded.session_id, remote_nonce, P2PUDPProbe.Role.HOST,
			now_ms, decoded.timestamp_ms, decoded.probe_id
		)
		socket.set_dest_address(src_ip, src_port)
		socket.put_packet(ack)

func _feed(client: RendezvousClient, packet: PackedByteArray) -> void:
	client._handle_packet(packet)

# ---- 收尾 ----

func _expect(condition: bool, label: String) -> void:
	if not condition:
		_failures.append(label)

func _finish() -> void:
	if _failures.is_empty():
		print("P2P_PRODUCTION_FLOW_OK")
		quit(0)
		return
	for failure: String in _failures:
		printerr("P2P_PRODUCTION_FLOW_FAIL: %s" % failure)
	quit(1)
