extends RefCounted
class_name DragScroll

## 触屏拖动滚动（抄 settings_overlay 的手感），给 ScrollContainer 用。
##
## 为什么不直接用 ScrollContainer 自带的触摸拖动：`project.godot` 开着
## `pointing/emulate_mouse_from_touch`（架构守卫要求保留），触摸会先变成鼠标事件被
## Button 吃掉 —— ScrollContainer 的 `InputEventScreenTouch/Drag` 路径永远走不到，
## 列表就只能靠滚轮和滚动条。所以只能在 `_input` 层自己接管原生触摸事件。
##
## 手感与 settings 一致：低于 TOUCH_SLOP 当 tap 交还给按钮，越过 slop 才吞掉事件；
## 位置用指数平滑（帧率无关）逼近目标，收敛后把控制权还给 ScrollContainer（滚轮/滚动条照旧可用）。
##
## 用法：
##   var _drag := DragScroll.attach(_scroll, _area_control)   # area 可省，默认整个 ScrollContainer
##   func _input(event): if _open and _drag.handle_event(event): get_viewport().set_input_as_handled()
##   func _process(delta): _drag.step(delta)
##   func open(): _drag.reset()

## osu.Framework：一格滚轮 80px。
const SCROLL_DISTANCE: float = 80.0
## 与 settings 同一组衰减：普通滚轮 10/s，触控/触控板 50/s。
const DISTANCE_DECAY_SCROLL: float = 10.0
const DISTANCE_DECAY_PRECISE: float = 50.0
## 小于这个位移算 tap，交给按钮；越过才开始滚。
const TOUCH_SLOP: float = 12.0

var _scroll: ScrollContainer
var _area: Control
var _current: float = 0.0
var _target: float = 0.0
var _decay: float = DISTANCE_DECAY_SCROLL
var _active: bool = false
var _enabled: bool = true
var _index: int = -1
var _origin: Vector2 = Vector2.ZERO
var _dragging: bool = false
var _drag_session_active: bool = false

## 绑定一个 ScrollContainer。area 是「手指落在这块区域里才算滚动」的控制；不传就用 ScrollContainer 自己。
static func attach(scroll: ScrollContainer, area: Control = null) -> DragScroll:
	var helper: DragScroll = DragScroll.new()
	helper._scroll = scroll
	helper._area = area if area != null else scroll
	return helper

func is_dragging() -> bool:
	return _dragging

func set_enabled(value: bool) -> void:
	_enabled = value
	if not value:
		_reset_touch()

## 打开页面 / 换内容后调：回到顶部并清掉进行中的触摸会话。
func reset() -> void:
	_reset_touch()
	_current = 0.0
	_target = 0.0
	_active = false
	if _scroll != null:
		_scroll.scroll_vertical = 0

## 每帧调。收敛后不再写 scroll_vertical，把滚轮 / 滚动条的控制权还回去。
func step(delta: float) -> void:
	if _scroll == null or not _enabled:
		return
	if not _active:
		_current = float(_scroll.scroll_vertical)
		_target = _current
		return
	var blend: float = 1.0 - exp(-_decay * delta)
	_current += (_target - _current) * blend
	if absf(_target - _current) < 0.25:
		_current = _target
		_active = false
	_scroll.scroll_vertical = int(round(_current))

## 在 `_input()` 里调。返回 true 表示本层已消费，调用方要 set_input_as_handled()。
func handle_event(event: InputEvent) -> bool:
	if _scroll == null or not _enabled:
		return false
	var touch: InputEventScreenTouch = event as InputEventScreenTouch
	if touch != null:
		if touch.pressed:
			if _point_in_area(touch.position):
				_begin_touch(touch.index, touch.position)
			return false
		if touch.index != _index:
			return false
		var was_dragging: bool = _dragging
		_reset_touch()
		return was_dragging
	var drag: InputEventScreenDrag = event as InputEventScreenDrag
	if drag == null or drag.index != _index:
		## 吞掉拖动会话中的模拟鼠标抬起（左键），防止把滑动误判成点击按钮。
		var mouse: InputEventMouseButton = event as InputEventMouseButton
		if _drag_session_active and mouse != null and mouse.button_index == MOUSE_BUTTON_LEFT and not mouse.pressed:
			_drag_session_active = false
			return true
		return false
	## screen_relative 不受 Content Scale 影响，比 relative 更适合触控拖动。
	if not _dragging:
		if absf(drag.position.y - _origin.y) < TOUCH_SLOP:
			return false
		_dragging = true
		_drag_session_active = true
		_active = true
		_current = float(_scroll.scroll_vertical)
		_target = _current
		return true
	var delta_y: float = drag.screen_relative.y
	## 手指下移 -> 内容下移（target 减小）；手指上移 -> 内容上滚（target 增大）。
	if not is_zero_approx(delta_y):
		scroll_by(-delta_y, true)
	return true

## 滚轮 / 触控板 / 键盘翻页共用的入口。
func scroll_by(offset: float, precise: bool = false) -> void:
	if _scroll == null:
		return
	_decay = DISTANCE_DECAY_PRECISE if precise else DISTANCE_DECAY_SCROLL
	_current = float(_scroll.scroll_vertical) if not _active else _current
	_target = clampf(_target + offset, 0.0, max_scroll())
	_active = true

func max_scroll() -> float:
	if _scroll == null:
		return 0.0
	var bar: VScrollBar = _scroll.get_v_scroll_bar()
	if bar == null:
		return 0.0
	return maxf(0.0, bar.max_value - bar.page)

func _point_in_area(position: Vector2) -> bool:
	if _area == null:
		return true
	return _area.get_global_rect().has_point(position)

func _begin_touch(index: int, position: Vector2) -> void:
	_index = index
	_origin = position
	_dragging = false

func _reset_touch() -> void:
	_index = -1
	_dragging = false
	_drag_session_active = false
