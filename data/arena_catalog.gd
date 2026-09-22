extends Resource
class_name ArenaCatalog

## 竞技场目录。重复 id 记错误并跳过后到的；找不到 id 返回 null。不是 Autoload。
const DEFAULT_ID: String = "yard"

@export var entries: Array[ArenaDef] = []

var _indexed: bool = false
var _by_id: Dictionary = {}
var _unique: Array[ArenaDef] = []

func get_count() -> int:
	_ensure_index()
	return _unique.size()

func get_all() -> Array[ArenaDef]:
	_ensure_index()
	return _unique.duplicate()

func get_by_id(arena_id: StringName) -> ArenaDef:
	_ensure_index()
	if String(arena_id).is_empty():
		return null
	if not _by_id.has(arena_id):
		return null
	return _by_id[arena_id] as ArenaDef

func sanitize(requested: String) -> String:
	if get_by_id(StringName(requested)) == null:
		return DEFAULT_ID
	return requested

func _ensure_index() -> void:
	if _indexed:
		return
	_indexed = true
	_by_id.clear()
	_unique.clear()
	for def: ArenaDef in entries:
		if def == null:
			continue
		if String(def.id).is_empty():
			continue
		if _by_id.has(def.id):
			push_error("竞技场目录重复 id: %s" % String(def.id))
			continue
		_by_id[def.id] = def
		_unique.append(def)
