extends SceneTree

## LAN E2E —— Guest 端真进程（由 tests/lan_e2e_test.gd 拉起，不单独跑）。
##
## 放在 tools/ci/ 而不是 tests/：smoke.py 会把 tests/ 下所有 *.gd 都当测试跑一遍，
## peer helper 脚本被无参调用会直接失败。这里不是独立测试，不该被自动发现。
##
## 与 lan_e2e_host.gd 配对：本进程用真实 ENetMultiplayerPeer 连上 127.0.0.1:17777，
## 走完整 hello / hello_ok / assign_seat 握手，再按 step 触发真实 RPC。
##
## 用法：godot --headless --path . --script res://tools/ci/lan_e2e_guest.gd -- <step> <result_file>
##
## 断言取向：Guest 侧只认 Host 广播下来的权威值。注意 set_local_ready 会先本地乐观落值，
## 所以「本地 ready == true」不能证明回程；真正证明 Host→Guest 的是 full 步里
## 「Host 改 Arena 后 Guest 的 ready 自己变 false」和「收到 begin 后进 STARTING」——
## 这两处 Guest 本地没有任何写入，只可能来自广播。

const TIMEOUT_MS: int = 30000

var _step: String = ""
var _result_path: String = ""
var _net: LobbyNet = null
var _manager: LobbyManager = null
var _done: bool = false
var _deadline: int = 0
var _phase: int = 0
var _dwell_until: int = 0

func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < 2:
		printerr("E2E_GUEST_FAIL -: 缺少 step / result_file")
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

	if not _manager.join_room_address("127.0.0.1"):
		_fail("client_connect 发起失败")
		return
	_wait()

func _wait() -> void:
	if _done:
		return
	if _deadline == 0:
		_deadline = Time.get_ticks_msec() + TIMEOUT_MS
	if _tick():
		if not _done:
			_done = true
			_write_result("OK")
			print("E2E_GUEST_OK %s" % _step)
			quit(0)
		return
	if Time.get_ticks_msec() > _deadline:
		_fail("step %s 超时（phase=%d）" % [_step, _phase])
		return
	create_timer(0.05).timeout.connect(_wait)

func _tick() -> bool:
	match _step:
		"full":
			return _tick_full()
		"disconnect":
			## 落座后优雅断线（真关 peer，Host 才会立刻收到 peer_disconnected）。
			if not _seated():
				return false
			## Host 每 50ms 才轮询一次；一落座就断线会让它来不及观察到「2 人在房」，
			## 于是 _ever_seated 永远是 false。先停一拍再断。
			if _phase == 0:
				_phase = 1
				_dwell_until = Time.get_ticks_msec() + 800
				return false
			if Time.get_ticks_msec() < _dwell_until:
				return false
			_net.close()
			return true
		"host_closed":
			if not _seated():
				return false
			## 先按 READY 告诉 Host「我这边已经完全入房」，Host 才关服；
			## 然后纯等 ENet 通知 -> LobbyNet 置 HOST_CLOSED。
			if _phase == 0:
				_manager.set_local_ready(true)
				_phase = 1
				return false
			return _net.get_state() == LobbyNet.NetState.HOST_CLOSED
	return false

func _tick_full() -> bool:
	if not _seated():
		return false
	var local: LobbyPlayer = _manager.get_local_player()
	var room: Room = _manager.get_room()
	if local == null or room == null:
		return false
	match _phase:
		0:
			## 握手完成：Host 分配的座位 > 1（1 是 Host）。
			_phase = 1
			return false
		1:
			## Ready：Guest 按 READY，发真 rpc_ready 给 Host（Host 侧另有断言证明到达）。
			_manager.set_local_ready(true)
			_phase = 2
			return false
		2:
			if not _manager.get_local_ready():
				return false
			## Guest 改角色 -> Ready 清除。默认是 boar，所以改成 chicken 才是真变化。
			_manager.set_local_character("chicken")
			_phase = 3
			return false
		3:
			if local.selected_character_id != "chicken":
				return false
			if local.ready:
				_fail("Guest 改角色后本地 ready 未清空")
				return false
			## 再次 READY，等 Host 改 Arena 把它清掉。
			_manager.set_local_ready(true)
			_phase = 4
			return false
		4:
			## 关键回程证明：本地没有任何写入，arena 与 ready 都只能来自 Host 广播。
			if room.arena_id != "pit":
				return false
			if local.ready:
				_fail("Host 改 Arena 后 Guest ready 未清空（Host 广播没到？）")
				return false
			## 最后再 READY 一次，等 Host 开局。
			_manager.set_local_ready(true)
			_phase = 5
			return false
		5:
			## 收到 begin -> STARTING。同样是纯 Host 驱动的本地状态变化。
			return room.room_state == Room.RoomState.STARTING
	return false

func _seated() -> bool:
	return _manager.get_room() != null and _manager.get_local_seat() > 1

func _fail(reason: String) -> void:
	if _done:
		return
	_done = true
	_write_result("FAIL: %s" % reason)
	printerr("E2E_GUEST_FAIL %s: %s" % [_step, reason])
	quit(1)

func _write_result(text: String) -> void:
	var file: FileAccess = FileAccess.open(_result_path, FileAccess.WRITE)
	if file == null:
		printerr("E2E_GUEST_FAIL %s: 无法写结果文件 %s" % [_step, _result_path])
		return
	file.store_string(text)
	file.close()
