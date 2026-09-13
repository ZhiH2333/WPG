extends Weapon
class_name Smg

## 猪在乱打：固定 9° 散布，按住连扫，松开不复位冷却。不是猎人的精准步枪。
func _ready() -> void:
	fire_interval = 0.07
	projectile_speed = 880.0
	damage = 4
	lifetime = 0.65
	super._ready()

func get_display_name() -> String:
	return "Smg"

func get_muzzle_local_offset() -> Vector2:
	return Vector2(65, 13)

func _should_reset_cooldown_on_release() -> bool:
	return false

func _spread_deg_for_this_shot() -> float:
	return 9.0

func _direction_for_pellet(aim: Vector2, _index: int, _pellet_count: int) -> Vector2:
	var spread: float = _spread_deg_for_this_shot()
	return aim.rotated(deg_to_rad(randf_range(-spread, spread)))

func get_camera_kick_amplitude() -> float:
	return 4.0

func get_recoil_pixels() -> float:
	return 3.0

func get_muzzle_flash_duration_sec() -> float:
	return 0.04

func get_muzzle_flash_scale() -> Vector2:
	return Vector2(1.15, 0.9)

func get_muzzle_flash_color() -> Color:
	return Color(1.0, 0.93, 0.62, 1)
