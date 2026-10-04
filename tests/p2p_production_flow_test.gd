extends SceneTree

## Phase 9.2.2 R2 production flow 回归：
## - production invite path（LobbyManager.join_invite）对 P2P invite 真正进入 P2PConnection
## - LAN invite 仍走旧 runner（不 regression）
## - candidates 到达自动触发 direct probing（不依赖外部调用 begin_direct_probing）
## - shared UDP ownership：P2PConnection 拥有，client / hole punch 不关闭它
## - 没有重复 signal connection：一次事件只执行一次 callback
## - validated direct path 真正建立，validated endpoint 与实际 probe target 一致
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

	## 真实 UDP 往返：P2PConnection tick -> responder 回 ACK -> 下一次 tick 确认。
	## 在 headless 模式下 UDP 回环包需要极短延迟才能被 OS 送达接收缓冲区。
	var remote_nonce: String = "ffffffffffffffffffffffffffffffff"
	for _i: int in 12:
		p2p.tick(0.0)
		_respond(responder, remote_nonce)
		OS.delay_usec(1000)
		if p2p.get_state_value() == P2PConnectionState.State.DIRECT_PATH_ESTABLISHED:
			break

	_expect(
		p2p.get_state_value() == P2PConnectionState.State.DIRECT_PATH_ESTABLISHED,
		"validated direct path 建立（DIRECT_PATH_ESTABLISHED）"
	)
	_expect(int(established_count[0]) == 1, "direct_path_established 只 emit 一次（无重复 callback）")
	_expect(int(finished_count[0]) == 0, "本阶段不自动进入 Direct ENet / finished（9.2.2 终点）")

	## validated endpoint 必须就是 responder 端点（实际 probe target）。
	var validated: Dictionary = p2p.get_validated_endpoint()
	_expect(int(validated.get("port", 0)) == responder_port, "validated endpoint = responder 端点")
	var target: Dictionary = p2p.get_validated_probe_target()
	_expect(int(target.get("port", 0)) == responder_port, "probe target == validated endpoint")
	_expect(
		p2p.get_state_value() != P2PConnectionState.State.DIRECT_ENET_CONNECTING,
		"没有开始 Direct ENet（不进入 9.2.3）"
	)

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
