extends SceneTree

## Ticket Admission 单元测试（stub / 过期 / 错 match / 重放 / 满员）。
## 跑法：godot --headless --path . --script res://tests/unit/ticket_admission_test.gd

var _failures: PackedStringArray = PackedStringArray()
var _port: int = 24701


func _initialize() -> void:
	_run_all.call_deferred()


func _run_all() -> void:
	_case_stub_valid_admit()
	_case_stub_expired()
	_case_stub_wrong_match()
	_case_stub_wrong_instance()
	_case_stub_replay()
	_case_no_ticket_dev_open_allows()
	_case_dev_bad_token()
	_case_fifth_full_stub()
	_case_settlement_local_minimal()
	_case_assignment_dto()
	_finish()


func _make_stub_session() -> DsSession:
	var cfg := ServerConfig.new()
	cfg.port = _port
	_port += 1
	cfg.max_players = 4
	cfg.ready_file = ""
	cfg.match_id = "dev_match"
	cfg.game_instance_id = "dev_instance"
	cfg.admission_mode = OnlineProtocol.AdmissionMode.STUB
	var session := DsSession.new()
	root.add_child(session)
	session.setup(cfg)
	_expect(session.start(), "listen")
	return session


func _ticket(player_id: String, match_id: String, instance_id: String, exp_offset: int, nonce: String) -> String:
	return StubTicketCodec.issue(
		player_id, "Pilot", match_id, instance_id,
		int(Time.get_unix_time_from_system()) + exp_offset, nonce
	)


func _case_stub_valid_admit() -> void:
	var session: DsSession = _make_stub_session()
	var ticket: String = _ticket("p1", "dev_match", "dev_instance", 60, "n1")
	var res: Dictionary = session.try_admit(10, OnlineProtocol.PROTOCOL_VERSION, "Pilot", ticket)
	_expect(int(res["reason"]) == OnlineProtocol.RejectReason.NONE, "stub admit")
	_expect(str(res.get("player_id", "")) == "p1", "player_id from ticket")
	session.stop()
	session.queue_free()


func _case_stub_expired() -> void:
	var session: DsSession = _make_stub_session()
	var ticket: String = _ticket("p1", "dev_match", "dev_instance", -10, "n_exp")
	var res: Dictionary = session.try_admit(11, OnlineProtocol.PROTOCOL_VERSION, "x", ticket)
	_expect(int(res["reason"]) == OnlineProtocol.RejectReason.TICKET_EXPIRED, "expired")
	session.stop()
	session.queue_free()


func _case_stub_wrong_match() -> void:
	var session: DsSession = _make_stub_session()
	var ticket: String = _ticket("p1", "other_match", "dev_instance", 60, "n_m")
	var res: Dictionary = session.try_admit(12, OnlineProtocol.PROTOCOL_VERSION, "x", ticket)
	_expect(int(res["reason"]) == OnlineProtocol.RejectReason.TICKET_MISMATCH, "wrong match")
	session.stop()
	session.queue_free()


func _case_stub_wrong_instance() -> void:
	var session: DsSession = _make_stub_session()
	var ticket: String = _ticket("p1", "dev_match", "other_instance", 60, "n_i")
	var res: Dictionary = session.try_admit(13, OnlineProtocol.PROTOCOL_VERSION, "x", ticket)
	_expect(int(res["reason"]) == OnlineProtocol.RejectReason.TICKET_MISMATCH, "wrong instance")
	session.stop()
	session.queue_free()


func _case_stub_replay() -> void:
	var session: DsSession = _make_stub_session()
	var ticket: String = _ticket("p1", "dev_match", "dev_instance", 60, "n_replay")
	var first: Dictionary = session.try_admit(14, OnlineProtocol.PROTOCOL_VERSION, "a", ticket)
	_expect(int(first["reason"]) == OnlineProtocol.RejectReason.NONE, "first admit")
	## 换 peer 重放同一 nonce ticket。
	var second: Dictionary = session.try_admit(15, OnlineProtocol.PROTOCOL_VERSION, "b", ticket)
	_expect(int(second["reason"]) == OnlineProtocol.RejectReason.TICKET_REPLAYED, "replay rejected")
	session.stop()
	session.queue_free()


func _case_no_ticket_dev_open_allows() -> void:
	var cfg := ServerConfig.new()
	cfg.port = _port
	_port += 1
	cfg.max_players = 4
	cfg.ready_file = ""
	cfg.dev_token = ""
	cfg.admission_mode = OnlineProtocol.AdmissionMode.DEV
	var session := DsSession.new()
	root.add_child(session)
	session.setup(cfg)
	session.start()
	var res: Dictionary = session.try_admit(20, OnlineProtocol.PROTOCOL_VERSION, "open", "")
	_expect(int(res["reason"]) == OnlineProtocol.RejectReason.NONE, "dev open admits empty ticket")
	session.stop()
	session.queue_free()


func _case_dev_bad_token() -> void:
	var cfg := ServerConfig.new()
	cfg.port = _port
	_port += 1
	cfg.max_players = 4
	cfg.ready_file = ""
	cfg.dev_token = "secret"
	cfg.admission_mode = OnlineProtocol.AdmissionMode.DEV
	var session := DsSession.new()
	root.add_child(session)
	session.setup(cfg)
	session.start()
	var bad: Dictionary = session.try_admit(21, OnlineProtocol.PROTOCOL_VERSION, "x", "")
	_expect(int(bad["reason"]) == OnlineProtocol.RejectReason.BAD_TOKEN, "empty != secret")
	var good: Dictionary = session.try_admit(22, OnlineProtocol.PROTOCOL_VERSION, "x", "secret")
	_expect(int(good["reason"]) == OnlineProtocol.RejectReason.NONE, "secret ok")
	session.stop()
	session.queue_free()


func _case_fifth_full_stub() -> void:
	var session: DsSession = _make_stub_session()
	for i in 4:
		var t: String = _ticket("p%d" % i, "dev_match", "dev_instance", 60, "full_%d" % i)
		session.try_admit(30 + i, OnlineProtocol.PROTOCOL_VERSION, "p", t)
	var fifth_t: String = _ticket("p5", "dev_match", "dev_instance", 60, "full_5")
	var fifth: Dictionary = session.try_admit(99, OnlineProtocol.PROTOCOL_VERSION, "x", fifth_t)
	_expect(int(fifth["reason"]) == OnlineProtocol.RejectReason.FULL, "5th full")
	session.stop()
	session.queue_free()


func _case_settlement_local_minimal() -> void:
	var session: DsSession = _make_stub_session()
	var t: String = _ticket("p1", "dev_match", "dev_instance", 60, "set1")
	session.try_admit(40, OnlineProtocol.PROTOCOL_VERSION, "Pilot", t)
	var res: Dictionary = await session.submit_settlement_minimal("completed")
	_expect(bool(res.get("ok", false)), "local settlement ok")
	_expect(bool(res.get("local", false)), "marked local not cloud")
	_expect(not str(res.get("settlement_id", "")).is_empty(), "settlement_id present")
	session.stop()
	session.queue_free()


func _case_assignment_dto() -> void:
	## 冻结契约：扁平 host/port（优先）。
	var flat: Dictionary = {
		"match_id": "22222222-2222-2222-2222-222222222222",
		"game_instance_id": "11111111-1111-1111-1111-111111111111",
		"server_id": "33333333-3333-3333-3333-333333333333",
		"host": "127.0.0.1",
		"port": 24567,
		"transport": "enet_udp",
		"game_ticket": "ticket",
		"ticket_expires_at": "2099-01-01T00:00:00Z",
		"protocol_version": 1,
		"server_build": "wpg-ds-local",
		"mode": "coop_survival",
	}
	var a: MatchAssignment = MatchAssignment.from_payload(flat)
	_expect(a.is_valid(), "flat assignment valid")
	_expect(a.host == "127.0.0.1", "flat host")
	_expect(a.port == 24567, "flat port")
	_expect(a.server_id == "33333333-3333-3333-3333-333333333333", "server_id")
	_expect(a.mode == "coop_survival", "mode")
	## 旧草案 endpoint 嵌套仍可解析。
	var nested: Dictionary = {
		"match_id": "mat_1",
		"game_instance_id": "gsi_1",
		"endpoint": {"host": "10.0.0.2", "port": 24568, "transport": "enet_udp"},
		"game_ticket": "ticket",
		"ticket_expires_at": "2099-01-01T00:00:00Z",
		"protocol_version": 1,
		"server_build": "x",
	}
	var b: MatchAssignment = MatchAssignment.from_payload(nested)
	_expect(b.is_valid(), "nested assignment valid")
	_expect(b.host == "10.0.0.2", "nested host")
	var safe: Dictionary = a.to_safe_dict()
	_expect(not safe.has("game_ticket"), "safe dict hides ticket")


func _expect(cond: bool, label: String) -> void:
	if not cond:
		_failures.append(label)


func _finish() -> void:
	if _failures.is_empty():
		print("TICKET_ADMISSION_OK")
		quit(0)
		return
	for failure: String in _failures:
		printerr("TICKET_ADMISSION_FAIL: %s" % failure)
	quit(1)
