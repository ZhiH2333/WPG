extends Control
class_name MainMenu

## 极简主菜单。Play 进现有 CombatSandbox；Quit 退出。禁止暂停树、禁止 Autoload。
const SANDBOX_SCENE := "res://sandbox/combat_sandbox.tscn"

@onready var _play_button: Button = $Center/Column/Play
@onready var _quit_button: Button = $Center/Column/Quit

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_play_button.pressed.connect(_on_play_pressed)
	_quit_button.pressed.connect(_on_quit_pressed)
	_play_button.grab_focus()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept"):
		get_viewport().set_input_as_handled()
		_on_play_pressed()

func _on_play_pressed() -> void:
	get_tree().change_scene_to_file(SANDBOX_SCENE)

func _on_quit_pressed() -> void:
	get_tree().quit()
