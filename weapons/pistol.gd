extends Weapon
class_name Pistol

## 点射或按住都行；松开后冷却钳到 now，可立刻再点。散布 0。

func _ready() -> void:
	fire_interval = 0.18
	projectile_speed = 980.0
	damage = 8
	lifetime = 0.9
	super._ready()

func get_display_name() -> String:
	return "Pistol"

func _should_reset_cooldown_on_release() -> bool:
	return true

func _pellets_per_shot() -> int:
	return 1

func _spread_deg_for_this_shot() -> float:
	return 0.0
