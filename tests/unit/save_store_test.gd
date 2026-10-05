extends SceneTree

## GameSaveStore 回归：duplicate slot / 损坏回退 / 备份恢复 / 原子写失败 /
## status 迁移 / cleared·best_score·history 重载存活 / profile_id 保留 / peer_id 永不落盘。
## 跑法：godot --headless --path . --script res://tests/unit/save_store_test.gd
## 通过输出 SAVE_STORE_OK；失败逐条 SAVE_STORE_FAIL 并返回非 0。
##
## 本测试会动 user://records.json（+ .tmp / .bak / .corrupt），跑完原样还原。

const FILE_NAMES: Array[String] = [
	"records.json",
	"records.json.tmp",
	"records.json.bak",
	"records.json.corrupt",
]

var _failures: PackedStringArray = PackedStringArray()
var _backup: Dictionary = {}

func _initialize() -> void:
	_backup = _snapshot()
	_clear()
	_run_all.call_deferred()

func _run_all() -> void:
	_case_create_and_reload()
	_case_duplicate_slot_protection()
	_case_status_transitions_survive_reload()
	_case_cleared_state_survives_reload()
	_case_best_score_and_history_survive_reload()
	_case_checkpoint_round_trip_via_disk()
	_case_profile_id_preserved_and_peer_id_never_persisted()
	_case_corrupted_json_falls_back_to_backup()
	_case_backup_recovery_when_main_missing()
	_case_both_files_corrupt_returns_empty_with_evidence()
	_case_atomic_write_failure_keeps_main_file()
	_case_latest_slot_queries()
	_case_delete_and_rename()
	_restore(_backup)
	if _failures.is_empty():
		print("SAVE_STORE_OK")
		quit(0)
		return
	for failure: String in _failures:
		printerr("SAVE_STORE_FAIL: %s" % failure)
	quit(1)

# ---- 工具 ----

func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures.append(message)

func _path(name: String) -> String:
	return "user://%s" % name

## 重新从磁盘取档；取不到返回 null（调用方必须先判空）。
func _slot(id: String) -> SaveSlot:
	GameSaveStore.load_from_disk()
	return GameSaveStore.get_slot(id)

func _snapshot() -> Dictionary:
	var saved: Dictionary = {}
	for name: String in FILE_NAMES:
		if DirAccess.dir_exists_absolute(_path(name)):
			continue
		if FileAccess.file_exists(_path(name)):
			saved[name] = FileAccess.get_file_as_string(_path(name))
	return saved

func _clear() -> void:
	GameSaveStore.wipe_files()
	for name: String in FILE_NAMES:
		if DirAccess.dir_exists_absolute(_path(name)):
			DirAccess.remove_absolute(_path(name))

func _restore(saved: Dictionary) -> void:
	_clear()
	for name: String in saved:
		_write_raw(_path(name), str(saved[name]))

func _write_raw(path: String, text: String) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(text)
	file.flush()
	file.close()

func _checkpoint(loop_index: int, gold: int, profile_id: String) -> RunCheckpoint:
	var shared: SharedRunState = SharedRunState.make("run-test", "slot-x")
	shared.loop_index = loop_index
	shared.elapsed_sec = 12.5
	var player: PlayerRunState = PlayerRunState.create(profile_id, "Evan", "boar", 1)
	player.gold = gold
	player.level = 4
	player.xp = 3
	player.kill_count = 9
	player.add_upgrade("swift")
	player.add_upgrade("swift")
	var players: Array[PlayerRunState] = [player]
	return RunCheckpoint.create(RunCheckpoint.Kind.LOOP_COMPLETE, shared, players)

func _result(score: int, outcome: String) -> RunResult:
	var result: RunResult = RunResult.new()
	result.run_id = "run-test"
	result.outcome = outcome
	result.loop_index = 3
	result.kill_count = 21
	result.gold = 140
	result.elapsed_sec = 88.0
	result.score = score
	result.player_scores = {"pf-store": score}
	result.team_score = score
	result.timestamp = 1700000777
	return result

# ---- 用例 ----

func _case_create_and_reload() -> void:
	_clear()
	var slot: SaveSlot = GameSaveStore.create_slot("Alpha", "chicken", 20, "pit")
	_expect(slot != null, "能建档")
	if slot == null:
		return
	_expect(GameSaveStore.get_slot(slot.slot_id) != null, "按 id 找回档")
	_expect(GameSaveStore.list_slots().size() == 1, "list_slots 返回 1 个")
	GameSaveStore.load_from_disk()
	var reloaded: SaveSlot = GameSaveStore.get_slot(slot.slot_id)
	_expect(reloaded != null, "重载后档还在")
	if reloaded == null:
		return
	_expect(reloaded.name == "Alpha", "name 落盘")
	_expect(reloaded.character_id == "chicken", "character_id 落盘")
	_expect(reloaded.loop_goal == 20, "loop_goal 落盘")
	_expect(reloaded.arena_id == "pit", "arena_id 落盘")
	_expect(reloaded.status == SaveSlot.Status.NEW, "新档是 NEW")
	_expect(not reloaded.has_active_run(), "新档没有 active_run")

## 7) duplicate slot protection：满员返回 null，不删旧档腾位。
func _case_duplicate_slot_protection() -> void:
	_clear()
	var ids: Array[String] = []
	for i: int in GameSaveStore.max_slots():
		var slot: SaveSlot = GameSaveStore.create_slot("Slot %d" % i, "boar", 0, "yard")
		if slot == null:
			_failures.append("第 %d 个档就建不出来" % (i + 1))
			return
		ids.append(slot.slot_id)
	_expect(GameSaveStore.list_slots().size() == GameSaveStore.max_slots(), "填满 %d 个档" % GameSaveStore.max_slots())
	var overflow: SaveSlot = GameSaveStore.create_slot("Overflow", "boar", 0, "yard")
	_expect(overflow == null, "第 %d 个档被拒（满员返回 null）" % (GameSaveStore.max_slots() + 1))
	GameSaveStore.load_from_disk()
	_expect(GameSaveStore.list_slots().size() == GameSaveStore.max_slots(), "满员后槽数不变")
	_expect(GameSaveStore.get_slot(ids[0]) != null, "满员没有删旧档腾位")

## 13) save status transitions：落盘 -> 重载 -> 状态不变。
func _case_status_transitions_survive_reload() -> void:
	_clear()
	var slot: SaveSlot = GameSaveStore.create_slot("Progress", "boar", 5, "yard")
	if slot == null:
		_failures.append("建档失败")
		return
	var id: String = slot.slot_id
	GameSaveStore.commit_checkpoint(id, _checkpoint(2, 100, "pf-store"))
	var in_progress: SaveSlot = _slot(id)
	_expect(in_progress != null and in_progress.status == SaveSlot.Status.IN_PROGRESS, "commit 后是 IN_PROGRESS")
	_expect(in_progress != null and in_progress.has_active_run(), "commit 后有 active_run")
	GameSaveStore.mark_failed(id, _result(1000, "dead"))
	var failed: SaveSlot = _slot(id)
	_expect(failed != null and failed.status == SaveSlot.Status.FAILED, "mark_failed 后是 FAILED")
	_expect(failed != null and not failed.has_active_run(), "终局清掉 active_run")
	GameSaveStore.commit_checkpoint(id, _checkpoint(1, 10, "pf-store"))
	var restarted: SaveSlot = _slot(id)
	_expect(restarted != null and restarted.status == SaveSlot.Status.IN_PROGRESS, "终局之后还能重开一局")
	GameSaveStore.clear_active_run(id)
	var cleared: SaveSlot = _slot(id)
	_expect(cleared != null and not cleared.has_active_run(), "clear_active_run 生效")
	_expect(cleared != null and cleared.status != SaveSlot.Status.IN_PROGRESS, "没有 active_run 就不能是 IN_PROGRESS")
	GameSaveStore.mark_cleared(id, _result(5000, "cleared"))
	var done: SaveSlot = _slot(id)
	_expect(done != null and done.status == SaveSlot.Status.CLEARED, "mark_cleared 后是 CLEARED")
	_expect(done != null and done.history.size() == 2, "两次终局都进 history")
	_expect(done != null and not done.has_active_run(), "CLEARED 没有 active_run")

## 14) cleared state survives reload。
func _case_cleared_state_survives_reload() -> void:
	_clear()
	var slot: SaveSlot = GameSaveStore.create_slot("Cleared", "boar", 5, "yard")
	if slot == null:
		_failures.append("建档失败")
		return
	GameSaveStore.mark_cleared(slot.slot_id, _result(8000, "cleared"))
	for _i: int in 3:
		GameSaveStore.load_from_disk()
	var reloaded: SaveSlot = GameSaveStore.get_slot(slot.slot_id)
	_expect(reloaded != null and reloaded.status == SaveSlot.Status.CLEARED, "CLEARED 多次重载后仍在")
	_expect(reloaded != null and not reloaded.has_active_run(), "CLEARED 没有 active_run")

## 15 / 16) best_score 与 history 重载存活。
func _case_best_score_and_history_survive_reload() -> void:
	_clear()
	var slot: SaveSlot = GameSaveStore.create_slot("Scores", "boar", 0, "yard")
	if slot == null:
		_failures.append("建档失败")
		return
	GameSaveStore.append_result(slot.slot_id, _result(3000, "dead"))
	GameSaveStore.append_result(slot.slot_id, _result(9000, "cleared"))
	GameSaveStore.append_result(slot.slot_id, _result(1500, "quit"))
	GameSaveStore.load_from_disk()
	var reloaded: SaveSlot = GameSaveStore.get_slot(slot.slot_id)
	_expect(reloaded != null, "重载后档还在")
	if reloaded == null:
		return
	_expect(reloaded.best_score == 9000, "best_score 重载存活")
	_expect(reloaded.history.size() == 3, "history 条数重载存活")
	_expect(reloaded.history[0].score == 9000, "history 按 score 降序")
	_expect(reloaded.history[0].scoring_version == RunResult.SCORING_VERSION, "history 记住评分规则版本")
	GameRecords.load_from_disk()
	var record: GameRecord = GameRecords.get_record(slot.slot_id)
	_expect(record != null and record.best_score == 9000, "GameRecords 兼容投影读到同一个 best_score")
	_expect(record != null and record.history.size() == 3, "GameRecords 兼容投影读到同一份 history")

## checkpoint 保存 -> 进程内重新 load -> 数据完全恢复。
func _case_checkpoint_round_trip_via_disk() -> void:
	_clear()
	var slot: SaveSlot = GameSaveStore.create_slot("Resume", "boar", 20, "yard")
	if slot == null:
		_failures.append("建档失败")
		return
	var checkpoint: RunCheckpoint = _checkpoint(6, 455, "pf-resume")
	checkpoint.run_id = "run-resume-1"
	checkpoint.save_slot_id = slot.slot_id
	GameSaveStore.commit_checkpoint(slot.slot_id, checkpoint)
	GameSaveStore.load_from_disk()
	var restored: RunCheckpoint = GameSaveStore.load_active_checkpoint(slot.slot_id)
	_expect(restored != null, "重载后 active_run 还在")
	if restored == null:
		return
	_expect(restored.run_id == "run-resume-1", "run_id 恢复")
	_expect(restored.checkpoint_kind == RunCheckpoint.Kind.LOOP_COMPLETE, "checkpoint_kind 恢复")
	_expect(restored.shared_state != null and restored.shared_state.loop_index == 6, "loop 恢复")
	_expect(restored.shared_state != null and restored.shared_state.elapsed_sec == 12.5, "elapsed 恢复")
	_expect(restored.players.size() == 1, "玩家数恢复")
	if restored.players.is_empty():
		return
	var player: PlayerRunState = restored.players[0]
	_expect(player.profile_id == "pf-resume", "profile_id 恢复")
	_expect(player.gold == 455, "gold 恢复")
	_expect(player.level == 4, "level 恢复")
	_expect(player.xp == 3, "xp 恢复")
	_expect(player.kill_count == 9, "kills 恢复")
	_expect(player.owned_upgrade_ids.size() == 2, "升级清单恢复（保留重复项）")
	_expect(player.owned_upgrade_ids[0] == "swift" and player.owned_upgrade_ids[1] == "swift", "升级 id 内容恢复")
	var reloaded_slot: SaveSlot = _slot(slot.slot_id)
	_expect(reloaded_slot != null and reloaded_slot.status == SaveSlot.Status.IN_PROGRESS, "有 active_run 即 IN_PROGRESS")

## 11 / 12) profile_id 保留；peer_id 永不落盘。
func _case_profile_id_preserved_and_peer_id_never_persisted() -> void:
	_clear()
	var slot: SaveSlot = GameSaveStore.create_slot("Identity", "boar", 0, "yard")
	if slot == null:
		_failures.append("建档失败")
		return
	GameSaveStore.commit_checkpoint(slot.slot_id, _checkpoint(1, 0, "pf-keep-me"))
	GameSaveStore.load_from_disk()
	var text: String = FileAccess.get_file_as_string(GameSaveStore.PATH)
	_expect(text.contains("pf-keep-me"), "profile_id 落盘")
	_expect(not text.contains("peer_id"), "peer_id 不落盘")
	var restored: RunCheckpoint = GameSaveStore.load_active_checkpoint(slot.slot_id)
	_expect(restored != null and not restored.players.is_empty() and restored.players[0].profile_id == "pf-keep-me", "profile_id 往返保留")
	## 有人手工往 JSON 里塞 peer_id 也不能被采纳。
	_write_raw(GameSaveStore.PATH, JSON.stringify({
		"save_version": 2,
		"slots": [{
			"slot_id": "injected",
			"status": "IN_PROGRESS",
			"active_run": {
				"checkpoint_version": 1,
				"checkpoint_kind": "RUN_START",
				"shared_state": {},
				"players": [{"profile_id": "pf-injected", "peer_id": 777}],
			},
		}],
	}))
	GameSaveStore.load_from_disk()
	var injected: RunCheckpoint = GameSaveStore.load_active_checkpoint("injected")
	_expect(
		injected != null and not injected.players.is_empty() and injected.players[0].profile_id == "pf-injected",
		"注入的 profile_id 被读到"
	)
	GameSaveStore.save_to_disk()
	var rewritten: String = FileAccess.get_file_as_string(GameSaveStore.PATH)
	_expect(not rewritten.contains("peer_id"), "重新序列化后 peer_id 被丢弃")

## 8) 主文件损坏：隔离留证 + 回退到 backup。
func _case_corrupted_json_falls_back_to_backup() -> void:
	_clear()
	var alpha: SaveSlot = GameSaveStore.create_slot("Alpha", "boar", 0, "yard")
	if alpha == null:
		_failures.append("建档失败")
		return
	var alpha_id: String = alpha.slot_id
	GameSaveStore.save_to_disk()
	var beta: SaveSlot = GameSaveStore.create_slot("Beta", "chicken", 0, "yard")
	if beta == null:
		_failures.append("建档失败")
		return
	var beta_id: String = beta.slot_id
	## 第二次写盘把上一份（只有 Alpha）旋转成了 .bak。
	_expect(FileAccess.file_exists(GameSaveStore.BAK_PATH), "存在 backup")
	_write_raw(GameSaveStore.PATH, "{ 这不是合法 JSON ]]]")
	GameSaveStore.load_from_disk()
	_expect(GameSaveStore.get_slot(alpha_id) != null, "从 backup 恢复出 Alpha")
	_expect(GameSaveStore.get_slot(beta_id) == null, "backup 是上一份完好文件")
	_expect(FileAccess.file_exists(GameSaveStore.CORRUPT_PATH), "坏文件被隔离留证")
	_expect(FileAccess.get_file_as_string(GameSaveStore.CORRUPT_PATH).contains("不是合法 JSON"), "坏字节原样保留")
	_expect(not FileAccess.file_exists(GameSaveStore.PATH), "load 没有把坏 JSON 覆盖成空数据")
	_expect(GameSaveStore.get_diagnostics().size() > 0, "解析错误可诊断")

## 9) 主文件丢失（原子写旋转窗口崩溃）：用 backup 恢复。
func _case_backup_recovery_when_main_missing() -> void:
	_clear()
	GameSaveStore.create_slot("Alpha", "boar", 0, "yard")
	GameSaveStore.save_to_disk()
	GameSaveStore.create_slot("Beta", "chicken", 0, "yard")
	## 此时 .bak = 只有 Alpha 的上一份。
	_expect(FileAccess.file_exists(GameSaveStore.BAK_PATH), "制造失败前 backup 存在")
	DirAccess.remove_absolute(GameSaveStore.PATH)
	_expect(not FileAccess.file_exists(GameSaveStore.PATH), "主文件已删除")
	GameSaveStore.load_from_disk()
	_expect(GameSaveStore.list_slots().size() == 1, "主文件缺失时回退到 backup")
	_expect(GameSaveStore.list_slots()[0].name == "Alpha", "backup 内容正确")
	_expect(GameSaveStore.get_diagnostics().size() > 0, "回退可诊断")

## 两个都坏：安全返回空集合，且谁都不覆盖。
func _case_both_files_corrupt_returns_empty_with_evidence() -> void:
	_clear()
	_write_raw(GameSaveStore.PATH, "{主文件坏的")
	_write_raw(GameSaveStore.BAK_PATH, "{备份也是坏的")
	GameSaveStore.load_from_disk()
	_expect(GameSaveStore.list_slots().is_empty(), "两个都坏返回空集合")
	_expect(FileAccess.file_exists(GameSaveStore.CORRUPT_PATH), "主文件留证")
	_expect(FileAccess.get_file_as_string(GameSaveStore.CORRUPT_PATH) == "{主文件坏的", "留证内容未被改写")
	_expect(FileAccess.file_exists(GameSaveStore.BAK_PATH), "backup 也没被覆盖")
	_expect(FileAccess.get_file_as_string(GameSaveStore.BAK_PATH) == "{备份也是坏的", "backup 字节未被改写")
	var diagnostics: PackedStringArray = GameSaveStore.get_diagnostics()
	var mentioned: bool = false
	for line: String in diagnostics:
		if line.contains("均不可用"):
			mentioned = true
	_expect(mentioned, "两个文件都坏的诊断可读")

## 10) atomic write failure：tmp 写不进去时主文件保持原样。
func _case_atomic_write_failure_keeps_main_file() -> void:
	_clear()
	var slot: SaveSlot = GameSaveStore.create_slot("Atomic", "boar", 0, "yard")
	if slot == null:
		_failures.append("建档失败")
		return
	var id: String = slot.slot_id
	var before: String = FileAccess.get_file_as_string(GameSaveStore.PATH)
	_expect(not before.is_empty(), "主文件已存在")
	## 把 tmp 路径变成目录 -> FileAccess.open 必然失败。
	var made: Error = DirAccess.make_dir_absolute(GameSaveStore.TMP_PATH)
	_expect(made == OK, "能制造 tmp 写入失败（建目录）")
	var renamed: bool = GameSaveStore.rename_slot(id, "Renamed")
	_expect(not renamed, "写入失败时 rename_slot 报告失败")
	_expect(GameSaveStore.get_last_error().contains("临时文件"), "写入失败有可诊断原因")
	var after: String = FileAccess.get_file_as_string(GameSaveStore.PATH)
	_expect(before == after, "写入失败不得改动主文件")
	GameSaveStore.load_from_disk()
	var untouched: SaveSlot = GameSaveStore.get_slot(id)
	_expect(untouched != null and untouched.name == "Atomic", "写入失败后磁盘仍是旧数据")
	DirAccess.remove_absolute(GameSaveStore.TMP_PATH)
	_expect(GameSaveStore.rename_slot(id, "Renamed"), "恢复后写入成功")
	GameSaveStore.load_from_disk()
	_expect(GameSaveStore.get_slot(id).name == "Renamed", "恢复后改动落盘")

func _case_latest_slot_queries() -> void:
	_clear()
	var alpha: SaveSlot = GameSaveStore.create_slot("Alpha", "boar", 0, "yard")
	var beta: SaveSlot = GameSaveStore.create_slot("Beta", "boar", 0, "yard")
	if alpha == null or beta == null:
		_failures.append("建档失败")
		return
	GameSaveStore.load_from_disk()
	var a: SaveSlot = GameSaveStore.get_slot(alpha.slot_id)
	var b: SaveSlot = GameSaveStore.get_slot(beta.slot_id)
	if a == null or b == null:
		_failures.append("重载后档位丢失")
		return
	a.updated_at = 1000
	b.updated_at = 2000
	GameSaveStore.save_to_disk()
	var latest: SaveSlot = GameSaveStore.get_latest_updated_slot()
	_expect(latest != null and latest.slot_id == beta.slot_id, "get_latest_updated_slot 取最新更新的档")
	GameSaveStore.commit_checkpoint(alpha.slot_id, _checkpoint(1, 0, "pf-a"))
	GameSaveStore.load_from_disk()
	var active: SaveSlot = GameSaveStore.get_latest_active_slot()
	_expect(active != null and active.slot_id == alpha.slot_id, "get_latest_active_slot 取有 active_run 的档")
	_expect(GameSaveStore.load_active_checkpoint(beta.slot_id) == null, "没有 active_run 的档返回 null")
	_expect(GameSaveStore.get_latest_updated_slot() != null, "有档时 get_latest_updated_slot 非空")

func _case_delete_and_rename() -> void:
	_clear()
	var slot: SaveSlot = GameSaveStore.create_slot("Doomed", "boar", 0, "yard")
	if slot == null:
		_failures.append("建档失败")
		return
	var id: String = slot.slot_id
	_expect(GameSaveStore.rename_slot(id, "Renamed"), "rename 成功")
	_expect(not GameSaveStore.rename_slot(id, "   "), "空名字被拒")
	_expect(not GameSaveStore.rename_slot("missing", "X"), "重命名不存在的档返回 false")
	_expect(not GameSaveStore.delete_slot("missing"), "删除不存在的档返回 false")
	var renamed: SaveSlot = _slot(id)
	_expect(renamed != null and renamed.name == "Renamed", "重命名落盘")
	_expect(GameSaveStore.delete_slot(id), "删除成功")
	_expect(_slot(id) == null, "删除后档消失")
	GameSaveStore.load_from_disk()
	_expect(GameSaveStore.list_slots().is_empty(), "档位表为空")
