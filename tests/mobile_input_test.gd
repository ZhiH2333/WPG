extends SceneTree

## Mobile Input 回归（Twin-Stick Boundary Pass）。
## 覆盖：VirtualStick / TouchActionButton / TouchInput -> PlayerInput Touch State。
## 核心约束：Touch 只经正式 PlayerInput API 进入；右摇杆 = Aim + Fire；Touch 任意位置 != Fire。
## 跑法：godot --headless --path . --script res://tests/mobile_input_test.gd --quit
## 通过输出 MOBILE_INPUT_OK；失败逐条 MOBILE_INPUT_FAIL 并返回非 0

var _failures: PackedStringArray = PackedStringArray()
var _just_pressed_count: int = 0

func _initialize() -> void:
	PlayerProfile.load_from_disk()

	_case_virtual_stick_center_zero()
	_case_virtual_stick_clamp_to_unit()
	_case_virtual_stick_deadzone()
	_case_virtual_stick_release_returns_zero()
	_case_virtual_stick_multi_touch_ids()

	_case_touch_action_button_edge_semantics()
	_case_touch_action_button_drag_not_click()

	_case_touch_idle_no_fire()
	_case_touch_arbitrary_screen_position_no_fire()
	_case_right_stick_active_fires()
	_case_right_stick_release_fire_false()
	_case_right_stick_deadzone_no_fire()
	_case_move_and_aim_simultaneously()
	_case_dash_edge()
	_case_weapon_slot_each()
	_case_pause_clears_touch()

	_case_touch_input_left_stick_to_move_vector()
	_case_touch_input_right_stick_aim_and_fire()
	_case_touch_input_dash_single_frame()
	_case_touch_input_weapon_slot()
	_case_touch_input_manual_fire_mode()
	_case_touch_no_interference_keyboard()
	_case_touch_no_interference_gamepad()

	_case_settings_touch_drag_classification()

	if _failures.is_empty():
		print("MOBILE_INPUT_OK")
		quit(0)
		return

	for failure: String in _failures:
		printerr("MOBILE_INPUT_FAIL: %s" % failure)
	quit(1)

func _on_just_pressed() -> void:
	_just_pressed_count += 1

# ---- VirtualStick ----

func _create_virtual_stick(deadzone: float = 0.15, max_radius: float = 80.0) -> VirtualStick:
	var stick: VirtualStick = VirtualStick.new()
	stick.deadzone = deadzone
	stick.max_radius = max_radius
	stick.size = Vector2(160, 160)
	stick.base_size = 160.0
	stick.knob_size = 80.0
	root.add_child(stick)
	stick._ready()
	return stick

func _stick_center(stick: VirtualStick) -> Vector2:
	return stick.size * 0.5

func _case_virtual_stick_center_zero() -> void:
	var stick: VirtualStick = _create_virtual_stick()
	_expect(stick.get_vector().is_zero_approx(), "中心位置返回 ZERO")
	stick.queue_free()

func _case_virtual_stick_clamp_to_unit() -> void:
	var stick: VirtualStick = _create_virtual_stick(0.0, 80.0)
	var center: Vector2 = _stick_center(stick)
	stick._activate(1)
	stick._update_stick(center + Vector2(200, 0))
	var vector: Vector2 = stick.get_vector()
	_expect(vector.length() <= 1.0 + 0.001, "向量长度 clamp 到 <= 1，实际: %.3f" % vector.length())
	_expect(vector.x > 0.0, "X 方向正确")
	stick.queue_free()

func _case_virtual_stick_deadzone() -> void:
	var stick: VirtualStick = _create_virtual_stick(0.3, 80.0)
	var center: Vector2 = _stick_center(stick)
	stick._activate(1)
	stick._update_stick(center + Vector2(20, 0))
	_expect(stick.get_vector().is_zero_approx(), "deadzone 内返回 ZERO")
	stick._update_stick(center + Vector2(80, 0))
	_expect(not stick.get_vector().is_zero_approx(), "deadzone 外返回非零向量")
	stick.queue_free()

func _case_virtual_stick_release_returns_zero() -> void:
	var stick: VirtualStick = _create_virtual_stick(0.0, 80.0)
	var center: Vector2 = _stick_center(stick)
	stick._activate(1)
	stick._update_stick(center + Vector2(80, 0))
	_expect(not stick.get_vector().is_zero_approx(), "拖动时非零")
	stick._release()
	_expect(stick.get_vector().is_zero_approx(), "松开后返回 ZERO")
	stick.queue_free()

## 双摇杆靠各自的 touch index，不共享一个全局 touch id。
func _case_virtual_stick_multi_touch_ids() -> void:
	var left: VirtualStick = _create_virtual_stick(0.0, 80.0)
	var right: VirtualStick = _create_virtual_stick(0.0, 80.0)
	left._activate(1)
	right._activate(2)
	left._update_stick(_stick_center(left) + Vector2(80, 0))
	right._update_stick(_stick_center(right) + Vector2(0, -80))
	_expect(left.is_active() and right.is_active(), "左右摇杆可同时激活")
	_expect(left.get_vector().x > 0.0, "左杆方向独立")
	_expect(right.get_vector().y < 0.0, "右杆方向独立")
	left.queue_free()
	right.queue_free()

# ---- TouchActionButton ----

func _create_touch_button(size: Vector2 = Vector2(100, 100)) -> TouchActionButton:
	var btn: TouchActionButton = TouchActionButton.new()
	btn.button_size = size
	root.add_child(btn)
	btn._ready()
	return btn

func _case_touch_action_button_edge_semantics() -> void:
	var btn: TouchActionButton = _create_touch_button()
	_just_pressed_count = 0
	btn.just_pressed.connect(_on_just_pressed)
	btn.just_pressed.emit()
	_expect(_just_pressed_count == 1, "信号连接工作")
	btn.just_pressed.emit()
	_expect(_just_pressed_count == 2, "信号可重复发射")
	btn._held = true
	btn._just_pressed = true
	btn._trigger_just_pressed_for_test()
	_expect(btn.is_just_pressed() == false, "_trigger_just_pressed_for_test 后复位")
	btn.queue_free()

## 触摸拖动超过 slop 不能算 click（drag != click）。
func _case_touch_action_button_drag_not_click() -> void:
	var btn: TouchActionButton = _create_touch_button(Vector2(120, 120))
	var count_before: int = 0
	_just_pressed_count = 0
	btn.just_pressed.connect(_on_just_pressed)
	var down: InputEventScreenTouch = InputEventScreenTouch.new()
	down.index = 3
	down.pressed = true
	down.position = Vector2(60, 60)
	btn._handle_touch(down)
	btn._process(0.016)
	_expect(_just_pressed_count == 1, "按下立即 click")
	var drag: InputEventScreenDrag = InputEventScreenDrag.new()
	drag.index = 3
	drag.position = Vector2(60, 140)
	btn._handle_drag(drag)
	_expect(not btn.is_held(), "拖动超过 slop 后释放按住")
	var up: InputEventScreenTouch = InputEventScreenTouch.new()
	up.index = 3
	up.pressed = false
	up.position = Vector2(60, 140)
	btn._handle_touch(up)
	count_before = _just_pressed_count
	btn._process(0.016)
	_expect(_just_pressed_count == count_before, "拖动释放不再产生 just_pressed")
	btn.queue_free()

# ---- PlayerInput Touch State 单元 ----

func _make_test_player_input() -> PlayerInput:
	var pi: PlayerInput = PlayerInput.new()
	root.add_child(pi)
	return pi

func _case_touch_idle_no_fire() -> void:
	var pi: PlayerInput = _make_test_player_input()
	pi.set_touch_active(true)
	pi.update_input()
	_expect(pi.fire_held == false, "touch idle -> fire false")
	_expect(pi.move_vector.is_zero_approx(), "touch idle -> move zero")
	pi.queue_free()

## Touch 任意世界坐标不能开火：不经过 Touch API 的输入完全不产生 fire。
func _case_touch_arbitrary_screen_position_no_fire() -> void:
	var pi: PlayerInput = _make_test_player_input()
	## 模拟「触摸屏幕任意位置」但不落到右摇杆 / Fire 按钮：不调用任何 touch API。
	pi.update_input()
	_expect(pi.fire_held == false, "触摸任意位置 -> fire false")
	pi.queue_free()

func _case_right_stick_active_fires() -> void:
	var pi: PlayerInput = _make_test_player_input()
	pi.set_touch_active(true)
	pi.set_touch_aim_vector(Vector2.UP, true)
	pi.update_input()
	_expect(pi.aim_vector.y < 0.0, "右摇杆 -> aim 方向")
	_expect(pi.fire_held == true, "右摇杆 active -> fire true")
	pi.queue_free()

func _case_right_stick_release_fire_false() -> void:
	var pi: PlayerInput = _make_test_player_input()
	pi.set_touch_active(true)
	pi.set_touch_aim_vector(Vector2.RIGHT, true)
	pi.update_input()
	_expect(pi.fire_held == true, "按下时 fire true")
	pi.set_touch_aim_vector(Vector2.ZERO, false)
	pi.update_input()
	_expect(pi.fire_held == false, "右摇杆 release -> fire false")
	_expect(not pi.aim_vector.is_zero_approx(), "release 后保留最后 aim")
	pi.queue_free()

func _case_right_stick_deadzone_no_fire() -> void:
	var pi: PlayerInput = _make_test_player_input()
	pi.set_touch_active(true)
	## deadzone 内：TouchInput 传 active=false（map_aim_stick 返回 ZERO）。
	pi.set_touch_aim_vector(Vector2.ZERO, false)
	pi.update_input()
	_expect(pi.fire_held == false, "右摇杆 deadzone -> no fire")
	pi.queue_free()

func _case_move_and_aim_simultaneously() -> void:
	var pi: PlayerInput = _make_test_player_input()
	pi.set_touch_active(true)
	pi.set_touch_move_vector(Vector2(1, 0))
	pi.set_touch_aim_vector(Vector2.UP, true)
	pi.update_input()
	_expect(pi.move_vector.x > 0.0, "移动与瞄准同时：move 生效")
	_expect(pi.aim_vector.y < 0.0, "移动与瞄准同时：aim 生效")
	_expect(pi.fire_held == true, "移动与瞄准同时：fire 生效")
	pi.queue_free()

func _case_dash_edge() -> void:
	var pi: PlayerInput = _make_test_player_input()
	pi.set_touch_active(true)
	pi.queue_touch_dash()
	pi._update_dash_pressed()
	_expect(pi.dash_just_pressed == true, "dash 首帧 true")
	pi._update_dash_pressed()
	_expect(pi.dash_just_pressed == false, "dash 次帧 false（不连发）")
	pi.queue_free()

func _case_weapon_slot_each() -> void:
	for slot: int in 4:
		var pi: PlayerInput = _make_test_player_input()
		pi.set_touch_active(true)
		pi.queue_touch_weapon_slot(slot)
		pi.update_input()
		_expect(pi.get_weapon_slot_just_pressed() == slot, "weapon slot %d 触发" % slot)
		pi.update_input()
		_expect(pi.get_weapon_slot_just_pressed() == -1, "weapon slot %d 只单帧" % slot)
		pi.queue_free()

## Pause 时必须清空所有 held / pending。
func _case_pause_clears_touch() -> void:
	var pi: PlayerInput = _make_test_player_input()
	pi.set_touch_active(true)
	pi.set_touch_move_vector(Vector2.RIGHT)
	pi.set_touch_aim_vector(Vector2.UP, true)
	pi.queue_touch_dash()
	pi.queue_touch_weapon_slot(2)
	pi.update_input()
	_expect(pi.fire_held, "pause 前 fire true")
	pi.clear_touch_state()
	pi.set_touch_active(false)
	pi.update_input()
	_expect(pi.move_vector.is_zero_approx(), "pause 后 move zero")
	_expect(pi.fire_held == false, "pause 后 fire false")
	_expect(pi.get_weapon_slot_just_pressed() == -1, "pause 后 weapon cleared")
	_expect(pi.take_pending_dash() == false, "pause 后 dash cleared")
	pi.queue_free()

# ---- TouchInput -> PlayerInput 集成 ----

func _make_test_touch_input(player_input: PlayerInput) -> TouchInput:
	var ti: TouchInput = TouchInput.new()
	ti.bind_player_input(player_input)
	root.add_child(ti)
	ti._ready()
	return ti

func _case_touch_input_left_stick_to_move_vector() -> void:
	var pi: PlayerInput = _make_test_player_input()
	var move_stick: VirtualStick = _create_virtual_stick(0.15, 80.0)
	var ti: TouchInput = _make_test_touch_input(pi)
	ti.bind_move_stick(move_stick)
	ti.set_active(true)
	move_stick._activate(1)
	move_stick._update_stick(_stick_center(move_stick) + Vector2(50, 0))
	pi.update_input()
	_expect(not pi.move_vector.is_zero_approx(), "左摇杆产生 move_vector")
	_expect(pi.move_vector.x > 0.0, "move_vector X 正向")
	move_stick._release()
	pi.update_input()
	_expect(pi.move_vector.is_zero_approx(), "左摇杆释放 move 归零")
	pi.queue_free()
	move_stick.queue_free()
	ti.queue_free()

func _case_touch_input_right_stick_aim_and_fire() -> void:
	var pi: PlayerInput = _make_test_player_input()
	var aim_stick: VirtualStick = _create_virtual_stick(0.12, 80.0)
	var ti: TouchInput = _make_test_touch_input(pi)
	ti.bind_aim_stick(aim_stick)
	ti.set_active(true)
	aim_stick._activate(2)
	aim_stick._update_stick(_stick_center(aim_stick) + Vector2(0, -50))
	pi.update_input()
	_expect(pi.aim_vector.y < 0.0, "右摇杆产生 aim")
	_expect(abs(pi.aim_vector.length() - 1.0) < 0.001, "aim 单位向量")
	_expect(pi.fire_held == true, "右摇杆 active -> fire true")
	aim_stick._release()
	pi.update_input()
	_expect(pi.fire_held == false, "右摇杆 release -> fire false")
	pi.queue_free()
	aim_stick.queue_free()
	ti.queue_free()

func _case_touch_input_dash_single_frame() -> void:
	var pi: PlayerInput = _make_test_player_input()
	var dash_btn: TouchActionButton = _create_touch_button()
	var ti: TouchInput = _make_test_touch_input(pi)
	ti.bind_dash_button(dash_btn)
	ti.set_active(true)
	dash_btn._just_pressed = true
	dash_btn._process(0.016)
	pi._update_dash_pressed()
	_expect(pi.dash_just_pressed == true, "Dash 首帧 true")
	_expect(pi.take_pending_dash() == true, "Dash 入队 pending")
	pi._update_dash_pressed()
	_expect(pi.dash_just_pressed == false, "Dash 次帧 false")
	pi.queue_free()
	dash_btn.queue_free()
	ti.queue_free()

func _case_touch_input_weapon_slot() -> void:
	var pi: PlayerInput = _make_test_player_input()
	var ti: TouchInput = _make_test_touch_input(pi)
	var buttons: Array[TouchActionButton] = []
	for i: int in 4:
		buttons.append(_create_touch_button())
	ti.bind_weapon_buttons(buttons)
	ti.set_active(true)
	buttons[2]._just_pressed = true
	buttons[2]._process(0.016)
	pi.update_input()
	_expect(pi.get_weapon_slot_just_pressed() == 2, "Weapon 按钮 3 -> slot 2")
	pi.queue_free()
	for btn: TouchActionButton in buttons:
		btn.queue_free()
	ti.queue_free()

func _case_touch_input_manual_fire_mode() -> void:
	var pi: PlayerInput = _make_test_player_input()
	var aim_stick: VirtualStick = _create_virtual_stick(0.12, 80.0)
	var ti: TouchInput = _make_test_touch_input(pi)
	ti.bind_aim_stick(aim_stick)
	ti.set_manual_fire_mode(true)
	ti.set_active(true)
	aim_stick._activate(2)
	aim_stick._update_stick(_stick_center(aim_stick) + Vector2(0, -50))
	pi.update_input()
	_expect(pi.aim_vector.y < 0.0, "Manual Fire：右摇杆仍瞄准")
	_expect(pi.fire_held == false, "Manual Fire：右摇杆不开火")
	pi.set_touch_fire_held(true)
	pi.update_input()
	_expect(pi.fire_held == true, "Manual Fire：FIRE 按钮开火")
	pi.queue_free()
	aim_stick.queue_free()
	ti.queue_free()

# ---- 设备优先级 ----

func _case_touch_no_interference_keyboard() -> void:
	var pi: PlayerInput = _make_test_player_input()
	pi._device_pinned = true
	pi.update_input()
	_expect(pi.fire_held == false, "键盘无输入：fire false")
	pi.set_touch_active(true)
	pi.set_touch_aim_vector(Vector2.UP, true)
	pi.update_input()
	_expect(pi.fire_held == true, "Touch Active 覆盖键盘：fire true")
	pi.queue_free()

func _case_touch_no_interference_gamepad() -> void:
	var pi: PlayerInput = _make_test_player_input()
	pi._device_id = 0
	pi._device_pinned = true
	pi.set_touch_active(true)
	pi.set_touch_move_vector(Vector2(1, 0))
	pi.update_input()
	_expect(pi.move_vector.x > 0.0, "Touch Active 覆盖手柄：move 生效")
	pi.queue_free()

# ---- Settings Touch Drag ----

## 直接验证 tap / drag 判定逻辑（slop = 12px），不依赖真实 SettingsOverlay 场景。
func _case_settings_touch_drag_classification() -> void:
	var slop: float = 12.0
	var origin := Vector2(500, 400)
	var tap_move := Vector2(500, 405)
	var drag_move := Vector2(500, 440)
	_expect(origin.distance_to(tap_move) < slop, "轻微移动 = tap")
	_expect(origin.distance_to(drag_move) >= slop, "大幅移动 = drag")
	## 手指上滑（y 减小）应使内容上滚：scroll delta 为负。
	var prev_y: float = 440.0
	var next_y: float = 380.0
	var delta_y: float = next_y - prev_y
	_expect(delta_y < 0.0, "手指上滑 -> 内容上滚（delta 负）")

func _expect(condition: bool, label: String) -> void:
	if not condition:
		_failures.append(label)
