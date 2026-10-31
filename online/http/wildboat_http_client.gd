extends Node
class_name WildboatHttpClient

## WildBoat HTTPS JSON 客户端封装。
## - 统一超时、请求 ID、Authorization、错误信封解析
## - 不记录 access/refresh/password/ticket
## - 不新增 Autoload：由 AuthSession / AssignmentClient / DS 侧 ServerClient 持有

signal request_finished(request_id: String, ok: bool, status: int, body: Variant, error: WildboatError)

const DEFAULT_TIMEOUT_SEC: float = 15.0
const MAX_BODY_BYTES: int = 1 << 20

var base_url: String = "http://127.0.0.1:8080"
var default_timeout_sec: float = DEFAULT_TIMEOUT_SEC
var user_agent: String = "WPG-Client/0.3"

var _http: HTTPRequest
var _inflight: Dictionary = {} ## request_id -> meta
var _results: Dictionary = {} ## request_id -> {ok,status,body,error}
var _queue: Array = [] ## pending when HTTPRequest is busy
var _busy: bool = false
var _seq: int = 0


func _ready() -> void:
	_ensure_http()


func configure(p_base_url: String, timeout_sec: float = DEFAULT_TIMEOUT_SEC) -> void:
	base_url = p_base_url.strip_edges().trim_suffix("/")
	default_timeout_sec = maxf(1.0, timeout_sec)


func cancel_all() -> void:
	_queue.clear()
	if _http != null:
		_http.cancel_request()
	for rid in _inflight.keys():
		var meta: Dictionary = _inflight[rid]
		var err := WildboatError.from_transport("cancelled", true)
		request_finished.emit(str(rid), false, 0, null, err)
		_complete_waiter(meta, false, 0, null, err)
	_inflight.clear()
	_busy = false


## 发起 JSON 请求。返回 request_id；结果通过 await wait_for(request_id) 或信号取得。
func request_json(
	method: String,
	path: String,
	body: Variant = null,
	access_token: String = "",
	timeout_sec: float = -1.0,
	extra_headers: PackedStringArray = PackedStringArray()
) -> String:
	_ensure_http()
	_seq += 1
	var request_id: String = "wb_%d_%d" % [Time.get_ticks_msec(), _seq]
	var meta: Dictionary = {
		"request_id": request_id,
		"method": method.to_upper(),
		"path": path,
		"body": body,
		"access_token": access_token,
		"timeout_sec": default_timeout_sec if timeout_sec < 0.0 else timeout_sec,
		"extra_headers": extra_headers,
		"waiter": null,
	}
	_queue.append(meta)
	_pump()
	return request_id


## 等待指定 request_id 完成。返回 {ok, status, body, error}。
func wait_for(request_id: String) -> Dictionary:
	return await _wait_via_meta(request_id)


func request_json_await(
	method: String,
	path: String,
	body: Variant = null,
	access_token: String = "",
	timeout_sec: float = -1.0,
	extra_headers: PackedStringArray = PackedStringArray()
) -> Dictionary:
	var rid: String = request_json(method, path, body, access_token, timeout_sec, extra_headers)
	return await _wait_via_meta(rid)


func _wait_via_meta(request_id: String) -> Dictionary:
	if _results.has(request_id):
		return _results[request_id]
	var tree := get_tree()
	if tree == null:
		return {
			"ok": false,
			"status": 0,
			"body": null,
			"error": WildboatError.from_transport("not_in_tree"),
		}
	var known: bool = _inflight.has(request_id) or _queued(request_id)
	if not known and not _results.has(request_id):
		## 可能尚在入队当帧；短暂等待。
		for _i in 3:
			await tree.process_frame
			if _results.has(request_id) or _inflight.has(request_id) or _queued(request_id):
				known = true
				break
	if not known and not _results.has(request_id):
		return {
			"ok": false,
			"status": 0,
			"body": null,
			"error": WildboatError.from_transport("unknown_request"),
		}
	while not _results.has(request_id):
		await tree.process_frame
	return _results[request_id]


func _queued(request_id: String) -> bool:
	for item in _queue:
		if str((item as Dictionary).get("request_id", "")) == request_id:
			return true
	return false


func _ensure_http() -> void:
	if _http != null:
		return
	_http = HTTPRequest.new()
	_http.name = "HTTPRequest"
	_http.timeout = default_timeout_sec
	_http.request_completed.connect(_on_request_completed)
	add_child(_http)


func _pump() -> void:
	if _busy or _queue.is_empty():
		return
	_ensure_http()
	var meta: Dictionary = _queue.pop_front()
	var request_id: String = str(meta["request_id"])
	_inflight[request_id] = meta
	_busy = true
	var timeout_sec: float = float(meta["timeout_sec"])
	_http.timeout = timeout_sec
	var url: String = base_url + str(meta["path"])
	var headers: PackedStringArray = PackedStringArray()
	headers.append("Content-Type: application/json; charset=utf-8")
	headers.append("Accept: application/json")
	headers.append("User-Agent: %s" % user_agent)
	headers.append("X-Request-ID: %s" % request_id)
	var token: String = str(meta.get("access_token", ""))
	if not token.is_empty():
		headers.append("Authorization: Bearer %s" % token)
	var extra: PackedStringArray = meta.get("extra_headers", PackedStringArray())
	for h in extra:
		headers.append(str(h))
	var body_text: String = ""
	var body_var: Variant = meta.get("body", null)
	if body_var != null:
		body_text = JSON.stringify(body_var)
	var method_enum: int = _method_enum(str(meta["method"]))
	var err: Error = _http.request(url, headers, method_enum, body_text)
	if err != OK:
		_busy = false
		_inflight.erase(request_id)
		var wb_err := WildboatError.from_transport("http_request_failed:%s" % error_string(err))
		request_finished.emit(request_id, false, 0, null, wb_err)
		_complete_waiter(meta, false, 0, null, wb_err)
		_pump()


func _on_request_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	_busy = false
	var request_id: String = ""
	var meta: Dictionary = {}
	## HTTPRequest 同时只跑一个；取唯一 inflight。
	if _inflight.size() == 1:
		request_id = str(_inflight.keys()[0])
		meta = _inflight[request_id]
		_inflight.erase(request_id)
	elif not _inflight.is_empty():
		request_id = str(_inflight.keys()[0])
		meta = _inflight[request_id]
		_inflight.erase(request_id)
	if meta.is_empty():
		_pump()
		return
	if result == HTTPRequest.RESULT_REQUEST_FAILED \
		or result == HTTPRequest.RESULT_CANT_CONNECT \
		or result == HTTPRequest.RESULT_CANT_RESOLVE \
		or result == HTTPRequest.RESULT_CONNECTION_ERROR \
		or result == HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR \
		or result == HTTPRequest.RESULT_NO_RESPONSE \
		or result == HTTPRequest.RESULT_BODY_SIZE_LIMIT_EXCEEDED \
		or result == HTTPRequest.RESULT_TIMEOUT \
		or result == HTTPRequest.RESULT_REDIRECT_LIMIT_REACHED:
		var transport := WildboatError.from_transport("http_result_%d" % result)
		request_finished.emit(request_id, false, response_code, null, transport)
		_complete_waiter(meta, false, response_code, null, transport)
		_pump()
		return
	if body.size() > MAX_BODY_BYTES:
		var too_big := WildboatError.from_transport("body_too_large")
		request_finished.emit(request_id, false, response_code, null, too_big)
		_complete_waiter(meta, false, response_code, null, too_big)
		_pump()
		return
	var text: String = body.get_string_from_utf8()
	var parsed: Variant = null
	if not text.is_empty():
		parsed = JSON.parse_string(text)
	var header_rid: String = _header_value(headers, "X-Request-ID")
	var ok: bool = response_code >= 200 and response_code < 300
	if ok:
		request_finished.emit(request_id, true, response_code, parsed, null)
		_complete_waiter(meta, true, response_code, parsed, null)
	else:
		var wb_err := WildboatError.from_http(response_code, parsed, header_rid)
		request_finished.emit(request_id, false, response_code, parsed, wb_err)
		_complete_waiter(meta, false, response_code, parsed, wb_err)
	_pump()


func _complete_waiter(meta: Dictionary, ok: bool, status: int, body: Variant, error: WildboatError) -> void:
	var result: Dictionary = {
		"ok": ok,
		"status": status,
		"body": body,
		"error": error,
	}
	meta["result"] = result
	var rid: String = str(meta.get("request_id", ""))
	if not rid.is_empty():
		_results[rid] = result


func _method_enum(method: String) -> int:
	match method:
		"GET":
			return HTTPClient.METHOD_GET
		"POST":
			return HTTPClient.METHOD_POST
		"PATCH":
			return HTTPClient.METHOD_PATCH
		"PUT":
			return HTTPClient.METHOD_PUT
		"DELETE":
			return HTTPClient.METHOD_DELETE
		_:
			return HTTPClient.METHOD_GET


func _header_value(headers: PackedStringArray, key: String) -> String:
	var needle: String = key.to_lower() + ":"
	for line in headers:
		var lower: String = line.to_lower()
		if lower.begins_with(needle):
			return line.substr(line.find(":") + 1).strip_edges()
	return ""
