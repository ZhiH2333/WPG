extends Control
class_name HpChart

## 固定大小的 HP-时间图：横轴时间，纵轴血量。
##
## 只画 RunSession 记下的 (t_sec, hp_ratio) 点。本类自己不采样、不读 Player、不读输入。
## 事件式点用**台阶**连线：两点之间 HP 并没有连续变化，画斜线会假装它是平滑掉血的。
##
## 尺寸固定（custom_minimum_size + SIZE_SHRINK_CENTER），不随容器拉伸，
## 这样 UI Scale 放大时它只是整体跟着变大，不会因为布局挤压变形。

const BG_COLOR := Color(0.06, 0.07, 0.09, 0.85)
const GRID_COLOR := Color(1.0, 1.0, 1.0, 0.08)
const LINE_COLOR := Color(0.98, 0.30, 0.48, 1.0)
const AXIS_COLOR := Color(1.0, 1.0, 1.0, 0.25)
const PAD := Vector2(8.0, 8.0)
const GRID_STEPS: int = 4

var _points: PackedVector2Array = PackedVector2Array()
var _duration: float = 0.0

func set_series(points: PackedVector2Array, duration_sec: float) -> void:
	_points = points
	_duration = maxf(duration_sec, 0.0)
	queue_redraw()

func get_point_count() -> int:
	return _points.size()

func has_series() -> bool:
	return _points.size() >= 2

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), BG_COLOR, true)
	## 4x4 网格 = 横轴 4 段、纵轴 25% 一档。
	for i: int in GRID_STEPS + 1:
		var t: float = float(i) / float(GRID_STEPS)
		var x: float = PAD.x + (size.x - PAD.x * 2.0) * t
		var y: float = PAD.y + (size.y - PAD.y * 2.0) * t
		draw_line(Vector2(x, PAD.y), Vector2(x, size.y - PAD.y), GRID_COLOR, 1.0)
		draw_line(Vector2(PAD.x, y), Vector2(size.x - PAD.x, y), GRID_COLOR, 1.0)
	## 坐标轴
	draw_line(Vector2(PAD.x, size.y - PAD.y), Vector2(size.x - PAD.x, size.y - PAD.y), AXIS_COLOR, 1.0)
	draw_line(Vector2(PAD.x, PAD.y), Vector2(PAD.x, size.y - PAD.y), AXIS_COLOR, 1.0)
	if _points.is_empty():
		return
	var inner_w: float = maxf(size.x - PAD.x * 2.0, 1.0)
	var inner_h: float = maxf(size.y - PAD.y * 2.0, 1.0)
	## 没有时长（例如刚开局就死）时用最后一个点的时间兜底，避免除零。
	var span: float = _duration if _duration > 0.001 else maxf(_points[_points.size() - 1].x, 0.001)
	var prev: Vector2 = _to_screen(_points[0], span, inner_w, inner_h)
	for i: int in range(1, _points.size()):
		var cur: Vector2 = _to_screen(_points[i], span, inner_w, inner_h)
		draw_line(prev, Vector2(cur.x, prev.y), LINE_COLOR, 2.0)
		draw_line(Vector2(cur.x, prev.y), cur, LINE_COLOR, 2.0)
		prev = cur
	## 最后一段水平拉到右端：表示"这条线一直维持到本局结束"。
	draw_line(prev, Vector2(PAD.x + inner_w, prev.y), LINE_COLOR, 2.0)

func _to_screen(point: Vector2, span: float, inner_w: float, inner_h: float) -> Vector2:
	var tx: float = clampf(point.x / span, 0.0, 1.0)
	var ty: float = clampf(point.y, 0.0, 1.0)
	return Vector2(PAD.x + inner_w * tx, PAD.y + inner_h * (1.0 - ty))
