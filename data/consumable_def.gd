extends Resource
class_name ConsumableDef

## 局内消耗品。不写 owned_ids / records.json / progress.cfg。
enum Kind {
	HEAL_FLAT,
	HEAL_FULL,
	I_FRAME,
}

@export var id: StringName
@export var display_name: String = ""
@export var description: String = ""
@export var shop_cost: int = 0
@export var kind: Kind = Kind.HEAL_FLAT
@export var value: float = 0.0 ## HEAL_FLAT=回复点数；HEAL_FULL 填 0；I_FRAME=秒
