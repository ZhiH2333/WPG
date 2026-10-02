extends Resource
class_name AbilityEffect

## 技能执行体的统一接口。AbilityDef.effect 直接引用一个 AbilityEffect 资源（数据驱动）。
##
## 纪律（重要）：
## 1. 禁止 get_tree().current_scene / get_nodes_in_group() 自己满场找 Player / Enemy /
##    Camera / Weapon。需要什么一律由 AbilityContext 显式带进来。
## 2. 禁止写 AbilityDef / context.parameters。需要跨 apply/remove 保留的现场，放 context.scratch。
## 3. 禁止读输入设备。Effect 不接触键鼠 / 手柄 / Touch。
##
## 生命周期：
##   apply(context)  激活时调用一次。
##   remove(context) duration 走完 / cancel / clear 时调用，用于还原现场。
##                   instant 技能不会收到 remove。

func apply(_context: AbilityContext) -> void:
	pass

func remove(_context: AbilityContext) -> void:
	pass
