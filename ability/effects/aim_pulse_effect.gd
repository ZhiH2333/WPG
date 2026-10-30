extends AbilityEffect
class_name AimPulseEffect

## 以玩家为中心的瞬时范围控制：权威端对范围内每个有效敌人结算一次伤害和击退，
## 所有端可复用 AbilityPulse 播放扩散表现。

@export var radius: float = 180.0
@export var damage: int = 12
@export var lifetime: float = 0.42

func apply(context: AbilityContext) -> void:
	var caster: Node = context.caster
	if caster == null or not is_instance_valid(caster):
		return
	var parent: Node = caster.get_parent()
	if parent == null:
		return
	var pulse: AbilityPulse = AbilityPulse.new()
	pulse.name = "AbilityPulse"
	pulse.setup(context.origin, radius, lifetime)
	parent.add_child(pulse)
	context.scratch["pulse"] = pulse
	if context.sfx_pool != null:
		context.sfx_pool.play_pulse(context.origin)
	if not context.authoritative:
		return
	var hit_ids: Dictionary = {}
	for enemy: EnemyBase in context.targets:
		if enemy == null or not is_instance_valid(enemy):
			continue
		if enemy.is_in_reserve() or enemy.is_defeated():
			continue
		if context.origin.distance_squared_to(enemy.global_position) > radius * radius:
			continue
		var instance_id: int = enemy.get_instance_id()
		if hit_ids.has(instance_id):
			continue
		hit_ids[instance_id] = true
		var direction: Vector2 = enemy.global_position - context.origin
		if direction.is_zero_approx():
			direction = context.direction
		if direction.is_zero_approx():
			direction = Vector2.RIGHT
		enemy.apply_damage(damage, enemy.global_position, direction.normalized())
	context.scratch["hit_count"] = hit_ids.size()
