extends SceneTree

## Save UI 投影（SaveUiProjection）语义测试：四种状态各长什么样、状态**不能只靠颜色**。
##
## 锁定（§13-1/2/3/4 + §3）：
##   1) IN_PROGRESS 展示：Loop 8 / 20 · Level · XP · Gold · Score，标题 CONTINUE
##   2) CLEARED     展示：20 / 20 loops · Best Score，标题 COMPLETED，时间前缀 Completed
##   3) FAILED      展示：Failed at loop N · Best Score，标题 RETRY，时间前缀 Failed
##   4) NEW         展示：Not started，标题 NEW SAVE
##   + 状态必须有**文字**（STATUS_TEXT）且四者互不相同，颜色只是辅助（色觉安全）
##   + 分数只能来自 RunResult.compute_score，界面不许自己发明公式
##   + Continue 按钮第二行只有像 SOLO「New run」那样的简单描述，不放 Loop / Score / Best 数字
##
## 跑法：godot --headless --path . --script res://tests/unit/save_status_projection_test.gd
## 通过输出 SAVE_STATUS_OK；失败逐条 SAVE_STATUS_FAIL 并返回非 0。
##
## 本测试会动 user://records.json（+ .tmp / .bak / .corrupt），跑完按快照逐字节还原。

## Home / Play 的 Continue 按钮第二行只能是像 SOLO「New run」那样的一句话。
const SIMPLE_CAPTIONS: Array[String] = ["New run", "Resume run", "Start over", "Try again"]

const SAVE_NAMES: Array[String] = [
	"records.json",
	"records.json.tmp",
	"records.json.bak",
	"records.json.corrupt",
]

var _failures: PackedStringArray = PackedStringArray()
var _save_snapshot: Dictionary = {}
var _ids: Dictionary = {}

func _initialize() -> void:
	_run_all.call_deferred()

func _run_all() -> void:
	await process_frame
	PlayerProfile.load_from_disk()
	GameSettings.load_from_disk()
	_snapshot_saves()
	_make_fixtures()

	_case_new_display()
	_case_in_progress_display()
	_case_cleared_display()
	_case_failed_display()
	_case_status_text_beats_color()
	_case_score_comes_from_run_result()
	_case_rail_caption_is_simple()

	_cleanup()
	if _failures.is_empty():
		print("SAVE_STATUS_OK")
		quit(0)
		return
	for failure: String in _failures:
		printerr("SAVE_STATUS_FAIL: %s" % failure)
	quit(1)

# ---- 1) NEW ----

func _case_new_display() -> void:
	var row: SaveUiProjection = _proj("new")
	if row == null:
		return
	_expect(row.status == "NEW", "NEW 档 status=NEW，实为 %s" % row.status)
	_expect(row.status_label_text() == "NEW", "NEW 档状态文字=NEW，实为 %s" % row.status_label_text())
	_expect(row.rail_title() == "NEW SAVE", "NEW 档标题=NEW SAVE，实为 %s" % row.rail_title())
	_expect(not row.has_active_run, "NEW 档没有 active_run")
	var lines: PackedStringArray = row.progress_lines()
	_expect(lines.size() >= 1 and lines[0] == "Not started", "NEW 档主进度=Not started，实为 %s" % _at(lines, 0))
	_expect(row.time_label().begins_with("Created "), "NEW 档时间前缀=Created，实为 %s" % row.time_label())

# ---- 2) IN_PROGRESS ----

func _case_in_progress_display() -> void:
	var row: SaveUiProjection = _proj("active")
	if row == null:
		return
	_expect(row.status == "IN_PROGRESS", "进行中档 status=IN_PROGRESS，实为 %s" % row.status)
	_expect(row.status_label_text() == "IN PROGRESS", "进行中档状态文字=IN PROGRESS，实为 %s" % row.status_label_text())
	_expect(row.rail_title() == "CONTINUE", "进行中档标题=CONTINUE，实为 %s" % row.rail_title())
	_expect(row.has_active_run, "进行中档有 active_run")
	var lines: PackedStringArray = row.progress_lines()
	_expect(_at(lines, 0) == "Loop 8 / 20", "进行中主进度=Loop 8 / 20，实为 %s" % _at(lines, 0))
	_expect(_at(lines, 1) == "Level 6  ·  XP 18 / 105", "进行中第二行=%s" % _at(lines, 1))
	_expect(_at(lines, 2) == "Gold 43", "进行中第三行=Gold 43，实为 %s" % _at(lines, 2))
	_expect(_at(lines, 3) == "Score 9,298", "进行中第四行=Score 9,298，实为 %s" % _at(lines, 3))
	_expect(row.loop_index == 8 and row.loop_goal == 20, "loop 8 / goal 20，实为 %d / %d" % [row.loop_index, row.loop_goal])
	_expect(row.level == 6 and row.xp == 18 and row.xp_to_next == 105, "level/xp/xp_to_next = 6/18/105，实为 %d/%d/%d" % [row.level, row.xp, row.xp_to_next])
	_expect(row.gold == 43, "gold=43，实为 %d" % row.gold)
	_expect(row.time_label().begins_with("Updated "), "进行中时间前缀=Updated，实为 %s" % row.time_label())
	_expect(row.rail_caption() == "Resume run", "Home 指标=Resume run，实为 %s" % row.rail_caption())
	_expect(not _has_digit(row.rail_caption()), "Home 指标不带具体数字，实为 %s" % row.rail_caption())

# ---- 3) CLEARED ----

func _case_cleared_display() -> void:
	var row: SaveUiProjection = _proj("cleared")
	if row == null:
		return
	_expect(row.status == "CLEARED", "通关档 status=CLEARED，实为 %s" % row.status)
	_expect(row.status_label_text() == "COMPLETED", "通关档状态文字=COMPLETED（不是 CLEARED 这种内部名），实为 %s" % row.status_label_text())
	_expect(row.rail_title() == "COMPLETED", "通关档标题=COMPLETED，实为 %s" % row.rail_title())
	_expect(not row.has_active_run, "通关档没有 active_run")
	var lines: PackedStringArray = row.progress_lines()
	_expect(_at(lines, 0) == "20 / 20 loops", "通关主进度=20 / 20 loops，实为 %s" % _at(lines, 0))
	_expect(_at(lines, 1) == "Best Score 31,240", "通关第二行=Best Score 31,240，实为 %s" % _at(lines, 1))
	_expect(row.time_label().begins_with("Completed "), "通关时间前缀=Completed，实为 %s" % row.time_label())
	_expect(row.rail_caption() == "Start over", "Home 指标=Start over，实为 %s" % row.rail_caption())
	_expect(not _has_digit(row.rail_caption()), "Home 指标不带具体数字，实为 %s" % row.rail_caption())
	_expect(row.best_score == 31240, "best_score=31240，实为 %d" % row.best_score)

# ---- 4) FAILED ----

func _case_failed_display() -> void:
	var row: SaveUiProjection = _proj("failed")
	if row == null:
		return
	_expect(row.status == "FAILED", "失败档 status=FAILED，实为 %s" % row.status)
	_expect(row.status_label_text() == "FAILED", "失败档状态文字=FAILED，实为 %s" % row.status_label_text())
	_expect(row.rail_title() == "RETRY", "失败档标题=RETRY，实为 %s" % row.rail_title())
	_expect(not row.has_active_run, "失败档没有 active_run")
	var lines: PackedStringArray = row.progress_lines()
	_expect(_at(lines, 0) == "Failed at loop 7", "失败主进度=Failed at loop 7，实为 %s" % _at(lines, 0))
	_expect(_at(lines, 1).begins_with("Best Score "), "失败第二行是 Best Score，实为 %s" % _at(lines, 1))
	_expect(row.time_label().begins_with("Failed "), "失败时间前缀=Failed，实为 %s" % row.time_label())

# ---- 状态不能只靠颜色（§3）----

func _case_status_text_beats_color() -> void:
	var statuses: Array[String] = [
		SaveUiProjection.STATUS_NEW,
		SaveUiProjection.STATUS_IN_PROGRESS,
		SaveUiProjection.STATUS_CLEARED,
		SaveUiProjection.STATUS_FAILED,
	]
	var texts: Dictionary = {}
	var colors: Dictionary = {}
	for status: String in statuses:
		var text: String = SaveUiProjection.status_label(status)
		_expect(not text.is_empty(), "%s 有状态文字" % status)
		_expect(texts.values().find(text) == -1, "状态文字 %s 不与别的状态重复" % text)
		texts[status] = text
		var color: Color = SaveRow.status_color(status)
		_expect(colors.values().find(color) == -1, "状态色 %s 不与别的状态重复" % status)
		colors[status] = color
	## 四种状态的**文字**必须两两不同：把颜色全去掉也分得清。
	_expect(texts.size() == statuses.size(), "四种状态各有自己的文字")

# ---- 分数只能来自 RunResult（唯一算法真源）----

func _case_score_comes_from_run_result() -> void:
	var active: SaveUiProjection = _proj("active")
	if active != null:
		var want: int = RunResult.compute_score(active.loop_index, active.kills, active.gold, active.elapsed_sec, RunResult.OUTCOME_QUIT)
		_expect(active.score == want, "进行中分数走 compute_score：%d == %d" % [active.score, want])
	var cleared: SaveUiProjection = _proj("cleared")
	if cleared != null:
		_expect(cleared.score == 31240, "通关分数来自落盘 result，实为 %d" % cleared.score)
		_expect(cleared.last_result_label() == "CLEARED", "通关最近结果=CLEARED，实为 %s" % cleared.last_result_label())

# ---- 工具 ----

func _proj(key: String) -> SaveUiProjection:
	if not _ids.has(key):
		_failures.append("缺测试档位 %s" % key)
		return null
	var row: SaveUiProjection = SaveUiProjection.load_for(_ids[key])
	if row == null:
		_failures.append("档位 %s 的投影建不出来" % key)
	return row

func _at(lines: PackedStringArray, index: int) -> String:
	if index < 0 or index >= lines.size():
		return "<缺行>"
	return lines[index]

## Home / Play 的 Continue 按钮第二行只能是像 SOLO「New run」那样的一句话：
## 一个数字都不许有，也不许把 Loop / Score / Best 铺在这里（具体进度在列表与详情里看）。
func _case_rail_caption_is_simple() -> void:
	for key: String in ["new", "active", "cleared", "failed"]:
		var row: SaveUiProjection = _proj(key)
		if row == null:
			continue
		var caption: String = row.rail_caption()
		_expect(SIMPLE_CAPTIONS.has(caption),
			"%s 的 Continue 第二行是简单描述，实为 %s" % [key, caption])
		_expect(not _has_digit(caption),
			"%s 的 Continue 第二行不带数字，实为 %s" % [key, caption])
		for word: String in ["Loop", "Score", "Best"]:
			_expect(not caption.contains(word),
				"%s 的 Continue 第二行不提 %s，实为 %s" % [key, word, caption])

func _has_digit(text: String) -> bool:
	for i: int in text.length():
		var code: int = text.unicode_at(i)
		if code >= 48 and code <= 57:
			return true
	return false

func _expect(condition: bool, label: String) -> void:
	if condition:
		return
	_failures.append(label)

# ---- 档位夹具 ----

func _make_fixtures() -> void:
	GameSaveStore.load_from_disk()
	if GameSaveStore.list_slots().size() + 4 > GameSaveStore.MAX_SLOTS:
		_wipe_files()
		GameSaveStore.load_from_disk()
	_ids["new"] = _create("Fresh Save", "chicken", 20, "yard")
	_ids["active"] = _create("Mid Run", "boar", 20, "yard")
	_ids["cleared"] = _create("Yard Clear", "boar", 20, "yard")
	_ids["failed"] = _create("Dead Run", "chicken", 20, "pit")
	_commit_active()
	_finish_cleared()
	_finish_failed()

func _create(display_name: String, character_id: String, loop_goal: int, arena_id: String) -> String:
	var slot: SaveSlot = GameSaveStore.create_slot(display_name, character_id, loop_goal, arena_id)
	if slot == null:
		_failures.append("建不出测试档位 %s" % display_name)
		return ""
	return slot.slot_id

func _commit_active() -> void:
	var id: String = _ids.get("active", "")
	if id.is_empty():
		return
	var shared: SharedRunState = SharedRunState.make("run-active", id)
	shared.arena_id = "yard"
	shared.loop_index = 8
	shared.loop_goal = 20
	shared.elapsed_sec = 612.0
	var player: PlayerRunState = PlayerRunState.create("p1", "Player", SaveSlot.CHARACTER_BOAR, 1)
	player.level = 6
	player.xp = 18
	player.gold = 43
	player.kill_count = 120
	GameSaveStore.commit_checkpoint(id, RunCheckpoint.create(RunCheckpoint.Kind.LOOP_COMPLETE, shared, [player]))

func _finish_cleared() -> void:
	var id: String = _ids.get("cleared", "")
	if id.is_empty():
		return
	var result: RunResult = _result(id, RunResult.OUTCOME_CLEARED, 20, 400, 300, 3640.0, 18 * 60)
	result.score = RunResult.compute_score(20, 400, 300, 3640.0, RunResult.OUTCOME_CLEARED)
	GameSaveStore.mark_cleared(id, result)

func _finish_failed() -> void:
	var id: String = _ids.get("failed", "")
	if id.is_empty():
		return
	var result: RunResult = _result(id, RunResult.OUTCOME_DEAD, 7, 60, 80, 300.0, 60 * 60)
	result.score = RunResult.compute_score(7, 60, 80, 300.0, RunResult.OUTCOME_DEAD)
	GameSaveStore.mark_failed(id, result)

func _result(id: String, outcome: String, loop_index: int, kills: int, gold: int, time_sec: float, age_sec: int) -> RunResult:
	var result: RunResult = RunResult.new()
	result.run_id = "run-%s" % id
	result.save_slot_id = id
	result.outcome = outcome
	result.loop_index = loop_index
	result.kill_count = kills
	result.gold = gold
	result.elapsed_sec = time_sec
	result.timestamp = int(Time.get_unix_time_from_system()) - age_sec
	return result

# ---- 存档卫生 ----

func _cleanup() -> void:
	_restore_saves()

func _wipe_files() -> void:
	for name: String in SAVE_NAMES:
		var path: String = "user://%s" % name
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)

## 只把字节抄进内存，绝不删用户文件。
func _snapshot_saves() -> void:
	_save_snapshot.clear()
	for name: String in SAVE_NAMES:
		var path: String = "user://%s" % name
		_save_snapshot[name] = FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else null

func _restore_saves() -> void:
	for name: String in _save_snapshot:
		var path: String = "user://%s" % name
		var stored: Variant = _save_snapshot[name]
		if stored == null:
			if FileAccess.file_exists(path):
				DirAccess.remove_absolute(path)
			continue
		var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
		if file == null:
			continue
		file.store_string(str(stored))
		file.flush()
		file.close()
	_save_snapshot.clear()
	GameSaveStore.load_from_disk()
