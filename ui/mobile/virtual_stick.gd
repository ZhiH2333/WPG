extends Control
class_name VirtualStick

## 常驻虚拟摇杆组件：base/knob 屏幕空间固定，不随 world/camera 移动。
## 触摸只在摇杆区域内激活，knob 跟随手指，松开回中；base/knob 始终可见。
## 无业务逻辑，只产出 Vector2。使用 FlatBold theme tokens，不创建 StyleBoxFlat.new()

signal stick_moved(direction: Vector2)
signal stick_released

@export var deadzone: float = 0.15
@export var max_radius: float = 80.0
@export var base_size: float = 160.0
@export var knob_size: float = 80.0

var _active: bool = false
var _touch_id: int = -1
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
	_base.theme_type_variation = "TouchStickBase"
	_knob.theme_type_variation = "TouchStickKnob"
	_centre_knob()
	_apply_rest_visual()

## 摇杆常驻正方形，尺寸由自身 size 决定（布局 / SafeArea 负责定位）。
func _get_stick_center() -> Vector2:
	return size * 0.5

func _ensure_sizes() -> void:
	if not _has_visuals:
		return
	var side: float = maxf(base_size, minf(size.x, size.y))
	if side <= 0.0:
		side = base_size
	_base.custom_minimum_size = Vector2(side, side)
	_knob.custom_minimum_size = Vector2(knob_size, knob_size)
	_base.size = Vector2(side, side)
	_knob.size = Vector2(knob_size, knob_size)

func _centre_knob() -> void:
	if not _has_visuals:
		return
	_knob.position = _get_stick_center() - Vector2(knob_size, knob_size) * 0.5

func _apply_rest_visual() -> void:
	if not _has_visuals:
		return
	_base.visible = true
	_knob.visible = true

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		if _has_visuals:
			_ensure_sizes()
			if not _active:
				_centre_knob()

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
			_activate(event.index)
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
				_activate(-1)
		else:
			if _active and _touch_id == -1:
				_release()

func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	if _active and _touch_id == -1:
		_update_stick(event.position)

func _activate(touch_id: int) -> void:
	_active = true
	_touch_id = touch_id
	if _has_visuals:
		_knob.visible = true
	_update_stick(_get_stick_center())

func _update_stick(local_pos: Vector2) -> void:
	var center: Vector2 = _get_stick_center()
	var offset: Vector2 = local_pos - center
	var distance: float = offset.length()
	var clamped_distance: float = minf(distance, max_radius)

	if clamped_distance > 0.0:
		var direction: Vector2 = offset.normalized()
		if _has_visuals:
			_knob.position = center + direction * clamped_distance - Vector2(knob_size, knob_size) * 0.5
		_current_vector = direction * (clamped_distance / max_radius)
	else:
		if _has_visuals:
			_knob.position = center - Vector2(knob_size, knob_size) * 0.5
		_current_vector = Vector2.ZERO

	if _current_vector.length() < deadzone:
		_current_vector = Vector2.ZERO

	stick_moved.emit(_current_vector)

func _release() -> void:
	_active = false
	_touch_id = -1
	_current_vector = Vector2.ZERO
	if _has_visuals:
		_centre_knob()
	stick_moved.emit(Vector2.ZERO)
	stick_released.emit()

func reset() -> void:
	_active = false
	_touch_id = -1
	_current_vector = Vector2.ZERO
	if _has_visuals:
		_ensure_sizes()
		_centre_knob()
		_apply_rest_visual()

func get_vector() -> Vector2:
	return _current_vector

func is_active() -> bool:
	return _active
