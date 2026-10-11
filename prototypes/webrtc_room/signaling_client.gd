extends RefCounted

## 房间码信令的 HTTP 客户端。不是 MultiplayerPeer，不占用 SceneTree。

signal completed(op: String, http_status: int, payload: Dictionary, error: String)

const REQUEST_TIMEOUT_MS: int = 8000

var _host: String = ""
var _port: int = 0
var _http: HTTPClient = null
var _phase: String = "idle"
var _op: String = ""
var _method: int = HTTPClient.METHOD_GET
var _path: String = ""
var _payload: String = ""
var _headers_value: PackedStringArray = PackedStringArray()
var _body: PackedByteArray = PackedByteArray()
var _sent: bool = false
var _response_code: int = 0
var _started_ms: int = 0

func setup(base_url: String) -> bool:
	var parsed: String = base_url.strip_edges()
	if parsed.begins_with("http://"):
		parsed = parsed.substr(7)
	else:
		return false
	var slash: int = parsed.find("/")
	if slash >= 0:
		parsed = parsed.substr(0, slash)
	var colon: int = parsed.rfind(":")
	if colon <= 0:
		return false
	_host = parsed.substr(0, colon)
	_port = parsed.substr(colon + 1).to_int()
	return _port > 0 and _port <= 65535 and _host != ""

func is_busy() -> bool:
	return _phase != "idle"

func create_room() -> bool:
	return _begin("create", HTTPClient.METHOD_POST, "/v1/rooms", "{}")

func join_room(code: String) -> bool:
	return _begin("join", HTTPClient.METHOD_POST, "/v1/rooms/%s/join" % code, "{}")

func post_signal(code: String, token: String, fields: Dictionary) -> bool:
	return _begin("post", HTTPClient.METHOD_POST, "/v1/rooms/%s/signals" % code, JSON.stringify(fields), token)

func get_signals(code: String, token: String, after: int) -> bool:
	return _begin("get", HTTPClient.METHOD_GET, "/v1/rooms/%s/signals?after=%d" % [code, after], "", token)

func poll() -> void:
	if _phase == "idle" or _http == null:
		return
	if Time.get_ticks_msec() - _started_ms > REQUEST_TIMEOUT_MS:
		_fail("HTTP_TIMEOUT")
		return
	_http.poll()
	var status: int = _http.get_status()
	if status == HTTPClient.STATUS_RESOLVING or status == HTTPClient.STATUS_CONNECTING or status == HTTPClient.STATUS_REQUESTING:
		return
	if status == HTTPClient.STATUS_CANT_RESOLVE or status == HTTPClient.STATUS_CANT_CONNECT or status == HTTPClient.STATUS_CONNECTION_ERROR or status == HTTPClient.STATUS_TLS_HANDSHAKE_ERROR:
		_fail("HTTP_CONNECT")
		return
	if status == HTTPClient.STATUS_CONNECTED:
		_on_connected()
		return
	if status == HTTPClient.STATUS_BODY:
		_on_body()
		return
	if status == HTTPClient.STATUS_DISCONNECTED:
		_on_disconnected()

func _begin(op: String, method: int, path: String, payload: String, token: String = "") -> bool:
	if _phase != "idle":
		return false
	_op = op
	_method = method
	_path = path
	_payload = payload
	_headers_value = _headers(token, payload.to_utf8_buffer().size())
	_body = PackedByteArray()
	_sent = false
	_response_code = 0
	_started_ms = Time.get_ticks_msec()
	_http = HTTPClient.new()
	var err: Error = _http.connect_to_host(_host, _port)
	if err != OK:
		_http = null
		return false
	_phase = "connect"
	return true

func _headers(token: String, length: int) -> PackedStringArray:
	var headers: PackedStringArray = PackedStringArray([
		"Host: %s:%d" % [_host, _port],
		"Content-Type: application/json",
		"Connection: close",
		"Content-Length: %d" % length,
	])
	if token != "":
		headers.append("X-Room-Token: %s" % token)
	return headers

func _on_connected() -> void:
	if _sent:
		if _http.has_response():
			_response_code = _http.get_response_code()
			_succeed()
		return
	var err: Error = _http.request(_method, _path, _headers_value, _payload)
	if err != OK:
		_fail("HTTP_REQUEST")
		return
	_sent = true

func _on_body() -> void:
	if _response_code == 0 and _http.has_response():
		_response_code = _http.get_response_code()
	var chunk: PackedByteArray = _http.read_response_body_chunk()
	if chunk.size() > 0:
		_body.append_array(chunk)
	if _http.get_status() != HTTPClient.STATUS_BODY:
		_succeed()

func _on_disconnected() -> void:
	if not _sent:
		_fail("HTTP_DISCONNECTED")
		return
	if _response_code == 0 and _http.has_response():
		_response_code = _http.get_response_code()
	if _response_code == 0 and _body.is_empty():
		_fail("HTTP_DISCONNECTED")
		return
	_succeed()

func _succeed() -> void:
	var payload: Dictionary = {}
	var error: String = ""
	if _body.size() > 0:
		var parsed: Variant = JSON.parse_string(_body.get_string_from_utf8())
		if typeof(parsed) != TYPE_DICTIONARY:
			error = "BAD_JSON"
		else:
			payload = parsed
			error = str(payload.get("error", ""))
	var op: String = _op
	var status: int = _response_code
	_reset()
	completed.emit(op, status, payload, error)

func _fail(error: String) -> void:
	var op: String = _op
	_reset()
	completed.emit(op, 0, {}, error)

func _reset() -> void:
	_phase = "idle"
	_http = null
	_sent = false
	_payload = ""
	_body = PackedByteArray()
