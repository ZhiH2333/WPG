extends SceneTree

## Part 1-C 真实 headless 端到端（§14）：
##   建档 -> 开局 -> 推进 -> checkpoint -> 退出
##   -> **重新打开主菜单** -> 存档显示 IN PROGRESS -> Continue / 点击 -> 详情 -> Continue Run
##   -> 恢复同一局（loop / gold / run_id 与退出前逐项一致）
##   -> 跑完一局 -> 返回 -> COMPLETED -> 确认 -> START NEW RUN
##   -> 新局开始、旧历史与 best_score 一条不少。
##
## 锁定（§14 / §15）：
##   · 退出再重开后，Home / 档位列表看到的状态确实来自磁盘上的 SaveSlot（不是内存残留）
##   · 点 Continue 发 resume_record，GameLaunch 拿到 RESUME_RUN + 同一个 slot id
##   · 恢复出来的 loop / gold / run_id 与退出前完全一致 = 「同一个存档继续」
##   · 通关档点开是已通关确认条，START NEW RUN 发 selected_record（START_NEW_RUN）
##   · START_NEW_RUN 换新 run_id，history 与 best_score 一条不动
##
## 跑法：godot --headless --path . --script res://tests/integration/save_lifecycle_e2e_test.gd
## 通过输出 SAVE_LIFECYCLE_OK；失败逐条 SAVE_LIFECYCLE_FAIL 并返回非 0。
##
## 本测试会动 user://records.json（+ .tmp / .bak / .corrupt），跑完按快照逐字节还原。
## 先把整份存档快照到 user://records.json.test_snapshot 再清场，保证「Home 的 Continue
## 指向哪一档」这件事完全由本测试决定（否则用户自己那档进行中的存档会抢走 Continue）；
## 快照文件落盘，万一测试进程被强杀，下次跑开头先按它还原，不会把用户存档留成空的。
##
## headless 下不能真的换场景，所以每次点击之后立刻掐掉 LoadingScreen 换场盖与
## MainMenu 的退场 tween（`_neutralize_leave`）；点到 GameLaunch 为止的**真实路由代码**全跑。

const SANDBOX_SCENE: String = "res://sandbox/combat_sandbox.tscn"
const MENU_SCENE: String = "res://ui/main_menu.tscn"
const SELECTOR_SCENE: String = "res://ui/record_selector.tscn"
const PROBE_NAME: String = "Lifecycle Probe"
const PROBE_CHARACTER: String = "boar"
const SNAPSHOT_PATH: String = "user://records.json.test_snapshot"
const SAVE_NAMES: Array[String] = [
	"records.json",
	"records.json.tmp",
	"records.json.bak",
	"records.json.corrupt",
]

var _failures: PackedStringArray = PackedStringArray()
var _save_snapshot: Dictionary = {}
var _probe_id: String = ""
var _prev_run_id: String = ""
var _resumed: String = ""
var _selected: String = ""

func _initialize() -> void:
	_run_all.call_deferred()

func _run_all() -> void:
	await process_frame
	PlayerProfile.load_from_disk()
	GameSettings.load_from_disk()
	_restore_leftover_snapshot()
	_snapshot_saves()
	_wipe_files()
	_probe_id = await _create_probe_via_editor()
	if _probe_id.is_empty():
		_failures.append("测试专用档位建不出来")
		_cleanup()
		printerr("SAVE_LIFECYCLE_FAIL: 测试专用档位建不出来")
		quit(1)
		return

	await _case_start_and_quit()
	await _case_reopen_menu_shows_in_progress()
	await _case_resume_same_run()
	await _case_completed_and_start_new_run()
	await _case_new_run_keeps_history()

	_cleanup()
	if _failures.is_empty():
		print("SAVE_LIFECYCLE_OK")
		quit(0)
		return
	for failure: String in _failures:
		printerr("SAVE_LIFECYCLE_FAIL: %s" % failure)
	quit(1)

# ---- 1) 开局 -> 推进 -> checkpoint -> 退出 ----

func _case_start_and_quit() -> void:
	_prepare_launch(GameLaunch.RunIntent.START_NEW_RUN)
	var sandbox: CombatSandbox = await _boot_sandbox()
	if sandbox == null:
		return
	var session: RunSession = sandbox._run_session
	_expect(session.get_loop_index() == 0, "新局 loop 从 0 开始")
	session.notify_phrase_loop()
	session.notify_phrase_loop()
	session.add_gold(150)
	for _i: int in 30:
		session.note_kill()
	_prev_run_id = session.get_shared_state().run_id
	_expect(not _prev_run_id.is_empty(), "新局有 run_id")
	sandbox._commit_checkpoint(RunCheckpoint.Kind.LOOP_COMPLETE)
	GameSaveStore.load_from_disk()
	var slot: SaveSlot = GameSaveStore.get_slot(_probe_id)
	_expect(slot != null, "checkpoint 落盘后档还在")
	if slot != null:
		_expect(slot.status == SaveSlot.Status.IN_PROGRESS, "退出前状态是 IN_PROGRESS，实为 %s" % SaveSlot.status_name(slot.status))
		_expect(slot.has_active_run(), "退出前 active_run 在")
		_expect(slot.active_run.shared_state.loop_index == 2, "checkpoint 记的 loop=2，实为 %d" % slot.active_run.shared_state.loop_index)
	sandbox.queue_free()
	await process_frame
	## 模拟「应用关掉又打开」：内存全丢，只信磁盘。
	GameSaveStore.load_from_disk()

# ---- 2) 重新打开主菜单：Home 显示 IN PROGRESS -> Continue -> 详情 -> Continue Run ----

func _case_reopen_menu_shows_in_progress() -> void:
	var menu: MainMenu = await _menu()
	if menu == null:
		return
	var cont: SaveUiProjection = menu.get_continue_projection()
	_expect(cont != null, "重开主菜单后 Continue 有档")
	if cont == null:
		menu.queue_free()
		await process_frame
		return
	_expect(cont.slot_id == _probe_id, "Continue 指向同一档，实为 %s" % cont.slot_id)
	_expect(cont.status == SaveUiProjection.STATUS_IN_PROGRESS, "状态=IN_PROGRESS，实为 %s" % cont.status)
	_expect(menu._continue_title.text == "CONTINUE", "Home 标题=CONTINUE，实为 %s" % menu._continue_title.text)
	## §6：第二行只给简单描述（跟 SOLO「New run」同款），具体 Loop / Score 不铺在这里。
	_expect(menu._continue_caption.text == "Resume run", "Home 指标=Resume run，实为 %s" % menu._continue_caption.text)
	_expect(not _has_digit(menu._continue_caption.text), "Home 指标不带具体数字，实为 %s" % menu._continue_caption.text)

	## §9：Home 的 Continue 对进行中档 = 直接续跑，不静默开新局。
	_capture_routes(menu)
	menu._on_continue_pressed()
	_expect(GameLaunch.take_run_intent() == GameLaunch.RunIntent.RESUME_RUN, "Home Continue → RESUME_RUN")
	_expect(GameLaunch.take_active_save_slot_id() == _probe_id, "Home Continue → 同一个 slot id")
	_neutralize_leave(menu)

	## §3/§4：档位列表里这一行写着 IN PROGRESS，点开是详情浮层，主按钮 Continue Run。
	var rs: RecordSelector = menu._record_selector
	rs.open()
	for _i: int in 6:
		await process_frame
	var button: Button = _row_for(rs, _probe_id)
	_expect(button != null, "列表里有这一档")
	if button != null:
		_expect(_badge_text(button) == "IN PROGRESS", "列表状态=IN PROGRESS，实为 %s" % _badge_text(button))

	_resumed = ""
	_selected = ""
	rs._on_record_pressed(_probe_id)
	_expect(rs._is_detail_open(), "点进行中档开详情浮层（不静默开新局）")
	if rs._is_detail_open():
		_expect(rs._detail_yes.text == "Continue Run", "主按钮=Continue Run，实为 %s" % rs._detail_yes.text)
		rs._on_detail_yes_pressed()
	_neutralize_leave(menu)
	_expect(_resumed == _probe_id, "发的是 resume_record(%s)，实为 %s" % [_probe_id, _resumed])
	_expect(_selected == "", "不该发 selected_record")
	_expect(GameLaunch.take_run_intent() == GameLaunch.RunIntent.RESUME_RUN, "详情 Continue Run → RESUME_RUN")
	_expect(GameLaunch.take_active_save_slot_id() == _probe_id, "详情 Continue Run → 同一个 slot id")

	menu.queue_free()
	await process_frame

# ---- 3) 续跑：进度与退出前逐项一致 ----

func _case_resume_same_run() -> void:
	var before: SaveSlot = _slot()
	var want_loop: int = -1
	var want_gold: int = -1
	var want_run_id: String = ""
	if before != null and before.active_run != null:
		want_loop = before.active_run.shared_state.loop_index
		var player: PlayerRunState = before.active_run.get_first_player()
		want_gold = player.gold if player != null else -1
		want_run_id = before.active_run.run_id

	_prepare_launch(GameLaunch.RunIntent.RESUME_RUN)
	var sandbox: CombatSandbox = await _boot_sandbox()
	if sandbox == null:
		return
	_expect(sandbox._resumed_from_checkpoint, "重启后真的走了续跑分支")
	_expect(sandbox._slot_id == _probe_id, "续跑挂同一档")
	var session: RunSession = sandbox._run_session
	_expect(session.get_loop_index() == want_loop, "loop 恢复为 %d，实为 %d" % [want_loop, session.get_loop_index()])
	_expect(session.get_gold() == want_gold, "gold 恢复为 %d，实为 %d" % [want_gold, session.get_gold()])
	_expect(session.get_shared_state().run_id == want_run_id, "run_id 不变 = 续的是同一个局")
	_prev_run_id = want_run_id
	sandbox.queue_free()
	await process_frame
	GameSaveStore.load_from_disk()

# ---- 4) 通关 -> 返回 -> COMPLETED -> 确认 -> START NEW RUN ----

func _case_completed_and_start_new_run() -> void:
	var history_before: int = _history_count()
	_clear_probe()
	var history_after_clear: int = _history_count()
	_expect(history_after_clear == history_before + 1, "通关后历史 +1（%d -> %d）" % [history_before, history_after_clear])
	var want_best: int = 0
	var cleared_before: SaveSlot = _slot()
	if cleared_before != null:
		want_best = cleared_before.best_score
	_expect(want_best > 0, "通关后 best_score > 0，实为 %d" % want_best)

	var menu: MainMenu = await _menu()
	if menu == null:
		return
	var cont: SaveUiProjection = menu.get_continue_projection()
	_expect(cont != null and cont.status == SaveUiProjection.STATUS_CLEARED, "通关后 Continue 状态=CLEARED，实为 %s" % (cont.status if cont else "<null>"))
	_expect(menu._continue_title.text == "COMPLETED", "Home 标题=COMPLETED，实为 %s" % menu._continue_title.text)
	_expect(menu._continue_caption.text == "Start over", "Home 指标=Start over，实为 %s" % menu._continue_caption.text)
	_expect(not _has_digit(menu._continue_caption.text), "Home 指标不带具体数字，实为 %s" % menu._continue_caption.text)

	var rs: RecordSelector = menu._record_selector
	_capture_routes(menu)

	## §5：Home 的 Continue 对通关档 = 档位列表 + 已通关确认条，绝不静默开新局。
	menu._on_continue_pressed()
	_expect(rs._is_completed_open(), "Home Continue → 已通关确认条")
	_expect(rs._completed_name.text == PROBE_NAME, "确认条写着存档名，实为 %s" % rs._completed_name.text)
	_neutralize_leave(menu)
	rs._on_completed_no_pressed()
	_expect(not rs._is_completed_open(), "CANCEL 收起确认条")

	## §3：列表里这一行还写着 COMPLETED（历史一条没丢）。
	rs.open()
	for _i: int in 6:
		await process_frame
	rs._refresh_list()
	var button: Button = _row_for(rs, _probe_id)
	_expect(button != null, "列表里还有这一档（历史没被清掉）")
	if button != null:
		_expect(_badge_text(button) == "COMPLETED", "列表状态=COMPLETED，实为 %s" % _badge_text(button))

	_resumed = ""
	_selected = ""
	rs._on_record_pressed(_probe_id)
	_expect(rs._is_completed_open(), "点通关档弹已通关确认条，不直接开新局")
	var body: Label = rs.get_node("CompletedCenter/CompletedPanel/Column/Body") as Label
	_expect(body != null and body.text == "This save has already been cleared.", "确认条正文逐字对上")
	var sub: Label = rs.get_node("CompletedCenter/CompletedPanel/Column/Sub") as Label
	_expect(sub != null and sub.text == "Start over?", "确认条追问 Start over?，实为 %s" % (sub.text if sub else "<null>"))
	rs._on_completed_yes_pressed()
	_neutralize_leave(menu)
	_expect(_selected == _probe_id, "START NEW RUN 发 selected_record(%s)，实为 %s" % [_probe_id, _selected])
	_expect(_resumed == "", "通关档不该发 resume_record")
	_expect(GameLaunch.take_run_intent() == GameLaunch.RunIntent.START_NEW_RUN, "START NEW RUN → START_NEW_RUN")
	_expect(GameLaunch.take_active_save_slot_id() == _probe_id, "START NEW RUN → 同一个 slot id")
	_expect(_history_count() == history_after_clear, "点 START NEW RUN 不动历史（%d 条）" % history_after_clear)
	var cleared: SaveSlot = _slot()
	_expect(cleared != null and cleared.best_score == want_best, "best_score %d 保留，实为 %s" % [want_best, str(cleared.best_score) if cleared else "<null>"])

	menu.queue_free()
	await process_frame

# ---- 5) 新局开始，run_id 换新 ----

func _case_new_run_keeps_history() -> void:
	var want_history: int = _history_count()
	var want_best: int = 0
	var slot: SaveSlot = _slot()
	if slot != null:
		want_best = slot.best_score

	_prepare_launch(GameLaunch.RunIntent.START_NEW_RUN)
	var sandbox: CombatSandbox = await _boot_sandbox()
	if sandbox == null:
		return
	_expect(not sandbox._resumed_from_checkpoint, "START_NEW_RUN 不该走续跑分支")
	var session: RunSession = sandbox._run_session
	var new_run_id: String = session.get_shared_state().run_id
	_expect(not new_run_id.is_empty(), "新局有 run_id")
	_expect(new_run_id != _prev_run_id, "新 run_id 与上一局不同（%s -> %s）" % [_prev_run_id, new_run_id])
	_expect(session.get_loop_index() == 0, "新局 loop 从 0 开始")
	## §5：START OVER 之后 active_run 重新建、状态立刻回到 IN PROGRESS，历史原样留着。
	GameSaveStore.load_from_disk()
	var fresh: SaveSlot = _slot()
	_expect(fresh != null and fresh.has_active_run(), "新局把 active_run 重新建起来")
	_expect(fresh != null and fresh.status == SaveSlot.Status.IN_PROGRESS, "状态回到 IN PROGRESS，实为 %s" % (SaveSlot.status_name(fresh.status) if fresh else "<null>"))
	_expect(fresh != null and fresh.history.size() == want_history, "通关历史留着（%d 条）" % want_history)
	sandbox.queue_free()
	await process_frame
	GameSaveStore.load_from_disk()
	_expect(_history_count() == want_history, "START_NEW_RUN 不动历史（%d 条）" % want_history)
	var after: SaveSlot = _slot()
	_expect(after != null and after.best_score == want_best, "best_score %d 仍然在，实为 %s" % [want_best, str(after.best_score) if after else "<null>"])

# ---- 工具 ----

func _expect(condition: bool, label: String) -> void:
	if condition:
		return
	_failures.append(label)

func _has_digit(text: String) -> bool:
	for i: int in text.length():
		var code: int = text.unicode_at(i)
		if code >= 48 and code <= 57:
			return true
	return false

## 自己挂两个信号桩，捕获「档位列表到底把哪个 id 发出去了」。
func _capture_routes(menu: MainMenu) -> void:
	var rs: RecordSelector = menu._record_selector
	if not rs.resume_record.is_connected(_on_resume_record):
		rs.resume_record.connect(_on_resume_record)
	if not rs.selected_record.is_connected(_on_selected_record):
		rs.selected_record.connect(_on_selected_record)

func _on_resume_record(id: String) -> void:
	_resumed = id

func _on_selected_record(id: String) -> void:
	_selected = id

## 点完之后立刻掐掉换场：LoadingScreen 盖 + MainMenu 退场 tween 都不许在 headless 里跑。
func _neutralize_leave(menu: MainMenu) -> void:
	if menu._music_fade_tween != null:
		menu._music_fade_tween.kill()
		menu._music_fade_tween = null
	var cover: CanvasLayer = LoadingScreen._find_active(self)
	if cover != null:
		cover.free()
	LoadingScreen._active = null
	GameLaunch.set_next_scene("")
	menu._leaving = false

func _prepare_launch(intent: GameLaunch.RunIntent) -> void:
	GameLaunch.set_mode(GameLaunch.Mode.SOLO)
	GameLaunch.set_net_role(GameLaunch.NetRole.OFFLINE)
	GameLaunch.set_net_play(GameLaunch.NetPlay.COOP)
	GameLaunch.set_local_seat(1)
	GameLaunch.set_arena_id("yard")
	GameLaunch.set_active_save_slot_id(_probe_id)
	GameLaunch.set_run_intent(intent)

func _boot_sandbox() -> CombatSandbox:
	var scene: PackedScene = load(SANDBOX_SCENE)
	if scene == null:
		_failures.append("combat_sandbox.tscn 可加载")
		return null
	var sandbox: CombatSandbox = scene.instantiate() as CombatSandbox
	if sandbox == null:
		_failures.append("CombatSandbox 可实例化")
		return null
	root.add_child(sandbox)
	for _i: int in 5:
		await process_frame
	return sandbox

func _menu() -> MainMenu:
	var scene: PackedScene = load(MENU_SCENE)
	if scene == null:
		_failures.append("main_menu.tscn 可加载")
		return null
	var menu: MainMenu = scene.instantiate() as MainMenu
	if menu == null:
		_failures.append("MainMenu 可实例化")
		return null
	root.add_child(menu)
	for _i: int in 8:
		await process_frame
	return menu

func _row_for(rs: RecordSelector, slot_id: String) -> Button:
	for child: Node in rs._rows.get_children():
		var button: Button = child as Button
		if button != null and SaveRow.slot_id_of(button) == slot_id:
			return button
	return null

func _badge_text(row: Button) -> String:
	var badge: Label = row.get_node_or_null("Content/Badge/Label") as Label
	return badge.text if badge != null else "<null>"

func _slot() -> SaveSlot:
	GameSaveStore.load_from_disk()
	return GameSaveStore.get_slot(_probe_id)

func _history_count() -> int:
	var slot: SaveSlot = _slot()
	return slot.history.size() if slot != null else -1

## 通关走的就是 sandbox 局末同一条写入口（GameSaveStore.mark_cleared）。
func _clear_probe() -> void:
	var slot: SaveSlot = _slot()
	if slot == null:
		_failures.append("通关前档还在")
		return
	var loop_index: int = 2
	var gold: int = 150
	var kills: int = 30
	var time_sec: float = 780.0
	var run_id: String = _prev_run_id
	if slot.active_run != null:
		loop_index = slot.active_run.shared_state.loop_index
		run_id = slot.active_run.run_id
		var player: PlayerRunState = slot.active_run.get_first_player()
		if player != null:
			gold = player.gold
			kills = player.kill_count
		time_sec = slot.active_run.shared_state.elapsed_sec
	var result: RunResult = RunResult.new()
	result.run_id = run_id
	result.save_slot_id = _probe_id
	result.outcome = RunResult.OUTCOME_CLEARED
	result.loop_index = loop_index
	result.kill_count = kills
	result.gold = gold
	result.elapsed_sec = time_sec
	result.timestamp = int(Time.get_unix_time_from_system())
	result.score = RunResult.compute_score(loop_index, kills, gold, time_sec, RunResult.OUTCOME_CLEARED)
	_expect(GameSaveStore.mark_cleared(_probe_id, result), "mark_cleared 写盘成功")
	GameSaveStore.load_from_disk()

## §8：建档走的是档位列表里那张真实表单（名字 / 角色 / 竞技场 / Loop Goal），
## 不是绕过去直接 GameSaveStore.create_slot —— 这一步就是 §14 的「建一个新的存档」。
func _create_probe_via_editor() -> String:
	var scene: PackedScene = load(SELECTOR_SCENE)
	if scene == null:
		_failures.append("record_selector.tscn 可加载")
		return ""
	var rs: RecordSelector = scene.instantiate() as RecordSelector
	if rs == null:
		_failures.append("RecordSelector 可实例化")
		return ""
	root.add_child(rs)
	rs.selected_record.connect(_on_selected_record)
	_resumed = ""
	_selected = ""
	rs.open()
	for _i: int in 6:
		await process_frame
	rs._on_new_pressed()
	_expect(rs._confirm_button.visible, "点 New Record 进建档表单")
	rs._name_edit.text = PROBE_NAME
	rs._select_character(RecordSelector.CHAR_BOAR)
	rs._select_arena("yard")
	rs._loop_slider.value = float(GameLaunch.SOLO_LOOP_GOAL)
	rs._on_confirm_pressed()
	_expect(_selected != "", "建档发出 selected_record")
	var created: String = _selected
	if created.is_empty():
		rs.queue_free()
		await process_frame
		return ""
	var slot: SaveSlot = GameSaveStore.get_slot(created)
	_expect(slot != null, "新建档落盘")
	if slot != null:
		_expect(slot.name == PROBE_NAME, "新建档名字=Lifecycle Probe，实为 %s" % slot.name)
		_expect(slot.character_id == PROBE_CHARACTER, "新建档角色=boar，实为 %s" % slot.character_id)
		_expect(slot.loop_goal == GameLaunch.SOLO_LOOP_GOAL, "新建档 Loop Goal=20，实为 %d" % slot.loop_goal)
		_expect(slot.status == SaveSlot.Status.NEW, "新建档状态=NEW，实为 %s" % SaveSlot.status_name(slot.status))
	rs.queue_free()
	await process_frame
	return created

func _wipe_files() -> void:
	for name: String in SAVE_NAMES:
		var path: String = "user://%s" % name
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	GameSaveStore.load_from_disk()

func _cleanup() -> void:
	if not _probe_id.is_empty():
		GameSaveStore.load_from_disk()
		GameSaveStore.delete_slot(_probe_id)
	_restore_saves()

func _snapshot_saves() -> void:
	_save_snapshot.clear()
	for name: String in SAVE_NAMES:
		var path: String = "user://%s" % name
		_save_snapshot[name] = FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else null
	var file: FileAccess = FileAccess.open(SNAPSHOT_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(_save_snapshot))
		file.flush()
		file.close()

## 上一趟测试被强杀在半路：快照文件还在 = 还原没做完，先把它还回去。
func _restore_leftover_snapshot() -> void:
	if not FileAccess.file_exists(SNAPSHOT_PATH):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SNAPSHOT_PATH))
	if parsed is Dictionary:
		_restore_snapshot_dict(parsed as Dictionary)
	DirAccess.remove_absolute(SNAPSHOT_PATH)

func _restore_saves() -> void:
	_restore_snapshot_dict(_save_snapshot)
	_save_snapshot.clear()
	if FileAccess.file_exists(SNAPSHOT_PATH):
		DirAccess.remove_absolute(SNAPSHOT_PATH)
	GameSaveStore.load_from_disk()

func _restore_snapshot_dict(snapshot: Dictionary) -> void:
	for name: Variant in snapshot:
		var path: String = "user://%s" % str(name)
		var stored: Variant = snapshot[name]
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
