extends Control
class_name MainMenu

## 极简主菜单。Play 进现有 CombatSandbox；Settings 开叠层；Quit 退出。禁止暂停树、禁止 Autoload。
const SANDBOX_SCENE := "res://sandbox/combat_sandbox.tscn"

@onready var _play_button: Button = $Center/Column/Play
@onready var _settings_button: Button = $Center/Column/Settings
@onready var _quit_button: Button = $Center/Column/Quit
@onready var _overlay: SettingsOverlay = $SettingsOverlay

func _ready() -> void:
	GameSettings.load_from_disk()
	GameSettings.apply()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_play_button.pressed.connect(_on_play_pressed)
	_settings_button.pressed.connect(_on_settings_pressed)
	_quit_button.pressed.connect(_on_quit_pressed)
	_play_button.grab_focus()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if _overlay.is_open():
			get_viewport().set_input_as_handled()
			_overlay.close()
			_play_button.grab_focus()
		return
	if event.is_action_pressed("ui_accept"):
		if _overlay.is_open():
			return
		get_viewport().set_input_as_handled()
		_on_play_pressed()

func _on_play_pressed() -> void:
	get_tree().change_scene_to_file(SANDBOX_SCENE)

func _on_settings_pressed() -> void:
	_overlay.open()

func _on_quit_pressed() -> void:
	get_tree().quit()
