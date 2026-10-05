extends RefCounted
class_name SaveSlot

## 一个存档位（Save Slot）。纯数据：不碰 SceneTree / UI / FileAccess / ENet /
## MultiplayerPeer，可 headless 单测，可 JSON 序列化 / 从 Dictionary 恢复。
##
## 边界：SaveSlot 才是「我现在这局在哪里」的 authoritative source。
## GameRecord 只是它的兼容投影；GameProgress 只是跨档位全局统计，绝不存 active_run。
const SCHEMA_VERSION: int = 2
const MAX_HISTORY: int = 10
const CHARACTER_BOAR := "boar"
const CHARACTER_CHICKEN := "chicken"
const CHARACTER_IDS: PackedStringArray = [CHARACTER_BOAR, CHARACTER_CHICKEN]
const ARENA_CATALOG: ArenaCatalog = preload("res://data/arena_catalog.tres")

## NEW = 档已创建但还没开始真正的 run（没有 active_run）。
## IN_PROGRESS = 存在可继续的 active_run。
## CLEARED = 这个 slot **曾经**成功通关过。
## FAILED = 一次 run 已经终止但没有通关。
enum Status { NEW, IN_PROGRESS, CLEARED, FAILED }

const STATUS_NAMES: Dictionary = {
	Status.NEW: "NEW",
	Status.IN_PROGRESS: "IN_PROGRESS",
	Status.CLEARED: "CLEARED",
	Status.FAILED: "FAILED",
}

var schema_version: int = SCHEMA_VERSION
var slot_id: String = ""
var name: String = ""
var created_at: int = 0
var updated_at: int = 0
var status: int = Status.NEW
var character_id: String = CHARACTER_BOAR
var arena_id: String = "yard"
var loop_goal: int = 0
var best_score: int = 0
var scoring_version: int = RunResult.SCORING_VERSION
## null = 这个 slot 现在没有进行中的 run。
var active_run: RunCheckpoint = null
var history: Array[RunHistoryEntry] = []

static func status_name(value: int) -> String:
	if STATUS_NAMES.has(value):
		return String(STATUS_NAMES[value])
	return String(STATUS_NAMES[Status.NEW])

static func status_from_name(value: String) -> int:
	for key: int in STATUS_NAMES:
		if String(STATUS_NAMES[key]) == value:
			return key
	return Status.NEW

static func create(slot_id: String, name: String, character_id: String, loop_goal: int, arena_id: String) -> SaveSlot:
	var slot: SaveSlot = SaveSlot.new()
	slot.slot_id = slot_id
	slot.name = name
	slot.character_id = sanitize_character_id(character_id)
	slot.arena_id = ARENA_CATALOG.sanitize(arena_id)
	slot.loop_goal = maxi(loop_goal, 0)
	var now: int = int(Time.get_unix_time_from_system())
	slot.created_at = now
	slot.updated_at = now
	slot.status = Status.NEW
	return slot

func has_active_run() -> bool:
	return active_run != null

func clear_active_run() -> void:
	active_run = null

func touch() -> void:
	updated_at = maxi(int(Time.get_unix_time_from_system()), updated_at)

## 只有「曾经成功通关」才允许是 CLEARED。
func mark_cleared() -> void:
	status = Status.CLEARED

## 一次 run 终止且没有通关。
func mark_failed() -> void:
	status = Status.FAILED

## 存在可继续的 active_run。
func mark_in_progress() -> void:
	status = Status.IN_PROGRESS

## 重开一局：清掉旧 active_run，回到 IN_PROGRESS（RUN_START 提交时调用）。
func begin_run() -> void:
	active_run = null
	status = Status.IN_PROGRESS

## history 插入（按 score 降序，超出上限丢最低分）。best_score 取见过的最大分。
func insert_history(entry: RunHistoryEntry) -> void:
	if entry == null:
		return
	var inserted: bool = false
	for i: int in history.size():
		var existing: RunHistoryEntry = history[i]
		if existing == null:
			continue
		if entry.score > existing.score:
			history.insert(i, entry)
			inserted = true
			break
	if not inserted:
		history.append(entry)
	while history.size() > MAX_HISTORY:
		history.remove_at(history.size() - 1)
	best_score = maxi(best_score, entry.score)
	scoring_version = entry.scoring_version

func to_dictionary() -> Dictionary:
	var rows: Array = []
	for entry: RunHistoryEntry in history:
		if entry == null:
			continue
		rows.append(entry.to_dictionary())
	return {
		"schema_version": schema_version,
		"slot_id": slot_id,
		"name": name,
		"created_at": created_at,
		"updated_at": updated_at,
		"status": status_name(status),
		"character_id": character_id,
		"arena_id": arena_id,
		"loop_goal": loop_goal,
		"best_score": best_score,
		"scoring_version": scoring_version,
		"active_run": active_run.to_dictionary() if active_run != null else null,
		"history": rows,
	}

static func from_dictionary(data: Dictionary) -> SaveSlot:
	var slot: SaveSlot = SaveSlot.new()
	slot.schema_version = maxi(int(data.get("schema_version", SCHEMA_VERSION)), 0)
	slot.slot_id = str(data.get("slot_id", ""))
	slot.name = str(data.get("name", ""))
	slot.created_at = int(data.get("created_at", 0))
	slot.updated_at = int(data.get("updated_at", slot.created_at))
	slot.status = status_from_name(str(data.get("status", "NEW")))
	slot.character_id = sanitize_character_id(str(data.get("character_id", CHARACTER_BOAR)))
	slot.arena_id = ARENA_CATALOG.sanitize(str(data.get("arena_id", "yard")))
	slot.loop_goal = maxi(int(data.get("loop_goal", 0)), 0)
	slot.best_score = maxi(int(data.get("best_score", 0)), 0)
	slot.scoring_version = maxi(int(data.get("scoring_version", RunResult.SCORING_VERSION)), 0)
	slot.history = _parse_history(data.get("history", []))
	var raw_active: Variant = data.get("active_run", null)
	if typeof(raw_active) == TYPE_DICTIONARY:
		slot.active_run = RunCheckpoint.from_dictionary(raw_active as Dictionary)
	else:
		slot.active_run = null
	## 状态与 active_run 必须自洽：没有 active_run 却标 IN_PROGRESS 是脏数据。
	if slot.status == Status.IN_PROGRESS and slot.active_run == null:
		slot.status = Status.NEW
	return slot

static func sanitize_character_id(value: String) -> String:
	if value in CHARACTER_IDS:
		return value
	return CHARACTER_BOAR

static func _parse_history(raw: Variant) -> Array[RunHistoryEntry]:
	var entries: Array[RunHistoryEntry] = []
	if typeof(raw) != TYPE_ARRAY:
		return entries
	for item: Variant in raw as Array:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		entries.append(RunHistoryEntry.from_dictionary(item as Dictionary))
	entries.sort_custom(RunHistoryEntry.is_score_higher)
	while entries.size() > MAX_HISTORY:
		entries.remove_at(entries.size() - 1)
	return entries
