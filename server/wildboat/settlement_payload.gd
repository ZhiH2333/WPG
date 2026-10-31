extends RefCounted
class_name SettlementPayload

## 最小可测试结算结构。不含虚构战绩：字段由 DS 实测填充。
## 客户端不得提交权威结果。

var settlement_id: String = ""
var match_id: String = ""
var game_instance_id: String = ""
var mode: String = "coop_survival"
var result: String = "completed" ## completed | aborted
var started_at: String = ""
var ended_at: String = ""
var players: Array = [] ## Array[Dictionary]
var mode_stats: Dictionary = {}


func to_dict() -> Dictionary:
	return {
		"settlement_id": settlement_id,
		"match_id": match_id,
		"game_instance_id": game_instance_id,
		"mode": mode,
		"result": result,
		"started_at": started_at,
		"ended_at": ended_at,
		"players": players,
		"mode_stats": mode_stats,
	}


static func make_minimal(
	match_id: String,
	instance_id: String,
	player_states: Array,
	mode: String = "coop_survival",
	result: String = "completed"
) -> SettlementPayload:
	var payload := SettlementPayload.new()
	payload.settlement_id = "set_%s_%d" % [match_id, Time.get_unix_time_from_system()]
	payload.match_id = match_id
	payload.game_instance_id = instance_id
	payload.mode = mode
	payload.result = result
	var now: String = Time.get_datetime_string_from_system(true) + "Z"
	payload.started_at = now
	payload.ended_at = now
	var rows: Array = []
	for entry in player_states:
		var state: DsPlayerState = entry as DsPlayerState
		if state == null:
			continue
		rows.append({
			"player_id": state.player_id,
			"seat": state.seat,
			"display_name": state.display_name,
			"kills": 0,
			"deaths": 0,
			"score": 0,
		})
	payload.players = rows
	payload.mode_stats = {
		"occupied_seats": rows.size(),
		"note": "minimal_test_settlement_no_combat_stats",
	}
	return payload
