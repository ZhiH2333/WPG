extends Object
class_name SaveMigration

## records.json 的 schema 迁移。纯函数，不碰磁盘（磁盘 IO 归 GameSaveStore）。
##
## v1（旧 GameRecords）：{"save_version": 1, "records": [preset-like record]}
## v2（SaveSlot）：      {"save_version": 2, "slots":  [SaveSlot]}
##
## v1 -> v2 硬规则：
## - id / name / character_id / loop_goal / arena_id / created_at / best_score / history
##   全部尽可能保留。
## - 旧版本**从来没有**真正保存 active run → 迁移绝不伪造 active_run（必须为 null）。
## - 历史 best_score 是**账本**，不是当前 run 的进度，绝不写进 active_run。
const VERSION_V1: int = 1
const VERSION_V2: int = 2

## 返回可直接序列化的 v2 root。无法识别的输入返回空 v2 集合（不抛异常）。
static func migrate(root: Variant) -> Dictionary:
	if typeof(root) != TYPE_DICTIONARY:
		return _empty_root()
	var source: Dictionary = root as Dictionary
	var version: int = int(source.get("save_version", VERSION_V1))
	if version >= VERSION_V2:
		return _normalize_v2(source)
	return migrate_v1_records(_read_array(source, "records"))

static func migrate_v1_records(raw_records: Array) -> Dictionary:
	var slots: Array = []
	for item: Variant in raw_records:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var slot: Dictionary = _migrate_v1_record(item as Dictionary)
		if slot.is_empty():
			continue
		slots.append(slot)
	return {
		"save_version": VERSION_V2,
		"slots": slots,
	}

static func _migrate_v1_record(data: Dictionary) -> Dictionary:
	var slot_id: String = str(data.get("id", ""))
	if slot_id.is_empty():
		return {}
	var created_at: int = int(data.get("created_at", 0))
	var history_raw: Variant = data.get("history", [])
	var history: Array = []
	var updated_at: int = created_at
	var ever_cleared: bool = false
	var has_history: bool = false
	var scoring_version: int = 0
	if typeof(history_raw) == TYPE_ARRAY:
		for entry: Variant in history_raw as Array:
			if typeof(entry) != TYPE_DICTIONARY:
				continue
			var row: Dictionary = (entry as Dictionary).duplicate(true)
			## v1 没有 scoring_version；补上当前规则版本，让账本知道自己按哪套规则算的。
			if int(row.get("scoring_version", 0)) <= 0:
				row["scoring_version"] = RunResult.SCORING_VERSION
			scoring_version = maxi(scoring_version, int(row["scoring_version"]))
			var outcome: String = str(row.get("outcome", "quit"))
			if outcome == "cleared":
				ever_cleared = true
			has_history = true
			updated_at = maxi(updated_at, int(row.get("timestamp", 0)))
			history.append(row)
	var status: String = "NEW"
	if ever_cleared:
		status = "CLEARED"
	elif has_history:
		status = "FAILED"
	return {
		"schema_version": VERSION_V2,
		"slot_id": slot_id,
		"name": str(data.get("name", "")),
		"created_at": created_at,
		"updated_at": updated_at,
		## 旧存档没有 run 可续：active_run 恒为 null，绝不伪造。
		"status": status,
		"character_id": str(data.get("character_id", "boar")),
		"arena_id": str(data.get("arena_id", "yard")),
		"loop_goal": maxi(int(data.get("loop_goal", 0)), 0),
		"best_score": maxi(int(data.get("best_score", 0)), 0),
		"scoring_version": maxi(scoring_version, RunResult.SCORING_VERSION),
		"active_run": null,
		"history": history,
	}

static func _normalize_v2(source: Dictionary) -> Dictionary:
	var slots: Array = []
	for item: Variant in _read_array(source, "slots"):
		if typeof(item) != TYPE_DICTIONARY:
			continue
		slots.append(item)
	var out: Dictionary = {
		"save_version": VERSION_V2,
		"slots": slots,
	}
	return out

static func _read_array(source: Dictionary, key: String) -> Array:
	var raw: Variant = source.get(key, [])
	if typeof(raw) != TYPE_ARRAY:
		return []
	return raw as Array

static func _empty_root() -> Dictionary:
	return {
		"save_version": VERSION_V2,
		"slots": [],
	}
