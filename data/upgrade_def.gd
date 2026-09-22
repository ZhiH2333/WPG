extends Resource
class_name UpgradeDef

## 升级是数据，不是效果。禁止运行时用本资源改枪 / HP / 移速。
enum Kind {
	MAX_HP_FLAT,
	MOVE_SPEED_PCT,
	DAMAGE_FLAT,
	FIRE_RATE_PCT,
	PROJECTILE_SPEED_FLAT,
	I_FRAME_FLAT,
	SHOTGUN_PELLETS_FLAT,
	RIFLE_MAX_SPREAD_FLAT,
	KNOCKBACK_TAKEN_PCT,
}

@export var id: StringName
@export var title: String = ""
@export var description: String = ""
@export var kind: Kind = Kind.MAX_HP_FLAT
@export var value: float = 0.0
@export var stackable: bool = false
## 空字符串 = 全角色可抽；只允许 "" / "boar" / "chicken"。
@export var character_id: String = "":
	set(value):
		character_id = _sanitize_character_id(value)

func _sanitize_character_id(value: String) -> String:
	if value == "boar" or value == "chicken":
		return value
	return ""
