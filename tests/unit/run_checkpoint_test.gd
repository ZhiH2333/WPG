extends SceneTree

## RunCheckpoint 回归：round trip / 六种 checkpoint_kind / 纯数据（不进场景树）。
## 跑法：godot --headless --path . --script res://tests/unit/run_checkpoint_test.gd
## 通过输出 RUN_CHECKPOINT_OK；失败逐条 RUN_CHECKPOINT_FAIL 并返回非 0。

var _failures: PackedStringArray = PackedStringArray()

func _initialize() -> void:
	_run_all.call_deferred()

func _run_all() -> void:
	_case_round_trip()
	_case_all_kinds_round_trip()
	_case_is_pure_data()
	_case_missing_fields_are_safe()
	if _failures.is_empty():
		print("RUN_CHECKPOINT_OK")
		quit(0)
		return
	for failure: String in _failures:
		printerr("RUN_CHECKPOINT_FAIL: %s" % failure)
	quit(1)

func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures.append(message)

func _shared() -> SharedRunState:
	var state: SharedRunState = SharedRunState.make("run-77", "s-77")
	state.arena_id = "yard"
	state.loop_goal = 20
	state.loop_index = 5
	state.elapsed_sec = 512.75
	state.run_seed = 987654321
	state.mode = "solo"
	state.outcome = "playing"
	return state

func _players() -> Array[PlayerRunState]:
	var rows: Array[PlayerRunState] = []
	var host: PlayerRunState = PlayerRunState.create("profile-host", "Host", "boar", 1)
	host.hp = 80
	host.max_hp = 160
	host.level = 9
	host.xp = 12
	host.pending_level = 2
	host.gold = 455
	host.kill_count = 123
	host.owned_upgrade_ids = ["swift", "cadence", "cadence"]
	host.alive = true
	rows.append(host)
	var guest: PlayerRunState = PlayerRunState.create("profile-guest", "Guest", "chicken", 2)
	guest.hp = 0
	guest.max_hp = 100
	guest.alive = false
	guest.eliminated = true
	rows.append(guest)
	return rows

## 4) Checkpoint round trip。
func _case_round_trip() -> void:
	var checkpoint: RunCheckpoint = RunCheckpoint.create(
		RunCheckpoint.Kind.PLAYER_DECISION, _shared(), _players()
	)
	var restored: RunCheckpoint = RunCheckpoint.from_dictionary(checkpoint.to_dictionary())
	_expect(restored.checkpoint_version == RunCheckpoint.CHECKPOINT_VERSION, "checkpoint_version round trip")
	_expect(restored.run_id == "run-77", "run_id round trip")
	_expect(restored.save_slot_id == "s-77", "save_slot_id round trip")
	_expect(restored.saved_at == checkpoint.saved_at, "saved_at round trip")
	_expect(restored.checkpoint_kind == RunCheckpoint.Kind.PLAYER_DECISION, "checkpoint_kind round trip")
	_expect(restored.players.size() == 2, "players 数量 round trip")
	_expect(restored.shared_state.run_seed == 987654321, "run_seed round trip")
	_expect(restored.shared_state.elapsed_sec == 512.75, "elapsed_sec round trip")
	_expect(restored.shared_state.loop_index == 5, "loop_index round trip")
	_expect(is_equal_approx(restored.shared_state.elapsed_sec, 512.75), "elapsed_sec 精度")
	var host: PlayerRunState = restored.get_player("profile-host")
	_expect(host != null, "按 profile_id 找回玩家")
	if host != null:
		_expect(host.gold == 455, "gold round trip")
		_expect(host.level == 9, "level round trip")
		_expect(host.xp == 12, "xp round trip")
		_expect(host.pending_level == 2, "pending_level round trip")
		_expect(host.kill_count == 123, "kill_count round trip")
		_expect(host.hp == 80 and host.max_hp == 160, "hp round trip")
		_expect(host.owned_upgrade_ids.size() == 3, "owned 升级数量 round trip")
		_expect(host.owned_upgrade_ids[2] == "cadence", "stackable 升级重复项保留")
	_expect(restored.get_player("nope") == null, "未知 profile_id 返回 null")
	var guest: PlayerRunState = restored.get_player("profile-guest")
	_expect(guest != null and not guest.alive and guest.eliminated, "eliminated round trip")

## checkpoint_kind 六种都要能进出 JSON。
func _case_all_kinds_round_trip() -> void:
	var kinds: Array[int] = [
		RunCheckpoint.Kind.RUN_START,
		RunCheckpoint.Kind.LOOP_COMPLETE,
		RunCheckpoint.Kind.PLAYER_DECISION,
		RunCheckpoint.Kind.SHOP_COMPLETE,
		RunCheckpoint.Kind.PRE_EXIT,
		RunCheckpoint.Kind.TERMINAL,
	]
	for kind: int in kinds:
		var name: String = RunCheckpoint.kind_name(kind)
		_expect(RunCheckpoint.kind_from_name(name) == kind, "%s 反解回同一个 kind" % name)
		var checkpoint: RunCheckpoint = RunCheckpoint.create(kind, _shared(), _players())
		var restored: RunCheckpoint = RunCheckpoint.from_dictionary(checkpoint.to_dictionary())
		_expect(restored.checkpoint_kind == kind, "%s round trip" % name)
		_expect(restored.shared_state.checkpoint_kind == name, "%s 写进 shared_state" % name)
	_expect(RunCheckpoint.kind_from_name("UNKNOWN_KIND") == RunCheckpoint.Kind.RUN_START, "未知 kind 打回 RUN_START")
	_expect(RunCheckpoint.sanitize_kind_name("whatever") == "RUN_START", "未知 kind 名打回 RUN_START")

## 纯数据对象：不依赖 SceneTree，不依赖 UI，不直接操作 FileAccess / ENet / MultiplayerPeer。
func _case_is_pure_data() -> void:
	var checkpoint: RunCheckpoint = RunCheckpoint.create(RunCheckpoint.Kind.RUN_START, _shared(), _players())
	var obj: Variant = checkpoint
	_expect(not (obj is Node), "RunCheckpoint 不是 Node")
	_expect(not (obj is SceneTree), "RunCheckpoint 不是 SceneTree")
	_expect(not checkpoint.is_inside_tree(), "RunCheckpoint 不在场景树里")
	_expect(obj is RefCounted, "RunCheckpoint 是 RefCounted")

## 缺字段 / 错类型不能崩，恢复成安全默认。
func _case_missing_fields_are_safe() -> void:
	var restored: RunCheckpoint = RunCheckpoint.from_dictionary({})
	_expect(restored.checkpoint_version == RunCheckpoint.CHECKPOINT_VERSION, "空字典补默认版本")
	_expect(restored.checkpoint_kind == RunCheckpoint.Kind.RUN_START, "空字典补默认 kind")
	_expect(restored.players.is_empty(), "空字典没有玩家")
	_expect(restored.shared_state != null, "空字典仍带 shared_state")
	_expect(restored.get_first_player() == null, "没有玩家时 get_first_player 为 null")
	var bad: RunCheckpoint = RunCheckpoint.from_dictionary({
		"shared_state": "nope",
		"players": [1, 2, "three"],
	})
	_expect(bad.shared_state != null, "错类型 shared_state 回退默认")
	_expect(bad.players.is_empty(), "非字典玩家被丢弃")
