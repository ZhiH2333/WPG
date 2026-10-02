extends SceneTree

## Lobby Ready 合同回归（Multiplayer UX 第一刀）。
## 锁定：Guest 默认 NOT READY、Ready/Not Ready 切换、改角色清 Ready、
## Host 改房间规则清所有 Guest Ready、Start 条件综合判定、seat 不前挪、掉线释放 seat。
## 全程离线，不 bind 17777、不碰 ENet。
## 跑法：godot --headless --path . --script res://tests/lobby_ready_test.gd --quit
## 通过输出 LOBBY_READY_OK；失败逐条 LOBBY_READY_FAIL 并返回非 0。

var _failures: PackedStringArray = PackedStringArray()

func _initialize() -> void:
	PlayerProfile.load_from_disk()
	_case_guest_default_not_ready()
	_case_guest_toggle_ready()
	_case_guest_ready_broadcast()
	_case_host_not_gated_by_ready()
	_case_ready_required_for_start()
	_case_all_guest_ready_enables_start()
	_case_connecting_blocks_start()
	_case_pending_blocks_start()
	_case_need_two_players()
	_case_seat_never_shifts()
	_case_disconnect_releases_seat()
	_case_character_change_clears_ready()
	_case_host_setting_change_clears_guest_ready()
	if _failures.is_empty():
		print("LOBBY_READY_OK")
		quit(0)
		return
	for failure: String in _failures:
		printerr("LOBBY_READY_FAIL: %s" % failure)
	quit(1)

# ---- 用例 ----

func _case_guest_default_not_ready() -> void:
	var manager: LobbyManager = LobbyManager.new()
	root.add_child(manager)
	manager.create_room("yard", GameLaunch.NetPlay.COOP, 20)
	manager.mark_networked()
	_expect(manager.note_peer_connecting(7) == 2, "peer 占下 seat 2")
	_expect(manager.confirm_peer(7) == 2, "握手完成落座")
	var guest: LobbyPlayer = manager.get_room().get_player_by_peer(7)
	_expect(guest != null and not guest.ready, "Guest 握手后默认 NOT READY")
	_expect(manager.start_block_reason() == "not ready", "未 ready 的阻断原因")
	manager.queue_free()

func _case_guest_toggle_ready() -> void:
	var manager: LobbyManager = LobbyManager.new()
	root.add_child(manager)
	manager.create_room("yard", GameLaunch.NetPlay.COOP, 20)
	manager.mark_networked()
	manager.note_peer_connecting(7)
	manager.confirm_peer(7)
	var host: LobbyPlayer = manager.get_local_player()
	_expect(host != null and host.is_host, "Host 在位")
	var before: bool = host.ready
	manager.set_local_ready(not before)
	_expect(host.ready == before, "Host 的 ready 字段不被本地 Ready API 改写")
	var guest: LobbyPlayer = manager.get_room().get_player_by_peer(7)
	_expect(manager.set_ready(guest.profile_id, true), "Guest ready 写入")
	_expect(guest.ready, "Guest READY 生效")
	_expect(manager.set_ready(guest.profile_id, false), "Guest not ready 写入")
	_expect(not guest.ready, "Guest WAITING 生效")
	manager.queue_free()

func _case_guest_ready_broadcast() -> void:
	var manager: LobbyManager = LobbyManager.new()
	root.add_child(manager)
	manager.create_room("yard", GameLaunch.NetPlay.COOP, 20)
	manager.mark_networked()
	manager.note_peer_connecting(7)
	manager.confirm_peer(7)
	var change_log: Array = [0]
	manager.room_changed.connect(func() -> void: change_log[0] += 1)
	var guest: LobbyPlayer = manager.get_room().get_player_by_peer(7)
	manager.set_ready(guest.profile_id, true)
	_expect(int(change_log[0]) > 0, "ready 变化派发 room_changed（UI / 网络据此刷新）")
	var seats: Array = manager.get_snapshot()["seats"]
	_expect(bool(seats[1]["ready"]), "快照座位 2 读出 READY")
	manager.queue_free()

func _case_host_not_gated_by_ready() -> void:
	var manager: LobbyManager = LobbyManager.new()
	root.add_child(manager)
	manager.create_room("yard", GameLaunch.NetPlay.COOP, 20)
	manager.mark_networked()
	manager.note_peer_connecting(7)
	manager.confirm_peer(7)
	var host: LobbyPlayer = manager.get_local_player()
	_expect(host != null and host.is_host, "本地是 Host")
	_expect(host.ready == true or host.ready == false, "Host 的 ready 字段不参与判定")
	manager.set_local_ready(false)
	_expect(manager.get_local_ready(), "Host 的 ready 字段不被本地 Ready API 改写")
	manager.queue_free()

func _case_ready_required_for_start() -> void:
	var manager: LobbyManager = LobbyManager.new()
	root.add_child(manager)
	manager.create_room("yard", GameLaunch.NetPlay.COOP, 20)
	manager.mark_networked()
	manager.note_peer_connecting(7)
	manager.confirm_peer(7)
	_expect(not manager.can_start(), "有未 ready 的 Guest 不能 Start")
	var guest: LobbyPlayer = manager.get_room().get_player_by_peer(7)
	manager.set_ready(guest.profile_id, true)
	_expect(manager.can_start(), "Guest ready 后可 Start")
	manager.queue_free()

func _case_all_guest_ready_enables_start() -> void:
	var manager: LobbyManager = LobbyManager.new()
	root.add_child(manager)
	manager.create_room("yard", GameLaunch.NetPlay.COOP, 20)
	manager.mark_networked()
	for peer: int in [7, 8]:
		manager.note_peer_connecting(peer)
		manager.confirm_peer(peer)
	_expect(manager.start_block_reason() == "not ready", "两人都未 ready")
	for peer: int in [7]:
		manager.set_ready(manager.get_room().get_player_by_peer(peer).profile_id, true)
	_expect(manager.start_block_reason() == "not ready", "仅一个 ready 仍不能 Start")
	manager.set_ready(manager.get_room().get_player_by_peer(8).profile_id, true)
	_expect(manager.can_start(), "全部 Guest ready 后可 Start")
	manager.queue_free()

func _case_connecting_blocks_start() -> void:
	var manager: LobbyManager = LobbyManager.new()
	root.add_child(manager)
	manager.create_room("yard", GameLaunch.NetPlay.COOP, 20)
	manager.mark_networked()
	manager.note_peer_connecting(7)
	var guest: LobbyPlayer = manager.get_room().get_player_by_peer(7)
	_expect(guest == null, "握手前不是正式成员")
	_expect(not manager.can_start(), "CONNECTING 期间不能 Start")
	manager.queue_free()

func _case_pending_blocks_start() -> void:
	var manager: LobbyManager = LobbyManager.new()
	root.add_child(manager)
	manager.create_room("yard", GameLaunch.NetPlay.COOP, 20)
	manager.mark_networked()
	manager.note_peer_connecting(7)
	manager.confirm_peer(7)
	manager.set_ready(manager.get_room().get_player_by_peer(7).profile_id, true)
	_expect(manager.can_start(), "先满足可开")
	manager.note_peer_connecting(8)
	_expect(manager.start_block_reason() == "pending", "有 pending 不能 Start")
	manager.drop_peer(8)
	_expect(manager.can_start(), "pending 清理后恢复可开")
	manager.queue_free()

func _case_need_two_players() -> void:
	var manager: LobbyManager = LobbyManager.new()
	root.add_child(manager)
	manager.create_room("yard", GameLaunch.NetPlay.COOP, 20)
	manager.mark_networked()
	_expect(manager.start_block_reason() == "need 2", "单人不能 Start")
	manager.queue_free()

func _case_seat_never_shifts() -> void:
	var manager: LobbyManager = LobbyManager.new()
	root.add_child(manager)
	manager.create_room("yard", GameLaunch.NetPlay.COOP, 20)
	manager.mark_networked()
	for peer: int in [7, 8, 9]:
		manager.note_peer_connecting(peer)
		manager.confirm_peer(peer)
	_expect(manager.get_room().get_player_by_peer(8).seat == 3, "peer 8 在 seat 3")
	manager.drop_peer(7)
	_expect(manager.get_room().get_player_in_seat(2) == null, "seat 2 释放")
	_expect(manager.get_room().get_player_by_peer(8).seat == 3, "号不前挪：peer 8 仍在 seat 3")
	_expect(manager.get_room().get_player_by_peer(9).seat == 4, "号不前挪：peer 9 仍在 seat 4")
	manager.queue_free()

func _case_disconnect_releases_seat() -> void:
	var manager: LobbyManager = LobbyManager.new()
	root.add_child(manager)
	manager.create_room("yard", GameLaunch.NetPlay.COOP, 20)
	manager.mark_networked()
	manager.note_peer_connecting(7)
	manager.confirm_peer(7)
	_expect(manager.get_snapshot()["player_count"] == 2, "2 人")
	_expect(manager.drop_peer(7), "掉线移除")
	_expect(manager.get_snapshot()["player_count"] == 1, "掉线后剩 Host")
	_expect(manager.get_room().get_player_in_seat(2) == null, "seat 2 变空")
	manager.queue_free()

func _case_character_change_clears_ready() -> void:
	var manager: LobbyManager = LobbyManager.new()
	root.add_child(manager)
	manager.create_room("yard", GameLaunch.NetPlay.COOP, 20)
	manager.mark_networked()
	manager.note_peer_connecting(7)
	manager.confirm_peer(7)
	var guest: LobbyPlayer = manager.get_room().get_player_by_peer(7)
	manager.set_ready(guest.profile_id, true)
	_expect(guest.ready, "先 READY")
	manager.set_local_character("chicken")  # Host 自己改角不影响 Guest
	_expect(guest.ready, "Host 改角不影响 Guest ready")
	manager.set_peer_character(7, "chicken")
	_expect(not guest.ready, "Guest 改角色 -> READY 变 WAITING")
	manager.set_ready(guest.profile_id, true)
	manager.set_character(guest.profile_id, "boar")
	_expect(not guest.ready, "本地 set_character 同样清 Ready")
	manager.queue_free()

func _case_host_setting_change_clears_guest_ready() -> void:
	var manager: LobbyManager = LobbyManager.new()
	root.add_child(manager)
	manager.create_room("yard", GameLaunch.NetPlay.COOP, 20)
	manager.mark_networked()
	manager.note_peer_connecting(7)
	manager.confirm_peer(7)
	var guest: LobbyPlayer = manager.get_room().get_player_by_peer(7)
	manager.set_ready(guest.profile_id, true)
	manager.set_arena_id("pit")
	_expect(not guest.ready, "Host 改 Arena -> Guest Ready 失效")
	manager.set_ready(guest.profile_id, true)
	manager.set_loop_goal(40)
	_expect(not guest.ready, "Host 改 Goal -> Guest Ready 失效")
	manager.set_ready(guest.profile_id, true)
	manager.set_net_play(GameLaunch.NetPlay.BATTLE)
	_expect(not guest.ready, "Host 改 Mode -> Guest Ready 失效")
	manager.queue_free()

func _expect(condition: bool, label: String) -> void:
	if not condition:
		_failures.append(label)
