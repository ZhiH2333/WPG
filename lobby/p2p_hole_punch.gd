extends RefCounted
class_name P2PHolePunch

## UDP Hole Punching 编排器（Phase 9.2.2 R2）。
##
## 职责：
## - 进入 DIRECT_PROBING 状态
## - 使用（或自建）UDP socket
## - 收集 local candidates（含 observed endpoint）
## - **同时**探测多个 candidate pair（不是一个一个串行）
## - 每个 active pair 独立拥有 probe_id / 重试 / 超时状态
## - 验证双向可达（同时收到对方 probe 且我方 probe 收到匹配 ACK）
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
##
## ---- 端点语义（Phase 9.2.2 R2 明确区分）----
##   local_bound      : 本端 UDP socket 实际绑定的端口（get_local_bound_endpoint）
##   local_observed   : 服务端观测到的本端公网端点（来自 local candidates 的 observed 字段）
##   remote_advertised: 对端自报的地址端口（可能是私网，可能不可达）
##   remote_observed  : 服务端观测到的对端公网端点（**打洞的目标地址**）
##   validated        : 真正收到匹配 ACK 的那个源地址端口（get_validated_endpoint）
##
## 探测目标优先级：remote_observed > remote_advertised。
## 只有「目标地址 == 实际回 ACK 的源地址端口」才会被接受，因此
## validated endpoint 必然等于成功 pair 的探测目标（测试里有断言）。
##
## ---- 所有权语义（Phase 9.2.2 R2）----
##   - 未传 shared_udp：本对象自建并**拥有** socket，release() 会 close()。
##   - 传入 shared_udp：本对象只**引用**，release()/cancel()/timeout 绝不 close()；
##     真正的 owner 是 P2PConnection。可用 owns_socket() 查询。

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
## true = 本对象自建并拥有 socket；false = 外部共享，绝不 close()。
var _owns_socket: bool = false
var _local_candidates: Array[NetworkCandidates.Candidate] = []
var _remote_candidates: Array[NetworkCandidates.Candidate] = []
## 每个 pair 独立维护：target / probe 计数 / pending probe_ids / ACK / RTT / validated 源。
var _candidate_pairs: Array[Dictionary] = []
var _elapsed_ms: int = 0
var _total_probes_sent: int = 0
var _bidirectional_confirmed: bool = false
var _validated_rtt_ms: int = 0
var _validated_candidate: Dictionary = {}
var _validated_source_address: String = ""
var _validated_source_port: int = 0
var _validated_pair_index: int = -1
var _generation: int = 0
var _finished: bool = false
## probe_id 单调递增（随机初值，跨 reset 不复用），从根上防「旧 ACK 撞上新 probe」。
var _probe_id_counter: int = 0

func _init() -> void:
	_socket = P2PUDPProbe.ProbeSocket.new()
	## 随机初值：同进程内多次 begin 的 probe_id 不重叠，旧 ACK 无法误匹配新 probe。
	_probe_id_counter = randi() & 0x3FFFFFFF

func get_state() -> int:
	return _state

func get_generation() -> int:
	return _generation

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

## 本对象是否拥有底层 UDP socket。
func owns_socket() -> bool:
	return _owns_socket

func get_socket() -> PacketPeerUDP:
	return _socket.get_udp() if _socket != null else null

## 已确认可用的双向路径。`remote` 一定是**真正回 ACK 的**端点。
func get_validated_candidate() -> Dictionary:
	return _validated_candidate.duplicate(true)

## 实际验证成功的远端点（源地址端口）。
func get_validated_endpoint() -> Dictionary:
	if _validated_source_address.is_empty() or _validated_source_port <= 0:
		return {}
	return {"address": _validated_source_address, "port": _validated_source_port}

## 本端 socket 实际绑定的端口。
func get_local_bound_endpoint() -> Dictionary:
	if _socket == null or not _socket.is_open():
		return {}
	return {"address": "", "port": _socket.get_local_port()}

## 本端 observed endpoint（由传入的 local candidates 携带；没有则空）。
func get_local_observed_endpoint() -> Dictionary:
	for candidate: NetworkCandidates.Candidate in _local_candidates:
		if candidate.has_observed_endpoint():
			return {"address": candidate.observed_address, "port": candidate.observed_port}
	return {}

## 对端自报候选端点（可能不可达）。
func get_remote_advertised_endpoints() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for candidate: NetworkCandidates.Candidate in _remote_candidates:
		out.append({"address": candidate.address, "port": candidate.port})
	return out

## 对端 observed endpoint（服务端观测）。
func get_remote_observed_endpoint() -> Dictionary:
	for candidate: NetworkCandidates.Candidate in _remote_candidates:
		if candidate.has_observed_endpoint():
			return {"address": candidate.observed_address, "port": candidate.observed_port}
	return {}

## 当前仍在探测的 pair 数量（用于 simultaneous probing 断言）。
func get_active_probe_count() -> int:
	var count: int = 0
	for pair: Dictionary in _candidate_pairs:
		if bool(pair.active) and not bool(pair.failed) and not bool(pair.ack_received):
			count += 1
	return count

## 诊断快照（测试用；不暴露内部引用）。
func debug_pair_states() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i: int in _candidate_pairs.size():
		var pair: Dictionary = _candidate_pairs[i]
		out.append({
			"index": i,
			"generation": int(pair.generation),
			"active": bool(pair.active),
			"failed": bool(pair.failed),
			"probes_sent": int(pair.probes_sent),
			"ack_received": bool(pair.ack_received),
			"rtt_ms": int(pair.rtt_ms),
			"target_address": str(pair.target_address),
			"target_port": int(pair.target_port),
			"advertised_address": str(pair.advertised_address),
			"advertised_port": int(pair.advertised_port),
			"observed_address": str(pair.observed_address),
			"observed_port": int(pair.observed_port),
			"pending_probe_ids": pair.pending_probe_ids.keys(),
		})
	return out

## 开始打洞。
##
## 参数：
##   session_id         - rendezvous 分配的会话 ID
##   local_nonce        - 本端 nonce
##   remote_nonce       - 对端 nonce（从 rendezvous CANDIDATES 消息获得）
##   local_role         - HOST=0 / GUEST=1（本端角色）
##   local_candidates   - 本端候选（含 observed endpoint）
##   remote_candidates  - 对端候选（含 observed endpoint）
##   bind_port          - 本端 UDP 绑定端口（0 = 自动分配；仅在自建 socket 时生效）
##   shared_udp         - 可选：外部共享的 PacketPeerUDP（9.2.2 共享 transport 模式）。
##                        如果提供，将复用该 socket 而非自建，**不拥有**其生命周期。
func begin(
	session_id: String,
	local_nonce: String,
	remote_nonce: String,
	local_role: int,
	local_candidates: Array,
	remote_candidates: Array,
	bind_port: int = 0,
	shared_udp: PacketPeerUDP = null
) -> bool:
	if _state != State.IDLE:
		return false
	if session_id.is_empty() or local_nonce.is_empty() or remote_nonce.is_empty():
		_transition(State.PATH_FAILED)
		path_failed.emit("invalid_parameters")
		_finished = true
		return false
	if local_candidates.is_empty() or remote_candidates.is_empty():
		_transition(State.PATH_FAILED)
		path_failed.emit("empty_candidates")
		_finished = true
		return false

	_session_id = session_id
	_local_nonce = local_nonce
	_remote_nonce = remote_nonce
	_local_role = local_role
	_expected_remote_role = P2PUDPProbe.Role.HOST if local_role == P2PUDPProbe.Role.GUEST else P2PUDPProbe.Role.GUEST

	## 收集并分类候选。
	_local_candidates = _collect_and_classify_local(local_candidates)
	_remote_candidates = _collect_and_classify_remote(remote_candidates)

	## 构建 candidate pairs（同时探测，因此全部保留 active）。
	_candidate_pairs = _build_candidate_pairs()
	if _candidate_pairs.is_empty():
		_transition(State.PATH_FAILED)
		path_failed.emit("no_usable_candidate_pairs")
		_finished = true
		return false

	## Bind UDP：优先使用外部共享 socket，否则自建。
	if shared_udp != null:
		if not _socket.adopt_existing_udp(shared_udp):
			_transition(State.PATH_FAILED)
			path_failed.emit("adopt_shared_udp_failed")
			_finished = true
			return false
		_owns_socket = false
	else:
		if not _socket.bind(bind_port):
			_transition(State.PATH_FAILED)
			path_failed.emit("socket_bind_failed")
			_finished = true
			return false
		_owns_socket = true

	_generation += 1
	_elapsed_ms = 0
	_total_probes_sent = 0
	_bidirectional_confirmed = false
	_validated_rtt_ms = 0
	_validated_candidate = {}
	_validated_source_address = ""
	_validated_source_port = 0
	_validated_pair_index = -1
	_finished = false

	_transition(State.PROBING)
	return true

## 每帧驱动（由上层 tick 调用）。
func tick(delta_ms: int) -> void:
	if _state != State.PROBING or _finished:
		return
	_elapsed_ms += maxi(delta_ms, 0)

	## 总超时
	if _elapsed_ms >= MAX_PROBE_DURATION_MS:
		_finish(Result.TIMEOUT, "probe_timeout")
		return

	## 接收处理（对方 probe / 我方 ACK）
	_process_receive()
	if _bidirectional_confirmed:
		_finish(Result.SUCCESS, "bidirectional_confirmed")
		return

	## 同时发送探测（所有 active pair 并行推进）
	_maybe_send_probes()
	if _bidirectional_confirmed:
		_finish(Result.SUCCESS, "bidirectional_confirmed")
		return

	## 所有 pair 都耗尽 -> 失败
	if _all_pairs_exhausted():
		_finish(Result.FAILED, "all_candidates_exhausted")

func _all_pairs_exhausted() -> bool:
	if _candidate_pairs.is_empty():
		return true
	for pair: Dictionary in _candidate_pairs:
		if bool(pair.active) and not bool(pair.failed):
			return false
	return true

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
		## 校验 session_id + nonce + expected role（角色/会话不符一律丢弃）。
		if not P2PUDPProbe.validate_expectation(decoded, _session_id, _remote_nonce, _expected_remote_role):
			continue
		## **源地址/端口必须匹配某个当前 pair 的探测目标**，否则丢弃。
		var pair_index: int = _find_pair_by_source(src_addr, src_port)
		if pair_index < 0:
			continue
		var pair: Dictionary = _candidate_pairs[pair_index]
		if int(pair.generation) != _generation:
			continue
		if decoded.is_probe():
			## 收到对端 probe -> 回 ACK（必须 echo probe_id）。
			var now_ms: int = Time.get_ticks_msec()
			var ack: PackedByteArray = P2PUDPProbe.encode_ack(
				_session_id, _local_nonce, _local_role, now_ms, decoded.timestamp_ms, decoded.probe_id
			)
			_socket.send_to(src_addr, src_port, ack)
		elif decoded.is_ack():
			## 已经确认过路径：之后的 ACK 不再改变最终状态。
			if _bidirectional_confirmed or _finished:
				continue
			if bool(pair.failed) or bool(pair.ack_received):
				continue
			## 严格 probe_id correlation：只接受本 pair 真正挂起的 probe 的 ACK。
			if not pair.pending_probe_ids.has(decoded.probe_id):
				## 旧 attempt 的 ACK / 伪造包 / 已过期的 probe：忽略。
				continue
			var now_ms: int = Time.get_ticks_msec()
			var rtt: int = P2PUDPProbe.calculate_rtt(now_ms, decoded.original_timestamp_ms)
			pair.ack_received = true
			pair.rtt_ms = rtt
			pair.validated_source_address = src_addr
			pair.validated_source_port = src_port
			if int(pair.probes_sent) > 0:
				_bidirectional_confirmed = true
				_validated_rtt_ms = rtt
				_validated_source_address = src_addr
				_validated_source_port = src_port
				_validated_pair_index = pair_index
				_validated_candidate = _build_validated_candidate(pair, src_addr, src_port, rtt)
				## 其他 active probe 必须安全停下，且不能再改变最终状态。
				_stop_other_pairs(pair_index)

func _maybe_send_probes() -> void:
	var now_ms: int = Time.get_ticks_msec()
	for pair: Dictionary in _candidate_pairs:
		if not bool(pair.active) or bool(pair.failed) or bool(pair.ack_received):
			continue
		if int(pair.generation) != _generation:
			continue
		if int(pair.probes_sent) >= MAX_PROBES_PER_CANDIDATE:
			pair.failed = true
			pair.active = false
			pair.pending_probe_ids.clear()
			continue
		## 每个 pair 独立节流（互不阻塞）。
		var first_probe: bool = int(pair.probes_sent) == 0
		if not first_probe and (now_ms - int(pair.last_probe_ms)) < PROBE_INTERVAL_MS:
			continue
		_probe_id_counter += 1
		var probe_id: int = _probe_id_counter
		var probe: PackedByteArray = P2PUDPProbe.encode_probe(
			_session_id, _local_nonce, _local_role, now_ms, probe_id
		)
		if _socket.send_to(str(pair.target_address), int(pair.target_port), probe):
			pair.probes_sent = int(pair.probes_sent) + 1
			pair.last_probe_ms = now_ms
			## 只保留最近一段 pending id，避免无限增长。
			pair.pending_probe_ids[probe_id] = now_ms
			if pair.pending_probe_ids.size() > MAX_PROBES_PER_CANDIDATE * 2:
				_trim_pending(pair)
			_total_probes_sent += 1

func _trim_pending(pair: Dictionary) -> void:
	var ids: Array = pair.pending_probe_ids.keys()
	ids.sort()
	var drop: int = ids.size() - MAX_PROBES_PER_CANDIDATE
	for i: int in drop:
		pair.pending_probe_ids.erase(ids[i])

## 按「实际源地址端口 == pair 探测目标」匹配。
func _find_pair_by_source(src_addr: String, src_port: int) -> int:
	for i: int in _candidate_pairs.size():
		var pair: Dictionary = _candidate_pairs[i]
		if str(pair.target_address) == src_addr and int(pair.target_port) == src_port:
			return i
	return -1

## 成功后停掉其它 probe：清空它们的 pending probe_ids，迟到的 ACK 因此无法匹配。
func _stop_other_pairs(keep_index: int) -> void:
	for i: int in _candidate_pairs.size():
		if i == keep_index:
			continue
		var pair: Dictionary = _candidate_pairs[i]
		pair.active = false
		pair.pending_probe_ids.clear()

## 停掉所有 probe（cancel / finish 收尾用）：清空 pending，迟到的 ACK 无法匹配。
func _deactivate_all_pairs() -> void:
	for pair: Dictionary in _candidate_pairs:
		pair.active = false
		pair.pending_probe_ids.clear()

func _build_validated_candidate(pair: Dictionary, src_addr: String, src_port: int, rtt: int) -> Dictionary:
	var validated_remote: Dictionary = {
		"candidate_type": pair.remote.candidate_type,
		"address": src_addr,
		"port": src_port,
		"observed_address": src_addr,
		"observed_port": src_port,
	}
	return {
		"local": _copy_candidate(pair.local),
		## legacy key `remote`：一定是真正回 ACK 的 validated endpoint（Direct ENet 用）。
		"remote": validated_remote,
		"rtt_ms": rtt,
		"remote_advertised": {
			"address": str(pair.advertised_address),
			"port": int(pair.advertised_port),
		},
		"remote_observed": {
			"address": str(pair.observed_address),
			"port": int(pair.observed_port),
		},
		"remote_validated": {"address": src_addr, "port": src_port},
		"probe_target": {
			"address": str(pair.target_address),
			"port": int(pair.target_port),
		},
	}

## NetworkCandidates.Candidate 是 RefCounted，没有 duplicate()；手动复制。
func _copy_candidate(source: NetworkCandidates.Candidate) -> NetworkCandidates.Candidate:
	var copy: NetworkCandidates.Candidate = NetworkCandidates.Candidate.new()
	copy.candidate_type = source.candidate_type
	copy.address = source.address
	copy.port = source.port
	copy.observed_address = source.observed_address
	copy.observed_port = source.observed_port
	copy.nonce = source.nonce
	return copy

## 收集本地候选：去重 + 分类 + 保留 observed endpoint。
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
	out = NetworkCandidates.deduplicate(out)
	out = NetworkCandidates.filter_usable(out)
	NetworkCandidates._sort_by_priority(out)
	return out

## 收集远端候选：同样分类，保留 observed（打洞目标来源）。
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

## 构建 candidate pairs：local x remote 的笛卡尔积，按优先级排序，限制数量。
## **全部同时 active** —— 不再用 _current_pair_index 串行试。
func _build_candidate_pairs() -> Array[Dictionary]:
	var pairs: Array[Dictionary] = []
	for local: NetworkCandidates.Candidate in _local_candidates:
		for remote: NetworkCandidates.Candidate in _remote_candidates:
			var observed: bool = remote.has_observed_endpoint()
			var pair: Dictionary = {
				"local": local,
				"remote": remote,
				"advertised_address": remote.address,
				"advertised_port": remote.port,
				"observed_address": remote.observed_address if observed else remote.address,
				"observed_port": remote.observed_port if observed else remote.port,
				## 打洞目标：优先 observed（服务端观测），否则对端自报地址。
				"target_address": remote.observed_address if observed else remote.address,
				"target_port": remote.observed_port if observed else remote.port,
				"generation": _generation + 1,
				"active": true,
				"failed": false,
				"probes_sent": 0,
				"ack_received": false,
				"rtt_ms": 0,
				"last_probe_ms": 0,
				"pending_probe_ids": {},
				"validated_source_address": "",
				"validated_source_port": 0,
			}
			pairs.append(pair)
			if pairs.size() >= MAX_CANDIDATE_PAIRS:
				break
		if pairs.size() >= MAX_CANDIDATE_PAIRS:
			break
	return pairs

func _transition(new_state: int) -> void:
	var from: int = _state
	_state = new_state
	state_changed.emit(from, _state)

## 只断开引用；是否真正 close() 由 _socket 的所有权决定。
func _release_socket() -> void:
	if _socket != null:
		_socket.release()

func _finish(result: int, reason: String) -> void:
	if _finished:
		return
	_finished = true
	_deactivate_all_pairs()
	_release_socket()
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

## 取消：停掉所有 probe，安全释放（共享 socket 不关），但不派发 path_failed ——
## cancel 是显式调用方的动作，由调用方决定如何终结，避免误触发上层失败回调。
func cancel() -> void:
	if _finished:
		return
	_finished = true
	_deactivate_all_pairs()
	_release_socket()
	if _state == State.PROBING or _state == State.IDLE:
		_transition(State.PATH_FAILED)

func reset() -> void:
	_release_socket()
	_state = State.IDLE
	_owns_socket = false
	_session_id = ""
	_local_nonce = ""
	_remote_nonce = ""
	_local_candidates.clear()
	_remote_candidates.clear()
	_candidate_pairs.clear()
	_elapsed_ms = 0
	_total_probes_sent = 0
	_bidirectional_confirmed = false
	_validated_rtt_ms = 0
	_validated_candidate = {}
	_validated_source_address = ""
	_validated_source_port = 0
	_validated_pair_index = -1
	_generation = 0
	_finished = false
	## 注意：_probe_id_counter 不重置，保证 probe_id 单调、旧 ACK 不撞新 probe。
