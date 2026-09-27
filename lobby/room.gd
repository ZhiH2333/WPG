extends RefCounted
class_name Room

## 房间身份与状态（docs/ui_lobby_architecture.md §3.4）。RefCounted 域对象：
## 不依赖 SceneTree 即可构造，不处理 socket，不碰 UI，不负责真正的 ENet 通信。
##
## 座位合同（沿用 Day 78）：seat 1 = Host，seat 2..5 = Guest，上限 5。号不前挪：
## 有人离开只释放他自己的座位，其余人的号不动。满员才拒（over capacity 直接拒绝，不踢人）。
##
## pending（已连上但握手未完成）不进 players，只占 reservation；认证失败就释放 reservation，
## occupied 不变。players 始终按 seat 升序且只含已入座的人。

const MAX_PLAYERS: int = GameLaunch.NET_MAX_SEATS
const MIN_PLAYERS: int = 2
const HOST_SEAT: int = LobbyPlayer.HOST_SEAT
const NO_SEAT: int = LobbyPlayer.NO_SEAT

const ARENA_CATALOG: ArenaCatalog = preload("res://data/arena_catalog.tres")

enum Privacy { LAN_VISIBLE, INVITE_ONLY }
enum RoomState { FORMING, STARTING, CLOSED }
enum AddResult { ADDED, FULL, DUPLICATE_PROFILE, DUPLICATE_PEER, BAD_SEAT, CLOSED, INVALID }

var room_id: String = ""
var host_profile_id: String = ""
var host_display_name: String = ""
var max_players: int = MAX_PLAYERS
var arena_id: String = ARENA_CATALOG.DEFAULT_ID
var net_play: GameLaunch.NetPlay = GameLaunch.NetPlay.COOP
var loop_goal: int = 0
var privacy: Privacy = Privacy.LAN_VISIBLE
var room_state: RoomState = RoomState.FORMING
## Phase 8 的 JoinInvite 连接信息（lan/wan/ip6/token）。本阶段留空；它不是 Room 主键。
var invite: Dictionary = {}
## 仅 Host 本地：借档开房时记下档 id，只用来种子 arena / loop / 角色，档本身不上网、不写网。
var borrowed_record_id: String = ""

var _players: Array[LobbyPlayer] = []
## seat(int) -> peer_id(int)：pending peer 的占位，尚未进 _players。
var _reserved: Dictionary = {}

static func create(host_player: LobbyPlayer, arena_id: String = ARENA_CATALOG.DEFAULT_ID, net_play: GameLaunch.NetPlay = GameLaunch.NetPlay.COOP, loop_goal: int = 0, borrowed_record_id: String = "") -> Room:
	var room: Room = Room.new()
	room.room_id = _make_room_id()
	room.arena_id = ARENA_CATALOG.sanitize(arena_id)
	room.net_play = net_play
	room.loop_goal = maxi(loop_goal, 0)
	room.borrowed_record_id = borrowed_record_id
	if host_player != null:
		host_player.seat = HOST_SEAT
		room.add_player(host_player, HOST_SEAT)
	return room

# ---- 读 ----

func player_count() -> int:
	return _players.size()

func occupied_count() -> int:
	return _players.size() + _reserved.size()

func is_full() -> bool:
	return occupied_count() >= max_players

func is_closed() -> bool:
	return room_state == RoomState.CLOSED

func get_players() -> Array[LobbyPlayer]:
	return _players.duplicate()

func get_player(profile_id: String) -> LobbyPlayer:
	for player: LobbyPlayer in _players:
		if player.profile_id == profile_id:
			return player
	return null

func get_player_by_peer(peer_id: int) -> LobbyPlayer:
	if peer_id <= 0:
		return null
	for player: LobbyPlayer in _players:
		if player.peer_id == peer_id:
			return player
	return null

func get_player_in_seat(seat: int) -> LobbyPlayer:
	for player: LobbyPlayer in _players:
		if player.seat == seat:
			return player
	return null

func seat_of(profile_id: String) -> int:
	var player: LobbyPlayer = get_player(profile_id)
	return player.seat if player != null else NO_SEAT

func free_seats() -> PackedInt32Array:
	var seats: PackedInt32Array = PackedInt32Array()
	for seat: int in range(HOST_SEAT, max_players + 1):
		if _is_seat_free(seat):
			seats.append(seat)
	return seats

func has_pending() -> bool:
	return not _reserved.is_empty()

func pending_count() -> int:
	return _reserved.size()

func pending_seat_of(peer_id: int) -> int:
	for seat: int in _reserved:
		if int(_reserved[seat]) == peer_id:
			return int(seat)
	return NO_SEAT

## UI / LobbyNet 只读投影：5 个座位槽，pending 渲染成 CONNECTING。
func to_snapshot() -> Dictionary:
	var seats: Array = []
	for seat: int in range(HOST_SEAT, max_players + 1):
		var player: LobbyPlayer = get_player_in_seat(seat)
		if player != null:
			var entry: Dictionary = player.to_dict()
			entry["occupied"] = true
			entry["pending"] = false
			seats.append(entry)
			continue
		if _reserved.has(seat):
			seats.append({
				"occupied": true,
				"pending": true,
				"seat": seat,
				"profile_id": "",
				"display_name": "",
				"avatar_id": "",
				"selected_character_id": "",
				"ready": false,
				"connection_state": int(LobbyPlayer.ConnectionState.CONNECTING),
				"is_host": false,
				"peer_id": int(_reserved[seat]),
				"rtt_ms": 0,
			})
			continue
		seats.append({"occupied": false, "pending": false, "seat": seat})
	return {
		"room_id": room_id,
		"host_profile_id": host_profile_id,
		"host_display_name": host_display_name,
		"max_players": max_players,
		"arena_id": arena_id,
		"net_play": int(net_play),
		"loop_goal": loop_goal,
		"privacy": int(privacy),
		"room_state": int(room_state),
		"borrowed_record_id": borrowed_record_id,
		"player_count": player_count(),
		"occupied_count": occupied_count(),
		"pending_count": pending_count(),
		"seats": seats,
	}

# ---- 座位分配 / 释放 ----

## preferred_seat = 0 时取最小空位；指定座位时必须仍空（同 peer 自己的 reservation 视为空）。
func add_player(player: LobbyPlayer, preferred_seat: int = NO_SEAT) -> AddResult:
	if is_closed():
		return AddResult.CLOSED
	if player == null or player.profile_id.is_empty():
		return AddResult.INVALID
	if get_player(player.profile_id) != null:
		return AddResult.DUPLICATE_PROFILE
	if player.peer_id > 0 and get_player_by_peer(player.peer_id) != null:
		return AddResult.DUPLICATE_PEER
	if _players.size() >= max_players:
		return AddResult.FULL
	var seat: int = _resolve_seat(preferred_seat, player.peer_id)
	if seat == NO_SEAT:
		return AddResult.BAD_SEAT
	player.seat = seat
	player.is_host = seat == HOST_SEAT
	_players.append(player)
	_reserved.erase(seat)
	if player.is_host:
		_set_host_fields(player)
	_sort_players()
	return AddResult.ADDED

## Host 离房：1.0 不做 Host 迁移，房间直接关闭（Guest 侧对应 Host closed 文案）。
## 其余人离房只释放自己的座位，别人的号不动。
func remove_player(profile_id: String) -> bool:
	var player: LobbyPlayer = get_player(profile_id)
	if player == null:
		return false
	if player.is_host or player.seat == HOST_SEAT:
		close()
		return true
	_players.erase(player)
	player.seat = NO_SEAT
	player.is_host = false
	return true

func set_ready(profile_id: String, ready: bool) -> bool:
	var player: LobbyPlayer = get_player(profile_id)
	if player == null:
		return false
	player.ready = ready
	return true

func set_character(profile_id: String, character_id: String) -> bool:
	var player: LobbyPlayer = get_player(profile_id)
	if player == null:
		return false
	player.selected_character_id = PlayerProfile.sanitize_character_id(character_id)
	return true

## Host 标记重设（快照同步用；1.0 不做 Host 迁移，真正的换主在 Phase 7 之后）。
func set_host(profile_id: String) -> bool:
	var player: LobbyPlayer = get_player(profile_id)
	if player == null or player.seat != HOST_SEAT:
		return false
	for entry: LobbyPlayer in _players:
		entry.is_host = entry == player
	_set_host_fields(player)
	return true

func set_arena_id(value: String) -> void:
	arena_id = ARENA_CATALOG.sanitize(value)

func set_loop_goal(value: int) -> void:
	loop_goal = maxi(value, 0)

## pending peer 占位：peer_connected 立刻占座（Day 78），握手完成才进 players。
func reserve_seat(peer_id: int) -> int:
	if is_closed() or peer_id <= 0:
		return NO_SEAT
	var seated: LobbyPlayer = get_player_by_peer(peer_id)
	if seated != null:
		return seated.seat
	var existing: int = pending_seat_of(peer_id)
	if existing != NO_SEAT:
		return existing
	var seat: int = _lowest_free_guest_seat()
	if seat == NO_SEAT:
		return NO_SEAT
	_reserved[seat] = peer_id
	return seat

func release_reservation(peer_id: int) -> bool:
	var seat: int = pending_seat_of(peer_id)
	if seat == NO_SEAT:
		return false
	_reserved.erase(seat)
	return true

## 关闭房间：清空所有座位与占位，保留房间身份（room_id / host 名）供 UI 显示 Host closed。
func close() -> void:
	room_state = RoomState.CLOSED
	for player: LobbyPlayer in _players:
		player.seat = NO_SEAT
		player.is_host = false
	_players.clear()
	_reserved.clear()

# ---- 开局条件 ----

## Host 的 Start 合同：2..5 人、无 pending、Host 在位、Guest 全部 CONNECTED 且 ready。
## Host 自己的 ready 不参与判定（Host 按 Start 就是同意开局）。离线单人的始发条件由 LobbyManager 决定。
func can_start() -> bool:
	return start_block_reason().is_empty()

## 空字符串 = 可以开。返回码供 UI / 测试直接断言。
func start_block_reason() -> String:
	if is_closed():
		return "closed"
	if room_state == RoomState.STARTING:
		return "started"
	if has_pending():
		return "pending"
	var count: int = player_count()
	if count < MIN_PLAYERS:
		return "need %d" % MIN_PLAYERS
	if count > max_players or occupied_count() > max_players:
		return "full"
	if get_player_in_seat(HOST_SEAT) == null:
		return "no host"
	for player: LobbyPlayer in _players:
		if player.seat == HOST_SEAT:
			continue
		if player.connection_state != LobbyPlayer.ConnectionState.CONNECTED:
			return "connecting"
		if not player.ready:
			return "not ready"
	return ""

# ---- 内部 ----

func _resolve_seat(preferred_seat: int, peer_id: int) -> int:
	if preferred_seat == NO_SEAT:
		for seat: int in range(HOST_SEAT, max_players + 1):
			if _is_seat_free(seat):
				return seat
		return NO_SEAT
	if preferred_seat < HOST_SEAT or preferred_seat > max_players:
		return NO_SEAT
	if not _is_seat_free(preferred_seat) and not _is_own_reservation(preferred_seat, peer_id):
		return NO_SEAT
	return preferred_seat

func _is_seat_free(seat: int) -> bool:
	if _reserved.has(seat):
		return false
	return get_player_in_seat(seat) == null

func _is_own_reservation(seat: int, peer_id: int) -> bool:
	if peer_id <= 0 or not _reserved.has(seat):
		return false
	return int(_reserved[seat]) == peer_id

func _lowest_free_guest_seat() -> int:
	for seat: int in range(HOST_SEAT + 1, max_players + 1):
		if _is_seat_free(seat):
			return seat
	return NO_SEAT

func _sort_players() -> void:
	_players.sort_custom(func(a: LobbyPlayer, b: LobbyPlayer) -> bool: return a.seat < b.seat)

func _set_host_fields(player: LobbyPlayer) -> void:
	host_profile_id = player.profile_id
	host_display_name = player.display_name

static func _make_room_id() -> String:
	return Crypto.new().generate_random_bytes(4).hex_encode()
