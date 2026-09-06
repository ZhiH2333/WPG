extends Resource
class_name UpgradeCatalog

## 10 条 UpgradeDef 目录。重复 id 记错误并跳过后到的；找不到 id 返回 null。
@export var entries: Array[UpgradeDef] = []

var _indexed: bool = false
var _by_id: Dictionary = {}
var _unique: Array[UpgradeDef] = []

func get_count() -> int:
	_ensure_index()
	return _unique.size()

func get_all() -> Array[UpgradeDef]:
	_ensure_index()
	return _unique.duplicate()

func get_by_id(upgrade_id: StringName) -> UpgradeDef:
	_ensure_index()
	if not _by_id.has(upgrade_id):
		return null
	return _by_id[upgrade_id] as UpgradeDef

func _ensure_index() -> void:
	if _indexed:
		return
	_indexed = true
	_by_id.clear()
	_unique.clear()
	for def: UpgradeDef in entries:
		if def == null:
			continue
		if _by_id.has(def.id):
			push_error("升级目录重复 id: %s" % String(def.id))
			continue
		_by_id[def.id] = def
		_unique.append(def)
