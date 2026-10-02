extends Control
class_name MobileHUDScaler

## 移动端 HUD / Touch 布局自适应：Safe Area + 分辨率。
## 不复制第二套 HUD：只对既有 TouchControls 集群做「角落锚点缩放 + 内缩」，
## 并给既有 Hud 一个底部保留带（reserve），避免左摇杆压住血条。
##
## 参考画布 1920x1080。stretch=canvas_items / aspect=expand 下逻辑短边恒 >= 1080，
## 20:9 变宽、平板 4:3 变高、窄屏变长。本类按逻辑尺寸计算统一 touch_scale，
## 每个集群以「贴屏幕那侧的角」为 pivot 缩放，缩完仍钉在角上。
##
## 集群定位仍由 touch_controls.tscn 的 anchor/offset 负责；本类只写 scale / pivot_offset
## 与 Safe Area 内缩后的额外 offset，不改子节点内部视觉与输入合同。

## 设计分辨率。逻辑短边以此为基准换 touch_scale。
const DESIGN_SIZE := Vector2(1920, 1080)
## 触控控件缩放钳制：小屏别小到点不中，大屏别大到盖住半个画面。
const MIN_TOUCH_SCALE: float = 0.85
const MAX_TOUCH_SCALE: float = 1.25
## HUD 底部保留带：左摇杆高度 + 间距。touch 开启时 Hud 左下块上移这么多。
const HUD_BOTTOM_RESERVE: float = 232.0
const HUD_RESERVE_GAP: float = 16.0
## Safe Area 兜底与额外内缩，与 SafeAreaRoot 保持一致口径。
const SAFE_FALLBACK: float = 24.0
const SAFE_EXTRA: float = 8.0

signal layout_applied(touch_scale: float, bottom_reserve: float)

@export var move_stick_path: NodePath = NodePath("../SafeAreaRoot/MoveStick")
@export var aim_pad_path: NodePath = NodePath("../SafeAreaRoot/AimPad")
@export var weapon_cluster_path: NodePath = NodePath("../SafeAreaRoot/WeaponCluster")
@export var system_cluster_path: NodePath = NodePath("../SafeAreaRoot/SystemCluster")

var _move_stick: Control
var _aim_pad: Control
var _weapon_cluster: Control
var _system_cluster: Control
var _touch_scale: float = 1.0
var _bottom_reserve: float = 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_move_stick = get_node_or_null(move_stick_path) as Control
	_aim_pad = get_node_or_null(aim_pad_path) as Control
	_weapon_cluster = get_node_or_null(weapon_cluster_path) as Control
	_system_cluster = get_node_or_null(system_cluster_path) as Control
	var viewport: Viewport = get_viewport()
	if viewport != null:
		viewport.size_changed.connect(_apply_layout)
	_apply_layout()

func _notification(what: int) -> void:
	## 全屏锚点 Control 随视口 resize 触发；headless / 部分平台 size_changed 不一定发。
	if what == NOTIFICATION_RESIZED:
		_apply_layout.call_deferred()

func get_touch_scale() -> float:
	return _touch_scale

## 供 Hud 使用：Touch 开启时左下 HUD 需要让出的底部高度（像素，逻辑坐标）。
func get_hud_bottom_reserve() -> float:
	return _bottom_reserve

## 逻辑可见尺寸。优先 get_viewport_rect；退化时用 stretch 反算，最后回落设计稿。
func _logical_size() -> Vector2:
	var rect: Vector2 = get_viewport_rect().size
	if rect.x > 1.0 and rect.y > 1.0:
		return rect
	var viewport: Viewport = get_viewport()
	if viewport != null:
		var vis: Vector2 = viewport.get_visible_rect().size
		if vis.x > 1.0 and vis.y > 1.0:
			var stretch: Vector2 = viewport.get_stretch_transform().get_scale()
			if stretch.x > 0.001 and stretch.y > 0.001:
				return Vector2(vis.x / stretch.x, vis.y / stretch.y)
			return vis
	return DESIGN_SIZE

## Safe Area 内缩（相对窗口物理尺寸），换算到逻辑坐标。
func _safe_insets() -> Dictionary:
	var window: Window = get_window()
	if window == null:
		return {"left": SAFE_FALLBACK, "top": SAFE_FALLBACK, "right": SAFE_FALLBACK, "bottom": SAFE_FALLBACK}
	var window_size: Vector2i = window.size
	if window_size.x <= 0 or window_size.y <= 0:
		return {"left": SAFE_FALLBACK, "top": SAFE_FALLBACK, "right": SAFE_FALLBACK, "bottom": SAFE_FALLBACK}
	var rect: Rect2i = DisplayServer.get_display_safe_area()
	var logical: Vector2 = _logical_size()
	var sx: float = logical.x / float(window_size.x) if window_size.x > 0 else 1.0
	var sy: float = logical.y / float(window_size.y) if window_size.y > 0 else 1.0
	var left: float = maxf(float(rect.position.x) * sx, SAFE_FALLBACK)
	var top: float = maxf(float(rect.position.y) * sy, SAFE_FALLBACK)
	var right: float = maxf(float(window_size.x - rect.end.x) * sx, SAFE_FALLBACK)
	var bottom: float = maxf(float(window_size.y - rect.end.y) * sy, SAFE_FALLBACK)
	return {"left": left + SAFE_EXTRA, "top": top + SAFE_EXTRA, "right": right + SAFE_EXTRA, "bottom": bottom + SAFE_EXTRA}

## 统一触控缩放：以窗口物理短边对 1080 取比值。用窗口物理尺寸而非 content_scale 后的
## 逻辑尺寸，避免与用户 ui_scale 互相抵消（ui_scale 已经放大整棵树，这里不再重复缩）。
## 物理短边越大（平板）控件越大，反之越小；钳制保证小屏可点、大屏不遮挡。
func _compute_touch_scale(_logical: Vector2) -> float:
	var short_side: float = _window_short_side()
	return clampf(short_side / DESIGN_SIZE.y, MIN_TOUCH_SCALE, MAX_TOUCH_SCALE)

func _window_short_side() -> float:
	var window: Window = get_window()
	if window != null:
		var size: Vector2i = window.size
		if size.x > 0 and size.y > 0:
			return float(mini(size.x, size.y))
	var logical: Vector2 = _logical_size()
	return minf(logical.x, logical.y)

## 角落锚点缩放：pivot 取「贴屏幕那个角」，缩放后仍钉在角上。
## 再叠加 Safe Area 内缩：bottom-left 集群右移/上移，右下集群左移/上移等。
func _apply_layout() -> void:
	if not is_inside_tree():
		return
	var logical: Vector2 = _logical_size()
	var scale_value: float = _compute_touch_scale(logical)
	_touch_scale = scale_value
	_apply_cluster(_move_stick, Vector2(0.0, 1.0), scale_value)
	_apply_cluster(_aim_pad, Vector2(1.0, 1.0), scale_value)
	_apply_cluster(_weapon_cluster, Vector2(1.0, 1.0), scale_value)
	_apply_cluster(_system_cluster, Vector2(1.0, 0.0), scale_value)
	_bottom_reserve = HUD_BOTTOM_RESERVE * scale_value + HUD_RESERVE_GAP
	layout_applied.emit(_touch_scale, _bottom_reserve)

## anchor_dir = 该集群贴哪个角：(0,1)=左下，(1,1)=右下，(1,0)=右上。
func _apply_cluster(cluster: Control, anchor_dir: Vector2, scale_value: float) -> void:
	if cluster == null:
		return
	cluster.scale = Vector2(scale_value, scale_value)
	cluster.pivot_offset = Vector2(
		cluster.size.x * anchor_dir.x,
		cluster.size.y * anchor_dir.y
	)
