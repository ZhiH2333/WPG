extends RefCounted
class_name RunResult

## 一局的结算结果（terminal 结果或被记录的退出）。纯数据：不碰 SceneTree / UI /
## FileAccess / ENet / MultiplayerPeer，可 headless 单测，可 JSON 序列化。
##
## 这里是**评分规则的唯一真源**：GameRecords.compute_score 只做转发，不再自己算。
## 未来改评分算法必须 bump SCORING_VERSION，这样历史结果永远知道自己用的是哪套规则。
const SCORING_VERSION: int = 1
const OUTCOME_CLEARED: String = "cleared"
const OUTCOME_DEAD: String = "dead"
const OUTCOME_QUIT: String = "quit"

var run_id: String = ""
var save_slot_id: String = ""
## cleared / dead / quit
var outcome: String = OUTCOME_QUIT
var loop_index: int = 0
var kill_count: int = 0
var gold: int = 0
var elapsed_sec: float = 0.0
## 本机（或该结果归属玩家）的分数。
var score: int = 0
var scoring_version: int = SCORING_VERSION
var timestamp: int = 0
## profile_id -> score。**不是** peer_id -> score：peer 不是稳定身份。
var player_scores: Dictionary = {}
## team score = sum(players.score)。单人时等于 score。
var team_score: int = 0

## 现有评分公式，一字不改：loop*1000 + kills*5 + gold*2 + floor(time) + (cleared ? 5000 : 0)
static func compute_score(loop_index: int, kills: int, gold: int, time_sec: float, outcome: String) -> int:
	var cleared_bonus: int = 5000 if outcome == OUTCOME_CLEARED else 0
	return loop_index * 1000 + kills * 5 + gold * 2 + floori(time_sec) + cleared_bonus

static func sanitize_outcome(value: String) -> String:
	if value == OUTCOME_CLEARED or value == OUTCOME_DEAD or value == OUTCOME_QUIT:
		return value
	return OUTCOME_QUIT

func recompute_team_score() -> void:
	var total: int = 0
	for key: Variant in player_scores:
		total += int(player_scores[key])
	team_score = total

func to_dictionary() -> Dictionary:
	return {
		"run_id": run_id,
		"save_slot_id": save_slot_id,
		"outcome": outcome,
		"loop_index": loop_index,
		"kill_count": kill_count,
		"gold": gold,
		"elapsed_sec": elapsed_sec,
		"score": score,
		"scoring_version": scoring_version,
		"timestamp": timestamp,
		"player_scores": _duplicate_scores(),
		"team_score": team_score,
	}

static func from_dictionary(data: Dictionary) -> RunResult:
	var result: RunResult = RunResult.new()
	result.run_id = str(data.get("run_id", ""))
	result.save_slot_id = str(data.get("save_slot_id", ""))
	result.outcome = sanitize_outcome(str(data.get("outcome", OUTCOME_QUIT)))
	result.loop_index = maxi(int(data.get("loop_index", 0)), 0)
	result.kill_count = maxi(int(data.get("kill_count", 0)), 0)
	result.gold = maxi(int(data.get("gold", 0)), 0)
	result.elapsed_sec = maxf(float(data.get("elapsed_sec", 0.0)), 0.0)
	result.score = maxi(int(data.get("score", 0)), 0)
	result.scoring_version = maxi(int(data.get("scoring_version", SCORING_VERSION)), 0)
	result.timestamp = int(data.get("timestamp", 0))
	result.player_scores = _parse_scores(data.get("player_scores", {}))
	result.team_score = maxi(int(data.get("team_score", 0)), 0)
	return result

func _duplicate_scores() -> Dictionary:
	var copy: Dictionary = {}
	for key: Variant in player_scores:
		copy[key] = int(player_scores[key])
	return copy

static func _parse_scores(raw: Variant) -> Dictionary:
	var scores: Dictionary = {}
	if typeof(raw) != TYPE_DICTIONARY:
		return scores
	var source: Dictionary = raw as Dictionary
	for key: Variant in source:
		scores[str(key)] = int(source[key])
	return scores
