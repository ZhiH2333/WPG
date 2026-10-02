extends SceneTree

## LobbyNet + 大厅状态同步回归（Multiplayer UX 第三刀）。
## 锁定：网络状态机（listen / connect / 握手 / 掉线 / 版本不符 / Host closed）、
## 座位缓存与 pending 合同、roster 编解码（协议 5 格式）、以及 host 权威的
## character / ready / arena / mode / goal / begin 五路同步 + Guest 只读投影。
##
## 本测试是「纯函数 + 状态机」：单进程里不跑两个 peer，也不靠 RPC 真发包
## （Godot 的 RPC 路由按节点路径解析，单进程内两个 LobbyNet 无法互为对端）。
## 因此这里直接打 LobbyNet 的校验函数 / 状态机与 LobbyManager 的网络事件处理函数，
## 只把 host_listen 用在「真 bind 一次再关掉」这件事上。
##
## 跑法：godot --headless --path . --script res://tests/lobby_net_test.gd --quit
## 通过输出 LOBBY_NET_OK；失败逐条 LOBBY_NET_FAIL 并返回非 0。

var _failures: PackedStringArray = PackedStringArray()

func _initialize() -> void:
	# LobbyNet 要碰 SceneTree 的 multiplayer，而 SceneTree 在 _initialize 期间还没建好自己的
	# MultiplayerAPI（Node.multiplayer 会是 null）。推迟到第一帧再跑，路径与真实运行一致。
	_run_all.call_deferred()

func _run_all() -> void:
	PlayerProfile.load_from_disk()
	_case_host_listen_state()
	_case_client_connect_state()
	_case_hello_protocol_gate()
	_case_hello_ok_seat_gate()
	_case_pending_peer()
	_case_seat_assignment_and_release()
	_case_confirm_peer()
	_case_roster_codec()
	_case_character_sync()
	_case_ready_sync()
	_case_arena_sync()
	_case_mode_sync()
	_case_goal_sync()
	_case_begin_match()
	_case_peer_disconnect()
	_case_server_disconnect()
	_case_privacy_switch()
	_case_invite_address_parse()
	if _failures.is_empty():
		print("LOBBY_NET_OK")
		quit(0)
		return
	for failure: String in _failures:
		printerr("LOBBY_NET_FAIL: %s" % failure)
	quit(1)

# ---- 1. host_listen 状态 ----

func _case_host_listen_state() -> void:
	var net: LobbyNet = LobbyNet.new()
	root.add_child(net)
	var listen_ok: Array = [0]
	var listen_failed: Array = [0]
	net.listen_ok.connect(func() -> void: listen_ok[0] += 1)
	net.listen_failed.connect(func() -> void: listen_failed[0] += 1)
	_expect(net.get_state() == LobbyNet.NetState.DISCONNECTED, "新建 LobbyNet 是 DISCONNECTED")
	_expect(not net.is_active(), "DISCONNECTED 不是 active")
	var bound: bool = net.host_listen()
	_expect(bound, "host_listen 绑定 17777 成功（CI headless 无第二个实例）")
	_expect(net.get_state() == LobbyNet.NetState.HOSTING, "listen 成功后是 HOSTING")
	_expect(net.is_active() and net.is_server(), "HOSTING 是 active 且本机就是 server")
	_expect(int(listen_ok[0]) == 1 and int(listen_failed[0]) == 0, "listen_ok 派发一次，listen_failed 不派发")
	_expect(net.seat_for_peer(LobbyNet.HOST_PEER) == Room.HOST_SEAT, "Host 自己恒占 seat 1")
	net.close()
	_expect(net.get_state() == LobbyNet.NetState.DISCONNECTED, "close 之后回到 DISCONNECTED")
	_expect(not net.is_active(), "close 之后不再 active")
	_expect(net.occupied_count() == 1, "close 之后只剩 Host 的座位缓存")
	net.queue_free()

# ---- 2. client_connect 状态 ----

func _case_client_connect_state() -> void:
	var net: LobbyNet = LobbyNet.new()
	root.add_child(net)
	var started: bool = net.client_connect("127.0.0.1")
	_expect(started, "client_connect 立即返回 true（连接过程是异步的）")
	_expect(net.get_state() == LobbyNet.NetState.CONNECTING, "发起连接后是 CONNECTING")
	_expect(net.is_active(), "CONNECTING 是 active")
	_expect(not net.is_server(), "Guest 侧不是 server")
	net._on_connected_to_server()
	_expect(net.get_state() == LobbyNet.NetState.HANDSHAKING, "连上但未握手是 HANDSHAKING")
	net.close()
	_expect(net.get_state() == LobbyNet.NetState.DISCONNECTED, "close 归零")
	net.queue_free()

# ---- 3. hello 协议闸门 ----

func _case_hello_protocol_gate() -> void:
	var net: LobbyNet = LobbyNet.new()
	root.add_child(net)
	var mismatches: Array = [0]
	net.version_mismatch.connect(func() -> void: mismatches[0] += 1)
	net.rpc_hello(GameLaunch.NET_PROTOCOL + 1)
	_expect(net.get_state() == LobbyNet.NetState.VERSION_MISMATCH, "版本不符 -> VERSION_MISMATCH")
	_expect(int(mismatches[0]) == 1, "version_mismatch 派发一次")
	_expect(not net.is_active(), "VERSION_MISMATCH 不是可用会话")
	# 正确协议分支：没有 peer 时不会回执，但状态机照样推进到 CONNECTED。
	net.rpc_hello(GameLaunch.NET_PROTOCOL)
	_expect(net.get_state() == LobbyNet.NetState.CONNECTED, "协议相符 -> CONNECTED")
	net.close()
	net.queue_free()

# ---- 4. hello_ok 座位闸门 ----

func _case_hello_ok_seat_gate() -> void:
	var net: LobbyNet = LobbyNet.new()
	root.add_child(net)
	var confirmed: Array = [0]
	net.peer_confirmed.connect(func(_peer_id: int, _seat: int) -> void: confirmed[0] += 1)
	_expect(net.accept_hello_ok(7) == 0, "没占座的 peer 不给确认")
	_expect(int(confirmed[0]) == 0, "未占座不派发 peer_confirmed")
	net.set_seat_peer(Room.HOST_SEAT + 1, 7)
	_expect(net.accept_hello_ok(7) == Room.HOST_SEAT + 1, "已占座的 peer 确认到它的座位")
	_expect(int(confirmed[0]) == 1, "已占座派发 Peer_confirmed")
	_expect(net.accept_hello_ok(LobbyNet.HOST_PEER) == 0, "Host 自己不是握手 Guest")
	net.queue_free()

# ---- 5. pending peer ----

func _case_pending_peer() -> void:
	var manager: LobbyManager = LobbyManager.new()
	root.add_child(manager)
	manager.create_room("yard", GameLaunch.NetPlay.COOP, 20)
	manager.mark_networked()
	_expect(manager.note_peer_connecting(7) == 2, "peer 立刻占下 seat 2")
	_expect(manager.has_pending(), "握手完成前是 pending")
	_expect(manager.get_room().player_count() == 1, "pending 不进 players")
	_expect(manager.get_room().occupied_count() == 2, "pending 计入 occupied")
	_expect(manager.start_block_reason() == "pending", "有 pending 不能 Start")
	_expect(manager.drop_peer(7), "pending 掉线可释放")
	_expect(not manager.has_pending(), "pending 释放后清空")
	_expect(manager.get_room().occupied_count() == 1, "occupied 回到 1")
	manager.queue_free()

# ---- 6. seat assignment / release ----

func _case_seat_assignment_and_release() -> void:
	var net: LobbyNet = LobbyNet.new()
	root.add_child(net)
	for index: int in 4:
		var seat: int = Room.HOST_SEAT + 1 + index
		net.set_seat_peer(seat, 10 + index)
		_expect(net.seat_for_peer(10 + index) == seat, "seat_for_peer 反查 seat %d" % seat)
	_expect(net.occupied_count() == 5, "5 个座位全占（含 Host）")
	net.clear_seat_of_peer(12)
	_expect(net.seat_for_peer(12) == 0, "掉线后 peer 反查归零")
	_expect(net.seat_peer(4) == 0, "seat 4 缓存清空")
	_expect(net.seat_character(4).is_empty(), "seat 4 角色缓存一并清空")
	_expect(net.occupied_count() == 4, "释放后 occupied 减一")
	_expect(net.seat_for_peer(10) == 2 and net.seat_for_peer(11) == 3, "号不前挪：别人的座位不动")
	net.set_seat_peer(Room.HOST_SEAT + 1, 99)
	_expect(net.seat_for_peer(10) == 0 and net.seat_for_peer(99) == 2, "座位缓存可被 Host 重写（换人）")
	net.queue_free()

# ---- 7. confirm peer ----

func _case_confirm_peer() -> void:
	var manager: LobbyManager = LobbyManager.new()
	root.add_child(manager)
	manager.create_room("yard", GameLaunch.NetPlay.COOP, 20)
	manager.mark_networked()
	manager.note_peer_connecting(7)
	_expect(manager.confirm_peer(7) == 2, "握手完成落座 seat 2")
	var guest: LobbyPlayer = manager.get_room().get_player_by_peer(7)
	_expect(guest != null, "确认后进 players")
	_expect(guest.connection_state == LobbyPlayer.ConnectionState.CONNECTED, "确认后 CONNECTED")
	_expect(not guest.ready, "确认后默认 NOT READY（进房不自动准备）")
	_expect(guest.seat == 2 and guest.peer_id == 7, "座位与 peer 都落在 LobbyPlayer 上")
	_expect(manager.confirm_peer(7) == 0, "重复确认返回 0（pending 已消费）")
	_expect(manager.confirm_peer(8) == 0, "没握手的 peer 确认不了")
	manager.queue_free()

# ---- 8. roster 编解码（协议 5 格式不变）----

func _case_roster_codec() -> void:
	var net: LobbyNet = LobbyNet.new()
	root.add_child(net)
	var characters: PackedStringArray = PackedStringArray()
	characters.resize(GameLaunch.NET_MAX_SEATS)
	characters[0] = "boar"
	characters[1] = "chicken"
	characters[2] = "boar"
	net.set_seat_peer(1, 1)
	net.set_seat_peer(2, 7)
	net.set_seat_peer(3, 8)
	var packed: PackedByteArray = net.encode_roster(characters, PackedInt32Array())
	_expect(not packed.is_empty(), "roster 包非空")
	_expect(packed[0] == 3, "包首字节 = 已占座位数（3）")
	var decoded: PackedStringArray = net.decode_roster(packed)
	_expect(decoded.size() == GameLaunch.NET_MAX_SEATS, "解出 5 个座位槽")
	_expect(decoded[1] == "chicken" and decoded[2] == "boar", "座位角色按 seat 还原")
	_expect(decoded[3].is_empty(), "空座位是空串")
	_expect(net.decode_roster(PackedByteArray()).size() == GameLaunch.NET_MAX_SEATS, "空包也解出 5 槽，不崩")
	var unknown: PackedStringArray = PackedStringArray()
	unknown.resize(GameLaunch.NET_MAX_SEATS)
	unknown[4] = "dragon"
	net.set_seat_peer(5, 9)
	var sanitized: PackedStringArray = net.decode_roster(net.encode_roster(unknown, PackedInt32Array()))
	_expect(sanitized[4] == "boar", "未知角色 id 在收包侧归一到默认")
	net.queue_free()

# ---- 9. character 同步 ----

func _case_character_sync() -> void:
	var host: LobbyManager = LobbyManager.new()
	root.add_child(host)
	host.create_room("yard", GameLaunch.NetPlay.COOP, 20)
	host.mark_networked()
	host.note_peer_connecting(7)
	host.confirm_peer(7)
	var guest_player: LobbyPlayer = host.get_room().get_player_by_peer(7)
	host.set_ready(guest_player.profile_id, true)
	_expect(host.set_peer_character(7, "chicken"), "Host 受理 Guest 角色")
	_expect(guest_player.selected_character_id == "chicken", "Host 侧角色落到 Room")
	_expect(not guest_player.ready, "Guest 改角色 -> Ready 失效（Host 侧权威）")
	_expect(host.set_peer_character(1, "boar") == false, "Host 座位不接受 peer 改角色")
	_expect(host.set_peer_character(99, "boar") == false, "没入座的 peer 改不了角色")
	# Guest 侧本地投影：改角清 Ready，且不再允许改别人的
	var guest: LobbyManager = LobbyManager.new()
	root.add_child(guest)
	_expect(guest.join_remote("roomid", "HOST", "yard", GameLaunch.NetPlay.COOP, 20, 2), "Guest 建立本地投影")
	_expect(not guest.get_local_ready(), "Guest 进房默认 NOT READY")
	_expect(guest.set_local_ready(true), "Guest 本地 Ready 可写")
	_expect(guest.get_local_ready(), "Guest 本地读到 READY")
	_expect(guest.set_local_character("chicken"), "Guest 改自己的角色")
	_expect(not guest.get_local_ready(), "Guest 改角色 -> 本地 READY 变 WAITING")
	_expect(guest.set_character("host:roomid", "chicken") == false, "Guest 改不了 Host 的角色")
	host.queue_free()
	guest.queue_free()

# ---- 10. ready 同步（Host 权威 + Starting 冻结）----

func _case_ready_sync() -> void:
	var host: LobbyManager = LobbyManager.new()
	root.add_child(host)
	host.create_room("yard", GameLaunch.NetPlay.COOP, 20)
	host.mark_networked()
	host.note_peer_connecting(7)
	host.confirm_peer(7)
	var guest_player: LobbyPlayer = host.get_room().get_player_by_peer(7)
	var changes: Array = [0]
	host.room_changed.connect(func() -> void: changes[0] += 1)
	_expect(host.apply_remote_ready(7, true), "Host 受理已入座 Guest 的 READY")
	_expect(guest_player.ready, "Host 侧 Room 记录 READY")
	_expect(int(changes[0]) > 0, "Ready 变化派发 room_changed（UI 据此重画）")
	_expect(host.apply_remote_ready(8, true) == false, "没入座的 peer 的 Ready 被丢")
	# pending 的 peer 不能抢跑 Ready
	host.note_peer_connecting(8)
	_expect(host.apply_remote_ready(8, true) == false, "pending peer 的 Ready 被丢")
	host.drop_peer(8)
	# Guest 侧只认 Host 的广播值
	var guest: LobbyManager = LobbyManager.new()
	root.add_child(guest)
	guest.join_remote("roomid", "HOST", "yard", GameLaunch.NetPlay.COOP, 20, 2)
	_expect(not guest.get_local_ready(), "广播前是 WAITING")
	guest._on_net_ready_applied(2, true)
	_expect(guest.get_local_ready(), "Host 广播 READY -> 本地投影 READY")
	guest._on_net_ready_applied(2, false)
	_expect(not guest.get_local_ready(), "Host 广播 WAITING -> 本地投影 WAITING")
	guest._on_net_ready_applied(4, true)
	_expect(not guest.get_local_ready(), "别的座位的 Ready 不影响本地（协议 5 不带身份）")
	# Starting 冻结：开战之后 Ready / 角色 / 房间规则都改不动
	host.set_ready(guest_player.profile_id, true)
	_expect(host.start_match(), "2 人 ready 后可开")
	_expect(host.get_room().room_state == Room.RoomState.STARTING, "开战后房间是 STARTING")
	_expect(guest_player.ready and host.apply_remote_ready(7, false) == false, "STARTING 期间 Ready 请求被丢")
	_expect(not host.set_ready(guest_player.profile_id, false), "STARTING 期间不能改 Ready")
	_expect(not host.set_character(guest_player.profile_id, "boar"), "STARTING 期间不能改角色")
	host.set_arena_id("keep")
	_expect(host.get_room().arena_id == "yard", "STARTING 期间不能改 Arena")
	host.set_loop_goal(40)
	_expect(host.get_room().loop_goal == 20, "STARTING 期间不能改 Goal")
	host.set_net_play(GameLaunch.NetPlay.BATTLE)
	_expect(host.get_room().net_play == GameLaunch.NetPlay.COOP, "STARTING 期间不能改 Mode")
	host.queue_free()
	guest.queue_free()

# ---- 11. arena 同步 ----

func _case_arena_sync() -> void:
	var host: LobbyManager = LobbyManager.new()
	root.add_child(host)
	host.create_room("yard", GameLaunch.NetPlay.COOP, 20)
	host.mark_networked()
	host.note_peer_connecting(7)
	host.confirm_peer(7)
	var guest_player: LobbyPlayer = host.get_room().get_player_by_peer(7)
	host.set_ready(guest_player.profile_id, true)
	host.set_arena_id("keep")
	_expect(host.get_room().arena_id == "keep", "Host 改 Arena 落到 Room")
	_expect(not guest_player.ready, "Host 改房间规则 -> Guest Ready 失效")
	var guest: LobbyManager = LobbyManager.new()
	root.add_child(guest)
	guest.join_remote("roomid", "HOST", "yard", GameLaunch.NetPlay.COOP, 20, 2)
	guest._on_net_arena_changed("pit")
	_expect(guest.get_room().arena_id == "pit", "Guest 投影跟随 Host 的 Arena")
	guest.set_arena_id("keep")
	_expect(guest.get_room().arena_id == "pit", "联网 Guest 不能自己改 Arena（Host 权威）")
	host.queue_free()
	guest.queue_free()

# ---- 12. mode 同步 ----

func _case_mode_sync() -> void:
	var host: LobbyManager = LobbyManager.new()
	root.add_child(host)
	host.create_room("yard", GameLaunch.NetPlay.COOP, 20)
	host.mark_networked()
	host.set_net_play(GameLaunch.NetPlay.BATTLE)
	_expect(host.get_room().net_play == GameLaunch.NetPlay.BATTLE, "Host 改 Mode 落到 Room")
	var guest: LobbyManager = LobbyManager.new()
	root.add_child(guest)
	guest.join_remote("roomid", "HOST", "yard", GameLaunch.NetPlay.COOP, 20, 2)
	guest._on_net_mode_changed(int(GameLaunch.NetPlay.BATTLE))
	_expect(guest.get_room().net_play == GameLaunch.NetPlay.BATTLE, "Guest 投影跟随 Mode")
	guest.set_net_play(GameLaunch.NetPlay.COOP)
	_expect(guest.get_room().net_play == GameLaunch.NetPlay.BATTLE, "联网 Guest 不能自己改 Mode")
	host.queue_free()
	guest.queue_free()

# ---- 13. goal 同步 ----

func _case_goal_sync() -> void:
	var host: LobbyManager = LobbyManager.new()
	root.add_child(host)
	host.create_room("yard", GameLaunch.NetPlay.COOP, 20)
	host.mark_networked()
	host.set_loop_goal(40)
	_expect(host.get_room().loop_goal == 40, "Host 改 Goal 落到 Room")
	var guest: LobbyManager = LobbyManager.new()
	root.add_child(guest)
	guest.join_remote("roomid", "HOST", "yard", GameLaunch.NetPlay.COOP, 20, 2)
	guest._on_net_goal_changed(40)
	_expect(guest.get_room().loop_goal == 40, "Guest 投影跟随 Goal")
	guest.set_loop_goal(10)
	_expect(guest.get_room().loop_goal == 40, "联网 Guest 不能自己改 Goal")
	host.queue_free()
	guest.queue_free()

# ---- 14. begin / 开始 ----

func _case_begin_match() -> void:
	var host: LobbyManager = LobbyManager.new()
	root.add_child(host)
	host.create_room("pit", GameLaunch.NetPlay.COOP, 20)
	host.mark_networked()
	host.note_peer_connecting(7)
	host.confirm_peer(7)
	host.set_ready(host.get_room().get_player_by_peer(7).profile_id, true)
	var started: Array = [0]
	host.match_started.connect(func() -> void: started[0] += 1)
	_expect(host.start_match(), "Host 开局成功")
	_expect(int(started[0]) == 1, "match_started 派发一次")
	_expect(GameLaunch.take_net_role() == GameLaunch.NetRole.HOST, "Host 信封是 HOST 角色")
	var roster: Dictionary = GameLaunch.take_lan_roster()
	var peer_ids: PackedInt32Array = roster["peer_ids"]
	_expect(peer_ids[0] == 1 and peer_ids[1] == 7, "信封座位表 peer 齐")
	_expect(GameLaunch.take_arena_id() == "pit", "信封带 arena")
	GameLaunch.take_mode()
	GameLaunch.take_active_record_id()
	# Guest 侧：收到 begin 就写 Guest 信封并把房间标 STARTING
	var guest: LobbyManager = LobbyManager.new()
	root.add_child(guest)
	var net: LobbyNet = LobbyNet.new()
	root.add_child(net)
	guest.bind_net(net)
	guest.join_remote("roomid", "HOST", "pit", GameLaunch.NetPlay.COOP, 20, 2)
	guest._on_net_match_begin(20, "pit", int(GameLaunch.NetPlay.COOP))
	_expect(guest.get_room().room_state == Room.RoomState.STARTING, "Guest 收到 begin -> STARTING")
	_expect(GameLaunch.take_net_role() == GameLaunch.NetRole.GUEST, "Guest 信封是 GUEST 角色")
	_expect(GameLaunch.take_arena_id() == "pit", "Guest 信封带 arena")
	GameLaunch.take_mode()
	GameLaunch.take_active_record_id()
	host.queue_free()
	guest.queue_free()
	net.queue_free()

# ---- 15. peer disconnect ----

func _case_peer_disconnect() -> void:
	var manager: LobbyManager = LobbyManager.new()
	root.add_child(manager)
	var net: LobbyNet = LobbyNet.new()
	root.add_child(net)
	manager.bind_net(net)
	_expect(net.host_listen(), "回归场景里真起一个 Host 监听（peer 断开事件只发给 server）")
	manager.create_room("yard", GameLaunch.NetPlay.COOP, 20)
	manager.mark_networked()
	manager.note_peer_connecting(7)
	manager.confirm_peer(7)
	net.set_seat_peer(2, 7)
	var left: Array = []
	manager.player_left.connect(func(name: String, seat: int) -> void: left.append([name, seat]))
	net._on_peer_disconnected(7)
	_expect(manager.get_room().player_count() == 1, "掉线后立刻释放座位")
	_expect(manager.get_room().get_player_in_seat(2) == null, "seat 2 变空")
	_expect(net.seat_for_peer(7) == 0, "LobbyNet 座位缓存一并清掉")
	_expect(left.size() == 1, "player_left 派发一次（UI 播 PLAYERxx LEFT）")
	if left.size() == 1:
		_expect(int(left[0][1]) == 2, "player_left 带出离开的座位号")
		_expect(not str(left[0][0]).is_empty(), "player_left 带出显示名")
	manager.queue_free()
	net.queue_free()

# ---- 16. server disconnect（Host closed / version mismatch / refused）----

func _case_server_disconnect() -> void:
	var manager: LobbyManager = LobbyManager.new()
	root.add_child(manager)
	var net: LobbyNet = LobbyNet.new()
	root.add_child(net)
	manager.bind_net(net)
	var states: Array = []
	var failed: Array = []
	manager.network_state_changed.connect(func(state: int) -> void: states.append(state))
	manager.network_failed.connect(func(reason: String) -> void: failed.append(reason))
	net.host_listen()
	net._on_server_disconnected()
	_expect(net.get_state() == LobbyNet.NetState.HOST_CLOSED, "Host 掉线 -> HOST_CLOSED")
	_expect(states.has(int(LobbyNet.NetState.HOST_CLOSED)), "状态变化透传给 LobbyManager（UI 只读）")
	_expect(failed.has("host closed"), "Host 掉线给出 host closed 文案")
	net.close()
	_expect(net.get_state() == LobbyNet.NetState.DISCONNECTED, "close 之后 DISCONNECTED")
	net.client_connect("127.0.0.1")
	net._on_connection_failed()
	_expect(net.get_state() == LobbyNet.NetState.FAILED, "连接被拒 -> FAILED")
	_expect(failed.has("refused"), "连接被拒给出 refused 文案")
	net.close()
	_expect(net.get_state() == LobbyNet.NetState.DISCONNECTED, "再次 close 归零")
	net.rpc_hello(-1)
	_expect(failed.has("Version mismatch"), "版本不符给出 Version mismatch 文案")
	manager.queue_free()
	net.queue_free()

# ---- 17. 房间隐私（LAN_VISIBLE / INVITE_ONLY）----

func _case_privacy_switch() -> void:
	var host: LobbyManager = LobbyManager.new()
	root.add_child(host)
	host.create_room("yard", GameLaunch.NetPlay.COOP, 20)
	_expect(host.get_privacy() == int(Room.Privacy.LAN_VISIBLE), "默认房间是 LAN VISIBLE")
	var changes: Array = [0]
	host.room_changed.connect(func() -> void: changes[0] += 1)
	_expect(host.set_privacy(Room.Privacy.INVITE_ONLY), "Host 可切到 INVITE ONLY")
	_expect(host.get_privacy() == int(Room.Privacy.INVITE_ONLY), "隐私落到 Room")
	_expect(host.get_room().privacy == Room.Privacy.INVITE_ONLY, "Room.privacy 与 Manager 一致")
	_expect(int(changes[0]) > 0, "隐私变化派发 room_changed（UI 据此起停 Beacon）")
	_expect(host.set_privacy(Room.Privacy.INVITE_ONLY) == false, "同值重复设置返回 false")
	host.set_ready("nobody", true)
	# 隐私不是房间规则：不该让 Guest 的 Ready 失效
	host.note_peer_connecting(7)
	host.confirm_peer(7)
	var guest_player: LobbyPlayer = host.get_room().get_player_by_peer(7)
	host.set_ready(guest_player.profile_id, true)
	host.set_privacy(Room.Privacy.LAN_VISIBLE)
	_expect(guest_player.ready, "切隐私不清 Guest 的 Ready（只有 Mode/Arena/Goal 才清）")
	# Guest 无权改隐私
	var guest: LobbyManager = LobbyManager.new()
	root.add_child(guest)
	guest.join_remote("roomid", "HOST", "yard", GameLaunch.NetPlay.COOP, 20, 2)
	_expect(guest.set_privacy(Room.Privacy.INVITE_ONLY) == false, "联网 Guest 不能改房间隐私")
	# Starting 冻结
	host.set_ready(guest_player.profile_id, true)
	_expect(host.start_match(), "隐私用例里也能正常开局")
	_expect(host.set_privacy(Room.Privacy.INVITE_ONLY) == false, "STARTING 期间不能改隐私")
	_expect(host.get_privacy() == int(Room.Privacy.LAN_VISIBLE), "冻结期间隐私保持原值")
	host.queue_free()
	guest.queue_free()

# ---- 18. JoinInvite 地址解析（纯函数）----

func _case_invite_address_parse() -> void:
	_expect(LobbyNet.parse_address("192.168.1.5") == "192.168.1.5", "纯 IPv4 原样解析")
	_expect(LobbyNet.parse_address("  192.168.1.5  ") == "192.168.1.5", "首尾空白被裁掉")
	_expect(LobbyNet.parse_address("192.168.1.5:17777") == "192.168.1.5", "带端口只取地址（端口固定 17777）")
	_expect(LobbyNet.parse_address("join 10.0.0.7 now") == "10.0.0.7", "从粘贴文本里取出地址")
	_expect(LobbyNet.parse_address("wpg://172.16.0.3") == "172.16.0.3", "带 scheme 前缀也能解析")
	_expect(LobbyNet.parse_address("300.1.1.1").is_empty(), "非法 IPv4 段解析失败")
	_expect(LobbyNet.parse_address("localhost").is_empty(), "主机名不是 IPv4，解析失败")
	_expect(LobbyNet.parse_address("").is_empty(), "空串解析失败")

func _expect(condition: bool, label: String) -> void:
	if not condition:
		_failures.append(label)