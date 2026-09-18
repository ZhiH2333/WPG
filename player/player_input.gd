extends Node
class_name PlayerInput

## 鼠标与玩家过近时不重新归一化，避免 aim_vector 出现 NaN。
const AIM_DEADZONE_SQ: float = 0.0001
const DEVICE_KEYBOARD: int = -1
const STICK_DEADZONE: float = 0.25
const FIRE_TRIGGER: float = 0.45
const AIM_LEAD_PX: float = 140.0
const MOUSE_STEAL_PX: float = 2.0
## 手柄右摇杆转向的非线性平滑，越大转向越快。alpha = 1 - exp(-AIM_TURN_SMOOTHING * delta)，与相机跟随同一手法。
const AIM_TURN_SMOOTHING: float = 14.0
const DPAD_BUTTONS: Array[int] = [
	JOY_BUTTON_DPAD_LEFT,
	JOY_BUTTON_DPAD_UP,
	JOY_BUTTON_DPAD_RIGHT,
	JOY_BUTTON_DPAD_DOWN,
]

## 全项目唯一输入合同：键鼠或单把手柄（device_id）。只产出 move/aim/fire。切枪仍由 WeaponHost 另读 1/2/3/4 或该手柄十字键。Dash 不进三量。
var move_vector: Vector2 = Vector2.ZERO
var aim_vector: Vector2 = Vector2.RIGHT
var fire_held: bool = false
var dash_just_pressed: bool = false
var mouse_world_position: Vector2 = Vector2.ZERO
var _fire_suppressed: bool = false
var _dash_suppressed: bool = false
var _need_fire_release: bool = false
var _device_id: int = DEVICE_KEYBOARD
var _device_pinned: bool = false
var _weapon_slot_just_pressed: int = -1
var _dpad_held: PackedByteArray = PackedByteArray()
var _joy_a_held: bool = false
var _need_dash_release: bool = false
var _last_mouse_world: Vector2 = Vector2.ZERO
var _has_last_mouse: bool = false
var _remote_driven: bool = false
var _pending_weapon_slot: int = -1
var _pending_dash: bool = false

func _enter_tree() -> void:
	## 小于 0 更早处理，让同一帧的朝向、相机、准星读到本帧输入。
	process_priority = -100
	process_physics_priority = -100
	_dpad_held.resize(4)

func _process(delta: float) -> void:
	update_input(delta)

func _physics_process(_delta: float) -> void:
	if _remote_driven:
		return
	dash_just_pressed = false
	_update_dash_pressed()

func get_device_id() -> int:
	return _device_id

func set_device_id(id: int) -> void:
	_device_id = id
	_device_pinned = true

func get_weapon_slot_just_pressed() -> int:
	return _weapon_slot_just_pressed

func set_remote_driven(enabled: bool) -> void:
	_remote_driven = enabled
	if not enabled:
		return
	_device_pinned = true
	move_vector = Vector2.ZERO
	fire_held = false
	dash_just_pressed = false

func is_remote_driven() -> bool:
	return _remote_driven

func apply_remote_frame(move: Vector2, aim: Vector2, fire: bool, dash: bool, weapon_slot: int) -> void:
	move_vector = move
	if aim.is_zero_approx():
		_keep_last_aim()
	else:
		aim_vector = aim.normalized()
	var host: Node2D = get_parent() as Node2D
	if host != null:
		mouse_world_position = host.global_position + aim_vector * AIM_LEAD_PX
	if _fire_suppressed:
		fire_held = false
	else:
		fire_held = fire
	if _dash_suppressed:
		dash_just_pressed = false
	else:
		dash_just_pressed = dash
	if dash:
		_pending_dash = true
	_weapon_slot_just_pressed = weapon_slot
	_pending_weapon_slot = weapon_slot

func take_pending_weapon_slot() -> int:
	var slot: int = _pending_weapon_slot
	_pending_weapon_slot = -1
	return slot

func take_pending_dash() -> bool:
	var pressed: bool = _pending_dash
	_pending_dash = false
	return pressed

func update_input(delta: float = 0.0) -> void:
	if _remote_driven:
		return
	_weapon_slot_just_pressed = -1
	_latch_weapon_keys()
	if not _device_pinned:
		_claim_device()
	if _device_id >= 0 and not _is_joy_connected(_device_id):
		_device_id = DEVICE_KEYBOARD
		move_vector = Vector2.ZERO
		fire_held = false
		_joy_a_held = false
		_keep_last_aim()
		_clear_dpad_held()
		return
	if _device_id >= 0:
		_update_from_joy(delta)
		return
	_clear_dpad_held()
	_joy_a_held = false
	_update_move_vector()
	_update_aim_vector()
	_update_fire_held()

func set_fire_suppressed(suppressed: bool) -> void:
	_fire_suppressed = suppressed
	if suppressed:
		fire_held = false
		_need_fire_release = true
		return
	if _device_id == DEVICE_KEYBOARD:
		if Input.is_action_pressed("fire"):
			_need_fire_release = true
			fire_held = false
		return
	if _device_id >= 0 and _joy_wants_fire(_device_id):
		_need_fire_release = true
		fire_held = false

func set_dash_suppressed(suppressed: bool) -> void:
	_dash_suppressed = suppressed
	if suppressed:
		dash_just_pressed = false
		_need_dash_release = true
		return
	if _is_dash_held():
		_need_dash_release = true
		dash_just_pressed = false

func is_dash_suppressed() -> bool:
	return _dash_suppressed

func _claim_device() -> void:
	var old_device: int = _device_id
	if _keyboard_wants_control():
		_device_id = DEVICE_KEYBOARD
	else:
		var claimed: int = DEVICE_KEYBOARD
		for id: int in Input.get_connected_joypads():
			if _joy_wants_control(id):
				claimed = id
		if claimed != DEVICE_KEYBOARD:
			_device_id = claimed
	if _device_id != old_device:
		fire_held = false
		_need_fire_release = true

func _keyboard_wants_control() -> bool:
	if _device_id == DEVICE_KEYBOARD:
		return false
	if Input.is_action_pressed("move_left") or Input.is_action_pressed("move_right") or Input.is_action_pressed("move_up") or Input.is_action_pressed("move_down"):
		return true
	var viewport: Viewport = get_viewport()
	if viewport == null:
		return false
	var mouse_now: Vector2 = viewport.get_mouse_position()
	if not _has_last_mouse:
		_last_mouse_world = mouse_now
		_has_last_mouse = true
		return false
	var moved: bool = mouse_now.distance_to(_last_mouse_world) >= MOUSE_STEAL_PX
	_last_mouse_world = mouse_now
	return moved

func _joy_wants_control(id: int) -> bool:
	if _read_stick(id, JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y).length() >= STICK_DEADZONE:
		return true
	if _read_stick(id, JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y).length() >= STICK_DEADZONE:
		return true
	if _joy_wants_fire(id):
		return true
	if Input.is_joy_button_pressed(id, JOY_BUTTON_A):
		return true
	for slot: int in DPAD_BUTTONS.size():
		if Input.is_joy_button_pressed(id, DPAD_BUTTONS[slot]):
			return true
	return false

func _joy_wants_fire(id: int) -> bool:
	## Godot 的扳机轴本身就是 0（松开）～1（扣到底），不需要再从 -1~1 重新映射。
	var trigger: float = Input.get_joy_axis(id, JOY_AXIS_TRIGGER_RIGHT)
	if trigger >= FIRE_TRIGGER:
		return true
	return Input.is_joy_button_pressed(id, JOY_BUTTON_RIGHT_SHOULDER)

func _update_from_joy(delta: float) -> void:
	var id: int = _device_id
	move_vector = _read_move_stick(id)
	var aim: Vector2 = _read_aim_stick(id)
	if aim.is_zero_approx():
		_keep_last_aim()
	else:
		aim_vector = _turn_aim_toward(aim_vector, aim, delta)
	var host: Node2D = get_parent() as Node2D
	if host != null:
		mouse_world_position = host.global_position + aim_vector * AIM_LEAD_PX
	_update_dpad_edges(id)
	if _fire_suppressed:
		fire_held = false
		return
	var want_fire: bool = _joy_wants_fire(id)
	if _need_fire_release:
		if want_fire:
			fire_held = false
			return
		_need_fire_release = false
	fire_held = want_fire

func _read_stick(id: int, x_axis: int, y_axis: int) -> Vector2:
	return Vector2(Input.get_joy_axis(id, x_axis), Input.get_joy_axis(id, y_axis))

func _read_move_stick(id: int) -> Vector2:
	var raw: Vector2 = _read_stick(id, JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y)
	var length: float = raw.length()
	if length < STICK_DEADZONE:
		return Vector2.ZERO
	var scaled: float = clampf((length - STICK_DEADZONE) / (1.0 - STICK_DEADZONE), 0.0, 1.0)
	return raw * (scaled / length)

func _read_aim_stick(id: int) -> Vector2:
	var raw: Vector2 = _read_stick(id, JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y)
	if raw.length() < STICK_DEADZONE:
		return Vector2.ZERO
	return raw.normalized()

func _turn_aim_toward(current: Vector2, target: Vector2, delta: float) -> Vector2:
	if delta <= 0.0:
		return target
	var alpha: float = 1.0 - exp(-AIM_TURN_SMOOTHING * delta)
	var eased_angle: float = lerp_angle(current.angle(), target.angle(), alpha)
	return Vector2.RIGHT.rotated(eased_angle)

func _update_dpad_edges(id: int) -> void:
	for slot: int in DPAD_BUTTONS.size():
		var pressed: bool = Input.is_joy_button_pressed(id, DPAD_BUTTONS[slot])
		var was_held: bool = _dpad_held[slot] != 0
		if pressed and not was_held and _weapon_slot_just_pressed < 0:
			_weapon_slot_just_pressed = slot
			_pending_weapon_slot = slot
		_dpad_held[slot] = 1 if pressed else 0

func _clear_dpad_held() -> void:
	for slot: int in _dpad_held.size():
		_dpad_held[slot] = 0

func _is_joy_connected(id: int) -> bool:
	return Input.get_connected_joypads().has(id)

func _latch_weapon_keys() -> void:
	if Input.is_action_just_pressed("weapon_pistol"):
		_weapon_slot_just_pressed = 0
		_pending_weapon_slot = 0
		return
	if Input.is_action_just_pressed("weapon_shotgun"):
		_weapon_slot_just_pressed = 1
		_pending_weapon_slot = 1
		return
	if Input.is_action_just_pressed("weapon_rifle"):
		_weapon_slot_just_pressed = 2
		_pending_weapon_slot = 2
		return
	if Input.is_action_just_pressed("weapon_smg"):
		_weapon_slot_just_pressed = 3
		_pending_weapon_slot = 3

func _update_move_vector() -> void:
	move_vector = Input.get_vector("move_left", "move_right", "move_up", "move_down")

func _update_aim_vector() -> void:
	var host: Node2D = get_parent() as Node2D
	if host == null:
		return
	mouse_world_position = host.get_global_mouse_position()
	var to_mouse: Vector2 = mouse_world_position - host.global_position
	if to_mouse.length_squared() < AIM_DEADZONE_SQ:
		_keep_last_aim()
		return
	aim_vector = to_mouse.normalized()

func _keep_last_aim() -> void:
	if aim_vector.is_zero_approx():
		aim_vector = Vector2.RIGHT

func _update_fire_held() -> void:
	if _fire_suppressed:
		fire_held = false
		return
	var pressed: bool = Input.is_action_pressed("fire")
	if _need_fire_release:
		if pressed:
			fire_held = false
			return
		_need_fire_release = false
	fire_held = pressed

func _is_dash_held() -> bool:
	if _device_id >= 0:
		return Input.is_joy_button_pressed(_device_id, JOY_BUTTON_A)
	return Input.is_action_pressed("dash")

func _update_dash_pressed() -> void:
	var edge: bool = false
	if _device_id >= 0:
		var pressed: bool = Input.is_joy_button_pressed(_device_id, JOY_BUTTON_A)
		edge = pressed and not _joy_a_held
		_joy_a_held = pressed
	else:
		edge = Input.is_action_just_pressed("dash")
	if _dash_suppressed:
		dash_just_pressed = false
		return
	if _need_dash_release:
		if _is_dash_held():
			dash_just_pressed = false
			return
		_need_dash_release = false
	dash_just_pressed = edge
	if edge:
		_pending_dash = true
