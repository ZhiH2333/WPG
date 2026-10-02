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

## Guest 连 Host。
func join_room_address(address: String) -> bool:
	if _net == null:
		return false
	return _net.client_connect(address)

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
		_net.send_hello(peer_id)

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
	# Guest 连上 Host，发自己的角色。
	if _net != null:
		var local: LobbyPlayer = get_local_player()
		var character_id: String = local.selected_character_id if local != null else PlayerProfile.get_preferred_character_id()
		_net.send_guest_character(character_id)

func _on_net_seat_assigned(seat: int) -> void:
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
	_networked = false
	room_changed.emit()
	network_failed.emit("refused")

func _on_net_version_mismatch() -> void:
	_networked = false
	network_failed.emit("Version mismatch")

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
