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
## 跑法：godot --headless --path . --script res://tests/p2p_hole_punch_integration_test.gd
## 通过输出 P2P_HOLE_PUNCH_INTEGRATION_OK；失败逐条 _FAIL 并返回非 0。

const SID := "abcdef1234567890"
const A_NONCE := "0123456789abcdef0123456789abcdef"
const B_NONCE := "fedcba9876543210fedcba9876543210"

var _failures: PackedStringArray = PackedStringArray()

func _initialize() -> void:
	_run_all.call_deferred()

func _run_all() -> void:
	_case_two_instance_bidirectional_punch()
	_case_shared_udp_ownership()
	_case_cancel_and_reset_cleanup()
	_finish()

# ---- 用例 ----

func _case_two_instance_bidirectional_punch() -> void:
	var port_b: int = _reserve_free_port()
	var port_r: int = _reserve_free_port()
	## R = 冒充「一个永远不回有效 ACK 的对端」的原始 socket（用于 stale ACK / 失败 pair）。
	var r: PacketPeerUDP = PacketPeerUDP.new()
	_expect(r.bind(port_r) == OK, "raw R socket bind")
	var port_q: int = _reserve_free_port()
	var q: PacketPeerUDP = PacketPeerUDP.new()
	_expect(q.bind(port_q) == OK, "raw Q socket bind（source mismatch 用）")

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

	## B 的远端候选 = A 的实际绑定端点。
	var remote_b: Array = [_wan_candidate("127.0.0.1", port_a, "127.0.0.1", port_a)]
	_expect(b.begin(SID, B_NONCE, A_NONCE, P2PUDPProbe.Role.HOST, _local_candidates(), remote_b, port_b), "B begin")

	## simultaneous probing：begin 后两个 pair 都是 active。
	_expect(a.get_active_probe_count() == 2, "A 有 2 个同时 active 的 probe pair")

	## 第一次 tick：两个 pair 都发出 probe（不再串行）。
	a.tick(0)
	var states: Array[Dictionary] = a.debug_pair_states()
	_expect(states.size() == 2, "A 构建了 2 个 candidate pair")
	var sent_all: bool = true
	for state: Dictionary in states:
		if int(state.probes_sent) < 1:
			sent_all = false
	_expect(sent_all, "两个 pair 第一次 tick 都发了 probe（simultaneous）")

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

	## 真实的双向打洞：A/B 交替 tick，R 永不回有效 ACK。
	for _i: int in 6:
		a.tick(0)
		b.tick(0)
	a.tick(0)
	b.tick(0)
	a.tick(0)

	_expect(a.is_success(), "A 双向打洞成功（PATH_ESTABLISHED）")
	_expect(b.is_success(), "B 双向打洞成功（PATH_ESTABLISHED）")

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
	var after: Array[Dictionary] = a.debug_pair_states()
	var failing_after: Dictionary = _find_pair_by_port(a, port_r)
	_expect(bool(failing_after.get("ack_received", true)) == false, "失败 pair 没有误报 ACK")
	_expect(a.get_active_probe_count() == 0, "成功后其它 active probe 已停止")
	## 成功后再 tick 不会改变 validated endpoint（stale ACK 不影响最终状态）。
	var before_port: int = int(a.get_validated_endpoint().get("port", 0))
	a.tick(5000)
	_expect(int(a.get_validated_endpoint().get("port", 0)) == before_port, "成功后 tick 不改变 validated endpoint")

	a.cancel()
	b.cancel()
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

## 占用再释放一个端口，得到一个「大概率仍可用」的固定端口。
func _reserve_free_port() -> int:
	var probe: PacketPeerUDP = PacketPeerUDP.new()
	if probe.bind(0) != OK:
		return 0
	var port: int = probe.get_local_port()
	probe.close()
	return port

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

func _finish() -> void:
	if _failures.is_empty():
		print("P2P_HOLE_PUNCH_INTEGRATION_OK")
		quit(0)
		return
	for failure: String in _failures:
		printerr("P2P_HOLE_PUNCH_INTEGRATION_FAIL: %s" % failure)
	quit(1)
