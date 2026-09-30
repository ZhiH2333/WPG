extends Control

## Mobile Controls 测试场景：左下 MOVE、右下 AIM、右侧 FIRE/DASH/ABILITY 0/1
## 仅用于可视化验证和调试，不作为生产场景

@onready var _player_input: PlayerInput = $PlayerInput
@onready var _move_stick: VirtualStick = $MoveStick
@onready var _aim_stick: VirtualStick = $AimStick
@onready var _fire_button: TouchActionButton = $ActionButtons/FireButton
@onready var _dash_button: TouchActionButton = $ActionButtons/DashButton
@onready var _ability0_button: TouchActionButton = $ActionButtons/Ability0Button
@onready var _ability1_button: TouchActionButton = $ActionButtons/Ability1Button
@onready var _touch_input: TouchInput = $TouchInput
@onready var _debug_label: Label = $DebugLabel

func _ready() -> void:
	_setup_button_labels()
	_player_input.process_priority = -100
	_touch_input.process_priority = -100

func _setup_button_labels() -> void:
	_fire_button.button_text = "FIRE"
	_dash_button.button_text = "DASH"
	_ability0_button.button_text = "A0"
	_ability1_button.button_text = "A1"
	_ability0_button.button_size = Vector2(80, 80)
	_ability1_button.button_size = Vector2(80, 80)
	_fire_button.font_size = 24
	_dash_button.font_size = 24
	_ability0_button.font_size = 20
	_ability1_button.font_size = 20
	_fire_button._setup_button()
	_dash_button._setup_button()
	_ability0_button._setup_button()
	_ability1_button._setup_button()

func _process(delta: float) -> void:
	_update_debug()

func _update_debug() -> void:
	var move_str: String = "MOVE: (%.2f, %.2f)" % [_player_input.move_vector.x, _player_input.move_vector.y]
	var aim_str: String = "AIM: (%.2f, %.2f)" % [_player_input.aim_vector.x, _player_input.aim_vector.y]
	var fire_str: String = "FIRE: %s" % ("HELD" if _player_input.fire_held else "OFF")
	var dash_str: String = "DASH: %s" % ("JUST" if _player_input.dash_just_pressed else "OFF")
	var touch_str: String = "TOUCH: %s" % ("ACTIVE" if _touch_input.is_touch_active() else "IDLE")
	_debug_label.text = "%s\n%s\n%s\n%s\n%s" % [move_str, aim_str, fire_str, dash_str, touch_str]