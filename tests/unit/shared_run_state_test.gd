extends SceneTree

## SharedRunState 回归：round trip / 本阶段必存字段 / 预留扩展位 / 清洗。
## 跑法：godot --headless --path . --script res://tests/unit/shared_run_state_test.gd
## 通过输出 SHARED_RUN_STATE_OK；失败逐条 SHARED_RUN_STATE_FAIL 并返回非 0。

var _failures: PackedStringArray = PackedStringArray()

func _initialize() -> void:
	_run_all.call_deferred()

func _run_all() -> void:
	_case_round_trip()
	_case_required_fields_present()
	_case_reserved_extension_slots()
	_case_invalid_data_sanitized()
	_case_is_pure_data()
	if _failures.is_empty():
		print("SHARED_RUN_STATE_OK")
		quit(0)
		return
	for failure: String in _failures:
		printerr("SHARED_RUN_STATE_FAIL: %s" % failure)
	quit(1)

func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures.append(message)

func _full_state() -> SharedRunState:
	var state: SharedRunState = SharedRunState.make("run-4242", "s-slot-9")
	state.arena_id = "pit"
	state.loop_goal = 20
	state.loop_index = 7
	state.elapsed_sec = 314.25
	state.run_seed = 1122334455
	state.mode = "solo"
	state.outcome = "playing"
	state.checkpoint_kind = "LOOP_COMPLETE"
	return state

## 3) SharedRunState round trip。
func _case_round_trip() -> void:
	var state: SharedRunState = _full_state()
	var restored: SharedRunState = SharedRunState.from_dictionary(state.to_dictionary())
	_expect(restored.run_id == "run-4242", "run_id round trip")
	_expect(restored.save_slot_id == "s-slot-9", "save_slot_id round trip")
	_expect(restored.arena_id == "pit", "arena_id round trip")
	_expect(restored.loop_goal == 20, "loop_goal round trip")
	_expect(restored.loop_index == 7, "loop_index round trip")
	_expect(restored.elapsed_sec == 314.25, "elapsed_sec round trip")
	_expect(restored.run_seed == 1122334455, "run_seed round trip")
	_expect(restored.mode == "solo", "mode round trip")
	_expect(restored.outcome == "playing", "outcome round trip")
	_expect(restored.checkpoint_kind == "LOOP_COMPLETE", "checkpoint_kind round trip")
	_expect(restored.is_solo(), "loop_goal>0 即 solo")

## 本阶段必须保存的十个字段一个都不能少。
func _case_required_fields_present() -> void:
	var payload: Dictionary = _full_state().to_dictionary()
	for key: String in [
		"run_id",
		"save_slot_id",
		"arena_id",
		"loop_goal",
		"loop_index",
		"elapsed_sec",
		"run_seed",
		"mode",
		"outcome",
		"checkpoint_kind",
	]:
		_expect(payload.has(key), "必存字段缺失：%s" % key)

## 预留扩展位：encounter_progress / shared_rng_state / shared_progress。
## 本阶段不实现复杂 encounter 序列化，但结构必须先立住并能往返。
func _case_reserved_extension_slots() -> void:
	var payload: Dictionary = _full_state().to_dictionary()
	_expect(payload.has("encounter_progress"), "预留 encounter_progress")
	_expect(payload.has("shared_rng_state"), "预留 shared_rng_state")
	_expect(payload.has("shared_progress"), "预留 shared_progress")
	var state: SharedRunState = _full_state()
	state.encounter_progress["phase"] = 3
	state.shared_rng_state["seed"] = 1234
	state.shared_progress["cleared_loops"] = 2
	var restored: SharedRunState = SharedRunState.from_dictionary(state.to_dictionary())
	_expect(int(restored.encounter_progress.get("phase", 0)) == 3, "encounter_progress round trip")
	_expect(int(restored.shared_rng_state.get("seed", 0)) == 1234, "shared_rng_state round trip")
	_expect(int(restored.shared_progress.get("cleared_loops", 0)) == 2, "shared_progress round trip")

## 6) invalid data sanitization。
func _case_invalid_data_sanitized() -> void:
	var restored: SharedRunState = SharedRunState.from_dictionary({
		"arena_id": "moon",
		"loop_goal": -1,
		"loop_index": -1,
		"elapsed_sec": -10.0,
		"mode": "battle-royale",
		"outcome": "victory",
		"checkpoint_kind": "SOME_KIND",
		"encounter_progress": "nope",
	})
	_expect(restored.arena_id == ArenaCatalog.DEFAULT_ID, "非法 arena 打回默认")
	_expect(restored.loop_goal == 0, "负 loop_goal 打回 0")
	_expect(restored.loop_index == 0, "负 loop_index 打回 0")
	_expect(restored.elapsed_sec == 0.0, "负 elapsed 打回 0")
	_expect(restored.mode == "infinite", "未知 mode 打回 infinite")
	_expect(restored.outcome == "playing", "未知 outcome 打回 playing")
	_expect(restored.checkpoint_kind == "RUN_START", "未知 checkpoint_kind 打回 RUN_START")
	_expect(restored.encounter_progress.is_empty(), "错类型扩展位回退空字典")

## 纯数据：不依赖 SceneTree / UI。
func _case_is_pure_data() -> void:
	var obj: Variant = _full_state()
	_expect(not (obj is Node), "SharedRunState 不是 Node")
	_expect(not (obj is SceneTree), "SharedRunState 不是 SceneTree")
	_expect(obj is RefCounted, "SharedRunState 是 RefCounted")
