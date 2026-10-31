extends TicketValidator
class_name WildboatTicketValidator

## 在线校验：DS -> WildBoat `POST /v1/server/tickets/validate`。
## 契约草案见 WildBoat docs；**Agent A 尚未落地该端点**。
## WildBoat 不可达时安全失败（BACKEND_UNAVAILABLE），绝不信任客户端自报身份。

var server_client: WildboatServerClient = null
var server_build: String = "wpg-server"
var timeout_sec: float = 5.0


func _init(p_client: WildboatServerClient = null, p_build: String = "wpg-server") -> void:
	server_client = p_client
	server_build = p_build


func validate(ticket: String, expected_match_id: String, expected_instance_id: String) -> Dictionary:
	## 同步门面：调用方应使用 validate_async。保留同步拒绝以防误用。
	return _reject(OnlineProtocol.RejectReason.BACKEND_UNAVAILABLE)


func validate_async(ticket: String, expected_match_id: String, expected_instance_id: String) -> Dictionary:
	if server_client == null:
		return _reject(OnlineProtocol.RejectReason.BACKEND_UNAVAILABLE)
	if ticket.strip_edges().is_empty():
		return _reject(OnlineProtocol.RejectReason.BAD_TOKEN)
	var body: Dictionary = {
		"ticket": ticket,
		"game_instance_id": expected_instance_id,
		"server_build": server_build,
	}
	var res: Dictionary = await server_client.validate_ticket(body, timeout_sec)
	if not bool(res.get("ok", false)):
		var err: WildboatError = res.get("error") as WildboatError
		if err != null and err.is_transport():
			return _reject(OnlineProtocol.RejectReason.BACKEND_UNAVAILABLE)
		if err != null:
			match err.code:
				"TICKET_EXPIRED":
					return _reject(OnlineProtocol.RejectReason.TICKET_EXPIRED)
				"TICKET_REPLAYED":
					return _reject(OnlineProtocol.RejectReason.TICKET_REPLAYED)
				"TICKET_MISMATCH", "MATCH_MISMATCH", "INSTANCE_MISMATCH":
					return _reject(OnlineProtocol.RejectReason.TICKET_MISMATCH)
				_:
					return _reject(OnlineProtocol.RejectReason.BAD_TOKEN)
		return _reject(OnlineProtocol.RejectReason.BAD_TOKEN)
	var payload: Variant = res.get("body")
	if typeof(payload) != TYPE_DICTIONARY:
		return _reject(OnlineProtocol.RejectReason.BAD_TOKEN)
	var data: Dictionary = payload
	if data.has("valid") and not bool(data.get("valid", false)):
		return _reject(OnlineProtocol.RejectReason.BAD_TOKEN)
	var player_id: String = str(data.get("player_id", ""))
	var match_id: String = str(data.get("match_id", ""))
	var instance_id: String = str(data.get("game_instance_id", expected_instance_id))
	var display_name: String = str(data.get("display_name", "player"))
	if player_id.is_empty() or match_id.is_empty():
		return _reject(OnlineProtocol.RejectReason.BAD_TOKEN)
	if not expected_match_id.is_empty() and match_id != expected_match_id:
		return _reject(OnlineProtocol.RejectReason.TICKET_MISMATCH)
	if not expected_instance_id.is_empty() and instance_id != expected_instance_id:
		return _reject(OnlineProtocol.RejectReason.TICKET_MISMATCH)
	return _ok(player_id, display_name, match_id, instance_id)
