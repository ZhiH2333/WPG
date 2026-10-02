extends Node2D
class_name AbilityPulse

## 最小范围效果可视化：一圈向外扩散并淡出的圆。
## 只负责表现与自毁，不含伤害 / 命中逻辑（那属于 Combat，不属于 Ability Framework）。

var _radius: float = 46.0
var _lifetime: float = 0.35
var _age: float = 0.0

func setup(world_position: Vector2, radius: float, lifetime: float) -> void:
	global_position = world_position
	_radius = maxf(radius, 1.0)
	_lifetime = maxf(lifetime, 0.01)

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
	var current_radius: float = _radius * (0.35 + 0.65 * t)
	var color: Color = Color(1.0, 0.86, 0.36, 0.55 * (1.0 - t))
	draw_circle(Vector2.ZERO, current_radius, color)
