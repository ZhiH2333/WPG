extends Control
class_name TouchActionButton

## 轻量触屏按钮组件：pressed / released / held / just_pressed
## 不包含任何战斗逻辑，只产出边沿与状态。
## 视觉全部来自 ui/game_theme.tres：variant / held / selected 只切 theme_type_variation，
## icon 由 ui/mobile/touch_icon.gd 矢量现画。禁止 StyleBoxFlat.new()。

signal pressed
signal released
signal just_pressed

## 触摸起手后再移动超过该像素数即视为 drag，不再算 click（移动端 tap/drag 区分）。
const DRAG_SLOP: float = 12.0
## 按下时的视觉收缩与回弹时长（只有内层 Button 缩放，命中区不变）。
const PRESS_SCALE: float = 0.93
const PRESS_TWEEN_SEC: float = 0.07

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
## 矢量 icon（TouchIcon.Glyph）。NONE = 只用 button_text 文字。
@export var icon: TouchIcon.Glyph = TouchIcon.Glyph.NONE
## icon 占按钮短边半径的比例。
@export var icon_fill: float = 0.62

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
var _icon: TouchIcon = null
var _tween: Tween = null

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
	_button.pivot_offset = button_size * 0.5
	_button.focus_mode = Control.FOCUS_NONE
	## 内部 Button/Label 只负责画面，绝不能成为输入 owner，否则会抢走父节点 _gui_input。
	_button.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.theme_type_variation = &"TouchActionLabel"

	_label.text = button_text
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if font_size > 0:
		_label.add_theme_font_size_override("font_size", font_size)
	if icon != TouchIcon.Glyph.NONE:
		_build_icon()
	_apply_visual_state()

## icon 是内层 Button 的子节点：跟着按钮一起缩放，且不参与命中判定。
## button_text 为空时文字完全让位给 icon；两者同时存在时 icon 占上半、文字在下半。
func _build_icon() -> void:
	if button_text.is_empty():
		_label.visible = false
	_icon = TouchIcon.new()
	_icon.name = "Icon"
	_icon.glyph = icon
	_icon.fill = icon_fill
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_button.add_child(_icon)
	_icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if not button_text.is_empty():
		_icon.anchor_bottom = 0.54
		_icon.offset_bottom = 0.0
		_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM

func _variation_name() -> String:
	if _held:
		if _selected:
			return "TouchActionButtonSelectedHeld"
		if variant == Variant.PRIMARY:
			return "TouchActionButtonPrimaryHeld"
		return "TouchActionButtonHeld"
	if _selected:
		return "TouchActionButtonSelected"
	match variant:
		Variant.PRIMARY:
			return "TouchActionButtonPrimary"
		Variant.SMALL:
			return "TouchActionButtonSmall"
		_:
			return "TouchActionButton"

## 当前视觉 variation（正常 / 按下 / 选中 = 三套 theme token）。测试与调试可读。
func get_visual_variation() -> String:
	return _variation_name()

func get_button() -> Button:
	return _button

func get_icon_node() -> TouchIcon:
	return _icon

func _apply_visual_state() -> void:
	if not _has_visuals:
		return
	_button.theme_type_variation = _variation_name()
	if _icon != null:
		_icon.set_state(_held, _selected)
	_tween_scale(Vector2.ONE * (PRESS_SCALE if _held else 1.0))

## 只缩内层 Button（视觉），父节点命中区 / hit_size 完全不变。
func _tween_scale(target: Vector2) -> void:
	if not _has_visuals or not is_inside_tree():
		return
	if _button.scale.is_equal_approx(target):
		return
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_tween.tween_property(_button, "scale", target, PRESS_TWEEN_SEC)

## 选中态视觉（例如当前武器）。与 HUD 的 selected 状态保持一致。
func set_selected(selected: bool) -> void:
	if _selected == selected:
		return
	_selected = selected
	_apply_visual_state()

func is_selected() -> bool:
	return _selected

## 运行时改按钮文字（例如技能按钮显示 READY / 冷却秒数）。
## 只改画面，不改变输入语义。
func set_label_text(text: String) -> void:
	if button_text == text:
		return
	button_text = text
	if _has_visuals:
		_label.text = text
		_label.visible = true

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
	_apply_visual_state()
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
	_apply_visual_state()
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
	_apply_visual_state()
