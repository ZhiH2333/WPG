extends RefCounted
class_name MatchAssignment

## WildBoat Match Assignment DTO（契约：WildBoat/docs/phase-2b-api-contract.md）。
## 生产响应为扁平字段；仍兼容旧草案的 endpoint 嵌套对象。

var match_id: String = ""
var game_instance_id: String = ""
var server_id: String = ""
var host: String = ""
var port: int = OnlineProtocol.DEFAULT_PORT
var transport: String = "enet_udp"
var game_ticket: String = ""
var ticket_expires_at: String = ""
var protocol_version: int = OnlineProtocol.PROTOCOL_VERSION
var server_build: String = ""
var mode: String = ""
var source: String = "wildboat" ## wildboat | local_stub


func is_valid() -> bool:
	return (
		not match_id.is_empty()
		and not game_instance_id.is_empty()
		and not host.is_empty()
		and port > 0
		and not game_ticket.is_empty()
	)


func ticket_expired(now_unix: int = -1) -> bool:
	if ticket_expires_at.is_empty():
		return false
	var exp: int = AuthSession._parse_rfc3339_unix(ticket_expires_at)
	if exp <= 0:
		return false
	var now: int = now_unix if now_unix >= 0 else int(Time.get_unix_time_from_system())
	return now >= exp


static func from_payload(payload: Dictionary) -> MatchAssignment:
	var out := MatchAssignment.new()
	out.match_id = str(payload.get("match_id", ""))
	out.game_instance_id = str(payload.get("game_instance_id", ""))
	out.server_id = str(payload.get("server_id", ""))
	out.game_ticket = str(payload.get("game_ticket", ""))
	out.ticket_expires_at = str(payload.get("ticket_expires_at", ""))
	out.protocol_version = int(payload.get("protocol_version", OnlineProtocol.PROTOCOL_VERSION))
	out.server_build = str(payload.get("server_build", ""))
	out.mode = str(payload.get("mode", ""))
	## 扁平字段优先（Phase 2B 冻结契约）。
	if str(payload.get("host", "")) != "":
		out.host = str(payload.get("host", ""))
		out.port = int(payload.get("port", OnlineProtocol.DEFAULT_PORT))
		out.transport = str(payload.get("transport", "enet_udp"))
	else:
		var endpoint: Variant = payload.get("endpoint", {})
		if typeof(endpoint) == TYPE_DICTIONARY:
			var ep: Dictionary = endpoint
			out.host = str(ep.get("host", ""))
			out.port = int(ep.get("port", OnlineProtocol.DEFAULT_PORT))
			out.transport = str(ep.get("transport", "enet_udp"))
	return out


func to_safe_dict() -> Dictionary:
	## 不含 game_ticket。
	return {
		"match_id": match_id,
		"game_instance_id": game_instance_id,
		"server_id": server_id,
		"host": host,
		"port": port,
		"transport": transport,
		"ticket_expires_at": ticket_expires_at,
		"protocol_version": protocol_version,
		"server_build": server_build,
		"mode": mode,
		"source": source,
	}
