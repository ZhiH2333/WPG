extends Node
class_name PlayerInput

## 鼠标与玩家过近时不重新归一化，避免 aim_vector 出现 NaN。
const AIM_DEADZONE_SQ: float = 0.0001
const DEVICE_KEYBOARD: int = -1
## 只给左摇杆走速和 _joy_wants_control 的左杆判定。不要拿来滤瞄准。
const STICK_DEADZONE: float = 0.25
## 只滤右摇杆静止漂移，不是手感延迟。「动一点」必须出这圈。瞄准没有半行程。
const AIM_STICK_DEADZONE: float = 0.12
const FIRE_TRIGGER: float = 0.45
const AIM_LEAD_PX: float = 140.0
const MOUSE_STEAL_PX: float = 2.0
const JOY_WEAPON_SLOT_COUNT: int = 4
## 技能槽位固定 2 个：ability_0 / ability_1。
const ABILITY_SLOT_COUNT: int = 2
## InputMap action 名。键鼠与手柄共用同一条 action，不按设备分叉。
const ABILITY_ACTIONS := ["ability_0", "ability_1"]

## 全项目唯一输入合同。三个 source：Keyboard/Mouse、Gamepad、Touch。只产出 move/aim/fire。
## 切枪仍由 WeaponHost 另读 1/2/3/4 或该手柄当前绑定的枪钮。Dash 不进三量。
## Touch 通过正式 API 写入内部 _touch_* state，update_input() 依 source 优先级选一套输出，
## 不再让 TouchInput 每帧抢写公开字段。
var move_vector: Vector2 = Vector2.ZERO
var aim_vector: Vector2 = Vector2.RIGHT
var fire_held: bool = false
var dash_just_pressed: bool = false
## 技能键边沿。与 dash 同为 edge：按下当帧 true，按住不重复，松开后才能再来一次。
var ability_0_just_pressed: bool = false
var ability_1_just_pressed: bool = false
var mouse_world_position: Vector2 = Vector2.ZERO
var _fire_suppressed: bool = false
var _dash_suppressed: bool = false
var _need_fire_release: bool = false
var _device_id: int = DEVICE_KEYBOARD
var _device_pinned: bool = false
var _weapon_slot_just_pressed: int = -1
var _joy_weapon_held: PackedByteArray = PackedByteArray()
var _joy_dash_held: bool = false
var _need_dash_release: bool = false
var _last_mouse_world: Vector2 = Vector2.ZERO
var _has_last_mouse: bool = false
var _remote_driven: bool = false
var _pending_weapon_slot: int = -1
var _pending_dash: bool = false
var _abilities_suppressed: bool = false
## Touch 技能边沿队列（每槽 0/1）：由 queue_touch_ability() 写入，_physics_process 消费。
var _touch_ability_pending: PackedByteArray = PackedByteArray()

## Touch source state：仅由 TouchControls 的正式 API 写入。
## Touch Aim 只表达方向，不表达距离：active=false 时 aim_vector 归 ZERO，准星回玩家中心。
var _touch_enabled: bool = false
var _touch_move_vector: Vector2 = Vector2.ZERO
var _touch_aim_vector: Vector2 = Vector2.ZERO
var _touch_aim_active: bool = false
var _touch_fire_held: bool = false
var _touch_dash_pending: bool = false
var _touch_weapon_slot_pending: int = -1
## Manual Fire ON 时右摇杆只瞄准，不自动开火，由 FIRE 按钮开火。
var _touch_manual_fire_mode: bool = false

func _enter_tree() -> void:
	## 小于 0 更早处理，让同一帧的朝向、相机、准星读到本帧输入。
	process_priority = -100
	process_physics_priority = -100
	_joy_weapon_held.resize(JOY_WEAPON_SLOT_COUNT)
	_ensure_ability_slots()

func _process(_delta: float) -> void:
	update_input()

func _physics_process(_delta: float) -> void:
	if _remote_driven:
		return
	dash_just_pressed = false
	_update_dash_pressed()
	_update_ability_edges()

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
	clear_touch_state()

func is_remote_driven() -> bool:
	return _remote_driven

## ---- Touch source 正式运行时 API ----
## 由 TouchControls / TouchInput 调用。不直接写公开输出字段，等 update_input() 统一合成。

func set_touch_active(active: bool) -> void:
	if _touch_enabled == active:
		return
	_touch_enabled = active
	if not active:
		_clear_touch_state()
		return
	## 接管瞬间清掉键鼠/手柄的 held，避免松开瞬间仍在开火。
	fire_held = false
	_need_fire_release = false

func is_touch_active() -> bool:
	return _touch_enabled

## Touch AimPad 是否正在给出方向。false 时 aim_vector 归 ZERO，准星/相机回玩家中心。
func is_touch_aim_active() -> bool:
	return _touch_enabled and _touch_aim_active

func set_touch_move_vector(value: Vector2) -> void:
	_touch_move_vector = value

## Touch Aim direction-only 正式 API：
## active=true  -> 记录归一化方向（忽略 magnitude，Aim 距离由游戏常量固定）
## active=false -> 清 active 并丢弃方向，下一帧 aim_vector 归 ZERO，准星回玩家中心
func set_touch_aim_vector(value: Vector2, active: bool) -> void:
	if not active:
		_touch_aim_active = false
		_touch_aim_vector = Vector2.ZERO
		return
	if value.is_zero_approx():
		_touch_aim_active = false
		_touch_aim_vector = Vector2.ZERO
		return
	_touch_aim_active = true
	_touch_aim_vector = value.normalized()

func set_touch_fire_held(value: bool) -> void:
	_touch_fire_held = value

func set_touch_manual_fire_mode(enabled: bool) -> void:
	_touch_manual_fire_mode = enabled
	if not enabled:
		## 关掉 Manual Fire 时 FIRE 按钮被隐藏 / 复位，released 不会再来：
		## 必须在这里丢掉 held，否则下一帧 _update_from_touch() 会一直开火。
		_touch_fire_held = false

func is_touch_manual_fire_mode() -> bool:
	return _touch_manual_fire_mode

func queue_touch_dash() -> void:
	_touch_dash_pending = true

func queue_touch_weapon_slot(slot: int) -> void:
	_touch_weapon_slot_pending = slot

func take_touch_weapon_slot() -> int:
	var slot: int = _touch_weapon_slot_pending
	_touch_weapon_slot_pending = -1
	return slot

## ---- Ability source 正式运行时 API ----
## Touch 只负责把「按了 A0 / A1」变成一次输入边沿（queue_touch_ability），
## 绝不直接调用 AbilityController。AbilityController 只读本类的 ability_*_just_pressed。

func queue_touch_ability(slot: int) -> void:
	if slot < 0 or slot >= ABILITY_SLOT_COUNT:
		return
	_ensure_ability_slots()
	_touch_ability_pending[slot] = 1

## Pause / Modal：不产出技能边沿。已在冷却中的技能状态不受影响，只是不能再放。
func set_abilities_suppressed(suppressed: bool) -> void:
	_abilities_suppressed = suppressed
	if suppressed:
		ability_0_just_pressed = false
		ability_1_just_pressed = false
		_clear_touch_ability_pending()

func is_abilities_suppressed() -> bool:
	return _abilities_suppressed

func _ensure_ability_slots() -> void:
	if _touch_ability_pending.size() != ABILITY_SLOT_COUNT:
		_touch_ability_pending.resize(ABILITY_SLOT_COUNT)

func _clear_touch_ability_pending() -> void:
	_ensure_ability_slots()
	for slot: int in _touch_ability_pending.size():
		_touch_ability_pending[slot] = 0

func clear_touch_state() -> void:
	_clear_touch_state()

func _clear_touch_state() -> void:
	_touch_move_vector = Vector2.ZERO
	_touch_aim_vector = Vector2.ZERO
	_touch_aim_active = false
	_touch_fire_held = false
	_touch_dash_pending = false
	_touch_weapon_slot_pending = -1
	_clear_touch_ability_pending()

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

func update_input(_delta: float = 0.0) -> void:
	if _remote_driven:
		return
	_weapon_slot_just_pressed = -1
	## 键鼠 1/2/3/4 与手柄枪钮始终保留，但 Touch 切枪在下方单独出队，不互相覆盖。
	_latch_weapon_keys()
	if _touch_enabled:
		_update_from_touch()
		return
	if not _device_pinned:
		_claim_device()
	if _device_id >= 0 and not _is_joy_connected(_device_id):
		_device_id = DEVICE_KEYBOARD
		move_vector = Vector2.ZERO
		fire_held = false
		_joy_dash_held = false
		_keep_last_aim()
		_clear_joy_weapon_held()
		return
	if _device_id >= 0:
		_update_from_joy()
		return
	_clear_joy_weapon_held()
	_joy_dash_held = false
	_update_move_vector()
	_update_aim_vector()
	_update_fire_held()

## Touch source：Touch Active 时独占 move/aim/fire/dash/weapon，不再读键鼠/手柄。
## Aim direction-only：AimPad 未按时 aim_vector 归 ZERO，准星与相机同时回玩家中心。
func _update_from_touch() -> void:
	move_vector = _touch_move_vector
	if _touch_aim_active:
		aim_vector = _touch_aim_vector
	else:
		aim_vector = Vector2.ZERO
	var host: Node2D = get_parent() as Node2D
	if host != null:
		mouse_world_position = host.global_position + aim_vector * AIM_LEAD_PX
	if _touch_weapon_slot_pending >= 0:
		_weapon_slot_just_pressed = _touch_weapon_slot_pending
		_pending_weapon_slot = _touch_weapon_slot_pending
		_touch_weapon_slot_pending = -1
	## Touch dash 由 _physics_process 的 _update_dash_pressed() 单帧消费，这里不处理。
	## 右摇杆 active 即开火（Manual Fire OFF）；Manual Fire ON 只认 FIRE 按钮。
	var want_fire: bool = _touch_fire_held
	if not _touch_manual_fire_mode and _touch_aim_active:
		want_fire = true
	if _fire_suppressed:
		fire_held = false
		return
	fire_held = want_fire

func set_fire_suppressed(suppressed: bool) -> void:
	_fire_suppressed = suppressed
	if suppressed:
		fire_held = false
		_need_fire_release = true
		return
	if _touch_enabled:
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
	if _touch_enabled:
		return
	if _is_dash_held():
		_need_dash_release = true
		dash_just_pressed = false

func is_dash_suppressed() -> bool:
	return _dash_suppressed

## 右摇杆与日后虚拟摇杆共用的瞄准映射。模长低于 AIM_STICK_DEADZONE 返回 ZERO（调用方走 keep last）；否则返回单位向量，当帧对准。瞄准没有半瞄准，也不做转向平滑。虚拟摇杆必须把「指尖相对基座 / 基座半径」得到的 Vector2（建议已 clamp 到长度≤1）丢进本函数：ZERO 则 keep last，非零则当帧朝向。本 Day 不写触屏、不建 touch_input_driver.gd。
static func map_aim_stick(raw: Vector2) -> Vector2:
	if raw.length() < AIM_STICK_DEADZONE:
		return Vector2.ZERO
	return raw.normalized()

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
	if _read_stick(id, JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y).length() >= AIM_STICK_DEADZONE:
		return true
	if _joy_wants_fire(id):
		return true
	return _joy_has_bound_button(id)

func _joy_has_bound_button(id: int) -> bool:
	for action: String in GameSettings.REBINDABLE_JOY_ACTIONS:
		if Input.is_joy_button_pressed(id, GameSettings.get_joy_button_for_action(action)):
			return true
	return false

func _joy_wants_fire(id: int) -> bool:
	## Godot 的扳机轴本身就是 0（松开）～1（扣到底），不需要再从 -1~1 重新映射。
	var trigger: float = Input.get_joy_axis(id, JOY_AXIS_TRIGGER_RIGHT)
	if trigger >= FIRE_TRIGGER:
		return true
	return Input.is_joy_button_pressed(id, JOY_BUTTON_RIGHT_SHOULDER)

func _update_from_joy() -> void:
	var id: int = _device_id
	move_vector = _read_move_stick(id)
	var aim: Vector2 = _read_aim_stick(id)
	if aim.is_zero_approx():
		_keep_last_aim()
	else:
		aim_vector = aim ## 已经是单位向量，不要再 smoothing
	var host: Node2D = get_parent() as Node2D
	if host != null:
		mouse_world_position = host.global_position + aim_vector * AIM_LEAD_PX
	_update_joy_weapon_edges(id)
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
	return map_aim_stick(raw)

func _update_joy_weapon_edges(id: int) -> void:
	var slot: int = 0
	for action: String in GameSettings.REBINDABLE_JOY_ACTIONS:
		if action == "dash":
			continue
		var pressed: bool = Input.is_joy_button_pressed(id, GameSettings.get_joy_button_for_action(action))
		var was_held: bool = _joy_weapon_held[slot] != 0
		if pressed and not was_held and _weapon_slot_just_pressed < 0:
			_weapon_slot_just_pressed = slot
			_pending_weapon_slot = slot
		_joy_weapon_held[slot] = 1 if pressed else 0
		slot += 1

func _clear_joy_weapon_held() -> void:
	for slot: int in _joy_weapon_held.size():
		_joy_weapon_held[slot] = 0

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
	## Touch source active 时绝不读键鼠/模拟鼠标 fire；由 _update_from_touch 独占。
	if _touch_enabled:
		return
	var pressed: bool = Input.is_action_pressed("fire")
	if _need_fire_release:
		if pressed:
			fire_held = false
			return
		_need_fire_release = false
	fire_held = pressed

func _get_dash_button() -> int:
	return GameSettings.get_joy_button_for_action("dash")

func _is_dash_held() -> bool:
	if _device_id >= 0:
		return Input.is_joy_button_pressed(_device_id, _get_dash_button())
	return Input.is_action_pressed("dash")

func _update_dash_pressed() -> void:
	if _touch_enabled:
		var touch_edge: bool = _touch_dash_pending
		_touch_dash_pending = false
		if _dash_suppressed:
			dash_just_pressed = false
			return
		dash_just_pressed = touch_edge
		if touch_edge:
			_pending_dash = true
		return
	var edge: bool = false
	if _device_id >= 0:
		var pressed: bool = Input.is_joy_button_pressed(_device_id, _get_dash_button())
		edge = pressed and not _joy_dash_held
		_joy_dash_held = pressed
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

## 技能键与 Dash 同为 edge：按下当帧出一次，按住不重复；松开后才能再次触发。
## Touch Active 时走 pending 队列；否则键鼠与手柄共用 InputMap action。
## 键鼠与手柄不做设备分叉：ability_0 的 action 里同时绑了 Q 与手柄钮，
## 这样设备仲裁切换的当帧也不会丢边沿。
func _update_ability_edges() -> void:
	ability_0_just_pressed = false
	ability_1_just_pressed = false
	if _abilities_suppressed:
		## Pause / Modal：清掉这一帧的边沿与 pending，解锁瞬间不会补放。
		_clear_touch_ability_pending()
		return
	if _touch_enabled:
		for slot: int in ABILITY_SLOT_COUNT:
			var edge: bool = _touch_ability_pending[slot] != 0
			_touch_ability_pending[slot] = 0
			_set_ability_edge(slot, edge)
		return
	for slot: int in ABILITY_SLOT_COUNT:
		_set_ability_edge(slot, Input.is_action_just_pressed(ABILITY_ACTIONS[slot]))

func _set_ability_edge(slot: int, edge: bool) -> void:
	if slot == 0:
		ability_0_just_pressed = edge
	elif slot == 1:
		ability_1_just_pressed = edge
