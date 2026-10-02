extends AbilityEffect
class_name BoostSpeedEffect

## 测试技能 0 的执行体（SELF，带 duration）：把施法者移速乘一个系数，duration 结束后还原。
##
## 纪律：
##   - 通过 context.caster 的显式 getter 拿 motor，不做任何满场查找。
##   - 需要还原的原始速度存在 context.scratch（本次激活私有），绝不写回 AbilityDef，
##     否则同一份 AbilityDef 资源被多个玩家共用时会互相污染。

const SCRATCH_BASE_SPEED: StringName = &"base_move_speed"

@export var multiplier: float = 1.5

func apply(context: AbilityContext) -> void:
	var motor: PlayerMotor = _resolve_motor(context)
	if motor == null:
		return
	context.scratch[SCRATCH_BASE_SPEED] = motor.move_speed
	motor.move_speed = motor.move_speed * multiplier

func remove(context: AbilityContext) -> void:
	var motor: PlayerMotor = _resolve_motor(context)
	if motor == null:
		return
	if not context.scratch.has(SCRATCH_BASE_SPEED):
		return
	motor.move_speed = float(context.scratch[SCRATCH_BASE_SPEED])

## 契约：caster 必须提供 get_player_motor()（Player 已满足）。用 has_method 探测，
## 这样测试可以塞一个最小 stub，而不必拉起整个 Player 场景。
func _resolve_motor(context: AbilityContext) -> PlayerMotor:
	var caster: Node = context.caster
	if caster == null or not is_instance_valid(caster):
		return null
	if not caster.has_method("get_player_motor"):
		return null
	return caster.get_player_motor() as PlayerMotor
