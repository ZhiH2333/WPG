extends SceneTree

## P2PHolePunch 真实 UDP 集成回归（Phase 9.2.2 R2）。
##
## 用**两个真实 P2PHolePunch 实例** + 真 loopback UDP，验证：
## - 双方用真实 encode/decode/path establishment logic 完成双向打洞
## - simultaneous probing：多个 candidate pair 同时 active
## - probe_id correlation / source address+port matching / stale ACK rejection
## - one pair 失败不阻塞另一个 pair，任意 pair 成功即 validated
## - validated remote endpoint 与真正成功的 probe target 一致
## - shared UDP ownership：共享 socket 不会被 P2PHolePunch close
## - cancel / reset 清理
##
## 跑法：godot --headless --path . --script res://tests/integration/p2p_hole_punch_integration_test.gd
## 通过输出 P2P_HOLE_PUNCH_INTEGRATION_OK；失败逐条 _FAIL 并返回非 0。
##
## ---- 为什么不再「reserve 端口 -> close -> 再 bind」----
## 「刚刚空闲」不等于「下一次 bind 时仍然空闲」，这是典型的 TOCTOU：
## reserve 出来的 port_r / port_q / port_b 一旦 close，就可能被**本测试自己**
## 的下一个 bind(0)（比如 A 的自建 socket）或系统的临时端口抢走。
## 现在所有真正要用的端口都由**真实持有它的 socket** 自己 bind(0) 后立刻读取：
##   - R / Q 直接 bind(0) 后用 get_local_port()，socket 全程不关
##   - B 先创建真实 socket 并 bind(0)，再把这个 already-bound socket 作为
##     shared_udp 交给 b.begin(...)，「先拿端口再重新 bind」这一步整个消失
## 这不削弱所有权语义测试：_case_shared_udp_ownership() 仍独立覆盖
## shared socket 的 close/release/reset 行为。
##
## ---- 为什么不再「固定 tick 6 次」----
## P2PHolePunch 的 PROBE_INTERVAL_MS = 120 用的是 Time.get_ticks_msec()，
## 而旧测试在**同一个 frame 里**连续 a.tick(0)/b.tick(0)，真实时间几乎不前进。
## 于是成败完全取决于 loopback UDP 的**亚毫秒投递顺序**：
##   - A 早一拍收到 B 的 ACK -> A 确认并 close() 自建 socket -> B 的第一个
##     probe 从此拿不到 ACK -> B 永远不成功（这正是 CI 上连续失败的形态）
##   - A 晚太多 -> 固定的几次 tick 内根本没完成交换 -> A 不成功
## 现在改为**有界的 real-frame 轮询**：每轮之间 await process_frame，
## 让 PROBE_INTERVAL_MS 真的有机会流逝、让 UDP 包真的投递完成；
## 成功立即退出，超时（PUMP_MAX_WAIT_MS = 2000，远低于
## MAX_PROBE_DURATION_MS = 3500）就带着完整诊断明确失败。
##
## 本文件不修改任何生产参数（PROBE_INTERVAL_MS / MAX_PROBE_DURATION_MS 等原样），
## 不修改 lobby/p2p_hole_punch.gd。

const SID := "abcdef1234567890"
const A_NONCE := "0123456789abcdef0123456789abcdef"
const B_NONCE := "fedcba9876543210fedcba9876543210"

## 有界等待上限。远低于 P2PHolePunch.MAX_PROBE_DURATION_MS(3500)。
const PUMP_MAX_WAIT_MS: int = 2000
## A 已经成功而 B 还没成功时的额外宽限：A 一旦成功就 close() 自建 socket，
## B 只能靠 A 在确认那次 drain 里顺带回的 ACK 完成。超过这个宽限说明
## 已经没有补救余地，提前结束循环（仍然有界）。
const ORPHAN_GRACE_MS: int = 500

var _failures: PackedStringArray = PackedStringArray()

## 主用例的诊断上下文；_finish() 失败时打印（不含 nonce / ticket）。
var _diag_a: P2PHolePunch = null
var _diag_b: P2PHolePunch = null
var _diag_ports: Dictionary = {}

func _initialize() -> void:
	_run_all.call_deferred()

func _run_all() -> void:
	await _case_two_instance_bidirectional_punch()
	_case_shared_udp_ownership()
	_case_cancel_and_reset_cleanup()
	_finish()

# ---- 用例 ----

func _case_two_instance_bidirectional_punch() -> void:
	## R / Q / B 的端口全部由**真实持有它们的 socket** 自己 bind(0) 取得，
	## 全程不 close、不 rebind —— 消除 reserve/close/rebind 的 TOCTOU。
	var r: PacketPeerUDP = PacketPeerUDP.new()
	_expect(r.bind(0) == OK, "raw R socket bind")
	var port_r: int = r.get_local_port()
	_expect(port_r > 0, "R 端口由真实 socket 持有")
	## R = 冒充「一个永远不回有效 ACK 的对端」的原始 socket（用于 stale ACK / 失败 pair）。

	var q: PacketPeerUDP = PacketPeerUDP.new()
	_expect(q.bind(0) == OK, "raw Q socket bind（source mismatch 用）")
	var port_q: int = q.get_local_port()
	_expect(port_q > 0, "Q 端口由真实 socket 持有")

	## B 的真实 socket：先 bind(0) 拿端口，再把它整体交给 b.begin() 复用。
	var b_udp: PacketPeerUDP = PacketPeerUDP.new()
	_expect(b_udp.bind(0) == OK, "B socket bind")
	var port_b: int = b_udp.get_local_port()
	_expect(port_b > 0, "B 端口由真实 socket 持有")

	var a: P2PHolePunch = P2PHolePunch.new()
	var b: P2PHolePunch = P2PHolePunch.new()

	## A 的远端候选：一个指向 R（永不成功），一个指向 B（真正成功）。
	var remote_a: Array = []
	remote_a.append(_wan_candidate("127.0.0.1", port_r, "127.0.0.1", port_r))
	remote_a.append(_wan_candidate("127.0.0.1", port_b, "127.0.0.1", port_b))

	_expect(a.begin(SID, A_NONCE, B_NONCE, P2PUDPProbe.Role.GUEST, _local_candidates(), remote_a), "A begin")
	var port_a: int = int(a.get_local_bound_endpoint().get("port", 0))
	_expect(port_a > 0, "A 自建 socket 拥有生命周期")
	_expect(a.owns_socket(), "A owns_socket() == true（自建）")
	## R / Q / B 一直被自己的 socket 持有，A 的 bind(0) 不可能抢到它们。
	_expect(port_a != port_r and port_a != port_q and port_a != port_b, "A 的端口与 R / Q / B 都不冲突")

	## B 的远端候选 = A 的实际绑定端点。
	var remote_b: Array = [_wan_candidate("127.0.0.1", port_a, "127.0.0.1", port_a)]
	_expect(b.begin(SID, B_NONCE, A_NONCE, P2PUDPProbe.Role.HOST, _local_candidates(), remote_b, port_b, b_udp), "B begin")
	_expect(not b.owns_socket(), "B 复用 already-bound shared socket，不拥有生命周期")

	_diag_a = a
	_diag_b = b
	_diag_ports = {
		"port_a": port_a,
		"port_b": port_b,
		"port_r": port_r,
		"port_q": port_q,
	}

	## simultaneous probing：begin 后两个 pair 都是 active。
	_expect(a.get_active_probe_count() == 2, "A 有 2 个同时 active 的 probe pair")

	## 第一次 tick：首帧不发（first_tick_skip），第二次 tick 发出 probe。
	a.tick(0)
	a.tick(0)
	var states: Array[Dictionary] = a.debug_pair_states()
	_expect(states.size() == 2, "A 构建了 2 个 candidate pair")
	var sent_all: bool = true
	for state: Dictionary in states:
		if int(state.probes_sent) < 1:
			sent_all = false
	_expect(sent_all, "两个 pair 第二次 tick 都发了 probe（simultaneous）")

	## ---- 以下两段必须在 B 开始 tick 之前做：B 不 tick 就不会回 ACK，
	## A 必然还在 PROBING，stale / source mismatch 的判定才有意义。 ----

	## stale ACK：probe_id 不匹配 -> 丢弃。
	var real_pair: Dictionary = _find_pair_by_port(a, port_b)
	var failing_pair: Dictionary = _find_pair_by_port(a, port_r)
	_expect(not real_pair.is_empty(), "找到指向 B 的 pair")
	_expect(not failing_pair.is_empty(), "找到指向 R 的 pair")

	var stale_probe_id: int = 0x7FFFFFF0
	_send_raw_ack(r, port_a, B_NONCE, P2PUDPProbe.Role.HOST, stale_probe_id)
	a.tick(0)
	_expect(a.get_state() == P2PHolePunch.State.PROBING, "stale probe_id 的 ACK 被忽略（仍 PROBING）")
	_expect(not a.is_success(), "stale ACK 不会让 A 误判成功")

	## source mismatch：probe_id 正确但来自没有对应 pair 的源地址 -> 丢弃。
	var pending: Array = _find_pair_by_port(a, port_b).get("pending_probe_ids", [])
	_expect(not pending.is_empty(), "B pair 有 pending probe_id")
	var valid_probe_id: int = int(pending[0])
	_send_raw_ack(q, port_a, B_NONCE, P2PUDPProbe.Role.HOST, valid_probe_id)
	a.tick(0)
	_expect(not a.is_success(), "source 不匹配的 ACK 被忽略（probe_id 对也不行）")

	## 真实的双向打洞：有界 real-frame 轮询，成功立即退出。
	var punched: bool = await _pump_until_success(a, b, PUMP_MAX_WAIT_MS)

	_expect(a.is_success(), "A 双向打洞成功（PATH_ESTABLISHED）")
	_expect(b.is_success(), "B 双向打洞成功（PATH_ESTABLISHED）")
	_expect(punched, "双向打洞在 %dms 的有界窗口内完成（不是靠固定 tick 次数）" % PUMP_MAX_WAIT_MS)

	## endpoint 语义：validated endpoint 必须是真正回 ACK 的对端端点。
	var a_validated: Dictionary = a.get_validated_endpoint()
	var b_validated: Dictionary = b.get_validated_endpoint()
	_expect(int(a_validated.get("port", 0)) == port_b, "A validated endpoint = B 的绑定端口")
	_expect(int(b_validated.get("port", 0)) == port_a, "B validated endpoint = A 的绑定端口")

	## validated == 成功 probe 的 target，不能只把 observed 放 metadata 却发错地址。
	var a_candidate: Dictionary = a.get_validated_candidate()
	var target: Dictionary = a_candidate.get("probe_target", {})
	var validated_remote: Dictionary = a_candidate.get("remote_validated", {})
	_expect(int(target.get("port", 0)) == int(a_validated.get("port", 0)), "probe target == validated endpoint")
	_expect(int(validated_remote.get("port", 0)) == int(a_validated.get("port", 0)), "validated_candidate.remote 是 validated endpoint")
	var legacy_remote: NetworkCandidates.Candidate = a_candidate.get("remote")
	_expect(legacy_remote != null and legacy_remote.port == int(a_validated.get("port", 0)), "legacy remote 也是 validated endpoint")
	_expect(a_candidate.has("remote_advertised") and a_candidate.has("remote_observed"), "endpoint 语义字段齐全")
	_expect(a_candidate.get("remote_observed", {}).get("port", 0) == port_b, "observed endpoint 用于打洞")

	## 成功后其它 probe 必须停下：R pair 没有 ACK，且不再 active。
	var failing_after: Dictionary = _find_pair_by_port(a, port_r)
	_expect(bool(failing_after.get("ack_received", true)) == false, "失败 pair 没有误报 ACK")
	_expect(a.get_active_probe_count() == 0, "成功后其它 active probe 已停止")
	## 成功后再 tick 不会改变 validated endpoint（stale ACK 不影响最终状态）。
	var before_port: int = int(a.get_validated_endpoint().get("port", 0))
	a.tick(5000)
	_expect(int(a.get_validated_endpoint().get("port", 0)) == before_port, "成功后 tick 不改变 validated endpoint")

	a.cancel()
	b.cancel()
	b_udp.close()
	r.close()
	q.close()

func _case_shared_udp_ownership() -> void:
	var shared: PacketPeerUDP = PacketPeerUDP.new()
	_expect(shared.bind(0) == OK, "shared socket bind")
	var shared_port: int = shared.get_local_port()
	var hp: P2PHolePunch = P2PHolePunch.new()
	var remote: Array = [_wan_candidate("127.0.0.1", 9, "127.0.0.1", 9)]
	_expect(hp.begin(SID, A_NONCE, B_NONCE, P2PUDPProbe.Role.GUEST, _local_candidates(), remote, 0, shared), "begin with shared udp")
	_expect(hp.owns_socket() == false, "adopt shared 后 owns_socket() == false")
	## cancel 不得关闭共享 socket。
	hp.cancel()
	_expect(shared.get_local_port() == shared_port, "cancel() 不关闭共享 socket（仍可查询端口）")
	## finish / timeout 也一样。
	var hp2: P2PHolePunch = P2PHolePunch.new()
	_expect(hp2.begin(SID, A_NONCE, B_NONCE, P2PUDPProbe.Role.GUEST, _local_candidates(), remote, 0, shared), "begin2 with shared udp")
	hp2.tick(P2PHolePunch.MAX_PROBE_DURATION_MS + 1)
	_expect(hp2.get_state() == P2PHolePunch.State.TIMEOUT, "timeout 到达")
	_expect(shared.get_local_port() == shared_port, "timeout 不关闭共享 socket")
	hp.reset()
	hp2.reset()
	_expect(shared.get_local_port() == shared_port, "reset 不关闭共享 socket")
	shared.close()

func _case_cancel_and_reset_cleanup() -> void:
	var hp: P2PHolePunch = P2PHolePunch.new()
	var remote: Array = [_wan_candidate("127.0.0.1", 9, "127.0.0.1", 9)]
	_expect(hp.begin(SID, A_NONCE, B_NONCE, P2PUDPProbe.Role.GUEST, _local_candidates(), remote), "begin")
	hp.tick(0)
	_expect(hp.get_active_probe_count() >= 1, "有 active probe")
	hp.cancel()
	_expect(hp.is_terminal(), "cancel 后是终态")
	_expect(hp.get_active_probe_count() == 0, "cancel 后没有 active probe")
	_expect(hp.get_validated_endpoint().is_empty(), "cancel 后没有 validated endpoint")
	## cancel 不影响 probe_id 单调性（防旧 ACK 撞新 probe）。
	var first_counter: int = hp._probe_id_counter
	hp.reset()
	_expect(hp.get_state() == P2PHolePunch.State.IDLE, "reset -> IDLE")
	_expect(hp.get_active_probe_count() == 0, "reset 清空 active probe")
	_expect(hp.get_validated_candidate().is_empty(), "reset 清空 validated candidate")
	_expect(hp.debug_pair_states().is_empty(), "reset 清空 candidate pairs")
	_expect(not hp.owns_socket(), "reset 后不再拥有 socket")
	_expect(hp._probe_id_counter == first_counter, "reset 不重置 probe_id counter（单调防重放）")

# ---- 有界 real-frame 轮询 ----

## 明确等待网络结果，而不是靠「刚好 6 次 tick」：
## 1. 有明确最大等待时间（max_wait_ms），不可能无限循环
## 2. 每轮之间 await process_frame，PROBE_INTERVAL_MS(120) 真的有机会流逝，
##    loopback UDP 包也真的有机会投递完成
## 3. 双方都成功就立刻 return true
## 4. 任一侧进入终态失败就立刻 return false
## 5. 到点未成功 return false，由调用方带诊断报告
##
## 前置两步（B 的暖机）是让测试**确定性**的关键：
## 必须先让 B 走完自己的头两拍（第一拍回 ACK、第二拍发出 B 的第一个 probe），
## 再让 A 开始 drain。否则 A 会先收到 ACK_b 而确认，随即 close() 自建 socket，
## 而 B 的第一个 probe 还没发出去 —— B 从此永远拿不到 ACK。
func _pump_until_success(a: P2PHolePunch, b: P2PHolePunch, max_wait_ms: int) -> bool:
	## 1) 等一帧，让上一阶段 A 发出的 probe 真正进入 B 的收包队列。
	await process_frame
	## 2) B 的暖机两拍：第一拍收 probe 回 ACK（first_tick_skip 不发 probe），
	##    第二拍发出 B 的第一个 probe。
	b.tick(0)
	b.tick(0)
	## 3) 再等一帧，让 ACK_b 与 probe_b 一起进入 A 的收包队列。
	await process_frame

	var deadline: int = Time.get_ticks_msec() + max_wait_ms
	var orphan_since: int = -1
	while Time.get_ticks_msec() < deadline:
		a.tick(0)
		b.tick(0)
		if a.is_success() and b.is_success():
			return true
		if a.is_failed() or b.is_failed():
			return false
		if a.is_success() and not b.is_success():
			if orphan_since < 0:
				orphan_since = Time.get_ticks_msec()
			elif Time.get_ticks_msec() - orphan_since >= ORPHAN_GRACE_MS:
				return false
		await process_frame
	return false

# ---- 辅助 ----

func _local_candidates() -> Array:
	var out: Array = []
	var c: RendezvousContract.Candidate = RendezvousContract.Candidate.new()
	c.path = LobbyPlayer.Path.LAN_IPV4
	c.address = "127.0.0.1"
	c.port = 40000
	out.append(c)
	return out

func _wan_candidate(address: String, port: int, observed_address: String, observed_port: int) -> RendezvousContract.Candidate:
	var c: RendezvousContract.Candidate = RendezvousContract.Candidate.new()
	c.path = LobbyPlayer.Path.WAN_IPV4
	c.address = address
	c.port = port
	c.observed_address = observed_address
	c.observed_port = observed_port
	return c

func _find_pair_by_port(hp: P2PHolePunch, port: int) -> Dictionary:
	for state: Dictionary in hp.debug_pair_states():
		if int(state.get("target_port", 0)) == port:
			return state
	return {}

func _send_raw_ack(socket: PacketPeerUDP, dest_port: int, nonce: String, role: int, probe_id: int) -> void:
	socket.set_dest_address("127.0.0.1", dest_port)
	var now_ms: int = Time.get_ticks_msec()
	var ack: PackedByteArray = P2PUDPProbe.encode_ack(SID, nonce, role, now_ms, now_ms - 5, probe_id)
	socket.put_packet(ack)

# ---- 收尾 ----

func _expect(condition: bool, label: String) -> void:
	if not condition:
		_failures.append(label)

## 失败时打印足以定位原因的诊断：bind / 发送 / ACK / source mismatch / timeout
## 一眼能分辨。不含 nonce / ticket 等敏感内容。
func _print_diagnostics() -> void:
	if _diag_a == null or _diag_b == null:
		return
	var a: P2PHolePunch = _diag_a
	var b: P2PHolePunch = _diag_b
	printerr("P2P_HOLE_PUNCH_INTEGRATION_DIAG: ports %s" % str(_diag_ports))
	for entry: Array in [["A", a], ["B", b]]:
		var label: String = entry[0]
		var hp: P2PHolePunch = entry[1]
		printerr(
			("P2P_HOLE_PUNCH_INTEGRATION_DIAG: %s state=%d success=%s terminal=%s active_probe_count=%d validated=%s")
			% [
				label,
				hp.get_state(),
				str(hp.is_success()),
				str(hp.is_terminal()),
				hp.get_active_probe_count(),
				str(hp.get_validated_endpoint()),
			]
		)
		printerr("P2P_HOLE_PUNCH_INTEGRATION_DIAG: %s pairs=%s" % [label, str(hp.debug_pair_states())])

func _finish() -> void:
	if _failures.is_empty():
		print("P2P_HOLE_PUNCH_INTEGRATION_OK")
		quit(0)
		return
	_print_diagnostics()
	for failure: String in _failures:
		printerr("P2P_HOLE_PUNCH_INTEGRATION_FAIL: %s" % failure)
	quit(1)
