extends Weapon
class_name Rifle

## 按住连发：第一发准，连续射击散布变大，停火后收回。
@export var min_spread_deg: float = 1.5
@export var max_spread_deg: float = 11.0
@export var spread_gain_deg: float = 0.9
@export var spread_recover_deg_per_sec: float = 18.0

var _current_spread_deg: float = 1.5

func _ready() -> void:
	fire_interval = 0.09
	projectile_speed = 1100.0
	damage = 5
	lifetime = 0.85
	_current_spread_deg = min_spread_deg
	super._ready()

func get_display_name() -> String:
	return "Rifle"

func get_current_spread_deg() -> float:
	return _current_spread_deg

func _should_reset_cooldown_on_release() -> bool:
	return true

func _pellets_per_shot() -> int:
	return 1

func _spread_deg_for_this_shot() -> float:
	return _current_spread_deg

func _direction_for_pellet(aim: Vector2, _index: int, _pellet_count: int) -> Vector2:
	var spread: float = _current_spread_deg
	return aim.rotated(deg_to_rad(randf_range(-spread, spread)))

func _tick_idle(delta: float) -> void:
	if _player_input != null and _player_input.fire_held:
		return
	_current_spread_deg = maxf(min_spread_deg, _current_spread_deg - spread_recover_deg_per_sec * delta)

func _on_shot_success() -> void:
	_current_spread_deg = minf(max_spread_deg, _current_spread_deg + spread_gain_deg)

func _on_deactivated() -> void:
	super._on_deactivated()
	_current_spread_deg = min_spread_deg

func get_camera_kick_amplitude() -> float:
	return 3.0

func get_recoil_pixels() -> float:
	return 3.0

func get_muzzle_flash_duration_sec() -> float:
	return 0.035

func get_muzzle_flash_scale() -> Vector2:
	return Vector2(0.9, 0.5)

func get_muzzle_flash_color() -> Color:
	return Color(1.0, 0.98, 0.86, 1)
