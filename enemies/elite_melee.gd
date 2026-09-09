extends MeleeEnemy
class_name EliteMelee

## 放大的近战精英：更肉、更慢、贴脸更疼。仍是红三角，不是猎人。
const VISUAL_SCALE := Vector2(1.75, 1.75)

func _ready() -> void:
	super._ready()
	max_hp = 90
	move_speed = 120.0
	acceleration = 1000.0
	knockback_impulse = 140.0
	contact_damage = 14
	_base_max_hp = max_hp
	_base_move_speed = move_speed
	_base_contact_damage = contact_damage
	_hp = max_hp
	_restore_visual_scale()

func get_kind_name() -> String:
	return "Elite"

func get_xp_reward() -> int:
	return 25

func get_gold_reward() -> int:
	return 8

func get_hp_per_loop() -> int:
	return 12

func get_contact_damage_per_loop() -> int:
	return 3

func _on_hold_in_reserve() -> void:
	super._on_hold_in_reserve()
	_restore_visual_scale()

func _on_reset_for_sandbox() -> void:
	super._on_reset_for_sandbox()
	if is_entering():
		_visual.scale = ENTER_SCALE_FROM * VISUAL_SCALE.x
		return
	_restore_visual_scale()

func _begin_enter() -> void:
	super._begin_enter()
	if _spawn_stagger_left_sec <= 0.0:
		_restore_visual_scale()
		return
	_visual.scale = ENTER_SCALE_FROM * VISUAL_SCALE.x

func _finish_entering() -> void:
	super._finish_entering()
	_restore_visual_scale()

func _update_enter_scale() -> void:
	if _defeated or _spawn_stagger_duration_sec <= 0.0 or _spawn_stagger_left_sec <= 0.0:
		return
	var t: float = 1.0 - (_spawn_stagger_left_sec / _spawn_stagger_duration_sec)
	_visual.scale = (ENTER_SCALE_FROM * VISUAL_SCALE.x).lerp(VISUAL_SCALE, clampf(t, 0.0, 1.0))

func _restore_visual_scale() -> void:
	if _visual == null or _defeated:
		return
	_visual.scale = VISUAL_SCALE
