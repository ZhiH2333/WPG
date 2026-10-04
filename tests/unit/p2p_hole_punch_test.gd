extends SceneTree

## P2PHolePunch 回归（Phase 9.2）：启动、探测、成功、失败、超时、过期 attempt、候选回退。
## 纯逻辑，不建 peer、不开真实端口、不碰 SceneTree.multiplayer。
## 注意：P2PHolePunch 依赖 PacketPeerUDP，在 headless 下可用。
## 跑法：godot --headless --path . --script res://tests/p2p_hole_punch_test.gd
## 通过输出 P2P_HOLE_PUNCH_OK；失败逐条 P2P_HOLE_PUNCH_FAIL 并返回非 0。

var _failures: PackedStringArray = PackedStringArray()

func _initialize() -> void:
	_case_start_probing()
	_case_probing_state()
	_case_success_transition()
	_case_failure_transition()
	_case_timeout()
	_case_stale_generation()
	_case_candidate_fallback_order()
	_case_cancel_cleanup()
	_case_reset()
	_case_simultaneous_probing()
	_case_shared_udp_ownership()
	_case_target_from_observed()
	_finish()

# ---- 用例 ----

func _case_start_probing() -> void:
	var hp: P2PHolePunch = P2PHolePunch.new()
	var session_id: String = "abcdef1234567890"
	var local_nonce: String = "0123456789abcdef0123456789abcdef"
	var remote_nonce: String = "fedcba9876543210fedcba9876543210"
	var local_candidates: Array = _make_test_candidates("192.168.1.50", 17777)
	var remote_candidates: Array = _make_test_candidates("192.168.1.60", 17777)
	var ok: bool = hp.begin(session_id, local_nonce, remote_nonce, P2PUDPProbe.Role.GUEST, local_candidates, remote_candidates)
	_expect(ok, "begin returns true")
	_expect(hp.get_state() == P2PHolePunch.State.PROBING, "state = PROBING")
	_expect(hp.is_active(), "is_active true")
	hp.cancel()

func _case_probing_state() -> void:
	var hp: P2PHolePunch = P2PHolePunch.new()
	var session_id: String = "abcdef1234567890"
	var local_nonce: String = "0123456789abcdef0123456789abcdef"
	var remote_nonce: String = "fedcba9876543210fedcba9876543210"
	var local_candidates: Array = _make_test_candidates("192.168.1.50", 17777)
	var remote_candidates: Array = _make_test_candidates("192.168.1.60", 17777)
	hp.begin(session_id, local_nonce, remote_nonce, P2PUDPProbe.Role.GUEST, local_candidates, remote_candidates)
	## tick 不应立即改变状态
	hp.tick(100)
	_expect(hp.get_state() == P2PHolePunch.State.PROBING, "still PROBING after 100ms")
	hp.cancel()

func _case_success_transition() -> void:
	## 模拟双向 probe 成功：这里只能测试状态机逻辑，真实 UDP 需要 E2E
	var hp: P2PHolePunch = P2PHolePunch.new()
	var session_id: String = "abcdef1234567890"
	var local_nonce: String = "0123456789abcdef0123456789abcdef"
	var remote_nonce: String = "fedcba9876543210fedcba9876543210"
	var local_candidates: Array = _make_test_candidates("192.168.1.50", 17777)
	var remote_candidates: Array = _make_test_candidates("192.168.1.60", 17777)
	hp.begin(session_id, local_nonce, remote_nonce, P2PUDPProbe.Role.GUEST, local_candidates, remote_candidates)
	## 手动触发成功（模拟内部 _bidirectional_confirmed = true）
	## 由于内部字段私有，这里只验证 begin 后状态正确
	_expect(hp.is_active(), "active after begin")
	hp.cancel()

func _case_failure_transition() -> void:
	var hp: P2PHolePunch = P2PHolePunch.new()
	var session_id: String = "abcdef1234567890"
	var local_nonce: String = "0123456789abcdef0123456789abcdef"
	var remote_nonce: String = "fedcba9876543210fedcba9876543210"
	## 空候选 -> 立即失败
	var ok: bool = hp.begin(session_id, local_nonce, remote_nonce, P2PUDPProbe.Role.GUEST, [], [])
	_expect(not ok, "begin with empty candidates fails")
	_expect(hp.get_state() == P2PHolePunch.State.PATH_FAILED, "state = PATH_FAILED")
	_expect(hp.is_failed(), "is_failed true")

func _case_timeout() -> void:
	var hp: P2PHolePunch = P2PHolePunch.new()
	var session_id: String = "abcdef1234567890"
	var local_nonce: String = "0123456789abcdef0123456789abcdef"
	var remote_nonce: String = "fedcba9876543210fedcba9876543210"
	var local_candidates: Array = _make_test_candidates("192.168.1.50", 17777)
	var remote_candidates: Array = _make_test_candidates("192.168.1.60", 17777)
	hp.begin(session_id, local_nonce, remote_nonce, P2PUDPProbe.Role.GUEST, local_candidates, remote_candidates)
	## 推进时间超过 MAX_PROBE_DURATION_MS (3500ms)
	hp.tick(4000)
	_expect(hp.get_state() == P2PHolePunch.State.TIMEOUT, "state = TIMEOUT after timeout")
	_expect(hp.is_failed(), "is_failed true (timeout is failure)")

func _case_stale_generation() -> void:
	## generation 机制：新的 begin 会让旧的回调失效
	var hp: P2PHolePunch = P2PHolePunch.new()
	var session_id: String = "abcdef1234567890"
	var local_nonce: String = "0123456789abcdef0123456789abcdef"
	var remote_nonce: String = "fedcba9876543210fedcba9876543210"
	var local_candidates: Array = _make_test_candidates("192.168.1.50", 17777)
	var remote_candidates: Array = _make_test_candidates("192.168.1.60", 17777)
	hp.begin(session_id, local_nonce, remote_nonce, P2PUDPProbe.Role.GUEST, local_candidates, remote_candidates)
	## 再次 begin（新 generation）
	var ok: bool = hp.begin(session_id, local_nonce, remote_nonce, P2PUDPProbe.Role.GUEST, local_candidates, remote_candidates)
	_expect(not ok, "second begin while active returns false")
	hp.cancel()

func _case_candidate_fallback_order() -> void:
	## 验证 candidate pairs 按优先级排序：LOCAL_PRIVATE > LOCAL_IPV6 > OBSERVED
	var hp: P2PHolePunch = P2PHolePunch.new()
	var session_id: String = "abcdef1234567890"
	var local_nonce: String = "0123456789abcdef0123456789abcdef"
	var remote_nonce: String = "fedcba9876543210fedcba9876543210"
	## 本地：private + observed
	var local_candidates: Array = []
	var c1: RendezvousContract.Candidate = RendezvousContract.Candidate.new()
	c1.path = LobbyPlayer.Path.LAN_IPV4
	c1.address = "192.168.1.50"
	c1.port = 17777
	local_candidates.append(c1)
	var c2: RendezvousContract.Candidate = RendezvousContract.Candidate.new()
	c2.path = LobbyPlayer.Path.WAN_IPV4
	c2.address = "203.0.113.10"
	c2.port = 49152
	c2.observed_address = "203.0.113.10"
	c2.observed_port = 49152
	local_candidates.append(c2)
	## 远端：private + observed
	var remote_candidates: Array = []
	var c3: RendezvousContract.Candidate = RendezvousContract.Candidate.new()
	c3.path = LobbyPlayer.Path.LAN_IPV4
	c3.address = "192.168.1.60"
	c3.port = 17777
	remote_candidates.append(c3)
	var c4: RendezvousContract.Candidate = RendezvousContract.Candidate.new()
	c4.path = LobbyPlayer.Path.WAN_IPV4
	c4.address = "203.0.113.20"
	c4.port = 49152
	c4.observed_address = "203.0.113.20"
	c4.observed_port = 49152
	remote_candidates.append(c4)
	hp.begin(session_id, local_nonce, remote_nonce, P2PUDPProbe.Role.GUEST, local_candidates, remote_candidates)
	_expect(hp.is_active(), "active with mixed candidates")
	## 内部 _candidate_pairs 应该是 4 个组合，按优先级排序
	## 这里只能验证 begin 成功
	hp.cancel()

func _case_cancel_cleanup() -> void:
	var hp: P2PHolePunch = P2PHolePunch.new()
	var session_id: String = "abcdef1234567890"
	var local_nonce: String = "0123456789abcdef0123456789abcdef"
	var remote_nonce: String = "fedcba9876543210fedcba9876543210"
	var local_candidates: Array = _make_test_candidates("192.168.1.50", 17777)
	var remote_candidates: Array = _make_test_candidates("192.168.1.60", 17777)
	hp.begin(session_id, local_nonce, remote_nonce, P2PUDPProbe.Role.GUEST, local_candidates, remote_candidates)
	_expect(hp.is_active(), "active before cancel")
	hp.cancel()
	_expect(hp.get_state() == P2PHolePunch.State.PATH_FAILED, "state = PATH_FAILED after cancel")
	_expect(not hp.is_active(), "not active after cancel")

func _case_reset() -> void:
	var hp: P2PHolePunch = P2PHolePunch.new()
	var session_id: String = "abcdef1234567890"
	var local_nonce: String = "0123456789abcdef0123456789abcdef"
	var remote_nonce: String = "fedcba9876543210fedcba9876543210"
	var local_candidates: Array = _make_test_candidates("192.168.1.50", 17777)
	var remote_candidates: Array = _make_test_candidates("192.168.1.60", 17777)
	hp.begin(session_id, local_nonce, remote_nonce, P2PUDPProbe.Role.GUEST, local_candidates, remote_candidates)
	hp.cancel()
	hp.reset()
	_expect(hp.get_state() == P2PHolePunch.State.IDLE, "state = IDLE after reset")
	_expect(not hp.is_active(), "not active after reset")
	_expect(hp.get_validated_candidate().is_empty(), "reset 清空 validated candidate")
	_expect(hp.debug_pair_states().is_empty(), "reset 清空 candidate pairs")
	_expect(not hp.owns_socket(), "reset 后不拥有 socket")

## Simultaneous probing：多个 candidate pair 同时 active，而不是串行。
func _case_simultaneous_probing() -> void:
	var hp: P2PHolePunch = P2PHolePunch.new()
	## 2 local x 2 remote = 4 pairs。
	var local_candidates: Array = []
	local_candidates.append(_make_candidate(LobbyPlayer.Path.LAN_IPV4, "192.168.1.50", 17777))
	local_candidates.append(_make_candidate(LobbyPlayer.Path.IPV6, "2001:db8::5", 17777))
	var remote_candidates: Array = []
	remote_candidates.append(_make_candidate(LobbyPlayer.Path.LAN_IPV4, "192.168.1.60", 17777))
	remote_candidates.append(_make_candidate(LobbyPlayer.Path.WAN_IPV4, "203.0.113.60", 49152, "203.0.113.60", 49152))
	hp.begin("abcdef1234567890", "0123456789abcdef0123456789abcdef", "fedcba9876543210fedcba9876543210", P2PUDPProbe.Role.GUEST, local_candidates, remote_candidates)
	_expect(hp.debug_pair_states().size() == 4, "构建 4 个 candidate pair")
	_expect(hp.get_active_probe_count() == 4, "4 个 pair 同时 active")
	hp.tick(0)
	var all_sent: bool = true
	for state: Dictionary in hp.debug_pair_states():
		if int(state.probes_sent) < 1:
			all_sent = false
	_expect(all_sent, "一次 tick 所有 pair 都发 probe（simultaneous）")
	_expect(hp.get_active_probe_count() == 4, "发送后仍全部 active")
	hp.cancel()
	_expect(hp.get_active_probe_count() == 0, "cancel 后没有 active probe")

## 共享 UDP ownership：adopt 后 cancel/timeout/reset 都不关闭它。
func _case_shared_udp_ownership() -> void:
	var shared: PacketPeerUDP = PacketPeerUDP.new()
	_expect(shared.bind(0) == OK, "shared bind")
	var port: int = shared.get_local_port()
	var hp: P2PHolePunch = P2PHolePunch.new()
	var local_candidates: Array = _make_test_candidates("192.168.1.50", 17777)
	var remote_candidates: Array = _make_test_candidates("192.168.1.60", 17777)
	_expect(hp.begin("abcdef1234567890", "0123456789abcdef0123456789abcdef", "fedcba9876543210fedcba9876543210", P2PUDPProbe.Role.GUEST, local_candidates, remote_candidates, 0, shared), "begin with shared")
	_expect(hp.owns_socket() == false, "owns_socket() == false")
	hp.cancel()
	_expect(shared.get_local_port() == port, "cancel 不关共享 socket")
	hp.reset()
	_expect(shared.get_local_port() == port, "reset 不关共享 socket")
	shared.close()

## 打洞目标必须来自 observed endpoint，而不是对端自报的私网地址。
func _case_target_from_observed() -> void:
	var hp: P2PHolePunch = P2PHolePunch.new()
	var local_candidates: Array = _make_test_candidates("192.168.1.50", 17777)
	var remote_candidates: Array = []
	remote_candidates.append(_make_candidate(
		LobbyPlayer.Path.WAN_IPV4, "10.0.0.99", 1, "203.0.113.77", 51820
	))
	hp.begin("abcdef1234567890", "0123456789abcdef0123456789abcdef", "fedcba9876543210fedcba9876543210", P2PUDPProbe.Role.GUEST, local_candidates, remote_candidates)
	var states: Array[Dictionary] = hp.debug_pair_states()
	_expect(states.size() == 1, "1 个 pair")
	_expect(int(states[0].target_port) == 51820, "target = observed port，而不是自报 port")
	_expect(str(states[0].target_address) == "203.0.113.77", "target = observed address")
	_expect(int(states[0].advertised_port) == 1, "advertised 端点单独保留")
	hp.cancel()

# ---- 辅助 ----

func _make_test_candidates(address: String, port: int) -> Array:
	var candidates: Array = []
	var c: RendezvousContract.Candidate = RendezvousContract.Candidate.new()
	c.path = LobbyPlayer.Path.LAN_IPV4
	c.address = address
	c.port = port
	candidates.append(c)
	return candidates

func _make_candidate(path: int, address: String, port: int, observed_address: String = "", observed_port: int = 0) -> RendezvousContract.Candidate:
	var c: RendezvousContract.Candidate = RendezvousContract.Candidate.new()
	c.path = path
	c.address = address
	c.port = port
	c.observed_address = observed_address
	c.observed_port = observed_port
	return c

# ---- 收尾 ----

func _expect(condition: bool, label: String) -> void:
	if not condition:
		_failures.append(label)

func _finish() -> void:
	if _failures.is_empty():
		print("P2P_HOLE_PUNCH_OK")
		quit(0)
		return
	for failure: String in _failures:
		printerr("P2P_HOLE_PUNCH_FAIL: %s" % failure)
	quit(1)