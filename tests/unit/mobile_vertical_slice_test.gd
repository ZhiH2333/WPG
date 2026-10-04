extends SceneTree

## Mobile Vertical Slice 验收测试（真机流程的可 headless 复刻）。
## 覆盖：MainMenu 可加载 -> Start Game 目标 CombatSandbox -> 真实 Touch 输入
## -> Pause -> Resume。
## 验证：TouchControls 存在、PlayerInput 收到输入、Fire 释放、Pause 状态恢复。
## 跑法：godot --headless --path . --script res://tests/mobile_vertical_slice_test.gd
## 通过输出 MOBILE_VERTICAL_SLICE_OK；失败逐条 ..._FAIL 并返回非 0。

var _failures: PackedStringArray = PackedStringArray()
var _sandbox: Node
var _touch: TouchControls
var _player: Player
var _pi: PlayerInput
var _pause: PauseOverlay

func _initialize() -> void:
	_run()

func _run() -> void:
	await process_frame
	PlayerProfile.load_from_disk()
	GameSettings.load_from_disk()
	root.size = Vector2i(2400, 1080)

	await _case_menu_loads_and_targets_combat()
	await _case_start_game_into_combat()
	await _case_touch_controls_exist_and_bound()
	await _case_touch_move_aim_fire()
	await _case_touch_dash_and_weapon()
	await _case_fire_released_on_aim_release()
	await _case_pause_via_touch_button()
	await _case_resume_restores_touch()

	_teardown()
	await process_frame

	if _failures.is_empty():
		print("MOBILE_VERTICAL_SLICE_OK")
		quit(0)
		return
	for failure: String in _failures:
		printerr("MOBILE_VERTICAL_SLICE_FAIL: %s" % failure)
	quit(1)

# ---- MainMenu -> Start Game ----

## MainMenu 可加载，且 Start Game 流程指向 combat_sandbox（vertical slice 目的地）。
func _case_menu_loads_and_targets_combat() -> void:
	var menu_scene: PackedScene = load("res://ui/main_menu.tscn")
	_expect(menu_scene != null, "MainMenu 场景可加载")
	var menu: Node = menu_scene.instantiate()
	_expect(menu != null, "MainMenu 可实例化")
	if menu != null:
		menu.queue_free()
	await process_frame
	var sandbox_scene: PackedScene = load("res://sandbox/combat_sandbox.tscn")
	_expect(sandbox_scene != null, "Start Game 目标 CombatSandbox 可加载")

## 进入 Combat：实例化真实 CombatSandbox，等待 runtime 绑定完成。
func _case_start_game_into_combat() -> void:
	var scene: PackedScene = load("res://sandbox/combat_sandbox.tscn")
	_sandbox = scene.instantiate()
	root.add_child(_sandbox)
	await process_frame
	## CombatSandbox._ready() 会 load_from_disk()，把 touch mode 复位成持久值；
	## 测试在 ready 之后再开 Touch，模拟真机移动平台 AUTO=ON。
	GameSettings.set_touch_controls_mode(GameSettings.TouchControlsMode.ON)
	for _i: int in 5:
		await process_frame
	_touch = _sandbox.get_node_or_null("TouchControls") as TouchControls
	_player = _sandbox.get_node_or_null("ViewportContainer/GameViewport/World/Player") as Player
	_pause = _sandbox.get_node_or_null("PauseOverlay") as PauseOverlay
	_expect(_touch != null, "Combat 中存在 TouchControls")
	_expect(_player != null, "Combat 中存在本地 Player")
	if _player != null:
		_pi = _player.get_player_input()
	_expect(_pi != null, "Player 暴露 PlayerInput")
	_expect(_pause != null, "Combat 中存在 PauseOverlay")

# ---- TouchControls 存在且经 PlayerInput ----

func _case_touch_controls_exist_and_bound() -> void:
	if _touch == null or _pi == null:
		_expect(false, "TouchControls / PlayerInput 缺失，无法验证绑定")
		return
	_touch.refresh_visibility()
	await process_frame
	_expect(_touch.is_touch_visible(), "Touch 开启时 TouchControls 可见")
	_expect(_touch.get_touch_input() != null, "TouchControls 持有 TouchInput 适配层")
	_expect(_touch.get_move_stick() != null, "存在左摇杆")
	_expect(_touch.get_aim_pad() != null, "存在右 Aim Pad")
	_expect(_touch.get_dash_button() != null, "存在 Dash 按钮")
	for slot: int in 4:
		_expect(_touch.get_weapon_button(slot) != null, "存在 Weapon %d 按钮" % (slot + 1))
	_expect(_touch.get_pause_button() != null, "存在 Pause 按钮")

# ---- 真实 Touch 事件链 ----

func _stick_press(stick: Control, index: int, offset: Vector2) -> void:
	var center: Vector2 = (stick.global_position + stick.size * 0.5) * root.content_scale_factor
	var ev: InputEventScreenTouch = InputEventScreenTouch.new()
	ev.index = index
	ev.pressed = true
	ev.position = center + offset * root.content_scale_factor
	root.push_input(ev)

func _stick_drag(stick: Control, index: int, offset: Vector2) -> void:
	var center: Vector2 = (stick.global_position + stick.size * 0.5) * root.content_scale_factor
	var ev: InputEventScreenDrag = InputEventScreenDrag.new()
	ev.index = index
	ev.position = center + offset * root.content_scale_factor
	ev.screen_relative = offset * root.content_scale_factor
	root.push_input(ev)

func _stick_release(stick: Control, index: int) -> void:
	var center: Vector2 = (stick.global_position + stick.size * 0.5) * root.content_scale_factor
	var ev: InputEventScreenTouch = InputEventScreenTouch.new()
	ev.index = index
	ev.pressed = false
	ev.position = center
	root.push_input(ev)

func _button_press(btn: TouchActionButton, index: int) -> void:
	var c: Vector2 = (btn.global_position + btn.button_size * 0.5) * root.content_scale_factor
	var ev: InputEventScreenTouch = InputEventScreenTouch.new()
	ev.index = index
	ev.pressed = true
	ev.position = c
	root.push_input(ev)

func _button_release(btn: TouchActionButton, index: int) -> void:
	var c: Vector2 = (btn.global_position + btn.button_size * 0.5) * root.content_scale_factor
	var ev: InputEventScreenTouch = InputEventScreenTouch.new()
	ev.index = index
	ev.pressed = false
	ev.position = c
	root.push_input(ev)

## 左摇杆移动 + 右 Aim Pad 瞄准自动开火。
func _case_touch_move_aim_fire() -> void:
	if _pi == null:
		return
	var move: VirtualStick = _touch.get_move_stick()
	var aim: TouchAimPad = _touch.get_aim_pad()
	_stick_press(move, 0, Vector2.ZERO)
	_stick_press(aim, 1, Vector2.ZERO)
	await process_frame
	_stick_drag(move, 0, Vector2(80, 0))
	_stick_drag(aim, 1, Vector2(0, -80))
	await process_frame
	_expect(_pi.move_vector.x > 0.0, "Touch 左摇杆驱动 move")
	_expect(_pi.aim_vector.y < 0.0, "Touch Aim Pad 驱动 aim")
	_expect(_pi.fire_held, "Aim Pad active -> 自动开火")

## Dash / Weapon 按钮经 TouchInput -> PlayerInput 边沿。
func _case_touch_dash_and_weapon() -> void:
	if _pi == null:
		return
	var dash: TouchActionButton = _touch.get_dash_button()
	_button_press(dash, 4)
	await process_frame
	await physics_frame
	await process_frame
	_expect(_pi.take_pending_dash() or _pi.dash_just_pressed, "Touch Dash 触发")
	_button_release(dash, 4)
	await process_frame
	var weapon: TouchActionButton = _touch.get_weapon_button(1)
	_button_press(weapon, 5)
	await process_frame
	await process_frame
	_expect(_pi.take_pending_weapon_slot() == 1, "Touch Weapon 2 -> slot 1")
	_button_release(weapon, 5)
	await process_frame

## 松开 Aim Pad：aim 归 ZERO，fire 释放（Fire 不得残留）。
func _case_fire_released_on_aim_release() -> void:
	if _pi == null:
		return
	var aim: TouchAimPad = _touch.get_aim_pad()
	_stick_release(aim, 1)
	await process_frame
	_expect(not _pi.fire_held, "Aim 松开 -> fire 释放，无残留")
	_expect(_pi.aim_vector.is_zero_approx(), "Aim 松开 -> aim 归 ZERO，无残留")
	var move: VirtualStick = _touch.get_move_stick()
	_stick_release(move, 0)
	await process_frame
	_expect(_pi.move_vector.is_zero_approx(), "左摇杆松开 -> move 归零")
	_expect(not _pi.fire_held, "松手后 fire 仍为 false")

# ---- Pause / Resume ----

## Touch Pause 按钮 -> PauseOverlay 打开；TouchControls 停用，Fire 释放。
func _case_pause_via_touch_button() -> void:
	if _touch == null or _pause == null:
		return
	## 先制造一个 held 状态，验证 Pause 会清掉。
	var aim: TouchAimPad = _touch.get_aim_pad()
	_stick_press(aim, 2, Vector2(0, -80))
	await process_frame
	_expect(_pi.fire_held, "Pause 前 Aim active -> fire")
	var pause_btn: TouchActionButton = _touch.get_pause_button()
	_button_press(pause_btn, 3)
	await process_frame
	await process_frame
	_expect(_pause.is_open(), "Touch Pause 按钮打开 PauseOverlay")
	_expect(_touch.is_modal_blocked(), "Pause 打开 -> TouchControls 被 modal 屏蔽")
	_expect(not _pi.fire_held, "Pause 打开 -> fire 释放，无残留")
	_expect(_pi.move_vector.is_zero_approx(), "Pause 打开 -> move 归零")
	_button_release(pause_btn, 3)
	await process_frame

## Resume：PauseOverlay 关闭，TouchControls / PlayerInput 恢复。
func _case_resume_restores_touch() -> void:
	if _touch == null or _pause == null:
		return
	_pause._on_continue_pressed()
	await process_frame
	await process_frame
	_expect(not _pause.is_open(), "Resume 后 PauseOverlay 关闭")
	_expect(not _touch.is_modal_blocked(), "Resume 后 TouchControls 解除屏蔽")
	var aim: TouchAimPad = _touch.get_aim_pad()
	_stick_press(aim, 7, Vector2(0, -80))
	await process_frame
	_expect(_pi.aim_vector.y < 0.0, "Resume 后 Touch Aim 恢复")
	_expect(_pi.fire_held, "Resume 后 Touch Fire 恢复")
	_stick_release(aim, 7)
	await process_frame
	_expect(not _pi.fire_held, "Resume 后释放仍正确")

func _teardown() -> void:
	paused = false
	if _sandbox != null and is_instance_valid(_sandbox):
		_sandbox.queue_free()

func _expect(condition: bool, label: String) -> void:
	if not condition:
		_failures.append(label)
