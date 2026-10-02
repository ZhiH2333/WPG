extends AbilityEffect
class_name AimPulseEffect

## 测试技能 1 的执行体（DIRECTION，instant）：在瞄准方向 distance 处生成一个短暂范围脉冲。
##
## 只用 context 提供的 origin / direction —— 不自己找 Player / Camera / 场景，也不读输入设备。

@export var distance: float = 130.0
@export var radius: float = 46.0
@export var lifetime: float = 0.35

func apply(context: AbilityContext) -> void:
	var caster: Node = context.caster
	if caster == null or not is_instance_valid(caster):
		return
	var parent: Node = caster.get_parent()
	if parent == null:
		return
	var direction: Vector2 = context.direction
	if direction.is_zero_approx():
		direction = Vector2.RIGHT
	direction = direction.normalized()
	var pulse: AbilityPulse = AbilityPulse.new()
	pulse.name = "AbilityPulse"
	pulse.setup(context.origin + direction * distance, radius, lifetime)
	parent.add_child(pulse)
	## 记进本次激活的 scratch，便于测试断言 / 后续把脉冲升级成可命中区域。
	context.scratch["pulse"] = pulse
