extends Node
class_name TouchInput

## 适配层：VirtualStick（Move）/ TouchAimPad（Aim）/ TouchActionButton -> PlayerInput 正式 Touch API。
## Touch Active 时，PlayerInput.update_input() 会独占 move/aim/fire/dash/weapon。
## 本层只把组件信号汇聚进 PlayerInput 的 _touch_* state，不写公开输出字段。
## Aim 是 direction-only：TouchAimPad 已输出单位方向，本层不再 map_aim_stick / magnitude。
## 不创建 TouchPlayerInput，不直接碰 WeaponHost / PauseOverlay / NetSession。

@export var move_stick_path: NodePath = NodePath("../SafeAreaRoot/MoveStick")
@export var aim_stick_path: NodePath = NodePath("../SafeAreaRoot/AimPad")
@export var fire_button_path: NodePath = NodePath()
@export var dash_button_path: NodePath = NodePath("../SafeAreaRoot/WeaponCluster/DashButton")
@export var ability_0_button_path: NodePath = NodePath("../SafeAreaRoot/WeaponCluster/Ability0Button")
@export var ability_1_button_path: NodePath = NodePath("../SafeAreaRoot/WeaponCluster/Ability1Button")

var _player_input: PlayerInput
var _move_stick: VirtualStick
var _aim_pad: TouchAimPad
var _fire_button: TouchActionButton
var _dash_button: TouchActionButton
var _ability_buttons: Array[TouchActionButton] = []
var _weapon_buttons: Array[TouchActionButton] = []
var _manual_fire_mode: bool = false
var _active: bool = false

func _ready() -> void:
	var parent_pi: PlayerInput = get_parent() as PlayerInput
	if parent_pi != null:
		_player_input = parent_pi

	_move_stick = get_node_or_null(move_stick_path) as VirtualStick
	_aim_pad = get_node_or_null(aim_stick_path) as TouchAimPad
	_fire_button = get_node_or_null(fire_button_path) as TouchActionButton
	_dash_button = get_node_or_null(dash_button_path) as TouchActionButton
	_ability_buttons = [
		get_node_or_null(ability_0_button_path) as TouchActionButton,
		get_node_or_null(ability_1_button_path) as TouchActionButton,
	]

	_connect_components()
	_connect_ability_buttons()

## Touch 是否处于 gameplay 激活态（任一控件被按下）。
func is_touch_active() -> bool:
	return (_move_stick != null and _move_stick.is_active()) or \
		(_aim_pad != null and _aim_pad.is_active()) or \
		(_fire_button != null and _fire_button.is_held()) or \
		(_dash_button != null and _dash_button.is_held()) or \
		_ability_any_held() or \
		_weapon_any_held()

func get_player_input() -> PlayerInput:
	return _player_input

func _weapon_any_held() -> bool:
	for btn: TouchActionButton in _weapon_buttons:
		if btn != null and btn.is_held():
			return true
	return false

func _ability_any_held() -> bool:
	for btn: TouchActionButton in _ability_buttons:
		if btn != null and btn.is_held():
			return true
	return false

func _connect_components() -> void:
	if _move_stick != null:
		if not _move_stick.stick_moved.is_connected(_on_move_stick_moved):
			_move_stick.stick_moved.connect(_on_move_stick_moved)
		if not _move_stick.stick_released.is_connected(_on_move_stick_released):
			_move_stick.stick_released.connect(_on_move_stick_released)
	if _aim_pad != null:
		if not _aim_pad.stick_moved.is_connected(_on_aim_pad_moved):
			_aim_pad.stick_moved.connect(_on_aim_pad_moved)
		if not _aim_pad.stick_released.is_connected(_on_aim_pad_released):
			_aim_pad.stick_released.connect(_on_aim_pad_released)
	if _fire_button != null:
		if not _fire_button.pressed.is_connected(_on_fire_pressed):
			_fire_button.pressed.connect(_on_fire_pressed)
		if not _fire_button.released.is_connected(_on_fire_released):
			_fire_button.released.connect(_on_fire_released)
	if _dash_button != null:
		if not _dash_button.just_pressed.is_connected(_on_dash_just_pressed):
			_dash_button.just_pressed.connect(_on_dash_just_pressed)

## 正式运行时绑定 API：把一个 PlayerInput 作为唯一输出源。
func bind_player_input(player_input: PlayerInput) -> void:
	_player_input = player_input
	_player_input.set_touch_manual_fire_mode(_manual_fire_mode)
	if _active:
		_player_input.set_touch_active(true)

func set_active(active: bool) -> void:
	_active = active
	if _player_input == null:
		return
	_player_input.set_touch_active(active)
	if not active:
		reset()

func bind_move_stick(stick: VirtualStick) -> void:
	_move_stick = stick
	_connect_components()

func bind_aim_pad(pad: TouchAimPad) -> void:
	_aim_pad = pad
	_connect_components()

func bind_fire_button(btn: TouchActionButton) -> void:
	_fire_button = btn
	_connect_components()

func bind_dash_button(btn: TouchActionButton) -> void:
	_dash_button = btn
	_connect_components()

## Weapon slot buttons（0..3）。数组顺序即 slot 顺序。
func bind_weapon_buttons(buttons: Array[TouchActionButton]) -> void:
	_weapon_buttons = buttons
	_connect_weapon_buttons()

## 技能按钮（0..1）。数组顺序即槽位顺序。只把 tap 变成 PlayerInput 的输入边沿，
## 绝不直接调用 AbilityController。
func bind_ability_buttons(buttons: Array[TouchActionButton]) -> void:
	_ability_buttons = buttons
	_connect_ability_buttons()

func _connect_ability_buttons() -> void:
	for i: int in _ability_buttons.size():
		var btn: TouchActionButton = _ability_buttons[i]
		if btn == null:
			continue
		if btn.just_pressed.is_connected(_on_ability_just_pressed):
			continue
		btn.just_pressed.connect(_on_ability_just_pressed.bind(i))

func _connect_weapon_buttons() -> void:
	for i: int in _weapon_buttons.size():
		var btn: TouchActionButton = _weapon_buttons[i]
		if btn == null:
			continue
		if btn.just_pressed.is_connected(_on_weapon_just_pressed):
			continue
		btn.just_pressed.connect(_on_weapon_just_pressed.bind(i))

func set_manual_fire_mode(enabled: bool) -> void:
	## 从 ON 切回 OFF：FIRE 按钮会被隐藏，released 事件不会再来，
	## 这里先复位按钮，再由 PlayerInput 清掉 touch fire held。
	if not enabled and _manual_fire_mode and _fire_button != null:
		_fire_button.reset()
	_manual_fire_mode = enabled
	if _player_input != null:
		_player_input.set_touch_manual_fire_mode(enabled)

func is_manual_fire_mode() -> bool:
	return _manual_fire_mode

func _on_move_stick_moved(direction: Vector2) -> void:
	if _player_input == null:
		return
	_player_input.set_touch_move_vector(direction)

func _on_move_stick_released() -> void:
	if _player_input == null:
		return
	_player_input.set_touch_move_vector(Vector2.ZERO)

## TouchAimPad 已输出单位方向（direction-only）。ZERO = 松手/死区，active=false。
func _on_aim_pad_moved(direction: Vector2) -> void:
	if _player_input == null:
		return
	if direction.is_zero_approx():
		_player_input.set_touch_aim_vector(Vector2.ZERO, false)
		return
	## AimPad active = aim + fire（Manual Fire OFF）。
	_player_input.set_touch_aim_vector(direction, true)

func _on_aim_pad_released() -> void:
	if _player_input == null:
		return
	## 松开：aim 归 ZERO（准星回中心），fire 关闭。
	_player_input.set_touch_aim_vector(Vector2.ZERO, false)

func _on_fire_pressed() -> void:
	if _player_input != null:
		_player_input.set_touch_fire_held(true)

func _on_fire_released() -> void:
	if _player_input != null:
		_player_input.set_touch_fire_held(false)

func _on_dash_just_pressed() -> void:
	if _player_input != null:
		_player_input.queue_touch_dash()

func _on_weapon_just_pressed(slot: int) -> void:
	if _player_input != null:
		_player_input.queue_touch_weapon_slot(slot)

## A0 / A1 -> PlayerInput 技能边沿。Touch 层到此为止，不认识 AbilityController。
func _on_ability_just_pressed(slot: int) -> void:
	if _player_input != null:
		_player_input.queue_touch_ability(slot)

func reset() -> void:
	if _move_stick != null:
		_move_stick.reset()
	if _aim_pad != null:
		_aim_pad.reset()
	if _fire_button != null:
		_fire_button.reset()
	if _dash_button != null:
		_dash_button.reset()
	for btn: TouchActionButton in _weapon_buttons:
		if btn != null:
			btn.reset()
	for btn: TouchActionButton in _ability_buttons:
		if btn != null:
			btn.reset()
	if _player_input != null:
		_player_input.clear_touch_state()
