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

## 评分公式唯一真源在 RunResult；这里只做转发，算法一字不改。
## 注意：这里**没有** append_run_result —— 局末账本的唯一写入点是
## GameSaveStore.mark_cleared / mark_failed（由 CombatSandbox._record_progress_if_needed 调用），
## 再开一个写入口就会出现重复写 result / 两套 source of truth。
static func compute_score(loop_index: int, kills: int, gold: int, time_sec: float, outcome: String) -> int:
	return RunResult.compute_score(loop_index, kills, gold, time_sec, outcome)

static func get_max_records() -> int:
	return MAX_RECORDS
