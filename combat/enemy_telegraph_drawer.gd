extends Node2D
class_name EnemyTelegraphDrawer

## 预警绘制节点：挂在敌人下，读 EnemyTelegraph 状态画线。
## 不参与攻击决策；EnemyBase 禁止 queue_redraw，绘制隔离在本节点。

const AIM_WIDTH: float = 1.5
const AIM_DASH: float = 8.0
const AIM_GAP: float = 6.0
const CHARGE_CORE_WIDTH: float = 2.0
const DEFAULT_BODY_RADIUS: float = 16.0

var _telegraph: EnemyTelegraph
var _body_radius: float = DEFAULT_BODY_RADIUS

func _ready() -> void:
	z_index = 8
	z_as_relative = false
	set_process(false)

func bind_telegraph(telegraph: EnemyTelegraph) -> void:
	_telegraph = telegraph
	queue_redraw()

func set_body_radius(radius: float) -> void:
	_body_radius = maxf(4.0, radius)
	queue_redraw()

func refresh() -> void:
	visible = _telegraph != null and _telegraph.is_active()
	queue_redraw()

func _draw() -> void:
	if _telegraph == null or not _telegraph.is_active():
		return
	var from: Vector2 = _telegraph.origin_local
	var dir: Vector2 = _telegraph.direction
	if not dir.is_finite() or dir.is_zero_approx():
		dir = Vector2.RIGHT
	var to: Vector2 = from + dir * _telegraph.length
	match _telegraph.kind:
		EnemyTelegraph.Kind.AIM_LINE:
			_draw_aim_line(from, to)
		EnemyTelegraph.Kind.CHARGE_PATH:
			_draw_charge_path(from, to)
		EnemyTelegraph.Kind.FAN_VOLLEY:
			_draw_fan(from, dir)
		_:
			pass

func _draw_aim_line(from: Vector2, to: Vector2) -> void:
	var color: Color = EnemyTelegraph.DEFAULT_AIM_COLOR
	color.a = _telegraph.aim_alpha()
	_draw_dashed(from, to, color, AIM_WIDTH, AIM_DASH, AIM_GAP)

func _draw_charge_path(from: Vector2, to: Vector2) -> void:
	var track: Color = EnemyTelegraph.DEFAULT_AIM_COLOR
	track.a = _telegraph.charge_alpha()
	var width: float = _body_radius * 1.8
	draw_line(from, to, track, width, true)
	var core: Color = EnemyTelegraph.DEFAULT_CORE_COLOR
	core.a = 0.55 + _telegraph.progress() * 0.45
	draw_line(from, to, core, CHARGE_CORE_WIDTH, true)

func _draw_fan(from: Vector2, center_dir: Vector2) -> void:
	var count: int = maxi(1, _telegraph.fan_count)
	var half: int = count / 2
	var color: Color = EnemyTelegraph.DEFAULT_AIM_COLOR
	color.a = _telegraph.aim_alpha()
	for i: int in count:
		var offset: int = i - half
		var dir: Vector2 = center_dir.rotated(deg_to_rad(float(offset) * _telegraph.fan_spread_deg))
		var to: Vector2 = from + dir * _telegraph.length
		_draw_dashed(from, to, color, AIM_WIDTH, AIM_DASH, AIM_GAP)

func _draw_dashed(from: Vector2, to: Vector2, color: Color, width: float, dash: float, gap: float) -> void:
	var delta: Vector2 = to - from
	var total: float = delta.length()
	if total <= 0.01:
		return
	var step: Vector2 = delta / total
	var pos: float = 0.0
	var drawing: bool = true
	while pos < total:
		var seg: float = dash if drawing else gap
		var a: Vector2 = from + step * pos
		var b: Vector2 = from + step * minf(pos + seg, total)
		if drawing:
			draw_line(a, b, color, width, true)
		pos += seg
		drawing = not drawing
