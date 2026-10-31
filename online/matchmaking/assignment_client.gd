extends RefCounted
class_name AssignmentClient

## Online Assignment 请求。
##
## 生产路径：`POST /v1/matchmaking/quick`（WildBoat 契约草案；**Agent A 尚未实现**）。
## 本地联调：`mode=local_stub` 返回指向本机 DS 的 stub assignment（非生产 API）。

const PATH_QUICK := "/v1/matchmaking/quick"

var auth: AuthSession = null
var mode: String = "wildboat" ## wildboat | local_stub
var stub_host: String = "127.0.0.1"
var stub_port: int = OnlineProtocol.DEFAULT_PORT
## 与 ServerConfig 默认 match/instance 对齐，便于 `WPG_ADMISSION_MODE=stub` 本地联调。
var stub_match_id: String = "dev_match"
var stub_instance_id: String = "dev_instance"
var _inflight: bool = false


func request_assignment(game_mode: String = "coop_survival", region: String = "auto") -> Dictionary:
	if _inflight:
		var busy := WildboatError.from_transport("assignment_in_progress")
		busy.code = "BUSY"
		return {"ok": false, "status": 0, "body": null, "error": busy, "assignment": null}
	_inflight = true
	var result: Dictionary
	if mode == "local_stub":
		result = _local_stub(game_mode)
	else:
		result = await _wildboat_quick(game_mode, region)
	_inflight = false
	return result


func _wildboat_quick(game_mode: String, region: String) -> Dictionary:
	if auth == null or not auth.is_authenticated():
		var err := WildboatError.from_transport("not_authenticated")
		err.code = "AUTH_REQUIRED"
		return {"ok": false, "status": 401, "body": null, "error": err, "assignment": null}
	var body: Dictionary = {
		"mode": game_mode,
		"region": region,
	}
	var res: Dictionary = await auth.authed_request("POST", PATH_QUICK, body)
	if not bool(res.get("ok", false)):
		res["assignment"] = null
		return res
	var payload: Variant = res.get("body")
	if typeof(payload) != TYPE_DICTIONARY:
		var err2 := WildboatError.from_transport("invalid_assignment_body")
		err2.code = "INVALID_ASSIGNMENT"
		return {"ok": false, "status": 502, "body": payload, "error": err2, "assignment": null}
	var assignment: MatchAssignment = MatchAssignment.from_payload(payload)
	assignment.source = "wildboat"
	if not assignment.is_valid():
		var err3 := WildboatError.from_transport("incomplete_assignment")
		err3.code = "INVALID_ASSIGNMENT"
		return {"ok": false, "status": 502, "body": payload, "error": err3, "assignment": null}
	if assignment.ticket_expired():
		var err4 := WildboatError.from_transport("ticket_already_expired")
		err4.code = "TICKET_EXPIRED"
		return {"ok": false, "status": 409, "body": payload, "error": err4, "assignment": null}
	res["assignment"] = assignment
	return res


func _local_stub(_game_mode: String) -> Dictionary:
	## 仅本地联调：签发 stub ticket，供 DS admission_mode=stub 验证。
	## 格式与生产 game_ticket 无关；不得用于生产。
	if auth == null or not auth.is_authenticated():
		var err := WildboatError.from_transport("not_authenticated")
		err.code = "AUTH_REQUIRED"
		return {"ok": false, "status": 401, "body": null, "error": err, "assignment": null}
	var identity: PlayerIdentity = auth.get_identity()
	var exp_unix: int = int(Time.get_unix_time_from_system()) + 120
	var nonce: String = str(Time.get_ticks_msec())
	var ticket: String = StubTicketCodec.issue(
		identity.player_id,
		identity.display_name,
		stub_match_id,
		stub_instance_id,
		exp_unix,
		nonce
	)
	var assignment := MatchAssignment.new()
	assignment.match_id = stub_match_id
	assignment.game_instance_id = stub_instance_id
	assignment.host = stub_host
	assignment.port = stub_port
	assignment.transport = "enet_udp"
	assignment.game_ticket = ticket
	assignment.ticket_expires_at = AuthSession._unix_to_rfc3339(exp_unix)
	assignment.protocol_version = OnlineProtocol.PROTOCOL_VERSION
	assignment.server_build = "local-stub"
	assignment.source = "local_stub"
	return {
		"ok": true,
		"status": 200,
		"body": assignment.to_safe_dict(),
		"error": null,
		"assignment": assignment,
	}
