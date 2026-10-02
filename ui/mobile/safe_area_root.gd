extends Control
class_name SafeAreaRoot

## 最小 Safe Area 接口：把窗口 safe area 内缩量换算成 Control 的 offset。
## 不处理具体手机型号，只读取 DisplayServer 报告的 safe area。
## Android 刘海 / 手势区 / 不同横屏分辨率统一走这条路径。

@export var fallback_margin: float = 24.0
@export var extra_padding: float = 8.0

func _ready() -> void:
	## SafeAreaRoot 必须是 PASS 而非 IGNORE，否则当 root.content_scale_factor != 1.0 时，
	## GUI 选取会在 IGNORE 层停止，无法穿透到 MoveStick/AimPad 等子控件。
	mouse_filter = Control.MOUSE_FILTER_PASS
	_apply_safe_area()
	get_viewport().size_changed.connect(_apply_safe_area)

func _apply_safe_area() -> void:
	var window: Window = get_window()
	if window == null:
		return
	var window_size: Vector2i = window.size
	if window_size.x <= 0 or window_size.y <= 0:
		return
	var rect: Rect2i = _valid_safe_area(window_size)
	var inset_left: float = float(rect.position.x)
	var inset_top: float = float(rect.position.y)
	var inset_right: float = float(window_size.x - rect.end.x)
	var inset_bottom: float = float(window_size.y - rect.end.y)
	inset_left = maxf(inset_left, fallback_margin)
	inset_top = maxf(inset_top, fallback_margin)
	inset_right = maxf(inset_right, fallback_margin)
	inset_bottom = maxf(inset_bottom, fallback_margin)
	offset_left = inset_left + extra_padding
	offset_top = inset_top + extra_padding
	offset_right = -(inset_right + extra_padding)
	offset_bottom = -(inset_bottom + extra_padding)

## DisplayServer 在 headless / 部分平台会返回 (0,0,0,0) 或越界 safe area。
## 那不是「无刘海」，而是无效数据；直接用会把内缩算成整屏宽度，控件塌到负坐标。
## 无效时回落到整个窗口，即四边内缩 0。
func _valid_safe_area(window_size: Vector2i) -> Rect2i:
	var rect: Rect2i = DisplayServer.get_display_safe_area()
	var degenerate: bool = rect.size.x <= 0 or rect.size.y <= 0
	var out_of_bounds: bool = rect.position.x < 0 or rect.position.y < 0 or rect.end.x > window_size.x or rect.end.y > window_size.y
	if degenerate or out_of_bounds:
		return Rect2i(0, 0, window_size.x, window_size.y)
	return rect
