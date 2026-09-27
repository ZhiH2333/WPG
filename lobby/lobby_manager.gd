extends Node
class_name LobbyManager

## Lobby domain 的唯一状态机与唯一命令入口（docs/ui_lobby_architecture.md §4）。
## 挂在 MainMenu 下，不是 Autoload；不碰 ENet API，不创建第二个 multiplayer_peer，
## 不建连 / 不关连（那是 Phase 7 的 LobbyNet），也不直接改 UI。
##
## 本阶段只有离线 mock：Room + LobbyPlayer 在本机自转，真实 peer 事件由 LanOverlay 转发进来，
## Start 把状态写成 GameLaunch 信封交给现有换场流程。Phase 7 接 LobbyNet 时替换命令执行者，
## GameLaunch 与 UI 都不用大改。

## 房间内容或状态变化，UI 重新拉一次 snapshot。
signal room_changed
## 房间结束（Host 离房 / 主动关房），UI 回多人大厅。
signal room_closed
## start_match() 已经写好 GameLaunch 信封。
signal match_started

enum Role { NONE, HOST, GUEST }

var _room: Room = null
var _role: Role = Role.NONE
## true = 房间有真实 ENet peer 背书（LanOverlay bind 成功）；false = 离线 mock。
var _networked: bool = false
## peer_id -> LobbyPlayer（CONNECTING，seat 0）。pending 不进 Room.players（架构 §4）。
var _pending: Dictionary = {}
var _local_profile_id: String = ""
## 离线 mock 造的假座位 profile_id，只用于本机移除，永不上网。
var _mock_ids: Array[String] = []
var _mock_seq: int = 0

func _exit_tree() -> void:
	_room = null
	_pending.clear()

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
	var changed: bool = _room.set_ready(profile_id, ready)
	if changed:
		room_changed.emit()
	return changed

func set_character(profile_id: String, character_id: String) -> bool:
	if _room == null:
		return false
	var changed: bool = _room.set_character(profile_id, character_id)
	if changed:
		room_changed.emit()
	return changed

func set_local_character(character_id: String) -> bool:
	return set_character(_local_profile_id, character_id)

func set_host(profile_id: String) -> bool:
	if _room == null:
		return false
	var changed: bool = _room.set_host(profile_id)
	if changed:
		room_changed.emit()
	return changed

func set_arena_id(arena_id: String) -> void:
	if _room == null:
		return
	_room.set_arena_id(arena_id)
	room_changed.emit()

func set_net_play(net_play: GameLaunch.NetPlay) -> void:
	if _room == null:
		return
	_room.net_play = net_play
	room_changed.emit()

func set_loop_goal(loop_goal: int) -> void:
	if _room == null:
		return
	_room.set_loop_goal(loop_goal)
	room_changed.emit()

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
	player.ready = true
	if _room.add_player(player, seat) != Room.AddResult.ADDED:
		return Room.NO_SEAT
	_pending.erase(peer_id)
	room_changed.emit()
	return seat

## 连接断开：pending 释放占位，已入座的移除。不影响别人座位号。
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
	_room.remove_player(player.profile_id)
	room_changed.emit()
	return true

func set_peer_character(peer_id: int, character_id: String) -> bool:
	if _room == null:
		return false
	var player: LobbyPlayer = _room.get_player_by_peer(peer_id)
	if player == null:
		return false
	player.set_selected_character_id(character_id)
	room_changed.emit()
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
			"seats": [],
		}
	var snapshot: Dictionary = _room.to_snapshot()
	snapshot["has_room"] = true
	snapshot["role"] = int(_role)
	snapshot["networked"] = _networked
	snapshot["offline"] = not _networked
	snapshot["local_profile_id"] = _local_profile_id
	snapshot["local_seat"] = get_local_seat()
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

func _mock_character_for(seat_hint: int) -> String:
	var ids: PackedStringArray = PlayerProfile.CHARACTER_IDS
	return str(ids[(maxi(seat_hint, 1) - 1) % ids.size()])

## pending / 刚握手的真实 peer 还不知道对方 profile_id：协议 5 不回传身份（不 bump 协议）。
## 先用 peer 占位 id，协议 6 的门票握手落地后由 LobbyNet 用真实 profile_id 覆盖。
func _pending_profile_id(peer_id: int) -> String:
	return "peer:%d" % peer_id
