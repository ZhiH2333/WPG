extends Control
class_name WarningBadge

## 测试版提示页顶部的警示图标：一个圆角三角形，中间挖空一个感叹号。
##
## 不直接用 "⚠" 这个字符：Web 导出的系统字体回退不生效（godotengine/godot#78921），
## 仓库里也没有 emoji 字体，字符方案在网页上就是空白。画出来才能跨平台一致，
## 而且颜色跟着主题走。
##
## 用法：给一个 Control 挂这个脚本，按需要设 custom_minimum_size 即可。

## 琥珀色。黑底上最容易读成「警告」，又不像纯红那样像错误。
const FILL := Color(0.97, 0.76, 0.24, 1)
## 感叹号用挖空的做法：填成页面底色，视觉上就是三角缺了一块。
const CUTOUT := Color(0, 0, 0, 1)
## 圆角半径 = min(宽, 高) × 这个比例。
const CORNER_RATIO: float = 0.22
## 三角到底边留一点内边距，免得圆角贴着控件边缘。
const INSET_RATIO: float = 0.04
## 感叹号竖条：粗细 / 上下端位置（相对三角形高度）。
const BAR_W_RATIO: float = 0.11
const BAR_TOP_RATIO: float = 0.30
const BAR_BOTTOM_RATIO: float = 0.62
## 感叹号圆点：位置比例 + 半径（相对竖条粗细）。
const DOT_Y_RATIO: float = 0.78
const DOT_R_RATIO: float = 0.62


func _ready() -> void:
	resized.connect(queue_redraw)


func _draw() -> void:
	var w: float = size.x
	var h: float = size.y
	if w <= 1.0 or h <= 1.0:
		return
	var inset: float = minf(w, h) * INSET_RATIO
	var corners: PackedVector2Array = PackedVector2Array(
		[
			Vector2(w * 0.5, inset),
			Vector2(w - inset, h - inset),
			Vector2(inset, h - inset),
		]
	)
	draw_colored_polygon(_beveled(corners, minf(w, h) * CORNER_RATIO), FILL)
	draw_exclamation(Vector2(w * 0.5, h), inset)


## 每个角沿两条边各切掉 r，得到 6 个点的圆角三角形。
func _beveled(corners: PackedVector2Array, radius: float) -> PackedVector2Array:
	var points: PackedVector2Array = PackedVector2Array()
	var count: int = corners.size()
	for i: int in count:
		var current: Vector2 = corners[i]
		var previous: Vector2 = corners[(i + count - 1) % count]
		var following: Vector2 = corners[(i + 1) % count]
		var to_previous: Vector2 = (previous - current).normalized()
		var to_following: Vector2 = (following - current).normalized()
		points.append(current + to_previous * radius)
		points.append(current + to_following * radius)
	return points


## 中间挖出的感叹号。中心 x 恒等于控件中线，靠 size 算，不依赖字体。
func draw_exclamation(center_bottom: Vector2, inset: float) -> void:
	var w: float = size.x
	var h: float = size.y
	var usable: float = h - inset * 2.0
	var bar_w: float = maxf(w * BAR_W_RATIO, 3.0)
	var top: float = inset + usable * BAR_TOP_RATIO
	var bottom: float = inset + usable * BAR_BOTTOM_RATIO
	var x: float = center_bottom.x
	draw_line(Vector2(x, top), Vector2(x, bottom), CUTOUT, bar_w, true)
	draw_circle(Vector2(x, inset + usable * DOT_Y_RATIO), bar_w * DOT_R_RATIO, CUTOUT)
