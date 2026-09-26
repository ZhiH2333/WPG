extends SceneTree

## 调试脚本。假人进出、借档锁定、开战信封都走 LobbyManager，不打开玩家界面上的测试按钮。
const RECORDS_PATH := "user://records.json"

var _seed_record: GameRecord = null

func _initialize() -> void:
	var packed: PackedScene = load("res://ui/main_menu.tscn") as PackedScene
	if packed == null:
		_fail("menu load")
		return
	var menu: Node = packed.instantiate()
	root.add_child(menu)
	if not _scene_ok(menu):
		return
	var lobby: LobbyManager = menu.get_node("LobbyManager") as LobbyManager
	if not _run_domain(lobby):
		return
	if _live_peer() != null:
		_fail("peer after offline")
		return
	print("PROBE_OK")
	quit(0)

func _scene_ok(menu: Node) -> bool:
	if menu.get_node_or_null("LobbyManager") == null:
		_fail("missing manager")
		return false
	var lan: Node = menu.get_node_or_null("LanOverlay")
	if lan == null:
		_fail("missing lan")
		return false
	if lan.get_node_or_null("Center/Panel/Column/Content/JoinRoot/Row/Browse/Offline") != null:
		_fail("offline button")
		return false
	if lan.get_node_or_null("Center/Panel/Column/Content/OfflineRoot") != null:
		_fail("offline panel")
		return false
	if lan.get_node_or_null("Center/Panel/Column/Content/HostRoot/Center/Column/SeatWall") != null:
		_fail("seat wall")
		return false
	if _live_peer() != null:
		_fail("peer at load")
		return false
	for property: Dictionary in ProjectSettings.get_property_list():
		if str(property.get("name", "")).begins_with("autoload/"):
			_fail("autoload")
			return false
	return true

func _run_domain(lobby: LobbyManager) -> bool:
	lobby.close_room()
	if not lobby.create_room() or lobby.create_room():
		_fail("create")
		return false
	if not _host_ok(lobby.get_room()):
		return false
	if not lobby.make_launch().is_empty():
		_fail("solo launch")
		return false
	if not _check_shift(lobby) or not _check_full(lobby) or not _check_seed(lobby) or not _check_launch(lobby):
		return false
	return _check_remote(lobby)

func _host_ok(room: Room) -> bool:
	if room == null or room.invite != null or room.max_players != GameLaunch.NET_MAX_SEATS:
		_fail("room shape")
		return false
	var host: LobbyPlayer = room.player_at(Room.HOST_SEAT)
	if host == null or not host.is_host or host.peer_id != LobbyManager.HOST_PEER_ID or host.seat != Room.HOST_SEAT:
		_fail("host player")
		return false
	if host.profile_id.is_empty() or host.profile_id == str(host.peer_id) or not host.ready or not host.has_joined():
		_fail("profile")
		return false
	return true

func _check_shift(lobby: LobbyManager) -> bool:
	if lobby.add_mock_guest() != 2 or lobby.add_mock_guest() != 3:
		_fail("add seats")
		return false
	var kept: int = lobby.get_room().player_at(3).peer_id
	if not lobby.remove_mock_guest(2) or lobby.get_room().player_at(2) != null:
		_fail("vacate")
		return false
	if lobby.get_room().player_at(3).peer_id != kept or lobby.add_mock_guest() != 2:
		_fail("shift")
		return false
	if lobby.get_room().player_at(3).peer_id != kept or lobby.remove_mock_guest(Room.HOST_SEAT):
		_fail("seat 3 moved")
		return false
	return true

func _check_full(lobby: LobbyManager) -> bool:
	if lobby.add_mock_guest() != 4 or lobby.add_mock_guest() != 5 or lobby.add_mock_guest() != 0:
		_fail("full")
		return false
	var tail: int = lobby.get_room().player_at(5).peer_id
	if not lobby.remove_mock_guest(4) or lobby.add_mock_guest() != 4 or lobby.get_room().player_at(5).peer_id != tail:
		_fail("refill")
		return false
	return true

func _check_seed(lobby: LobbyManager) -> bool:
	var existed: bool = FileAccess.file_exists(RECORDS_PATH)
	var before: String = FileAccess.get_file_as_string(RECORDS_PATH) if existed else ""
	var created: bool = _ensure_probe_record()
	if _seed_record == null:
		_fail("no record")
		return false
	var snapshot: String = FileAccess.get_file_as_string(RECORDS_PATH)
	if not lobby.seed_from_record(_seed_record.id):
		_restore_records(existed, before, created)
		_fail("seed")
		return false
	if FileAccess.get_file_as_string(RECORDS_PATH) != snapshot:
		_restore_records(existed, before, created)
		_fail("records rewritten")
		return false
	if lobby.set_arena("yard") or lobby.set_character("boar") or lobby.set_loop_goal(1):
		_restore_records(existed, before, created)
		_fail("lock")
		return false
	var host: LobbyPlayer = lobby.get_room().player_at(Room.HOST_SEAT)
	if host.selected_character_id != _seed_record.character_id:
		_restore_records(existed, before, created)
		_fail("seed character")
		return false
	if lobby.get_room().arena_id != _seed_record.arena_id or lobby.get_room().loop_goal != _seed_record.loop_goal:
		_restore_records(existed, before, created)
		_fail("seed rules")
		return false
	_restore_records(existed, before, created)
	return true

func _ensure_probe_record() -> bool:
	GameRecords.load_from_disk()
	var records: Array[GameRecord] = GameRecords.list_records()
	if not records.is_empty():
		_seed_record = records[records.size() - 1]
		return false
	_seed_record = GameRecords.create_record("probe", "chicken", 7, "pit")
	return _seed_record != null

func _restore_records(existed: bool, before: String, created: bool) -> void:
	if not created:
		return
	if not existed:
		var dir: DirAccess = DirAccess.open("user://")
		if dir != null:
			dir.remove("records.json")
		return
	var file: FileAccess = FileAccess.open(RECORDS_PATH, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(before)
	file.close()

func _check_launch(lobby: LobbyManager) -> bool:
	var launch: Dictionary = lobby.make_launch()
	if launch.is_empty() or not lobby.commit_launch(launch):
		_fail("commit")
		return false
	if not _launch_matches(launch):
		return false
	if lobby.add_mock_guest() != 0:
		_fail("start still open")
		return false
	if GameLaunch.take_net_role() != GameLaunch.NetRole.OFFLINE:
		_fail("envelope left set")
		return false
	lobby.close_room()
	return true

func _launch_matches(launch: Dictionary) -> bool:
	var characters: PackedStringArray = launch[LobbyManager.KEY_CHARACTERS]
	var peers: PackedInt32Array = launch[LobbyManager.KEY_PEERS]
	if int(launch[LobbyManager.KEY_ROLE]) != int(GameLaunch.NetRole.HOST) or int(launch[LobbyManager.KEY_SEAT]) != Room.HOST_SEAT:
		_fail("role")
		return false
	if str(launch[LobbyManager.KEY_ARENA]) != _seed_record.arena_id or int(launch[LobbyManager.KEY_LOOP]) != _seed_record.loop_goal:
		_fail("envelope rules")
		return false
	if characters[0] != _seed_record.character_id or peers[0] != LobbyManager.HOST_PEER_ID or peers[1] != LobbyPlayer.MOCK_PEER_BASE + 2:
		_fail("roster")
		return false
	var role: GameLaunch.NetRole = GameLaunch.take_net_role()
	var seat: int = GameLaunch.take_local_seat()
	var roster: Dictionary = GameLaunch.take_lan_roster()
	var arena: String = GameLaunch.take_arena_id()
	var play: GameLaunch.NetPlay = GameLaunch.take_net_play()
	if role != GameLaunch.NetRole.HOST or seat != Room.HOST_SEAT or arena != _seed_record.arena_id:
		_fail("taken envelope")
		return false
	if int(play) != int(launch[LobbyManager.KEY_PLAY]) or int(roster["loop_goal"]) != _seed_record.loop_goal:
		_fail("taken roster")
		return false
	return true

func _check_remote(lobby: LobbyManager) -> bool:
	if not lobby.create_room() or lobby.occupy_remote(42, "chicken") != 2:
		_fail("occupy")
		return false
	var guest: LobbyPlayer = lobby.get_room().player_at(2)
	if guest == null or guest.has_joined() or guest.is_mock() or not lobby.make_launch().is_empty():
		_fail("connecting")
		return false
	if not lobby.mark_connected(42) or lobby.make_launch().is_empty():
		_fail("connected launch")
		return false
	if not lobby.vacate_peer(42) or lobby.get_room().player_at(2) != null or lobby.occupy_remote(77, "boar") != 2:
		_fail("reuse seat")
		return false
	lobby.close_room()
	return true

func _live_peer() -> ENetMultiplayerPeer:
	var api: MultiplayerAPI = root.get_multiplayer()
	if api == null or not (api.multiplayer_peer is ENetMultiplayerPeer):
		return null
	return api.multiplayer_peer as ENetMultiplayerPeer

func _fail(reason: String) -> void:
	push_error("lobby probe: %s" % reason)
	quit(1)
