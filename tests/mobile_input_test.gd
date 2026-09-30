extends SceneTree

## Mobile Input 回归（Phase 4）：VirtualStick / TouchActionButton / TouchInput -> PlayerInput
## 全程 headless，不渲染、不 bind 触摸，直接驱动组件内部状态
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
	_case_touch_action_button_edge_semantics()
	_case_touch_input_left_stick_to_move_vector()
	_case_touch_input_right_stick_to_aim_vector()
	_case_touch_input_fire_held_semantics()
	_case_touch_input_dash_just_pressed_single_frame()
	_case_touch_input_dash_not_repeated_next_frame()
	_case_touch_input_no_interference_keyboard()
	_case_touch_input_no_interference_gamepad()
	
	if _failures.is_empty():
		print("MOBILE_INPUT_OK")
		quit(0)
		return
	
	for failure: String in _failures:
		printerr("MOBILE_INPUT_FAIL: %s" % failure)
	quit(1)

func _on_just_pressed() -> void:
	_just_pressed_count += 1

# ---- VirtualStick 测试 ----

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

## 摇杆中心（本地坐标）
func _stick_center(stick: VirtualStick) -> Vector2:
	return stick.size * 0.5

func _case_virtual_stick_center_zero() -> void:
	var stick: VirtualStick = _create_virtual_stick()
	var vector: Vector2 = stick.get_vector()
	_expect(vector.is_zero_approx(), "中心位置返回 ZERO")
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
	
	var vector: Vector2 = stick.get_vector()
	_expect(vector.is_zero_approx(), "deadzone 内返回 ZERO，实际长度: %.3f" % vector.length())
	
	stick._update_stick(center + Vector2(80, 0))
	vector = stick.get_vector()
	_expect(not vector.is_zero_approx(), "deadzone 外返回非零向量")
	stick.queue_free()

func _case_virtual_stick_release_returns_zero() -> void:
	var stick: VirtualStick = _create_virtual_stick(0.0, 80.0)
	var center: Vector2 = _stick_center(stick)
	stick._activate(1)
	stick._update_stick(center + Vector2(80, 0))
	_expect(not stick.get_vector().is_zero_approx(), "拖动时非零")
	
	stick._release()
	var vector: Vector2 = stick.get_vector()
	_expect(vector.is_zero_approx(), "松开后返回 ZERO")
	stick.queue_free()

# ---- TouchActionButton 测试 ----

func _create_touch_button() -> TouchActionButton:
	var btn: TouchActionButton = TouchActionButton.new()
	root.add_child(btn)
	btn._ready()
	return btn

func _case_touch_action_button_edge_semantics() -> void:
	var btn: TouchActionButton = _create_touch_button()
	_just_pressed_count = 0
	btn.just_pressed.connect(_on_just_pressed)
	
	# 直接测试信号发射
	btn.just_pressed.emit()
	_expect(_just_pressed_count == 1, "信号连接工作，实际: %d" % _just_pressed_count)
	
	btn.just_pressed.emit()
	_expect(_just_pressed_count == 2, "信号可重复发射，实际: %d" % _just_pressed_count)
	
	# 测试内部逻辑：_just_pressed 标志在 _process 中被清零
	btn._held = true
	btn._just_pressed = true
	btn._trigger_just_pressed_for_test()
	_expect(btn.is_just_pressed() == false, "_trigger_just_pressed_for_test 后 _just_pressed 复位为 false")
	
	btn.queue_free()

# ---- TouchInput -> PlayerInput 集成测试 ----

func _make_test_player_input() -> PlayerInput:
	var pi: PlayerInput = PlayerInput.new()
	root.add_child(pi)
	return pi

func _make_test_touch_input(player_input: PlayerInput) -> TouchInput:
	var ti: TouchInput = TouchInput.new()
	ti._set_player_input_for_test(player_input)
	root.add_child(ti)
	ti._ready()
	return ti

func _case_touch_input_left_stick_to_move_vector() -> void:
	var player_input: PlayerInput = _make_test_player_input()
	var move_stick: VirtualStick = _create_virtual_stick(0.15, 80.0)
	var touch_input: TouchInput = _make_test_touch_input(player_input)
	touch_input._set_move_stick_for_test(move_stick)
	
	move_stick._activate(1)
	move_stick._update_stick(_stick_center(move_stick) + Vector2(50, 0))
	touch_input._process(0.016)
	
	_expect(not player_input.move_vector.is_zero_approx(), "左摇杆产生 move_vector")
	_expect(player_input.move_vector.x > 0.0, "move_vector X 正向")
	_expect(player_input.move_vector.length() <= 1.0 + 0.001, "move_vector clamp <= 1")
	
	move_stick._release()
	touch_input._process(0.016)
	_expect(player_input.move_vector.is_zero_approx(), "左摇杆释放 move_vector 归零")
	
	player_input.queue_free()
	move_stick.queue_free()
	touch_input.queue_free()

func _case_touch_input_right_stick_to_aim_vector() -> void:
	var player_input: PlayerInput = _make_test_player_input()
	var aim_stick: VirtualStick = _create_virtual_stick(0.12, 80.0)
	var touch_input: TouchInput = _make_test_touch_input(player_input)
	touch_input._set_aim_stick_for_test(aim_stick)
	
	aim_stick._activate(2)
	aim_stick._update_stick(_stick_center(aim_stick) + Vector2(0, -50))
	touch_input._process(0.016)
	
	_expect(not player_input.aim_vector.is_zero_approx(), "右摇杆产生 aim_vector")
	_expect(player_input.aim_vector.y < 0.0, "aim_vector Y 负向")
	_expect(abs(player_input.aim_vector.length() - 1.0) < 0.001, "aim_vector 为单位向量")
	
	aim_stick._release()
	touch_input._process(0.016)
	
	player_input.queue_free()
	aim_stick.queue_free()
	touch_input.queue_free()

func _case_touch_input_fire_held_semantics() -> void:
	var player_input: PlayerInput = _make_test_player_input()
	var fire_btn: TouchActionButton = _create_touch_button()
	var touch_input: TouchInput = _make_test_touch_input(player_input)
	touch_input._set_fire_button_for_test(fire_btn)
	
	_expect(player_input.fire_held == false, "初始 fire_held 为 false")
	
	fire_btn._held = true
	fire_btn._just_pressed = true
	fire_btn.pressed.emit()
	touch_input._process(0.016)
	
	_expect(player_input.fire_held == true, "Fire pressed -> fire_held = true")
	
	fire_btn._held = false
	fire_btn.released.emit()
	touch_input._process(0.016)
	
	_expect(player_input.fire_held == false, "Fire released -> fire_held = false")
	
	player_input.queue_free()
	fire_btn.queue_free()
	touch_input.queue_free()

func _case_touch_input_dash_just_pressed_single_frame() -> void:
	var player_input: PlayerInput = _make_test_player_input()
	var dash_btn: TouchActionButton = _create_touch_button()
	var touch_input: TouchInput = _make_test_touch_input(player_input)
	touch_input._set_dash_button_for_test(dash_btn)
	
	_expect(player_input.dash_just_pressed == false, "初始 dash_just_pressed 为 false")
	
	dash_btn._held = true
	dash_btn._just_pressed = true
	dash_btn._process(0.016)
	touch_input._process(0.016)
	
	_expect(player_input.dash_just_pressed == true, "Dash just_pressed -> dash_just_pressed = true (第1帧)")
	
	dash_btn._process(0.016)
	touch_input._process(0.016)
	_expect(player_input.dash_just_pressed == false, "第2帧 dash_just_pressed 复位为 false")
	
	player_input.queue_free()
	dash_btn.queue_free()
	touch_input.queue_free()

func _case_touch_input_dash_not_repeated_next_frame() -> void:
	var player_input: PlayerInput = _make_test_player_input()
	var dash_btn: TouchActionButton = _create_touch_button()
	var touch_input: TouchInput = _make_test_touch_input(player_input)
	touch_input._set_dash_button_for_test(dash_btn)
	
	dash_btn._held = true
	dash_btn._just_pressed = true
	dash_btn._process(0.016)
	touch_input._process(0.016)
	_expect(player_input.dash_just_pressed == true, "首帧触发")
	
	dash_btn._just_pressed = false
	dash_btn._process(0.016)
	touch_input._process(0.016)
	_expect(player_input.dash_just_pressed == false, "非 just_pressed 帧不触发")
	
	touch_input._process(0.016)
	_expect(player_input.dash_just_pressed == false, "第三帧也不触发")
	
	player_input.queue_free()
	dash_btn.queue_free()
	touch_input.queue_free()

# ---- 设备优先级 / 互不干扰测试 ----

func _case_touch_input_no_interference_keyboard() -> void:
	var player_input: PlayerInput = _make_test_player_input()
	var touch_input: TouchInput = _make_test_touch_input(player_input)
	
	player_input._device_id = PlayerInput.DEVICE_KEYBOARD
	player_input._device_pinned = true
	
	player_input.update_input(0.016)
	_expect(player_input.move_vector.is_zero_approx(), "键盘无输入时 move_vector 为零")
	
	touch_input._process(0.016)
	
	player_input.queue_free()
	touch_input.queue_free()

func _case_touch_input_no_interference_gamepad() -> void:
	var player_input: PlayerInput = _make_test_player_input()
	var touch_input: TouchInput = _make_test_touch_input(player_input)
	
	player_input._device_id = 0
	player_input._device_pinned = true
	
	player_input.update_input(0.016)
	_expect(player_input.move_vector.is_zero_approx(), "手柄无输入时 move_vector 为零")
	
	touch_input._process(0.016)
	
	player_input.queue_free()
	touch_input.queue_free()

func _expect(condition: bool, label: String) -> void:
	if not condition:
		_failures.append(label)