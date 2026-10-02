extends RefCounted
class_name AbilityState

## 技能运行时状态。由 AbilityController 持有；AbilityDef 是只读配置，永不写入。
##
## 状态机（duration > 0）：
##   READY --activate--> ACTIVE --duration 走完--> COOLDOWN --冷却走完--> READY
## 状态机（instant，duration == 0）：
##   READY --activate--> COOLDOWN --冷却走完--> READY
## DISABLED 是「未装备 / 被显式禁用」，不参与上面的转换；从 DISABLED 出来只能靠 equip / set_disabled。

enum {
	READY,
	ACTIVE,
	COOLDOWN,
	DISABLED,
}

## UI / 日志用的可读名。禁止在 gameplay 里拿它做判断。
static func to_string_name(state: int) -> String:
	match state:
		READY:
			return "READY"
		ACTIVE:
			return "ACTIVE"
		COOLDOWN:
			return "COOLDOWN"
		DISABLED:
			return "DISABLED"
	return "UNKNOWN"
