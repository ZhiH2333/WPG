extends RefCounted
class_name P2PHolePunch

## UDP Hole Punching 编排器（Phase 9.2）。
##
## 职责：
## - 进入 DIRECT_PROBING 状态
## - bind 本地 UDP socket
## - 收集 local candidates（含 observed endpoint）
## - 选择 candidate pairs（按优先级：LAN IPv4 > IPv6 > observed > other）
## - 发送 probe，接收 probe/ack
## - 验证双向可达（BIDIRECTIONAL PROBE SUCCESS）
## - 标记 DIRECT_PATH_ESTABLISHED 或 DIRECT_PATH_FAILED
##
## 严格不做：
## - 创建 ENetMultiplayerPeer
## - 修改 SceneTree.multiplayer
## - 处理 Lobby roster / Ready / Combat
## - Relay / TURN（留接口，Phase 9.3 实现）
##
## 状态流：
##   IDLE -> PROBING -> PATH_ESTABLISHED
##                    -> PATH_FAILED
##                    -> TIMEOUT
##
## 所有超时/尝试次数有界，禁止无限发包。

signal state_changed(from: int, to: int)
signal path_established(rtt_ms: int, validated_candidate: Dictionary)
signal path_failed(reason: String)
signal timeout

enum State {
	IDLE,
	PROBING,
	PATH_ESTABLISHED,
	PATH_FAILED,
	TIMEOUT,
}

enum Result {
	SUCCESS,
	FAILED,
	TIMEOUT,
}

## 探测参数（可按测试调整，但必须有界）。
const PROBE_INTERVAL_MS: int = 120
const MAX_PROBE_DURATION_MS: int = 3500
const MAX_PROBES_PER_CANDIDATE: int = 20
const MAX_CANDIDATE_PAIRS: int = 8

var _state: int = State.IDLE
var _session_id: String = ""
var _local_nonce: String = ""
var _remote_nonce: String = ""
var _local_role: int = P2PUDPProbe.Role.GUEST
var _expected_remote_role: int = P2PUDPProbe.Role.HOST
var _socket: P2PUDPProbe.ProbeSocket = null
var _local_candidates: Array[NetworkCandidates.Candidate] = []
var _remote_candidates: Array[NetworkCandidates.Candidate] = []
var _candidate_pairs: Array[Dictionary] = []  # {local, remote, probes_sent, ack_received, rtt, pending_probe_ids, last_remote_addr, last_remote_port}
var _current_pair_index: int = 0
var _elapsed_ms: int = 0
var _total_probes_sent: int = 0
var _bidirectional_confirmed: bool = false
var _validated_rtt_ms: int = 0
var _validated_candidate: Dictionary = {}
var _generation: int = 0
var _finished: bool = false
var _probe_id_counter: int = 0

func _init() -> void:
	_socket = P2PUDPProbe.ProbeSocket.new()

func get_state() -> int:
	return _state

func is_active() -> bool:
	return _state == State.PROBING

func is_success() -> bool:
	return _state == State.PATH_ESTABLISHED

func is_failed() -> bool:
	return _state == State.PATH_FAILED or _state == State.TIMEOUT

func is_terminal() -> bool:
	return _state == State.PATH_ESTABLISHED or _state == State.PATH_FAILED or _state == State.TIMEOUT

func get_validated_rtt_ms() -> int:
	return _validated_rtt_ms

func get_validated_candidate() -> Dictionary:
	return _validated_candidate.duplicate()

## 开始打洞。
##
## 参数：
##   session_id         - rendezvous 分配的会话 ID
##   local_nonce        - 本端 nonce
##   remote_nonce       - 对端 nonce（从 rendezvous CANDIDATES 消息获得）
##   local_role         - HOST=0 / GUEST=1（本端角色）
##   local_candidates   - 本端候选（含 observed endpoint）
##   remote_candidates  - 对端候选（含 observed endpoint）
##   bind_port          - 本地 UDP 绑定端口（0 = 自动分配）
##   external_udp       - 可选：外部共享的 PacketPeerUDP（9.2.2 共享 transport 模式）。
##                        如果提供，将复用该 socket 而非自建，且不拥有其生命周期。
func begin(
	session_id: String,
	local_nonce: String,
	remote_nonce: String,
	local_role: int,
	local_candidates: Array,
	remote_candidates: Array,
	bind_port: int = 0,
	external_udp: PacketPeerUDP = null
) -> bool:
	if _state != State.IDLE:
		return false
	if session_id.is_empty() or local_nonce.is_empty() or remote_nonce.is_empty():
		_transition(State.PATH_FAILED)
		path_failed.emit("invalid_parameters")
		return false
	if local_candidates.is_empty() or remote_candidates.is_empty():
		_transition(State.PATH_FAILED)
		path_failed.emit("empty_candidates")
		return false

	_session_id = session_id
	_local_nonce = local_nonce
	_remote_nonce = remote_nonce
	_local_role = local_role
	_expected_remote_role = P2PUDPProbe.Role.HOST if local_role == P2PUDPProbe.Role.GUEST else P2PUDPProbe.Role.GUEST

	## 收集并分类本地候选
	_local_candidates = _collect_and_classify_local(local_candidates)
	_remote_candidates = _collect_and_classify_remote(remote_candidates)

	## 构建 candidate pairs（按优先级排序，限制数量）
	_candidate_pairs = _build_candidate_pairs()
	if _candidate_pairs.is_empty():
		_transition(State.PATH_FAILED)
		path_failed.emit("no_usable_candidate_pairs")
		return false

	## Bind UDP socket：优先使用外部共享 socket，否则自建
	if external_udp != null:
		if not _socket.adopt_existing_udp(external_udp):
			_transition(State.PATH_FAILED)
			path_failed.emit("adopt_shared_udp_failed")
			return false
	else:
		if not _socket.bind(bind_port):
			_transition(State.PATH_FAILED)
			path_failed.emit("socket_bind_failed")
			return false

	_generation += 1
	_elapsed_ms = 0
	_total_probes_sent = 0
	_current_pair_index = 0
	_bidirectional_confirmed = false
	_validated_rtt_ms = 0
	_validated_candidate = {}
	_finished = false
	_probe_id_counter = 0

	_transition(State.PROBING)
	return true

## 每帧驱动（由上层 tick 调用）。
func tick(delta_ms: int) -> void:
	if _state != State.PROBING or _finished:
		return
	_elapsed_ms += delta_ms

	## 总超时
	if _elapsed_ms >= MAX_PROBE_DURATION_MS:
		_finish(Result.TIMEOUT, "probe_timeout")
		return

	## 接收处理
	_process_receive()

	## 发送探测（按间隔）
	_maybe_send_probes()

	## 检查当前 candidate pair 是否已确认双向
	if _bidirectional_confirmed:
		_finish(Result.SUCCESS, "bidirectional_confirmed")
		return

	## 当前 pair 耗尽 -> 尝试下一个
	if _current_pair_index < _candidate_pairs.size():
		var current_pair: Dictionary = _candidate_pairs[_current_pair_index]
		if current_pair.probes_sent >= MAX_PROBES_PER_CANDIDATE:
			_current_pair_index += 1
			if _current_pair_index >= _candidate_pairs.size():
				_finish(Result.FAILED, "all_candidates_exhausted")
	else:
		_finish(Result.FAILED, "all_candidates_exhausted")

func _process_receive() -> void:
	while _socket.is_open():
		var received: Array = _socket.receive()
		if received.is_empty():
			break
		var packet: PackedByteArray = received[0]
		var src_addr: String = received[1]
		var src_port: int = received[2]
		if packet.is_empty():
			continue
		var decoded: P2PUDPProbe.Decoded = P2PUDPProbe.decode(packet)
		if not decoded.is_ok():
			continue
		## 校验 session_id + nonce + expected role
		if not P2PUDPProbe.validate_expectation(decoded, _session_id, _remote_nonce, _expected_remote_role):
			continue
		## 找到匹配的 candidate pair（按 source address+port）
		var pair_index: int = _find_pair_by_source(src_addr, src_port)
		if pair_index < 0:
			continue
		var pair: Dictionary = _candidate_pairs[pair_index]
		## 记录实际来源地址（用于回复 ACK）
		pair.last_remote_addr = src_addr
		pair.last_remote_port = src_port
		if decoded.is_probe():
			## 收到对端 probe -> 回 ACK（必须 echo probe_id）
			var now_ms: int = Time.get_ticks_msec()
			var ack: PackedByteArray = P2PUDPProbe.encode_ack(
				_session_id, _local_nonce, _local_role, now_ms, decoded.timestamp_ms, decoded.probe_id
			)
			_socket.send_to(src_addr, src_port, ack)
		elif decoded.is_ack():
			## 收到对端 ACK -> 严格 probe_id correlation 验证
			if not pair.ack_received:
				## 验证 ACK 的 probe_id 是否匹配我们发出的 pending probe
				if decoded.probe_id in pair.pending_probe_ids:
					pair.ack_received = true
					var now_ms: int = Time.get_ticks_msec()
					var rtt: int = P2PUDPProbe.calculate_rtt(now_ms, decoded.original_timestamp_ms)
					pair.rtt_ms = rtt
					## 只有当我们也发过 probe 且对端回了匹配的 ACK，才算双向确认
					if pair.probes_sent > 0:
						_bidirectional_confirmed = true
						_validated_rtt_ms = rtt
						_validated_candidate = {
							"local": pair.local.duplicate(),
							"remote": pair.remote.duplicate(),
							"rtt_ms": rtt,
						}
				else:
					## probe_id 不匹配：可能是旧 attempt 的 ACK 或伪造包，忽略
					pass

func _maybe_send_probes() -> void:
	if _current_pair_index >= _candidate_pairs.size():
		return
	var pair: Dictionary = _candidate_pairs[_current_pair_index]
	var now_ms: int = Time.get_ticks_msec()
	## 简单的发送节流：按 PROBE_INTERVAL_MS 发送
	if _total_probes_sent == 0 or (now_ms - pair.last_probe_ms) >= PROBE_INTERVAL_MS:
		if pair.probes_sent < MAX_PROBES_PER_CANDIDATE:
			_probe_id_counter += 1
			var probe_id: int = _probe_id_counter
			var probe: PackedByteArray = P2PUDPProbe.encode_probe(
				_session_id, _local_nonce, _local_role, now_ms, probe_id
			)
			## 使用 observed endpoint 作为目标（如果可用），否则用候选地址
			var target_addr: String = pair.remote.observed_address if pair.remote.has_observed_endpoint() else pair.remote.address
			var target_port: int = pair.remote.observed_port if pair.remote.has_observed_endpoint() else pair.remote.port
			if _socket.send_to(target_addr, target_port, probe):
				pair.probes_sent += 1
				pair.last_probe_ms = now_ms
				pair.pending_probe_ids.append(probe_id)
				_total_probes_sent += 1

func _find_pair_by_source(src_addr: String, src_port: int) -> int:
	## 使用实际源地址端口匹配 candidate pair
	for i in range(_candidate_pairs.size()):
		var pair: Dictionary = _candidate_pairs[i]
		var target_addr: String = pair.remote.observed_address if pair.remote.has_observed_endpoint() else pair.remote.address
		var target_port: int = pair.remote.observed_port if pair.remote.has_observed_endpoint() else pair.remote.port
		if src_addr == target_addr and src_port == target_port:
			return i
	return -1

## 收集本地候选：去重 + 分类 + 加上 observed endpoint
func _collect_and_classify_local(candidates: Array) -> Array[NetworkCandidates.Candidate]:
	var out: Array[NetworkCandidates.Candidate] = []
	for candidate: RendezvousContract.Candidate in candidates:
		if not candidate.is_usable():
			continue
		var nc: NetworkCandidates.Candidate = NetworkCandidates.Candidate.new()
		nc.candidate_type = _rendezvous_path_to_type(candidate.path)
		nc.address = candidate.address
		nc.port = candidate.port
		if candidate.has_observed_endpoint():
			nc.observed_address = candidate.observed_address
			nc.observed_port = candidate.observed_port
		out.append(nc)
	## 去重
	out = NetworkCandidates.deduplicate(out)
	## 只保留可用
	out = NetworkCandidates.filter_usable(out)
	## 排序
	NetworkCandidates._sort_by_priority(out)
	return out

## 收集远端候选：同样分类，但不加 observed（远端 observed 已在 remote_candidates 里）
func _collect_and_classify_remote(candidates: Array) -> Array[NetworkCandidates.Candidate]:
	var out: Array[NetworkCandidates.Candidate] = []
	for candidate: RendezvousContract.Candidate in candidates:
		if not candidate.is_usable():
			continue
		var nc: NetworkCandidates.Candidate = NetworkCandidates.Candidate.new()
		nc.candidate_type = _rendezvous_path_to_type(candidate.path)
		nc.address = candidate.address
		nc.port = candidate.port
		if candidate.has_observed_endpoint():
			nc.observed_address = candidate.observed_address
			nc.observed_port = candidate.observed_port
		out.append(nc)
	out = NetworkCandidates.deduplicate(out)
	out = NetworkCandidates.filter_usable(out)
	NetworkCandidates._sort_by_priority(out)
	return out

func _rendezvous_path_to_path(path: int) -> int:
	return path

func _rendezvous_path_to_type(path: int) -> int:
	match path:
		LobbyPlayer.Path.LAN_IPV4:
			return NetworkCandidates.CandidateType.LOCAL_PRIVATE
		LobbyPlayer.Path.IPV6:
			return NetworkCandidates.CandidateType.LOCAL_IPV6
		LobbyPlayer.Path.WAN_IPV4:
			return NetworkCandidates.CandidateType.OBSERVED_PUBLIC
		_:
			return NetworkCandidates.CandidateType.OBSERVED_PUBLIC

## 构建 candidate pairs：local x remote 的笛卡尔积，按优先级排序，限制数量
## 每个 pair 明确保存：local/remote endpoint、candidate type、probe 状态、pending probe_ids
func _build_candidate_pairs() -> Array[Dictionary]:
	var pairs: Array[Dictionary] = []
	for local: NetworkCandidates.Candidate in _local_candidates:
		for remote: NetworkCandidates.Candidate in _remote_candidates:
			var pair: Dictionary = {
				"local": local,
				"remote": remote,
				"probes_sent": 0,
				"ack_received": false,
				"rtt_ms": 0,
				"last_probe_ms": 0,
				"pending_probe_ids": [],
				"last_remote_addr": "",
				"last_remote_port": 0,
			}
			pairs.append(pair)
			if pairs.size() >= MAX_CANDIDATE_PAIRS:
				break
		if pairs.size() >= MAX_CANDIDATE_PAIRS:
			break
	## pairs 已按 local/remote 优先级自然排序（因输入已排序）
	return pairs

func _transition(new_state: int) -> void:
	var from: int = _state
	_state = new_state
	state_changed.emit(from, _state)

func _finish(result: int, reason: String) -> void:
	if _finished:
		return
	_finished = true
	_socket.close()
	match result:
		Result.SUCCESS:
			_transition(State.PATH_ESTABLISHED)
			path_established.emit(_validated_rtt_ms, _validated_candidate)
		Result.TIMEOUT:
			_transition(State.TIMEOUT)
			timeout.emit()
		_:
			_transition(State.PATH_FAILED)
			path_failed.emit(reason)

## 取消/重置
func cancel() -> void:
	if _finished:
		return
	_finished = true
	_socket.close()
	_transition(State.PATH_FAILED)
	path_failed.emit("cancelled")

func reset() -> void:
	cancel()
	_state = State.IDLE
	_session_id = ""
	_local_nonce = ""
	_remote_nonce = ""
	_local_candidates.clear()
	_remote_candidates.clear()
	_candidate_pairs.clear()
	_current_pair_index = 0
	_elapsed_ms = 0
	_total_probes_sent = 0
	_bidirectional_confirmed = false
	_validated_rtt_ms = 0
	_validated_candidate = {}
	_generation = 0
	_finished = false
	_probe_id_counter = 0