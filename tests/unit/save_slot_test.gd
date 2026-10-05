extends SceneTree

## SaveSlot 回归：round trip / 非法数据清洗 / status 与 active_run 的自洽 / history 与 best_score。
## 跑法：godot --headless --path . --script res://tests/unit/save_slot_test.gd
## 通过输出 SAVE_SLOT_OK；失败逐条 SAVE_SLOT_FAIL 并返回非 0。
const ARENA_CATALOG: ArenaCatalog = preload("res://data/arena_catalog.tres")

var _failures: PackedStringArray = PackedStringArray()

func _initialize() -> void:
	_run_all.call_deferred()

func _run_all() -> void:
	_case_round_trip()
	_case_status_names()
	_case_status_transitions()
	_case_status_without_active_run_is_not_in_progress()
	_case_invalid_data_sanitized()
	_case_history_order_cap_and_best_score()
	if _failures.is_empty():
		print("SAVE_SLOT_OK")
		quit(0)
		return
	for failure: String in _failures:
		printerr("SAVE_SLOT_FAIL: %s" % failure)
	quit(1)

func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures.append(message)

func _make_slot() -> SaveSlot:
	var slot: SaveSlot = SaveSlot.create("s1000-1", "Boar · 20 loops", "chicken", 20, "pit")
	slot.created_at = 1700000000
	slot.updated_at = 1700000500
	var checkpoint: RunCheckpoint = RunCheckpoint.create(
		RunCheckpoint.Kind.LOOP_COMPLETE,
		_shared(),
		[_player()]
	)
	slot.active_run = checkpoint
	slot.status = SaveSlot.Status.IN_PROGRESS
	return slot

func _shared() -> SharedRunState:
	var state: SharedRunState = SharedRunState.make("run-1", "s1000-1")
	state.arena_id = "pit"
	state.loop_goal = 20
	state.loop_index = 3
	state.elapsed_sec = 123.5
	state.run_seed = 4242
	state.mode = "solo"
	state.outcome = "playing"
	return state

func _player() -> PlayerRunState:
	var state: PlayerRunState = PlayerRunState.create("profile-abc", "Evan", "chicken", 2)
	state.hp = 60
	state.max_hp = 140
	state.level = 6
	state.xp = 7
	state.pending_level = 1
	state.gold = 321
	state.kill_count = 88
	state.owned_upgrade_ids = ["swift", "swift", "thick_hide"]
	state.alive = true
	return state

## 1) SaveSlot round trip：to_dictionary -> from_dictionary 字段全等。
func _case_round_trip() -> void:
	var slot: SaveSlot = _make_slot()
	var entry: RunHistoryEntry = RunHistoryEntry.new()
	entry.score = 9999
	entry.loop = 4
	entry.kills = 70
	entry.gold = 210
	entry.time_sec = 64.2
	entry.outcome = "cleared"
	entry.timestamp = 1700000400
	slot.insert_history(entry)
	slot.best_score = 9999

	var restored: SaveSlot = SaveSlot.from_dictionary(slot.to_dictionary())
	_expect(restored.slot_id == "s1000-1", "slot_id round trip")
	_expect(restored.name == "Boar · 20 loops", "name round trip")
	_expect(restored.character_id == "chicken", "character_id round trip")
	_expect(restored.arena_id == "pit", "arena_id round trip")
	_expect(restored.loop_goal == 20, "loop_goal round trip")
	_expect(restored.created_at == 1700000000, "created_at round trip")
	_expect(restored.updated_at == 1700000500, "updated_at round trip")
	_expect(restored.status == SaveSlot.Status.IN_PROGRESS, "status round trip")
	_expect(restored.best_score == 9999, "best_score round trip")
	_expect(restored.history.size() == 1, "history 长度 round trip")
	if not restored.history.is_empty():
		_expect(restored.history[0].score == 9999, "history score round trip")
		_expect(restored.history[0].outcome == "cleared", "history outcome round trip")
		_expect(restored.history[0].scoring_version == RunResult.SCORING_VERSION, "history 带 scoring_version")
	_expect(restored.has_active_run(), "active_run round trip")
	if restored.active_run != null:
		_expect(restored.active_run.checkpoint_kind == RunCheckpoint.Kind.LOOP_COMPLETE, "checkpoint kind round trip")
		_expect(restored.active_run.shared_state.loop_index == 3, "shared loop_index round trip")
		_expect(restored.active_run.players.size() == 1, "checkpoint 玩家数 round trip")
		if not restored.active_run.players.is_empty():
			_expect(restored.active_run.players[0].profile_id == "profile-abc", "checkpoint profile_id round trip")

## status 名字是 JSON 契约的一部分，不能改。
func _case_status_names() -> void:
	_expect(SaveSlot.status_name(SaveSlot.Status.NEW) == "NEW", "NEW 名字")
	_expect(SaveSlot.status_name(SaveSlot.Status.IN_PROGRESS) == "IN_PROGRESS", "IN_PROGRESS 名字")
	_expect(SaveSlot.status_name(SaveSlot.Status.CLEARED) == "CLEARED", "CLEARED 名字")
	_expect(SaveSlot.status_name(SaveSlot.Status.FAILED) == "FAILED", "FAILED 名字")
	_expect(SaveSlot.status_from_name("CLEARED") == SaveSlot.Status.CLEARED, "CLEARED 反解")
	_expect(SaveSlot.status_from_name("bogus") == SaveSlot.Status.NEW, "未知 status 打回 NEW")

## 13) status 迁移：NEW -> IN_PROGRESS -> CLEARED / FAILED。
func _case_status_transitions() -> void:
	var slot: SaveSlot = SaveSlot.create("s1", "A", "boar", 0, "yard")
	_expect(slot.status == SaveSlot.Status.NEW, "新建档是 NEW")
	_expect(not slot.has_active_run(), "新建档没有 active_run")
	slot.begin_run()
	_expect(slot.status == SaveSlot.Status.IN_PROGRESS, "begin_run -> IN_PROGRESS")
	_expect(not slot.has_active_run(), "begin_run 会清掉旧 active_run")
	slot.active_run = RunCheckpoint.create(RunCheckpoint.Kind.RUN_START, _shared(), [_player()])
	slot.mark_in_progress()
	_expect(slot.status == SaveSlot.Status.IN_PROGRESS, "有 active_run -> IN_PROGRESS")
	slot.mark_cleared()
	_expect(slot.status == SaveSlot.Status.CLEARED, "mark_cleared -> CLEARED")
	slot.mark_failed()
	_expect(slot.status == SaveSlot.Status.FAILED, "mark_failed -> FAILED")

## 「没有 active_run」与「通关」绝不混成一个状态：IN_PROGRESS 一定意味着有 active_run。
func _case_status_without_active_run_is_not_in_progress() -> void:
	var raw: Dictionary = _make_slot().to_dictionary()
	raw["active_run"] = null
	raw["status"] = "IN_PROGRESS"
	var restored: SaveSlot = SaveSlot.from_dictionary(raw)
	_expect(restored.active_run == null, "伪造的 IN_PROGRESS 不该带回 active_run")
	_expect(restored.status == SaveSlot.Status.NEW, "没有 active_run 的 IN_PROGRESS 打回 NEW")

## 6) invalid data sanitization。
func _case_invalid_data_sanitized() -> void:
	var raw: Dictionary = {
		"slot_id": "s-bad",
		"name": "x",
		"character_id": "dragon",
		"arena_id": "moon",
		"loop_goal": -5,
		"best_score": -1,
		"status": "SOMETHING",
		"history": [
			"not-a-dict",
			{"score": 10, "outcome": "explode", "loop": -1, "kills": -2, "gold": -3, "time_sec": -4.0},
		],
		"active_run": "not-a-dict",
	}
	var restored: SaveSlot = SaveSlot.from_dictionary(raw)
	_expect(restored.character_id == SaveSlot.CHARACTER_BOAR, "非法 character 打回 boar")
	_expect(restored.arena_id == ARENA_CATALOG.DEFAULT_ID, "非法 arena 打回默认")
	_expect(restored.loop_goal == 0, "负 loop_goal 打回 0")
	_expect(restored.best_score == 0, "负 best_score 打回 0")
	_expect(restored.status == SaveSlot.Status.NEW, "未知 status 打回 NEW")
	_expect(restored.active_run == null, "非字典 active_run 忽略")
	_expect(restored.history.size() == 1, "非字典 history 行被丢弃")
	if restored.history.size() == 1:
		_expect(restored.history[0].outcome == "quit", "非法 outcome 打回 quit")
		_expect(restored.history[0].loop == 0, "负 loop 打回 0")
		_expect(restored.history[0].kills == 0, "负 kills 打回 0")
		_expect(restored.history[0].gold == 0, "负 gold 打回 0")
		_expect(restored.history[0].time_sec == 0.0, "负 time 打回 0")

## history 按 score 降序、超上限丢最低分，best_score 取见过的最大分（被裁掉的低分不影响）。
func _case_history_order_cap_and_best_score() -> void:
	var slot: SaveSlot = SaveSlot.create("s2", "B", "boar", 0, "yard")
	for score: int in [10, 500, 300, 70, 900, 100, 5, 40, 60, 80, 20, 1]:
		var entry: RunHistoryEntry = RunHistoryEntry.new()
		entry.score = score
		slot.insert_history(entry)
	_expect(slot.history.size() == SaveSlot.MAX_HISTORY, "history 上限 %d" % SaveSlot.MAX_HISTORY)
	_expect(slot.history[0].score == 900, "history 首行是最高分")
	_expect(slot.best_score == 900, "best_score 是见过的最大分")
	_expect(slot.history[slot.history.size() - 1].score == 10, "最低分被裁掉")
