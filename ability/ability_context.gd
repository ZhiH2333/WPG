extends RefCounted
class_name AbilityContext

## 一次技能执行的运行时参数。由 AbilityController 构造，交给 AbilityEffect 执行。
##
## 只装 gameplay 事实：不放 InputEvent / Touch event / 鼠标位置 / Button 节点。
## 技能层不知道输入设备，也不知道 UI。
##
## 为什么要有 scratch：duration 类效果需要「还原现场」（例如把移速改回去）。
## 那份状态属于**这一次激活**，既不能写进 AbilityDef（多个玩家共用同一 Resource 会互相
## 污染），也不该混进 parameters（那是配置）。所以单独给一个本次激活的私有暂存区。

## 施法者（通常 Player）。Effect 只允许通过它已有的显式 getter 访问 gameplay。
var caster: Node = null
## 施法瞬间的世界坐标。
var origin: Vector2 = Vector2.ZERO
## 单位方向。SELF 忽略它；DIRECTION / AREA 用它决定落点。
var direction: Vector2 = Vector2.RIGHT
## 显式目标（TARGET 类技能用）。没有就是 null。
var target: Node = null
## 本次执行的帧步长。
var delta: float = 0.0
## AbilityDef.parameters 的**副本**：配置，Effect 只读。
var parameters: Dictionary = {}
## 本次激活的私有暂存区：Effect 把需要还原的现场放这里。
var scratch: Dictionary = {}
## 触发它的槽位（0 / 1）。
var slot: int = -1
## 实际类型是 AbilityDef。这里用 Resource 声明，是为了打断
## AbilityDef -> AbilityEffect -> AbilityContext -> AbilityDef 的 class_name 循环引用。
var ability: Resource = null

## 只读取配置参数。
func get_parameter(key: StringName, fallback: Variant = null) -> Variant:
	return parameters.get(key, fallback)

## 取数值配置参数，带兜底。
func get_number(key: StringName, fallback: float) -> float:
	var raw: Variant = parameters.get(key, null)
	if raw == null:
		return fallback
	return float(raw)
