extends SceneTree

## AssignmentClient：未登录拒绝；local_stub 登录后成功；真实 /v1/games/assign（需 DS ready）；BUSY。
## Auth 依赖本机 WildBoat；不可用则 SKIP。

var _failures: PackedStringArray = PackedStringArray()
var _auth: AuthSession


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if not await _backend_up():
		print("ASSIGNMENT_CLIENT_SKIP")
		quit(0)
		return
	_auth = AuthSession.new()
	root.add_child(_auth)
	_auth.configure("http://127.0.0.1:8080")
	await process_frame
	await _case_requires_login()
	await _case_stub_after_login()
	await _case_wildboat_assign_or_unavailable()
	_finish()


func _backend_up() -> bool:
	var http := HTTPRequest.new()
	root.add_child(http)
	http.timeout = 2.0
	if http.request("http://127.0.0.1:8080/healthz") != OK:
		http.queue_free()
		return false
	var result: Array = await http.request_completed
	http.queue_free()
	return int(result[1]) == 200


func _login_fresh() -> void:
	var email: String = "wpg_asg_%d@example.com" % Time.get_unix_time_from_system()
	var password: String = "TestPass123!ok"
	var reg: Dictionary = await _auth.register(email, password, "AsgPilot")
	_expect(bool(reg.get("ok", false)), "register")
	var token: String = str((reg.get("body") as Dictionary).get("dev_verification_token", ""))
	await _auth.verify_email(token)
	var login: Dictionary = await _auth.login(email, password)
	_expect(bool(login.get("ok", false)), "login")


func _case_requires_login() -> void:
	var client := AssignmentClient.new()
	client.auth = _auth
	client.mode = "local_stub"
	var res: Dictionary = await client.request_assignment()
	_expect(not bool(res.get("ok", false)), "unauth assignment fails")
	var err: WildboatError = res.get("error") as WildboatError
	_expect(err != null and err.code == "AUTH_REQUIRED", "AUTH_REQUIRED")


func _case_stub_after_login() -> void:
	await _login_fresh()
	var client := AssignmentClient.new()
	client.auth = _auth
	client.mode = "local_stub"
	client.stub_port = 24567
	var res: Dictionary = await client.request_assignment()
	_expect(bool(res.get("ok", false)), "stub assignment ok")
	var a: MatchAssignment = res.get("assignment") as MatchAssignment
	_expect(a != null and a.is_valid(), "assignment valid")
	_expect(a.source == "local_stub", "source stub")
	## 重复进行中：手动置 inflight。
	client._inflight = true
	var busy: Dictionary = await client.request_assignment()
	_expect(not bool(busy.get("ok", false)), "busy fails")
	var berr: WildboatError = busy.get("error") as WildboatError
	_expect(berr != null and berr.code == "BUSY", "BUSY code")
	client._inflight = false


func _case_wildboat_assign_or_unavailable() -> void:
	## 调用真实 POST /v1/games/assign。无 ready DS → GAME_SERVER_UNAVAILABLE（仍证明端点正确）。
	## 有 ready DS → 返回合法 assignment（source=wildboat）。
	if not _auth.is_authenticated():
		await _login_fresh()
	var client := AssignmentClient.new()
	client.auth = _auth
	client.mode = "wildboat"
	var res: Dictionary = await client.request_assignment("coop_survival")
	if bool(res.get("ok", false)):
		var a: MatchAssignment = res.get("assignment") as MatchAssignment
		_expect(a != null and a.is_valid(), "wildboat assignment valid")
		_expect(a.source == "wildboat", "source wildboat")
		_expect(not a.host.is_empty(), "host present")
		_expect(a.port > 0, "port present")
		_expect(not a.game_ticket.is_empty(), "ticket present")
		return
	var err: WildboatError = res.get("error") as WildboatError
	_expect(err != null, "assign error object")
	if err != null:
		## 端点存在且鉴权通过；无 DS 时的契约错误。
		_expect(
			err.code in ["GAME_SERVER_UNAVAILABLE", "GAME_CAPACITY_FULL", "RATE_LIMITED"],
			"expected assign business error got %s" % err.code
		)


func _expect(cond: bool, label: String) -> void:
	if not cond:
		_failures.append(label)


func _finish() -> void:
	if _failures.is_empty():
		print("ASSIGNMENT_CLIENT_OK")
		quit(0)
		return
	for failure: String in _failures:
		printerr("ASSIGNMENT_CLIENT_FAIL: %s" % failure)
	quit(1)
