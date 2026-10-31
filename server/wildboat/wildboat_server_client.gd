extends Node
class_name WildboatServerClient

## Dedicated Server → WildBoat server-to-server HTTPS 客户端。
## 凭证来自环境变量（DEDICATED_SERVER_CREDENTIAL），绝不写入客户端包、不记日志。
##
## 认证：Authorization: Bearer <dedicated_server_credential>
## 契约：WildBoat/docs/phase-2b-api-contract.md

const PATH_REGISTER := "/v1/server/instances/register"
const PATH_HEARTBEAT_FMT := "/v1/server/instances/%s/heartbeat"
const PATH_VALIDATE := "/v1/server/tickets/validate"
const PATH_SETTLEMENT_FMT := "/v1/server/matches/%s/settlement"

## 契约推荐：ticket validate 客户端超时 3s。
const VALIDATE_TIMEOUT_SEC: float = 3.0
const DEFAULT_S2S_TIMEOUT_SEC: float = 5.0

var http: WildboatHttpClient = null
var server_token: String = ""


func _ready() -> void:
	if http == null:
		http = WildboatHttpClient.new()
		http.name = "WildboatHttpClient"
		http.user_agent = "WPG-DedicatedServer/0.3"
		add_child(http)


func configure(base_url: String, token: String, timeout_sec: float = DEFAULT_S2S_TIMEOUT_SEC) -> void:
	_ready_if_needed()
	http.configure(base_url, timeout_sec)
	server_token = token


func register_instance(body: Dictionary, timeout_sec: float = DEFAULT_S2S_TIMEOUT_SEC) -> Dictionary:
	return await _s2s_post(PATH_REGISTER, body, timeout_sec)


func heartbeat(game_instance_id: String, body: Dictionary, timeout_sec: float = DEFAULT_S2S_TIMEOUT_SEC) -> Dictionary:
	if game_instance_id.strip_edges().is_empty():
		var err := WildboatError.from_transport("missing_game_instance_id")
		err.code = "INVALID_INPUT"
		return {"ok": false, "status": 0, "body": null, "error": err}
	var path: String = PATH_HEARTBEAT_FMT % game_instance_id.uri_encode()
	return await _s2s_post(path, body, timeout_sec)


func validate_ticket(body: Dictionary, timeout_sec: float = VALIDATE_TIMEOUT_SEC) -> Dictionary:
	## 超时/不可达时调用方必须 fail closed，且不得自动重试（票可能已消费）。
	return await _s2s_post(PATH_VALIDATE, body, timeout_sec)


func submit_settlement(match_id: String, payload: Dictionary, timeout_sec: float = 10.0) -> Dictionary:
	## 幂等键在 payload.settlement_id；重试必须保持同一 settlement_id。
	if match_id.strip_edges().is_empty():
		var err := WildboatError.from_transport("missing_match_id")
		err.code = "INVALID_INPUT"
		return {"ok": false, "status": 0, "body": null, "error": err}
	var path: String = PATH_SETTLEMENT_FMT % match_id.uri_encode()
	return await _s2s_post(path, payload, timeout_sec)


func _s2s_post(path: String, body: Dictionary, timeout_sec: float) -> Dictionary:
	_ready_if_needed()
	if server_token.is_empty():
		var err := WildboatError.from_transport("missing_server_token")
		err.code = "SERVER_AUTH_MISSING"
		return {"ok": false, "status": 0, "body": null, "error": err}
	return await http.request_json_await(
		"POST",
		path,
		body,
		server_token,
		timeout_sec
	)


func _ready_if_needed() -> void:
	if http == null:
		_ready()
