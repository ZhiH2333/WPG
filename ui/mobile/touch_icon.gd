extends Control
class_name TouchIcon

## 触控 UI 的纯矢量 icon：全部图形在 _draw() 里按归一化坐标（1.0 = 半径）现画，
## 不依赖 PNG / SVG，也不创建 StyleBoxFlat（视觉 token 仍只在 ui/game_theme.tres）。
## 颜色来自 theme 的 TouchIcon token：
##   icon_color        —— 常态
##   icon_active_color —— 按下
##   icon_accent_color —— 选中（当前武器）
## 组件不参与输入：mouse_filter 固定 IGNORE，命中判定永远归父级 TouchActionButton。

enum Glyph {
	NONE = 0,
	PISTOL = 1,
	SHOTGUN = 2,
	RIFLE = 3,
	SMG = 4,
	DASH = 5,
	FIRE = 6,
	PAUSE = 7,
	CROSSHAIR = 8,
	STICK_TICKS = 9,
}

## 画哪个图形。
@export var glyph: Glyph = Glyph.NONE
## 图形占控件短边半径的比例：1.0 = 顶满，0.62 留出按钮圆边的呼吸。
@export var fill: float = 0.62
## 额外透明度（摇杆底座的刻度用 0.5 左右的弱化值）。
@export var opacity: float = 1.0

var _active: bool = false
var _accent: bool = false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(false)

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()

func set_glyph(value: Glyph) -> void:
	if glyph == value:
		return
	glyph = value
	queue_redraw()

func get_glyph() -> Glyph:
	return glyph

## 按钮状态 -> icon 颜色。active = 正在按下；accent = 选中（当前武器）。
func set_state(active: bool, accent: bool = false) -> void:
	if _active == active and _accent == accent:
		return
	_active = active
	_accent = accent
	queue_redraw()

func is_active_state() -> bool:
	return _active

func set_opacity(value: float) -> void:
	var clamped: float = clampf(value, 0.0, 1.0)
	if is_equal_approx(opacity, clamped):
		return
	opacity = clamped
	queue_redraw()

func _draw() -> void:
	if glyph == Glyph.NONE:
		return
	var r: float = minf(size.x, size.y) * 0.5 * fill
	if r <= 0.5:
		return
	var c: Vector2 = size * 0.5
	var col: Color = _icon_color()
	match glyph:
		Glyph.PISTOL:
			_draw_pistol(c, r, col)
		Glyph.SHOTGUN:
			_draw_shotgun(c, r, col)
		Glyph.RIFLE:
			_draw_rifle(c, r, col)
		Glyph.SMG:
			_draw_smg(c, r, col)
		Glyph.DASH:
			_draw_dash(c, r, col)
		Glyph.FIRE:
			_draw_fire(c, r, col)
		Glyph.PAUSE:
			_draw_pause(c, r, col)
		Glyph.CROSSHAIR:
			_draw_crosshair(c, r, col)
		Glyph.STICK_TICKS:
			_draw_stick_ticks(c, r, col)

func _icon_color() -> Color:
	var col: Color = get_theme_color("icon_active_color" if _active else "icon_color", "TouchIcon")
	if _accent:
		col = get_theme_color("icon_accent_color", "TouchIcon")
	col.a *= opacity
	return col

# ---- 归一化绘制原语 ----

func _pts(c: Vector2, r: float, src: PackedVector2Array) -> PackedVector2Array:
	var out: PackedVector2Array = PackedVector2Array()
	for p: Vector2 in src:
		out.append(c + p * r)
	return out

func _poly(c: Vector2, r: float, src: PackedVector2Array, col: Color) -> void:
	draw_colored_polygon(_pts(c, r, src), col)

func _line(c: Vector2, r: float, src: PackedVector2Array, width: float, col: Color) -> void:
	var out: PackedVector2Array = _pts(c, r, src)
	draw_polyline(out, col, width, true)
	## draw_polyline 没有圆头/圆角，折点与端点补小圆，避免尖角。
	for p: Vector2 in out:
		draw_circle(p, width * 0.5, col)

func _capsule(c: Vector2, r: float, a: Vector2, b: Vector2, width: float, col: Color) -> void:
	var pa: Vector2 = c + a * r
	var pb: Vector2 = c + b * r
	var half: float = width * 0.5
	var n: Vector2 = (pb - pa).normalized().orthogonal() * half
	draw_colored_polygon(PackedVector2Array([pa + n, pb + n, pb - n, pa - n]), col)
	draw_circle(pa, half, col)
	draw_circle(pb, half, col)

func _ring(c: Vector2, r: float, radius: float, width: float, col: Color) -> void:
	draw_arc(c, radius * r, 0.0, TAU, 48, col, width, true)

# ---- 图形 ----

## 手枪：短滑套 + 后倾握把。
func _draw_pistol(c: Vector2, r: float, col: Color) -> void:
	_poly(c, r, PackedVector2Array([
		Vector2(-0.80, -0.34), Vector2(0.78, -0.34), Vector2(0.78, -0.06),
		Vector2(0.24, -0.06), Vector2(-0.06, 0.30), Vector2(-0.16, 0.66),
		Vector2(-0.48, 0.66), Vector2(-0.34, 0.30), Vector2(-0.36, -0.06),
		Vector2(-0.80, -0.06),
	]), col)

## 霰弹枪：细长枪管 + 护木 + 后托。
func _draw_shotgun(c: Vector2, r: float, col: Color) -> void:
	_poly(c, r, PackedVector2Array([
		Vector2(-0.95, -0.20), Vector2(0.95, -0.20), Vector2(0.95, -0.02), Vector2(-0.95, -0.02),
	]), col)
	_poly(c, r, PackedVector2Array([
		Vector2(-0.42, 0.02), Vector2(0.02, 0.02), Vector2(0.02, 0.26), Vector2(-0.42, 0.26),
	]), col)
	_poly(c, r, PackedVector2Array([
		Vector2(-0.95, -0.02), Vector2(-0.66, -0.02), Vector2(-0.86, 0.62), Vector2(-0.95, 0.62),
	]), col)

## 步枪：枪身 + 上方瞄准镜 + 弹匣 + 握把。
func _draw_rifle(c: Vector2, r: float, col: Color) -> void:
	_poly(c, r, PackedVector2Array([
		Vector2(-0.95, -0.12), Vector2(0.95, -0.12), Vector2(0.95, 0.14), Vector2(-0.95, 0.14),
	]), col)
	_poly(c, r, PackedVector2Array([
		Vector2(-0.34, -0.46), Vector2(0.28, -0.46), Vector2(0.28, -0.12), Vector2(-0.34, -0.12),
	]), col)
	_poly(c, r, PackedVector2Array([
		Vector2(-0.02, 0.14), Vector2(0.30, 0.14), Vector2(0.18, 0.66), Vector2(-0.16, 0.66),
	]), col)
	_poly(c, r, PackedVector2Array([
		Vector2(0.34, 0.14), Vector2(0.56, 0.14), Vector2(0.44, 0.56), Vector2(0.22, 0.56),
	]), col)
	_poly(c, r, PackedVector2Array([
		Vector2(-0.95, 0.14), Vector2(-0.66, 0.14), Vector2(-0.78, 0.52), Vector2(-0.95, 0.52),
	]), col)

## 冲锋枪：短枪身 + 直长弹匣。
func _draw_smg(c: Vector2, r: float, col: Color) -> void:
	_poly(c, r, PackedVector2Array([
		Vector2(-0.62, -0.16), Vector2(0.92, -0.16), Vector2(0.92, 0.10), Vector2(-0.62, 0.10),
	]), col)
	_poly(c, r, PackedVector2Array([
		Vector2(-0.36, 0.10), Vector2(-0.04, 0.10), Vector2(-0.04, 0.82), Vector2(-0.36, 0.82),
	]), col)
	_poly(c, r, PackedVector2Array([
		Vector2(0.28, 0.10), Vector2(0.52, 0.10), Vector2(0.42, 0.54), Vector2(0.18, 0.54),
	]), col)
	_poly(c, r, PackedVector2Array([
		Vector2(-0.95, -0.04), Vector2(-0.62, -0.04), Vector2(-0.62, 0.22), Vector2(-0.95, 0.22),
	]), col)

## 冲刺：双箭头 >> 。
func _draw_dash(c: Vector2, r: float, col: Color) -> void:
	var w: float = r * 0.26
	_line(c, r, PackedVector2Array([
		Vector2(-0.64, -0.56), Vector2(0.00, 0.0), Vector2(-0.64, 0.56),
	]), w, col)
	_line(c, r, PackedVector2Array([
		Vector2(0.08, -0.56), Vector2(0.72, 0.0), Vector2(0.08, 0.56),
	]), w, col)

## 开火：准心（外圈 + 四刻度 + 中心点）。
func _draw_fire(c: Vector2, r: float, col: Color) -> void:
	var w: float = r * 0.14
	_ring(c, r, 0.56, w, col)
	draw_circle(c, r * 0.13, col)
	for dir: Vector2 in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
		_line(c, r, PackedVector2Array([dir * 0.74, dir * 0.98]), w, col)

## 暂停：两根竖条。
func _draw_pause(c: Vector2, r: float, col: Color) -> void:
	var w: float = r * 0.30
	_capsule(c, r, Vector2(-0.28, -0.58), Vector2(-0.28, 0.58), w, col)
	_capsule(c, r, Vector2(0.28, -0.58), Vector2(0.28, 0.58), w, col)

## 瞄准：细准星（四刻度穿过细圆环，中心留空）。
func _draw_crosshair(c: Vector2, r: float, col: Color) -> void:
	var w: float = r * 0.10
	_ring(c, r, 0.54, w, col)
	for dir: Vector2 in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
		_line(c, r, PackedVector2Array([dir * 0.28, dir * 0.92]), w, col)

## 摇杆底座刻度：四向短线 + 中心点。
func _draw_stick_ticks(c: Vector2, r: float, col: Color) -> void:
	var w: float = r * 0.10
	for dir: Vector2 in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
		_line(c, r, PackedVector2Array([dir * 0.74, dir * 0.92]), w, col)
	draw_circle(c, r * 0.06, col)
