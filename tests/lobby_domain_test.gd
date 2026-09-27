extends SceneTree

## Lobby domain 回归（Phase 3）：LobbyPlayer / Room / LobbyManager → GameLaunch 信封。
## 全程离线，不 bind 17777、不碰 ENet；假座位由 LobbyManager 生成。
## 跑法：godot --headless --path . --script res://tests/lobby_domain_test.gd --quit
## 通过输出 LOBBY_DOMAIN_OK；失败逐条 LOBBY_DOMAIN_FAIL 并返回非 0。
##
## 离线开局会走 GameRecords.ensure_playable_record（等同 Solo 的「用该档新开一局」），
## 因此测试前备份 user://records.json，结束后原样还原（原本没有就删掉）。

const RECORDS_FILE := "user://records.json"

var _failures: PackedStringArray = PackedStringArray()

func _initialize() -> void:
	var records_backup: Variant = _backup_records()
	PlayerProfile.load_from_disk()
	_case_profile_copy_is_one_way()
	_case_create_room_and_single_player_gate()
	_case_seat_allocation_and_release()
	_case_duplicate_and_capacity()
	_case_ready_and_character()
	_case_host_leave_closes_room()
	_case_pending_reservation()
	_case_manager_offline_solo_start()
	_case_manager_mock_roster()
	_case_manager_lan_bridge()
	_restore_records(records_backup)
	if _failures.is_empty():
		print("LOBBY_DOMAIN_OK")
		quit(0)
		return
	for failure: String in _failures:
		printerr("LOBBY_DOMAIN_FAIL: %s" % failure)
	quit(1)

# ---- 用例 ----

func _case_profile_copy_is_one_way() -> void:
	var profile: Dictionary = PlayerProfile.get_public_profile()
	var profile_id: String = str(profile["profile_id"])
	_expect(not profile_id.is_empty(), "Profile.profile_id 非空")
	_expect(PlayerProfile.get_profile_id() == profile_id, "Profile.profile_id 与 getter 一致")
	var preferred: String = PlayerProfile.get_preferred_character_id()
	var host: LobbyPlayer = LobbyPlayer.from_profile(profile, 1, Room.HOST_SEAT, true)
	_expect(host.profile_id == profile_id, "LobbyPlayer.profile_id 复制自 Profile")
	_expect(host.is_host and host.seat == Room.HOST_SEAT, "Host 在 seat 1")
	host.set_selected_character_id("chicken")
	_expect(PlayerProfile.get_preferred_character_id() == preferred, "改房内选角不回写 Profile")
	var clone: LobbyPlayer = host.copy()
	clone.set_selected_character_id("boar")
	_expect(host.selected_character_id == "chicken", "copy() 是副本，不共享状态")
	var restored: LobbyPlayer = LobbyPlayer.from_dict(host.to_dict())
	_expect(restored.seat == host.seat and restored.profile_id == host.profile_id, "to_dict/from_dict 往返保留身份")
	_expect(restored.connection_state == host.connection_state, "to_dict/from_dict 往返保留连接状态")

func _case_create_room_and_single_player_gate() -> void:
	var room: Room = _make_room()
	_expect(room.max_players == 5, "默认上限 5")
	_expect(room.room_id.length() == 8, "room_id 由 Host 本地生成")
	_expect(room.player_count() == 1, "建房只有 Host")
	_expect(room.occupied_count() == 1, "occupied = players + pending")
	_expect(not room.is_full(), "1/5 不满")
	_expect(room.arena_id == "pit", "arena 种子写入 Room")
	_expect(room.loop_goal == 20, "loop_goal 种子写入 Room")
	_expect(room.get_player_in_seat(Room.HOST_SEAT).is_host, "seat 1 是 Host")
	_expect(room.start_block_reason() == "need 2", "单人不能 Start（LAN 合同）")
	_expect(room.to_snapshot()["seats"].size() == 5, "快照始终 5 个座位槽")
	var seats: Array = room.to_snapshot()["seats"]
	_expect(int(seats[2]["seat"]) == 3 and not bool(seats[2]["occupied"]), "空位在快照里标记未占用")

func _case_seat_allocation_and_release() -> void:
	var room: Room = _make_room()
	for index: int in 4:
		_expect(room.add_player(_guest(_guest_id(index), index + 2)) == Room.AddResult.ADDED, "加入第 %d 个 Guest" % (index + 2))
	_expect(room.player_count() == 5 and room.is_full(), "5/5 满员")
	_expect(room.get_player_in_seat(5).profile_id == _guest_id(3), "座位按 2..5 递增分配")
	_expect(room.remove_player(_guest_id(1)), "移除 seat 3")
	_expect(room.get_player_in_seat(3) == null, "seat 3 已释放")
	_expect(room.seat_of(_guest_id(3)) == 5, "号不前挪：别人的座位不动")
	_expect(room.get_player_in_seat(4).profile_id == _guest_id(2), "seat 4 不变")
	_expect(room.add_player(_guest(_guest_id(9), 9)) == Room.AddResult.ADDED, "释放后可再进人")
	_expect(room.get_player_in_seat(3).profile_id == _guest_id(9), "新玩家取最小空位 seat 3")
	_expect(room.free_seats().is_empty(), "重新满员")
	_expect(room.occupied_count() == 5, "occupied 与玩家数一致")

func _case_duplicate_and_capacity() -> void:
	var room: Room = _make_room()
	_expect(room.add_player(_guest(_guest_id(0), 2)) == Room.AddResult.ADDED, "先占 seat 2")
	_expect(room.add_player(_guest(_guest_id(0), 3)) == Room.AddResult.DUPLICATE_PROFILE, "重复 profile_id 拒绝")
	_expect(room.add_player(_guest(_guest_id(1), 2)) == Room.AddResult.DUPLICATE_PEER, "重复 peer_id 拒绝")
	for index: int in range(1, 4):
		_expect(room.add_player(_guest(_guest_id(index), index + 2)) == Room.AddResult.ADDED, "继续填满 seat %d" % (index + 2))
	_expect(room.player_count() == 5, "已满 5 人")
	_expect(room.add_player(_guest(_guest_id(5), 9)) == Room.AddResult.FULL, "第 6 人被拒（满员才踢，不超员）")

func _case_ready_and_character() -> void:
	var room: Room = _make_room()
	room.add_player(_guest(_guest_id(0), 2))
	_expect(room.can_start(), "2/2 且 ready 时可开")
	_expect(room.set_ready(_guest_id(0), false), "set_ready 命中玩家")
	_expect(room.start_block_reason() == "not ready", "未 ready 不能开")
	room.set_ready(_guest_id(0), true)
	_expect(room.set_character(_guest_id(0), "chicken"), "set_character 命中玩家")
	_expect(room.get_player(_guest_id(0)).selected_character_id == "chicken", "房内选角生效")
	_expect(room.set_character(_guest_id(0), "dragon") == true, "未知角色 id 归一到默认")
	_expect(room.get_player(_guest_id(0)).selected_character_id == "boar", "未知角色落到 boar")
	var snapshot: Dictionary = room.to_snapshot()
	_expect(str(snapshot["host_profile_id"]) == PlayerProfile.get_profile_id(), "快照带 Host 身份")
	_expect(str(snapshot["seats"][1]["selected_character_id"]) == "boar", "座位槽读出角色")
	_expect(not room.set_ready("nobody", true), "未入座的 profile_id 不可 ready")

func _case_host_leave_closes_room() -> void:
	var room: Room = _make_room()
	room.add_player(_guest(_guest_id(0), 2))
	_expect(room.remove_player(PlayerProfile.get_profile_id()), "Host 离房")
	_expect(room.is_closed(), "Host 离房即关房（1.0 不做 Host 迁移）")
	_expect(room.player_count() == 0, "关房清空座位")
	_expect(room.host_display_name == PlayerProfile.get_display_name(), "保留房间身份供 Host closed 文案")
	_expect(room.add_player(_guest(_guest_id(1), 2)) == Room.AddResult.CLOSED, "关房后拒绝加入")

func _case_pending_reservation() -> void:
	var room: Room = _make_room()
	room.add_player(_guest(_guest_id(0), 2))
	_expect(room.can_start(), "先满足开局条件")
	_expect(room.reserve_seat(77) == 3, "pending peer 立刻占座")
	_expect(room.occupied_count() == 3, "pending 计入 occupied")
	_expect(room.player_count() == 2, "pending 不进 players")
	_expect(room.start_block_reason() == "pending", "有 pending 不能开")
	_expect(room.reserve_seat(78) != 3, "占位不会被第二个 peer 复用")
	_expect(room.release_reservation(77), "释放占位")
	_expect(room.release_reservation(78), "释放第二个占位")
	_expect(not room.has_pending(), "占位清空")
	_expect(room.can_start(), "占位释放后恢复可开")

func _case_manager_offline_solo_start() -> void:
	var manager: LobbyManager = LobbyManager.new()
	root.add_child(manager)
	var room: Room = manager.create_room("pit", GameLaunch.NetPlay.COOP, 20)
	_expect(manager.is_host() and not manager.is_networked(), "建房默认离线 Host")
	_expect(manager.get_local_seat() == Room.HOST_SEAT, "本地玩家在 seat 1")
	_expect(manager.can_start(), "离线单人可直接用 Room 种子开局")
	_expect(manager.set_local_character("chicken"), "本地选角写进房")
	var preferred: String = PlayerProfile.get_preferred_character_id()
	_expect(manager.start_match(), "离线 start 写信封")
	_expect(GameLaunch.take_net_role() == GameLaunch.NetRole.OFFLINE, "离线开局走 OFFLINE 角色（不假装有 peer）")
	_expect(GameLaunch.take_net_play() == GameLaunch.NetPlay.COOP, "net_play 入信封")
	_expect(GameLaunch.take_arena_id() == "pit", "arena 入信封")
	_expect(GameLaunch.take_local_seat() == Room.HOST_SEAT, "local seat 入信封")
	_expect(GameLaunch.take_mode() == GameLaunch.Mode.SOLO, "有目标即 SOLO 模式")
	var record_id: String = GameLaunch.take_active_record_id()
	_expect(not record_id.is_empty(), "离线开局带 active_record_id")
	var record: GameRecord = GameRecords.get_record(record_id)
	_expect(record != null, "信封里的档存在")
	if record != null and GameRecords.list_records().size() < GameRecords.get_max_records():
		_expect(record.character_id == "chicken", "档角色 = 房内选角")
	_expect(not manager.can_start(), "已开战不再可开")
	_expect(not manager.start_match(), "重复 Start 被拒")
	_expect(manager.get_local_player().selected_character_id == "chicken", "房内本地玩家保留选角")
	_expect(PlayerProfile.get_preferred_character_id() == preferred, "离线开局不改 Profile 首选角色")
	_expect(str(room.to_snapshot()["seats"][0]["display_name"]) == PlayerProfile.get_display_name(), "座位行显示 Profile 昵称")
	manager.queue_free()

func _case_manager_mock_roster() -> void:
	var manager: LobbyManager = LobbyManager.new()
	root.add_child(manager)
	manager.create_room("yard", GameLaunch.NetPlay.COOP, 20)
	var change_log: Array = [0]
	manager.room_changed.connect(func() -> void: change_log[0] += 1)
	for _index: int in 4:
		_expect(manager.add_mock_player() != null, "假座位加入")
	_expect(manager.get_mock_count() == 4, "4 个假座位")
	_expect(manager.get_snapshot()["player_count"] == 5, "连 Host 共 5 人")
	_expect(manager.add_mock_player() == null, "第 6 人被拒（上限 5）")
	_expect(manager.can_start(), "5 人全 ready 时可开")
	_expect(int(change_log[0]) > 0, "room_changed 有派发")
	var guest: LobbyPlayer = manager.get_room().get_player_in_seat(3)
	manager.set_ready(guest.profile_id, false)
	_expect(not manager.can_start(), "有未 ready 的假座位不能开")
	_expect(manager.start_block_reason() == "not ready", "拒绝原因可读")
	_expect(not manager.start_match(), "条件不足时 start_match 拒绝")
	manager.set_ready(guest.profile_id, true)
	manager.set_character(guest.profile_id, "chicken")
	_expect(manager.get_snapshot()["can_start"], "恢复 ready 后可开")
	_expect(manager.remove_mock_player(), "移除最后一个假座位（seat 5）")
	_expect(manager.get_mock_count() == 3 and manager.get_snapshot()["player_count"] == 4, "移除后剩 4 人")
	_expect(manager.get_room().get_player_in_seat(5) == null, "seat 5 已释放")
	_expect(manager.add_mock_player().seat == 5, "新假座位取回释放的 seat 5")
	_expect(manager.get_room().get_player(guest.profile_id).selected_character_id == "chicken", "假座位选角保留")
	_expect(manager.start_match(), "离线多人 mock 也能写信封")
	_expect(GameLaunch.take_net_role() == GameLaunch.NetRole.OFFLINE, "离线 mock 不带假 peer 进战斗")
	_expect(GameLaunch.take_active_record_id() != "", "离线 mock 信封带档")
	manager.queue_free()

func _case_manager_lan_bridge() -> void:
	var manager: LobbyManager = LobbyManager.new()
	root.add_child(manager)
	manager.create_room("yard", GameLaunch.NetPlay.BATTLE, 0)
	manager.mark_networked()
	_expect(not manager.can_start(), "真房间单人不能开")
	_expect(manager.start_block_reason() == "need 2", "原因沿用 Room 合同")
	_expect(manager.add_mock_player() == null, "真房间不塞假座位")
	_expect(manager.note_peer_connecting(42) == 2, "peer 占下 seat 2")
	_expect(manager.has_pending(), "handshake 前是 pending")
	_expect(not manager.can_start(), "pending 期间不能开")
	_expect(manager.confirm_peer(42) == 2, "握手完成落座 seat 2")
	_expect(not manager.has_pending(), "pending 清空")
	_expect(manager.get_snapshot()["player_count"] == 2, "2 人")
	_expect(manager.get_room().get_player_by_peer(42).connection_state == LobbyPlayer.ConnectionState.CONNECTED, "握手后 CONNECTED")
	_expect(manager.can_start(), "2 人握手完成可开")
	_expect(manager.set_peer_character(42, "chicken"), "peer 改角色")
	_expect(manager.start_match(), "真房间写 Host 信封")
	_expect(GameLaunch.take_net_role() == GameLaunch.NetRole.HOST, "真房间走 HOST 角色")
	_expect(GameLaunch.take_net_play() == GameLaunch.NetPlay.BATTLE, "net_play 入信封")
	var roster: Dictionary = GameLaunch.take_lan_roster()
	var peer_ids: PackedInt32Array = roster["peer_ids"]
	var character_ids: PackedStringArray = roster["character_ids"]
	_expect(peer_ids[0] == 1 and peer_ids[1] == 42, "座位表 peer：Host=1、Guest=42")
	_expect(character_ids[1] == "chicken", "座位表角色 = 房内选角")
	_expect(GameLaunch.take_local_seat() == Room.HOST_SEAT, "Host 本地座位 1")
	GameLaunch.take_arena_id()
	GameLaunch.take_mode()
	GameLaunch.take_active_record_id()
	_expect(manager.get_room().is_closed() == false, "开战后房间仍在（随主菜单销毁）")
	var second: LobbyManager = LobbyManager.new()
	root.add_child(second)
	second.create_room("yard", GameLaunch.NetPlay.COOP, 0)
	second.note_peer_connecting(43)
	_expect(second.drop_peer(43), "掉线释放 pending")
	_expect(not second.has_pending(), "pending 清空，occupied 不变")
	_expect(second.remove_mock_player() == false, "没有假座位时移除返回 false")
	second.leave_room()
	_expect(not second.has_room(), "leave_room 清空房间")
	manager.queue_free()
	second.queue_free()

# ---- 工具 ----

func _make_room() -> Room:
	var host: LobbyPlayer = LobbyPlayer.from_profile(PlayerProfile.get_public_profile(), 1, Room.HOST_SEAT, true)
	return Room.create(host, "pit", GameLaunch.NetPlay.COOP, 20)

func _guest(profile_id: String, peer_id: int) -> LobbyPlayer:
	var player: LobbyPlayer = LobbyPlayer.new()
	player.profile_id = profile_id
	player.display_name = profile_id.to_upper()
	player.peer_id = peer_id
	player.seat = LobbyPlayer.NO_SEAT
	player.ready = true
	player.connection_state = LobbyPlayer.ConnectionState.CONNECTED
	return player

func _guest_id(index: int) -> String:
	return "guest-%02d" % index

func _expect(condition: bool, label: String) -> void:
	if not condition:
		_failures.append(label)

func _backup_records() -> Variant:
	if not FileAccess.file_exists(RECORDS_FILE):
		return null
	return FileAccess.get_file_as_bytes(RECORDS_FILE)

func _restore_records(backup: Variant) -> void:
	var dir: DirAccess = DirAccess.open("user://")
	if dir == null:
		return
	if backup == null:
		dir.remove("records.json")
		return
	var file: FileAccess = FileAccess.open(RECORDS_FILE, FileAccess.WRITE)
	if file == null:
		return
	file.store_buffer(backup as PackedByteArray)
	file.close()
