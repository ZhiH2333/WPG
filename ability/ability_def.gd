extends Resource
class_name AbilityDef

## 技能配置（纯数据，可作为 .tres 保存）。
##
## 禁止写进这里的东西：
##   - 输入：key = KEY_F / button = X / touch slot。输入只属于 PlayerInput。
##   - 运行时状态：剩余冷却 / 剩余持续时间。同一个 AbilityDef 会被多个玩家共用，
##     运行时状态一律在 AbilityController（避免 A 放技能把 B 的冷却也改了）。
##
## 为什么是 `effect: AbilityEffect` 而不是 spec 建议的 `effect_type: String`：
## 字符串会逼 AbilityController 维护一张硬编码的 effect dispatch 表，正好违反
## 「数据驱动、不要把技能硬编码进 Controller」。用 Resource 引用后，新增技能 = 新增 .tres，
## Controller 一行都不用改。

enum TargetType {
	SELF,
	DIRECTION,
	AREA,
	TARGET,
}

## 最小 Cost 接口的类别。本阶段只有 NONE 会被真实结算：
## 非零 cost 需要 AbilityController.bind_cost_provider() 绑定一个提供者，
## 没绑定就一律拒绝（fail closed），避免"免费放技能"。
## 本阶段不因此重构 Player Resources。
enum CostType {
	NONE,
	HP,
	ENERGY,
	CHARGE,
}

@export var id: StringName = &""
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var icon: Texture2D = null
## 冷却秒数（0 = 无冷却，回到 READY）。
@export var cooldown: float = 0.0
## 持续秒数（0 = instant：不经过 ACTIVE，直接进 COOLDOWN）。
@export var duration: float = 0.0
@export var cost_type: CostType = CostType.NONE
@export var cost_value: int = 0
@export var target_type: TargetType = TargetType.SELF
## 真正的执行体。用 Resource 引用而不是字符串类型名。
@export var effect: AbilityEffect = null
## 传给 AbilityContext.parameters 的配置参数（执行体只读）。
@export var parameters: Dictionary = {}

func is_instant() -> bool:
	return duration <= 0.0

func has_cost() -> bool:
	return cost_type != CostType.NONE and cost_value > 0
