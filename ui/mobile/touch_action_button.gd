extends Control
class_name TouchActionButton

## 轻量触屏按钮组件：pressed / released / held / just_pressed
## 不包含任何战斗逻辑，只产出边沿与状态

signal pressed
signal released
signal just_pressed

@export var button_text: String = "ACTION"
@export var button_color: Color = Color(1, 0.4, 0.67, 1)
@export var button_size: Vector2 = Vector2(100, 100)
@export var font_size: int = 28

var _held: bool = false
var _just_pressed: bool = false
var _touch_id: int = -1
var _mouse_over: bool = false

@onready var _button: Button = $Button
@onready var _label: Label = $Button/Label
var _has_visuals: bool = false

func _ready() -> void:
	_has_visuals = is_instance_valid(_button) and is_instance_valid(_label)
	if _has_visuals:
		_setup_button()

func _setup_button() -> void:
	_button.custom_minimum_size = button_size
	_button.size = button_size
	_button.theme_type_variation = ""
	
	var style_normal: StyleBoxFlat = StyleBoxFlat.new()
	style_normal.bg_color = button_color
	style_normal.corner_radius_top_left = 50
	style_normal.corner_radius_top_right = 50
	style_normal.corner_radius_bottom_right = 50
	style_normal.corner_radius_bottom_left = 50
	style_normal.content_margin_left = 0
	style_normal.content_margin_top = 0
	style_normal.content_margin_right = 0
	style_normal.content_margin_bottom = 0
	
	var style_hover: StyleBoxFlat = style_normal.duplicate() as StyleBoxFlat
	style_hover.bg_color = button_color * Color(1.15, 1.15, 1.15, 1)
	
	var style_pressed: StyleBoxFlat = style_normal.duplicate() as StyleBoxFlat
	style_pressed.bg_color = button_color * Color(0.85, 0.85, 0.85, 1)
	
	var style_focus: StyleBoxFlat = StyleBoxFlat.new()
	style_focus.border_width_left = 3
	style_focus.border_width_top = 3
	style_focus.border_width_right = 3
	style_focus.border_width_bottom = 3
	style_focus.border_color = Color(0.96, 0.93, 0.88, 0.9)
	style_focus.corner_radius_top_left = 50
	style_focus.corner_radius_top_right = 50
	style_focus.corner_radius_bottom_right = 50
	style_focus.corner_radius_bottom_left = 50
	
	_button.add_theme_stylebox_override("normal", style_normal)
	_button.add_theme_stylebox_override("hover", style_hover)
	_button.add_theme_stylebox_override("pressed", style_pressed)
	_button.add_theme_stylebox_override("focus", style_focus)
	_button.add_theme_stylebox_override("disabled", style_normal.duplicate())
	
	_label.text = button_text
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", font_size)
	_label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_label.add_theme_constant_override("outline_size", 4)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_handle_touch(event)
	elif event is InputEventMouseButton:
		_handle_mouse_button(event)
	elif event is InputEventMouseMotion:
		_handle_mouse_motion(event)

func _handle_touch(event: InputEventScreenTouch) -> void:
	if event.pressed:
		if not _held and _is_point_in_button(event.position):
			_held = true
			_touch_id = event.index
			_just_pressed = true
			pressed.emit()
	else:
		if _held and event.index == _touch_id:
			_release()

func _handle_mouse_button(event: InputEventMouseButton) -> void:
	if event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if not _held and _is_point_in_button(event.position):
				_held = true
				_touch_id = -1
				_just_pressed = true
				pressed.emit()
		else:
			if _held and _touch_id == -1:
				_release()

func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	var inside: bool = _is_point_in_button(event.position)
	if _mouse_over != inside:
		_mouse_over = inside

func _is_point_in_button(point: Vector2) -> bool:
	return Rect2(Vector2.ZERO, button_size).has_point(point)

func _release() -> void:
	_held = false
	_touch_id = -1
	released.emit()

func _process(delta: float) -> void:
	if _just_pressed:
		just_pressed.emit()
		_just_pressed = false

func is_held() -> bool:
	return _held

func is_just_pressed() -> bool:
	return _just_pressed

## 测试辅助：直接触发 just_pressed 逻辑（用于 headless 测试）
func _trigger_just_pressed_for_test() -> void:
	if _just_pressed:
		just_pressed.emit()
		_just_pressed = false

func reset() -> void:
	_held = false
	_just_pressed = false
	_touch_id = -1
	_mouse_over = false