extends Node2D
class_name DamageNumber

## 命中点飘字。挂在游戏 World 画布上用 _draw 描字，不进 HUD，不跟 SubViewport/相机错位。
const FONT_COLOR := Color(1, 0.92, 0.55, 1)
const OUTLINE_COLOR := Color(0.08, 0.08, 0.1, 0.9)
const FONT_SIZE: int = 16
const OUTLINE_PX: int = 4
const LIFT_PX := Vector2(0.0, -12.0)

@export var duration_sec: float = 0.45
@export var rise_pixels: float = 50.0

var _age_sec: float = 0.0
var _start_position: Vector2 = Vector2.ZERO
var _text: String = "0"

static func spawn(from: Node, amount: int, world_position: Vector2) -> void:
	var host: Node = _resolve_host(from)
	if host == null:
		return
	var number: DamageNumber = DamageNumber.new()
	host.add_child(number)
	number.play(amount, world_position)

static func _resolve_host(from: Node) -> Node:
	if from == null:
		return null
	var vp: Viewport = from.get_viewport()
	if vp != null:
		var world: Node = vp.get_node_or_null("World")
		if world != null:
			return world
	if from is Node2D:
		return from.get_parent()
	var actor: Node = from.get_parent()
	if actor == null:
		return null
	return actor.get_parent()

func _ready() -> void:
	z_index = 40
	z_as_relative = false
	top_level = true

func play(amount: int, world_position: Vector2) -> void:
	_text = str(amount)
	_start_position = world_position + LIFT_PX
	global_position = _start_position
	_age_sec = 0.0
	modulate.a = 1.0
	queue_redraw()

func _process(delta: float) -> void:
	_age_sec += delta
	var t: float = clampf(_age_sec / duration_sec, 0.0, 1.0)
	global_position = _start_position + Vector2(0.0, -rise_pixels * t)
	modulate.a = 1.0 - t
	if _age_sec >= duration_sec:
		queue_free()

func _draw() -> void:
	var font: Font = ThemeDB.fallback_font
	if font == null:
		return
	var size: Vector2 = font.get_string_size(_text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, FONT_SIZE)
	var pos: Vector2 = Vector2(size.x * -0.5, font.get_ascent(FONT_SIZE) - size.y * 0.5)
	draw_string_outline(font, pos, _text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, FONT_SIZE, OUTLINE_PX, OUTLINE_COLOR)
	draw_string(font, pos, _text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, FONT_SIZE, FONT_COLOR)
