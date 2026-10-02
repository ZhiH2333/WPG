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
var _host: Node2D
var _reticle: AimReticle

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
	## PlayerInput 挂在 Node2D 宿主下，让 AimReticle 能拿到玩家位置，走真实准星路径。
	_host = Node2D.new()
	_host.position = Vector2(400, 300)
	root.add_child(_host)
	_pi = PlayerInput.new()
	_host.add_child(_pi)
	_reticle = AimReticle.new()
	root.add_child(_reticle)
	_reticle.bind_player_input(_pi)
	_tc.bind_player_input(_pi)
	await process_frame
	_tc.refresh_visibility()
	await process_frame

	await _case_real_screen_touch_drives_move()
	await _case_real_touch_multi_index()
	await _case_real_aim_pad_direction_only()
	await _case_real_touch_button_edge()
	await _case_emulated_mouse_ignored()
	await _case_real_mouse_works()
	await _case_world_touch_no_fire()
	await _case_manual_fire_button()
	await _case_pressed_visuals()

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

func _aim_pad_press(pad: TouchAimPad, index: int, offset: Vector2 = Vector2.ZERO) -> void:
	var center: Vector2 = pad.global_position + pad.size * 0.5
	var ev: InputEventScreenTouch = InputEventScreenTouch.new()
	ev.index = index
	ev.pressed = true
	ev.position = center + offset
	get_root().push_input(ev)

func _aim_pad_drag(pad: TouchAimPad, index: int, offset: Vector2) -> void:
	var center: Vector2 = pad.global_position + pad.size * 0.5
	var ev: InputEventScreenDrag = InputEventScreenDrag.new()
	ev.index = index
	ev.position = center + offset
	ev.screen_relative = offset
	get_root().push_input(ev)

func _aim_pad_release(pad: TouchAimPad, index: int) -> void:
	var center: Vector2 = pad.global_position + pad.size * 0.5
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

## 左摇杆 Move + 右 AimPad：真实 touch -> aim + fire；release -> aim ZERO，fire false。
func _case_real_touch_multi_index() -> void:
	var move_stick: VirtualStick = _tc.get_move_stick()
	var aim_pad: TouchAimPad = _tc.get_aim_pad()
	_stick_press(move_stick, 0)
	_aim_pad_press(aim_pad, 1)
	await process_frame
	_stick_drag(move_stick, 0, Vector2(70, 0))
	_aim_pad_drag(aim_pad, 1, Vector2(0, -70))
	await process_frame
	_expect(move_stick.is_active() and aim_pad.is_active(), "touch index 0/1 可并存")
	_expect(_pi.move_vector.x > 0.0, "左杆 index 0 移动")
	_expect(_pi.aim_vector.y < 0.0, "AimPad index 1 瞄准")
	_expect(_pi.fire_held, "AimPad active -> fire")
	_aim_pad_release(aim_pad, 1)
	await process_frame
	_expect(not _pi.fire_held, "AimPad release -> fire false")
	_expect(_pi.aim_vector.is_zero_approx(), "AimPad release -> aim ZERO（回中心）")
	_stick_release(move_stick, 0)
	await process_frame
	# index 2 独立第三指仍可激活
	_aim_pad_press(aim_pad, 2)
	await process_frame
	_expect(aim_pad.is_active(), "touch index 2 可激活")
	_aim_pad_release(aim_pad, 2)
	await process_frame

## 真实原生 touch 下：小拖 / 大拖同向 -> 相同 aim 方向、相同固定准星距离。
func _case_real_aim_pad_direction_only() -> void:
	var aim_pad: TouchAimPad = _tc.get_aim_pad()
	_aim_pad_press(aim_pad, 3)
	await process_frame
	_aim_pad_drag(aim_pad, 3, Vector2(20, 0))
	await process_frame
	_reticle._follow(0.0)
	var small_dir: Vector2 = _pi.aim_vector
	var small_reticle: Vector2 = _reticle.global_position
	_aim_pad_drag(aim_pad, 3, Vector2(100, 0))
	await process_frame
	_reticle._follow(0.0)
	var large_dir: Vector2 = _pi.aim_vector
	var large_reticle: Vector2 = _reticle.global_position
	_expect(small_dir.is_equal_approx(Vector2.RIGHT), "小拖 -> RIGHT")
	_expect(large_dir.is_equal_approx(Vector2.RIGHT), "大拖 -> RIGHT")
	_expect(small_dir.is_equal_approx(large_dir), "20px 与 100px 方向相同")
	_expect(small_reticle.is_equal_approx(large_reticle), "20px 与 100px 准星距离相同")
	_expect(_host.global_position.distance_to(small_reticle) > 100.0, "准星在固定距离上，不在玩家中心")
	_expect(small_dir.length() > 0.99 and small_dir.length() < 1.01, "输出单位方向无 magnitude")
	_aim_pad_release(aim_pad, 3)
	await process_frame
	_reticle._follow(0.0)
	_expect(_pi.aim_vector.is_zero_approx(), "release -> aim ZERO")
	_expect(_reticle.global_position.is_equal_approx(_host.global_position), "release -> 准星回玩家中心")

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

## Manual Fire Button：默认隐藏（右摇杆 = Aim + Fire）；ON 时出现，且只有它能开火。
## 覆盖三个回归点：FIRE 按钮在场景里真的存在、可见性跟 GameSettings 走、
## 按住 FIRE 时把开关切回 OFF 必须清掉 held（不能停不下来）。
func _case_manual_fire_button() -> void:
	var fire: TouchActionButton = _tc.get_fire_button()
	_expect(fire != null, "TouchControls 暴露 FIRE 按钮")
	if fire == null:
		return
	_expect(not fire.visible, "Manual Fire OFF：FIRE 按钮默认隐藏")
	_expect(fire.get_icon_node() != null, "FIRE 按钮带矢量 icon")
	_expect(fire.get_visual_variation() == "TouchActionButtonPrimary", "FIRE 按钮用 Primary token")

	GameSettings.set_touch_manual_fire(true)
	await process_frame
	await process_frame
	_expect(fire.visible, "Manual Fire ON：FIRE 按钮出现")

	var aim: TouchAimPad = _tc.get_aim_pad()
	_aim_pad_press(aim, 11, Vector2(0, -80))
	await process_frame
	_expect(aim.is_active(), "Manual Fire：AimPad 仍可按住")
	_expect(_pi.aim_vector.y < 0.0, "Manual Fire：AimPad 仍瞄准")
	_expect(not _pi.fire_held, "Manual Fire：AimPad 不再自动开火")

	_button_press(fire, 12)
	await process_frame
	_expect(fire.is_held(), "FIRE 按钮可按下")
	_expect(fire.get_visual_variation() == "TouchActionButtonPrimaryHeld", "FIRE 按下切到 held token")
	_expect(_pi.fire_held, "Manual Fire：FIRE 按钮开火")
	_button_release(fire, 12)
	await process_frame
	_expect(not _pi.fire_held, "FIRE 松开 -> 停火")

	## 按住 FIRE 的同时关掉开关：FIRE 的 held 必须一起清掉（否则 fire 停不下来）。
	## 先把右摇杆松开，避免命中「Manual Fire OFF + 右摇杆 active = 自动开火」这条正常合同。
	_aim_pad_release(aim, 11)
	await process_frame
	_button_press(fire, 13)
	await process_frame
	_expect(_pi.fire_held, "关掉开关前 FIRE 开火")
	GameSettings.set_touch_manual_fire(false)
	await process_frame
	await process_frame
	_expect(not fire.visible, "Manual Fire OFF：FIRE 按钮重新隐藏")
	_expect(not _pi.fire_held, "切回 OFF -> FIRE 的 held 释放，无残留")
	_button_release(fire, 13)
	await process_frame
	_expect(not _pi.fire_held, "FIRE 按钮隐藏后松手仍无残留")

## 按下反馈 + stylebox 名字合同：
## Panel 读的是 "panel"（不是 "normal"），写错会静默 fallback 到 Godot 默认 Panel（圆角 3 的深灰方块）。
func _case_pressed_visuals() -> void:
	var stick: VirtualStick = _tc.get_move_stick()
	var knob: Panel = stick.get_node_or_null("Knob") as Panel
	_expect(knob != null, "左摇杆有 Knob")
	if knob != null:
		var sb: StyleBoxFlat = knob.get_theme_stylebox("panel") as StyleBoxFlat
		_expect(sb != null, "Knob 从 theme 拿到 panel stylebox")
		_expect(sb == null or sb.corner_radius_top_left >= 100.0,
			"Knob 是圆盘 token（styles/panel 生效，不是默认 Panel 的圆角 3）")
		_expect(knob.theme_type_variation == "TouchStickKnob", "Knob 常态用 TouchStickKnob")
		_stick_press(stick, 21, Vector2(60, 0))
		await process_frame
		_expect(knob.theme_type_variation == "TouchStickKnobActive", "摇杆按住 -> Knob 切 active token")
		_stick_release(stick, 21)
		await process_frame
		_expect(knob.theme_type_variation == "TouchStickKnob", "摇杆松开 -> Knob 回常态 token")

	var aim: TouchAimPad = _tc.get_aim_pad()
	var center: TouchIcon = aim.get_node_or_null("Center") as TouchIcon
	_expect(center != null, "AimPad 中心是矢量准星（TouchIcon）")
	if center != null:
		_expect(center.get_glyph() == TouchIcon.Glyph.CROSSHAIR, "AimPad 中心 glyph = CROSSHAIR")
		_expect(not center.is_active_state(), "AimPad 未按时准星是常态")
		_aim_pad_press(aim, 22, Vector2(0, -70))
		await process_frame
		_expect(center.is_active_state(), "AimPad 按住 -> 中心准星提亮")
		_aim_pad_release(aim, 22)
		await process_frame
		_expect(not center.is_active_state(), "AimPad 松开 -> 中心准星回常态")

func _expect(condition: bool, label: String) -> void:
	if not condition:
		_failures.append(label)
