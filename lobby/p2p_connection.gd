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
##
## 关键架构（9.2.2）：P2PConnection 持有**单一共享 UDP socket**，
## RendezvousClient 与 P2PHolePunch 复用同一个端点，
## 保证 server observed endpoint 就是 hole punch 真实使用的端点。

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
## 共享 UDP socket：由 P2PConnection 创建并**拥有**生命周期，
## RendezvousClient 与 P2PHolePunch 只复用（它们 owns_udp()/owns_socket() 均为 false）。
var _shared_udp: PacketPeerUDP = null
## finished 只允许派发一次（防止重复 signal 导致上层重复收尾）。
var _finished: bool = false
## cancel 进行中：此时 hole punch 的 cancel 不应被当成探测失败传播。
var _cancelling: bool = false

func _init() -> void:
	_state = P2PConnectionState.new()
	_session = RendezvousContract.SessionState.new()
	_hole_punch = P2PHolePunch.new()
	## 每个信号**只连接一次**（Phase 9.2.2 R2：历史上这里存在重复 connect，
	## 导致一个事件回调执行两次、可能重复 begin_direct_enet()）。
	_hole_punch.path_established.connect(_on_hole_punch_path_established)
	_hole_punch.path_failed.connect(_on_hole_punch_path_failed)
	_hole_punch.timeout.connect(_on_hole_punch_timeout)
	_state.state_changed.connect(_on_state_changed)

## 获取/创建共享 UDP socket。RendezvousClient 与 P2PHolePunch 复用此端点。
func _get_or_create_shared_udp(bind_port: int = 0) -> PacketPeerUDP:
	if _shared_udp == null:
		_shared_udp = PacketPeerUDP.new()
		var err: Error = _shared_udp.bind(bind_port)
		if err != OK:
			_shared_udp = null
			return null
	return _shared_udp

## 关闭共享 UDP socket。
func _close_shared_udp() -> void:
	if _shared_udp != null:
		_shared_udp.close()
		_shared_udp = null

## 共享 UDP 是否由本对象拥有（永远为 true；RendezvousClient / P2PHolePunch 为 false）。
func owns_shared_udp() -> bool:
	return _shared_udp != null

## 共享 UDP socket（诊断 / 测试用）。
func get_shared_udp() -> PacketPeerUDP:
	return _shared_udp

## 是否已有共享 socket（用于「谁拥有 UDP」的测试断言）。
func has_shared_udp() -> bool:
	return _shared_udp != null

## 收到/发出的 state_changed 转发（单一连接）。
func _on_state_changed(from: int, to: int, event: int) -> void:
	state_changed.emit(from, to, event)

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
	## 与 rendezvous 路径一致：候选一到就自动进入 direct probing。
	begin_direct_probing()
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
	_finished = false
	_cancelling = false
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
	## 创建/获取共享 UDP socket，传给 RendezvousClient 复用。
	if _client != null and not rendezvous_host.strip_edges().is_empty():
		var shared_udp: PacketPeerUDP = _get_or_create_shared_udp(0)
		if shared_udp == null:
			_finish(false, "shared_udp_create_failed")
			return false
		if not _client.begin(rendezvous_host, rendezvous_port, _identity, _session.local_candidates, shared_udp):
			_finish(false, "rendezvous_begin_failed")
			return false
		return true
	## 本地装配模式（9.1）：注册立即完成。
	if not _state.transition(P2PConnectionState.Event.RENDEZVOUS_REGISTERED):
		return false
	return true

## 使用预设 SessionIdentity 和本地候选开始 P2P join（供测试/E2E 使用确定性 nonce）。
## 与 begin() 不同，此方法：
## - 接受外部传入的 identity（含预设 nonce）
## - 接受外部传入的 local_candidates
## - 接受外部传入的共享 UDP socket（避免自建）
## - 直接调用 rendezvous client.begin()
func begin_with_identity(
	identity: RendezvousContract.SessionIdentity,
	local_candidates: Array,
	rendezvous_host: String,
	rendezvous_port: int,
	shared_udp: PacketPeerUDP
) -> bool:
	if identity == null or not identity.is_valid():
		return false
	if _client == null:
		return false
	if not _connect_fn.is_valid():
		return false
	if not _state.transition(P2PConnectionState.Event.BEGIN_RENDEZVOUS):
		return false
	_finished = false
	_cancelling = false
	_identity = identity
	_session.local_nonce = identity.nonce
	_session.local_candidates = _clone_rendezvous_candidates(local_candidates)
	_state.set_local_candidate_count(_session.local_candidates.size())
	## 真实 rendezvous：使用传入的共享 UDP socket
	_shared_udp = shared_udp
	if not _client.begin(rendezvous_host, rendezvous_port, _identity, _session.local_candidates, shared_udp):
		_finish(false, "rendezvous_begin_failed")
		return false
	return true

func _clone_rendezvous_candidates(source: Array) -> Array[RendezvousContract.Candidate]:
	var out: Array[RendezvousContract.Candidate] = []
	for candidate: RendezvousContract.Candidate in source:
		var copy: RendezvousContract.Candidate = RendezvousContract.Candidate.new()
		copy.transport = candidate.transport
		copy.path = candidate.path
		copy.address = candidate.address
		copy.port = candidate.port
		copy.observed_address = candidate.observed_address
		copy.observed_port = candidate.observed_port
		out.append(copy)
	return out

func _on_rendezvous_registered(session_id: String, observed_address: String, observed_port: int) -> void:
	## 记录**服务端观测到的**本端端点，以及服务端分配的 session_id。
	## session_id 是 hole punch probe 包的一部分，必须与服务端一致。
	_session.rendezvous_id = session_id
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
	_ensure_remote_observed_candidate()
	_state.set_remote_candidate_count(_session.remote_candidates.size())
	if not _state.transition(P2PConnectionState.Event.CANDIDATES_RECEIVED):
		return
	## Phase 9.2.2 R2：候选到达后**自动**进入 direct probing。
	## 不允许依赖外部调用方“记得”再手动 begin_direct_probing()；
	## tick/poll 只负责推进状态，不能成为遗漏状态转换的唯一机制。
	if not begin_direct_probing():
		## begin_direct_probing() 内部已在失败时进入终态并 _finish。
		pass
	else:
		## Hole punch 已启动，rendezvous client 已完成使命（候选交换完成）。
		## 共享 UDP socket 归 hole punch 使用，rendezvous client 可优雅关闭。
		## 避免服务端因 idle timeout 清理会话导致 client 进入 TIMEOUT。
		## 保留 _client 引用但不再轮询（通过 get_udp() 判断 socket 是否已关闭）。
		if _client != null:
			_client.close()

## 如果服务端给了会话级 remote observed，但候选里没带 per-candidate observed，
## 则补一个 OBSERVED_PUBLIC 候选 —— 打洞必须有真实的 observed 目标。
func _ensure_remote_observed_candidate() -> void:
	if _session.remote_observed_address.is_empty() or _session.remote_observed_port < 1:
		return
	for candidate: RendezvousContract.Candidate in _session.remote_candidates:
		if candidate.has_observed_endpoint():
			return
	var observed: NetworkCandidates.Candidate = NetworkCandidates.from_observed_endpoint(
		_session.remote_observed_address, _session.remote_observed_port, _session.remote_nonce
	)
	_session.remote_candidates.append(NetworkCandidates.to_rendezvous_candidate(observed))

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
##
## **共享 socket 的解复用规则（Phase 9.2.2 R2）**：RendezvousClient 与 P2PHolePunch
## 复用同一个 PacketPeerUDP，而两者都用「取走所有包」的方式读取。任何时刻只能有
## 一个消费者在 drain：
##   - 进入 DIRECT_PROBING（打洞）后，socket 归 P2PHolePunch 读，client.set_paused(true)；
##   - 打洞结束（成功/失败/超时）后，client.set_paused(false) 恢复（可处理 BYE/ERROR 等）。
## 否则 rendezvous 的 poll 会把打洞 probe 吞掉，导致探测永远收不到。
func poll_rendezvous(delta_sec: float) -> void:
	if _client == null or _client.get_udp() == null:
		return
	if _hole_punch.is_active():
		_client.set_paused(true)
	else:
		_client.set_paused(false)
		_client.poll()
	_client.tick(delta_sec)

# ---- Hole Punch 回调（内部）----

func _on_hole_punch_path_established(rtt_ms: int, validated_candidate: Dictionary) -> void:
	if _finished:
		return
	_state.transition(P2PConnectionState.Event.DIRECT_PATH_OK)
	direct_path_established.emit(rtt_ms, validated_candidate)

func _on_hole_punch_path_failed(reason: String) -> void:
	## cancel 期间 hole punch 的失败回调不参与状态推进（cancel 自己收尾）。
	if _finished or _cancelling:
		return
	_state.transition(P2PConnectionState.Event.DIRECT_PATH_FAILED)
	direct_path_failed.emit(reason)
	_finish(false, reason)

func _on_hole_punch_timeout() -> void:
	if _finished or _cancelling:
		return
	_state.transition(P2PConnectionState.Event.TIMEOUT)
	_finish(false, "hole_punch_timeout")

# ---- Hole Punch 公共 API ----

## 开始 UDP hole punch（Phase 9.2）。
## 从 CANDIDATES_RECEIVED 状态调用（**也会由 _on_rendezvous_candidates 自动调用**）。
## 使用 rendezvous 交换的 candidates + observed endpoint。
func begin_direct_probing(bind_port: int = 0) -> bool:
	if _finished:
		return false
	if not _state.transition(P2PConnectionState.Event.BEGIN_DIRECT_PROBING):
		return false
	## 准备本端候选：invite 的 local candidates + 服务端观测到的本端 observed endpoint。
	## observed 必须挂到候选上，hole punch 才能在自己的端点语义里看到它。
	var local_candidates: Array = _local_candidates_with_observed()
	## 远端候选：rendezvous 交换来的 remote candidates（含 observed）。
	var remote_candidates: Array = _session.remote_candidates.duplicate()
	if local_candidates.is_empty() or remote_candidates.is_empty():
		_state.transition(P2PConnectionState.Event.DIRECT_PATH_FAILED)
		_finish(false, "no_candidates_for_probing")
		return false
	## 本端 role：Guest 发起 join，所以是 GUEST；Host 侧由 LobbyManager 调用时传 HOST。
	var local_role: int = P2PUDPProbe.Role.GUEST
	if _identity != null and _identity.role == RendezvousContract.Role.HOST:
		local_role = P2PUDPProbe.Role.HOST
	## 共享 socket 属于本对象；hole punch 只复用（owns_socket() == false）。
	var shared: PacketPeerUDP = _shared_udp
	if shared == null:
		shared = _get_or_create_shared_udp(bind_port)
	var ok: bool = _hole_punch.begin(
		_session.rendezvous_id,
		_session.local_nonce,
		_session.remote_nonce,
		local_role,
		local_candidates,
		remote_candidates,
		bind_port,
		shared
	)
	if not ok:
		_state.transition(P2PConnectionState.Event.DIRECT_PATH_FAILED)
		_finish(false, "hole_punch_begin_failed")
		return false
	return true

## 把服务端观测到的本端端点写进 local candidates（如果有）。
func _local_candidates_with_observed() -> Array:
	var out: Array = []
	for candidate: RendezvousContract.Candidate in _session.local_candidates:
		var copy: RendezvousContract.Candidate = RendezvousContract.Candidate.new()
		copy.transport = candidate.transport
		copy.path = candidate.path
		copy.address = candidate.address
		copy.port = candidate.port
		copy.observed_address = candidate.observed_address
		copy.observed_port = candidate.observed_port
		if not copy.has_observed_endpoint() and _session.has_local_observed_endpoint():
			copy.observed_address = _session.local_observed_address
			copy.observed_port = _session.local_observed_port
		out.append(copy)
	return out

## Hole punch 成功后，在 validated path 上发起 ENet 直连。
## 从 DIRECT_PATH_ESTABLISHED 状态调用。
##
## 关键设计：validated UDP endpoint 与 ENet target endpoint 必须分离。
## validated UDP endpoint 只证明 UDP probe 双向可达，不等于 ENet server listen port。
## ENet target 应使用 remote_advertised（对端自报的 ENet listen port）或 remote_observed，
## 而非 remote_validated（UDP probe 实际源端口）。
## 若有显式设置的 enet_target_override（来自权威来源），优先使用它。
func begin_direct_enet() -> bool:
	if not _state.transition(P2PConnectionState.Event.BEGIN_DIRECT_ENET):
		return false
	## 从 validated candidate 取 remote address/port
	var validated: Dictionary = _hole_punch.get_validated_candidate()
	if validated.is_empty():
		_state.transition(P2PConnectionState.Event.DIRECT_ENET_FAILED)
		_finish(false, "no_validated_candidate")
		return false
	## 优先使用显式设置的 ENet target endpoint override（权威来源）
	var enet_override: Dictionary = _hole_punch.get_enet_target_override()
	var enet_target_address: String
	var enet_target_port: int
	if not enet_override.is_empty() and not enet_override.address.is_empty() and enet_override.port >= 1:
		enet_target_address = enet_override.address
		enet_target_port = enet_override.port
	else:
		## 使用 remote_advertised（对端自报的 ENet listen 端口），
		## 这是 rendezvous 交换的 candidate 原始端口，通常就是 ENet server port。
		var advertised: Dictionary = validated.get("remote_advertised", {})
		if not advertised.is_empty() and not advertised.address.is_empty() and advertised.port >= 1:
			enet_target_address = advertised.address
			enet_target_port = advertised.port
		else:
			## fallback：使用 remote_observed（服务端观测端点）
			var observed: Dictionary = validated.get("remote_observed", {})
			if not observed.is_empty() and not observed.address.is_empty() and observed.port >= 1:
				enet_target_address = observed.address
				enet_target_port = observed.port
			else:
				## 最后 fallback：validated UDP endpoint（仅 loopback 场景可行）
				var validated_udp: Dictionary = validated.get("remote_validated", validated.remote)
				enet_target_address = validated_udp.address
				enet_target_port = validated_udp.port
	if enet_target_address.is_empty() or enet_target_port < 1:
		_state.transition(P2PConnectionState.Event.DIRECT_ENET_FAILED)
		_finish(false, "invalid_enet_target_endpoint")
		return false
	## 关闭 probe socket（hole punch 已完成，不再需要打洞探测）
	_hole_punch.cancel()
	## 复用现有 ConnectAttemptRunner 逻辑，但只试这一个 ENet target candidate
	var plan: ConnectionPath = ConnectionPath.new()
	var candidate: ConnectionPath.Candidate = ConnectionPath.Candidate.new()
	candidate.path = LobbyPlayer.Path.WAN_IPV4
	candidate.address = enet_target_address
	candidate.port = enet_target_port
	plan._candidates.append(candidate)
	_runner = ConnectAttemptRunner.new()
	_runner.candidate_started.connect(_on_candidate_started)
	_runner.attempt_finished.connect(_on_attempt_finished)
	_runner.exhausted.connect(_on_runner_exhausted)
	_runner.begin(plan, _ticket(), _connect_fn, _close_fn)
	return true

## 获取当前 Direct ENet 连接目标（仅供查询/测试断言）。
## 返回包含 address, port, validated=true 的字典；若未进入 DIRECT_ENET_CONNECTING 则为空。
## 同时返回 validated_udp_endpoint 与 enet_target_endpoint 的分离视图。
func get_direct_enet_target() -> Dictionary:
	if _state.get_state() != P2PConnectionState.State.DIRECT_ENET_CONNECTING:
		return {}
	var validated: Dictionary = _hole_punch.get_validated_candidate()
	if validated.is_empty():
		return {}
	var validated_udp: Dictionary = validated.get("remote_validated", validated.remote)
	var advertised: Dictionary = validated.get("remote_advertised", {})
	var observed: Dictionary = validated.get("remote_observed", {})
	var enet_override: Dictionary = _hole_punch.get_enet_target_override()
	var enet_target_address: String
	var enet_target_port: int
	var endpoint_type: String
	if not enet_override.is_empty() and not enet_override.address.is_empty() and enet_override.port >= 1:
		enet_target_address = enet_override.address
		enet_target_port = enet_override.port
		endpoint_type = "enet_target_override"
	elif not advertised.is_empty() and not advertised.address.is_empty() and advertised.port >= 1:
		enet_target_address = advertised.address
		enet_target_port = advertised.port
		endpoint_type = "enet_target_from_advertised"
	elif not observed.is_empty() and not observed.address.is_empty() and observed.port >= 1:
		enet_target_address = observed.address
		enet_target_port = observed.port
		endpoint_type = "enet_target_from_observed"
	else:
		enet_target_address = validated_udp.address
		enet_target_port = validated_udp.port
		endpoint_type = "enet_target_from_validated_udp"
	return {
		"address": enet_target_address,
		"port": enet_target_port,
		"validated": true,
		"endpoint_type": endpoint_type,
		"validated_udp_endpoint": {
			"address": validated_udp.address,
			"port": validated_udp.port
		},
		"enet_target_endpoint": {
			"address": enet_target_address,
			"port": enet_target_port
		},
		"advertised_endpoint": {
			"address": advertised.get("address", ""),
			"port": advertised.get("port", 0)
		},
		"observed_endpoint": {
			"address": observed.get("address", ""),
			"port": observed.get("port", 0)
		}
	}

## ENet connected_to_server 回调（在 validated path 上）。
func notify_direct_enet_connected() -> void:
	if _finished:
		return
	if _runner != null:
		_runner.notify_transport_connected(_runner.current_attempt_id())
	_state.transition(P2PConnectionState.Event.DIRECT_ENET_CONNECTED)

## ENet connection_failed 回调（在 validated path 上）。
func notify_direct_enet_failed(why: String = "refused") -> void:
	if _finished:
		return
	## Direct ENet path 只有一个 validated candidate，失败即终结，不走 runner 的重试逻辑。
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
## 用于 legacy direct path (Phase 9.1) 和 Direct ENet path (Phase 9.2.3) 共用。
func notify_transport_connected() -> void:
	if _finished:
		return
	if _runner != null:
		_runner.notify_transport_connected(_runner.current_attempt_id())
	_state.transition(P2PConnectionState.Event.DIRECT_CONNECTED)

## 握手通过：真正的 CONNECTED。
## 用于 legacy direct path (Phase 9.1) 和 Direct ENet path (Phase 9.2.3) 共用。
func notify_handshake_ok() -> void:
	if _finished:
		return
	if _runner != null:
		_runner.notify_handshake_ok(_runner.current_attempt_id())
	_state.transition(P2PConnectionState.Event.HANDSHAKE_OK)
	_finish(true, "connected")

## 协议不符：VERSION_MISMATCH 终态，不做普通重试。
## 用于 legacy direct path (Phase 9.1) 和 Direct ENet path (Phase 9.2.3) 共用。
func notify_version_mismatch() -> void:
	if _finished:
		return
	## Direct ENet path：直接终结，不走 runner 的重试逻辑。
	_state.transition(P2PConnectionState.Event.VERSION_MISMATCH)
	_finish(false, "version_mismatch")

## ticket 被拒：TICKET_REJECTED 终态，不做普通重试。
## 用于 legacy direct path (Phase 9.1) 和 Direct ENet path (Phase 9.2.3) 共用。
func notify_ticket_rejected() -> void:
	if _finished:
		return
	## Direct ENet path：直接终结，不走 runner 的重试逻辑。
	_state.transition(P2PConnectionState.Event.TICKET_REJECTED)
	_finish(false, "ticket_rejected")

## 传输层失败（connection_failed）：换下一个候选，由 runner 决定是否还有候选。
## 用于 legacy direct path (Phase 9.1)。Direct ENet path 用 notify_direct_enet_failed。
func notify_connection_failed(why: String = "refused") -> void:
	if _finished:
		return
	if _runner == null:
		_finish(false, why)
		return
	_runner.notify_connection_failed(_runner.current_attempt_id(), why)

## 推进超时。四级超时分别生效（见 P2PConnectionState 常量）。
func tick(delta_sec: float) -> void:
	if _finished:
		return
	if _runner != null:
		_runner.tick(delta_sec)
	if _hole_punch != null and _hole_punch.is_active():
		_hole_punch.tick(int(delta_sec * 1000))

## 取消：停掉所有探测、释放共享 socket、明确终结。可重复调用且只终结一次。
func cancel() -> void:
	if _finished:
		return
	_cancelling = true
	if _runner != null:
		_runner.cancel()
	if _hole_punch != null:
		_hole_punch.cancel()
	## 取消也要关掉 rendezvous socket，不留资源。
	if _client != null:
		_client.close()
	## 共享 socket 的 owner 是本对象，只有这里能关它。
	_close_shared_udp()
	_state.transition(P2PConnectionState.Event.CANCEL)
	_finish(false, "cancelled")
	_cancelling = false

## 完整重置：清理 runner / hole punch / rendezvous / 共享 socket / candidate 状态 /
## validated endpoint / attempt 与 generation 标识。重置后可重新 begin()。
func reset() -> void:
	if _runner != null:
		_runner.cancel()
	_runner = null
	if _hole_punch != null:
		_hole_punch.reset()
	if _client != null:
		_client.reset()
	_unbind_rendezvous()
	_close_shared_udp()
	_invite = null
	_identity = null
	_session = RendezvousContract.SessionState.new()
	_finished = false
	_cancelling = false
	_state.reset()

## 当前是否已走到 validated direct path（Phase 9.2.2 的终点）。
func has_validated_path() -> bool:
	return _hole_punch != null and _hole_punch.is_success()

## 实际验证成功的远端端点（源地址端口）；未成功则为空。
func get_validated_endpoint() -> Dictionary:
	if _hole_punch == null:
		return {}
	return _hole_punch.get_validated_endpoint()

## 验证成功时真正使用的探测目标（用于断言 target == validated）。
func get_validated_probe_target() -> Dictionary:
	if _hole_punch == null:
		return {}
	return _hole_punch.get_validated_candidate().get("probe_target", {})

## 显式设置 ENet target endpoint（来自 rendezvous / 显式配置 / STUN 等 transport-authoritative 来源）。
## 当有权威 ENet public endpoint 时调用，覆盖 hole punch validated UDP endpoint。
## Phase 9.2.3：当前默认使用 validated UDP endpoint，此方法为后续阶段预留。
func set_enet_target_endpoint(address: String, port: int) -> void:
	if address.is_empty() or port < 1 or port > 65535:
		return
	## 存储到 hole_punch 的 validated candidate 里（仅供 begin_direct_enet 读取）
	if _hole_punch != null:
		var validated: Dictionary = _hole_punch.get_validated_candidate()
		if not validated.is_empty():
			validated.enet_target_endpoint = {"address": address, "port": port}
			## 通过内部方法更新（需要在 P2PHolePunch 暴露 setter，或直接修改内部字典）
			## 当前简化：在 begin_direct_enet 里读取这个字段
			_hole_punch._set_enet_target_override(address, port)

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
	## finished 只派发一次：重复 signal / cancel+timeout 竞争都不得让上层收两次。
	if _finished:
		return
	_finished = true
	## 失败收尾一定不留 peer。
	if not success and _close_fn.is_valid():
		_close_fn.call()
	## 终态后不再需要 rendezvous socket；owner 是本对象，只有这里能关。
	if not _hole_punch.is_active():
		_close_shared_udp()
	finished.emit(success, reason)
