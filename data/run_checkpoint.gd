extends RefCounted
class_name RunCheckpoint

## 一次**安全检查点**（SAFE CHECKPOINT）的完整快照。
## 纯数据：不碰 SceneTree / UI / FileAccess / ENet / MultiplayerPeer，可 headless 单测。
##
## 明确不做的事：本对象**不**保存任意一帧的完整世界状态。敌人完整 AI、弹体、动画内部
## 状态、任意瞬时 timer、任意瞬时战斗 frame 都没有可靠 serializer，因此**不进 JSON**。
## 退出时永远只恢复最近一次已经提交的 checkpoint。
const CHECKPOINT_VERSION: int = 1

enum Kind {
	RUN_START, ## 一局开始（或 Retry 后重开）
	LOOP_COMPLETE, ## 一轮 loop 结算完成
	PLAYER_DECISION, ## 玩家做完一次选择（升级三选一等）
	SHOP_COMPLETE, ## 商店结算完成
	PRE_EXIT, ## 离开沙盒前提交
	TERMINAL, ## 终局（通关 / 死亡）
}

const KIND_NAMES: Dictionary = {
	Kind.RUN_START: "RUN_START",
	Kind.LOOP_COMPLETE: "LOOP_COMPLETE",
	Kind.PLAYER_DECISION: "PLAYER_DECISION",
	Kind.SHOP_COMPLETE: "SHOP_COMPLETE",
	Kind.PRE_EXIT: "PRE_EXIT",
	Kind.TERMINAL: "TERMINAL",
}

var checkpoint_version: int = CHECKPOINT_VERSION
var run_id: String = ""
var save_slot_id: String = ""
var saved_at: int = 0
var checkpoint_kind: int = Kind.RUN_START
var shared_state: SharedRunState = SharedRunState.new()
var players: Array[PlayerRunState] = []

static func kind_name(kind: int) -> String:
	if KIND_NAMES.has(kind):
		return String(KIND_NAMES[kind])
	return String(KIND_NAMES[Kind.RUN_START])

static func kind_from_name(value: String) -> int:
	for kind: int in KIND_NAMES:
		if String(KIND_NAMES[kind]) == value:
			return kind
	return Kind.RUN_START

static func sanitize_kind_name(value: String) -> String:
	return kind_name(kind_from_name(value))

static func create(kind: int, shared: SharedRunState, player_states: Array[PlayerRunState]) -> RunCheckpoint:
	var checkpoint: RunCheckpoint = RunCheckpoint.new()
	checkpoint.checkpoint_kind = kind
	if shared != null:
		checkpoint.shared_state = shared.duplicate_state()
		checkpoint.run_id = shared.run_id
		checkpoint.save_slot_id = shared.save_slot_id
	checkpoint.players = []
	for state: PlayerRunState in player_states:
		if state == null:
			continue
		checkpoint.players.append(state.duplicate_state())
	checkpoint.saved_at = int(Time.get_unix_time_from_system())
	if checkpoint.shared_state != null:
		checkpoint.shared_state.checkpoint_kind = kind_name(kind)
	return checkpoint

func get_player(profile_id: String) -> PlayerRunState:
	if profile_id.is_empty():
		return null
	for state: PlayerRunState in players:
		if state != null and state.profile_id == profile_id:
			return state
	return null

func get_first_player() -> PlayerRunState:
	for state: PlayerRunState in players:
		if state != null:
			return state
	return null

func to_dictionary() -> Dictionary:
	var rows: Array = []
	for state: PlayerRunState in players:
		if state == null:
			continue
		rows.append(state.to_dictionary())
	return {
		"checkpoint_version": checkpoint_version,
		"run_id": run_id,
		"save_slot_id": save_slot_id,
		"saved_at": saved_at,
		"checkpoint_kind": kind_name(checkpoint_kind),
		"shared_state": shared_state.to_dictionary() if shared_state != null else {},
		"players": rows,
	}

static func from_dictionary(data: Dictionary) -> RunCheckpoint:
	var checkpoint: RunCheckpoint = RunCheckpoint.new()
	checkpoint.checkpoint_version = maxi(int(data.get("checkpoint_version", CHECKPOINT_VERSION)), 0)
	checkpoint.run_id = str(data.get("run_id", ""))
	checkpoint.save_slot_id = str(data.get("save_slot_id", ""))
	checkpoint.saved_at = int(data.get("saved_at", 0))
	checkpoint.checkpoint_kind = kind_from_name(str(data.get("checkpoint_kind", "RUN_START")))
	var raw_shared: Variant = data.get("shared_state", {})
	if typeof(raw_shared) == TYPE_DICTIONARY:
		checkpoint.shared_state = SharedRunState.from_dictionary(raw_shared as Dictionary)
	else:
		checkpoint.shared_state = SharedRunState.new()
	checkpoint.shared_state.checkpoint_kind = kind_name(checkpoint.checkpoint_kind)
	if checkpoint.run_id.is_empty():
		checkpoint.run_id = checkpoint.shared_state.run_id
	if checkpoint.save_slot_id.is_empty():
		checkpoint.save_slot_id = checkpoint.shared_state.save_slot_id
	checkpoint.players = []
	var raw_players: Variant = data.get("players", [])
	if typeof(raw_players) == TYPE_ARRAY:
		for item: Variant in raw_players as Array:
			if typeof(item) != TYPE_DICTIONARY:
				continue
			checkpoint.players.append(PlayerRunState.from_dictionary(item as Dictionary))
	return checkpoint
