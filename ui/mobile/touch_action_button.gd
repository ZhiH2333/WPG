extends Control
class_name TouchActionButton

## 轻量触屏按钮组件：pressed / released / held / just_pressed
## 不包含任何战斗逻辑，只产出边沿与状态
## 使用 FlatBold theme tokens，不创建 StyleBoxFlat.new()

signal pressed
signal released
signal just_pressed

@export var button_text: String = "ACTION"
@export var button_size: Vector2 = Vector2(100, 100)
@export var font_size: int = 28
@export var use_small_variant: bool = false

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
	_button.theme_type_variation = "TouchActionButtonSmall" if use_small_variant else "TouchActionButton"
	_button.focus_mode = Control.FOCUS_NONE
	
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