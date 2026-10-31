extends RefCounted
class_name TicketValidator

## Game Ticket 校验结果约定：
## {
##   ok: bool,
##   reason: OnlineProtocol.RejectReason,
##   player_id: String,
##   display_name: String,
##   match_id: String,
##   game_instance_id: String,
## }
##
## 子类覆盖 validate()。默认拒绝一切。


func validate(_ticket: String, _expected_match_id: String, _expected_instance_id: String) -> Dictionary:
	return _reject(OnlineProtocol.RejectReason.BAD_TOKEN)


func _ok(
	player_id: String,
	display_name: String,
	match_id: String,
	instance_id: String
) -> Dictionary:
	return {
		"ok": true,
		"reason": OnlineProtocol.RejectReason.NONE,
		"player_id": player_id,
		"display_name": display_name,
		"match_id": match_id,
		"game_instance_id": instance_id,
	}


func _reject(reason: int) -> Dictionary:
	return {
		"ok": false,
		"reason": reason,
		"player_id": "",
		"display_name": "",
		"match_id": "",
		"game_instance_id": "",
	}
