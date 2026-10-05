extends SceneTree

## Part 1-B 真实 headless 集成：START_NEW_RUN -> 推进一局 -> 提交 checkpoint ->
## 模拟进程结束 -> 从磁盘重载 -> RESUME_RUN -> 逐项核对运行时状态一致。
##
## 锁定（§5/§6/§7）：
##   · 落盘的 checkpoint 真的存在 user://records.json 里（不是只在内存）
##   · 重载后档位仍是 IN_PROGRESS、active_run 还在
##   · 续跑分支确实走了 restore（_resumed_from_checkpoint = true），run_id 不变 = 没调 restart()
##   · loop / gold / level / xp / kills / 升级 / 跟班 / HP / arena / loop_goal 全部对上
##   · 续跑**不**改写磁盘上原 checkpoint 的 kind / saved_at（不会伪装成 RUN_START）
##   · 中途退出只写 PRE_EXIT，不写 history，状态仍是 IN_PROGRESS
## 跑法：godot --headless --path . --script res://tests/integration/save_resume_integration_test.gd
## 通过输出 SAVE_RESUME_OK；失败逐条 SAVE_RESUME_FAIL 并返回非 0。
##
## 本测试会动 user://records.json（+ .tmp / .bak / .corrupt），跑完按快照逐字节还原；
## 全程只在**测试专用**档位上写，不碰用户已有的档。

const SANDBOX_SCENE: String = "res://sandbox/combat_sandbox.tscn"
const UPGRADE_CATALOG: UpgradeCatalog = preload("res://data/upgrade_catalog.tres")
const SAVE_NAMES: Array[String] = [
	"records.json",
	"records.json.tmp",
	"records.json.bak",
	"records.json.corrupt",
]

var _failures: PackedStringArray = PackedStringArray()
var _save_snapshot: Dictionary = {}
var _probe_id: String = ""
var _runs_played_before: int = 0

func _initialize() -> void:
	_run_all.call_deferred()

func _run_all() -> void:
	await process_frame
	PlayerProfile.load_from_disk()
	GameSettings.load_from_disk()
	_snapshot_saves()
	_runs_played_before = GameProgress.get_runs_played()
	_probe_id = _make_probe_slot()

	await _case_start_checkpoint_reload_resume()
	await _case_quit_stays_in_progress()

	_expect(GameProgress.get_runs_played() == _runs_played_before, "没到终局时 GameProgress.runs_played 不该变（§10）")
	_cleanup()
	if _failures.is_empty():
		print("SAVE_RESUME_OK")
		quit(0)
		return
	for failure: String in _failures:
		printerr("SAVE_RESUME_FAIL: %s" % failure)
	quit(1)

# ---- 用例 ----

## START -> 推进 -> checkpoint -> 进程结束 -> 重载 -> RESUME -> 逐项一致。
func _case_start_checkpoint_reload_resume() -> void:
	if _probe_id.is_empty():
		_failures.append("测试专用档位建不出来")
		return
	_prepare_launch(GameLaunch.RunIntent.START_NEW_RUN, _probe_id)
	var first: CombatSandbox = await _boot_sandbox()
	if first == null:
		return
	var session: RunSession = first._run_session
	_expect(not first._resumed_from_checkpoint, "START_NEW_RUN 不该走续跑分支")
	_expect(first._slot_id == _probe_id, "沙盒用上了指定测试档位")

	var want_run_id: String = session.get_shared_state().run_id
	_expect(not want_run_id.is_empty(), "新局有 run_id")
	_expect(session.get_loop_index() == 0, "新局 loop 从 0 开始")

	## ---- 推进一局：loop 1 + gold + xp/level + kills + 升级 + 跟班 ----
	session.notify_phrase_loop()
	session.add_gold(88)
	session.add_xp(1500)
	while session.has_pending_level():
		session.consume_pending_level()
	for _i: int in 5:
		session.note_kill()
	var granted: Array[String] = []
	for def: UpgradeDef in UPGRADE_CATALOG.get_all():
		if session.try_grant(def.id):
			granted.append(String(def.id))
		if granted.size() >= 2:
			break
	_expect(granted.size() >= 2, "至少发出 2 个升级，实为 %d" % granted.size())
	first._spawn_companion(&"gunner", 0)
	await process_frame
	_expect(first._count_living_companions() == 1, "本局有 1 只跟班，实为 %d" % first._count_living_companions())

	var want_level: int = session.get_level()
	var want_xp: int = session.get_xp()
	var want_gold: int = session.get_gold()
	var want_kills: int = session.get_kill_count()

	## ---- 提交安全检查点 ----
	first._commit_checkpoint(RunCheckpoint.Kind.LOOP_COMPLETE)

	## ---- 磁盘上必须真的有这份数据（不是只在内存）----
	var raw_slot: Dictionary = _read_raw_slot(_probe_id)
	_expect(not raw_slot.is_empty(), "checkpoint 真的写进了 user://records.json")
	var raw_run: Dictionary = _raw_dict(raw_slot.get("active_run"))
	_expect(str(raw_run.get("checkpoint_kind", "")) == "LOOP_COMPLETE", "落盘 kind=LOOP_COMPLETE，实为 %s" % str(raw_run.get("checkpoint_kind", "")))
	var raw_shared: Dictionary = _raw_dict(raw_run.get("shared_state"))
	_expect(int(raw_shared.get("loop_index", -1)) == 1, "落盘 loop_index=1，实为 %d" % int(raw_shared.get("loop_index", -1)))
	var want_saved_at: int = int(raw_run.get("saved_at", 0))
	_expect(want_saved_at > 0, "落盘 checkpoint 有 saved_at")
	var raw_players: Array = _raw_array(raw_run.get("players"))
	var want_hp: int = 0
	if raw_players.size() > 0:
		want_hp = int(_raw_dict(raw_players[0]).get("hp", 0))
	_expect(want_hp > 0, "落盘 HP > 0，实为 %d" % want_hp)

	## ---- 模拟进程结束：直接销毁场景（退出时不会补写任何东西）----
	first.queue_free()
	await process_frame
	GameSaveStore.load_from_disk()
	var stored: SaveSlot = GameSaveStore.get_slot(_probe_id)
	_expect(stored != null, "重载后档位还在")
	if stored != null:
		_expect(stored.status == SaveSlot.Status.IN_PROGRESS, "重载后状态是 IN_PROGRESS，实为 %s" % SaveSlot.status_name(stored.status))
		_expect(stored.has_active_run(), "重载后 active_run 还在")

	## ---- RESUME_RUN ----
	_prepare_launch(GameLaunch.RunIntent.RESUME_RUN, _probe_id)
	var second: CombatSandbox = await _boot_sandbox()
	if second == null:
		return
	_expect(second._resumed_from_checkpoint, "第二次启动走续跑分支")
	_expect(second._slot_id == _probe_id, "续跑用同一个档位")
	_expect(second._arena_id == "yard", "续跑 arena 来自 checkpoint（yard），实为 %s" % second._arena_id)

	var resumed: RunSession = second._run_session
	## run_id 不变 = 全程没调 restart()（restart 必换 run_id 并清空一切）。
	_expect(resumed.get_shared_state().run_id == want_run_id, "run_id 保持不变（证明 resume 没调 restart）")
	_expect(resumed.get_loop_index() == 1, "loop 恢复为 1，实为 %d" % resumed.get_loop_index())
	_expect(resumed.get_gold() == want_gold, "gold 恢复为 %d，实为 %d" % [want_gold, resumed.get_gold()])
	_expect(resumed.get_level() == want_level, "level 恢复为 %d，实为 %d" % [want_level, resumed.get_level()])
	_expect(resumed.get_xp() == want_xp, "xp 恢复为 %d，实为 %d" % [want_xp, resumed.get_xp()])
	_expect(resumed.get_kill_count() == want_kills, "kills 恢复为 %d，实为 %d" % [want_kills, resumed.get_kill_count()])
	for id: String in granted:
		_expect(resumed.has_upgrade(StringName(id)), "升级 %s 保留" % id)
	_expect(resumed.get_owned_upgrade_ids().size() == granted.size(), "升级数量一致，实为 %d" % resumed.get_owned_upgrade_ids().size())
	_expect(second._count_living_companions() == 1, "跟班恢复 1 只，实为 %d" % second._count_living_companions())
	var rstate: PlayerRunState = resumed.get_local_player_state()
	_expect(rstate.hp == want_hp, "HP 恢复为 %d，实为 %d" % [want_hp, rstate.hp])
	_expect(rstate.max_hp > 0, "max_hp > 0")
	_expect(resumed.get_loop_goal() == GameLaunch.SOLO_LOOP_GOAL, "loop_goal 来自档位，实为 %d" % resumed.get_loop_goal())
	_expect(resumed.get_save_slot_id() == _probe_id, "续跑仍挂在同一档位")

	## ---- 续跑绝不改写磁盘上原 checkpoint（§6：不伪装成 RUN_START）----
	GameSaveStore.load_from_disk()
	var after_slot: Dictionary = _read_raw_slot(_probe_id)
	var after_run: Dictionary = _raw_dict(after_slot.get("active_run"))
	_expect(str(after_run.get("checkpoint_kind", "")) == "LOOP_COMPLETE", "续跑没把 kind 改写成 RUN_START，实为 %s" % str(after_run.get("checkpoint_kind", "")))
	_expect(int(after_run.get("saved_at", 0)) == want_saved_at, "续跑没改写 saved_at（last_saved 仍然如实）")

	second.queue_free()
	await process_frame

## 中途退出只提交 PRE_EXIT：档保持 IN_PROGRESS、active_run 在、history 不多一条。
func _case_quit_stays_in_progress() -> void:
	if _probe_id.is_empty():
		return
	_prepare_launch(GameLaunch.RunIntent.START_NEW_RUN, _probe_id)
	var sandbox: CombatSandbox = await _boot_sandbox()
	if sandbox == null:
		return
	sandbox._run_session.notify_phrase_loop()
	sandbox._run_session.add_gold(7)
	var history_before: int = 0
	var before_slot: SaveSlot = GameSaveStore.get_slot(_probe_id)
	if before_slot != null:
		history_before = before_slot.history.size()

	sandbox._record_progress_if_needed()

	var raw_slot: Dictionary = _read_raw_slot(_probe_id)
	var raw_run: Dictionary = _raw_dict(raw_slot.get("active_run"))
	_expect(str(raw_run.get("checkpoint_kind", "")) == "PRE_EXIT", "中途退出只提交 PRE_EXIT，实为 %s" % str(raw_run.get("checkpoint_kind", "")))
	var stored: SaveSlot = GameSaveStore.get_slot(_probe_id)
	if stored == null:
		_failures.append("退出后档位丢失")
	else:
		_expect(stored.status == SaveSlot.Status.IN_PROGRESS, "退出后仍是 IN_PROGRESS，实为 %s" % SaveSlot.status_name(stored.status))
		_expect(stored.has_active_run(), "退出后 active_run 必须保留")
		_expect(stored.history.size() == history_before, "退出不写 history（没有 RunResult），%d -> %d" % [history_before, stored.history.size()])

	sandbox.queue_free()
	await process_frame

# ---- 工具 ----

func _expect(condition: bool, label: String) -> void:
	if condition:
		return
	_failures.append(label)

func _prepare_launch(intent: GameLaunch.RunIntent, slot_id: String) -> void:
	GameLaunch.set_mode(GameLaunch.Mode.SOLO)
	GameLaunch.set_net_role(GameLaunch.NetRole.OFFLINE)
	GameLaunch.set_net_play(GameLaunch.NetPlay.COOP)
	GameLaunch.set_local_seat(1)
	GameLaunch.set_arena_id("yard")
	GameLaunch.set_active_save_slot_id(slot_id)
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

## 直接读磁盘原始 JSON（绕过 GameSaveStore 内存），证明数据真的落过盘。
func _read_raw_slot(slot_id: String) -> Dictionary:
	var path: String = "user://records.json"
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	var rows: Variant = (parsed as Dictionary).get("slots", [])
	if typeof(rows) != TYPE_ARRAY:
		return {}
	for item: Variant in rows as Array:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		if str((item as Dictionary).get("slot_id", "")) == slot_id:
			return item as Dictionary
	return {}

func _raw_dict(value: Variant) -> Dictionary:
	return value if typeof(value) == TYPE_DICTIONARY else {}

func _raw_array(value: Variant) -> Array:
	return value if typeof(value) == TYPE_ARRAY else []

## 建一个**测试专用**档：这样 ensure_playable_slot 不会命中用户已有档，
## 全程只写自己这一个 slot。档位表满（12 个）才退化成「清空 + 跑完逐字节还原」。
func _make_probe_slot() -> String:
	GameSaveStore.load_from_disk()
	var probe: SaveSlot = GameSaveStore.create_slot("Resume Probe", "boar", GameLaunch.SOLO_LOOP_GOAL, "yard")
	if probe != null:
		return probe.slot_id
	for name: String in SAVE_NAMES:
		var path: String = "user://%s" % name
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	GameSaveStore.load_from_disk()
	probe = GameSaveStore.create_slot("Resume Probe", "boar", GameLaunch.SOLO_LOOP_GOAL, "yard")
	return probe.slot_id if probe != null else ""

func _cleanup() -> void:
	if not _probe_id.is_empty():
		GameSaveStore.load_from_disk()
		GameSaveStore.delete_slot(_probe_id)
	_restore_saves()

## 只把字节抄进内存，绝不删用户文件。
func _snapshot_saves() -> void:
	_save_snapshot.clear()
	for name: String in SAVE_NAMES:
		var path: String = "user://%s" % name
		_save_snapshot[name] = FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else null

## 把字节写回；测试开始前不存在的文件才删除（只删自己造出来的）。
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
