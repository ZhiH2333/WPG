extends SceneTree

## WildBoat WPass Auth 客户端测试（需本机 WildBoat :8080）。
## 跑法：godot --headless --path . --script res://tests/unit/wildboat_auth_test.gd
## 无后端时输出 WILDBOAT_AUTH_SKIP 并以 0 退出（不把环境缺失当失败）。

var _failures: PackedStringArray = PackedStringArray()
var _auth: AuthSession


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if not await _backend_up():
		print("WILDBOAT_AUTH_SKIP")
		quit(0)
		return
	_auth = AuthSession.new()
	root.add_child(_auth)
	_auth.configure("http://127.0.0.1:8080")
	await process_frame
	await _case_register_verify_login_me_refresh_logout()
	await _case_login_failure()
	await _case_unverified_login()
	_case_credentials_store_not_secure()
	_finish()


func _backend_up() -> bool:
	var http := HTTPRequest.new()
	root.add_child(http)
	http.timeout = 2.0
	var err: Error = http.request("http://127.0.0.1:8080/healthz")
	if err != OK:
		http.queue_free()
		return false
	var result: Array = await http.request_completed
	http.queue_free()
	return int(result[1]) == 200


func _case_register_verify_login_me_refresh_logout() -> void:
	var email: String = "wpg_auth_%d@example.com" % Time.get_unix_time_from_system()
	var password: String = "TestPass123!ok"
	var reg: Dictionary = await _auth.register(email, password, "AuthPilot")
	_expect(bool(reg.get("ok", false)), "register ok")
	var body: Dictionary = reg.get("body") as Dictionary
	_expect(body != null and body.has("dev_verification_token"), "dev verification token present")
	var token: String = str(body.get("dev_verification_token", ""))
	var ver: Dictionary = await _auth.verify_email(token)
	_expect(bool(ver.get("ok", false)), "verify ok")
	var login: Dictionary = await _auth.login(email, password)
	_expect(bool(login.get("ok", false)), "login ok")
	_expect(_auth.is_authenticated(), "authenticated after login")
	var me: Dictionary = await _auth.fetch_me()
	_expect(bool(me.get("ok", false)), "me ok")
	var old_access: String = _auth.get_access_token()
	var refreshed: Dictionary = await _auth.refresh_tokens()
	_expect(bool(refreshed.get("ok", false)), "refresh ok")
	_expect(_auth.get_access_token() != old_access and not _auth.get_access_token().is_empty(), "access rotated")
	var logout: Dictionary = await _auth.logout()
	_expect(bool(logout.get("ok", false)), "logout ok")
	_expect(not _auth.is_authenticated(), "not authenticated after logout")
	var me2: Dictionary = await _auth.fetch_me()
	_expect(not bool(me2.get("ok", false)), "me fails after logout")


func _case_login_failure() -> void:
	var res: Dictionary = await _auth.login("missing_%d@example.com" % Time.get_unix_time_from_system(), "bad")
	_expect(not bool(res.get("ok", false)), "bad login fails")
	var err: WildboatError = res.get("error") as WildboatError
	_expect(err != null and err.code == "AUTH_INVALID_CREDENTIALS", "invalid credentials code")


func _case_unverified_login() -> void:
	var email: String = "wpg_unverified_%d@example.com" % Time.get_unix_time_from_system()
	var password: String = "TestPass123!ok"
	var reg: Dictionary = await _auth.register(email, password, "Unverified")
	_expect(bool(reg.get("ok", false)), "unverified register")
	var login: Dictionary = await _auth.login(email, password)
	_expect(not bool(login.get("ok", false)), "unverified login blocked")
	var err: WildboatError = login.get("error") as WildboatError
	_expect(err != null and err.code == "ACCOUNT_NOT_VERIFIED", "ACCOUNT_NOT_VERIFIED")


func _case_credentials_store_not_secure() -> void:
	_expect(not _auth.credentials_storage_is_secure(), "storage not claimed secure")


func _expect(cond: bool, label: String) -> void:
	if not cond:
		_failures.append(label)


func _finish() -> void:
	if _failures.is_empty():
		print("WILDBOAT_AUTH_OK")
		quit(0)
		return
	for failure: String in _failures:
		printerr("WILDBOAT_AUTH_FAIL: %s" % failure)
	quit(1)
