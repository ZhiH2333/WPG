extends SceneTree

## 存档列表（RecordSelector 纵向 SaveRow）行为测试：一排一档、点击分流、删除二次确认、
## Home / Play / 列表三处 Continue 同源、以及 200% UI Scale / 540 宽不炸版。
##
## 锁定（§13-5/6/7/8/9/10/11/12）：
##   5)  一排 = 一个存档（纵向 VBox，不是 2/3 列卡片墙），每排有状态徽章 + 名字 + 主进度
##   6)  ACTIVE 点击 -> 详情浮层（12 个字段）-> Continue Run 发 resume_record
##   7)  CLEARED 点击 -> 「COMPLETED / This save has already been cleared. / Start over?」
##       START NEW RUN 发 selected_record（不是 resume_record）
##   8)  删除二次确认：Name/Progress/History + This cannot be undone.，默认焦点 CANCEL
##   9)  Home Continue 与 RecordSelector 状态一致
##   10) Play  Continue 与 RecordSelector 状态一致
##   11) 960 逻辑宽（UI Scale 200%）行内容不溢出
##   12) 540 逻辑宽不严重裁切，且 status / name / 主进度永不消失
##
## 跑法：godot --headless --path . --script res://tests/unit/save_selector_test.gd
## 通过输出 SAVE_SELECTOR_OK；失败逐条 SAVE_SELECTOR_FAIL 并返回非 0。
##
## 本测试会动 user://records.json（+ .tmp / .bak / .corrupt），跑完按快照逐字节还原。

const SELECTOR_SCENE: String = "res://ui/record_selector.tscn"
const MENU_SCENE: String = "res://ui/main_menu.tscn"
const SAVE_NAMES: Array[String] = [
	"records.json",
	"records.json.tmp",
	"records.json.bak",
	"records.json.corrupt",
]
const DETAIL_KEYS: Array[String] = [
	"SAVE NAME", "STATUS", "ARENA", "CHARACTER", "LOOP", "LEVEL",
	"XP", "GOLD", "SCORE", "LAST SAVED", "BEST SCORE", "LAST RESULT",
]

var _failures: PackedStringArray = PackedStringArray()
var _save_snapshot: Dictionary = {}
var _ids: Dictionary = {}
var _resumed: String = ""
var _selected: String = ""

func _initialize() -> void:
	_run_all.call_deferred()

func _run_all() -> void:
	await process_frame
	PlayerProfile.load_from_disk()
	GameSettings.load_from_disk()
	_snapshot_saves()
	_make_fixtures()

	var rs: RecordSelector = await _selector()
	if rs != null:
		await _case_one_row_per_save(rs)
		await _case_active_click_resume_flow(rs)
		await _case_cleared_click_restart_flow(rs)
		await _case_delete_double_confirm(rs)
		await _case_responsive(rs)

	await _case_home_and_play_share_status()

	_cleanup()
	if _failures.is_empty():
		print("SAVE_SELECTOR_OK")
		quit(0)
		return
	for failure: String in _failures:
		printerr("SAVE_SELECTOR_FAIL: %s" % failure)
	quit(1)

# ---- 5) 一排 = 一个存档 ----

func _case_one_row_per_save(rs: RecordSelector) -> void:
	## 列表容器必须是纵向 VBox：卡片墙（GridContainer columns=2/3）已经废弃。
	_expect(rs._rows is VBoxContainer, "列表容器是纵向 VBoxContainer（不是卡片墙 GridContainer）")
	var slots: Array[SaveSlot] = GameSaveStore.list_slots()
	var rows: Array[Node] = rs._rows.get_children()
	_expect(rows.size() == slots.size(), "排数 %d == 存档数 %d" % [rows.size(), slots.size()])
	var seen: Dictionary = {}
	for child: Node in rows:
		var button: Button = child as Button
		if not _expect(button != null, "每一排都是可点的 Button"):
			continue
		var id: String = SaveRow.slot_id_of(button)
		_expect(not id.is_empty(), "每排带 slot_id")
		_expect(not seen.has(id), "每排对应不同存档（%s 没重复）" % id)
		seen[id] = true
		_expect(_label(button, "Content/Badge/Label") != null and not _label(button, "Content/Badge/Label").text.is_empty(),
			"每排有状态徽章文字（不能只靠颜色）")
		_expect(_label(button, "Content/Identity/Name") != null and not _label(button, "Content/Identity/Name").text.is_empty(),
			"每排有存档名")
		var progress: Label = _label(button, "Content/Progress/P0")
		_expect(progress != null and progress.visible and not progress.text.is_empty(),
			"每排有可见的主进度行")

# ---- 6) ACTIVE 点击 -> continue 流程 ----

func _case_active_click_resume_flow(rs: RecordSelector) -> void:
	var id: String = _ids.get("active", "")
	if id.is_empty():
		return
	_resumed = ""
	_selected = ""
	rs._on_record_pressed(id)
	_expect(rs._is_detail_open(), "点进行中档先开详情浮层（不静默开新局）")
	_expect(not rs._is_completed_open(), "进行中档不弹已通关确认条")
	var title: Label = rs.get_node("DetailCenter/DetailPanel/Column/Title") as Label
	_expect(title != null and title.text == "Mid Run", "详情标题=存档名，实为 %s" % (title.text if title else "<null>"))
	var keys: Array[String] = _detail_keys(rs)
	_expect(keys.size() == DETAIL_KEYS.size(), "详情列出 12 个字段，实为 %d 个：%s" % [keys.size(), str(keys)])
	for i: int in DETAIL_KEYS.size():
		_expect(i < keys.size() and keys[i] == DETAIL_KEYS[i],
			"详情第 %d 个字段=%s，实为 %s" % [i + 1, DETAIL_KEYS[i], keys[i] if i < keys.size() else "<缺>"])
	_expect(rs._detail_yes.text == "Continue Run", "主按钮=Continue Run，实为 %s" % rs._detail_yes.text)

	rs._on_detail_yes_pressed()
	_expect(_resumed == id, "详情主按钮发 resume_record(%s)，实为 %s" % [id, _resumed])
	_expect(_selected == "", "进行中档不该发 selected_record（那是新开一局）")
	_expect(not rs._is_detail_open(), "点完详情浮层关掉")

# ---- 7) CLEARED 点击 -> 重开确认 ----

func _case_cleared_click_restart_flow(rs: RecordSelector) -> void:
	var id: String = _ids.get("cleared", "")
	if id.is_empty():
		return
	_resumed = ""
	_selected = ""
	var history_before: int = _history_count(id)
	rs._on_record_pressed(id)
	_expect(rs._is_completed_open(), "点通关档弹已通关确认条")
	_expect(not rs._is_detail_open(), "通关档不进普通详情浮层")
	var title: Label = rs.get_node("CompletedCenter/CompletedPanel/Column/Title") as Label
	var body: Label = rs.get_node("CompletedCenter/CompletedPanel/Column/Body") as Label
	var sub: Label = rs.get_node("CompletedCenter/CompletedPanel/Column/Sub") as Label
	_expect(title != null and title.text == "COMPLETED", "确认条标题=COMPLETED，实为 %s" % (title.text if title else "<null>"))
	_expect(body != null and body.text == "This save has already been cleared.", "确认条正文逐字对上，实为 %s" % (body.text if body else "<null>"))
	_expect(sub != null and sub.text == "Start over?", "确认条问句=Start over?，实为 %s" % (sub.text if sub else "<null>"))
	## Cancel 必须是第一个焦点（安全默认）。
	var focus: Array = rs._first_focus_target()
	_expect(focus.size() == 2 and focus[0] == rs._completed_no, "确认条默认焦点是 Cancel")

	rs._on_completed_yes_pressed()
	_expect(_selected == id, "START NEW RUN 发 selected_record(%s)，实为 %s" % [id, _selected])
	_expect(_resumed == "", "已通关确认不该发 resume_record")
	_expect(_history_count(id) == history_before, "历史一条不少（%d -> %d）" % [history_before, _history_count(id)])
	_expect(not rs._is_completed_open(), "点完确认条关掉")

# ---- 8) 删除二次确认 ----

func _case_delete_double_confirm(rs: RecordSelector) -> void:
	var keep: String = _ids.get("failed", "")
	var victim: String = _ids.get("new", "")
	if keep.is_empty() or victim.is_empty():
		return
	var before: int = GameSaveStore.list_slots().size()

	rs._on_delete_pressed(victim)
	_expect(rs._is_deleting(), "点 × 先出删除二次确认")
	_expect(rs._delete_body.text.contains("Name: "), "确认条写 Name，实为 %s" % rs._delete_body.text)
	_expect(rs._delete_body.text.contains("Progress: "), "确认条写 Progress")
	_expect(rs._delete_body.text.contains("History: "), "确认条写 History")
	var warning: Label = rs.get_node("DeleteCenter/DeletePanel/Column/Warning") as Label
	_expect(warning != null and warning.text == "This cannot be undone.", "确认条写 This cannot be undone.")
	var focus: Array = rs._first_focus_target()
	_expect(focus.size() == 2 and focus[0] == rs._delete_cancel and focus[1] == rs._delete_confirm,
		"删除默认焦点是 CANCEL，不是 DELETE")

	rs._on_delete_no_pressed()
	_expect(not rs._is_deleting(), "取消后确认条关掉")
	_expect(GameSaveStore.list_slots().size() == before, "取消不删档（%d -> %d）" % [before, GameSaveStore.list_slots().size()])
	_expect(SaveUiProjection.load_for(victim) != null, "取消后档还在")

	rs._on_delete_pressed(victim)
	_expect(rs._is_deleting(), "二次确认能再开")
	rs._on_delete_yes_pressed()
	_expect(GameSaveStore.list_slots().size() == before - 1, "确认才删（%d -> %d）" % [before, GameSaveStore.list_slots().size()])
	_expect(SaveUiProjection.load_for(victim) == null, "被删档没了")
	_expect(SaveUiProjection.load_for(keep) != null, "别的档不受影响")

# ---- 9/10) Home / Play / RecordSelector 状态同源 ----

func _case_home_and_play_share_status() -> void:
	var cont: SaveUiProjection = SaveUiProjection.load_continue()
	if cont == null:
		_failures.append("至少要有一个存档")
		return
	var menu: MainMenu = await _menu()
	if menu == null:
		return
	_expect(menu.get_continue_projection() != null, "Home 也有 Continue 投影")
	_expect(menu.get_continue_projection().slot_id == cont.slot_id, "Home 的 Continue 与 SaveUiProjection 同一档")
	_expect(menu._continue_button.visible, "有存档时 Home 的 Continue 可见")
	_expect(menu._continue_title.text == cont.rail_title(), "Home 标题=%s，实为 %s" % [cont.rail_title(), menu._continue_title.text])
	_expect(menu._continue_caption.text == cont.rail_caption(), "Home 指标同源，实为 %s" % menu._continue_caption.text)
	## §6：第二行只给简单描述，不能把 Loop / Score / Best 铺在这里。
	_expect(not _has_digit(menu._continue_caption.text), "Home 指标不带具体数字，实为 %s" % menu._continue_caption.text)

	menu._play_page.open()
	for _i: int in 4:
		await process_frame
	_expect(menu._play_page._continue_button.visible, "有存档时 Play 的 Continue 可见")
	_expect(menu._play_page._continue_title.text == cont.rail_title(), "Play 标题=%s，实为 %s" % [cont.rail_title(), menu._play_page._continue_title.text])
	_expect(menu._play_page._continue_caption.text == cont.rail_caption(), "Play 指标同源，实为 %s" % menu._play_page._continue_caption.text)
	_expect(not _has_digit(menu._play_page._continue_caption.text), "Play 指标不带具体数字，实为 %s" % menu._play_page._continue_caption.text)
	menu._play_page.close()

	## 列表里同一档那一排的状态文字必须和 Continue 完全一致。
	var rs: RecordSelector = await _selector()
	if rs != null:
		var button: Button = _row_for(rs, cont.slot_id)
		_expect(button != null, "列表里能找到 Continue 对应的那一排")
		if button != null:
			var badge: Label = _label(button, "Content/Badge/Label")
			_expect(badge != null and badge.text == cont.status_label_text(),
				"列表状态文字=%s，实为 %s" % [cont.status_label_text(), badge.text if badge else "<null>"])
			_expect(SaveRow.status_of(button) == cont.status, "列表状态元数据同源")

# ---- 11/12) 响应式 ----

func _case_responsive(rs: RecordSelector) -> void:
	for viewport_width: float in [1920.0, 1140.0, 960.0, 540.0]:
		rs.sync_content_width_for(viewport_width)
		await process_frame
		var row_width: float = rs._row_width()
		## 行内容必须装得下：Content 左边 16、右边 56（给行尾的 × 让位）。
		var budget: float = row_width - 72.0
		_expect(budget > 0.0, "宽 %.0f 下行宽 %.0f 为正" % [viewport_width, row_width])
		for child: Node in rs._rows.get_children():
			var button: Button = child as Button
			if button == null:
				continue
			var content: Control = button.get_node_or_null("Content") as Control
			if content == null:
				_failures.append("宽 %.0f：行里没有 Content" % viewport_width)
				continue
			var needed: float = content.get_combined_minimum_size().x
			_expect(needed <= budget + 0.5,
				"宽 %.0f：行内容最小 %.0f <= 可用 %.0f（否则横向溢出被裁）" % [viewport_width, needed, budget])
			## 状态 / 存档名 / 主进度永远在（§11 硬要求）。
			var badge: Label = _label(button, "Content/Badge/Label")
			var name_label: Label = _label(button, "Content/Identity/Name")
			var progress: Label = _label(button, "Content/Progress/P0")
			_expect(badge != null and badge.visible and not badge.text.is_empty(),
				"宽 %.0f：状态徽章可见" % viewport_width)
			_expect(name_label != null and name_label.visible and not name_label.text.is_empty(),
				"宽 %.0f：存档名可见" % viewport_width)
			_expect(progress != null and progress.visible and not progress.text.is_empty(),
				"宽 %.0f：主进度可见" % viewport_width)

# ---- 工具 ----

func _selector() -> RecordSelector:
	var scene: PackedScene = load(SELECTOR_SCENE)
	if scene == null:
		_failures.append("record_selector.tscn 可加载")
		return null
	var rs: RecordSelector = scene.instantiate() as RecordSelector
	if rs == null:
		_failures.append("RecordSelector 可实例化")
		return null
	root.add_child(rs)
	rs.resume_record.connect(_on_resume)
	rs.selected_record.connect(_on_selected)
	rs.open()
	for _i: int in 6:
		await process_frame
	return rs

func _menu() -> MainMenu:
	var scene: PackedScene = load(MENU_SCENE)
	if scene == null:
		_failures.append("main_menu.tscn 可加载")
		return null
	var menu: MainMenu = scene.instantiate() as MainMenu
	root.add_child(menu)
	for _i: int in 8:
		await process_frame
	return menu

func _on_resume(id: String) -> void:
	_resumed = id

func _on_selected(id: String) -> void:
	_selected = id

func _row_for(rs: RecordSelector, slot_id: String) -> Button:
	for child: Node in rs._rows.get_children():
		var button: Button = child as Button
		if button != null and SaveRow.slot_id_of(button) == slot_id:
			return button
	return null

func _label(button: Node, path: String) -> Label:
	if button == null:
		return null
	return button.get_node_or_null(path) as Label

func _detail_keys(rs: RecordSelector) -> Array[String]:
	var keys: Array[String] = []
	var left: VBoxContainer = rs.get_node("DetailCenter/DetailPanel/Column/Grid/Left") as VBoxContainer
	var right: VBoxContainer = rs.get_node("DetailCenter/DetailPanel/Column/Grid/Right") as VBoxContainer
	if left == null or right == null:
		return keys
	for i: int in maxi(left.get_child_count(), right.get_child_count()):
		for box: VBoxContainer in [left, right]:
			if i >= box.get_child_count():
				continue
			var row: HBoxContainer = box.get_child(i) as HBoxContainer
			if row == null or row.get_child_count() == 0:
				continue
			var key: Label = row.get_child(0) as Label
			keys.append(key.text if key != null else "")
	return keys

func _history_count(slot_id: String) -> int:
	GameSaveStore.load_from_disk()
	var slot: SaveSlot = GameSaveStore.get_slot(slot_id)
	return slot.history.size() if slot != null else -1

func _expect(condition: bool, label: String) -> bool:
	if condition:
		return true
	_failures.append(label)
	return false

func _has_digit(text: String) -> bool:
	for i: int in text.length():
		var code: int = text.unicode_at(i)
		if code >= 48 and code <= 57:
			return true
	return false

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
