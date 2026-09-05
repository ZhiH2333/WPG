extends Weapon
class_name Shotgun

## 走近再扣：同一枪口扇形多弹，泵动冷却，松开不复位。
@export var pellet_count: int = 8
@export var spread_deg: float = 22.0
@export var pellet_jitter_deg: float = 1.0

func _ready() -> void:
	fire_interval = 0.62
	projectile_speed = 780.0
	damage = 6
	lifetime = 0.45
	super._ready()

func get_display_name() -> String:
	return "Shotgun"

func _should_reset_cooldown_on_release() -> bool:
	return false

func _pellets_per_shot() -> int:
	return pellet_count

func _spread_deg_for_this_shot() -> float:
	return spread_deg

func _pellet_jitter_deg() -> float:
	return randf_range(-pellet_jitter_deg, pellet_jitter_deg)

func _pellet_visual_scale() -> float:
	return 0.72

func get_camera_kick_amplitude() -> float:
	return 9.0

func get_recoil_pixels() -> float:
	return 6.0

func get_muzzle_flash_duration_sec() -> float:
	return 0.07

func get_muzzle_flash_scale() -> Vector2:
	return Vector2(1.85, 1.4)

func get_muzzle_flash_color() -> Color:
	return Color(1.0, 0.9, 0.52, 1)
