extends Node2D
class_name WorldHpBar

## 头顶短血条。不进 HUD、不跟 Visual 挤压，只画矩形。
const FILL_ENEMY: Color = Color(0.86, 0.16, 0.14, 1)
const FILL_COMPANION: Color = Color(0.22, 0.78, 0.38, 1)
const BG: Color = Color(0.06, 0.06, 0.08, 0.86)
const SIZE: Vector2 = Vector2(28.0, 3.0)
const PAD: float = 1.0
const GAP_PX: float = 6.0
const MIN_WIDTH: float = 22.0
const MAX_WIDTH: float = 52.0

var _fill: Color = FILL_ENEMY
var _ratio: float = 1.0
var _width: float = SIZE.x

func _ready() -> void:
	z_index = 16
	z_as_relative = false

func configure(fill: Color, y_offset: float, width: float) -> void:
	_fill = fill
	_width = clampf(width, MIN_WIDTH, MAX_WIDTH)
	position = Vector2(0.0, y_offset)
	queue_redraw()

func bind_hp(hp: int, max_hp: int) -> void:
	var next: float = 0.0
	if max_hp > 0:
		next = clampf(float(hp) / float(max_hp), 0.0, 1.0)
	if is_equal_approx(next, _ratio):
		return
	_ratio = next
	queue_redraw()

func set_shown(shown: bool) -> void:
	visible = shown

static func width_for_sprite(texture: Texture2D, body_scale: Vector2) -> float:
	if texture == null:
		return SIZE.x
	return clampf(float(texture.get_width()) * absf(body_scale.x) * 0.55, MIN_WIDTH, MAX_WIDTH)

static func y_for_sprite(texture: Texture2D, body_scale: Vector2) -> float:
	if texture == null:
		return -24.0
	return -float(texture.get_height()) * absf(body_scale.y) * 0.5 - GAP_PX

func _draw() -> void:
	var height: float = SIZE.y
	var top_left: Vector2 = Vector2(_width * -0.5, height * -0.5)
	draw_rect(Rect2(top_left, Vector2(_width, height)), BG, true)
	var inner_w: float = (_width - PAD * 2.0) * _ratio
	if inner_w <= 0.01:
		return
	var inner_h: float = height - PAD * 2.0
	var inner_pos: Vector2 = Vector2(top_left.x + PAD, top_left.y + PAD)
	draw_rect(Rect2(inner_pos, Vector2(inner_w, inner_h)), _fill, true)
