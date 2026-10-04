extends SceneTree

## P2P 连接状态机回归（Phase 9.1）。锁定：
## - 状态转换确定性：同样 (state, event) 永远同样结果
## - 非法转换返回 false 且**不改状态**
## - 协议 / ticket 问题进入明确终态，不落回 DISCONNECTED
## - 三级超时常量存在且互相独立
## - 不依赖 SceneTree / 不持有 peer（本文件不 new 任何 ENet）
##
## 跑法：godot --headless --path . --script res://tests/p2p_connection_state_test.gd
## 通过输出 P2P_CONNECTION_STATE_OK；失败逐条 P2P_CONNECTION_STATE_FAIL 并返回非 0。

var _failures: PackedStringArray = PackedStringArray()

func _initialize() -> void:
	_run_all.call_deferred()

func _run_all() -> void:
	_case_states_and_events_exist()
	_case_happy_path()
	_case_timeouts_are_independent()
	_case_illegal_transitions_are_rejected()
	_case_version_mismatch_is_terminal()
	_case_ticket_rejected_is_reachable_from_active_states()
	_case_timeout_is_terminal()
	_case_cancel_only_while_active()
	_case_direct_failure_allows_another_attempt()
	_case_direct_probe_attempts_reset()
	_case_reset_clears_everything()
	_case_transition_is_deterministic()
	_case_no_scenetree_dependency()
	_finish()

# ---- 用例 ----

func _case_states_and_events_exist() -> void:
	_expect(P2PConnectionState.State.DISCONNECTED == 0, "DISCONNECTED 存在")
	_expect(P2PConnectionState.State.CONNECTED == 10, "CONNECTED 存在")
	_expect(P2PConnectionState.State.TICKET_REJECTED == 13, "TICKET_REJECTED 存在")
	_expect(P2PConnectionState.State.VERSION_MISMATCH == 14, "VERSION_MISMATCH 存在")
	_expect(P2PConnectionState.Event.RESET == 17, "RESET 事件存在")
	_expect(P2PConnectionState.state_name(P2PConnectionState.State.HANDSHAKING) == "handshaking", "state_name 覆盖 HANDSHAKING")
	_expect(P2PConnectionState.event_name(P2PConnectionState.Event.BEGIN_DIRECT_ATTEMPT) == "begin_direct_attempt", "event_name 覆盖 begin_direct_attempt")

## 正常路径：rendezvous -> candidates -> direct -> handshaking -> connected。
func _case_happy_path() -> void:
	var machine: P2PConnectionState = P2PConnectionState.new()
	_expect(machine.get_state() == P2PConnectionState.State.DISCONNECTED, "初始是 DISCONNECTED")
	_expect(machine.transition(P2PConnectionState.Event.BEGIN_RENDEZVOUS), "begin_rendezvous 合法")
	_expect(machine.get_state() == P2PConnectionState.State.RENDEZVOUS_CONNECTING, "-> RENDEZVOUS_CONNECTING")
	_expect(machine.transition(P2PConnectionState.Event.RENDEZVOUS_REGISTERED), "rendezvous_registered 合法")
	_expect(machine.get_state() == P2PConnectionState.State.RENDEZVOUS_REGISTERED, "-> RENDEZVOUS_REGISTERED")
	_expect(machine.transition(P2PConnectionState.Event.CANDIDATES_RECEIVED), "candidates_received 合法")
	_expect(machine.get_state() == P2PConnectionState.State.CANDIDATES_RECEIVED, "-> CANDIDATES_RECEIVED")
	_expect(machine.transition(P2PConnectionState.Event.BEGIN_DIRECT_ATTEMPT), "begin_direct_attempt 合法")
	_expect(machine.get_state() == P2PConnectionState.State.DIRECT_CONNECTING, "-> DIRECT_CONNECTING")
	_expect(machine.direct_attempts() == 1, "直连尝试计数 = 1")
	_expect(machine.transition(P2PConnectionState.Event.DIRECT_CONNECTED), "direct_connected 合法")
	_expect(machine.get_state() == P2PConnectionState.State.HANDSHAKING, "-> HANDSHAKING")
	_expect(not machine.is_terminal(), "HANDSHAKING 不是终态")
	_expect(machine.transition(P2PConnectionState.Event.HANDSHAKE_OK), "handshake_ok 合法")
	_expect(machine.get_state() == P2PConnectionState.State.CONNECTED, "-> CONNECTED")
	_expect(machine.is_connection_established(), "is_connection_established() == true")
	_expect(machine.is_terminal(), "CONNECTED 是终态")

## 三级超时必须是三个独立值，不允许一个数字覆盖全部。
func _case_timeouts_are_independent() -> void:
	var r: float = P2PConnectionState.RENDEZVOUS_TIMEOUT_SEC
	var d: float = P2PConnectionState.DIRECT_PROBE_TIMEOUT_SEC
	var o: float = P2PConnectionState.OVERALL_JOIN_TIMEOUT_SEC
	_expect(r > 0.0 and d > 0.0 and o > 0.0, "三级超时都为正")
	_expect(r != d and d != o and r != o, "三级超时互不相同（不是一个数字）")
	_expect(o > r and o > d, "总超时大于任一单阶段超时")
	_expect(is_equal_approx(r, ConnectAttemptRunner.RENDEZVOUS_TIMEOUT_SEC), "rendezvous 超时与 runner 一致")
	_expect(is_equal_approx(d, ConnectAttemptRunner.DIRECT_ATTEMPT_TIMEOUT_SEC), "direct probe 超时与 runner 一致")
	_expect(is_equal_approx(o, ConnectAttemptRunner.OVERALL_JOIN_TIMEOUT_SEC), "overall 超时与 runner 一致")
	## Phase 9.2.1 起超时在第三处也有定义：rendezvous 客户端用同一组预算，
	## 三处必须始终一致，否则注册阶段与直连阶段会各算各的。
	_expect(
		is_equal_approx(r, RendezvousContract.RENDEZVOUS_TIMEOUT_SEC),
		"rendezvous 超时与 RendezvousContract 一致"
	)
	_expect(
		is_equal_approx(o, RendezvousContract.OVERALL_JOIN_TIMEOUT_SEC),
		"overall 超时与 RendezvousContract 一致"
	)
	## 服务端 session 空闲阈值必须**大于**客户端整体预算，否则客户端还在等就被回收。
	_expect(
		RendezvousContract.SESSION_IDLE_TIMEOUT_SEC > o,
		"服务端 session 空闲阈值 > 客户端整体超时"
	)

## 非法转换必须返回 false 且状态不变（确定性的核心保证）。
func _case_illegal_transitions_are_rejected() -> void:
	var machine: P2PConnectionState = P2PConnectionState.new()
	## DISCONNECTED 上不能直接 handshake_ok / direct_connected。
	_expect(not machine.transition(P2PConnectionState.Event.HANDSHAKE_OK), "DISCONNECTED 上 handshake_ok 被拒")
	_expect(not machine.transition(P2PConnectionState.Event.DIRECT_CONNECTED), "DISCONNECTED 上 direct_connected 被拒")
	_expect(not machine.transition(P2PConnectionState.Event.CANDIDATES_RECEIVED), "DISCONNECTED 上 candidates_received 被拒")
	_expect(machine.get_state() == P2PConnectionState.State.DISCONNECTED, "非法转换后状态不变")
	## 跳过 rendezvous 直接走 candidates。
	_expect(machine.transition(P2PConnectionState.Event.BEGIN_RENDEZVOUS), "begin_rendezvous 合法")
	_expect(not machine.transition(P2PConnectionState.Event.CANDIDATES_RECEIVED), "未注册就 candidates_received 被拒")
	_expect(not machine.transition(P2PConnectionState.Event.HANDSHAKE_OK), "RENDEZVOUS_CONNECTING 上 handshake_ok 被拒")
	_expect(machine.get_state() == P2PConnectionState.State.RENDEZVOUS_CONNECTING, "拒绝后仍在 RENDEZVOUS_CONNECTING")
	## 跳过 direct 直接 handshake。
	_expect(machine.transition(P2PConnectionState.Event.RENDEZVOUS_REGISTERED), "registered 合法")
	_expect(machine.transition(P2PConnectionState.Event.CANDIDATES_RECEIVED), "candidates 合法")
	_expect(not machine.transition(P2PConnectionState.Event.DIRECT_CONNECTED), "未 begin_direct 就 direct_connected 被拒")
	_expect(machine.get_state() == P2PConnectionState.State.CANDIDATES_RECEIVED, "拒绝后仍在 CANDIDATES_RECEIVED")

## 协议不符 -> VERSION_MISMATCH 终态。
func _case_version_mismatch_is_terminal() -> void:
	var machine: P2PConnectionState = _machine_in_handshaking()
	_expect(machine.transition(P2PConnectionState.Event.VERSION_MISMATCH), "HANDSHAKING 上 version_mismatch 合法")
	_expect(machine.get_state() == P2PConnectionState.State.VERSION_MISMATCH, "-> VERSION_MISMATCH")
	_expect(machine.is_terminal(), "VERSION_MISMATCH 是终态")
	_expect(not machine.is_connection_established(), "VERSION_MISMATCH 不是 CONNECTED")
	## 终态上不能再握手成功。
	_expect(not machine.transition(P2PConnectionState.Event.HANDSHAKE_OK), "终态上 handshake_ok 被拒")
	_expect(machine.get_state() == P2PConnectionState.State.VERSION_MISMATCH, "状态保持 VERSION_MISMATCH")

## ticket 有**两个**校验点（9.2.1 rendezvous 注册 + Host protocol 6 握手），
## 所以任一进行中的阶段都可能进入 TICKET_REJECTED 终态。
func _case_ticket_rejected_is_reachable_from_active_states() -> void:
	## 1) rendezvous 注册阶段被服务端拒（Phase 9.2.1 新增路径）。
	var registering: P2PConnectionState = P2PConnectionState.new()
	_advance_to(registering, P2PConnectionState.State.RENDEZVOUS_CONNECTING)
	_expect(
		registering.transition(P2PConnectionState.Event.TICKET_REJECTED),
		"RENDEZVOUS_CONNECTING 上 ticket_rejected 合法（服务端 register 时拒票）"
	)
	_expect(registering.get_state() == P2PConnectionState.State.TICKET_REJECTED, "-> TICKET_REJECTED")
	_expect(registering.is_terminal(), "TICKET_REJECTED 是终态")
	_expect(not registering.is_connection_established(), "TICKET_REJECTED 不是 CONNECTED")

	## 2) 已注册但还在等候选时被拒。
	var registered: P2PConnectionState = P2PConnectionState.new()
	_advance_to(registered, P2PConnectionState.State.RENDEZVOUS_REGISTERED)
	_expect(
		registered.transition(P2PConnectionState.Event.TICKET_REJECTED),
		"RENDEZVOUS_REGISTERED 上 ticket_rejected 合法"
	)

	## 3) 直连阶段被拒也合法（Host 校验权威在握手前可能先回错误）。
	var direct: P2PConnectionState = P2PConnectionState.new()
	_advance_to(direct, P2PConnectionState.State.DIRECT_CONNECTING)
	_expect(direct.transition(P2PConnectionState.Event.TICKET_REJECTED), "DIRECT_CONNECTING 上 ticket_rejected 合法")
	_expect(direct.get_state() == P2PConnectionState.State.TICKET_REJECTED, "-> TICKET_REJECTED")

	## 4) 握手阶段被 Host 拒（Phase 8 原路径）仍然合法。
	var handshaking: P2PConnectionState = _machine_in_handshaking()
	_expect(handshaking.transition(P2PConnectionState.Event.TICKET_REJECTED), "HANDSHAKING 上 ticket_rejected 合法")
	_expect(handshaking.get_state() == P2PConnectionState.State.TICKET_REJECTED, "-> TICKET_REJECTED")

	## 但 DISCONNECTED 与终态上仍然非法。
	var idle: P2PConnectionState = P2PConnectionState.new()
	_expect(not idle.transition(P2PConnectionState.Event.TICKET_REJECTED), "DISCONNECTED 上 ticket_rejected 被拒")
	_expect(not handshaking.transition(P2PConnectionState.Event.TICKET_REJECTED), "终态上 ticket_rejected 被拒")
	_expect(
		handshaking.get_state() == P2PConnectionState.State.TICKET_REJECTED,
		"二次拒绝不改变状态"
	)

func _case_timeout_is_terminal() -> void:
	var machine: P2PConnectionState = P2PConnectionState.new()
	_advance_to(machine, P2PConnectionState.State.DIRECT_CONNECTING)
	_expect(machine.transition(P2PConnectionState.Event.TIMEOUT), "DIRECT_CONNECTING 上 timeout 合法")
	_expect(machine.get_state() == P2PConnectionState.State.TIMEOUT, "-> TIMEOUT")
	_expect(machine.is_terminal(), "TIMEOUT 是终态")
	## DISCONNECTED 上 timeout 无意义，必须被拒。
	var idle: P2PConnectionState = P2PConnectionState.new()
	_expect(not idle.transition(P2PConnectionState.Event.TIMEOUT), "DISCONNECTED 上 timeout 被拒")

## cancel 只在「进行中」有意义。
func _case_cancel_only_while_active() -> void:
	var idle: P2PConnectionState = P2PConnectionState.new()
	_expect(not idle.transition(P2PConnectionState.Event.CANCEL), "DISCONNECTED 上 cancel 被拒")
	var running: P2PConnectionState = P2PConnectionState.new()
	_advance_to(running, P2PConnectionState.State.RENDEZVOUS_CONNECTING)
	_expect(running.transition(P2PConnectionState.Event.CANCEL), "进行中 cancel 合法")
	_expect(running.get_state() == P2PConnectionState.State.FAILED, "cancel -> FAILED")
	_expect(running.is_terminal(), "FAILED 是终态")
	## 终态上再 cancel 非法。
	_expect(not running.transition(P2PConnectionState.Event.CANCEL), "终态上 cancel 被拒")

## direct_failed 允许再试一次（自环），不直接终结。
func _case_direct_failure_allows_another_attempt() -> void:
	var machine: P2PConnectionState = P2PConnectionState.new()
	_advance_to(machine, P2PConnectionState.State.DIRECT_CONNECTING)
	_expect(machine.transition(P2PConnectionState.Event.DIRECT_FAILED), "direct_failed 合法")
	_expect(machine.get_state() == P2PConnectionState.State.DIRECT_CONNECTING, "direct_failed 留在 DIRECT_CONNECTING")
	_expect(not machine.is_terminal(), "direct_failed 后不是终态（可换候选）")
	_expect(machine.transition(P2PConnectionState.Event.BEGIN_DIRECT_ATTEMPT), "可再次 begin_direct_attempt")
	_expect(machine.direct_attempts() == 2, "直连尝试计数 = 2")

## Phase 9.2.2：BEGIN_DIRECT_PROBING 累加计数，reset 必须一并清空。
func _case_direct_probe_attempts_reset() -> void:
	var machine: P2PConnectionState = P2PConnectionState.new()
	_advance_to(machine, P2PConnectionState.State.CANDIDATES_RECEIVED)
	_expect(machine.transition(P2PConnectionState.Event.BEGIN_DIRECT_PROBING), "begin_direct_probing 合法")
	_expect(machine.get_state() == P2PConnectionState.State.DIRECT_PROBING, "-> DIRECT_PROBING")
	_expect(machine.direct_probe_attempts() == 1, "probe 尝试计数 = 1")
	machine.reset()
	_expect(machine.direct_probe_attempts() == 0, "reset 清空 probe 尝试计数")

func _case_reset_clears_everything() -> void:
	var machine: P2PConnectionState = P2PConnectionState.new()
	machine.set_local_candidate_count(3)
	machine.set_remote_candidate_count(2)
	_advance_to(machine, P2PConnectionState.State.CONNECTED)
	_expect(machine.is_connection_established(), "重置前是 CONNECTED")
	machine.reset()
	_expect(machine.get_state() == P2PConnectionState.State.DISCONNECTED, "reset -> DISCONNECTED")
	_expect(machine.direct_attempts() == 0, "reset 清空直连计数")
	_expect(machine.remote_candidate_count() == 0, "reset 清空远端候选计数")
	_expect(not machine.is_terminal(), "DISCONNECTED 不是终态")
	## 重置后可以重新发起完整流程。
	_expect(machine.transition(P2PConnectionState.Event.BEGIN_RENDEZVOUS), "reset 后可重新 begin_rendezvous")

## 确定性：同一串事件在两个实例上必须得到完全一致的状态序列。
func _case_transition_is_deterministic() -> void:
	var script: Array[int] = [
		P2PConnectionState.Event.BEGIN_RENDEZVOUS,
		P2PConnectionState.Event.RENDEZVOUS_REGISTERED,
		P2PConnectionState.Event.CANDIDATES_RECEIVED,
		P2PConnectionState.Event.BEGIN_DIRECT_ATTEMPT,
		P2PConnectionState.Event.DIRECT_FAILED,
		P2PConnectionState.Event.BEGIN_DIRECT_ATTEMPT,
		P2PConnectionState.Event.DIRECT_CONNECTED,
		P2PConnectionState.Event.HANDSHAKE_OK,
	]
	var first: PackedInt32Array = _replay(script)
	var second: PackedInt32Array = _replay(script)
	_expect(first == second, "同一事件序列产生同样的状态序列")
	_expect(first.size() == script.size() + 1, "状态序列长度 = 事件数 + 1")
	_expect(first[first.size() - 1] == P2PConnectionState.State.CONNECTED, "回放最终到达 CONNECTED")

## 状态对象必须与 SceneTree 无关：不 new 节点、不碰 multiplayer。
func _case_no_scenetree_dependency() -> void:
	var machine: P2PConnectionState = P2PConnectionState.new()
	_expect(machine.get_state() == P2PConnectionState.State.DISCONNECTED, "状态对象可独立构造（不依赖 SceneTree）")
	## Godot 4.6 在无 peer 时给的是 OfflineMultiplayerPeer 占位对象（不是 null），
	## 所以这里断言的是「没有真实 active peer」。
	_expect(not _has_active_peer(), "状态机测试全程没有 active peer")
	_expect(machine._next_state(P2PConnectionState.State.DISCONNECTED, P2PConnectionState.Event.BEGIN_RENDEZVOUS) == P2PConnectionState.State.RENDEZVOUS_CONNECTING, "_next_state 是纯函数")
	_expect(machine._next_state(P2PConnectionState.State.CONNECTED, P2PConnectionState.Event.BEGIN_RENDEZVOUS) == -1, "_next_state 对终态返回 -1")

## 是否存在真实 active peer（OfflineMultiplayerPeer 占位不算）。
func _has_active_peer() -> bool:
	var peer: MultiplayerPeer = root.multiplayer.multiplayer_peer
	if peer == null:
		return false
	return not (peer is OfflineMultiplayerPeer)

# ---- 辅助 ----

func _machine_in_handshaking() -> P2PConnectionState:
	var machine: P2PConnectionState = P2PConnectionState.new()
	_advance_to(machine, P2PConnectionState.State.HANDSHAKING)
	return machine

## 沿正常路径推进到目标状态（只走 happy path）。
func _advance_to(machine: P2PConnectionState, target: int) -> void:
	var path: Array[int] = [
		P2PConnectionState.State.RENDEZVOUS_CONNECTING,
		P2PConnectionState.State.RENDEZVOUS_REGISTERED,
		P2PConnectionState.State.CANDIDATES_RECEIVED,
		P2PConnectionState.State.DIRECT_CONNECTING,
		P2PConnectionState.State.HANDSHAKING,
		P2PConnectionState.State.CONNECTED,
	]
	var events: Array[int] = [
		P2PConnectionState.Event.BEGIN_RENDEZVOUS,
		P2PConnectionState.Event.RENDEZVOUS_REGISTERED,
		P2PConnectionState.Event.CANDIDATES_RECEIVED,
		P2PConnectionState.Event.BEGIN_DIRECT_ATTEMPT,
		P2PConnectionState.Event.DIRECT_CONNECTED,
		P2PConnectionState.Event.HANDSHAKE_OK,
	]
	for i: int in path.size():
		if machine.get_state() == target:
			return
		machine.transition(events[i])

func _replay(script: Array[int]) -> PackedInt32Array:
	var machine: P2PConnectionState = P2PConnectionState.new()
	var states: PackedInt32Array = PackedInt32Array()
	states.append(int(machine.get_state()))
	for event: int in script:
		machine.transition(event as P2PConnectionState.Event)
		states.append(int(machine.get_state()))
	return states

func _expect(condition: bool, label: String) -> void:
	if not condition:
		_failures.append(label)

func _finish() -> void:
	if _failures.is_empty():
		print("P2P_CONNECTION_STATE_OK")
		quit(0)
		return
	for failure: String in _failures:
		printerr("P2P_CONNECTION_STATE_FAIL: %s" % failure)
	quit(1)
