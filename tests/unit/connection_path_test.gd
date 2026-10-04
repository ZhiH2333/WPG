extends SceneTree

## ConnectionPath 回归（Phase 8）：候选顺序 / IPv6 回退 / WAN 回退 / 单一 peer 约束。
## 跑法：godot --headless --path . --script res://tests/connection_path_test.gd
## 通过输出 CONNECTION_PATH_OK；失败逐条 CONNECTION_PATH_FAIL 并返回非 0。

const LAN := "192.168.1.20"
const WAN := "203.0.113.7"
const V6 := "fe80::1c2d:3e4f:5a6b:7c8d"

var _failures: PackedStringArray = PackedStringArray()

func _initialize() -> void:
	_run_all.call_deferred()

func _run_all() -> void:
	_case_enum_is_complete()
	_case_lan_first()
	_case_ipv6_fallback()
	_case_wan_fallback()
	_case_missing_candidates_are_not_faked()
	_case_order_is_stable()
	_case_select_next_path_walks_then_ends()
	_case_validate_rejects_bad_candidate()
	await _case_single_multiplayer_peer()
	## Phase 8 hardening：异步回退语义（attempt_id / 单 peer / 明确失败分类）。
	_case_connect_success_needs_handshake_not_create_client()
	_case_failed_first_candidate_falls_back()
	_case_timeout_first_candidate_falls_back()
	_case_stale_callback_is_discarded()
	_case_second_candidate_connected_not_overwritten()
	_case_version_mismatch_does_not_retry()
	_case_ticket_rejected_does_not_retry()
	_case_timeout_leaves_no_peer()
	_case_at_most_one_active_peer()
	_case_retryable_and_terminal_classification()
	_case_manual_join_uses_runner()
	_finish()

# ---- 用例 ----

func _case_enum_is_complete() -> void:
	_expect(LobbyPlayer.Path.LAN_IPV4 == 0, "LAN_IPV4 存在")
	_expect(ConnectionPath.DEFAULT_ORDER.size() == 3, "默认候选顺序有 3 项")
	_expect(ConnectionPath.DEFAULT_ORDER[0] == LobbyPlayer.Path.LAN_IPV4, "顺序 1 = LAN_IPV4")
	_expect(ConnectionPath.DEFAULT_ORDER[1] == LobbyPlayer.Path.IPV6, "顺序 2 = IPV6")
	_expect(ConnectionPath.DEFAULT_ORDER[2] == LobbyPlayer.Path.WAN_IPV4, "顺序 3 = WAN_IPV4")
	_expect(ConnectionPath.path_name(LobbyPlayer.Path.IPV6) == "ipv6", "path_name 覆盖 IPv6")
	_expect(ConnectionPath.path_name(LobbyPlayer.Path.WAN_IPV4) == "wan_ipv4", "path_name 覆盖 WAN")

## LAN 优先：即使 WAN / IPv6 同时存在，第一个候选也必须是 LAN。
func _case_lan_first() -> void:
	var invite: JoinInvite = JoinInvite.create(LAN, 17777, "", "", "", V6, WAN, 49152)
	var plan: ConnectionPath = invite.to_candidates()
	_expect(plan.size() == 3, "三候选都在")
	_expect(plan.preferred_path() == LobbyPlayer.Path.LAN_IPV4, "首选是 LAN_IPV4")
	var first: ConnectionPath.Candidate = plan.select_next_path(0)
	_expect(first != null and first.address == LAN and first.port == 17777, "第一个候选 = LAN 地址")

func _case_ipv6_fallback() -> void:
	## 没有 WAN，只有 LAN + IPv6 -> iOS/无公网场景的回退顺序。
	var invite: JoinInvite = JoinInvite.create(LAN, 17777, "", "", "", V6)
	var plan: ConnectionPath = invite.to_candidates()
	_expect(plan.size() == 2, "LAN + IPv6 两个候选")
	var paths: PackedInt32Array = plan.path_list()
	_expect(paths[0] == LobbyPlayer.Path.LAN_IPV4, "先试 LAN")
	_expect(paths[1] == LobbyPlayer.Path.IPV6, "LAN 之后回退 IPv6")
	var second: ConnectionPath.Candidate = plan.select_next_path(1)
	_expect(second != null and second.address == V6, "第二个候选是 IPv6 地址")

func _case_wan_fallback() -> void:
	var invite: JoinInvite = JoinInvite.create(LAN, 17777, "", "", "", "", WAN, 49152)
	var plan: ConnectionPath = invite.to_candidates()
	var paths: PackedInt32Array = plan.path_list()
	_expect(paths[0] == LobbyPlayer.Path.LAN_IPV4, "先试 LAN")
	_expect(paths[1] == LobbyPlayer.Path.WAN_IPV4, "LAN 之后回退 WAN")
	var wan: ConnectionPath.Candidate = plan.select_next_path(1)
	_expect(wan != null and wan.port == 49152, "WAN 候选带自己的端口")

## 缺的候选不许伪造（尤其不许把没提供的 WAN 当成已有路径）。
func _case_missing_candidates_are_not_faked() -> void:
	var invite: JoinInvite = JoinInvite.create(LAN, 17777)
	var plan: ConnectionPath = invite.to_candidates()
	_expect(plan.size() == 1, "只有 LAN 时只有一个候选")
	_expect(plan.preferred_path() == LobbyPlayer.Path.LAN_IPV4, "唯一候选是 LAN")
	_expect(plan.select_next_path(1) == null, "没有第二个候选可试")

## 顺序稳定：同样输入重复构造，顺序必须完全一致。
func _case_order_is_stable() -> void:
	var invite: JoinInvite = JoinInvite.create(LAN, 17777, "", "", "", V6, WAN, 49152)
	var a: PackedInt32Array = invite.to_candidates().path_list()
	var b: PackedInt32Array = invite.to_candidates().path_list()
	_expect(a == b, "重复构造的候选顺序一致")
	var address_a: PackedStringArray = invite.to_candidates().address_list()
	var address_b: PackedStringArray = invite.to_candidates().address_list()
	_expect(address_a == address_b, "重复构造的候选地址一致")

## 游标语义：0/1/2 逐个走完，之后返回 null（调用方据此放弃）。
func _case_select_next_path_walks_then_ends() -> void:
	var invite: JoinInvite = JoinInvite.create(LAN, 17777, "", "", "", V6, WAN, 49152)
	var plan: ConnectionPath = invite.to_candidates()
	_expect(plan.select_next_path(0) != null, "游标 0 有候选")
	_expect(plan.select_next_path(1) != null, "游标 1 有候选")
	_expect(plan.select_next_path(2) != null, "游标 2 有候选")
	_expect(plan.select_next_path(3) == null, "游标 3 走完 -> null")

func _case_validate_rejects_bad_candidate() -> void:
	var plan: ConnectionPath = ConnectionPath.new()
	var bad_port: ConnectionPath.Candidate = ConnectionPath.Candidate.new()
	bad_port.path = LobbyPlayer.Path.LAN_IPV4
	bad_port.address = LAN
	bad_port.port = 0
	_expect(not plan.validate_candidate(bad_port), "端口 0 的候选不合法")
	var no_address: ConnectionPath.Candidate = ConnectionPath.Candidate.new()
	no_address.path = LobbyPlayer.Path.LAN_IPV4
	no_address.port = 17777
	_expect(not plan.validate_candidate(no_address), "无地址的候选不合法")
	## IPv6 候选却给了 IPv4 地址 = 装配错误，必须拒绝而不是喂给 ENet。
	var mislabeled: ConnectionPath.Candidate = ConnectionPath.Candidate.new()
	mislabeled.path = LobbyPlayer.Path.IPV6
	mislabeled.address = LAN
	mislabeled.port = 17777
	_expect(not plan.validate_candidate(mislabeled), "IPv6 候选配 IPv4 地址被拒")

## 关键约束：候选回退过程不允许出现第二个 multiplayer peer。
## SceneTree.multiplayer 全程只有一个 peer；每次尝试前都必须先关掉上一个。
## 用真实 listening peer 而不是空对象：Godot 会拒绝未连接的 peer（这本身就是约束的一部分）。
func _case_single_multiplayer_peer() -> void:
	var net: LobbyNet = LobbyNet.new()
	root.add_child(net)
	var invite: JoinInvite = JoinInvite.create(LAN, 17777, "", "", "", V6, WAN, 49152)
	var plan: ConnectionPath = invite.to_candidates()
	var seen: Array[int] = []
	var index: int = 0
	while true:
		var candidate: ConnectionPath.Candidate = plan.select_next_path(index)
		if candidate == null:
			break
		index += 1
		## 与 LobbyManager._try_candidate 同款顺序：先 close 再建连（回退绝不并发两个 peer）。
		net.close()
		_expect(net.multiplayer.multiplayer_peer == null, "尝试候选前 multiplayer_peer 已清空")
		var probe: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
		if probe.create_server(GameLaunch.NET_PORT, 1) != OK:
			_expect(false, "本机回环监听失败（端口被占？）")
			break
		net.multiplayer.multiplayer_peer = probe
		seen.append(candidate.path)
		_expect(net.multiplayer.multiplayer_peer == probe, "同一时刻只挂一个 peer")
		var live: MultiplayerPeer = net.multiplayer.multiplayer_peer
		_expect(live == probe, "没有第二个 peer 顶替")
	net.close()
	_expect(seen.size() == 3, "三个候选都被顺序走到")
	_expect(net.multiplayer.multiplayer_peer == null, "收尾后没有残留 peer")
	net.queue_free()

# ---- 异步回退（Phase 8 hardening）----
#
# 这些用例用「假 transport」驱动 ConnectAttemptRunner：真实 ENet 无法在单进程内
# 可靠地制造 connection_failed / 延迟 callback，而这些恰恰是出 bug 的地方。
# 生产路径（真 ENet）由 tests/lan_e2e_test + tools/ci/lan_start_ui_* 覆盖。

## 关键修正：create_client() 返回 true **不等于**连接成功。
## 必须等 connected_to_server + 握手通过才算 CONNECTED。
func _case_connect_success_needs_handshake_not_create_client() -> void:
	var harness: Array = _make_runner([LAN, V6])
	var runner: ConnectAttemptRunner = harness[0]
	_expect(runner.attempts_made() == 1, "只发起了 1 次尝试")
	_expect(not runner.is_finished(), "create_client 成功后仍未定论（不是 CONNECTED）")
	var attempt: ConnectAttempt = runner.current_attempt()
	_expect(attempt.is_pending(), "attempt 仍 PENDING")
	_expect(not attempt.transport_connected, "还没有真实 transport connected")
	## 真实连上（传输层）。
	runner.notify_transport_connected(attempt.attempt_id)
	_expect(attempt.transport_connected, "transport_connected 置位")
	_expect(not runner.is_finished(), "传输层连上但未握手 -> 仍未定论")
	## 握手通过才算成功。
	runner.notify_handshake_ok(attempt.attempt_id)
	_expect(runner.is_finished(), "握手后 join 终结")
	_expect(runner.is_success(), "join 成功")
	_expect(attempt.outcome == ConnectAttempt.Outcome.CONNECTED, "outcome = CONNECTED")

## 场景 1：第一个 candidate create_client 成功，但随后 connection_failed
## -> 必须尝试第二个 candidate。
func _case_failed_first_candidate_falls_back() -> void:
	var harness: Array = _make_runner([LAN, V6])
	var runner: ConnectAttemptRunner = harness[0]
	var transport: FakeTransport = harness[1]
	var first: ConnectAttempt = runner.current_attempt()
	_expect(runner.attempts_made() == 1, "先试第一个候选")
	runner.notify_connection_failed(first.attempt_id, "refused")
	_expect(transport.closed_count >= 1, "换候选前 close 了旧 peer")
	_expect(runner.attempts_made() == 2, "回退到第二个候选")
	_expect(transport.requested.size() == 2, "两次建连请求")
	_expect(transport.requested[1] == V6, "第二次请求的是 IPv6 候选")
	_expect(not runner.is_finished(), "回退后仍在进行（未终结）")
	## 第二个候选成功。
	var second: ConnectAttempt = runner.current_attempt()
	runner.notify_transport_connected(second.attempt_id)
	runner.notify_handshake_ok(second.attempt_id)
	_expect(runner.is_success(), "第二个候选连上 -> 成功")

## 场景 2：第一个 candidate timeout -> 尝试第二个。
func _case_timeout_first_candidate_falls_back() -> void:
	var harness: Array = _make_runner([LAN, V6])
	var runner: ConnectAttemptRunner = harness[0]
	var transport: FakeTransport = harness[1]
	## 推进超过单次尝试超时。
	runner.tick(ConnectAttemptRunner.DIRECT_ATTEMPT_TIMEOUT_SEC + 0.1)
	_expect(transport.closed_count >= 1, "超时后 close 了旧 peer")
	_expect(runner.attempts_made() == 2, "超时后回退到第二个候选")
	## 第二个候选成功收尾。
	var second: ConnectAttempt = runner.current_attempt()
	runner.notify_transport_connected(second.attempt_id)
	runner.notify_handshake_ok(second.attempt_id)
	_expect(runner.is_success(), "超时回退后第二个候选成功")

## 场景 3：第一个 candidate 的**延迟 callback** 在第二个 candidate 已开始后到达
## -> 必须被 attempt_id 丢弃，不得修改新候选状态。
func _case_stale_callback_is_discarded() -> void:
	var harness: Array = _make_runner([LAN, V6])
	var runner: ConnectAttemptRunner = harness[0]
	var first: ConnectAttempt = runner.current_attempt()
	var stale_id: int = first.attempt_id
	## 第一个失败 -> 换到第二个。
	runner.notify_connection_failed(stale_id, "refused")
	var second: ConnectAttempt = runner.current_attempt()
	_expect(second.attempt_id != stale_id, "第二个候选有新的 attempt_id")
	## 旧候选的延迟失败回调到达：必须被丢弃。
	var accepted: bool = runner.notify_connection_failed(stale_id, "late_refused")
	_expect(not accepted, "旧 attempt 的延迟回调被拒绝")
	_expect(runner.current_attempt() == second, "当前 attempt 仍是第二个候选")
	_expect(second.is_pending(), "第二个候选状态未被旧回调污染")
	_expect(runner.attempts_made() == 2, "不因为延迟回调多试一个候选")
	## 旧候选的延迟「连上」回调同样必须被丢弃。
	_expect(not runner.notify_transport_connected(stale_id), "旧 attempt 的延迟 connected 被拒绝")
	_expect(not runner.notify_handshake_ok(stale_id), "旧 attempt 的延迟握手被拒绝")
	_expect(not runner.is_finished(), "延迟回调没有提前终结 join")

## 场景 4：第二个 candidate connected -> 旧 candidate callback 不得覆盖 CONNECTED。
func _case_second_candidate_connected_not_overwritten() -> void:
	var harness: Array = _make_runner([LAN, V6])
	var runner: ConnectAttemptRunner = harness[0]
	var stale_id: int = runner.current_attempt().attempt_id
	runner.notify_connection_failed(stale_id, "refused")
	var second: ConnectAttempt = runner.current_attempt()
	runner.notify_transport_connected(second.attempt_id)
	runner.notify_handshake_ok(second.attempt_id)
	_expect(runner.is_success(), "第二个候选已 CONNECTED")
	_expect(runner.final_attempt() == second, "终态指向第二个候选")
	## 旧候选的超时 / 失败回调迟到了，绝不能把 CONNECTED 改回去。
	_expect(not runner.notify_connection_failed(stale_id, "late"), "旧候选失败回调被丢弃")
	_expect(not runner.notify_transport_connected(stale_id), "旧候选 connected 回调被丢弃")
	_expect(runner.is_success(), "CONNECTED 未被旧 callback 覆盖")
	_expect(runner.current_attempt().outcome == ConnectAttempt.Outcome.CONNECTED, "outcome 仍是 CONNECTED")

## 场景 5：protocol mismatch -> VERSION_MISMATCH，不走普通 retry。
func _case_version_mismatch_does_not_retry() -> void:
	var harness: Array = _make_runner([LAN, V6])
	var runner: ConnectAttemptRunner = harness[0]
	var attempt: ConnectAttempt = runner.current_attempt()
	runner.notify_version_mismatch(attempt.attempt_id, "protocol_mismatch")
	_expect(runner.is_finished(), "协议不符立即终结 join")
	_expect(not runner.is_success(), "协议不符不算成功")
	_expect(runner.attempts_made() == 1, "协议不符不换候选重试（只试了 1 次）")
	_expect(attempt.outcome == ConnectAttempt.Outcome.VERSION_MISMATCH, "outcome = VERSION_MISMATCH")
	_expect(not attempt.is_retryable(), "VERSION_MISMATCH 不可重试")
	_expect(runner.final_reason() == "version_mismatch", "终结原因 = version_mismatch")

## 场景 6：ticket rejected -> TICKET_REJECTED，不走普通 retry。
func _case_ticket_rejected_does_not_retry() -> void:
	var harness: Array = _make_runner([LAN, V6])
	var runner: ConnectAttemptRunner = harness[0]
	var attempt: ConnectAttempt = runner.current_attempt()
	runner.notify_ticket_rejected(attempt.attempt_id, "ticket_rejected:2")
	_expect(runner.is_finished(), "ticket 被拒立即终结 join")
	_expect(not runner.is_success(), "ticket 被拒不算成功")
	_expect(runner.attempts_made() == 1, "ticket 被拒不换候选重试（只试了 1 次）")
	_expect(attempt.outcome == ConnectAttempt.Outcome.TICKET_REJECTED, "outcome = TICKET_REJECTED")
	_expect(not attempt.is_retryable(), "TICKET_REJECTED 不可重试")

## 场景 7：timeout -> 没有残留 multiplayer_peer。
func _case_timeout_leaves_no_peer() -> void:
	var harness: Array = _make_runner([LAN, V6])
	var runner: ConnectAttemptRunner = harness[0]
	var transport: FakeTransport = harness[1]
	## 推进到总超时。
	runner.tick(ConnectAttemptRunner.OVERALL_JOIN_TIMEOUT_SEC + 0.1)
	_expect(runner.is_finished(), "总超时终结 join")
	_expect(not runner.is_success(), "超时不算成功")
	_expect(runner.final_reason() == "overall_timeout", "终结原因 = overall_timeout")
	_expect(transport.closed_count >= 1, "超时后调用了 close（无残留 peer）")
	_expect(transport.peer_alive == false, "超时后没有 active peer")
	_expect(runner.current_attempt().outcome == ConnectAttempt.Outcome.CONNECT_TIMEOUT, "outcome = CONNECT_TIMEOUT")

## 场景 8：任意时刻最多一个 active peer。
## 用真实 ENet peer 证明：回退过程中永远是「先关旧、再开新」。
func _case_at_most_one_active_peer() -> void:
	var net: LobbyNet = LobbyNet.new()
	root.add_child(net)
	var harness: Array = _make_runner_with_transport([LAN, V6])
	var runner: ConnectAttemptRunner = harness[0]
	var transport: FakeTransport = harness[1]
	## 让假 transport 真的往 LobbyNet 上挂 peer，模拟生产路径。
	transport.net = net
	var max_live: int = 0
	var first: ConnectAttempt = runner.current_attempt()
	max_live = maxi(max_live, transport.live_peer_count())
	runner.notify_connection_failed(first.attempt_id, "refused")
	max_live = maxi(max_live, transport.live_peer_count())
	_expect(transport.max_concurrent_peers <= 1, "回退全程并发 peer 从未超过 1")
	_expect(max_live <= 1, "任意时刻最多一个 active peer")
	## 收尾不留 peer。
	runner.cancel()
	_expect(net.multiplayer.multiplayer_peer == null, "cancel 后 LobbyNet 无残留 peer")
	net.close()
	net.queue_free()

## 分类表：可重试 vs 终态必须互斥且覆盖完整。
func _case_retryable_and_terminal_classification() -> void:
	_expect(ConnectAttempt.RETRYABLE.has(ConnectAttempt.Outcome.CONNECT_TIMEOUT), "超时可重试")
	_expect(ConnectAttempt.RETRYABLE.has(ConnectAttempt.Outcome.CONNECTION_FAILED), "connection_failed 可重试")
	_expect(ConnectAttempt.RETRYABLE.has(ConnectAttempt.Outcome.SOCKET_ERROR), "socket_error 可重试")
	_expect(not ConnectAttempt.RETRYABLE.has(ConnectAttempt.Outcome.VERSION_MISMATCH), "version_mismatch 不可重试")
	_expect(not ConnectAttempt.RETRYABLE.has(ConnectAttempt.Outcome.TICKET_REJECTED), "ticket_rejected 不可重试")
	_expect(ConnectAttempt.TERMINAL.has(ConnectAttempt.Outcome.CONNECTED), "CONNECTED 是终态")
	_expect(not ConnectAttempt.TERMINAL.has(ConnectAttempt.Outcome.PENDING), "PENDING 不是终态")
	_expect(ConnectAttempt.outcome_name(ConnectAttempt.Outcome.CONNECT_TIMEOUT) == "connect_timeout", "outcome_name 覆盖超时")
	_expect(ConnectAttempt.outcome_name(ConnectAttempt.Outcome.VERSION_MISMATCH) == "version_mismatch", "outcome_name 覆盖协议不符")
	_expect(ConnectAttempt.outcome_name(ConnectAttempt.Outcome.TICKET_REJECTED) == "ticket_rejected", "outcome_name 覆盖 ticket 被拒")

## 手打 IP 路径（LobbyManager.join_room_address）也必须走 runner：
## 单候选、无回退，但同样有 attempt_id 隔离与明确结果分类。
## 否则手打 IP 失败后旧 runner 会误收别的连接的回调。
func _case_manual_join_uses_runner() -> void:
	var manager: LobbyManager = LobbyManager.new()
	root.add_child(manager)
	var net: LobbyNet = LobbyNet.new()
	root.add_child(net)
	manager.bind_net(net)
	## 空地址不合法：不该发起，也不该留下 runner。
	_expect(not manager.join_room_address(""), "空地址被拒")
	_expect(manager.get_connect_attempt() == null, "空地址后没有 attempt")
	## 合法地址：发起一次尝试（结果异步）。
	var started: bool = manager.join_room_address(LAN)
	_expect(started, "手打 IP 已发起")
	var attempt: ConnectAttempt = manager.get_connect_attempt()
	_expect(attempt != null, "手打 IP 也创建 attempt")
	if attempt != null:
		_expect(attempt.candidate != null and attempt.candidate.address == LAN, "attempt 指向手打地址")
		_expect(attempt.is_pending(), "发起后仍是 PENDING（未连上）")
	## 取消必须清干净，不留 peer。
	manager.cancel_join()
	_expect(manager.get_connect_attempt() == null, "cancel 后无 attempt")
	_expect(net.multiplayer.multiplayer_peer == null, "cancel 后无残留 peer")
	manager.queue_free()
	net.queue_free()

# ---- 假 transport ----

## 记录建连请求与 close 次数，用于断言回退顺序与「先关后开」。
class FakeTransport extends RefCounted:
	var requested: Array[String] = []
	var closed_count: int = 0
	## 设为非 null 时，close 会真的关掉 LobbyNet 上的 peer（场景 8 用）。
	var net: LobbyNet = null
	## 同时存活的 peer 数峰值。
	var max_concurrent_peers: int = 0
	var _live: int = 0

	func connect_to(address: String, _port: int, _ticket: String) -> bool:
		requested.append(address)
		_live += 1
		max_concurrent_peers = maxi(max_concurrent_peers, _live)
		return true

	func close_transport() -> void:
		closed_count += 1
		_live = 0
		if net != null:
			net.close()

	func live_peer_count() -> int:
		return _live

	var peer_alive: bool:
		get:
			return _live > 0

# ---- 辅助 ----

## 用假 transport 建一个 runner（候选来自 invite）。
func _make_runner(addresses: Array) -> Array:
	return _make_runner_with_transport(addresses)

func _make_runner_with_transport(_addresses: Array) -> Array:
	var invite: JoinInvite = JoinInvite.create(LAN, 17777, "", "", "", V6, WAN, 49152)
	var plan: ConnectionPath = invite.to_candidates()
	var runner: ConnectAttemptRunner = ConnectAttemptRunner.new()
	var transport: FakeTransport = FakeTransport.new()
	runner.begin(plan, invite.token, transport.connect_to, transport.close_transport)
	return [runner, transport]

# ---- 收尾 ----

func _expect(condition: bool, label: String) -> void:
	if not condition:
		_failures.append(label)

func _finish() -> void:
	if _failures.is_empty():
		print("CONNECTION_PATH_OK")
		quit(0)
		return
	for failure: String in _failures:
		printerr("CONNECTION_PATH_FAIL: %s" % failure)
	quit(1)
