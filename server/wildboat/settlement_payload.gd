extends RefCounted
class_name SettlementPayload

## 最小可测试结算结构。不含虚构战绩：字段由 DS 实测填充。
## 客户端不得提交权威结果。
## settlement_id 必须为 UUID（WildBoat 契约）。

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
	## 提交体对齐契约 §8.5（额外字段 WildBoat 会忽略）。
	return {
		"settlement_id": settlement_id,
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
	payload.settlement_id = _new_uuid_v4()
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
		if state.player_id.strip_edges().is_empty():
			continue
		rows.append({
			"player_id": state.player_id,
			"team_id": "",
			"kills": 0,
			"deaths": 0,
			"score": 0,
		})
	payload.players = rows
	payload.mode_stats = {
		"duration_seconds": 0,
		"occupied_seats": rows.size(),
		"note": "minimal_test_settlement_no_combat_stats",
	}
	return payload


static func _new_uuid_v4() -> String:
	var b := PackedByteArray()
	b.resize(16)
	for i in 16:
		b[i] = randi() % 256
	b[6] = (b[6] & 0x0f) | 0x40
	b[8] = (b[8] & 0x3f) | 0x80
	return "%02x%02x%02x%02x-%02x%02x-%02x%02x-%02x%02x-%02x%02x%02x%02x%02x%02x" % [
		b[0], b[1], b[2], b[3],
		b[4], b[5],
		b[6], b[7],
		b[8], b[9],
		b[10], b[11], b[12], b[13], b[14], b[15],
	]
