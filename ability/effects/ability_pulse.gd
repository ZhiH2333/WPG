extends Node2D
class_name AbilityPulse

## 环形能量冲击波表现。伤害只在 AimPulseEffect 的权威结算中发生。

const DEFAULT_COLOR := Color(0.24, 0.86, 1.0, 1.0)

var _radius: float = 180.0
var _lifetime: float = 0.42
var _age: float = 0.0
var _color: Color = DEFAULT_COLOR

func setup(world_position: Vector2, radius: float, lifetime: float, color: Color = DEFAULT_COLOR) -> void:
	global_position = world_position
	_radius = maxf(radius, 1.0)
	_lifetime = maxf(lifetime, 0.01)
	_color = color
	z_index = 12
	z_as_relative = false

func _process(delta: float) -> void:
	_age += delta
	queue_redraw()
	if _age >= _lifetime:
		queue_free()

func get_age_ratio() -> float:
	return clampf(_age / _lifetime, 0.0, 1.0)

func get_radius() -> float:
	return _radius

func _draw() -> void:
	var t: float = get_age_ratio()
	var eased: float = 1.0 - pow(1.0 - t, 3.0)
	var current_radius: float = _radius * eased
	var alpha: float = 0.8 * (1.0 - t)
	var glow: Color = _color
	glow.a = alpha * 0.22
	draw_circle(Vector2.ZERO, current_radius, glow)
	var ring: Color = _color
	ring.a = alpha
	draw_arc(Vector2.ZERO, current_radius, 0.0, TAU, 96, ring, 5.0, true)
	var core: Color = Color(0.88, 0.98, 1.0, alpha * 0.85)
	draw_arc(Vector2.ZERO, maxf(0.0, current_radius - 5.0), 0.0, TAU, 96, core, 1.5, true)
