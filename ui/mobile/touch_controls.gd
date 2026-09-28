extends CanvasLayer
class_name TouchControls

## Touch Controls 容器：管理虚拟摇杆和动作按钮的显示/隐藏
## 根据 GameSettings.is_touch_controls_enabled() 决定是否显示
## 不包含战斗逻辑，只负责组合 VirtualStick / TouchActionButton / TouchInput

signal touch_visibility_changed(visible: bool)

@onready var _move_stick: VirtualStick = $Root/MoveStick
@onready var _aim_stick: VirtualStick = $Root/AimStick
@onready var _fire_button: TouchActionButton = $Root/ActionButtons/FireButton
@onready var _dash_button: TouchActionButton = $Root/ActionButtons/DashButton
@onready var _ability0_button: TouchActionButton = $Root/ActionButtons/Ability0Button
@onready var _ability1_button: TouchActionButton = $Root/ActionButtons/Ability1Button
@onready var _touch_input: TouchInput = $Root/TouchInput
@onready var _root: Control = $Root

func _ready() -> void:
	_setup_buttons_if_enabled()
	_update_visibility()
	GameSettings.load_from_disk()
	set_process(true)

func _process(delta: float) -> void:
	_update_visibility()

func _update_visibility() -> void:
	var should_show: bool = GameSettings.is_touch_controls_enabled()
	if _root.visible != should_show:
		_root.visible = should_show
		touch_visibility_changed.emit(should_show)

func set_touch_visible(visible: bool) -> void:
	_root.visible = visible

func is_touch_visible() -> bool:
	return _root.visible

func _setup_buttons_if_enabled() -> void:
	if not GameSettings.is_touch_controls_enabled():
		return
	if _fire_button == null or _dash_button == null or _ability0_button == null or _ability1_button == null:
		print("WARNING: TouchActionButton references are null, buttons not setup")
		return
	_fire_button.button_text = "FIRE"
	_dash_button.button_text = "DASH"
	_ability0_button.button_text = "A0"
	_ability1_button.button_text = "A1"
	_fire_button.button_color = Color(1, 0.4, 0.67, 1)
	_dash_button.button_color = Color(0.4, 0.72, 1, 1)
	_ability0_button.button_color = Color(0.95, 0.62, 0.35, 1)
	_ability1_button.button_color = Color(0.95, 0.62, 0.35, 1)
	_ability0_button.use_small_variant = true
	_ability1_button.use_small_variant = true
	_fire_button._setup_button()
	_dash_button._setup_button()
	_ability0_button._setup_button()
	_ability1_button._setup_button()

func bind_player_input(player_input: PlayerInput) -> void:
	if _touch_input != null:
		_touch_input.bind_player_input(player_input)
		_touch_input.bind_move_stick(_move_stick)
		_touch_input.bind_aim_stick(_aim_stick)
		_touch_input.bind_fire_button(_fire_button)
		_touch_input.bind_dash_button(_dash_button)

func get_touch_input() -> TouchInput:
	return _touch_input

func get_move_stick() -> VirtualStick:
	return _move_stick

func get_aim_stick() -> VirtualStick:
	return _aim_stick

func get_fire_button() -> TouchActionButton:
	return _fire_button

func get_dash_button() -> TouchActionButton:
	return _dash_button

func get_ability0_button() -> TouchActionButton:
	return _ability0_button

func get_ability1_button() -> TouchActionButton:
	return _ability1_button

func refresh_visibility() -> void:
	_update_visibility()