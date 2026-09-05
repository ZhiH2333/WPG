extends Node2D
class_name HitSpark

## 命中点短火花：沿 -hit 微喷，约 0.08s 后 queue_free。不是粒子海。
const LIFE_SEC: float = 0.08
const SPRAY_SPEED: float = 140.0

var _age_sec: float = 0.0
var _spray_dir: Vector2 = Vector2.LEFT

func play(world_position: Vector2, hit_direction: Vector2) -> void:
	global_position = world_position
	if hit_direction.is_zero_approx():
		_spray_dir = Vector2.LEFT
	else:
		_spray_dir = -hit_direction.normalized()
	rotation = _spray_dir.angle()
	_age_sec = 0.0
	modulate.a = 1.0

func _process(delta: float) -> void:
	_age_sec += delta
	global_position += _spray_dir * SPRAY_SPEED * delta
	var t: float = clampf(_age_sec / LIFE_SEC, 0.0, 1.0)
	modulate.a = 1.0 - t
	scale = Vector2.ONE * (1.0 - 0.35 * t)
	if _age_sec >= LIFE_SEC:
		queue_free()
