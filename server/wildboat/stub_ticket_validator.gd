extends TicketValidator
class_name StubTicketValidator

## 本地 stub ticket 校验 + 重放防护（nonce 消费）。仅测试 / 本地联调。

var _consumed_nonces: Dictionary = {} ## nonce -> true
var allow_replay: bool = false


func validate(ticket: String, expected_match_id: String, expected_instance_id: String) -> Dictionary:
	var parsed: Dictionary = StubTicketCodec.parse(ticket)
	if not bool(parsed.get("ok", false)):
		return _reject(OnlineProtocol.RejectReason.BAD_TOKEN)
	var exp: int = int(parsed.get("expires_at_unix", 0))
	if exp > 0 and int(Time.get_unix_time_from_system()) >= exp:
		return _reject(OnlineProtocol.RejectReason.TICKET_EXPIRED)
	var match_id: String = str(parsed.get("match_id", ""))
	var instance_id: String = str(parsed.get("game_instance_id", ""))
	if not expected_match_id.is_empty() and match_id != expected_match_id:
		return _reject(OnlineProtocol.RejectReason.TICKET_MISMATCH)
	if not expected_instance_id.is_empty() and instance_id != expected_instance_id:
		return _reject(OnlineProtocol.RejectReason.TICKET_MISMATCH)
	var nonce: String = str(parsed.get("nonce", ""))
	if not allow_replay and not nonce.is_empty():
		if _consumed_nonces.has(nonce):
			return _reject(OnlineProtocol.RejectReason.TICKET_REPLAYED)
		_consumed_nonces[nonce] = true
	return _ok(
		str(parsed.get("player_id", "")),
		str(parsed.get("display_name", "player")),
		match_id,
		instance_id
	)


func clear_replay_cache() -> void:
	_consumed_nonces.clear()
