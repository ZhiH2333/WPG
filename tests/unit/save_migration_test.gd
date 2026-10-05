extends SceneTree

## v1 -> v2 迁移回归：旧 records.json 的字段全部保留、绝不伪造 active_run、
## 历史 best_score 不会被当成当前 run 进度。
## 跑法：godot --headless --path . --script res://tests/unit/save_migration_test.gd
## 通过输出 SAVE_MIGRATION_OK；失败逐条 SAVE_MIGRATION_FAIL 并返回非 0。

var _failures: PackedStringArray = PackedStringArray()

func _initialize() -> void:
	_run_all.call_deferred()

func _run_all() -> void:
	_case_v1_preserves_everything()
	_case_v1_never_fabricates_active_run()
	_case_v1_best_score_is_not_run_progress()
	_case_v1_status_derivation()
	_case_v1_malformed_records_skipped()
	_case_v2_passes_through()
	_case_unusable_input_yields_empty()
	if _failures.is_empty():
		print("SAVE_MIGRATION_OK")
		quit(0)
		return
	for failure: String in _failures:
		printerr("SAVE_MIGRATION_FAIL: %s" % failure)
	quit(1)

func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures.append(message)

func _v1_root() -> Dictionary:
	return {
		"save_version": 1,
		"records": [
			{
				"id": "r1700000000-77",
				"name": "Chicken · 20 loops",
				"character_id": "chicken",
				"loop_goal": 20,
				"arena_id": "pit",
				"created_at": 1700000000,
				"best_score": 15432,
				"history": [
					{
						"score": 15432,
						"loop": 7,
						"kills": 210,
						"gold": 480,
						"time_sec": 611.5,
						"outcome": "cleared",
						"timestamp": 1700000900,
					},
					{
						"score": 2100,
						"loop": 1,
						"kills": 30,
						"gold": 40,
						"time_sec": 95.0,
						"outcome": "dead",
						"timestamp": 1700000400,
					},
				],
			},
			{
				"id": "r1700000100-88",
				"name": "Boar · Inf",
				"character_id": "boar",
				"loop_goal": 0,
				"arena_id": "yard",
				"created_at": 1700000100,
				"best_score": 0,
				"history": [],
			},
		],
	}

func _migrated_slots() -> Array:
	var root: Dictionary = SaveMigration.migrate(_v1_root())
	_expect(int(root.get("save_version", 0)) == SaveMigration.VERSION_V2, "迁移后 save_version = 2")
	var slots: Variant = root.get("slots", [])
	_expect(typeof(slots) == TYPE_ARRAY, "迁移后键名是 slots")
	if typeof(slots) != TYPE_ARRAY:
		return []
	return slots as Array

## 9) v1 -> v2：id / name / character_id / loop_goal / arena_id / created_at / best_score / history 全保留。
func _case_v1_preserves_everything() -> void:
	var slots: Array = _migrated_slots()
	_expect(slots.size() == 2, "两个旧档都被迁移")
	if slots.size() < 2:
		return
	var first: Dictionary = slots[0]
	_expect(str(first.get("slot_id", "")) == "r1700000000-77", "id -> slot_id")
	_expect(str(first.get("name", "")) == "Chicken · 20 loops", "name 保留")
	_expect(str(first.get("character_id", "")) == "chicken", "character_id 保留")
	_expect(int(first.get("loop_goal", 0)) == 20, "loop_goal 保留")
	_expect(str(first.get("arena_id", "")) == "pit", "arena_id 保留")
	_expect(int(first.get("created_at", 0)) == 1700000000, "created_at 保留")
	_expect(int(first.get("best_score", 0)) == 15432, "best_score 保留")
	var history: Variant = first.get("history", [])
	_expect(typeof(history) == TYPE_ARRAY and (history as Array).size() == 2, "history 保留 2 条")
	if typeof(history) == TYPE_ARRAY and (history as Array).size() == 2:
		var rows: Array = history as Array
		_expect(int((rows[0] as Dictionary).get("score", 0)) == 15432, "history score 保留")
		_expect(str((rows[0] as Dictionary).get("outcome", "")) == "cleared", "history outcome 保留")
		_expect(int((rows[0] as Dictionary).get("timestamp", 0)) == 1700000900, "history timestamp 保留")
		_expect(int((rows[0] as Dictionary).get("scoring_version", 0)) == RunResult.SCORING_VERSION, "history 补 scoring_version")
	var second: Dictionary = slots[1]
	_expect(str(second.get("slot_id", "")) == "r1700000100-88", "第二个档 id 保留")
	_expect(int(second.get("best_score", 0)) == 0, "空档 best_score 保留 0")
	_expect((second.get("history") as Array).is_empty(), "空档 history 仍为空")

## 旧版本从来没保存过 active run：迁移绝不伪造一个。
func _case_v1_never_fabricates_active_run() -> void:
	var slots: Array = _migrated_slots()
	_expect(not slots.is_empty(), "迁移出了档")
	for item: Variant in slots:
		var slot: Dictionary = item as Dictionary
		_expect(slot.get("active_run", null) == null, "迁移后的档不得伪造 active_run")
		_expect(not slot.has("active_run") or slot["active_run"] == null, "active_run 显式为 null")

## 历史 best_score 是账本，不是当前 run 的进度。
func _case_v1_best_score_is_not_run_progress() -> void:
	var slots: Array = _migrated_slots()
	if slots.is_empty():
		return
	var slot: SaveSlot = SaveSlot.from_dictionary(slots[0] as Dictionary)
	_expect(slot.best_score == 15432, "best_score 迁移后仍在 best_score 上")
	_expect(not slot.has_active_run(), "best_score 不会变成 active_run")
	_expect(slot.active_run == null, "active_run 为 null")
	## best_score 只进账本：新写一局结果时它只可能被 max() 更新，不会被当成本局进度。
	var entry: RunHistoryEntry = RunHistoryEntry.new()
	entry.score = 10
	slot.insert_history(entry)
	_expect(slot.best_score == 15432, "更低的分不会拉低 best_score")
	_expect(slot.history.size() == 3, "新结果追加到 history")

## 迁移后的状态是安全状态：没有 active_run。
func _case_v1_status_derivation() -> void:
	var slots: Array = _migrated_slots()
	if slots.size() < 2:
		return
	var cleared_slot: SaveSlot = SaveSlot.from_dictionary(slots[0] as Dictionary)
	var empty_slot: SaveSlot = SaveSlot.from_dictionary(slots[1] as Dictionary)
	_expect(cleared_slot.status == SaveSlot.Status.CLEARED, "有通关历史的档迁移为 CLEARED")
	_expect(empty_slot.status == SaveSlot.Status.NEW, "空档迁移为 NEW")
	_expect(not cleared_slot.has_active_run(), "CLEARED 档没有 active_run")
	_expect(not empty_slot.has_active_run(), "NEW 档没有 active_run")

func _case_v1_malformed_records_skipped() -> void:
	var root: Dictionary = SaveMigration.migrate({
		"save_version": 1,
		"records": ["junk", 42, null, {"name": "no-id"}, {"id": "ok-id"}],
	})
	var slots: Variant = root.get("slots", [])
	_expect(typeof(slots) == TYPE_ARRAY, "坏记录不炸")
	if typeof(slots) == TYPE_ARRAY:
		_expect((slots as Array).size() == 1, "只留下有 id 的那条")
		if (slots as Array).size() == 1:
			_expect(str(((slots as Array)[0] as Dictionary).get("slot_id", "")) == "ok-id", "保留合法档")

## 已经是 v2 的输入直接透传（幂等）。
func _case_v2_passes_through() -> void:
	var v2: Dictionary = {
		"save_version": 2,
		"slots": [{"slot_id": "s-v2", "status": "IN_PROGRESS", "active_run": {"checkpoint_version": 1}}],
	}
	var out: Dictionary = SaveMigration.migrate(v2)
	_expect(int(out.get("save_version", 0)) == 2, "v2 版本号不变")
	var slots: Variant = out.get("slots", [])
	_expect(typeof(slots) == TYPE_ARRAY and (slots as Array).size() == 1, "v2 档位数不变")
	_expect(int(out.get("save_version", 0)) == int(v2["save_version"]), "幂等")

func _case_unusable_input_yields_empty() -> void:
	for bad: Variant in [null, "text", 42, []]:
		var out: Dictionary = SaveMigration.migrate(bad)
		_expect(int(out.get("save_version", 0)) == SaveMigration.VERSION_V2, "坏输入仍返回 v2 root")
		_expect((out.get("slots", []) as Array).is_empty(), "坏输入返回空集合")
	var missing_records: Dictionary = SaveMigration.migrate({"save_version": 1})
	_expect((missing_records.get("slots", []) as Array).is_empty(), "没有 records 键返回空集合")
