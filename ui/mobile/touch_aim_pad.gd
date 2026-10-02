extends Control
class_name TouchAimPad

## 移动端右侧 Aim Direction Pad：固定 Base + 固定 Center。
## 与 VirtualStick 输入语义不同：只表达方向，不表达距离。
##   direction = (touch_position - center).normalized()
## 手指离中心 20px 还是 100px，只要方向相同，输出就相同（不 clamp 到半径，也不做 mag）。
## 无 Arrow / 无 Knob：方向反馈交给世界准星，控件本身保持中性。
## 视觉全部来自 ui/game_theme.tres，不创建 StyleBoxFlat.new()。
## 共同接口与 VirtualStick 对齐：stick_moved / stick_released / get_vector / is_active。

signal stick_moved(direction: Vector2)
signal stick_released

@export var base_size: float = 200.0
## 触摸命中区可比视觉半径大：手指落在 base/2 + hit_padding 内即可激活。
@export var hit_padding: float = 60.0
## 方向死区：距中心太近不产生方向，避免抖动，但一旦超出就是纯方向，不再随距离变化。
@export var direction_deadzone: float = 12.0

var _active: bool = false
var _touch_id: int = -1
var _direction: Vector2 = Vector2.ZERO

@onready var _base: Panel = $Base
@onready var _center: Control = $Center
var _center_icon: TouchIcon = null
var _has_visuals: bool = false

func _ready() -> void:
	## 组件自身是输入 owner：STOP 让 _gui_input 拿到原生 Touch / 真实鼠标。
	mouse_filter = Control.MOUSE_FILTER_STOP
	_has_visuals = is_instance_valid(_base) and is_instance_valid(_center)
	if _has_visuals:
		_setup_visuals()
	reset()

func _setup_visuals() -> void:
	_base.theme_type_variation = "TouchStickBase"
	## 视觉层只负责画面，不抢占输入。
	_base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_center_icon = _center as TouchIcon
	_apply_rest_visual()

## 按下时中心准星提亮（只切 TouchIcon 的 state，颜色仍来自 theme token）。
func _apply_active_visual(active: bool) -> void:
	if _center_icon != null:
		_center_icon.set_state(active)

func _get_center() -> Vector2:
	return size * 0.5

func _ensure_sizes() -> void:
	if not _has_visuals:
		return
	var side: float = base_size
	if side <= 0.0:
		side = minf(size.x, size.y)
	if side <= 0.0:
		side = 200.0
	_base.custom_minimum_size = Vector2(side, side)
	_base.size = Vector2(side, side)
	_base.position = _get_center() - Vector2(side, side) * 0.5
	_center.size = Vector2(40.0, 40.0)
	_center.position = _get_center() - _center.size * 0.5

func _apply_rest_visual() -> void:
	if not _has_visuals:
		return
	_base.visible = true
	_center.visible = true

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		if _has_visuals:
			_ensure_sizes()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_handle_touch(event)
	elif event is InputEventScreenDrag:
		_handle_drag(event)
	elif event is InputEventMouseButton:
		## emulate_mouse_from_touch=true 时模拟鼠标不得二次驱动。
		if event.device == InputEvent.DEVICE_ID_EMULATION:
			return
		_handle_mouse_button(event)
	elif event is InputEventMouseMotion:
		if event.device == InputEvent.DEVICE_ID_EMULATION:
			return
		_handle_mouse_motion(event)

func is_point_in_hit_area(local_pos: Vector2) -> bool:
	var center: Vector2 = _get_center()
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
		_update_direction(event.position)

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
		_update_direction(event.position)

func _activate(touch_id: int, initial_pos: Vector2 = Vector2.INF) -> void:
	_active = true
	_touch_id = touch_id
	_apply_active_visual(true)
	if initial_pos == Vector2.INF:
		_update_direction(_get_center())
	else:
		_update_direction(initial_pos)

## 只取方向：normalized()。不做 clamp，不用 magnitude，距离不影响输出。
## 控件不做方向视觉反馈，方向由世界准星表达。
func _update_direction(local_pos: Vector2) -> void:
	var center: Vector2 = _get_center()
	var offset: Vector2 = local_pos - center
	if offset.length() < direction_deadzone:
		_direction = Vector2.ZERO
	else:
		_direction = offset.normalized()
	stick_moved.emit(_direction)

func _release() -> void:
	_active = false
	_touch_id = -1
	_direction = Vector2.ZERO
	_apply_active_visual(false)
	stick_moved.emit(Vector2.ZERO)
	stick_released.emit()

func reset() -> void:
	_active = false
	_touch_id = -1
	_direction = Vector2.ZERO
	if _has_visuals:
		_ensure_sizes()
		_apply_rest_visual()
	_apply_active_visual(false)

func get_vector() -> Vector2:
	return _direction

func is_active() -> bool:
	return _active
