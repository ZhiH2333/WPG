extends Control
class_name ModeChoiceOverlay

## Play 路由器：每次问 SOLO / MULTI。不是内容页，不套大面板，不记上次选择。
signal solo_pressed
signal multi_pressed

var _open: bool = false
var _anim_tween: Tween

@onready var _dimmer: ColorRect = $Dimmer
@onready var _cards: HBoxContainer = $Center/Cards
@onready var _solo_button: Button = $Center/Cards/Solo
@onready var _multi_button: Button = $Center/Cards/Multi
@onready var _back_button: Button = $Back

func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_solo_button.pressed.connect(func() -> void: solo_pressed.emit())
	_multi_button.pressed.connect(func() -> void: multi_pressed.emit())
	_back_button.pressed.connect(close)

func is_open() -> bool:
	return _open

func open() -> void:
	_open = true
	visible = true
	modulate.a = 1.0
	mouse_filter = Control.MOUSE_FILTER_STOP
	UiAnim.kill_tween(_anim_tween)
	_anim_tween = UiAnim.enter_overlay(self, _dimmer, _cards, [_solo_button, _multi_button, _back_button])
	_solo_button.grab_focus()

func close() -> void:
	if not _open:
		return
	_open = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiAnim.kill_tween(_anim_tween)
	_anim_tween = UiAnim.exit_overlay(self, self)
	_anim_tween.finished.connect(_finish_close)
	_refocus_menu()

func _refocus_menu() -> void:
	var play: Button = get_parent().get_node_or_null("Center/Column/Buttons/Play") as Button
	if play != null:
		play.grab_focus()

func _finish_close() -> void:
	if _open:
		return
	visible = false
	modulate.a = 1.0

func _unhandled_input(event: InputEvent) -> void:
	if not _open:
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()
