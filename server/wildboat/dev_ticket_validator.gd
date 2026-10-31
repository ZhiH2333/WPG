extends TicketValidator
class_name DevTicketValidator

## Phase 2A 兼容：共享 WPG_DEV_TOKEN。空 token 配置 = 本地开放。
## 生产禁止依赖本验证器作为身份认证。

var expected_token: String = ""
var match_id: String = "dev_match"
var instance_id: String = "dev_instance"


func _init(p_token: String = "", p_match_id: String = "dev_match", p_instance_id: String = "dev_instance") -> void:
	expected_token = p_token.substr(0, OnlineProtocol.MAX_GAME_TICKET_LEN)
	match_id = p_match_id
	instance_id = p_instance_id


func validate(ticket: String, expected_match_id: String, expected_instance_id: String) -> Dictionary:
	var offered: String = ticket.substr(0, OnlineProtocol.MAX_GAME_TICKET_LEN)
	if not expected_token.is_empty() and offered != expected_token:
		return _reject(OnlineProtocol.RejectReason.BAD_TOKEN)
	var mid: String = expected_match_id if not expected_match_id.is_empty() else match_id
	var iid: String = expected_instance_id if not expected_instance_id.is_empty() else instance_id
	## Dev 模式不绑定真实 player_id（空串），避免多人共享同一 dev token 被当成重复身份。
	return _ok("", "player", mid, iid)
