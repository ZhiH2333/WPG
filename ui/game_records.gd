extends Object
class_name GameRecords

## 本地档位表。全是 static，不是 Autoload。写 user://records.json，禁止碰 progress.cfg。
const PATH := "user://records.json"
const TMP_PATH := "user://records.json.tmp"
const FILE_NAME := "records.json"
const TMP_NAME := "records.json.tmp"
const SAVE_VERSION: int = 1
const MAX_RECORDS: int = 12
const MAX_HISTORY: int = 10

static var _records: Array[GameRecord] = []

static func load_from_disk() -> void:
	_records.clear()
	if not FileAccess.file_exists(PATH):
		return
	var text: String = FileAccess.get_file_as_string(PATH)
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var root: Dictionary = parsed as Dictionary
	var raw_records: Variant = root.get("records", [])
	if typeof(raw_records) != TYPE_ARRAY:
		return
	for item: Variant in raw_records:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		_records.append(GameRecord.from_dictionary(item as Dictionary))

static func save_to_disk() -> void:
	var rows: Array = []
	for record: GameRecord in _records:
		if record == null:
			continue
		rows.append(record.to_dictionary())
	var payload: Dictionary = {
		"save_version": SAVE_VERSION,
		"records": rows,
	}
	_write_atomic(JSON.stringify(payload))

static func list_records() -> Array[GameRecord]:
	var sorted: Array[GameRecord] = []
	for record: GameRecord in _records:
		sorted.append(record)
	sorted.sort_custom(_is_created_earlier)
	return sorted

static func get_record(id: String) -> GameRecord:
	if id.is_empty():
		return null
	for record: GameRecord in _records:
		if record.id == id:
			return record
	return null

static func create_record(name: String, character_id: String, loop_goal: int, arena_id: String = "yard") -> GameRecord:
	load_from_disk()
	if _records.size() >= MAX_RECORDS:
		return null
	var record: GameRecord = GameRecord.new()
	record.id = _make_record_id()
	record.loop_goal = maxi(loop_goal, 0)
	record.character_id = _character_id_for_write(character_id)
	record.arena_id = _arena_id_for_write(arena_id)
	record.name = _resolve_name(name, record.character_id, record.loop_goal)
	record.created_at = int(Time.get_unix_time_from_system())
	record.best_score = 0
	_records.append(record)
	save_to_disk()
	return record

static func delete_record(id: String) -> bool:
	load_from_disk()
	var index: int = _find_record_index(id)
	if index < 0:
		return false
	_records.remove_at(index)
	save_to_disk()
	return true

static func ensure_playable_record(character_id: String, loop_goal: int, arena_id: String = "yard") -> GameRecord:
	load_from_disk()
	var matched: GameRecord = _find_earliest_match(character_id, loop_goal, arena_id)
	if matched != null:
		return matched
	var created: GameRecord = create_record("", character_id, loop_goal, arena_id)
	if created != null:
		return created
	var fallback: Array[GameRecord] = list_records()
	return fallback[0]

static func append_run_result(record_id: String, session: RunSession, outcome: String) -> void:
	load_from_disk()
	if session == null:
		return
	var record: GameRecord = get_record(record_id)
	if record == null:
		return
	var resolved: String = _sanitize_outcome(outcome)
	var loop_index: int = session.get_loop_index()
	var kills: int = session.get_kill_count()
	var gold: int = session.get_gold()
	var time_sec: float = session.get_elapsed_sec()
	var score: int = compute_score(loop_index, kills, gold, time_sec, resolved)
	var entry: Dictionary = {
		"score": score,
		"loop": loop_index,
		"kills": kills,
		"gold": gold,
		"time_sec": time_sec,
		"outcome": resolved,
		"timestamp": int(Time.get_unix_time_from_system()),
	}
	_insert_history_by_score(record, entry)
	record.best_score = maxi(record.best_score, score)
	save_to_disk()

static func compute_score(loop_index: int, kills: int, gold: int, time_sec: float, outcome: String) -> int:
	var cleared_bonus: int = 5000 if outcome == "cleared" else 0
	return loop_index * 1000 + kills * 5 + gold * 2 + floori(time_sec) + cleared_bonus

static func get_max_records() -> int:
	return MAX_RECORDS

static func _write_atomic(text: String) -> void:
	var file: FileAccess = FileAccess.open(TMP_PATH, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(text)
	file.flush()
	file.close()
	var dir: DirAccess = DirAccess.open("user://")
	if dir == null:
		return
	var err: Error = dir.rename(TMP_NAME, FILE_NAME)
	if err == OK:
		return
	dir.remove(FILE_NAME)
	dir.rename(TMP_NAME, FILE_NAME)

static func _make_record_id() -> String:
	return "r%d-%d" % [int(Time.get_unix_time_from_system()), randi()]

static func _character_id_for_write(requested: String) -> String:
	if requested == "boar" or requested == "chicken":
		return requested
	return "boar"

static func _arena_id_for_write(requested: String) -> String:
	return GameRecord._sanitize_arena_id(requested)

static func _resolve_name(name: String, character_id: String, loop_goal: int) -> String:
	if not name.strip_edges().is_empty():
		return name.strip_edges()
	var species: String = "Chicken" if character_id == "chicken" else "Boar"
	if loop_goal > 0:
		return "%s · %d loops" % [species, loop_goal]
	return "%s · Inf" % species

static func _sanitize_outcome(value: String) -> String:
	if value == "dead" or value == "cleared" or value == "quit":
		return value
	return "quit"

static func _find_record_index(id: String) -> int:
	if id.is_empty():
		return -1
	for i: int in _records.size():
		if _records[i].id == id:
			return i
	return -1

static func _find_earliest_match(character_id: String, loop_goal: int, arena_id: String) -> GameRecord:
	var wanted_arena: String = _arena_id_for_write(arena_id)
	var matched: GameRecord = null
	for record: GameRecord in _records:
		if record.character_id != character_id:
			continue
		if not _is_same_loop_goal_bucket(loop_goal, record.loop_goal):
			continue
		if record.arena_id != wanted_arena:
			continue
		if matched == null or record.created_at < matched.created_at:
			matched = record
	return matched

static func _is_same_loop_goal_bucket(requested: int, existing: int) -> bool:
	if requested <= 0:
		return existing <= 0
	return existing == requested

static func _insert_history_by_score(record: GameRecord, entry: Dictionary) -> void:
	var score: int = int(entry.get("score", 0))
	var inserted: bool = false
	for i: int in record.history.size():
		var existing: Dictionary = record.history[i]
		if score > int(existing.get("score", 0)):
			record.history.insert(i, entry)
			inserted = true
			break
	if not inserted:
		record.history.append(entry)
	while record.history.size() > MAX_HISTORY:
		record.history.remove_at(record.history.size() - 1)

static func _is_created_earlier(left: GameRecord, right: GameRecord) -> bool:
	return left.created_at < right.created_at
