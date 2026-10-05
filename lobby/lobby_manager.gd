extends Node
class_name LobbyManager

## Lobby domain 的唯一状态机与唯一命令入口（docs/ui_lobby_architecture.md §4）。
## 挂在 MainMenu 下，不是 Autoload；不碰 ENet API，不创建第二个 multiplayer_peer，
## 不建连 / 不关连（那是 LobbyNet 的事），也不直接改 UI。
##
## 分层：LanOverlay --command--> LobbyManager --network command--> LobbyNet
##       LobbyNet --signal--> LobbyManager（改 Room / LobbyPlayer）--snapshot--> UI
## Ready 是状态语义而不是裸 bool：Host 恒显示 HOST（不参与 Start 判定），Guest 显示
## CONNECTING / WAITING / READY；Guest 改角色、Host 改房间规则都会让旧 Ready 失效。

## 房间内容或状态变化，UI 重新拉一次 snapshot。
signal room_changed
## 房间结束（Host 离房 / 主动关房），UI 回多人大厅。
signal room_closed
## start_match() 已经写好 GameLaunch 信封。
signal match_started
## 网络状态变化（来自 LobbyNet），UI 只读，不直接监听底层 ENet / RPC。
signal network_state_changed(state: int)
## Guest 侧连接失败 / 协议不符 / Host 关闭。UI 据此显示失败状态页。
signal network_failed(reason: String)
## Guest 侧握手完成进入 Lobby。
signal joined_lobby
## 有人在房里掉线 / 离房：UI 播放 PLAYERxx LEFT 后把座位画回 EMPTY SEAT。
signal player_left(display_name: String, seat: int)
## Phase 9.2.2 R2：P2P hole punch 已确认一条 validated 直连路径。
## 本阶段到此为止（Direct ENet 属 9.2.3，不在此自动发起）。
signal p2p_path_established(rtt_ms: int, validated_candidate: Dictionary)

enum Role { NONE, HOST, GUEST }

var _room: Room = null
var _role: Role = Role.NONE
## true = 房间有真实 ENet peer 背书（LobbyNet listen/connect 成功）；false = 离线 mock。
var _networked: bool = false
## peer_id -> LobbyPlayer（CONNECTING，seat 0）。pending 不进 Room.players（架构 §4）。
var _pending: Dictionary = {}
var _local_profile_id: String = ""
## 离线 mock 造的假座位 profile_id，只用于本机移除，永不上网。
var _mock_ids: Array[String] = []
var _mock_seq: int = 0
## 网络层（唯一允许碰 ENet 的地方）。由 MainMenu 注入；离线域测试可为空。
var _net: LobbyNet = null
## Guest 侧本地投影用的房间种子（协议 5 不回传身份，先占位）。
var _remote_seed: Dictionary = {}
## 本房 room ticket（Phase 8）。Host 建房时随机生成，属于**房间**生命周期，
## 只用于「持有门票」校验。绝不是身份：与 profile_id / room_id / seat / peer_id 严格分开。
var _room_ticket: String = ""
## Guest 侧本次连接携带的 guest ticket（凭据副本，只读）。
## 与 _room_ticket 分开命名：Host 持 room_ticket，Guest 持 guest_ticket，两者不是同一个东西。
var _guest_ticket: String = ""
## Guest 实际选中的连接路径（LobbyPlayer.Path）。未连接时不假装成 WAN_IPV4。
var _active_path: int = LobbyPlayer.Path.LAN_IPV4
## 当前 join attempt 驱动器（Phase 8 hardening）。null = 没有进行中的 join。
var _runner: ConnectAttemptRunner = null
## P2P 连接编排器（Phase 9.2）：处理 rendezvous + hole punch + ENet 直连。
var _p2p_connection: P2PConnection = null
## 本机默认 rendezvous 服务端（可由 MainMenu / 测试注入；为空则必须由 invite 携带 rv=）。
var _rendezvous_host: String = ""
var _rendezvous_port: int = RendezvousClient.DEFAULT_PORT

func _exit_tree() -> void:
	if _net != null and _net.get_parent() == self:
		_net.queue_free()
	_net = null
	_room = null
	_pending.clear()

# ---- 网络接线（LobbyNet → LobbyManager → UI）----

## MainMenu 注入 LobbyNet。LobbyNet 是唯一碰 ENet 的对象，UI 不接触它。
func bind_net(net: LobbyNet) -> void:
	if _net == net:
		return
	_unbind_net()
	_net = net
	if _net == null:
		return
	if not _net.get_parent() == self and _net.get_parent() == null:
		add_child(_net)
	_net.listen_ok.connect(_on_net_listen_ok)
	_net.listen_failed.connect(_on_net_listen_failed)
	_net.peer_joined.connect(_on_net_peer_joined)
	_net.peer_left.connect(_on_net_peer_left)
	_net.peer_confirmed.connect(_on_net_peer_confirmed)
	_net.guest_character.connect(_on_net_guest_character)
	_net.ready_requested.connect(_on_net_ready_requested)
	_net.ready_applied.connect(_on_net_ready_applied)
	_net.connected.connect(_on_net_connected)
	_net.seat_assigned.connect(_on_net_seat_assigned)
	_net.goal_changed.connect(_on_net_goal_changed)
	_net.arena_changed.connect(_on_net_arena_changed)
	_net.mode_changed.connect(_on_net_mode_changed)
	_net.roster_changed.connect(_on_net_roster_changed)
	_net.match_begin.connect(_on_net_match_begin)
	_net.connection_failed.connect(_on_net_connection_failed)
	_net.version_mismatch.connect(_on_net_version_mismatch)
	_net.join_rejected.connect(_on_net_join_rejected)
	_net.host_closed.connect(_on_net_host_closed)
	_net.state_changed.connect(_on_net_state_changed)

func _unbind_net() -> void:
	if _net == null:
		return
	for conn: Array in [
		[_net.listen_ok, _on_net_listen_ok],
		[_net.listen_failed, _on_net_listen_failed],
		[_net.peer_joined, _on_net_peer_joined],
		[_net.peer_left, _on_net_peer_left],
		[_net.peer_confirmed, _on_net_peer_confirmed],
		[_net.guest_character, _on_net_guest_character],
		[_net.ready_requested, _on_net_ready_requested],
		[_net.ready_applied, _on_net_ready_applied],
		[_net.connected, _on_net_connected],
		[_net.seat_assigned, _on_net_seat_assigned],
		[_net.goal_changed, _on_net_goal_changed],
		[_net.arena_changed, _on_net_arena_changed],
		[_net.mode_changed, _on_net_mode_changed],
		[_net.roster_changed, _on_net_roster_changed],
		[_net.match_begin, _on_net_match_begin],
		[_net.connection_failed, _on_net_connection_failed],
		[_net.version_mismatch, _on_net_version_mismatch],
		[_net.join_rejected, _on_net_join_rejected],
		[_net.host_closed, _on_net_host_closed],
		[_net.state_changed, _on_net_state_changed],
	]:
		var sig: Signal = conn[0] as Signal
		var callable: Callable = conn[1] as Callable
		if sig.is_connected(callable):
			sig.disconnect(callable)

func has_net() -> bool:
	return _net != null

func get_net_state() -> int:
	return int(_net.get_state()) if _net != null else int(LobbyNet.NetState.DISCONNECTED)

# ---- 网络命令（UI 只发这些，不碰 ENet）----

## Host 建房并监听。返回 false = bind 失败（调用方显示 bind failed），房间留在离线 mock。
func host_room(arena_id: String, net_play: GameLaunch.NetPlay, loop_goal: int, borrowed_record_id: String = "") -> bool:
	create_room(arena_id, net_play, loop_goal, borrowed_record_id)
	if _net == null:
		return false
	if not _net.host_listen():
		return false
	_networked = true
	room_changed.emit()
	return true

## Guest 连 Host（手打 IPv4 的 LAN 路径）。
## 走同一个 ConnectAttemptRunner：单候选、无回退，但同样享有 attempt_id 隔离与
## 明确的结果分类 —— 否则手打 IP 失败时旧 runner 会误收别的连接的回调。
func join_room_address(address: String) -> bool:
	if _net == null:
		return false
	_guest_ticket = ""
	var plan: ConnectionPath = ConnectionPath.from_address(address)
	if plan.is_empty():
		return false
	if _runner != null:
		_runner.cancel()
	_runner = ConnectAttemptRunner.new()
	_runner.candidate_started.connect(_on_candidate_started)
	_runner.attempt_finished.connect(_on_attempt_finished)
	_runner.exhausted.connect(_on_join_exhausted)
	return _runner.begin(plan, "", _connect_transport, _close_transport)

# ---- 邀请票据（Phase 8）----
#
# UI 只允许调这两个命令。禁止 UI 自己拼 "wpg://"、自己解析 query、自己生成 token、
# 自己挑 ENet 地址 —— 那些全部归本层与 JoinInvite / ConnectionPath。

## Host：生成本房邀请票据。
##
## ticket lifecycle（Phase 8 明确语义，方案 A = 复用）：
## - room ticket 在**建房时**生成一次，属于当前房间的生命周期；
## - 再次调用 create_invite() **复用**当前 room ticket —— 复制第二张 invite 不会
##   让第一张失效，同一间房的多个 Guest 可以共享同一张门票；
## - 只有显式 rotate_room_ticket() 才生成新 ticket（旧 invite 从那一刻起失效）；
## - ticket 绝不复用 room_id / profile_id / seat / peer_id。
##
## lan_host 由调用方给出（UI 从 LanBeacon / 多网卡里读出本机地址，不猜）。
func create_invite(lan_host: String, lan_port: int = GameLaunch.NET_PORT) -> JoinInvite:
	if _room == null:
		return null
	if _room_ticket.is_empty():
		_room_ticket = JoinInvite.generate_token()
	var host_name: String = _room.host_display_name
	var invite: JoinInvite = JoinInvite.create(
		lan_host,
		lan_port,
		_room_ticket,
		_room.room_id,
		host_name
	)
	if not invite.is_valid():
		return null
	if _net != null:
		_net.set_ticket(_room_ticket)
	return invite

## Host：显式轮换本房 ticket（旧 invite 立即失效）。
## 这是唯一会改变 room ticket 的入口；常规 create_invite() 不再换票。
func rotate_room_ticket() -> String:
	_room_ticket = JoinInvite.generate_token()
	if _net != null:
		_net.set_ticket(_room_ticket)
	return _room_ticket

## Host 侧：本房当前 ticket（无房则空）。仅供 Host 自己复述给 Guest，绝不外发身份。
func get_room_ticket() -> String:
	return _room_ticket

## Guest 侧：本次连接携带的 guest ticket（无则空）。与 room ticket 是两个独立概念。
func get_guest_ticket() -> String:
	return _guest_ticket

## Guest：解析并消费一张邀请票据，按候选顺序**串行**发起连接。
##
## 返回 JoinInvite（含 error 供 UI 显示）。
## 语义修正（Phase 8 hardening）：本函数返回 error == OK 只表示「解析通过且已**发起**
## 第一次尝试」，**不代表连接成功**。真正的结果通过 attempt_finished / 网络信号异步到达：
##   connected + 握手成功 => CONNECTED
##   connection_failed / timeout => 自动 close peer 后换下一个候选
##   VERSION_MISMATCH / TICKET_REJECTED => 立即停止，不再换路径
func join_invite(raw: String) -> JoinInvite:
	var invite: JoinInvite = JoinInvite.parse(raw)
	if not invite.is_valid():
		return invite
	## Phase 9.2.2 R2：P2P 邀请必须进入 P2P domain flow（rendezvous + hole punch），
	## 而不是旧的 LAN 串行候选。UI 不变（仍只调 join_invite），分流在 domain 内完成。
	if invite.is_p2p():
		return join_invite_p2p(invite, invite.rendezvous_host, invite.rendezvous_port)
	if _net == null:
		invite.error = JoinInvite.InvalidReason.BAD_LAN_HOST
		return invite
	var plan: ConnectionPath = invite.to_candidates()
	if plan.is_empty():
		invite.error = JoinInvite.InvalidReason.BAD_LAN_HOST
		return invite
	_guest_ticket = invite.token
	if _runner != null:
		_runner.cancel()
	_runner = ConnectAttemptRunner.new()
	_runner.candidate_started.connect(_on_candidate_started)
	_runner.attempt_finished.connect(_on_attempt_finished)
	_runner.exhausted.connect(_on_join_exhausted)
	_runner.begin(plan, invite.token, _connect_transport, _close_transport)
	return invite

## 传输层注入：真正的建连在 LobbyNet（唯一持有 ENet 的对象）。
## 返回 true 仅表示「已发起」——**不是**连接成功，这正是过去出 bug 的地方。
func _connect_transport(address: String, port: int, ticket: String) -> bool:
	if _net == null:
		return false
	return _net.client_connect(address, port, ticket)

## 换候选前必须关掉当前 peer：SceneTree.multiplayer 同时只能有一个 active peer。
func _close_transport() -> void:
	if _net != null:
		_net.close()

# ---- P2P Connection (Phase 9.2) ----

## 创建/获取 P2PConnection 实例。
func _get_or_create_p2p_connection() -> P2PConnection:
	if _p2p_connection == null:
		_p2p_connection = P2PConnection.new()
		_p2p_connection.bind_transport(_connect_transport.bind(), _close_transport.bind())
		_p2p_connection.state_changed.connect(_on_p2p_state_changed)
		_p2p_connection.finished.connect(_on_p2p_finished)
		_p2p_connection.direct_path_established.connect(_on_p2p_direct_path_established)
		_p2p_connection.direct_path_failed.connect(_on_p2p_direct_path_failed)
	return _p2p_connection

## 配置本机默认 rendezvous 服务端（供 create_p2p_invite / join_invite 兜底）。
func set_rendezvous_endpoint(host: String, port: int = RendezvousClient.DEFAULT_PORT) -> void:
	_rendezvous_host = host.strip_edges()
	_rendezvous_port = port if port >= 1 and port <= 65535 else RendezvousClient.DEFAULT_PORT

func get_rendezvous_host() -> String:
	return _rendezvous_host

func get_rendezvous_port() -> int:
	return _rendezvous_port

## Host 侧：生成一张 **P2P** 邀请（带 p2p=1 与 rendezvous 端点）。
func create_p2p_invite(lan_host: String, rendezvous_host: String = "", rendezvous_port: int = 0) -> JoinInvite:
	if _room == null:
		return null
	if _room_ticket.is_empty():
		_room_ticket = JoinInvite.generate_token()
	var rv_host: String = rendezvous_host.strip_edges() if not rendezvous_host.strip_edges().is_empty() else _rendezvous_host
	var rv_port: int = rendezvous_port if rendezvous_port >= 1 and rendezvous_port <= 65535 else _rendezvous_port
	var invite: JoinInvite = JoinInvite.create(
		lan_host,
		GameLaunch.NET_PORT,
		_room_ticket,
		_room.room_id,
		_room.host_display_name,
		"",
		"",
		JoinInvite.DEFAULT_WAN_PORT,
		true,
		rv_host,
		rv_port
	)
	if not invite.is_valid():
		return null
	if _net != null:
		_net.set_ticket(_room_ticket)
	return invite

## 开始通过 rendezvous + hole punch 的 P2P join。
## invite 必须包含有效的 room_id / ticket / candidates。
## rendezvous_host/port：公网 rendezvous 服务端地址；为空时用本机配置兜底。
func join_invite_p2p(invite: JoinInvite, rendezvous_host: String = "", rendezvous_port: int = 0) -> JoinInvite:
	if invite == null or not invite.is_valid():
		if invite == null:
			invite = JoinInvite.new()
		invite.error = JoinInvite.InvalidReason.BAD_LAN_HOST
		return invite
	if _net == null:
		invite.error = JoinInvite.InvalidReason.BAD_LAN_HOST
		return invite
	var rv_host: String = rendezvous_host.strip_edges()
	if rv_host.is_empty():
		rv_host = invite.rendezvous_host.strip_edges()
	if rv_host.is_empty():
		rv_host = _rendezvous_host
	if rv_host.is_empty():
		## 没有 rendezvous 端点 = 无法做真 P2P；明确报错，绝不退化成「假装已注册」。
		invite.error = JoinInvite.InvalidReason.MISSING_RENDEZVOUS
		return invite
	var rv_port: int = rendezvous_port
	if rv_port < 1 or rv_port > 65535:
		rv_port = invite.rendezvous_port
	if rv_port < 1 or rv_port > 65535:
		rv_port = _rendezvous_port

	## 每次 join 用**新的** P2PConnection，避免复用上一个的终态/残留。
	if _p2p_connection != null:
		_p2p_connection.reset()
		_p2p_connection = null
	_runner = null
	var p2p: P2PConnection = _get_or_create_p2p_connection()
	var client: RendezvousClient = RendezvousClient.new()
	p2p.bind_rendezvous(client)

	## 开始 P2P 连接流程（状态由 rendezvous 回包 + hole punch 驱动）。
	if not p2p.begin(invite, rv_host, rv_port):
		invite.error = JoinInvite.InvalidReason.BAD_LAN_HOST
		_p2p_connection = null
		return invite

	_guest_ticket = invite.token
	return invite

## 推进 P2P 连接状态机。由 MainMenu 每帧驱动。
func tick_p2p(delta_sec: float) -> void:
	if _p2p_connection != null:
		_p2p_connection.poll_rendezvous(delta_sec)
		_p2p_connection.tick(delta_sec)

## 取消进行中的 P2P join。
func cancel_p2p() -> void:
	if _p2p_connection != null:
		_p2p_connection.cancel()
		_p2p_connection = null

## P2P 状态变化回调。
func _on_p2p_state_changed(from: int, to: int, event: int) -> void:
	## 映射到 LobbyManager 可观测状态
	pass

## P2P 完成回调（成功或失败）。
func _on_p2p_finished(success: bool, reason: String) -> void:
	if success:
		## 成功：ENet 已在 validated path 上连上并握手通过
		_networked = true
		room_changed.emit()
	else:
		## 失败：清理并通知 UI
		if _net != null:
			_net.close()
		network_failed.emit(reason)
	## 终态后彻底清理（socket / client / probe 状态），不留「看似可继续」的残骸。
	if _p2p_connection != null:
		_p2p_connection.reset()
	_p2p_connection = null

## Hole punch 成功，得到 validated path。
## Phase 9.2.3：自动发起 Direct ENet，接到 LobbyNet 单 peer，跑 protocol 6 握手。
func _on_p2p_direct_path_established(rtt_ms: int, validated_candidate: Dictionary) -> void:
	p2p_path_established.emit(rtt_ms, validated_candidate)
	## 在 validated path 上发起 ENet 直连。
	if _p2p_connection != null:
		_p2p_connection.begin_direct_enet()

## Hole punch 失败。
func _on_p2p_direct_path_failed(reason: String) -> void:
	## 失败由 _on_p2p_finished 处理
	pass

func _on_candidate_started(attempt: ConnectAttempt) -> void:
	if attempt.candidate != null:
		_active_path = attempt.candidate.path

func _on_attempt_finished(attempt: ConnectAttempt) -> void:
	if attempt == null:
		return
	if attempt.is_success():
		_networked = true
		room_changed.emit()
		return
	## 可重试的失败：继续往下试，不报错（UI 不该在 LAN 失败瞬间弹错）。
	if attempt.is_retryable():
		return
	## VERSION_MISMATCH / TICKET_REJECTED：明确失败，不再重试。
	network_failed.emit(ConnectAttempt.outcome_name(attempt.outcome))

func _on_join_exhausted(attempt: ConnectAttempt, reason: String) -> void:
	_runner = null
	if attempt != null and attempt.is_success():
		return
	## 收尾保证没有残留 peer（超时 / 全候选失败都走这里）。
	if _net != null:
		_net.close()
	if reason != "cancelled":
		network_failed.emit(reason)

## 当前 join attempt（无则 null）。UI / 测试只读，不修改。
func get_connect_attempt() -> ConnectAttempt:
	return _runner.current_attempt() if _runner != null else null

## 推进 join 超时。由 MainMenu 每帧驱动；没有进行中的 join 时是空操作。
func tick_join(delta_sec: float) -> void:
	if _runner != null:
		_runner.tick(delta_sec)
	tick_p2p(delta_sec)

## 取消进行中的 join（关 peer、不留残留）。没有进行中的 join 时是空操作。
func cancel_join() -> void:
	if _runner != null:
		_runner.cancel()
		_runner = null
	cancel_p2p()

## 本机实际选中的连接路径（未连接时返回 LAN_IPV4 作为无害默认）。
func get_active_path() -> int:
	return _active_path

## 关掉网络。Host 关房 / Guest 断线都走这里。
func close_network() -> void:
	if _net != null:
		_net.close()
	_networked = false
	room_changed.emit()

# ---- 建 / 入 / 离 ----

## 建房：本地 Profile 直接进 seat 1，Host = true。默认离线 mock，bind 成功后调 mark_networked()。
func create_room(arena_id: String = "yard", net_play: GameLaunch.NetPlay = GameLaunch.NetPlay.COOP, loop_goal: int = 0, borrowed_record_id: String = "") -> Room:
	leave_room()
	if PlayerProfile.get_profile_id().is_empty():
		PlayerProfile.load_from_disk()
	_local_profile_id = PlayerProfile.get_profile_id()
	var host_player: LobbyPlayer = LobbyPlayer.from_profile(PlayerProfile.get_public_profile(), 1, Room.HOST_SEAT, true)
	_room = Room.create(host_player, arena_id, net_play, loop_goal, borrowed_record_id)
	_role = Role.HOST
	_networked = false
	room_changed.emit()
	return _room

## Guest 侧入房（Phase 7 由 LobbyNet 的 hello/roster 驱动；本阶段只给域测试用）。
func join_room(room: Room) -> bool:
	if room == null or room.is_closed():
		return false
	leave_room()
	if PlayerProfile.get_profile_id().is_empty():
		PlayerProfile.load_from_disk()
	_local_profile_id = PlayerProfile.get_profile_id()
	var guest: LobbyPlayer = LobbyPlayer.from_profile(PlayerProfile.get_public_profile(), LobbyPlayer.NO_PEER, LobbyPlayer.NO_SEAT, false)
	if room.add_player(guest) != Room.AddResult.ADDED:
		return false
	_room = room
	_role = Role.GUEST
	_networked = true
	room_changed.emit()
	return true

## Guest 从 Host 同步的种子构造本地投影房：只用于 Lobby UI 显示与本地 Ready 交互。
## Ready 的真实网络广播是下一刀（LobbyNet）的事，本刀 Guest 侧只保证 UI contract 成立。
func join_remote(room_id: String, host_name: String, arena_id: String, net_play: GameLaunch.NetPlay, loop_goal: int, seat: int) -> bool:
	leave_room()
	if PlayerProfile.get_profile_id().is_empty():
		PlayerProfile.load_from_disk()
	_local_profile_id = PlayerProfile.get_profile_id()
	var host: LobbyPlayer = LobbyPlayer.new()
	host.profile_id = "host:%s" % room_id
	host.display_name = PlayerProfile.sanitize_name(host_name if not host_name.is_empty() else "HOST")
	host.avatar_id = PlayerProfile.DEFAULT_AVATAR
	host.peer_id = 1
	_room = Room.create(host, arena_id, net_play, loop_goal)
	_room.room_id = room_id
	var guest: LobbyPlayer = LobbyPlayer.from_profile(PlayerProfile.get_public_profile(), LobbyPlayer.NO_PEER, LobbyPlayer.NO_SEAT, false)
	guest.connection_state = LobbyPlayer.ConnectionState.CONNECTED
	## 进房默认 NOT READY：Guest 必须自己按 READY，Host 不会替谁准备。
	guest.ready = false
	if _room.add_player(guest, clampi(seat, Room.HOST_SEAT + 1, Room.MAX_PLAYERS)) != Room.AddResult.ADDED:
		_room = null
		return false
	_role = Role.GUEST
	_networked = true
	room_changed.emit()
	return true

## 离房。Host 离房 = 关房（1.0 不做 Host 迁移），Guest 离房只释放自己的座位。
func leave_room() -> void:
	_pending.clear()
	_mock_ids.clear()
	if _room == null:
		_role = Role.NONE
		_networked = false
		return
	if _role == Role.HOST:
		_room.close()
	else:
		_room.remove_player(_local_profile_id)
	_room = null
	_role = Role.NONE
	_networked = false
	room_closed.emit()
	room_changed.emit()

# ---- LobbyNet 信号处理（Host 权威）----

func _on_net_listen_ok() -> void:
	if _room != null:
		_networked = true
		room_changed.emit()

func _on_net_listen_failed() -> void:
	_networked = false
	room_changed.emit()
	network_failed.emit("bind failed")

func _on_net_peer_joined(peer_id: int, _seat: int) -> void:
	# peer 连上立刻占座（pending），握手完成才进 players。
	var seat: int = note_peer_connecting(peer_id)
	if seat == Room.NO_SEAT:
		if _net != null and _net.is_server():
			_net.disconnect_peer(peer_id)
		return
	if _net != null:
		_net.set_seat_peer(seat, peer_id)
		# 协议 6：不再由 Host 主动 send_hello。Guest 连上后自己出示 ticket，
		# Host 在 rpc_hello 里校验；这里只负责占 pending 座。
		# ticket 不通过时 peer_confirmed 不会到达 -> pending 由 drop_peer 释放。

func _on_net_peer_left(peer_id: int) -> void:
	drop_peer(peer_id)
	if _net != null:
		_net.clear_seat_of_peer(peer_id)

func _on_net_peer_confirmed(peer_id: int, _seat: int) -> void:
	confirm_peer(peer_id)
	if _net != null:
		_net.send_session_to_peer(peer_id, _roster_characters(), _room.loop_goal if _room != null else 0, _room.arena_id if _room != null else "yard", int(_room.net_play) if _room != null else int(GameLaunch.NetPlay.COOP))
		## 新 Guest 需要补齐 5 个座位的 Ready 快照；已在房里的 Guest 需要知道新座位是 WAITING。
		_net.send_ready_snapshot_to_peer(peer_id, _ready_flags())
		_broadcast_roster()
		_broadcast_cleared_ready()

func _on_net_guest_character(peer_id: int, character_id: String) -> void:
	set_peer_character(peer_id, character_id)
	if _net != null:
		_broadcast_roster()

func _on_net_ready_requested(peer_id: int, ready: bool) -> void:
	apply_remote_ready(peer_id, ready)

## Guest 侧：Host 的 Ready 权威值覆盖本地投影。
## 协议 5 不回传身份，Guest 只认得自己那个座位；别人的 Ready 由 Host 端 UI 读 Room 快照。
func _on_net_ready_applied(seat: int, ready: bool) -> void:
	if _room == null or _role != Role.GUEST:
		return
	var player: LobbyPlayer = _room.get_player_in_seat(seat)
	if player == null or player.ready == ready:
		return
	player.ready = ready
	room_changed.emit()

func _on_net_connected() -> void:
	# 传输层连上（尚未握手）。告诉当前 attempt「还没定论，继续等握手」。
	# 关键：**这里绝不能判定成功** —— 握手没过就换候选/宣告成功都是错的。
	
	# P2P Direct ENet path: route to P2PConnection
	if _p2p_connection != null and _p2p_connection.get_state_value() == P2PConnectionState.State.DIRECT_ENET_CONNECTING:
		_p2p_connection.notify_direct_enet_connected()
		# P2P path: 不在这里发送 guest character，等 handshake_ok (seat_assigned) 再发
		return
	
	# Legacy LAN/Invite path: use ConnectAttemptRunner
	if _runner != null:
		_runner.notify_transport_connected(_runner.current_attempt_id())
	# Guest 连上 Host，发自己的角色。
	if _net != null:
		var local: LobbyPlayer = get_local_player()
		var character_id: String = local.selected_character_id if local != null else PlayerProfile.get_preferred_character_id()
		_net.send_guest_character(character_id)

func _on_net_seat_assigned(seat: int) -> void:
	# 收到座位 = Host 的握手回执，本次 attempt 真正成功。
	
	# P2P Direct ENet path: route to P2PConnection
	if _p2p_connection != null and (_p2p_connection.get_state_value() == P2PConnectionState.State.DIRECT_ENET_CONNECTING or _p2p_connection.get_state_value() == P2PConnectionState.State.HANDSHAKING):
		_p2p_connection.notify_handshake_ok()
		# P2P path: 必须完成 Guest 本地 Lobby 投影并 emit joined_lobby
		var local: LobbyPlayer = get_local_player()
		var character_id: String = local.selected_character_id if local != null else PlayerProfile.get_preferred_character_id()
		# 协议 6：seat_assigned 后 Guest 发角色（已在 connected 时发过，这里确保幂等）
		if _net != null:
			_net.send_guest_character(character_id)
		join_remote(str(_remote_seed.get("room_id", "")), str(_remote_seed.get("host_name", "")), str(_remote_seed.get("arena_id", "yard")), _remote_seed.get("net_play", GameLaunch.NetPlay.COOP), int(_remote_seed.get("loop_goal", 0)), seat)
		set_local_character(character_id)
		joined_lobby.emit()
		return
	
	# Legacy LAN/Invite path: use ConnectAttemptRunner
	if _runner != null:
		_runner.notify_handshake_ok(_runner.current_attempt_id())
	# Guest 侧 Lobby 是本地投影；协议 5 不回传 host 名 / room_id，先占位。
	var arena: String = str(_remote_seed.get("arena_id", "yard"))
	var net_play: GameLaunch.NetPlay = _remote_seed.get("net_play", GameLaunch.NetPlay.COOP)
	var loop_goal: int = int(_remote_seed.get("loop_goal", 0))
	var local: LobbyPlayer = get_local_player()
	var character_id: String = local.selected_character_id if local != null else PlayerProfile.get_preferred_character_id()
	join_remote(str(_remote_seed.get("room_id", "")), str(_remote_seed.get("host_name", "")), arena, net_play, loop_goal, seat)
	set_local_character(character_id)
	joined_lobby.emit()

func _on_net_goal_changed(loop_goal: int) -> void:
	_remote_seed["loop_goal"] = loop_goal
	if _room != null and _role == Role.GUEST:
		_room.set_loop_goal(loop_goal)
		room_changed.emit()

func _on_net_arena_changed(arena_id: String) -> void:
	_remote_seed["arena_id"] = arena_id
	if _room != null and _role == Role.GUEST:
		_room.set_arena_id(arena_id)
		room_changed.emit()

func _on_net_mode_changed(net_play: int) -> void:
	_remote_seed["net_play"] = GameLaunch.NetPlay.BATTLE if net_play == int(GameLaunch.NetPlay.BATTLE) else GameLaunch.NetPlay.COOP
	if _room != null and _role == Role.GUEST:
		_room.set_net_play(_remote_seed["net_play"])
		room_changed.emit()

func _on_net_roster_changed(_character_ids: PackedStringArray) -> void:
	room_changed.emit()

func _on_net_match_begin(loop_goal: int, arena_id: String, net_play: int) -> void:
	_remote_seed["loop_goal"] = loop_goal
	_remote_seed["arena_id"] = arena_id
	_remote_seed["net_play"] = GameLaunch.NetPlay.BATTLE if net_play == int(GameLaunch.NetPlay.BATTLE) else GameLaunch.NetPlay.COOP
	_write_guest_envelope(loop_goal, arena_id, net_play)
	if _room != null:
		_room.room_state = Room.RoomState.STARTING
	match_started.emit()
	room_changed.emit()

func _on_net_connection_failed() -> void:
	# 有进行中的 join：交给 runner 决定「换下一个候选」。它自己会 close peer，
	# 只有候选全部耗尽才 emit network_failed（由 _on_join_exhausted 负责）。
	
	# P2P Direct ENet path: route to P2PConnection
	if _p2p_connection != null and (_p2p_connection.get_state_value() == P2PConnectionState.State.DIRECT_ENET_CONNECTING or _p2p_connection.get_state_value() == P2PConnectionState.State.HANDSHAKING):
		_p2p_connection.notify_direct_enet_failed("refused")
		return
	
	# Legacy LAN/Invite path: use ConnectAttemptRunner
	if _runner != null:
		_runner.notify_connection_failed(_runner.current_attempt_id(), "refused")
		return
	_networked = false
	room_changed.emit()
	network_failed.emit("refused")

func _on_net_version_mismatch() -> void:
	# 协议不符：换 IP 也解决不了，立即终结本次 join，不做普通重试。
	
	# P2P Direct ENet path: route to P2PConnection
	if _p2p_connection != null and (_p2p_connection.get_state_value() == P2PConnectionState.State.DIRECT_ENET_CONNECTING or _p2p_connection.get_state_value() == P2PConnectionState.State.HANDSHAKING):
		_p2p_connection.notify_version_mismatch()
		return
	
	# Legacy LAN/Invite path: use ConnectAttemptRunner
	if _runner != null:
		_runner.notify_version_mismatch(_runner.current_attempt_id(), "protocol_mismatch")
		return
	_networked = false
	network_failed.emit("Version mismatch")

func _on_net_join_rejected(reason: int) -> void:
	# ticket 被拒：换 IP 也解决不了，立即终结本次 join，不做普通重试。
	
	# P2P Direct ENet path: route to P2PConnection
	if _p2p_connection != null and (_p2p_connection.get_state_value() == P2PConnectionState.State.DIRECT_ENET_CONNECTING or _p2p_connection.get_state_value() == P2PConnectionState.State.HANDSHAKING):
		_p2p_connection.notify_ticket_rejected()
		return
	
	# Legacy LAN/Invite path: use ConnectAttemptRunner
	if _runner != null:
		_runner.notify_ticket_rejected(_runner.current_attempt_id(), "ticket_rejected:%d" % reason)
		return
	_networked = false
	network_failed.emit("ticket rejected")

func _on_net_host_closed() -> void:
	_networked = false
	network_failed.emit("host closed")

func _on_net_state_changed(state: int) -> void:
	network_state_changed.emit(state)

func has_room() -> bool:
	return _room != null

func get_room() -> Room:
	return _room

func get_role() -> Role:
	return _role

func is_host() -> bool:
	return _role == Role.HOST

func is_networked() -> bool:
	return _networked

func is_offline() -> bool:
	return _room != null and not _networked

func mark_networked() -> void:
	if _room == null:
		return
	_networked = true
	room_changed.emit()

## 关掉 ENet peer 后把房间留在离线 mock 状态（调试口，见 LanOverlay 的 F12）。
func mark_offline() -> void:
	if _room == null:
		return
	_networked = false
	_pending.clear()
	room_changed.emit()

func get_local_profile_id() -> String:
	return _local_profile_id

func get_local_player() -> LobbyPlayer:
	if _room == null:
		return null
	return _room.get_player(_local_profile_id)

func get_local_seat() -> int:
	var player: LobbyPlayer = get_local_player()
	return player.seat if player != null else Room.NO_SEAT

# ---- 玩家增删 ----

func add_player(player: LobbyPlayer, preferred_seat: int = Room.NO_SEAT) -> Room.AddResult:
	if _room == null:
		return Room.AddResult.INVALID
	var result: Room.AddResult = _room.add_player(player, preferred_seat)
	if result == Room.AddResult.ADDED:
		room_changed.emit()
	return result

func remove_player(profile_id: String) -> bool:
	if _room == null:
		return false
	if profile_id == _local_profile_id:
		leave_room()
		return true
	var removed: bool = _room.remove_player(profile_id)
	if removed:
		room_changed.emit()
	return removed

## 离线 mock 的假座位：只在没有真实 peer 背书的房间里允许，profile_id 带 mock: 前缀。
func add_mock_player(display_name: String = "", connection_state: LobbyPlayer.ConnectionState = LobbyPlayer.ConnectionState.CONNECTED) -> LobbyPlayer:
	if _room == null or _networked or _room.is_full():
		return null
	_mock_seq += 1
	var seat_hint: int = _room.player_count() + 1
	var player: LobbyPlayer = LobbyPlayer.new()
	player.profile_id = "%s%d" % [LobbyPlayer.MOCK_PROFILE_PREFIX, _mock_seq]
	player.display_name = PlayerProfile.sanitize_name(display_name if not display_name.is_empty() else "Player %02d" % seat_hint)
	player.avatar_id = PlayerProfile.DEFAULT_AVATAR
	player.preferred_character_id = _mock_character_for(seat_hint)
	player.selected_character_id = player.preferred_character_id
	player.peer_id = LobbyPlayer.NO_PEER
	player.ready = true
	player.connection_state = connection_state
	if _room.add_player(player) != Room.AddResult.ADDED:
		return null
	_mock_ids.append(player.profile_id)
	room_changed.emit()
	return player

## 移除最后一个假座位（最高 seat）。
func remove_mock_player() -> bool:
	if _room == null or _mock_ids.is_empty():
		return false
	var profile_id: String = _mock_ids[_mock_ids.size() - 1]
	var player: LobbyPlayer = _room.get_player(profile_id)
	if player == null:
		_mock_ids.remove_at(_mock_ids.size() - 1)
		return false
	_mock_ids.remove_at(_mock_ids.size() - 1)
	_room.remove_player(profile_id)
	room_changed.emit()
	return true

func get_mock_count() -> int:
	return _mock_ids.size()

# ---- 房间设置 ----

func set_ready(profile_id: String, ready: bool) -> bool:
	if _room == null:
		return false
	if not _ready_change_allowed(profile_id):
		return false
	var changed: bool = _room.set_ready(profile_id, ready)
	if changed:
		room_changed.emit()
	return changed

## Guest 只能改自己的 Ready；Host 不参与 Start 判定，不接受普通 Guest Ready 操作。
## 联网 Guest 的 Ready 是请求：本地先落（UI 立刻响应），Host 权威值广播回来再覆盖。
## 返回实际写入后的本地 Ready。
func set_local_ready(ready: bool) -> bool:
	if _room == null:
		return false
	var local: LobbyPlayer = get_local_player()
	if local == null or local.is_host:
		return local.ready if local != null else false
	if not _ready_change_allowed(local.profile_id):
		return local.ready
	if _networked and _role == Role.GUEST and _net != null:
		set_ready(local.profile_id, ready)
		_net.send_ready(local.ready)
		return local.ready
	set_ready(local.profile_id, ready)
	return local.ready

func toggle_local_ready() -> bool:
	var local: LobbyPlayer = get_local_player()
	if local == null or local.is_host:
		return local.ready if local != null else false
	return set_local_ready(not local.ready)

func get_local_ready() -> bool:
	var local: LobbyPlayer = get_local_player()
	return local.ready if local != null else false

## Host 侧：受理 Guest 的 Ready 请求。座位 / pending / 房间状态 / 权限校验都在这里，
## 不合法的请求直接丢弃：Host 的广播才是唯一权威（Guest 本地乐观值不算数）。
func apply_remote_ready(peer_id: int, ready: bool) -> bool:
	if _room == null or _role != Role.HOST:
		return false
	if _room.room_state != Room.RoomState.FORMING or _pending.has(peer_id):
		return false
	var player: LobbyPlayer = _room.get_player_by_peer(peer_id)
	if player == null or player.is_host:
		return false
	if not _room.set_ready(player.profile_id, ready):
		return false
	room_changed.emit()
	_broadcast_ready(player.seat, player.ready)
	return true

## Ready 只在 FORMING 期间可改（Starting 冻结）；Guest 联网时只能改自己。
func _ready_change_allowed(profile_id: String) -> bool:
	if _room == null or _room.room_state != Room.RoomState.FORMING:
		return false
	if _networked and _role == Role.GUEST and profile_id != _local_profile_id:
		return false
	return true

func set_character(profile_id: String, character_id: String) -> bool:
	if _room == null or _room.room_state != Room.RoomState.FORMING:
		return false
	if _networked and _role == Role.GUEST and profile_id != _local_profile_id:
		return false
	var changed: bool = _room.set_character(profile_id, character_id)
	if changed:
		room_changed.emit()
	return changed

func set_local_character(character_id: String) -> bool:
	var changed: bool = set_character(_local_profile_id, character_id)
	if not _networked or _net == null:
		return changed
	if _role == Role.GUEST:
		_net.send_guest_character(get_local_player().selected_character_id if get_local_player() != null else character_id)
	elif _net.is_server():
		_broadcast_roster()
	return changed

func set_host(profile_id: String) -> bool:
	if _room == null:
		return false
	var changed: bool = _room.set_host(profile_id)
	if changed:
		room_changed.emit()
	return changed

## 房间规则只有 Host 能改（Guest 改了也无效），且只在 FORMING 期间。
## 规则一变，所有 Guest 的旧 Ready 失效：必须把新的权威 Ready 广播出去，否则各端显示不一致。
func set_arena_id(arena_id: String) -> void:
	if not _settings_change_allowed():
		return
	_room.set_arena_id(arena_id)
	room_changed.emit()
	if _networked and _net != null and _net.is_server():
		_broadcast_arena()
		_broadcast_cleared_ready()

func set_net_play(net_play: GameLaunch.NetPlay) -> void:
	if not _settings_change_allowed():
		return
	_room.set_net_play(net_play)
	room_changed.emit()
	if _networked and _net != null and _net.is_server():
		_broadcast_mode()
		_broadcast_cleared_ready()

func set_loop_goal(loop_goal: int) -> void:
	if not _settings_change_allowed():
		return
	_room.set_loop_goal(loop_goal)
	room_changed.emit()
	if _networked and _net != null and _net.is_server():
		_broadcast_goal()
		_broadcast_cleared_ready()

## 房间规则（mode / arena / goal）只有 Host 能改，且只在 FORMING 期间（Starting 冻结）。
func _settings_change_allowed() -> bool:
	if _room == null or _room.room_state != Room.RoomState.FORMING:
		return false
	if _networked and _role == Role.GUEST:
		return false
	return true

## 房间隐私：只有 Host 能改。LAN_VISIBLE 才允许对外广播信标（Beacon 起停归 Host 侧 UI）。
## 隐私不是房间规则，所以不动 Guest 的 Ready。
func set_privacy(privacy: Room.Privacy) -> bool:
	if _room == null or _role != Role.HOST:
		return false
	if _room.room_state != Room.RoomState.FORMING:
		return false
	if not _room.set_privacy(privacy):
		return false
	room_changed.emit()
	return true

func get_privacy() -> int:
	return int(_room.privacy) if _room != null else int(Room.Privacy.LAN_VISIBLE)

# ---- pending peer（LanOverlay 转发 ENet 事件；Phase 7 归 LobbyNet） ----

## peer_connected：立刻占座，但还不是 players 成员。返回 0 = 满员 / 无房，调用方应断开该 peer。
func note_peer_connecting(peer_id: int) -> int:
	if _room == null:
		return Room.NO_SEAT
	var seat: int = _room.reserve_seat(peer_id)
	if seat == Room.NO_SEAT:
		return Room.NO_SEAT
	if not _pending.has(peer_id):
		var player: LobbyPlayer = LobbyPlayer.new()
		player.profile_id = _pending_profile_id(peer_id)
		player.display_name = "Player %02d" % seat
		player.avatar_id = PlayerProfile.DEFAULT_AVATAR
		player.preferred_character_id = PlayerProfile.DEFAULT_CHARACTER
		player.selected_character_id = PlayerProfile.DEFAULT_CHARACTER
		player.peer_id = peer_id
		player.seat = LobbyPlayer.NO_SEAT
		player.ready = false
		player.connection_state = LobbyPlayer.ConnectionState.CONNECTING
		_pending[peer_id] = player
	room_changed.emit()
	return seat

## 握手完成：pending → 正式座位（CONNECTED）。返回 seat，0 = 失败。
func confirm_peer(peer_id: int) -> int:
	if _room == null:
		return Room.NO_SEAT
	var seat: int = _room.pending_seat_of(peer_id)
	var player: LobbyPlayer = _pending.get(peer_id) as LobbyPlayer
	if seat == Room.NO_SEAT or player == null:
		return Room.NO_SEAT
	player.connection_state = LobbyPlayer.ConnectionState.CONNECTED
	## Guest 握手完成 = 刚到房里，必须自己按 READY，不默认准备。
	player.ready = false
	if _room.add_player(player, seat) != Room.AddResult.ADDED:
		return Room.NO_SEAT
	_pending.erase(peer_id)
	room_changed.emit()
	return seat

## 连接断开：pending 释放占位，已入座的移除。不影响别人座位号。
## 已入座的人掉线会发 player_left（UI 播 PLAYERxx LEFT），座位立刻变空。
func drop_peer(peer_id: int) -> bool:
	if _room == null:
		return false
	if _pending.has(peer_id):
		_pending.erase(peer_id)
		_room.release_reservation(peer_id)
		room_changed.emit()
		return true
	var player: LobbyPlayer = _room.get_player_by_peer(peer_id)
	if player == null:
		return false
	var left_seat: int = player.seat
	var left_name: String = player.display_name
	_room.remove_player(player.profile_id)
	## 先发 player_left 再发 room_changed：UI 借「刷新前」的那一帧把离开的行淡出并播 PLAYERxx LEFT，
	## 播完（1.5s）才重画成 EMPTY SEAT。座位在 domain 侧已经立刻释放，这里只是呈现顺序。
	player_left.emit(left_name, left_seat)
	room_changed.emit()
	return true

func set_peer_character(peer_id: int, character_id: String) -> bool:
	if _room == null or _room.room_state != Room.RoomState.FORMING:
		return false
	var player: LobbyPlayer = _room.get_player_by_peer(peer_id)
	if player == null or player.is_host:
		return false
	## Guest 改角色 = Ready 失效（与本地改角同一规则），必须广播让所有客户端看到同一个 WAITING。
	_room.set_character(player.profile_id, character_id)
	room_changed.emit()
	_broadcast_ready(player.seat, player.ready)
	return true

func has_pending() -> bool:
	return not _pending.is_empty()

# ---- 开局 ----

func can_start() -> bool:
	return start_block_reason().is_empty()

## 空字符串 = 可以开。返回码供 UI 直接显示 / 测试断言。
func start_block_reason() -> String:
	if _room == null:
		return "no room"
	if _role == Role.GUEST:
		return "guest"
	if _room.room_state != Room.RoomState.FORMING:
		return _room.start_block_reason()
	if _networked:
		if not _is_network_ready():
			return "no peer"
		return _room.start_block_reason()
	# 离线 mock：假座位不上网也不参战，单人可直接用 Room 的种子开一局。
	# 有假座位在场时沿用同一套 ready / connection 校验，保证 start 条件仍可被验证。
	if _room.has_pending():
		return "pending"
	if _room.player_count() <= 1:
		return ""
	return _room.start_block_reason()

## 打通存档：把 Room 状态整理成 GameLaunch 信封（一次性交接），本方法不启动场景。
func start_match() -> bool:
	if not can_start():
		return false
	if _networked:
		_write_host_envelope()
		if _net != null and _net.is_server():
			_net.begin_match(_roster_characters(), _roster_peer_ids(), _room.loop_goal, _room.arena_id, int(_room.net_play))
	else:
		_write_offline_envelope()
	_room.room_state = Room.RoomState.STARTING
	match_started.emit()
	room_changed.emit()
	return true

func get_snapshot() -> Dictionary:
	if _room == null:
		return {
			"has_room": false,
			"role": int(Role.NONE),
			"networked": false,
			"offline": false,
			"player_count": 0,
			"occupied_count": 0,
			"max_players": Room.MAX_PLAYERS,
			"can_start": false,
			"start_block_reason": "no room",
			"local_profile_id": _local_profile_id,
			"local_seat": Room.NO_SEAT,
			"local_ready": false,
			"local_is_host": false,
			"seats": [],
		}
	var snapshot: Dictionary = _room.to_snapshot()
	snapshot["has_room"] = true
	snapshot["role"] = int(_role)
	snapshot["networked"] = _networked
	snapshot["offline"] = not _networked
	snapshot["local_profile_id"] = _local_profile_id
	snapshot["local_seat"] = get_local_seat()
	var local: LobbyPlayer = get_local_player()
	snapshot["local_ready"] = local.ready if local != null else false
	snapshot["local_is_host"] = local.is_host if local != null else false
	snapshot["can_start"] = can_start()
	snapshot["start_block_reason"] = start_block_reason()
	return snapshot

# ---- 信封 ----

## 真实 peer 背书：沿用 Day 78/85 的 Host 信封，座位表就是 Room 的座位表。
func _write_host_envelope() -> void:
	var character_ids: PackedStringArray = PackedStringArray()
	var peer_ids: PackedInt32Array = PackedInt32Array()
	character_ids.resize(GameLaunch.NET_MAX_SEATS)
	peer_ids.resize(GameLaunch.NET_MAX_SEATS)
	for player: LobbyPlayer in _room.get_players():
		var index: int = player.seat - 1
		if index < 0 or index >= GameLaunch.NET_MAX_SEATS:
			continue
		character_ids[index] = player.selected_character_id
		peer_ids[index] = maxi(player.peer_id, 0)
	GameLaunch.set_lan_roster(character_ids, peer_ids, _room.loop_goal)
	GameLaunch.set_local_seat(Room.HOST_SEAT)
	GameLaunch.set_net_role(GameLaunch.NetRole.HOST)
	GameLaunch.set_arena_id(_room.arena_id)
	GameLaunch.set_net_play(_room.net_play)

## 离线 mock：没有 peer，就没有 LAN 座位表可以开。用 Room 的种子走现有 Solo 信封
## （角色 / 目标 / 地图种子写进档，等于「用该档新开一局」）。假座位不参与本局。
func _write_offline_envelope() -> void:
	var host: LobbyPlayer = _room.get_player_in_seat(Room.HOST_SEAT)
	var character_id: String = host.selected_character_id if host != null else PlayerProfile.DEFAULT_CHARACTER
	var record: GameRecord = null
	if not _room.borrowed_record_id.is_empty():
		GameRecords.load_from_disk()
		record = GameRecords.get_record(_room.borrowed_record_id)
	if record == null:
		record = GameRecords.ensure_playable_record(character_id, _room.loop_goal, _room.arena_id)
	GameLaunch.set_active_record_id(record.id if record != null else "")
	GameLaunch.set_mode(GameLaunch.Mode.SOLO if _room.loop_goal > 0 else GameLaunch.Mode.INFINITE)
	GameLaunch.set_arena_id(_room.arena_id)
	GameLaunch.set_net_role(GameLaunch.NetRole.OFFLINE)
	GameLaunch.set_net_play(GameLaunch.NetPlay.COOP)
	GameLaunch.set_local_seat(Room.HOST_SEAT)
	GameLaunch.set_lan_roster(PackedStringArray(), PackedInt32Array(), 0)

func _is_network_ready() -> bool:
	for player: LobbyPlayer in _room.get_players():
		if player.seat == Room.HOST_SEAT:
			continue
		if player.peer_id <= 0:
			return false
	return true

# ---- 网络广播（Host 权威 → LobbyNet）----

func _roster_characters() -> PackedStringArray:
	var character_ids: PackedStringArray = PackedStringArray()
	character_ids.resize(GameLaunch.NET_MAX_SEATS)
	if _room == null:
		return character_ids
	for player: LobbyPlayer in _room.get_players():
		var index: int = player.seat - 1
		if index < 0 or index >= GameLaunch.NET_MAX_SEATS:
			continue
		character_ids[index] = player.selected_character_id
	return character_ids

func _roster_peer_ids() -> PackedInt32Array:
	var peer_ids: PackedInt32Array = PackedInt32Array()
	peer_ids.resize(GameLaunch.NET_MAX_SEATS)
	if _room == null:
		return peer_ids
	for player: LobbyPlayer in _room.get_players():
		var index: int = player.seat - 1
		if index < 0 or index >= GameLaunch.NET_MAX_SEATS:
			continue
		peer_ids[index] = maxi(player.peer_id, 0)
	return peer_ids

func _broadcast_roster() -> void:
	if _net != null and _net.is_server():
		_net.broadcast_roster(_roster_characters(), _roster_peer_ids())

func _broadcast_goal() -> void:
	if _net != null and _net.is_server() and _room != null:
		_net.broadcast_goal(_room.loop_goal)

func _broadcast_arena() -> void:
	if _net != null and _net.is_server() and _room != null:
		_net.broadcast_arena(_room.arena_id)

func _broadcast_mode() -> void:
	if _net != null and _net.is_server() and _room != null:
		_net.broadcast_mode(int(_room.net_play))

## Host 权威：广播单个座位的 Ready。
func _broadcast_ready(seat: int, ready: bool) -> void:
	if _net != null and _net.is_server():
		_net.broadcast_ready(seat, ready)

## Host 改了房间规则 / 有人改了角色之后，把每个 Guest 的权威 Ready 重播一遍（通常是 WAITING）。
## 不发这个，Guest 端的旧 READY 就会留在屏幕上，各端状态不一致。
func _broadcast_cleared_ready() -> void:
	if _net == null or not _net.is_server() or _room == null:
		return
	for player: LobbyPlayer in _room.get_players():
		if player.is_host:
			continue
		_net.broadcast_ready(player.seat, player.ready)

## 5 个座位的 Ready 位图（Host 端权威，用于新 Guest 的入房快照）。
func _ready_flags() -> PackedByteArray:
	var flags: PackedByteArray = PackedByteArray()
	flags.resize(GameLaunch.NET_MAX_SEATS)
	flags.fill(0)
	if _room == null:
		return flags
	for player: LobbyPlayer in _room.get_players():
		var index: int = player.seat - 1
		if index < 0 or index >= GameLaunch.NET_MAX_SEATS:
			continue
		flags[index] = 1 if player.ready else 0
	return flags

## Guest 侧信封：座位表来自 Host 广播的 roster，本地座位已落在 GameLaunch。
func _write_guest_envelope(loop_goal: int, arena_id: String, net_play: int) -> void:
	var character_ids: PackedStringArray = PackedStringArray()
	if _net != null:
		character_ids = _net.get_roster_characters()
	if character_ids.is_empty():
		character_ids.resize(GameLaunch.NET_MAX_SEATS)
	GameLaunch.set_lan_roster(character_ids, PackedInt32Array(), loop_goal)
	GameLaunch.set_net_role(GameLaunch.NetRole.GUEST)
	GameLaunch.set_arena_id(arena_id)
	GameLaunch.set_net_play(GameLaunch.NetPlay.BATTLE if net_play == int(GameLaunch.NetPlay.BATTLE) else GameLaunch.NetPlay.COOP)

func _mock_character_for(seat_hint: int) -> String:
	var ids: PackedStringArray = PlayerProfile.CHARACTER_IDS
	return str(ids[(maxi(seat_hint, 1) - 1) % ids.size()])

## pending / 刚握手的真实 peer 还不知道对方 profile_id：协议 5 不回传身份（不 bump 协议）。
## 先用 peer 占位 id，协议 6 的门票握手落地后由 LobbyNet 用真实 profile_id 覆盖。
func _pending_profile_id(peer_id: int) -> String:
	return "peer:%d" % peer_id
