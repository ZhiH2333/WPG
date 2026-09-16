extends Resource
class_name CharacterCatalog

## 角色目录。重复 id 记错误并跳过后到的；找不到 id 返回 null。不是 Autoload。
@export var entries: Array[CharacterDef] = []

var _indexed: bool = false
var _by_id: Dictionary = {}
var _unique: Array[CharacterDef] = []

func get_count() -> int:
	_ensure_index()
	return _unique.size()

func get_all() -> Array[CharacterDef]:
	_ensure_index()
	return _unique.duplicate()

func get_by_id(character_id: StringName) -> CharacterDef:
	_ensure_index()
	if String(character_id).is_empty():
		return null
	if not _by_id.has(character_id):
		return null
	return _by_id[character_id] as CharacterDef

func _ensure_index() -> void:
	if _indexed:
		return
	_indexed = true
	_by_id.clear()
	_unique.clear()
	for def: CharacterDef in entries:
		if def == null:
			continue
		if String(def.id).is_empty():
			continue
		if _by_id.has(def.id):
			push_error("角色目录重复 id: %s" % String(def.id))
			continue
		_by_id[def.id] = def
		_unique.append(def)
