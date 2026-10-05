extends RefCounted
class_name SharedRunState

## 一局里**所有玩家共享**的运行状态。纯数据：不碰 SceneTree / UI / FileAccess /
## ENet / MultiplayerPeer，可 headless 单测，可 JSON 序列化。
##
## 本阶段必须保存：run_id / save_slot_id / arena_id / loop_goal / loop_index /
## elapsed_sec / run_seed / mode / outcome / checkpoint_kind。
## 下面三个 Dictionary 是**预留扩展位**（encounter_progress / shared_rng_state /
## shared_progress），本阶段只留结构，不做复杂 encounter 序列化。
const ARENA_CATALOG: ArenaCatalog = preload("res://data/arena_catalog.tres")

var run_id: String = ""
var save_slot_id: String = ""
var arena_id: String = "yard"
var loop_goal: int = 0
## 0 起：与 HUD 顶中 / Overlay 同一套。
var loop_index: int = 0
var elapsed_sec: float = 0.0
var run_seed: int = 0
## "solo" / "infinite"
var mode: String = "infinite"
## "playing" / "cleared" / "dead"
var outcome: String = "playing"
## 该状态来自哪种 checkpoint（字符串名，便于 JSON 可读）。
var checkpoint_kind: String = "RUN_START"

var encounter_progress: Dictionary = {}
var shared_rng_state: Dictionary = {}
var shared_progress: Dictionary = {}

## 深拷贝（走 JSON 同一条路径，保证「能存就能拷」）。
func duplicate_state() -> SharedRunState:
	return SharedRunState.from_dictionary(to_dictionary())

static func make(run_id: String, save_slot_id: String) -> SharedRunState:
	var state: SharedRunState = SharedRunState.new()
	state.run_id = run_id
	state.save_slot_id = save_slot_id
	return state

func is_solo() -> bool:
	return loop_goal > 0

func to_dictionary() -> Dictionary:
	return {
		"run_id": run_id,
		"save_slot_id": save_slot_id,
		"arena_id": arena_id,
		"loop_goal": loop_goal,
		"loop_index": loop_index,
		"elapsed_sec": elapsed_sec,
		"run_seed": run_seed,
		"mode": mode,
		"outcome": outcome,
		"checkpoint_kind": checkpoint_kind,
		"encounter_progress": encounter_progress.duplicate(true),
		"shared_rng_state": shared_rng_state.duplicate(true),
		"shared_progress": shared_progress.duplicate(true),
	}

static func from_dictionary(data: Dictionary) -> SharedRunState:
	var state: SharedRunState = SharedRunState.new()
	state.run_id = str(data.get("run_id", ""))
	state.save_slot_id = str(data.get("save_slot_id", ""))
	state.arena_id = ARENA_CATALOG.sanitize(str(data.get("arena_id", "yard")))
	state.loop_goal = maxi(int(data.get("loop_goal", 0)), 0)
	state.loop_index = maxi(int(data.get("loop_index", 0)), 0)
	state.elapsed_sec = maxf(float(data.get("elapsed_sec", 0.0)), 0.0)
	state.run_seed = int(data.get("run_seed", 0))
	state.mode = sanitize_mode(str(data.get("mode", "infinite")))
	state.outcome = sanitize_outcome(str(data.get("outcome", "playing")))
	state.checkpoint_kind = RunCheckpoint.sanitize_kind_name(str(data.get("checkpoint_kind", "RUN_START")))
	state.encounter_progress = _parse_dict(data.get("encounter_progress", {}))
	state.shared_rng_state = _parse_dict(data.get("shared_rng_state", {}))
	state.shared_progress = _parse_dict(data.get("shared_progress", {}))
	return state

static func sanitize_mode(value: String) -> String:
	if value == "solo":
		return "solo"
	return "infinite"

static func sanitize_outcome(value: String) -> String:
	if value == "cleared" or value == "dead" or value == "playing":
		return value
	return "playing"

static func _parse_dict(raw: Variant) -> Dictionary:
	if typeof(raw) != TYPE_DICTIONARY:
		return {}
	return (raw as Dictionary).duplicate(true)
