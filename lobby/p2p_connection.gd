extends RefCounted
class_name P2PConnection

## P2P 连接编排器（Phase 9.1 / 9.2）。
##
## 分层：
##   LobbyManager -> P2PConnection -> RendezvousContract（只交换信息）
##                                 -> ConnectionPath（只描述候选）
##                                 -> P2PHolePunch（UDP probe，仅验证路径）
##                                 -> LobbyNet（唯一持有 ENet、唯一建连）
##
## 职责（严格）：
## 1. 接受 JoinInvite
## 2. 创建一次 join attempt
## 3. 与 rendezvous contract 对接（本阶段是本地 / 注入式，不接公网服务器）
## 4. 得到 remote candidates
## 5. Phase 9.1：直接进入 DIRECT_CONNECTING（ENet 直连）
##    Phase 9.2：进入 DIRECT_PROBING（UDP hole punch）→ DIRECT_PATH_ESTABLISHED → DIRECT_ENET_CONNECTING
## 6. 调用已有 LobbyNet 的「单 peer 建连能力」
## 7. 等待 connected / failed / timeout
## 8. 控制 attempt generation
## 9. 连接成功后进入 HANDSHAKING / CONNECTED
##
## **明确不做**：STUN / TURN / UPnP / Relay（Phase 9.3）。
## 本对象**不创建 ENet peer**，也不持有 MultiplayerPeer —— 建连只经注入的 transport。

## 状态推进（UI / 日志只读，不直接改）。
signal state_changed(from: int, to: int, event: int)
## 整个 join 流程终结（成功或失败）。
signal finished(success: bool, reason: String)
## 诊断：即将尝试的直连候选（Phase 9.1 兼容）。
signal direct_attempt_started(attempt: ConnectAttempt)
## Hole punch 诊断。
signal direct_probe_started(local_candidate: Dictionary, remote_candidate: Dictionary)
signal direct_path_established(rtt_ms: int, validated_candidate: Dictionary)
signal direct_path_failed(reason: String)

var _state: P2PConnectionState = null
var _session: RendezvousContract.SessionState = null
var _identity: RendezvousContract.SessionIdentity = null
var _runner: ConnectAttemptRunner = null
var _hole_punch: P2PHolePunch = null
var _invite: JoinInvite = null
## 注入的传输层（生产 = LobbyManager -> LobbyNet；测试 = 假实现）。
var _connect_fn: Callable = Callable()
var _close_fn: Callable = Callable()
## 可选的真实 rendezvous 客户端（Phase 9.2.1）。为 null = 本地装配模式（9.1 行为）。
var _client: RendezvousClient = null

func _init() -> void:
	_state = P2PConnectionState.new()
	_session = RendezvousContract.SessionState.new()
	_hole_punch = P2PHolePunch.new()
	_hole_punch.state_changed.connect(func(from: int, to: int) -> void:
		## Hole punch 内部状态变化不直接映射到 P2PConnectionState，
		## 由显式 notify 方法驱动主状态机。
		pass
	)
	_hole_punch.path_established.connect(_on_hole_punch_path_established)
	_hole_punch.path_failed.connect(_on_hole_punch_path_failed)
	_hole_punch.timeout.connect(_on_hole_punch_timeout)
	_state.state_changed.connect(func(from: int, to: int, event: int) -> void:
		state_changed.emit(from, to, event)
	)

# ---- 查询 ----

func get_state() -> P2PConnectionState:
	return _state

func get_state_value() -> int:
	return int(_state.get_state())

func get_session() -> RendezvousContract.SessionState:
	return _session

func current_attempt() -> ConnectAttempt:
	return _runner.current_attempt() if _runner != null else null

## 连接已建立（握手也过了）。
## 不能叫 is_connected()：Object 已有同名方法（信号连接查询），重名会导致静态解析失败。
func is_connection_established() -> bool:
	return _state.is_connection_established()

## 状态机是否处于终态。
func is_terminal() -> bool:
	return _state.is_terminal()

# ---- 生命周期 ----

## 注入传输层。connect_fn(address, port, ticket) -> bool（true = 已发起，**不等于连上**）。
func bind_transport(connect_fn: Callable, close_fn: Callable) -> void:
	_connect_fn = connect_fn
	_close_fn = close_fn

## 收到对端候选（9.2.1 起由 RendezvousClient 的真实回包驱动；仍可本地直接喂入）。
func apply_remote_candidates(candidates: Array, remote_nonce: String = "") -> bool:
	if not _state.transition(P2PConnectionState.Event.CANDIDATES_RECEIVED):
		return false
	_session.remote_candidates.assign(candidates)
	_session.remote_nonce = remote_nonce
	_state.set_remote_candidate_count(_session.remote_candidates.size())
	return true

# ---- 真实 rendezvous（Phase 9.2.1）----

## 绑定一个真实 rendezvous 客户端。绑定后 begin() 会走公网注册流程，
## 状态由 REGISTERED / CANDIDATES 回包驱动，而不是立即完成。
func bind_rendezvous(client: RendezvousClient) -> void:
	if _client == client:
		return
	_unbind_rendezvous()
	_client = client
	if _client == null:
		return
	_client.registered.connect(_on_rendezvous_registered)
	_client.peer_ready.connect(_on_rendezvous_peer_ready)
	_client.candidates_received.connect(_on_rendezvous_candidates)
	_client.server_error.connect(_on_rendezvous_error)
	_client.timed_out.connect(_on_rendezvous_timeout)

func _unbind_rendezvous() -> void:
	if _client == null:
		return
	if _client.registered.is_connected(_on_rendezvous_registered):
		_client.registered.disconnect(_on_rendezvous_registered)
	if _client.peer_ready.is_connected(_on_rendezvous_peer_ready):
		_client.peer_ready.disconnect(_on_rendezvous_peer_ready)
	if _client.candidates_received.is_connected(_on_rendezvous_candidates):
		_client.candidates_received.disconnect(_on_rendezvous_candidates)
	if _client.server_error.is_connected(_on_rendezvous_error):
		_client.server_error.disconnect(_on_rendezvous_error)
	if _client.timed_out.is_connected(_on_rendezvous_timeout):
		_client.timed_out.disconnect(_on_rendezvous_timeout)
	_client = null

func get_rendezvous_client() -> RendezvousClient:
	return _client

## 是否使用真实 rendezvous（false = 9.1 的本地装配模式）。
func uses_rendezvous() -> bool:
	return _client != null

## 开始一次 P2P join。
## - 未 bind rendezvous：本地装配模式（9.1 行为，注册立即完成）。
## - 已 bind rendezvous：真实注册，等 REGISTERED / CANDIDATES 回包驱动状态。
func begin(invite: JoinInvite, rendezvous_host: String = "", rendezvous_port: int = RendezvousClient.DEFAULT_PORT) -> bool:
	if invite == null or not invite.is_valid():
		return false
	if not _connect_fn.is_valid():
		return false
	if not _state.transition(P2PConnectionState.Event.BEGIN_RENDEZVOUS):
		return false
	_invite = invite
	_identity = RendezvousContract.make_identity(
		invite.room_id,
		invite.token,
		GameLaunch.NET_PROTOCOL,
		RendezvousContract.Role.GUEST
	)
	_session.local_nonce = _identity.nonce
	_session.local_candidates = RendezvousContract.candidates_from_invite(invite)
	_state.set_local_candidate_count(_session.local_candidates.size())
	## 真实 rendezvous：把注册发出去，等回包。**绝不**在这里假装已注册。
	if _client != null and not rendezvous_host.strip_edges().is_empty():
		if not _client.begin(rendezvous_host, rendezvous_port, _identity, _session.local_candidates):
			_finish(false, "rendezvous_begin_failed")
			return false
		return true
	## 本地装配模式（9.1）：注册立即完成。
	if not _state.transition(P2PConnectionState.Event.RENDEZVOUS_REGISTERED):
		return false
	return true

func _on_rendezvous_registered(_session_id: String, observed_address: String, observed_port: int) -> void:
	## 记录**服务端观测到的**本端端点。绝不自己填。
	_session.local_observed_address = observed_address
	_session.local_observed_port = observed_port
	_state.transition(P2PConnectionState.Event.RENDEZVOUS_REGISTERED)

func _on_rendezvous_peer_ready(_remote_nonce: String, _remote_role: int) -> void:
	## 对端已就绪，但候选可能还没到 —— 状态不前进，等 CANDIDATES。
	pass

func _on_rendezvous_candidates(
	candidates: Array,
	remote_nonce: String,
	_remote_role: int
) -> void:
	## 真实候选取代本地假设：只有服务端交换来的才是「远端候选」。
	_session.remote_candidates.clear()
	for candidate: RendezvousContract.Candidate in candidates:
		_session.remote_candidates.append(candidate)
	_session.remote_nonce = remote_nonce
	## 对端 observed endpoint 来自服务端观测，从 client 的 session 取回。
	## （信号只带候选，observed 是服务端权威数据，不经信号传递以免被伪造。）
	if _client != null and _client.get_session() != null:
		var remote_session: RendezvousContract.SessionState = _client.get_session()
		_session.remote_observed_address = remote_session.remote_observed_address
		_session.remote_observed_port = remote_session.remote_observed_port
	_state.set_remote_candidate_count(_session.remote_candidates.size())
	_state.transition(P2PConnectionState.Event.CANDIDATES_RECEIVED)

func _on_rendezvous_error(error_code: int, detail: String) -> void:
	## ticket / 协议类错误是终态；其它按直连失败处理，由上层决定是否换候选。
	match error_code:
		RendezvousContract.ErrorCode.BAD_TICKET:
			_state.transition(P2PConnectionState.Event.TICKET_REJECTED)
			_finish(false, "ticket_rejected")
		RendezvousContract.ErrorCode.BAD_PROTOCOL:
			_state.transition(P2PConnectionState.Event.VERSION_MISMATCH)
			_finish(false, "version_mismatch")
		RendezvousContract.ErrorCode.TIMEOUT:
			_state.transition(P2PConnectionState.Event.TIMEOUT)
			_finish(false, "rendezvous_timeout")
		_:
			_finish(false, "rendezvous_error:%d %s" % [error_code, detail])

func _on_rendezvous_timeout(reason: String) -> void:
	if not _state.is_terminal():
		_state.transition(P2PConnectionState.Event.TIMEOUT)
	_finish(false, reason)

## 推进 rendezvous 轮询与超时。由上层每帧驱动。
func poll_rendezvous(delta_sec: float) -> void:
	if _client != null:
		_client.poll()
		_client.tick(delta_sec)

# ---- Hole Punch 回调（内部）----

func _on_hole_punch_path_established(rtt_ms: int, validated_candidate: Dictionary) -> void:
	_state.transition(P2PConnectionState.Event.DIRECT_PATH_OK)
	direct_path_established.emit(rtt_ms, validated_candidate)

func _on_hole_punch_path_failed(reason: String) -> void:
	_state.transition(P2PConnectionState.Event.DIRECT_PATH_FAILED)
	direct_path_failed.emit(reason)

func _on_hole_punch_timeout() -> void:
	_state.transition(P2PConnectionState.Event.TIMEOUT)
	_finish(false, "hole_punch_timeout")

# ---- Hole Punch 公共 API ----

## 开始 UDP hole punch（Phase 9.2）。
## 从 CANDIDATES_RECEIVED 状态调用。
## 使用 rendezvous 交换的 candidates + observed endpoint。
func begin_direct_probing(bind_port: int = 0) -> bool:
	if not _state.transition(P2PConnectionState.Event.BEGIN_DIRECT_PROBING):
		return false
	## 准备本端候选：invite 的 local candidates + observed endpoint
	var local_candidates: Array = _session.local_candidates.duplicate()
	## 远端候选：rendezvous 交换来的 remote candidates（已含 observed）
	var remote_candidates: Array = _session.remote_candidates.duplicate()
	if local_candidates.is_empty() or remote_candidates.is_empty():
		_state.transition(P2PConnectionState.Event.DIRECT_PATH_FAILED)
		_finish(false, "no_candidates_for_probing")
		return false
	## 本端 role：Guest 发起 join，所以是 GUEST；Host 侧由 LobbyManager 调用时传 HOST
	var local_role: int = P2PUDPProbe.Role.GUEST
	if _identity != null and _identity.role == RendezvousContract.Role.HOST:
		local_role = P2PUDPProbe.Role.HOST
	## 启动 hole punch
	var ok: bool = _hole_punch.begin(
		_session.rendezvous_id,
		_session.local_nonce,
		_session.remote_nonce,
		local_role,
		local_candidates,
		remote_candidates,
		bind_port
	)
	if not ok:
		_state.transition(P2PConnectionState.Event.DIRECT_PATH_FAILED)
		_finish(false, "hole_punch_begin_failed")
		return false
	return true

## Hole punch 成功后，在 validated path 上发起 ENet 直连。
## 从 DIRECT_PATH_ESTABLISHED 状态调用。
func begin_direct_enet() -> bool:
	if not _state.transition(P2PConnectionState.Event.BEGIN_DIRECT_ENET):
		return false
	## 从 validated candidate 取 remote address/port
	var validated: Dictionary = _hole_punch.get_validated_candidate()
	if validated.is_empty():
		_state.transition(P2PConnectionState.Event.DIRECT_ENET_FAILED)
		_finish(false, "no_validated_candidate")
		return false
	var remote: Dictionary = validated.remote
	var address: String = remote.address
	var port: int = remote.port
	if address.is_empty() or port < 1:
		_state.transition(P2PConnectionState.Event.DIRECT_ENET_FAILED)
		_finish(false, "invalid_validated_candidate")
		return false
	## 关闭 probe socket（hole punch 已完成）
	_hole_punch.cancel()
	## 复用现有 ConnectAttemptRunner 逻辑，但只试这一个 validated candidate
	var plan: ConnectionPath = ConnectionPath.new()
	var candidate: ConnectionPath.Candidate = ConnectionPath.Candidate.new()
	candidate.path = LobbyPlayer.Path.WAN_IPV4
	candidate.address = address
	candidate.port = port
	plan._candidates.append(candidate)
	_runner = ConnectAttemptRunner.new()
	_runner.candidate_started.connect(_on_candidate_started)
	_runner.attempt_finished.connect(_on_attempt_finished)
	_runner.exhausted.connect(_on_runner_exhausted)
	_runner.begin(plan, _ticket(), _connect_fn, _close_fn)
	return true

## ENet connected_to_server 回调（在 validated path 上）。
func notify_direct_enet_connected() -> void:
	if _runner != null:
		_runner.notify_transport_connected(_runner.current_attempt_id())
	_state.transition(P2PConnectionState.Event.DIRECT_ENET_CONNECTED)

## ENet connection_failed 回调（在 validated path 上）。
func notify_direct_enet_failed(why: String = "refused") -> void:
	if _runner != null:
		_runner.notify_connection_failed(_runner.current_attempt_id(), why)
	_state.transition(P2PConnectionState.Event.DIRECT_ENET_FAILED)

## 进入直连阶段：按候选顺序串行尝试（复用 ConnectionPath 的顺序语义）。
func begin_direct() -> bool:
	if not _state.transition(P2PConnectionState.Event.BEGIN_DIRECT_ATTEMPT):
		return false
	var plan: ConnectionPath = ConnectionPath.new()
	for candidate: RendezvousContract.Candidate in _session.remote_candidates:
		if not candidate.is_usable():
			continue
		var converted: ConnectionPath.Candidate = ConnectionPath.Candidate.new()
		converted.path = candidate.path
		converted.address = candidate.address
		converted.port = candidate.port
		plan._candidates.append(converted)
	plan._sort_by_default_order()
	if plan.is_empty():
		_state.transition(P2PConnectionState.Event.DIRECT_FAILED)
		_finish(false, "no_usable_candidates")
		return false
	_runner = ConnectAttemptRunner.new()
	_runner.candidate_started.connect(_on_candidate_started)
	_runner.attempt_finished.connect(_on_attempt_finished)
	_runner.exhausted.connect(_on_runner_exhausted)
	_runner.begin(plan, _ticket(), _connect_fn, _close_fn)
	return true

## 传输层连上（connected_to_server）：进入 HANDSHAKING，等握手结果。
func notify_transport_connected() -> void:
	if _runner != null:
		_runner.notify_transport_connected(_runner.current_attempt_id())
	_state.transition(P2PConnectionState.Event.DIRECT_CONNECTED)

## 握手通过：真正的 CONNECTED。
func notify_handshake_ok() -> void:
	if _runner != null:
		_runner.notify_handshake_ok(_runner.current_attempt_id())
	_state.transition(P2PConnectionState.Event.HANDSHAKE_OK)
	_finish(true, "connected")

## 协议不符：VERSION_MISMATCH 终态，不做普通重试。
func notify_version_mismatch() -> void:
	if _runner != null:
		_runner.notify_version_mismatch(_runner.current_attempt_id(), "protocol_mismatch")
	_state.transition(P2PConnectionState.Event.VERSION_MISMATCH)
	_finish(false, "version_mismatch")

## ticket 被拒：TICKET_REJECTED 终态，不做普通重试。
func notify_ticket_rejected() -> void:
	if _runner != null:
		_runner.notify_ticket_rejected(_runner.current_attempt_id(), "ticket_rejected")
	_state.transition(P2PConnectionState.Event.TICKET_REJECTED)
	_finish(false, "ticket_rejected")

## 传输层失败（connection_failed）：换下一个候选，由 runner 决定是否还有候选。
func notify_connection_failed(why: String = "refused") -> void:
	if _runner == null:
		_finish(false, why)
		return
	_runner.notify_connection_failed(_runner.current_attempt_id(), why)

## 推进超时。四级超时分别生效（见 P2PConnectionState 常量）。
func tick(delta_sec: float) -> void:
	if _runner != null:
		_runner.tick(delta_sec)
	if _hole_punch != null and _hole_punch.is_active():
		_hole_punch.tick(int(delta_sec * 1000))

## 取消 / 重置：保证不留 active peer。
func cancel() -> void:
	if _runner != null:
		_runner.cancel()
	if _hole_punch != null:
		_hole_punch.cancel()
	## 取消也要关掉 rendezvous socket，不留资源。
	if _client != null:
		_client.close()
	_state.transition(P2PConnectionState.Event.CANCEL)
	_finish(false, "cancelled")

func reset() -> void:
	if _runner != null:
		_runner.cancel()
	_runner = null
	if _hole_punch != null:
		_hole_punch.reset()
	if _client != null:
		_client.reset()
	_invite = null
	_identity = null
	_session = RendezvousContract.SessionState.new()
	_state.reset()

# ---- 内部 ----

func _ticket() -> String:
	return _identity.ticket if _identity != null else ""

func _on_candidate_started(attempt: ConnectAttempt) -> void:
	direct_attempt_started.emit(attempt)

func _on_attempt_finished(attempt: ConnectAttempt) -> void:
	## 可重试失败不在此终结：runner 会自动换下一个候选。
	if attempt.is_success():
		_state.transition(P2PConnectionState.Event.HANDSHAKE_OK)
		_finish(true, "connected")
		return
	if attempt.outcome == ConnectAttempt.Outcome.VERSION_MISMATCH:
		_state.transition(P2PConnectionState.Event.VERSION_MISMATCH)
		_finish(false, "version_mismatch")
		return
	if attempt.outcome == ConnectAttempt.Outcome.TICKET_REJECTED:
		_state.transition(P2PConnectionState.Event.TICKET_REJECTED)
		_finish(false, "ticket_rejected")
		return
	if attempt.is_retryable():
		## 让状态机知道这次直连失败（DIRECT_CONNECTING -> DIRECT_CONNECTING）。
		_state.transition(P2PConnectionState.Event.DIRECT_FAILED)

func _on_runner_exhausted(attempt: ConnectAttempt, reason: String) -> void:
	if attempt != null and attempt.is_success():
		return
	## 所有候选都试完 / 总超时：明确进入 TIMEOUT 或 FAILED。
	if reason == "overall_timeout" or reason == "connect_timeout":
		_state.transition(P2PConnectionState.Event.TIMEOUT)
	else:
		_state.transition(P2PConnectionState.Event.DIRECT_FAILED)
		if not _state.is_terminal():
			_state.transition(P2PConnectionState.Event.TIMEOUT)
	_finish(false, reason)

func _finish(success: bool, reason: String) -> void:
	## 失败收尾一定不留 peer。
	if not success and _close_fn.is_valid():
		_close_fn.call()
	finished.emit(success, reason)
