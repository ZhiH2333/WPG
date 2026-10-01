extends Node
class_name TouchInput

## 适配层：VirtualStick / TouchActionButton -> PlayerInput 正式 Touch API。
## Touch Active 时，PlayerInput.update_input() 会独占 move/aim/fire/dash/weapon。
## 本层只把组件信号汇聚进 PlayerInput 的 _touch_* state，不写公开输出字段。
## 不创建 TouchPlayerInput，不直接碰 WeaponHost / PauseOverlay / NetSession。

@export var move_stick_path: NodePath = NodePath("../SafeAreaRoot/MoveStick")
@export var aim_stick_path: NodePath = NodePath("../SafeAreaRoot/AimStick")
@export var fire_button_path: NodePath = NodePath()
@export var dash_button_path: NodePath = NodePath("../SafeAreaRoot/WeaponCluster/DashButton")

var _player_input: PlayerInput
var _move_stick: VirtualStick
var _aim_stick: VirtualStick
var _fire_button: TouchActionButton
var _dash_button: TouchActionButton
var _weapon_buttons: Array[TouchActionButton] = []
var _manual_fire_mode: bool = false
var _active: bool = false

func _ready() -> void:
	var parent_pi: PlayerInput = get_parent() as PlayerInput
	if parent_pi != null:
		_player_input = parent_pi

	_move_stick = get_node_or_null(move_stick_path) as VirtualStick
	_aim_stick = get_node_or_null(aim_stick_path) as VirtualStick
	_fire_button = get_node_or_null(fire_button_path) as TouchActionButton
	_dash_button = get_node_or_null(dash_button_path) as TouchActionButton

	_connect_components()

## Touch 是否处于 gameplay 激活态（任一控件被按下）。
func is_touch_active() -> bool:
	return (_move_stick != null and _move_stick.is_active()) or \
		(_aim_stick != null and _aim_stick.is_active()) or \
		(_fire_button != null and _fire_button.is_held()) or \
		(_dash_button != null and _dash_button.is_held()) or \
		_weapon_any_held()

func get_player_input() -> PlayerInput:
	return _player_input

func _weapon_any_held() -> bool:
	for btn: TouchActionButton in _weapon_buttons:
		if btn != null and btn.is_held():
			return true
	return false

func _connect_components() -> void:
	if _move_stick != null:
		if not _move_stick.stick_moved.is_connected(_on_move_stick_moved):
			_move_stick.stick_moved.connect(_on_move_stick_moved)
		if not _move_stick.stick_released.is_connected(_on_move_stick_released):
			_move_stick.stick_released.connect(_on_move_stick_released)
	if _aim_stick != null:
		if not _aim_stick.stick_moved.is_connected(_on_aim_stick_moved):
			_aim_stick.stick_moved.connect(_on_aim_stick_moved)
		if not _aim_stick.stick_released.is_connected(_on_aim_stick_released):
			_aim_stick.stick_released.connect(_on_aim_stick_released)
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

func bind_aim_stick(stick: VirtualStick) -> void:
	_aim_stick = stick
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

func _connect_weapon_buttons() -> void:
	for i: int in _weapon_buttons.size():
		var btn: TouchActionButton = _weapon_buttons[i]
		if btn == null:
			continue
		if btn.just_pressed.is_connected(_on_weapon_just_pressed):
			continue
		btn.just_pressed.connect(_on_weapon_just_pressed.bind(i))

func set_manual_fire_mode(enabled: bool) -> void:
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

func _on_aim_stick_moved(direction: Vector2) -> void:
	if _player_input == null:
		return
	var mapped: Vector2 = PlayerInput.map_aim_stick(direction)
	if mapped.is_zero_approx():
		_player_input.set_touch_aim_vector(Vector2.ZERO, false)
		return
	## 右摇杆 active = aim + fire（Manual Fire OFF）。
	_player_input.set_touch_aim_vector(mapped, true)

func _on_aim_stick_released() -> void:
	if _player_input == null:
		return
	## 松开：保留最后一次 aim，fire 关闭。
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

func reset() -> void:
	if _move_stick != null:
		_move_stick.reset()
	if _aim_stick != null:
		_aim_stick.reset()
	if _fire_button != null:
		_fire_button.reset()
	if _dash_button != null:
		_dash_button.reset()
	for btn: TouchActionButton in _weapon_buttons:
		if btn != null:
			btn.reset()
	if _player_input != null:
		_player_input.clear_touch_state()
