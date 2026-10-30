extends Sprite2D
class_name DashAfterimage

const LIFETIME_SEC: float = 0.18
const GHOST_COLOR := Color(0.28, 0.9, 1.0, 0.42)

var _age_sec: float = 0.0

func setup(source: Sprite2D) -> void:
	if source == null:
		queue_free()
		return
	texture = source.texture
	centered = source.centered
	region_enabled = source.region_enabled
	region_rect = source.region_rect
	global_transform = source.global_transform
	flip_h = source.flip_h
	flip_v = source.flip_v
	modulate = GHOST_COLOR
	z_index = 4
	z_as_relative = false

func _process(delta: float) -> void:
	_age_sec += delta
	var t: float = clampf(_age_sec / LIFETIME_SEC, 0.0, 1.0)
	modulate.a = GHOST_COLOR.a * (1.0 - t)
	scale *= 1.0 + delta * 0.6
	if _age_sec >= LIFETIME_SEC:
		queue_free()
