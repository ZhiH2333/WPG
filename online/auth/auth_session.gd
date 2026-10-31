extends Node
class_name AuthSession

## WPass 会话：注册 / 登录 / 刷新 / 登出 / 恢复。
## - 单飞 refresh：并发请求共享同一次 refresh，避免旋转竞态
## - 不把 password / token 打进日志
## - 不向 Dedicated Server 发送 access/refresh token

signal logged_in(identity: PlayerIdentity)
signal logged_out
signal auth_error(error: WildboatError)
signal identity_updated(identity: PlayerIdentity)

var http: WildboatHttpClient = null
var store: AuthCredentialsStore = null

var _access_token: String = ""
var _refresh_token: String = ""
var _session_id: String = ""
var _access_expires_at_unix: int = 0
var _refresh_expires_at_unix: int = 0
var _identity: PlayerIdentity = null
var _refresh_inflight: bool = false
var _refresh_waiters: Array = [] ## Array of Dictionary results slots
var _busy_login: bool = false


func _ready() -> void:
	_ensure_deps()


func configure(base_url: String, timeout_sec: float = WildboatHttpClient.DEFAULT_TIMEOUT_SEC) -> void:
	_ensure_deps()
	http.configure(base_url, timeout_sec)


func is_authenticated() -> bool:
	return not _access_token.is_empty() and _identity != null and _identity.is_logged_in_identity()


func get_identity() -> PlayerIdentity:
	return _identity


func get_access_token() -> String:
	return _access_token


func get_session_id() -> String:
	return _session_id


func credentials_storage_is_secure() -> bool:
	_ready_if_needed()
	return store.storage_is_secure()


func register(email: String, password: String, display_name: String) -> Dictionary:
	_ready_if_needed()
	var body: Dictionary = {
		"email": email.strip_edges(),
		"password": password,
		"display_name": display_name.strip_edges(),
	}
	var res: Dictionary = await http.request_json_await("POST", "/v1/auth/register", body)
	if not bool(res.get("ok", false)):
		_emit_err(res.get("error") as WildboatError)
		return res
	return res


func verify_email(token: String) -> Dictionary:
	_ready_if_needed()
	var res: Dictionary = await http.request_json_await(
		"POST", "/v1/auth/email/verify", {"token": token.strip_edges()}
	)
	if not bool(res.get("ok", false)):
		_emit_err(res.get("error") as WildboatError)
	return res


func login(email: String, password: String) -> Dictionary:
	_ready_if_needed()
	if _busy_login:
		var err := WildboatError.from_transport("login_in_progress")
		err.code = "BUSY"
		return {"ok": false, "status": 0, "body": null, "error": err}
	_busy_login = true
	var res: Dictionary = await http.request_json_await(
		"POST",
		"/v1/auth/login",
		{"email": email.strip_edges(), "password": password}
	)
	_busy_login = false
	if not bool(res.get("ok", false)):
		_emit_err(res.get("error") as WildboatError)
		return res
	_apply_login_body(res.get("body"))
	if is_authenticated():
		_persist()
		logged_in.emit(_identity)
	return res


func logout() -> Dictionary:
	_ready_if_needed()
	var res: Dictionary = {"ok": true, "status": 200, "body": {"ok": true}, "error": null}
	if not _access_token.is_empty():
		res = await http.request_json_await("POST", "/v1/auth/logout", null, _access_token)
	_clear_memory()
	store.clear()
	logged_out.emit()
	return res


func fetch_me() -> Dictionary:
	_ready_if_needed()
	var token_res: Dictionary = await ensure_access_token()
	if not bool(token_res.get("ok", false)):
		return token_res
	var res: Dictionary = await http.request_json_await("GET", "/v1/me", null, _access_token)
	if not bool(res.get("ok", false)):
		var err: WildboatError = res.get("error") as WildboatError
		if err != null and err.code == "AUTH_SESSION_EXPIRED":
			## 尝试一次 refresh 后重试。
			var refreshed: Dictionary = await refresh_tokens()
			if bool(refreshed.get("ok", false)):
				res = await http.request_json_await("GET", "/v1/me", null, _access_token)
	if bool(res.get("ok", false)):
		var body: Variant = res.get("body")
		if typeof(body) == TYPE_DICTIONARY:
			_identity = PlayerIdentity.from_me_payload(body)
			identity_updated.emit(_identity)
	else:
		_emit_err(res.get("error") as WildboatError)
	return res


## 恢复本地 refresh 会话。成功则发出 logged_in。
func restore_session() -> Dictionary:
	_ready_if_needed()
	var saved: Dictionary = store.load_session()
	if saved.is_empty():
		return {"ok": false, "status": 0, "body": null, "error": WildboatError.from_transport("no_saved_session")}
	var saved_base: String = str(saved.get("base_url", ""))
	if not saved_base.is_empty() and saved_base != http.base_url:
		http.configure(saved_base, http.default_timeout_sec)
	_refresh_token = str(saved.get("refresh_token", ""))
	_session_id = str(saved.get("session_id", ""))
	if _refresh_token.is_empty():
		store.clear()
		return {"ok": false, "status": 0, "body": null, "error": WildboatError.from_transport("empty_refresh")}
	var refreshed: Dictionary = await refresh_tokens()
	if bool(refreshed.get("ok", false)) and is_authenticated():
		logged_in.emit(_identity)
	elif not bool(refreshed.get("ok", false)):
		_clear_memory()
		store.clear()
	return refreshed


## 保证 access token 可用；过期则 refresh（单飞）。
func ensure_access_token() -> Dictionary:
	if not _access_token.is_empty() and not _access_expired(30):
		return {"ok": true, "status": 200, "body": null, "error": null}
	if _refresh_token.is_empty():
		var err := WildboatError.from_transport("not_authenticated")
		err.code = "AUTH_REQUIRED"
		return {"ok": false, "status": 401, "body": null, "error": err}
	return await refresh_tokens()


func refresh_tokens() -> Dictionary:
	_ready_if_needed()
	if _refresh_inflight:
		return await _await_refresh_result()
	_refresh_inflight = true
	var res: Dictionary = await http.request_json_await(
		"POST",
		"/v1/auth/refresh",
		{"refresh_token": _refresh_token}
	)
	if bool(res.get("ok", false)):
		_apply_login_body(res.get("body"))
		_persist()
	else:
		var err: WildboatError = res.get("error") as WildboatError
		if err != null and err.code in ["AUTH_SESSION_EXPIRED", "AUTH_REQUIRED", "TOKEN_INVALID"]:
			_clear_memory()
			store.clear()
			logged_out.emit()
		_emit_err(err)
	_refresh_inflight = false
	_resolve_refresh_waiters(res)
	return res


## 已认证请求：自动带 Bearer，遇 401 尝试 refresh 一次后重试。
func authed_request(
	method: String,
	path: String,
	body: Variant = null,
	timeout_sec: float = -1.0,
	extra_headers: PackedStringArray = PackedStringArray()
) -> Dictionary:
	var gate: Dictionary = await ensure_access_token()
	if not bool(gate.get("ok", false)):
		return gate
	var res: Dictionary = await http.request_json_await(
		method, path, body, _access_token, timeout_sec, extra_headers
	)
	if bool(res.get("ok", false)):
		return res
	var err: WildboatError = res.get("error") as WildboatError
	if err != null and (err.http_status == 401 or err.code in ["AUTH_SESSION_EXPIRED", "AUTH_REQUIRED"]):
		var refreshed: Dictionary = await refresh_tokens()
		if bool(refreshed.get("ok", false)):
			return await http.request_json_await(
				method, path, body, _access_token, timeout_sec, extra_headers
			)
	return res


func _apply_login_body(body: Variant) -> void:
	if typeof(body) != TYPE_DICTIONARY:
		return
	var data: Dictionary = body
	var tokens: Variant = data.get("tokens", {})
	if typeof(tokens) == TYPE_DICTIONARY:
		var t: Dictionary = tokens
		_access_token = str(t.get("access_token", ""))
		_refresh_token = str(t.get("refresh_token", ""))
		_session_id = str(t.get("session_id", ""))
		_access_expires_at_unix = _parse_rfc3339_unix(str(t.get("access_expires_at", "")))
		_refresh_expires_at_unix = _parse_rfc3339_unix(str(t.get("refresh_expires_at", "")))
	var me: Variant = data.get("me", {})
	if typeof(me) == TYPE_DICTIONARY:
		_identity = PlayerIdentity.from_me_payload(me)


func _persist() -> void:
	if store == null or _identity == null:
		return
	store.save_session(
		_refresh_token,
		_session_id,
		_unix_to_rfc3339(_refresh_expires_at_unix),
		_identity.account_id,
		_identity.player_id,
		_identity.display_name,
		http.base_url if http != null else ""
	)


func _clear_memory() -> void:
	_access_token = ""
	_refresh_token = ""
	_session_id = ""
	_access_expires_at_unix = 0
	_refresh_expires_at_unix = 0
	_identity = null


func _access_expired(skew_sec: int = 0) -> bool:
	if _access_expires_at_unix <= 0:
		return true
	return Time.get_unix_time_from_system() + skew_sec >= _access_expires_at_unix


func _await_refresh_result() -> Dictionary:
	var slot: Dictionary = {"done": false, "result": {}}
	_refresh_waiters.append(slot)
	while not bool(slot.get("done", false)):
		await get_tree().process_frame
	return slot.get("result", {})


func _resolve_refresh_waiters(res: Dictionary) -> void:
	for slot in _refresh_waiters:
		var d: Dictionary = slot
		d["result"] = res
		d["done"] = true
	_refresh_waiters.clear()


func _emit_err(err: WildboatError) -> void:
	if err != null:
		auth_error.emit(err)


func _ready_if_needed() -> void:
	_ensure_deps()


func _ensure_deps() -> void:
	if store == null:
		store = AuthCredentialsStore.new()
	if http == null:
		http = WildboatHttpClient.new()
		http.name = "WildboatHttpClient"
		if is_inside_tree():
			add_child(http)
		else:
			## 进树后再挂，避免孤儿 HTTPRequest。
			call_deferred("_attach_http")


func _attach_http() -> void:
	if http != null and http.get_parent() == null and is_inside_tree():
		add_child(http)


static func _parse_rfc3339_unix(text: String) -> int:
	## 接受形如 2026-10-31T06:15:00Z / 带小数秒 / 带偏移。失败返回 0。
	var raw: String = text.strip_edges()
	if raw.is_empty():
		return 0
	raw = raw.replace("Z", "+00:00")
	## Godot Time.get_unix_time_from_datetime_string 需要 "YYYY-MM-DDTHH:MM:SS"。
	var core: String = raw
	var plus: int = raw.rfind("+")
	var minus: int = raw.rfind("-")
	## 去掉时区：找 T 之后的 +/-。
	var tpos: int = raw.find("T")
	if tpos >= 0:
		var tz_plus: int = raw.find("+", tpos)
		var tz_minus: int = raw.find("-", tpos + 1)
		var cut: int = -1
		if tz_plus >= 0:
			cut = tz_plus
		elif tz_minus >= 0:
			cut = tz_minus
		if cut >= 0:
			core = raw.substr(0, cut)
	if "." in core:
		core = core.get_slice(".", 0)
	if core.length() < 19:
		return 0
	core = core.substr(0, 19)
	return int(Time.get_unix_time_from_datetime_string(core))


static func _unix_to_rfc3339(unix: int) -> String:
	if unix <= 0:
		return ""
	return Time.get_datetime_string_from_unix_time(unix, true) + "Z"
