extends RefCounted
class_name GameRecord

## 一条本地档的**兼容投影**（projection），不是 authoritative persistence model。
## 真源是 SaveSlot（data/save_slot.gd）+ GameSaveStore；GameRecord 只给旧 UI / 旧测试读。
## 不是 Resource，不是中途续打。history 只记局末结果。
const MAX_HISTORY: int = 10
const CHARACTER_BOAR := "boar"
const CHARACTER_CHICKEN := "chicken"
const ARENA_CATALOG: ArenaCatalog = preload("res://data/arena_catalog.tres")

var id: String = ""
var name: String = ""
var character_id: String = CHARACTER_BOAR
var loop_goal: int = 0
var arena_id: String = "yard"
var created_at: int = 0
var updated_at: int = 0
## NEW / IN_PROGRESS / CLEARED / FAILED（见 SaveSlot.Status）
var status: String = "NEW"
var best_score: int = 0
var scoring_version: int = RunResult.SCORING_VERSION
var history: Array[Dictionary] = []

## SaveSlot -> GameRecord 投影。真正的写盘永远走 GameSaveStore，不走这个对象。
static func from_save_slot(slot: SaveSlot) -> GameRecord:
	var record: GameRecord = GameRecord.new()
	if slot == null:
		return record
	record.id = slot.slot_id
	record.name = slot.name
	record.character_id = _sanitize_character_id(slot.character_id)
	record.loop_goal = maxi(slot.loop_goal, 0)
	record.arena_id = _sanitize_arena_id(slot.arena_id)
	record.created_at = slot.created_at
	record.updated_at = slot.updated_at
	record.status = SaveSlot.status_name(slot.status)
	record.best_score = slot.best_score
	record.scoring_version = slot.scoring_version
	record.history = []
	for entry: RunHistoryEntry in slot.history:
		if entry == null:
			continue
		record.history.append(entry.to_dictionary())
	return record

func has_active_run() -> bool:
	return status == "IN_PROGRESS"

func to_dictionary() -> Dictionary:
	return {
		"id": id,
		"name": name,
		"character_id": character_id,
		"loop_goal": loop_goal,
		"arena_id": arena_id,
		"created_at": created_at,
		"updated_at": updated_at,
		"status": status,
		"best_score": best_score,
		"scoring_version": scoring_version,
		"history": _duplicate_history(),
	}

static func from_dictionary(data: Dictionary) -> GameRecord:
	var record: GameRecord = GameRecord.new()
	record.id = str(data.get("id", ""))
	record.name = str(data.get("name", ""))
	record.character_id = _sanitize_character_id(str(data.get("character_id", CHARACTER_BOAR)))
	record.loop_goal = maxi(int(data.get("loop_goal", 0)), 0)
	record.arena_id = _sanitize_arena_id(str(data.get("arena_id", "yard")))
	record.created_at = int(data.get("created_at", 0))
	record.updated_at = int(data.get("updated_at", record.created_at))
	record.status = _sanitize_status(str(data.get("status", "NEW")))
	record.best_score = int(data.get("best_score", 0))
	record.scoring_version = maxi(int(data.get("scoring_version", RunResult.SCORING_VERSION)), 0)
	record.history = _parse_history(data.get("history", []))
	return record

func _duplicate_history() -> Array:
	var rows: Array = []
	for entry: Dictionary in history:
		rows.append(entry.duplicate())
	return rows

static func _parse_history(raw: Variant) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	if typeof(raw) != TYPE_ARRAY:
		return entries
	for item: Variant in raw:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		entries.append(_parse_history_entry(item as Dictionary))
	entries.sort_custom(_is_score_higher)
	if entries.size() > MAX_HISTORY:
		entries.resize(MAX_HISTORY)
	return entries

static func _parse_history_entry(data: Dictionary) -> Dictionary:
	return {
		"score": int(data.get("score", 0)),
		"loop": int(data.get("loop", 0)),
		"kills": int(data.get("kills", 0)),
		"gold": int(data.get("gold", 0)),
		"time_sec": float(data.get("time_sec", 0.0)),
		"outcome": _sanitize_outcome(str(data.get("outcome", "quit"))),
		"timestamp": int(data.get("timestamp", 0)),
		"scoring_version": maxi(int(data.get("scoring_version", RunResult.SCORING_VERSION)), 0),
	}

static func _sanitize_character_id(value: String) -> String:
	if value == CHARACTER_BOAR or value == CHARACTER_CHICKEN:
		return value
	return CHARACTER_BOAR

static func _sanitize_arena_id(value: String) -> String:
	return ARENA_CATALOG.sanitize(value)

static func _sanitize_outcome(value: String) -> String:
	return RunResult.sanitize_outcome(value)

static func _sanitize_status(value: String) -> String:
	return SaveSlot.status_name(SaveSlot.status_from_name(value))

static func _is_score_higher(left: Dictionary, right: Dictionary) -> bool:
	return int(left.get("score", 0)) > int(right.get("score", 0))
