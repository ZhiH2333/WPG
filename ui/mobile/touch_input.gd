extends Node
class_name TouchInput

## 轻量适配层：VirtualStick / TouchActionButton -> PlayerInput
## 职责只有把触控输入汇聚到现有 PlayerInput 数据模型
## 不创建 TouchPlayerInput，不复制战斗输入，不发第二套 dash 信号

@export var move_stick_path: NodePath = NodePath("../MoveStick")
@export var aim_stick_path: NodePath = NodePath("../AimStick")
@export var fire_button_path: NodePath = NodePath("../FireButton")
@export var dash_button_path: NodePath = NodePath("../DashButton")
@export var ability0_button_path: NodePath = NodePath("../Ability0Button")
@export var ability1_button_path: NodePath = NodePath("../Ability1Button")

var _player_input: PlayerInput
var _move_stick: VirtualStick
var _aim_stick: VirtualStick
var _fire_button: TouchActionButton
var _dash_button: TouchActionButton
var _ability0_button: TouchActionButton
var _ability1_button: TouchActionButton
var _dash_pending: bool = false

func _ready() -> void:
	var parent_pi: PlayerInput = get_parent() as PlayerInput
	if parent_pi != null:
		_player_input = parent_pi
	
	_move_stick = get_node_or_null(move_stick_path) as VirtualStick
	_aim_stick = get_node_or_null(aim_stick_path) as VirtualStick
	_fire_button = get_node_or_null(fire_button_path) as TouchActionButton
	_dash_button = get_node_or_null(dash_button_path) as TouchActionButton
	_ability0_button = get_node_or_null(ability0_button_path) as TouchActionButton
	_ability1_button = get_node_or_null(ability1_button_path) as TouchActionButton
	
	if _move_stick != null:
		_move_stick.stick_moved.connect(_on_move_stick_moved)
		_move_stick.stick_released.connect(_on_move_stick_released)
	
	if _aim_stick != null:
		_aim_stick.stick_moved.connect(_on_aim_stick_moved)
		_aim_stick.stick_released.connect(_on_aim_stick_released)
	
	if _fire_button != null:
		_fire_button.pressed.connect(_on_fire_pressed)
		_fire_button.released.connect(_on_fire_released)
	
	if _dash_button != null:
		_dash_button.just_pressed.connect(_on_dash_just_pressed)

func _process(delta: float) -> void:
	if _player_input == null:
		return
	
	if _dash_pending:
		_player_input.dash_just_pressed = true
		_dash_pending = false
	else:
		_player_input.dash_just_pressed = false

func _on_move_stick_moved(direction: Vector2) -> void:
	if _player_input != null:
		_player_input.move_vector = direction

func _on_move_stick_released() -> void:
	if _player_input != null:
		_player_input.move_vector = Vector2.ZERO

func _on_aim_stick_moved(direction: Vector2) -> void:
	if _player_input != null:
		var mapped: Vector2 = PlayerInput.map_aim_stick(direction)
		if not mapped.is_zero_approx():
			_player_input.aim_vector = mapped

func _on_aim_stick_released() -> void:
	if _player_input != null:
		_player_input.move_vector = _player_input.move_vector

func _on_fire_pressed() -> void:
	if _player_input != null:
		_player_input.fire_held = true

func _on_fire_released() -> void:
	if _player_input != null:
		_player_input.fire_held = false

func _on_dash_just_pressed() -> void:
	_dash_pending = true

func is_touch_active() -> bool:
	return (_move_stick != null and _move_stick.is_active()) or \
	       (_aim_stick != null and _aim_stick.is_active()) or \
	       (_fire_button != null and _fire_button.is_held()) or \
	       (_dash_button != null and _dash_button.is_held())

func reset() -> void:
	if _move_stick != null:
		_move_stick.reset()
	if _aim_stick != null:
		_aim_stick.reset()
	if _fire_button != null:
		_fire_button.reset()
	if _dash_button != null:
		_dash_button.reset()
	if _ability0_button != null:
		_ability0_button.reset()
	if _ability1_button != null:
		_ability1_button.reset()
	_dash_pending = false

## 测试注入方法
func _set_player_input_for_test(pi: PlayerInput) -> void:
	_player_input = pi

func _set_move_stick_for_test(stick: VirtualStick) -> void:
	if _move_stick != null:
		_move_stick.stick_moved.disconnect(_on_move_stick_moved)
		_move_stick.stick_released.disconnect(_on_move_stick_released)
	_move_stick = stick
	if _move_stick != null:
		_move_stick.stick_moved.connect(_on_move_stick_moved)
		_move_stick.stick_released.connect(_on_move_stick_released)

func _set_aim_stick_for_test(stick: VirtualStick) -> void:
	if _aim_stick != null:
		_aim_stick.stick_moved.disconnect(_on_aim_stick_moved)
		_aim_stick.stick_released.disconnect(_on_aim_stick_released)
	_aim_stick = stick
	if _aim_stick != null:
		_aim_stick.stick_moved.connect(_on_aim_stick_moved)
		_aim_stick.stick_released.connect(_on_aim_stick_released)

func _set_fire_button_for_test(btn: TouchActionButton) -> void:
	if _fire_button != null:
		_fire_button.pressed.disconnect(_on_fire_pressed)
		_fire_button.released.disconnect(_on_fire_released)
	_fire_button = btn
	if _fire_button != null:
		_fire_button.pressed.connect(_on_fire_pressed)
		_fire_button.released.connect(_on_fire_released)

func _set_dash_button_for_test(btn: TouchActionButton) -> void:
	if _dash_button != null:
		_dash_button.just_pressed.disconnect(_on_dash_just_pressed)
	_dash_button = btn
	if _dash_button != null:
		_dash_button.just_pressed.connect(_on_dash_just_pressed)