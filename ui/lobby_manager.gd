extends Node
class_name LobbyManager

## 主菜单下的房间命令入口。不是 Autoload。本刀不碰 ENet。
signal room_changed(room: Variant)

const DEFAULT_ARENA := "yard"
const DEFAULT_LOOP: int = 20
const HOST_PEER_ID: int = 1
const KEY_CHARACTERS := "character_ids"
const KEY_PEERS := "peer_ids"
const KEY_LOOP := "loop_goal"
const KEY_ARENA := "arena_id"
const KEY_PLAY := "net_play"
const KEY_SEAT := "local_seat"
const KEY_ROLE := "net_role"
const KEY_ADDRESS := "join_address"
const ROOM_ID_BYTES: int = 16

var _room: Room = null

func has_room() -> bool:
	return _room != null

func get_room() -> Room:
	return _room

func create_room() -> bool:
	if _room != null:
		return false
	PlayerProfile.load_from_disk()
	_room = _make_room()
	if not _room.insert_player(_make_host_player()):
		_room = null
		return false
	_emit()
	return true

func close_room() -> void:
	if _room == null:
		return
	_room = null
	_emit()

func seed_from_record(record_id: String) -> bool:
	if not _can_seed():
		return false
	GameRecords.load_from_disk()
	var record: GameRecord = GameRecords.get_record(record_id)
	if record == null:
		return false
	var host: LobbyPlayer = _room.player_at(Room.HOST_SEAT)
	if host == null:
		return false
	host.selected_character_id = GameLaunch._sanitize_character_id(record.character_id)
	_room.arena_id = GameLaunch._sanitize_arena_id(record.arena_id)
	_room.loop_goal = maxi(record.loop_goal, 0)
	_room.borrowed_record_id = record.id
	_emit()
	return true

func set_character(character_id: String) -> bool:
	if not _can_edit_seeded():
		return false
	var host: LobbyPlayer = _room.player_at(Room.HOST_SEAT)
	if host == null:
		return false
	host.selected_character_id = GameLaunch._sanitize_character_id(character_id)
	_emit()
	return true

func set_arena(arena_id: String) -> bool:
	if not _can_edit_seeded():
		return false
	_room.arena_id = GameLaunch._sanitize_arena_id(arena_id)
	_emit()
	return true

func set_loop_goal(goal: int) -> bool:
	if not _can_edit_seeded():
		return false
	_room.loop_goal = maxi(goal, 0)
	_emit()
	return true

func set_net_play(play: GameLaunch.NetPlay) -> bool:
	if _room == null or not _room.is_open():
		return false
	_room.net_play = play
	_emit()
	return true

## 调试用。正式界面不得调用。假客人直接 CONNECTED，peer_id = 1000 + seat。
func add_mock_guest() -> int:
	if _room == null or not _room.is_open():
		return 0
	var seat: int = _room.lowest_empty_guest_seat()
	if seat < Room.FIRST_GUEST_SEAT:
		return 0
	var player: LobbyPlayer = _make_guest(seat, LobbyPlayer.MOCK_PEER_BASE + seat, "Player %d" % seat, "boar")
	player.connection_state = LobbyPlayer.ConnectionState.CONNECTED
	if not _room.insert_player(player):
		return 0
	_emit()
	return seat

func remove_mock_guest(seat: int) -> bool:
	if _room == null or not _room.is_open():
		return false
	var player: LobbyPlayer = _room.player_at(seat)
	if player == null or not player.is_mock():
		return false
	if not _room.remove_seat(seat):
		return false
	_emit()
	return true

func occupy_remote(peer_id: int, character_id: String) -> int:
	if _room == null or not _room.is_open() or peer_id <= HOST_PEER_ID:
		return 0
	var existing: LobbyPlayer = _room.player_for_peer(peer_id)
	if existing != null:
		return existing.seat
	var seat: int = _room.lowest_empty_guest_seat()
	if seat < Room.FIRST_GUEST_SEAT:
		return 0
	var player: LobbyPlayer = _make_guest(seat, peer_id, "Player %d" % seat, character_id)
	player.connection_state = LobbyPlayer.ConnectionState.CONNECTING
	if not _room.insert_player(player):
		return 0
	_emit()
	return seat

func mark_connected(peer_id: int) -> bool:
	if _room == null or not _room.is_open():
		return false
	var player: LobbyPlayer = _room.player_for_peer(peer_id)
	if player == null or player.is_host:
		return false
	player.connection_state = LobbyPlayer.ConnectionState.CONNECTED
	_emit()
	return true

func vacate_peer(peer_id: int) -> bool:
	if _room == null or not _room.is_open():
		return false
	var player: LobbyPlayer = _room.player_for_peer(peer_id)
	if player == null or player.is_host or player.is_mock():
		return false
	if not _room.remove_seat(player.seat):
		return false
	_emit()
	return true

func set_remote_character(peer_id: int, character_id: String) -> bool:
	if _room == null or not _room.is_open():
		return false
	var player: LobbyPlayer = _room.player_for_peer(peer_id)
	if player == null or player.is_host:
		return false
	player.selected_character_id = GameLaunch._sanitize_character_id(character_id)
	_emit()
	return true

func make_launch() -> Dictionary:
	if _room == null or not _room.is_open() or not _room.all_seated_ready():
		return {}
	return {
		KEY_CHARACTERS: _room.roster_characters(),
		KEY_PEERS: _room.roster_peers(),
		KEY_LOOP: _room.loop_goal,
		KEY_ARENA: _room.arena_id,
		KEY_PLAY: int(_room.net_play),
		KEY_SEAT: Room.HOST_SEAT,
		KEY_ROLE: int(GameLaunch.NetRole.HOST),
		KEY_ADDRESS: "",
	}

func commit_launch(launch: Dictionary) -> bool:
	if launch.is_empty():
		return false
	var characters: PackedStringArray = launch.get(KEY_CHARACTERS, PackedStringArray())
	var peers: PackedInt32Array = launch.get(KEY_PEERS, PackedInt32Array())
	GameLaunch.set_lan_roster(characters, peers, int(launch.get(KEY_LOOP, 0)))
	GameLaunch.set_local_seat(int(launch.get(KEY_SEAT, Room.HOST_SEAT)))
	GameLaunch.set_net_role(_role_from_value(int(launch.get(KEY_ROLE, GameLaunch.NetRole.OFFLINE))))
	GameLaunch.set_arena_id(str(launch.get(KEY_ARENA, DEFAULT_ARENA)))
	GameLaunch.set_net_play(_play_from_value(int(launch.get(KEY_PLAY, GameLaunch.NetPlay.COOP))))
	_apply_join_address(str(launch.get(KEY_ADDRESS, "")))
	_mark_host_starting(int(launch.get(KEY_ROLE, GameLaunch.NetRole.OFFLINE)))
	return true

func _make_room() -> Room:
	var room: Room = Room.new()
	room.room_id = _make_room_id()
	room.host_profile_id = PlayerProfile.get_profile_id()
	room.host_display_name = PlayerProfile.get_display_name()
	room.max_players = GameLaunch.NET_MAX_SEATS
	room.arena_id = DEFAULT_ARENA
	room.net_play = GameLaunch.NetPlay.COOP
	room.loop_goal = DEFAULT_LOOP
	room.privacy = Room.Privacy.LAN_VISIBLE
	room.room_state = Room.RoomState.OPEN
	room.borrowed_record_id = ""
	room.invite = null
	return room

func _make_host_player() -> LobbyPlayer:
	var player: LobbyPlayer = LobbyPlayer.new()
	player.profile_id = PlayerProfile.get_profile_id()
	player.display_name = PlayerProfile.get_display_name()
	player.avatar_id = PlayerProfile.get_avatar_id()
	player.peer_id = HOST_PEER_ID
	player.seat = Room.HOST_SEAT
	player.selected_character_id = GameLaunch._sanitize_character_id(PlayerProfile.get_preferred_character_id())
	player.ready = true
	player.connection_state = LobbyPlayer.ConnectionState.CONNECTED
	player.is_host = true
	player.path = LobbyPlayer.PATH_LAN_IPV4
	player.rtt_ms = 0
	return player

func _make_guest(seat: int, peer_id: int, display_name: String, character_id: String) -> LobbyPlayer:
	var player: LobbyPlayer = LobbyPlayer.new()
	player.profile_id = ""
	player.display_name = display_name
	player.avatar_id = "boar"
	player.peer_id = peer_id
	player.seat = seat
	player.selected_character_id = GameLaunch._sanitize_character_id(character_id)
	player.ready = true
	player.connection_state = LobbyPlayer.ConnectionState.CONNECTED
	player.is_host = false
	player.path = LobbyPlayer.PATH_LAN_IPV4
	player.rtt_ms = 0
	return player

func _can_seed() -> bool:
	if _room == null or not _room.is_open():
		return false
	return _room.borrowed_record_id.is_empty()

func _can_edit_seeded() -> bool:
	if _room == null or not _room.is_open():
		return false
	return not _room.is_borrow_locked()

func _apply_join_address(address: String) -> void:
	if address.is_empty():
		return
	GameLaunch.set_join_address(address)

func _mark_host_starting(role: int) -> void:
	if _room == null or role != int(GameLaunch.NetRole.HOST):
		return
	_room.room_state = Room.RoomState.STARTING
	_emit()

func _emit() -> void:
	room_changed.emit(_room)

func _make_room_id() -> String:
	var crypto: Crypto = Crypto.new()
	return crypto.generate_random_bytes(ROOM_ID_BYTES).hex_encode()

func _play_from_value(value: int) -> GameLaunch.NetPlay:
	if value == int(GameLaunch.NetPlay.BATTLE):
		return GameLaunch.NetPlay.BATTLE
	return GameLaunch.NetPlay.COOP

func _role_from_value(value: int) -> GameLaunch.NetRole:
	if value == int(GameLaunch.NetRole.GUEST):
		return GameLaunch.NetRole.GUEST
	if value == int(GameLaunch.NetRole.HOST):
		return GameLaunch.NetRole.HOST
	return GameLaunch.NetRole.OFFLINE
