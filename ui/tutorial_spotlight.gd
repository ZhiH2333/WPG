extends Control
class_name TutorialSpotlight

## 全屏 PAGE_VEIL + 挖洞高亮。洞外扩 SPREAD px，洞缘骨色描边。
const SPREAD: float = 8.0
const RING_WIDTH: float = 2.0

var _target: Control = null
var _target_rect: Rect2 = Rect2()
var _use_manual_rect: bool = false
var _veil_alpha: float = -1.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)

func set_target(control: Control) -> void:
	_target = control
	_use_manual_rect = false
	queue_redraw()

func set_manual_rect(rect: Rect2) -> void:
	_target = null
	_target_rect = rect
	_use_manual_rect = true
	queue_redraw()

func set_veil_strength(alpha: float) -> void:
	_veil_alpha = alpha
	queue_redraw()

func clear_target() -> void:
	_target = null
	_use_manual_rect = false
	queue_redraw()

func _process(_delta: float) -> void:
	if _target != null and is_instance_valid(_target) and _target.is_visible_in_tree():
		queue_redraw()

func _draw() -> void:
	var hole: Rect2 = _hole_rect()
	var veil: Color = UiType.PAGE_VEIL
	if _veil_alpha >= 0.0:
		veil.a = clampf(_veil_alpha, 0.0, 1.0)
	var full: Rect2 = Rect2(Vector2.ZERO, size)
	_draw_veil_ring(full, hole, veil)
	if hole.size.x > 0.0 and hole.size.y > 0.0:
		draw_rect(hole, UiType.INK, false, RING_WIDTH)

func _hole_rect() -> Rect2:
	if _use_manual_rect:
		return _target_rect.grow(SPREAD)
	if _target == null or not is_instance_valid(_target):
		return Rect2()
	var rect: Rect2 = _target.get_global_rect()
	var local: Rect2 = Rect2(get_global_transform().affine_inverse() * rect.position, rect.size)
	return local.grow(SPREAD)

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
