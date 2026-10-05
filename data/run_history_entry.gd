extends RefCounted
class_name RunHistoryEntry

## 档位 history 里的一行：一局**已经结束**的结果投影。不是 run state，永远不含 active_run。
## 只存账本需要的标量，不存升级清单 / 物品清单（硬规定：任何界面都不显示它）。
const MAX_ENTRIES: int = 10

var score: int = 0
var loop: int = 0
var kills: int = 0
var gold: int = 0
var time_sec: float = 0.0
var outcome: String = RunResult.OUTCOME_QUIT
var timestamp: int = 0
var scoring_version: int = RunResult.SCORING_VERSION

static func from_result(result: RunResult) -> RunHistoryEntry:
	var entry: RunHistoryEntry = RunHistoryEntry.new()
	if result == null:
		return entry
	entry.score = result.score
	entry.loop = result.loop_index
	entry.kills = result.kill_count
	entry.gold = result.gold
	entry.time_sec = result.elapsed_sec
	entry.outcome = result.outcome
	entry.timestamp = result.timestamp
	entry.scoring_version = result.scoring_version
	return entry

static func is_score_higher(left: RunHistoryEntry, right: RunHistoryEntry) -> bool:
	if left == null or right == null:
		return right != null
	return left.score > right.score

func to_dictionary() -> Dictionary:
	return {
		"score": score,
		"loop": loop,
		"kills": kills,
		"gold": gold,
		"time_sec": time_sec,
		"outcome": outcome,
		"timestamp": timestamp,
		"scoring_version": scoring_version,
	}

static func from_dictionary(data: Dictionary) -> RunHistoryEntry:
	var entry: RunHistoryEntry = RunHistoryEntry.new()
	entry.score = maxi(int(data.get("score", 0)), 0)
	entry.loop = maxi(int(data.get("loop", 0)), 0)
	entry.kills = maxi(int(data.get("kills", 0)), 0)
	entry.gold = maxi(int(data.get("gold", 0)), 0)
	entry.time_sec = maxf(float(data.get("time_sec", 0.0)), 0.0)
	entry.outcome = RunResult.sanitize_outcome(str(data.get("outcome", RunResult.OUTCOME_QUIT)))
	entry.timestamp = int(data.get("timestamp", 0))
	entry.scoring_version = maxi(int(data.get("scoring_version", RunResult.SCORING_VERSION)), 0)
	return entry
