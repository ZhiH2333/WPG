extends Object
class_name GameRecords

## 兼容层：GameRecord / GameRecords 不再是 authoritative persistence model。
## 本类只是 GameSaveStore（SaveSlot 仓储）的投影 + 旧 API 门面，全 static，不是 Autoload。
## 所有真正的 save operation 都走 GameSaveStore；UI 禁止自己 FileAccess 读 records.json。
const PATH := GameSaveStore.PATH
const TMP_PATH := GameSaveStore.TMP_PATH
const FILE_NAME := GameSaveStore.FILE_NAME
const TMP_NAME := GameSaveStore.TMP_NAME
const SAVE_VERSION: int = GameSaveStore.SAVE_VERSION
const MAX_RECORDS: int = GameSaveStore.MAX_SLOTS
const MAX_HISTORY: int = GameSaveStore.MAX_HISTORY

static func load_from_disk() -> void:
	GameSaveStore.load_from_disk()

static func save_to_disk() -> void:
	GameSaveStore.save_to_disk()

static func list_records() -> Array[GameRecord]:
	var rows: Array[GameRecord] = []
	for slot: SaveSlot in GameSaveStore.list_slots():
		rows.append(GameRecord.from_save_slot(slot))
	return rows

static func get_record(id: String) -> GameRecord:
	var slot: SaveSlot = GameSaveStore.get_slot(id)
	if slot == null:
		return null
	return GameRecord.from_save_slot(slot)

static func create_record(name: String, character_id: String, loop_goal: int, arena_id: String = "yard") -> GameRecord:
	var slot: SaveSlot = GameSaveStore.create_slot(name, character_id, loop_goal, arena_id)
	if slot == null:
		return null
	return GameRecord.from_save_slot(slot)

static func delete_record(id: String) -> bool:
	return GameSaveStore.delete_slot(id)

static func rename_record(id: String, name: String) -> bool:
	return GameSaveStore.rename_slot(id, name)

static func ensure_playable_record(character_id: String, loop_goal: int, arena_id: String = "yard") -> GameRecord:
	var slot: SaveSlot = GameSaveStore.ensure_playable_slot(character_id, loop_goal, arena_id)
	if slot == null:
		return null
	return GameRecord.from_save_slot(slot)

## 追加一局结果（历史 + best_score）。评分只调 RunResult.compute_score，
## 规则版本记在 result.scoring_version，永远知道自己用的是哪套规则。
static func append_run_result(record_id: String, session: RunSession, outcome: String) -> void:
	if session == null:
		return
	if record_id.is_empty():
		return
	GameSaveStore.load_from_disk()
	if GameSaveStore.get_slot(record_id) == null:
		return
	var resolved: String = _sanitize_outcome(outcome)
	var result: RunResult = session.export_result(record_id, resolved)
	GameSaveStore.append_result(record_id, result)

## 评分公式唯一真源在 RunResult；这里只做转发，算法一字不改。
static func compute_score(loop_index: int, kills: int, gold: int, time_sec: float, outcome: String) -> int:
	return RunResult.compute_score(loop_index, kills, gold, time_sec, outcome)

static func get_max_records() -> int:
	return MAX_RECORDS

static func _sanitize_outcome(value: String) -> String:
	return RunResult.sanitize_outcome(value)
