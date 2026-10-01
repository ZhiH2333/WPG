extends SceneTree

## Touch 真实事件链集成测试（非 unit-level）。
## 覆盖：touch_controls.tscn 真实节点 -> get_root().push_input(InputEventScreenTouch/Drag)
## -> VirtualStick / TouchActionButton -> TouchInput -> PlayerInput。
## 同时验证模拟鼠标（DEVICE_ID_EMULATION）不会二次驱动 gameplay 控件。
## 跑法：godot --headless --path . --script res://tests/touch_event_integration_test.gd
## 通过输出 TOUCH_EVENT_INTEGRATION_OK；失败逐条 ..._FAIL 并返回非 0。

var _failures: PackedStringArray = PackedStringArray()
var _tc: TouchControls
var _pi: PlayerInput

func _initialize() -> void:
	_run()

func _run() -> void:
	await process_frame
	PlayerProfile.load_from_disk()
	GameSettings.set_touch_controls_mode(GameSettings.TouchControlsMode.ON)
	root.size = Vector2i(1920, 1080)

	var scene: PackedScene = load("res://ui/mobile/touch_controls.tscn")
	_tc = scene.instantiate() as TouchControls
	root.add_child(_tc)
	_pi = PlayerInput.new()
	root.add_child(_pi)
	_tc.bind_player_input(_pi)
	await process_frame
	_tc.refresh_visibility()
	await process_frame

	await _case_real_screen_touch_drives_move()
	await _case_real_touch_multi_index()
	await _case_real_touch_button_edge()
	await _case_emulated_mouse_ignored()
	await _case_real_mouse_works()
	await _case_world_touch_no_fire()

	if _failures.is_empty():
		print("TOUCH_EVENT_INTEGRATION_OK")
		quit(0)
		return
	for failure: String in _failures:
		printerr("TOUCH_EVENT_INTEGRATION_FAIL: %s" % failure)
	quit(1)

func _stick_press(stick: VirtualStick, index: int, offset: Vector2 = Vector2.ZERO) -> void:
	var center: Vector2 = stick.global_position + stick.size * 0.5
	var ev: InputEventScreenTouch = InputEventScreenTouch.new()
	ev.index = index
	ev.pressed = true
	ev.position = center + offset
	get_root().push_input(ev)

func _stick_drag(stick: VirtualStick, index: int, offset: Vector2) -> void:
	var center: Vector2 = stick.global_position + stick.size * 0.5
	var ev: InputEventScreenDrag = InputEventScreenDrag.new()
	ev.index = index
	ev.position = center + offset
	ev.screen_relative = offset
	get_root().push_input(ev)

func _stick_release(stick: VirtualStick, index: int) -> void:
	var center: Vector2 = stick.global_position + stick.size * 0.5
	var ev: InputEventScreenTouch = InputEventScreenTouch.new()
	ev.index = index
	ev.pressed = false
	ev.position = center
	get_root().push_input(ev)

func _button_press(btn: TouchActionButton, index: int) -> void:
	var c: Vector2 = btn.global_position + btn.button_size * 0.5
	var ev: InputEventScreenTouch = InputEventScreenTouch.new()
	ev.index = index
	ev.pressed = true
	ev.position = c
	get_root().push_input(ev)

func _button_release(btn: TouchActionButton, index: int) -> void:
	var c: Vector2 = btn.global_position + btn.button_size * 0.5
	var ev: InputEventScreenTouch = InputEventScreenTouch.new()
	ev.index = index
	ev.pressed = false
	ev.position = c
	get_root().push_input(ev)

## 真实 ScreenTouch down + drag + release 必须贯穿到 PlayerInput.move_vector。
func _case_real_screen_touch_drives_move() -> void:
	var stick: VirtualStick = _tc.get_move_stick()
	_stick_press(stick, 0)
	await process_frame
	_expect(stick.is_active(), "原生 ScreenTouch down 激活左摇杆")
	_stick_drag(stick, 0, Vector2(70, 0))
	await process_frame
	_expect(_pi.move_vector.x > 0.0, "ScreenDrag 驱动 PlayerInput.move_vector.x")
	_stick_release(stick, 0)
	await process_frame
	_expect(not stick.is_active(), "ScreenTouch up 释放左摇杆")
	_expect(_pi.move_vector.is_zero_approx(), "释放后 move 归零")

## 右摇杆：真实 touch -> aim + fire；release -> fire false，aim 保留。
func _case_real_touch_multi_index() -> void:
	var move_stick: VirtualStick = _tc.get_move_stick()
	var aim_stick: VirtualStick = _tc.get_aim_stick()
	_stick_press(move_stick, 0)
	_stick_press(aim_stick, 1)
	await process_frame
	_stick_drag(move_stick, 0, Vector2(70, 0))
	_stick_drag(aim_stick, 1, Vector2(0, -70))
	await process_frame
	_expect(move_stick.is_active() and aim_stick.is_active(), "touch index 0/1 可并存")
	_expect(_pi.move_vector.x > 0.0, "左杆 index 0 移动")
	_expect(_pi.aim_vector.y < 0.0, "右杆 index 1 瞄准")
	_expect(_pi.fire_held, "右杆 active -> fire")
	_stick_release(aim_stick, 1)
	await process_frame
	_expect(not _pi.fire_held, "右杆 release -> fire false")
	_expect(not _pi.aim_vector.is_zero_approx(), "release 后保留最后 aim")
	_stick_release(move_stick, 0)
	await process_frame
	# index 2 独立第三指仍可激活
	_stick_press(aim_stick, 2)
	await process_frame
	_expect(aim_stick.is_active(), "touch index 2 可激活")
	_stick_release(aim_stick, 2)
	await process_frame

## 真实 Touch 边沿驱动 Dash / Weapon 按钮（经 TouchInput -> PlayerInput）。
func _case_real_touch_button_edge() -> void:
	var dash: TouchActionButton = _tc.get_dash_button()
	_button_press(dash, 6)
	await process_frame
	await physics_frame
	await process_frame
	_expect(dash.is_held(), "原生 ScreenTouch 命中 DashButton")
	_expect(_pi.take_pending_dash(), "Dash 进入 PlayerInput pending")
	_button_release(dash, 6)
	await process_frame
	var weapon: TouchActionButton = _tc.get_weapon_button(2)
	_button_press(weapon, 7)
	await process_frame
	await process_frame
	_expect(weapon.is_held(), "原生 ScreenTouch 命中 Weapon3Button")
	_expect(_pi.get_weapon_slot_just_pressed() == 2 or _pi.take_pending_weapon_slot() == 2, "Weapon 3 -> slot 2")
	_button_release(weapon, 7)
	await process_frame

## emulate_mouse_from_touch=true 时，模拟鼠标绝不能驱动 gameplay 摇杆/按钮。
func _case_emulated_mouse_ignored() -> void:
	var stick: VirtualStick = _tc.get_move_stick()
	var c: Vector2 = stick.size * 0.5
	var down: InputEventMouseButton = InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = c
	down.device = InputEvent.DEVICE_ID_EMULATION
	stick._gui_input(down)
	_expect(not stick.is_active(), "模拟鼠标不得激活摇杆")
	var drag: InputEventMouseMotion = InputEventMouseMotion.new()
	drag.position = c + Vector2(80, 0)
	drag.device = InputEvent.DEVICE_ID_EMULATION
	stick._gui_input(drag)
	_expect(stick.get_vector().is_zero_approx(), "模拟鼠标不得驱动摇杆向量")

## 真实鼠标（device != DEVICE_ID_EMULATION）仍可用于 PC TouchControls 测试。
func _case_real_mouse_works() -> void:
	var stick: VirtualStick = _tc.get_move_stick()
	## 直接调用 _gui_input 使用本地坐标。
	var local_center: Vector2 = stick.size * 0.5
	var down: InputEventMouseButton = InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = local_center
	down.device = 0
	stick._gui_input(down)
	_expect(stick.is_active(), "真实鼠标可激活摇杆（PC 测试）")
	stick.reset()
	var btn: TouchActionButton = _tc.get_dash_button()
	var bc: Vector2 = btn.button_size * 0.5
	var bdown: InputEventMouseButton = InputEventMouseButton.new()
	bdown.button_index = MOUSE_BUTTON_LEFT
	bdown.pressed = true
	bdown.position = bc
	bdown.device = 0
	btn._gui_input(bdown)
	_expect(btn.is_held(), "真实鼠标可命中 TouchActionButton")
	btn._gui_input(_mouse_up(bc, 0))
	_expect(not btn.is_held(), "真实鼠标抬起释放 TouchActionButton")

func _mouse_up(pos: Vector2, device: int) -> InputEventMouseButton:
	var e: InputEventMouseButton = InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = false
	e.position = pos
	e.device = device
	return e

## Touch source active 时，触摸游戏世界普通位置不能开火。
func _case_world_touch_no_fire() -> void:
	var before: bool = _pi.fire_held
	var ev: InputEventScreenTouch = InputEventScreenTouch.new()
	ev.index = 9
	ev.pressed = true
	ev.position = Vector2(960, 100)
	get_root().push_input(ev)
	await process_frame
	_expect(not _pi.fire_held, "触摸世界普通位置 -> fire false")
	_expect(_pi.fire_held == before, "世界触摸不改变 fire 状态")

func _expect(condition: bool, label: String) -> void:
	if not condition:
		_failures.append(label)
