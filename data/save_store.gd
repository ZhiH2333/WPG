extends Object
class_name GameSaveStore

## SaveSlot 仓储：唯一的存档读写入口。全 static，不是 Autoload，不进场景树。
##
## 职责边界（硬约束）：
##   RunSession   -> 只 export checkpoint / result 数据，绝不碰磁盘
##   GameSaveStore -> serialize + persist（唯一允许读写 records.json 的地方）
##   UI           -> 只读 GameSaveStore 快照（经 GameRecords 兼容投影），禁止自己 FileAccess
##
## 磁盘：user://records.json（主）/ .tmp（原子写中转）/ .bak（上一份完好备份）
##       / .corrupt（解析失败时隔离的原始字节，作为证据保留）。
## 读：主文件可用则用；损坏 → 隔离 + 尝试 .bak；两个都坏 → 安全返回空集合且不覆盖。
## 写：完整 payload -> tmp -> flush/close -> 旧主旋转成 .bak -> tmp 改名成主。
const PATH := "user://records.json"
const TMP_PATH := "user://records.json.tmp"
const BAK_PATH := "user://records.json.bak"
const CORRUPT_PATH := "user://records.json.corrupt"
const FILE_NAME := "records.json"
const TMP_NAME := "records.json.tmp"
const BAK_NAME := "records.json.bak"
const CORRUPT_NAME := "records.json.corrupt"
const SAVE_VERSION: int = 2
const MAX_SLOTS: int = 12
const MAX_HISTORY: int = 10

static var _slots: Array[SaveSlot] = []
static var _loaded: bool = false
static var _last_error: String = ""
static var _diagnostics: PackedStringArray = PackedStringArray()

# ---- 磁盘 ----

static func load_from_disk() -> void:
	_slots.clear()
	_diagnostics.clear()
	_last_error = ""
	var main_exists: bool = FileAccess.file_exists(PATH)
	var bak_exists: bool = FileAccess.file_exists(BAK_PATH)
	if not main_exists and not bak_exists:
		_loaded = true
		return
	if main_exists:
		var parsed: Dictionary = _parse_file(PATH, FILE_NAME)
		if bool(parsed.get("ok", false)):
			_adopt_root(parsed.get("root", {}))
			_loaded = true
			return
		_last_error = str(parsed.get("error", "records.json 解析失败"))
		_diagnostics.append(_last_error)
		## 不把坏 JSON 覆盖成空数据：先把原始字节隔离留证。
		_quarantine_corrupt_main()
	if bak_exists:
		var parsed_bak: Dictionary = _parse_file(BAK_PATH, BAK_NAME)
		if bool(parsed_bak.get("ok", false)):
			_diagnostics.append("records.json 不可用，已回退到 records.json.bak")
			_adopt_root(parsed_bak.get("root", {}))
			_loaded = true
			return
		var bak_error: String = str(parsed_bak.get("error", "records.json.bak 解析失败"))
		_last_error = "%s | %s" % [_last_error, bak_error] if not _last_error.is_empty() else bak_error
		_diagnostics.append(bak_error)
	## 两个都坏：返回空集合，但什么都不覆盖（坏文件仍在盘上可诊断）。
	_diagnostics.append("records.json 与 records.json.bak 均不可用：返回空集合，未覆盖任何文件")
	_loaded = true

static func save_to_disk() -> bool:
	var rows: Array = []
	for slot: SaveSlot in _slots:
		if slot == null:
			continue
		rows.append(slot.to_dictionary())
	var payload: Dictionary = {
		"save_version": SAVE_VERSION,
		"slots": rows,
	}
	var text: String = JSON.stringify(payload)
	if not _write_tmp(text):
		return false
	return _rotate_tmp_into_place()

## 把坏掉的主文件挪成 .corrupt（保留证据），不删内容。
static func _quarantine_corrupt_main() -> void:
	var dir: DirAccess = DirAccess.open("user://")
	if dir == null:
		return
	dir.remove(CORRUPT_NAME)
	var err: Error = dir.rename(FILE_NAME, CORRUPT_NAME)
	if err != OK:
		_diagnostics.append("隔离坏文件失败（rename=%d）：" % err)

static func _parse_file(path: String, label: String) -> Dictionary:
	var text: String = FileAccess.get_file_as_string(path)
	if text.strip_edges().is_empty():
		return {"ok": false, "root": {}, "error": "%s 为空文件" % label}
	var json: JSON = JSON.new()
	var err: Error = json.parse(text)
	if err != OK:
		return {
			"ok": false,
			"root": {},
			"error": "%s JSON 解析失败（line %d）：%s" % [label, json.get_error_line(), json.get_error_message()],
		}
	if typeof(json.data) != TYPE_DICTIONARY:
		return {"ok": false, "root": {}, "error": "%s 顶层不是对象" % label}
	return {"ok": true, "root": json.data as Dictionary, "error": ""}

static func _adopt_root(root: Variant) -> void:
	_slots.clear()
	var migrated: Dictionary = SaveMigration.migrate(root)
	var raw_slots: Variant = migrated.get("slots", [])
	if typeof(raw_slots) != TYPE_ARRAY:
		return
	for item: Variant in raw_slots as Array:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var slot: SaveSlot = SaveSlot.from_dictionary(item as Dictionary)
		if slot.slot_id.is_empty():
			continue
		_slots.append(slot)

static func _write_tmp(text: String) -> bool:
	var file: FileAccess = FileAccess.open(TMP_PATH, FileAccess.WRITE)
	if file == null:
		_last_error = "无法写入临时文件 %s（error=%d）" % [TMP_PATH, FileAccess.get_open_error()]
		_diagnostics.append(_last_error)
		return false
	file.store_string(text)
	file.flush()
	file.close()
	return true

static func _rotate_tmp_into_place() -> bool:
	var dir: DirAccess = DirAccess.open("user://")
	if dir == null:
		_last_error = "无法打开 user:// 目录"
		_diagnostics.append(_last_error)
		return false
	if FileAccess.file_exists(PATH):
		dir.remove(BAK_NAME)
		var rotate_err: Error = dir.rename(FILE_NAME, BAK_NAME)
		if rotate_err != OK:
			_diagnostics.append("主文件轮转到备份失败（rename=%d）" % rotate_err)
	var err: Error = dir.rename(TMP_NAME, FILE_NAME)
	if err == OK:
		return true
	dir.remove(FILE_NAME)
	err = dir.rename(TMP_NAME, FILE_NAME)
	if err == OK:
		return true
	_last_error = "临时文件替换主文件失败（rename=%d）" % err
	_diagnostics.append(_last_error)
	return false

static func wipe_files() -> void:
	var dir: DirAccess = DirAccess.open("user://")
	if dir == null:
		return
	for name: String in [FILE_NAME, TMP_NAME, BAK_NAME, CORRUPT_NAME]:
		if FileAccess.file_exists("user://%s" % name):
			dir.remove(name)
	_slots.clear()
	_loaded = false
	_last_error = ""
	_diagnostics.clear()

# ---- 读 ----

static func ensure_loaded() -> void:
	if not _loaded:
		load_from_disk()

static func get_last_error() -> String:
	return _last_error

static func get_diagnostics() -> PackedStringArray:
	return _diagnostics.duplicate()

static func max_slots() -> int:
	return MAX_SLOTS

static func list_slots() -> Array[SaveSlot]:
	ensure_loaded()
	var sorted: Array[SaveSlot] = []
	for slot: SaveSlot in _slots:
		if slot == null:
			continue
		sorted.append(slot)
	sorted.sort_custom(_is_created_earlier)
	return sorted

static func get_slot(id: String) -> SaveSlot:
	if id.is_empty():
		return null
	ensure_loaded()
	for slot: SaveSlot in _slots:
		if slot != null and slot.slot_id == id:
			return slot
	return null

static func load_active_checkpoint(id: String) -> RunCheckpoint:
	var slot: SaveSlot = get_slot(id)
	if slot == null:
		return null
	return slot.active_run

static func get_latest_active_slot() -> SaveSlot:
	ensure_loaded()
	var best: SaveSlot = null
	for slot: SaveSlot in _slots:
		if slot == null or not slot.has_active_run():
			continue
		if best == null or slot.updated_at > best.updated_at:
			best = slot
	return best

static func get_latest_updated_slot() -> SaveSlot:
	ensure_loaded()
	var best: SaveSlot = null
	for slot: SaveSlot in _slots:
		if slot == null:
			continue
		if best == null or slot.updated_at > best.updated_at:
			best = slot
	return best

# ---- 写 ----

static func create_slot(name: String, character_id: String, loop_goal: int, arena_id: String = "yard") -> SaveSlot:
	load_from_disk()
	if _slots.size() >= MAX_SLOTS:
		return null
	var slot: SaveSlot = SaveSlot.create(
		_make_slot_id(),
		"",
		character_id,
		loop_goal,
		arena_id
	)
	slot.name = _resolve_name(name, slot.character_id, slot.loop_goal)
	_slots.append(slot)
	if save_to_disk():
		return slot
	## 写不进去就别留一个只存在于内存里的幽灵档。
	_slots.remove_at(_slots.size() - 1)
	return null

static func delete_slot(id: String) -> bool:
	load_from_disk()
	var index: int = _find_index(id)
	if index < 0:
		return false
	_slots.remove_at(index)
	return save_to_disk()

static func rename_slot(id: String, name: String) -> bool:
	load_from_disk()
	var slot: SaveSlot = get_slot(id)
	if slot == null:
		return false
	var trimmed: String = name.strip_edges()
	if trimmed.is_empty():
		return false
	slot.name = trimmed
	slot.touch()
	return save_to_disk()

## 与旧 ensure_playable_record 同一语义：按 character + loop_goal 桶 + arena 找最早匹配，
## 找不到就建一个。这是「用某个档开一局」的入口，不是 run 恢复。
static func ensure_playable_slot(character_id: String, loop_goal: int, arena_id: String = "yard") -> SaveSlot:
	load_from_disk()
	var matched: SaveSlot = _find_earliest_match(character_id, loop_goal, arena_id)
	if matched != null:
		return matched
	var created: SaveSlot = create_slot("", character_id, loop_goal, arena_id)
	if created != null:
		return created
	var fallback: Array[SaveSlot] = list_slots()
	if fallback.is_empty():
		return null
	return fallback[0]

static func commit_checkpoint(id: String, checkpoint: RunCheckpoint) -> bool:
	load_from_disk()
	var slot: SaveSlot = get_slot(id)
	if slot == null or checkpoint == null:
		return false
	slot.active_run = checkpoint
	slot.status = SaveSlot.Status.IN_PROGRESS
	slot.scoring_version = RunResult.SCORING_VERSION
	slot.touch()
	return save_to_disk()

static func mark_cleared(id: String, result: RunResult) -> bool:
	return _finish_run(id, result, SaveSlot.Status.CLEARED)

static func mark_failed(id: String, result: RunResult) -> bool:
	return _finish_run(id, result, SaveSlot.Status.FAILED)

static func clear_active_run(id: String) -> bool:
	load_from_disk()
	var slot: SaveSlot = get_slot(id)
	if slot == null:
		return false
	slot.clear_active_run()
	if slot.status == SaveSlot.Status.IN_PROGRESS:
		slot.status = SaveSlot.Status.FAILED if not slot.history.is_empty() else SaveSlot.Status.NEW
	slot.touch()
	return save_to_disk()

## 只追加局末账本（历史 + best_score），不改 active_run / 不改 status。
## 正式终局请用 mark_cleared / mark_failed；本方法只给账本类调用方与测试用。
static func append_result(id: String, result: RunResult) -> bool:
	load_from_disk()
	var slot: SaveSlot = get_slot(id)
	if slot == null or result == null:
		return false
	slot.insert_history(RunHistoryEntry.from_result(result))
	slot.touch()
	return save_to_disk()

static func _finish_run(id: String, result: RunResult, status: int) -> bool:
	load_from_disk()
	var slot: SaveSlot = get_slot(id)
	if slot == null:
		return false
	if result != null:
		slot.insert_history(RunHistoryEntry.from_result(result))
	slot.clear_active_run()
	if status == SaveSlot.Status.CLEARED:
		slot.mark_cleared()
	else:
		slot.mark_failed()
	slot.touch()
	return save_to_disk()

# ---- 内部 ----

static func _make_slot_id() -> String:
	return "s%d-%d" % [int(Time.get_unix_time_from_system()), randi()]

static func _resolve_name(name: String, character_id: String, loop_goal: int) -> String:
	if not name.strip_edges().is_empty():
		return name.strip_edges()
	var species: String = "Chicken" if character_id == SaveSlot.CHARACTER_CHICKEN else "Boar"
	if loop_goal > 0:
		return "%s · %d loops" % [species, loop_goal]
	return "%s · Inf" % species

static func _find_index(id: String) -> int:
	if id.is_empty():
		return -1
	for i: int in _slots.size():
		if _slots[i] != null and _slots[i].slot_id == id:
			return i
	return -1

static func _find_earliest_match(character_id: String, loop_goal: int, arena_id: String) -> SaveSlot:
	var wanted_character: String = SaveSlot.sanitize_character_id(character_id)
	var wanted_arena: String = SaveSlot.ARENA_CATALOG.sanitize(arena_id)
	var matched: SaveSlot = null
	for slot: SaveSlot in _slots:
		if slot == null:
			continue
		if slot.character_id != wanted_character:
			continue
		if not _is_same_loop_goal_bucket(loop_goal, slot.loop_goal):
			continue
		if slot.arena_id != wanted_arena:
			continue
		if matched == null or slot.created_at < matched.created_at:
			matched = slot
	return matched

static func _is_same_loop_goal_bucket(requested: int, existing: int) -> bool:
	if requested <= 0:
		return existing <= 0
	return existing == requested

static func _is_created_earlier(left: SaveSlot, right: SaveSlot) -> bool:
	return left.created_at < right.created_at
