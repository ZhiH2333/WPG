extends RefCounted
class_name P2PConnection

## P2P 连接编排器（Phase 9.1）。
##
## 分层：
##   LobbyManager -> P2PConnection -> RendezvousContract（只交换信息）
##                                 -> ConnectionPath（只描述候选）
##                                 -> LobbyNet（唯一持有 ENet、唯一建连）
##
## 职责（严格）：
## 1. 接受 JoinInvite
## 2. 创建一次 join attempt
## 3. 与 rendezvous contract 对接（本阶段是本地 / 注入式，不接公网服务器）
## 4. 得到 remote candidates
## 5. 决定进入 DIRECT_CONNECTING
## 6. 调用已有 LobbyNet 的「单 peer 建连能力」
## 7. 等待 connected / failed / timeout
## 8. 控制 attempt generation
## 9. 连接成功后进入 HANDSHAKING / CONNECTED
##
## **明确不做**（Phase 9.1 范围）：STUN / TURN / UPnP / 真公网 NAT hole punching / Relay。
## 直连用的是 ENet 自己 bind 的地址，与 LAN 路径同一条代码路径。
##
## 本对象**不创建 ENet peer**，也不持有 MultiplayerPeer —— 建连只经注入的 transport。

## 状态推进（UI / 日志只读，不直接改）。
signal state_changed(from: int, to: int, event: int)
## 整个 join 流程终结（成功或失败）。
signal finished(success: bool, reason: String)
## 诊断：即将尝试的直连候选。
signal direct_attempt_started(attempt: ConnectAttempt)

var _state: P2PConnectionState = null
var _session: RendezvousContract.SessionState = null
var _identity: RendezvousContract.SessionIdentity = null
var _runner: ConnectAttemptRunner = null
var _invite: JoinInvite = null
## 注入的传输层（生产 = LobbyManager -> LobbyNet；测试 = 假实现）。
var _connect_fn: Callable = Callable()
var _close_fn: Callable = Callable()

func _init() -> void:
	_state = P2PConnectionState.new()
	_session = RendezvousContract.SessionState.new()
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

## 开始一次 P2P join。
## 本阶段 rendezvous 是**本地装配**：候选直接来自 invite（真实的公网交换留到 9.2）。
func begin(invite: JoinInvite) -> bool:
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
	## 本阶段：注册立即完成（没有公网服务可等）。9.2 会由真实往返驱动这两个事件。
	if not _state.transition(P2PConnectionState.Event.RENDEZVOUS_REGISTERED):
		return false
	return true

## 收到对端候选（本阶段由上层直接喂入；9.2 由 rendezvous 服务回包驱动）。
func apply_remote_candidates(candidates: Array, remote_nonce: String = "") -> bool:
	if not _state.transition(P2PConnectionState.Event.CANDIDATES_RECEIVED):
		return false
	_session.remote_candidates.assign(candidates)
	_session.remote_nonce = remote_nonce
	_state.set_remote_candidate_count(_session.remote_candidates.size())
	return true

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

## 推进超时。三级超时分别生效（见 P2PConnectionState 常量）。
func tick(delta_sec: float) -> void:
	if _runner != null:
		_runner.tick(delta_sec)

## 取消 / 重置：保证不留 active peer。
func cancel() -> void:
	if _runner != null:
		_runner.cancel()
	_state.transition(P2PConnectionState.Event.CANCEL)
	_finish(false, "cancelled")

func reset() -> void:
	if _runner != null:
		_runner.cancel()
	_runner = null
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
