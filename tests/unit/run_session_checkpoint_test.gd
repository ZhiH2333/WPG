extends SceneTree

## Part 1-B §7/§10/§11 检查点回归：RunSession 导出/恢复 × SaveSlot 生命周期。
##
## 锁定：
##   · 新建局 -> 提交 RUN_START checkpoint -> 另一个 session restore 后数据逐项一致
##   · resume 路径**绝不调用 restart()**（restart 会清掉 upgrade/loop/xp/level/gold/kills）
##   · restart() 只属于 START_NEW_RUN，新 run 不继承上一局的 runtime state
##   · PRE_EXIT 保留 active_run、状态仍是 IN_PROGRESS，可继续续
##   · CLEARED / FAILED 落盘重载后仍然正确，active_run 已清空
##   · history 只追加、不覆盖；best_score 只涨不跌
## 跑法：godot --headless --path . --script res://tests/unit/run_session_checkpoint_test.gd
## 通过输出 RUN_SESSION_CHECKPOINT_OK；失败逐条 RUN_SESSION_CHECKPOINT_FAIL 并返回非 0。
##
## 本测试会动 user://records.json（+ .tmp / .bak / .corrupt），跑完原样还原。

const UPGRADE_CATALOG: UpgradeCatalog = preload("res://data/upgrade_catalog.tres")

const FILE_NAMES: Array[String] = [
	"records.json",
	"records.json.tmp",
	"records.json.bak",
	"records.json.corrupt",
]

## 只为测试数 restart() 被调了几次；行为与 RunSession 完全一致。
class SpySession extends RunSession:
	var restart_count: int = 0

	func restart() -> void:
		restart_count += 1
		super.restart()

var _failures: PackedStringArray = PackedStringArray()
var _backup: Dictionary = {}

func _initialize() -> void:
	_backup = _snapshot()
	_clear()
	_run_all.call_deferred()

func _run_all() -> void:
	_case_new_run_writes_run_start_checkpoint()
	_case_checkpoint_to_restore_round_trip()
	_case_resume_does_not_call_restart()
	_case_new_run_does_not_inherit_old_runtime_state()
	_case_pre_exit_keeps_slot_resumable()
	_case_cleared_status_persists()
	_case_failed_status_persists()
	_case_history_appends_and_best_score_only_grows()
	_case_companions_round_trip()
	_restore(_backup)
	if _failures.is_empty():
		print("RUN_SESSION_CHECKPOINT_OK")
		quit(0)
		return
	for failure: String in _failures:
		printerr("RUN_SESSION_CHECKPOINT_FAIL: %s" % failure)
	quit(1)

# ---- 用例 ----

## 新开一局 -> 打成 RUN_START checkpoint -> 落盘 -> 重载能取回来。
func _case_new_run_writes_run_start_checkpoint() -> void:
	_clear()
	var slot: SaveSlot = GameSaveStore.create_slot("Loop A", "boar", 20, "yard")
	if slot == null:
		_failures.append("建档失败")
		return
	var session: SpySession = _make_session(true)
	session.set_save_slot_id(slot.slot_id)
	var checkpoint: RunCheckpoint = session.export_checkpoint(RunCheckpoint.Kind.RUN_START, slot.slot_id)
	_expect(checkpoint.checkpoint_kind == RunCheckpoint.Kind.RUN_START, "新局首帧是 RUN_START")
	_expect(not checkpoint.run_id.is_empty(), "checkpoint 带 run_id")
	_expect(checkpoint.shared_state != null and checkpoint.shared_state.save_slot_id == slot.slot_id, "checkpoint 记住档位")
	_expect(GameSaveStore.commit_checkpoint(slot.slot_id, checkpoint), "RUN_START 落盘成功")
	var reloaded: RunCheckpoint = GameSaveStore.load_active_checkpoint(slot.slot_id)
	_expect(reloaded != null, "重载能取回 active_run")
	if reloaded != null:
		_expect(reloaded.run_id == checkpoint.run_id, "重载后 run_id 一致")
		_expect(reloaded.shared_state.loop_index == 0, "新局 loop 从 0 开始")
		_expect(reloaded.checkpoint_kind == RunCheckpoint.Kind.RUN_START, "落盘的 kind 是 RUN_START")
	var stored: SaveSlot = _slot(slot.slot_id)
	_expect(stored != null and stored.status == SaveSlot.Status.IN_PROGRESS, "提交检查点后状态是 IN_PROGRESS")
	session.queue_free()

## 升级 / loop / gold / xp-level / kills / HP -> checkpoint -> 另一个 session restore -> 全部一致。
func _case_checkpoint_to_restore_round_trip() -> void:
	_clear()
	var slot: SaveSlot = GameSaveStore.create_slot("Loop B", "boar", 20, "yard")
	if slot == null:
		_failures.append("建档失败")
		return
	var session: SpySession = _make_session(true)
	session.set_save_slot_id(slot.slot_id)
	session.notify_phrase_loop()
	session.notify_phrase_loop()
	session.add_gold(137)
	session.add_xp(999)
	while session.has_pending_level():
		session.consume_pending_level()
	for i: int in 6:
		session.note_kill()
	var granted: Array[String] = _grant_some(session)
	var want_level: int = session.get_level()
	var want_xp: int = session.get_xp()
	## 本测试没有绑 Pawn，_sync_local_vitals 不会覆盖这里写的快照。
	session.get_local_player_state().hp = 42
	var checkpoint: RunCheckpoint = session.export_checkpoint(RunCheckpoint.Kind.LOOP_COMPLETE, slot.slot_id)
	_expect(GameSaveStore.commit_checkpoint(slot.slot_id, checkpoint), "LOOP_COMPLETE 落盘成功")
	session.queue_free()

	## 全新 session，只走 resume：bind profile -> restore_checkpoint（不 restart）。
	var resumed: SpySession = _make_session(false)
	resumed.set_save_slot_id(slot.slot_id)
	var loaded: RunCheckpoint = GameSaveStore.load_active_checkpoint(slot.slot_id)
	_expect(resumed.restore_checkpoint(loaded), "restore_checkpoint 成功")
	_expect(resumed.restart_count == 0, "restore 路径不应调用 restart")
	_expect(resumed.get_loop_index() == 2, "loop_index 恢复为 2，实为 %d" % resumed.get_loop_index())
	_expect(resumed.get_gold() == 137, "gold 恢复为 137，实为 %d" % resumed.get_gold())
	_expect(resumed.get_level() == want_level, "level 恢复为 %d，实为 %d" % [want_level, resumed.get_level()])
	_expect(resumed.get_xp() == want_xp, "xp 恢复为 %d，实为 %d" % [want_xp, resumed.get_xp()])
	_expect(resumed.get_kill_count() == 6, "kills 恢复为 6，实为 %d" % resumed.get_kill_count())
	for id: String in granted:
		_expect(resumed.has_upgrade(StringName(id)), "升级 %s 应保留" % id)
	_expect(resumed.get_owned_upgrade_ids().size() == granted.size(), "升级数量一致")
	var state: PlayerRunState = resumed.get_local_player_state()
	_expect(state.hp == 42 and state.max_hp == 100, "HP 快照恢复为 42/100，实为 %d/%d" % [state.hp, state.max_hp])
	_expect(state.alive, "玩家仍存活")
	_expect(resumed.get_save_slot_id() == slot.slot_id, "档位 id 恢复")
	_expect(resumed.is_playing(), "恢复后仍在 playing")
	resumed.queue_free()

## resume 绝不 restart：run_id 必须原样保留（restart 会换 run_id 并清空一切）。
func _case_resume_does_not_call_restart() -> void:
	_clear()
	var slot: SaveSlot = GameSaveStore.create_slot("Resume", "boar", 20, "yard")
	if slot == null:
		_failures.append("建档失败")
		return
	var session: SpySession = _make_session(true)
	session.set_save_slot_id(slot.slot_id)
	session.notify_phrase_loop()
	session.add_gold(55)
	var want_run_id: String = session.get_shared_state().run_id
	GameSaveStore.commit_checkpoint(slot.slot_id, session.export_checkpoint(RunCheckpoint.Kind.PLAYER_DECISION, slot.slot_id))
	session.queue_free()

	var resumed: SpySession = _make_session(false)
	resumed.restore_checkpoint(GameSaveStore.load_active_checkpoint(slot.slot_id))
	_expect(resumed.restart_count == 0, "RESUME_RUN 全程 restart 次数应为 0，实为 %d" % resumed.restart_count)
	_expect(resumed.get_shared_state().run_id == want_run_id, "resume 必须保留原 run_id")
	_expect(resumed.get_gold() == 55, "resume 保留 gold")
	_expect(resumed.get_loop_index() == 1, "resume 保留 loop")
	resumed.queue_free()

## restart() 只属于 START_NEW_RUN：新 run 不继承上一局任何 runtime state。
func _case_new_run_does_not_inherit_old_runtime_state() -> void:
	var session: SpySession = _make_session(true)
	session.notify_phrase_loop()
	session.notify_phrase_loop()
	session.add_gold(999)
	session.add_xp(500)
	session.note_kill()
	var granted: Array[String] = _grant_some(session)
	_expect(not granted.is_empty(), "至少要给出一个升级")
	var old_run_id: String = session.get_shared_state().run_id
	session.set_local_companions([{"id": "gunner", "weapon_index": 1}])

	session.restart()
	_expect(session.restart_count == 2, "restart 次数应为 2，实为 %d" % session.restart_count)
	_expect(session.get_shared_state().run_id != old_run_id, "新局换 run_id")
	_expect(session.get_loop_index() == 0, "新局 loop 归零")
	_expect(session.get_gold() == 0, "新局 gold 归零")
	_expect(session.get_level() == 1, "新局 level 归零")
	_expect(session.get_xp() == 0, "新局 xp 归零")
	_expect(session.get_kill_count() == 0, "新局 kills 归零")
	_expect(session.get_owned_upgrade_ids().is_empty(), "新局不继承升级")
	_expect(session.get_local_companions().is_empty(), "新局不继承跟班")
	_expect(session.get_local_player_state().hp == session.get_local_player_state().max_hp, "新局回满血")
	session.queue_free()

## 中途退出只写 PRE_EXIT：active_run 还在、状态仍 IN_PROGRESS，重载后能续。
func _case_pre_exit_keeps_slot_resumable() -> void:
	_clear()
	var slot: SaveSlot = GameSaveStore.create_slot("Quit", "boar", 20, "yard")
	if slot == null:
		_failures.append("建档失败")
		return
	var session: SpySession = _make_session(true)
	session.set_save_slot_id(slot.slot_id)
	session.notify_phrase_loop()
	session.add_gold(12)
	_expect(GameSaveStore.commit_checkpoint(slot.slot_id, session.export_checkpoint(RunCheckpoint.Kind.PRE_EXIT, slot.slot_id)), "PRE_EXIT 落盘")
	session.queue_free()

	var stored: SaveSlot = _slot(slot.slot_id)
	_expect(stored != null, "档位仍在")
	if stored == null:
		return
	_expect(stored.status == SaveSlot.Status.IN_PROGRESS, "退出后仍是 IN_PROGRESS，实为 %s" % SaveSlot.status_name(stored.status))
	_expect(stored.has_active_run(), "退出后 active_run 必须保留（否则没法续）")
	_expect(GameSaveStore.get_latest_active_slot() != null, "Continue 能找到最新 active 档")
	var resumed: SpySession = _make_session(false)
	_expect(resumed.restore_checkpoint(GameSaveStore.load_active_checkpoint(slot.slot_id)), "PRE_EXIT checkpoint 可续")
	_expect(resumed.restart_count == 0, "续跑不 restart")
	_expect(resumed.get_loop_index() == 1, "续跑保留 loop")
	_expect(resumed.get_gold() == 12, "续跑保留 gold")
	resumed.queue_free()

## 通关：CLEARED 落盘重载仍是 CLEARED，active_run 清空，history 有一条。
func _case_cleared_status_persists() -> void:
	_clear()
	var slot: SaveSlot = GameSaveStore.create_slot("Clear", "boar", 3, "yard")
	if slot == null:
		_failures.append("建档失败")
		return
	var session: SpySession = _make_session(true)
	session.set_save_slot_id(slot.slot_id)
	session.notify_phrase_loop()
	session.notify_phrase_loop()
	session.add_gold(60)
	session.note_kill()
	GameSaveStore.commit_checkpoint(slot.slot_id, session.export_checkpoint(RunCheckpoint.Kind.TERMINAL, slot.slot_id))
	var result: RunResult = session.export_result(slot.slot_id, RunResult.OUTCOME_CLEARED)
	_expect(GameSaveStore.mark_cleared(slot.slot_id, result), "mark_cleared 成功")
	session.queue_free()

	var stored: SaveSlot = _slot(slot.slot_id)
	_expect(stored != null, "通关后档位仍在")
	if stored == null:
		return
	_expect(stored.status == SaveSlot.Status.CLEARED, "通关后状态是 CLEARED，实为 %s" % SaveSlot.status_name(stored.status))
	_expect(not stored.has_active_run(), "通关后 active_run 必须清空")
	_expect(GameSaveStore.get_latest_active_slot() == null, "通关后不再有 active 档（Continue 不会误续）")
	_expect(stored.history.size() == 1, "history 有 1 条，实为 %d" % stored.history.size())
	if stored.history.size() == 1:
		var entry: RunHistoryEntry = stored.history[0]
		_expect(entry.outcome == RunResult.OUTCOME_CLEARED, "history 记 outcome=cleared")
		_expect(entry.loop == 2, "history 记 loop=2，实为 %d" % entry.loop)
		_expect(entry.gold == 60, "history 记 gold=60，实为 %d" % entry.gold)
	_expect(stored.best_score > 0, "best_score 有分数")

## 死亡：FAILED 落盘重载仍是 FAILED，active_run 清空。
func _case_failed_status_persists() -> void:
	_clear()
	var slot: SaveSlot = GameSaveStore.create_slot("Fail", "boar", 20, "yard")
	if slot == null:
		_failures.append("建档失败")
		return
	var session: SpySession = _make_session(true)
	session.set_save_slot_id(slot.slot_id)
	session.notify_phrase_loop()
	session.note_kill()
	GameSaveStore.commit_checkpoint(slot.slot_id, session.export_checkpoint(RunCheckpoint.Kind.TERMINAL, slot.slot_id))
	var result: RunResult = session.export_result(slot.slot_id, RunResult.OUTCOME_DEAD)
	_expect(GameSaveStore.mark_failed(slot.slot_id, result), "mark_failed 成功")
	session.queue_free()

	var stored: SaveSlot = _slot(slot.slot_id)
	_expect(stored != null, "失败后档位仍在")
	if stored == null:
		return
	_expect(stored.status == SaveSlot.Status.FAILED, "失败后状态是 FAILED，实为 %s" % SaveSlot.status_name(stored.status))
	_expect(not stored.has_active_run(), "失败后 active_run 必须清空")
	_expect(stored.history.size() == 1, "history 有 1 条")
	if stored.history.size() == 1:
		_expect(stored.history[0].outcome == RunResult.OUTCOME_DEAD, "history 记 outcome=dead")

## history 只追加：三局结果全都在；best_score 只取最高，不被低分覆盖。
func _case_history_appends_and_best_score_only_grows() -> void:
	_clear()
	var slot: SaveSlot = GameSaveStore.create_slot("History", "boar", 20, "yard")
	if slot == null:
		_failures.append("建档失败")
		return
	var session: SpySession = _make_session(true)
	session.set_save_slot_id(slot.slot_id)
	var low: RunResult = session.export_result(slot.slot_id, RunResult.OUTCOME_DEAD)
	low.score = 1000
	var high: RunResult = session.export_result(slot.slot_id, RunResult.OUTCOME_CLEARED)
	high.score = 9000
	var last: RunResult = session.export_result(slot.slot_id, RunResult.OUTCOME_QUIT)
	last.score = 500
	_expect(GameSaveStore.mark_failed(slot.slot_id, low), "第一局落盘")
	_expect(GameSaveStore.mark_cleared(slot.slot_id, high), "第二局落盘")
	_expect(GameSaveStore.append_result(slot.slot_id, last), "第三局只追加账本")
	session.queue_free()

	var stored: SaveSlot = _slot(slot.slot_id)
	if stored == null:
		_failures.append("history 档位丢失")
		return
	_expect(stored.history.size() == 3, "history 应有 3 条，实为 %d" % stored.history.size())
	_expect(stored.best_score == 9000, "best_score 应为 9000，实为 %d" % stored.best_score)
	_expect(stored.status == SaveSlot.Status.CLEARED, "最后一次终局是 CLEARED，实为 %s" % SaveSlot.status_name(stored.status))
	for i: int in stored.history.size():
		_expect(stored.history[i].scoring_version == RunResult.SCORING_VERSION, "第 %d 条 history 带 scoring_version" % i)

## 跟班清单进 checkpoint（只存 id + 武器槽），restore 后原样回来。
func _case_companions_round_trip() -> void:
	var session: SpySession = _make_session(true)
	session.set_local_companions([
		{"id": "gunner", "weapon_index": 1},
		{"id": "scout", "weapon_index": 0},
	])
	var checkpoint: RunCheckpoint = session.export_checkpoint(RunCheckpoint.Kind.SHOP_COMPLETE, "slot-x")
	session.queue_free()

	var resumed: SpySession = _make_session(false)
	_expect(resumed.restore_checkpoint(checkpoint), "restore 成功")
	var rows: Array[Dictionary] = resumed.get_local_companions()
	_expect(rows.size() == 2, "跟班恢复 2 只，实为 %d" % rows.size())
	if rows.size() == 2:
		_expect(str(rows[0].get("id", "")) == "gunner", "第一只 id 正确")
		_expect(int(rows[0].get("weapon_index", -1)) == 1, "第一只武器槽正确")
		_expect(str(rows[1].get("id", "")) == "scout", "第二只 id 正确")
	resumed.queue_free()

# ---- 工具 ----

func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures.append(message)

## 计数版：默认 restart 一次开局（= START_NEW_RUN），传 false 模拟纯 resume 路径。
func _make_session(counted_restart: bool) -> SpySession:
	var session: SpySession = SpySession.new()
	root.add_child(session)
	session.bind_local_profile("pf-checkpoint", "Tester", 1)
	session.bind_catalog(UPGRADE_CATALOG)
	if counted_restart:
		session.restart()
	return session

## 从目录里尽量多地发升级，返回真正拿到的 id。
func _grant_some(session: RunSession) -> Array[String]:
	var granted: Array[String] = []
	for def: UpgradeDef in UPGRADE_CATALOG.get_all():
		if session.try_grant(def.id):
			granted.append(String(def.id))
		if granted.size() >= 3:
			break
	return granted

func _slot(id: String) -> SaveSlot:
	GameSaveStore.load_from_disk()
	return GameSaveStore.get_slot(id)

func _clear() -> void:
	GameSaveStore.wipe_files()
	GameSaveStore.load_from_disk()

func _path(name: String) -> String:
	return "user://%s" % name

func _snapshot() -> Dictionary:
	var saved: Dictionary = {}
	for name: String in FILE_NAMES:
		if not FileAccess.file_exists(_path(name)):
			continue
		saved[name] = FileAccess.get_file_as_string(_path(name))
	return saved

func _restore(saved: Dictionary) -> void:
	for name: String in FILE_NAMES:
		var path: String = _path(name)
		if saved.has(name):
			var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
			if file != null:
				file.store_string(String(saved[name]))
				file.close()
			continue
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	GameSaveStore.load_from_disk()
