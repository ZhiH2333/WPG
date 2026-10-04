extends SceneTree

## LAN E2E —— Host 端真进程（由 tests/integration/lan_e2e_test.gd 或 tools/e2e/lan/ui_run.py 拉起，不单独跑）。
##
## 放在 tools/e2e/ 而不是 tests/：smoke.py 会把 tests/ 下所有 *.gd 都当测试跑一遍，
## peer helper 脚本被无参调用会直接失败。这里不是独立测试，不该被自动发现。
##
## 与 guest.gd 是两个独立 Godot 进程，通过真实 ENetMultiplayerPeer 在
## 127.0.0.1:17777 上互发 RPC。这是仓库里唯一一条「两个 peer 真握手」的路径：其余
## lobby 测试都是单进程直接打状态机（见 tests/integration/lobby_net_test.gd 顶部说明）。
##
## 用法：godot --headless --path . --script res://tools/e2e/lan/host.gd -- <step> <result_file>
##   step = full | disconnect | host_closed
## 结果写进 result_file（OK / FAIL: reason）；编排脚本读文件而不是抓 stdout，
## 因为两个 peer 必须并发跑，无法用阻塞式 OS.execute 同时收集两边输出。

const TIMEOUT_MS: int = 30000

var _step: String = ""
var _result_path: String = ""
var _net: LobbyNet = null
var _manager: LobbyManager = null
var _done: bool = false
var _deadline: int = 0
var _ever_seated: bool = false
var _left_seen: bool = false
var _phase: int = 0

func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < 2:
		printerr("E2E_HOST_FAIL -: 缺少 step / result_file")
		quit(1)
		return
	_step = args[0]
	_result_path = args[1]
	_run.call_deferred()

func _run() -> void:
	PlayerProfile.load_from_disk()
	_net = LobbyNet.new()
	root.add_child(_net)
	_manager = LobbyManager.new()
	root.add_child(_manager)
	_manager.bind_net(_net)
	_manager.player_left.connect(func(_name: String, _seat: int) -> void: _left_seen = true)

	if not _manager.host_room("yard", GameLaunch.NetPlay.COOP, 20):
		_fail("host_room 失败（17777 端口被占？）")
		return
	## 协议 6：Host 必须为房间生成 ticket，Guest 才有可出示的入场券。
	## invite 通过文件交接给 Guest 进程（真实链路里这一步是复制 / 扫码）。
	var invite: JoinInvite = _manager.create_invite("127.0.0.1", GameLaunch.NET_PORT)
	if invite == null or not invite.is_valid():
		_fail("create_invite 失败")
		return
	_write_marker(_result_path + ".invite", invite.to_uri())
	## 监听已建立：给编排脚本一个确定性握手点，Guest 据此才启动，避免抢跑连不上。
	_write_marker(_result_path + ".ready")
	_wait()

## 帧驱动轮询：用 create_timer 而不是 sleep，保证 multiplayer poll 持续推进。
func _wait() -> void:
	if _done:
		return
	if _deadline == 0:
		_deadline = Time.get_ticks_msec() + TIMEOUT_MS
	if _tick():
		if not _done:
			_finish_ok()
		return
	if Time.get_ticks_msec() > _deadline:
		_fail("step %s 超时（phase=%d）" % [_step, _phase])
		return
	create_timer(0.05).timeout.connect(_wait)

func _tick() -> bool:
	var room: Room = _manager.get_room()
	if room == null:
		return false
	if room.player_count() == 2:
		_ever_seated = true
	var guest: LobbyPlayer = room.get_player_in_seat(2)
	match _step:
		"full":
			return _tick_full(room, guest)
		"disconnect":
			if not _ever_seated or not _left_seen:
				return false
			if room.player_count() != 1:
				return false
			if room.get_player_in_seat(2) != null:
				return false
			return true
		"host_closed":
			## 等 Guest 真能交互（按过 READY）再关服，否则可能在 rpc_assign_seat 送达前
			## 就把连接掐了，Guest 永远等不到自己的座位，测试变成假超时。
			return guest != null and guest.ready
	return false

## full：Host 权威视角依次验证 5 件事。
func _tick_full(room: Room, guest: LobbyPlayer) -> bool:
	## phase 5 只读 Host 自己的 room_state：Guest 一旦观察到 STARTING 就会退出进程，
	## 座位随即被释放（guest 变 null）。若在这里统一用 guest == null 提前返回，
	## phase 5 就会永远等不到，表现成随机超时。
	if _phase >= 5:
		return room.room_state == Room.RoomState.STARTING
	if guest == null:
		return false
	match _phase:
		0:
			## 1) 握手落座，且未 READY 时不允许开局。
			if guest.ready:
				return false
			if _manager.can_start():
				_fail("Guest 未 READY 却允许开局")
				return false
			if _manager.start_block_reason() != "not ready":
				_fail("未 READY 的阻断原因应为 not ready，实为 %s" % _manager.start_block_reason())
				return false
			_phase = 1
			return false
		1:
			## 2) 受理 Guest 的 READY（真 rpc_ready 到达）。
			if not guest.ready:
				return false
			_phase = 2
			return false
		2:
			## 3) Guest 改角色 -> Host 侧 ready 被清。默认角色是 boar，所以断言 chicken。
			if guest.selected_character_id != "chicken":
				return false
			if guest.ready:
				_fail("Guest 改角色后 Host 侧 ready 未清空")
				return false
			_phase = 3
			return false
		3:
			## 4) Host 改 Arena -> 旧 Ready 立刻失效。必须**同步**断言：Guest 观察到
			## 广播后会马上发下一轮 READY，异步去等就会跟那次 READY 抢，断言假失败。
			if not guest.ready:
				return false
			_manager.set_arena_id("pit")
			if room.arena_id != "pit":
				_fail("Host 改 Arena 没落到 Room，实为 %s" % room.arena_id)
				return false
			if guest.ready:
				_fail("Host 改 Arena 后 Host 侧 Guest ready 未清空")
				return false
			_phase = 4
			return false
		4:
			## 5) 等 Guest 自己观察到 arena=pit / ready=false 后重新 READY（回程证明在 Guest 侧）。
			if not guest.ready:
				return false
			if not _manager.can_start():
				_fail("2 人 READY 后仍不能开局：%s" % _manager.start_block_reason())
				return false
			if not _manager.start_match():
				_fail("start_match 返回 false")
				return false
			_phase = 5
			return false
		5:
			return room.room_state == Room.RoomState.STARTING
	return false

func _finish_ok() -> void:
	## host_closed：优雅关服，让 Guest 真的收到 server_disconnected。
	## 直接 quit 不关 peer 的话，对端只能靠超时发现，测试会变得很慢且不确定。
	if _step == "host_closed" and _net != null:
		_net.close()
	_write_result("OK")
	if _done:
		return
	_done = true
	print("E2E_HOST_OK %s" % _step)
	quit(0)

func _fail(reason: String) -> void:
	if _done:
		return
	_done = true
	_write_result("FAIL: %s" % reason)
	printerr("E2E_HOST_FAIL %s: %s" % [_step, reason])
	quit(1)

## 结果落盘。Godot 的 user:// 在受限沙箱里不可靠（日志轮转会直接崩），一律用绝对路径。
func _write_result(text: String) -> void:
	_write_marker(_result_path, text)

func _write_marker(path: String, text: String = "ready") -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		printerr("E2E_HOST_FAIL %s: 无法写 %s" % [_step, path])
		return
	file.store_string(text)
	file.close()
