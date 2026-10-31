extends TicketValidator
class_name WildboatTicketValidator

## 在线校验：DS -> WildBoat `POST /v1/server/tickets/validate`。
## 契约：WildBoat/docs/phase-2b-api-contract.md（opaque + 一次性消费）。
## WildBoat 不可达 / 超时 → fail closed（BACKEND_UNAVAILABLE）。
## 身份以响应中的 player_id 为准；客户端 claimed_player_id 仅用于绑定校验请求。
##
## 超时语义：若请求已发出但响应超时，**不得重试同一 ticket**（可能已消费）；
## 拒绝入场，玩家需重新 Assignment 获取新票。

var server_client: WildboatServerClient = null
var timeout_sec: float = WildboatServerClient.VALIDATE_TIMEOUT_SEC


func _init(p_client: WildboatServerClient = null, _p_build: String = "") -> void:
	server_client = p_client


func validate(_ticket: String, _expected_match_id: String, _expected_instance_id: String) -> Dictionary:
	## 同步门面：在线校验必须走 validate_async，避免假成功。
	return _reject(OnlineProtocol.RejectReason.BACKEND_UNAVAILABLE)


func validate_async(
	ticket: String,
	expected_match_id: String,
	expected_instance_id: String,
	claimed_player_id: String = ""
) -> Dictionary:
	if server_client == null:
		return _reject(OnlineProtocol.RejectReason.BACKEND_UNAVAILABLE)
	if ticket.strip_edges().is_empty():
		return _reject(OnlineProtocol.RejectReason.BAD_TOKEN)
	if claimed_player_id.strip_edges().is_empty():
		## 契约要求 validate 绑定 player_id；无声明则拒绝（不猜测身份）。
		return _reject(OnlineProtocol.RejectReason.MALFORMED)
	if expected_match_id.strip_edges().is_empty() or expected_instance_id.strip_edges().is_empty():
		return _reject(OnlineProtocol.RejectReason.MALFORMED)
	var body: Dictionary = {
		"game_ticket": ticket,
		"player_id": claimed_player_id.strip_edges(),
		"match_id": expected_match_id.strip_edges(),
		"game_instance_id": expected_instance_id.strip_edges(),
	}
	## 单次请求；超时/传输失败不重试（防双消费与假放行）。
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
				"TICKET_REVOKED", "TICKET_INVALID", "TICKET_MISMATCH", "MATCH_MISMATCH", "INSTANCE_MISMATCH":
					return _reject(OnlineProtocol.RejectReason.TICKET_MISMATCH)
				"SERVER_AUTH_INVALID", "SERVER_AUTH_MISSING", "FORBIDDEN":
					return _reject(OnlineProtocol.RejectReason.BACKEND_UNAVAILABLE)
				_:
					return _reject(OnlineProtocol.RejectReason.BAD_TOKEN)
		return _reject(OnlineProtocol.RejectReason.BAD_TOKEN)
	var payload: Variant = res.get("body")
	if typeof(payload) != TYPE_DICTIONARY:
		return _reject(OnlineProtocol.RejectReason.BAD_TOKEN)
	var data: Dictionary = payload
	if data.has("valid") and not bool(data.get("valid", false)):
		return _reject(OnlineProtocol.RejectReason.BAD_TOKEN)
	## 权威身份来自 WildBoat，不采用客户端 claimed_player_id。
	var player_id: String = str(data.get("player_id", ""))
	var match_id: String = str(data.get("match_id", ""))
	var instance_id: String = str(data.get("game_instance_id", expected_instance_id))
	if player_id.is_empty() or match_id.is_empty():
		return _reject(OnlineProtocol.RejectReason.BAD_TOKEN)
	if match_id != expected_match_id:
		return _reject(OnlineProtocol.RejectReason.TICKET_MISMATCH)
	if not expected_instance_id.is_empty() and instance_id != expected_instance_id:
		return _reject(OnlineProtocol.RejectReason.TICKET_MISMATCH)
	var display_name: String = str(data.get("display_name", ""))
	if display_name.is_empty():
		display_name = "player"
	return _ok(player_id, display_name, match_id, instance_id)
