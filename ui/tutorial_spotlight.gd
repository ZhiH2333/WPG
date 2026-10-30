extends Control
class_name TutorialSpotlight

## 全屏 PAGE_VEIL 挖洞高亮。洞外扩 8px，洞缘骨色 2px；可画指向箭头。无第二框。
const SPREAD: float = 8.0
const RING_WIDTH: float = 2.0
const PULSE_HZ: float = 1.1
const ARROW_LEN: float = 18.0

var _target: Control = null
var _target_rect: Rect2 = Rect2()
var _use_manual_rect: bool = false
var _veil_alpha: float = -1.0
var _show_arrow: bool = false
var _pulse: float = 0.0

func _ready() -> void:
	## 有挖洞目标时拦截洞外点击；洞内 `_has_point` 返回 false 以穿透到目标。
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	set_process(true)

func set_target(control: Control, with_arrow: bool = true) -> void:
	_target = control
	_use_manual_rect = false
	_show_arrow = with_arrow and control != null
	_sync_mouse_filter()
	queue_redraw()

func set_manual_rect(rect: Rect2, with_arrow: bool = false) -> void:
	_target = null
	_target_rect = rect
	_use_manual_rect = true
	_show_arrow = with_arrow
	_sync_mouse_filter()
	queue_redraw()

func set_veil_strength(alpha: float) -> void:
	_veil_alpha = alpha
	queue_redraw()

func clear_target() -> void:
	_target = null
	_use_manual_rect = false
	_show_arrow = false
	_sync_mouse_filter()
	queue_redraw()

func _sync_mouse_filter() -> void:
	var hole: Rect2 = _hole_rect()
	mouse_filter = Control.MOUSE_FILTER_STOP if hole.size.x > 0.0 else Control.MOUSE_FILTER_IGNORE

func _has_point(point: Vector2) -> bool:
	if mouse_filter == Control.MOUSE_FILTER_IGNORE:
		return false
	var hole: Rect2 = _hole_rect()
	if hole.size.x > 0.0 and hole.has_point(point):
		return false
	return true

func hole_rect() -> Rect2:
	return _hole_rect()

func _process(delta: float) -> void:
	_pulse = fmod(_pulse + delta * PULSE_HZ, 1.0)
	if _target != null and is_instance_valid(_target) and _target.is_visible_in_tree():
		queue_redraw()
	elif _show_arrow or _veil_alpha >= 0.0:
		queue_redraw()

func _draw() -> void:
	var hole: Rect2 = _hole_rect()
	var veil: Color = UiType.PAGE_VEIL
	if _veil_alpha >= 0.0:
		veil.a = clampf(_veil_alpha, 0.0, 1.0)
	## α=0 且无洞：不画罩，避免无意义全屏填充。
	if veil.a <= 0.001 and hole.size.x <= 0.0:
		return
	var full: Rect2 = Rect2(Vector2.ZERO, size)
	_draw_veil_ring(full, hole, veil)
	if hole.size.x <= 0.0 or hole.size.y <= 0.0:
		return
	var ring: Color = UiType.INK
	ring.a = lerpf(0.55, 1.0, 0.5 + 0.5 * sin(_pulse * TAU))
	draw_rect(hole, ring, false, RING_WIDTH)
	if _show_arrow:
		_draw_pointer(hole)

func _hole_rect() -> Rect2:
	if _use_manual_rect:
		return _target_rect.grow(SPREAD)
	if _target == null or not is_instance_valid(_target):
		return Rect2()
	if not _target.is_visible_in_tree():
		return Rect2()
	var rect: Rect2 = _target.get_global_rect()
	var local_pos: Vector2 = get_global_transform().affine_inverse() * rect.position
	return Rect2(local_pos, rect.size).grow(SPREAD)

func _draw_veil_ring(full: Rect2, hole: Rect2, color: Color) -> void:
	if hole.size.x <= 0.0 or hole.size.y <= 0.0:
		draw_rect(full, color, true)
		return
	var left: Rect2 = Rect2(full.position, Vector2(maxf(hole.position.x - full.position.x, 0.0), full.size.y))
	var right: Rect2 = Rect2(
		Vector2(hole.end.x, full.position.y),
		Vector2(maxf(full.end.x - hole.end.x, 0.0), full.size.y)
	)
	var top: Rect2 = Rect2(
		Vector2(hole.position.x, full.position.y),
		Vector2(hole.size.x, maxf(hole.position.y - full.position.y, 0.0))
	)
	var bottom: Rect2 = Rect2(
		Vector2(hole.position.x, hole.end.y),
		Vector2(hole.size.x, maxf(full.end.y - hole.end.y, 0.0))
	)
	for patch: Rect2 in [left, right, top, bottom]:
		if patch.size.x > 0.0 and patch.size.y > 0.0:
			draw_rect(patch, color, true)

func _draw_pointer(hole: Rect2) -> void:
	## 骨色小三角，落在洞上方中点外侧，提示「点这里」。
	var tip: Vector2 = Vector2(hole.get_center().x, hole.position.y - 10.0)
	var bounce: float = sin(_pulse * TAU) * 3.0
	tip.y += bounce
	var left: Vector2 = tip + Vector2(-ARROW_LEN * 0.55, -ARROW_LEN)
	var right: Vector2 = tip + Vector2(ARROW_LEN * 0.55, -ARROW_LEN)
	var fill: Color = UiType.INK
	fill.a = 0.92
	draw_colored_polygon(PackedVector2Array([tip, left, right]), fill)
	var edge: Color = UiType.STRUCTURE
	edge.a = 0.9
	draw_polyline(PackedVector2Array([tip, left, right, tip]), edge, 1.5, true)
