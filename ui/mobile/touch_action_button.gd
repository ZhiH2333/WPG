extends Control
class_name TouchActionButton

## 轻量触屏按钮组件：pressed / released / held / just_pressed
## 不包含任何战斗逻辑，只产出边沿与状态。
## 视觉全部来自 ui/game_theme.tres，按 variant 选择 theme_type_variation。
## 禁止 StyleBoxFlat.new()。

signal pressed
signal released
signal just_pressed

## 触摸起手后再移动超过该像素数即视为 drag，不再算 click（移动端 tap/drag 区分）。
const DRAG_SLOP: float = 12.0

enum Variant {
	PRIMARY = 0,
	DEFAULT = 1,
	SMALL = 2,
}

@export var variant: Variant = Variant.DEFAULT
@export var button_text: String = "ACTION"
@export var button_size: Vector2 = Vector2(100, 100)
@export var font_size: int = 0
@export var use_small_variant: bool = false
## 命中区可比视觉大：>0 时作为触摸判定尺寸，否则用按钮自身 size。
@export var hit_size: Vector2 = Vector2.ZERO

var _held: bool = false
var _just_pressed: bool = false
var _touch_id: int = -1
var _mouse_over: bool = false
var _press_origin: Vector2 = Vector2.ZERO
var _dragging: bool = false
var _selected: bool = false

@onready var _button: Button = $Button
@onready var _label: Label = $Button/Label
var _has_visuals: bool = false

func _ready() -> void:
	## 组件自身是输入 owner：STOP 让 _gui_input 拿到原生 Touch / 真实鼠标。
	mouse_filter = Control.MOUSE_FILTER_STOP
	_has_visuals = is_instance_valid(_button) and is_instance_valid(_label)
	if use_small_variant and variant == Variant.DEFAULT:
		variant = Variant.SMALL
	if _has_visuals:
		_setup_button()

func _setup_button() -> void:
	_button.custom_minimum_size = button_size
	_button.size = button_size
	_button.theme_type_variation = _variation_name()
	_button.focus_mode = Control.FOCUS_NONE
	## 内部 Button/Label 只负责画面，绝不能成为输入 owner，否则会抢走父节点 _gui_input。
	_button.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_label.text = button_text
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if font_size > 0:
		_label.add_theme_font_size_override("font_size", font_size)

func _variation_name() -> String:
	if _selected:
		return "TouchActionButtonSelected"
	match variant:
		Variant.PRIMARY:
			return "TouchActionButtonPrimary"
		Variant.SMALL:
			return "TouchActionButtonSmall"
		_:
			return "TouchActionButton"

## 选中态视觉（例如当前武器）。与 HUD 的 selected 状态保持一致。
func set_selected(selected: bool) -> void:
	if _selected == selected:
		return
	_selected = selected
	if _has_visuals:
		_button.theme_type_variation = _variation_name()

func is_selected() -> bool:
	return _selected

func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_handle_touch(event)
	elif event is InputEventScreenDrag:
		_handle_drag(event)
	elif event is InputEventMouseButton:
		## emulate_mouse_from_touch=true 时 Android 会同时产生 ScreenTouch + 模拟 MouseButton。
		## 模拟鼠标只服务于标准 UI，绝不能二次驱动本组件。
		if event.device == InputEvent.DEVICE_ID_EMULATION:
			return
		_handle_mouse_button(event)
	elif event is InputEventMouseMotion:
		if event.device == InputEvent.DEVICE_ID_EMULATION:
			return
		_handle_mouse_motion(event)

func _handle_touch(event: InputEventScreenTouch) -> void:
	if event.pressed:
		if not _held and _is_point_in_button(event.position):
			_begin_press(event.index, event.position)
	else:
		if _held and event.index == _touch_id:
			_release()

func _handle_drag(event: InputEventScreenDrag) -> void:
	if not _held or event.index != _touch_id:
		return
	if _dragging:
		return
	if event.position.distance_to(_press_origin) > DRAG_SLOP:
		## 判定为 drag：取消本次按压，不触发 click/just_pressed。
		_dragging = true
		_release()

func _handle_mouse_button(event: InputEventMouseButton) -> void:
	if event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if not _held and _is_point_in_button(event.position):
				_begin_press(-1, event.position)
		else:
			if _held and _touch_id == -1:
				_release()

func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	if _held and _touch_id == -1 and not _dragging:
		if event.position.distance_to(_press_origin) > DRAG_SLOP:
			_dragging = true
			_release()
			return
	var inside: bool = _is_point_in_button(event.position)
	if _mouse_over != inside:
		_mouse_over = inside

func _begin_press(touch_id: int, origin: Vector2) -> void:
	_held = true
	_touch_id = touch_id
	_just_pressed = true
	_dragging = false
	_press_origin = origin
	pressed.emit()

func _is_point_in_button(point: Vector2) -> bool:
	var rect_size: Vector2 = hit_size if hit_size.x > 0.0 and hit_size.y > 0.0 else button_size
	return Rect2(Vector2.ZERO, rect_size).has_point(point)

func _release() -> void:
	if not _held:
		return
	_held = false
	_touch_id = -1
	_dragging = false
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
	_dragging = false
	_press_origin = Vector2.ZERO
