extends Control
class_name VirtualStick

## 通用虚拟摇杆组件：base/knob + 触摸拖动 + 归一化输出 + deadzone + clamp
## 左摇杆用于移动，右摇杆用于瞄准。无业务逻辑，只产出 Vector2
## 使用 FlatBold theme tokens，不创建 StyleBoxFlat.new()

signal stick_moved(direction: Vector2)
signal stick_released

@export var deadzone: float = 0.15
@export var max_radius: float = 80.0
@export var base_size: float = 160.0
@export var knob_size: float = 80.0

var _active: bool = false
var _touch_id: int = -1
var _base_pos: Vector2 = Vector2.ZERO
var _current_vector: Vector2 = Vector2.ZERO

@onready var _base: Panel = $Base
@onready var _knob: Panel = $Knob
var _has_visuals: bool = false

func _ready() -> void:
	_has_visuals = is_instance_valid(_base) and is_instance_valid(_knob)
	if _has_visuals:
		_setup_visuals()
	reset()

func _setup_visuals() -> void:
	_base.custom_minimum_size = Vector2(base_size, base_size)
	_knob.custom_minimum_size = Vector2(knob_size, knob_size)
	_base.size = Vector2(base_size, base_size)
	_knob.size = Vector2(knob_size, knob_size)
	
	_base.theme_type_variation = "TouchStickBase"
	_knob.theme_type_variation = "TouchStickKnob"
	
	_knob.anchor_left = 0.5
	_knob.anchor_top = 0.5
	_knob.anchor_right = 0.5
	_knob.anchor_bottom = 0.5
	_knob.offset_left = -knob_size * 0.5
	_knob.offset_top = -knob_size * 0.5
	_knob.offset_right = knob_size * 0.5
	_knob.offset_bottom = knob_size * 0.5

func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_handle_touch(event)
	elif event is InputEventScreenDrag:
		_handle_drag(event)
	elif event is InputEventMouseButton:
		_handle_mouse_button(event)
	elif event is InputEventMouseMotion:
		_handle_mouse_motion(event)

func _handle_touch(event: InputEventScreenTouch) -> void:
	if event.pressed:
		if not _active:
			_activate(event.position, event.index)
	else:
		if _active and event.index == _touch_id:
			_release()

func _handle_drag(event: InputEventScreenDrag) -> void:
	if _active and event.index == _touch_id:
		_update_stick(event.position)

func _handle_mouse_button(event: InputEventMouseButton) -> void:
	if event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if not _active:
				_activate(event.position, -1)
		else:
			if _active and _touch_id == -1:
				_release()

func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	if _active and _touch_id == -1:
		_update_stick(event.position)

func _activate(pos: Vector2, touch_id: int) -> void:
	_active = true
	_touch_id = touch_id
	_base_pos = pos
	if _has_visuals:
		_base.global_position = pos
		_knob.global_position = pos
		visible = true

func _update_stick(touch_pos: Vector2) -> void:
	var offset: Vector2 = touch_pos - _base_pos
	var distance: float = offset.length()
	var clamped_distance: float = min(distance, max_radius)
	
	if clamped_distance > 0.0:
		var direction: Vector2 = offset.normalized()
		var knob_pos: Vector2 = _base_pos + direction * clamped_distance
		if _has_visuals:
			_knob.global_position = knob_pos
		_current_vector = direction * (clamped_distance / max_radius)
	else:
		if _has_visuals:
			_knob.global_position = _base_pos
		_current_vector = Vector2.ZERO
	
	if _current_vector.length() < deadzone:
		_current_vector = Vector2.ZERO
	
	stick_moved.emit(_current_vector)

func _release() -> void:
	_active = false
	_touch_id = -1
	_current_vector = Vector2.ZERO
	if _has_visuals:
		_knob.global_position = _base_pos
		visible = false
	stick_moved.emit(Vector2.ZERO)
	stick_released.emit()

func reset() -> void:
	_active = false
	_touch_id = -1
	_current_vector = Vector2.ZERO
	if _has_visuals:
		visible = false
		if is_instance_valid(_base):
			_base.global_position = Vector2.ZERO
		if is_instance_valid(_knob):
			_knob.global_position = Vector2.ZERO

func get_vector() -> Vector2:
	return _current_vector

func is_active() -> bool:
	return _active