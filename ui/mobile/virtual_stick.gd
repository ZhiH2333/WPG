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
## 触摸命中区可比视觉半径大：手指只需落在 base + hit_padding 内即可激活。
## 固定左下 / 右下，Touch 时移动 base 是禁止的。
@export var hit_padding: float = 40.0

var _active: bool = false
var _touch_id: int = -1
var _current_vector: Vector2 = Vector2.ZERO

@onready var _base: Panel = $Base
@onready var _knob: Panel = $Knob
## 可选装饰层（刻度）：只画在 Base 之上、Knob 之下，不参与输入。
@onready var _decor: Control = get_node_or_null("Decor")
var _has_visuals: bool = false

func _ready() -> void:
	## 摇杆自身是输入 owner。
	mouse_filter = Control.MOUSE_FILTER_STOP
	_has_visuals = is_instance_valid(_base) and is_instance_valid(_knob)
	if _has_visuals:
		_setup_visuals()
	reset()

func _setup_visuals() -> void:
	_base.theme_type_variation = "TouchStickBase"
	_knob.theme_type_variation = "TouchStickKnob"
	## 视觉层只负责画面，不抢占输入。
	_base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_knob.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _decor != null:
		_decor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_centre_knob()
	_apply_rest_visual()

## 按住时 knob 换成更亮的 token（按下手感），只切 theme_type_variation。
func _apply_active_visual(active: bool) -> void:
	if not _has_visuals:
		return
	_knob.theme_type_variation = "TouchStickKnobActive" if active else "TouchStickKnob"

## 摇杆常驻正方形，尺寸由自身 size 决定（布局 / SafeArea 负责定位）。
func _get_stick_center() -> Vector2:
	return size * 0.5

func _ensure_sizes() -> void:
	if not _has_visuals:
		return
	var side: float = base_size
	if side <= 0.0:
		side = minf(size.x, size.y)
	if side <= 0.0:
		side = 160.0
	## 视觉 base 固定视觉尺寸，居中于命中节点；节点本身可比 base 大（hit_padding）。
	_base.custom_minimum_size = Vector2(side, side)
	_knob.custom_minimum_size = Vector2(knob_size, knob_size)
	_base.size = Vector2(side, side)
	_knob.size = Vector2(knob_size, knob_size)
	_base.position = _get_stick_center() - Vector2(side, side) * 0.5
	if _decor != null:
		_decor.size = Vector2(side, side)
		_decor.position = _base.position

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
		## emulate_mouse_from_touch=true 时模拟鼠标不得二次驱动摇杆。
		if event.device == InputEvent.DEVICE_ID_EMULATION:
			return
		_handle_mouse_button(event)
	elif event is InputEventMouseMotion:
		if event.device == InputEvent.DEVICE_ID_EMULATION:
			return
		_handle_mouse_motion(event)

## 命中区略大于视觉 base：以中心为圆心，base/2 + hit_padding 为半径。
func is_point_in_hit_area(local_pos: Vector2) -> bool:
	var center: Vector2 = _get_stick_center()
	return local_pos.distance_to(center) <= base_size * 0.5 + hit_padding

func _handle_touch(event: InputEventScreenTouch) -> void:
	if event.pressed:
		if not _active and is_point_in_hit_area(event.position):
			_activate(event.index, event.position)
	else:
		if _active and event.index == _touch_id:
			_release()

func _handle_drag(event: InputEventScreenDrag) -> void:
	if _active and event.index == _touch_id:
		_update_stick(event.position)

func _handle_mouse_button(event: InputEventMouseButton) -> void:
	if event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if not _active and is_point_in_hit_area(event.position):
				_activate(-1, event.position)
		else:
			if _active and _touch_id == -1:
				_release()

func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	if _active and _touch_id == -1:
		_update_stick(event.position)

func _activate(touch_id: int, initial_pos: Vector2 = Vector2.INF) -> void:
	_active = true
	_touch_id = touch_id
	if _has_visuals:
		_knob.visible = true
	_apply_active_visual(true)
	## 手指落在 base 外缘的 padding 区时，第一次就用真实位置算出向量，而不是先归零。
	if initial_pos == Vector2.INF:
		_update_stick(_get_stick_center())
	else:
		_update_stick(initial_pos)

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
	_apply_active_visual(false)
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
	_apply_active_visual(false)

func get_vector() -> Vector2:
	return _current_vector

func is_active() -> bool:
	return _active
