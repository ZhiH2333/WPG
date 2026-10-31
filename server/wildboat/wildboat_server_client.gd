extends Node
class_name WildboatServerClient

## Dedicated Server → WildBoat server-to-server HTTPS 客户端。
## 凭证来自环境变量，绝不写入客户端包、不记日志。
##
## 认证方式（草案，待 Agent A 确认）：
##   Authorization: Bearer <WPG_WILDBOAT_SERVER_TOKEN>
## 或
##   X-WPG-Server-Token: <token>

const PATH_VALIDATE := "/v1/server/tickets/validate"
const PATH_SETTLEMENT_FMT := "/v1/server/matches/%s/settlement"

var http: WildboatHttpClient = null
var server_token: String = ""
var auth_header_mode: String = "bearer" ## bearer | x_header


func _ready() -> void:
	if http == null:
		http = WildboatHttpClient.new()
		http.name = "WildboatHttpClient"
		http.user_agent = "WPG-DedicatedServer/0.3"
		add_child(http)


func configure(base_url: String, token: String, timeout_sec: float = 5.0) -> void:
	_ready_if_needed()
	http.configure(base_url, timeout_sec)
	server_token = token


func validate_ticket(body: Dictionary, timeout_sec: float = 5.0) -> Dictionary:
	_ready_if_needed()
	if server_token.is_empty():
		var err := WildboatError.from_transport("missing_server_token")
		err.code = "SERVER_AUTH_MISSING"
		return {"ok": false, "status": 0, "body": null, "error": err}
	return await http.request_json_await(
		"POST",
		PATH_VALIDATE,
		body,
		_bearer_or_empty(),
		timeout_sec,
		_extra_headers()
	)


func submit_settlement(match_id: String, payload: Dictionary, idempotency_key: String, timeout_sec: float = 10.0) -> Dictionary:
	_ready_if_needed()
	if server_token.is_empty():
		var err := WildboatError.from_transport("missing_server_token")
		err.code = "SERVER_AUTH_MISSING"
		return {"ok": false, "status": 0, "body": null, "error": err}
	var path: String = PATH_SETTLEMENT_FMT % match_id.uri_encode()
	var headers := _extra_headers()
	if not idempotency_key.is_empty():
		headers.append("Idempotency-Key: %s" % idempotency_key)
	return await http.request_json_await(
		"POST",
		path,
		payload,
		_bearer_or_empty(),
		timeout_sec,
		headers
	)


func _bearer_or_empty() -> String:
	if auth_header_mode == "bearer":
		return server_token
	return ""


func _extra_headers() -> PackedStringArray:
	var headers := PackedStringArray()
	if auth_header_mode == "x_header":
		headers.append("X-WPG-Server-Token: %s" % server_token)
	return headers


func _ready_if_needed() -> void:
	if http == null:
		_ready()
