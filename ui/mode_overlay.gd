extends Control
class_name ModeOverlay

## 主菜单模式叠层：Solo / Infinite 进同一沙盒，Multi 灰掉。卡片 osu 式错峰进场，逻辑开关仍瞬时。
signal selected_solo
signal selected_infinite

var _open: bool = false
var _anim_tween: Tween

@onready var _dimmer: ColorRect = $Dimmer
@onready var _solo_button: Button = $Center/Cards/Solo
@onready var _infinite_button: Button = $Center/Cards/Infinite
@onready var _multi_button: Button = $Center/Cards/Multi
@onready var _back_button: Button = $Back

func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_multi_button.disabled = true
	_multi_button.focus_mode = Control.FOCUS_NONE
	_solo_button.focus_neighbor_left = _infinite_button.get_path()
	_solo_button.focus_neighbor_right = _infinite_button.get_path()
	_solo_button.focus_neighbor_top = _solo_button.get_path()
	_solo_button.focus_neighbor_bottom = _back_button.get_path()
	_infinite_button.focus_neighbor_left = _solo_button.get_path()
	_infinite_button.focus_neighbor_right = _solo_button.get_path()
	_infinite_button.focus_neighbor_top = _infinite_button.get_path()
	_infinite_button.focus_neighbor_bottom = _back_button.get_path()
	_back_button.focus_neighbor_top = _solo_button.get_path()
	_back_button.focus_neighbor_left = _back_button.get_path()
	_back_button.focus_neighbor_right = _back_button.get_path()
	_back_button.focus_neighbor_bottom = _back_button.get_path()
	_solo_button.focus_next = _infinite_button.get_path()
	_solo_button.focus_previous = _back_button.get_path()
	_infinite_button.focus_next = _back_button.get_path()
	_infinite_button.focus_previous = _solo_button.get_path()
	_back_button.focus_next = _solo_button.get_path()
	_back_button.focus_previous = _infinite_button.get_path()
	_solo_button.pressed.connect(_on_solo_pressed)
	_infinite_button.pressed.connect(_on_infinite_pressed)
	_back_button.pressed.connect(close)

func is_open() -> bool:
	return _open

func open() -> void:
	_open = true
	visible = true
	modulate.a = 1.0
	mouse_filter = Control.MOUSE_FILTER_STOP
	UiAnim.kill_tween(_anim_tween)
	_anim_tween = UiAnim.enter_overlay(self, _dimmer, null, [_solo_button, _infinite_button, _multi_button, _back_button])
	_solo_button.grab_focus()

func close() -> void:
	if not _open:
		return
	_open = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiAnim.kill_tween(_anim_tween)
	_anim_tween = UiAnim.exit_overlay(self, self)
	_anim_tween.finished.connect(_finish_close)
	var play: Button = get_parent().get_node_or_null("Center/Column/Play") as Button
	if play != null:
		play.grab_focus()

func _finish_close() -> void:
	visible = false
	modulate.a = 1.0

func _unhandled_input(event: InputEvent) -> void:
	if not _open:
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()
		return
	if event is InputEventJoypadButton:
		var joy: InputEventJoypadButton = event as InputEventJoypadButton
		if joy.pressed and joy.button_index == JOY_BUTTON_START:
			get_viewport().set_input_as_handled()
			close()

func _input(event: InputEvent) -> void:
	if not _open:
		return
	if event.is_action_pressed("weapon_pistol"):
		get_viewport().set_input_as_handled()
		_emit_solo()
		return
	if event.is_action_pressed("weapon_shotgun"):
		get_viewport().set_input_as_handled()
		_emit_infinite()
		return
	if event.is_action_pressed("weapon_rifle"):
		get_viewport().set_input_as_handled()

func _on_solo_pressed() -> void:
	_emit_solo()

func _on_infinite_pressed() -> void:
	_emit_infinite()

func _emit_solo() -> void:
	if not _open:
		return
	selected_solo.emit()

func _emit_infinite() -> void:
	if not _open:
		return
	selected_infinite.emit()
