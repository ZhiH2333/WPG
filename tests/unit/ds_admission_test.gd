extends SceneTree

## Dedicated Server 准入 / 座位 / 满员拒绝（Phase 2A）。
## 单进程打 DsSession 状态机；真多客户端 E2E 见 tools/e2e/dedicated。
## 跑法：godot --headless --path . --script res://tests/unit/ds_admission_test.gd

var _failures: PackedStringArray = PackedStringArray()
var _port: int = 24601


func _initialize() -> void:
	_run_all.call_deferred()


func _run_all() -> void:
	_case_server_admits_up_to_four()
	_case_fifth_rejected_full()
	_case_bad_protocol_rejected()
	_case_bad_token_rejected()
	_case_server_peer_is_not_a_player_seat()
	_case_lan_seat_policy_untouched()
	_case_movement_is_server_authoritative()
	_finish()


func _make_session(max_players: int = 4, token: String = "") -> DsSession:
	var cfg := ServerConfig.new()
	cfg.port = _port
	_port += 1
	cfg.max_players = max_players
	cfg.dev_token = token
	cfg.ready_file = ""
	cfg.match_id = "unit_match"
	var session := DsSession.new()
	root.add_child(session)
	session.setup(cfg)
	_expect(session.start(), "listen on %d" % cfg.port)
	return session


func _case_server_admits_up_to_four() -> void:
	var session: DsSession = _make_session(4)
	for i in 4:
		var peer_id: int = 10 + i
		var result: Dictionary = session.try_admit(peer_id, OnlineProtocol.PROTOCOL_VERSION, "p%d" % i, "")
		_expect(int(result["reason"]) == OnlineProtocol.RejectReason.NONE, "admit peer %d" % peer_id)
		_expect(int(result["seat"]) == i + 1, "seat %d" % (i + 1))
	_expect(session.occupied_count() == 4, "occupied == 4")
	session.stop()
	session.queue_free()


func _case_fifth_rejected_full() -> void:
	var session: DsSession = _make_session(4)
	for i in 4:
		session.try_admit(20 + i, OnlineProtocol.PROTOCOL_VERSION, "x", "")
	var fifth: Dictionary = session.try_admit(99, OnlineProtocol.PROTOCOL_VERSION, "overflow", "")
	_expect(int(fifth["reason"]) == OnlineProtocol.RejectReason.FULL, "5th -> FULL")
	_expect(session.occupied_count() == 4, "still 4 after reject")
	session.stop()
	session.queue_free()


func _case_bad_protocol_rejected() -> void:
	var session: DsSession = _make_session(4)
	var result: Dictionary = session.try_admit(30, OnlineProtocol.PROTOCOL_VERSION + 1, "x", "")
	_expect(int(result["reason"]) == OnlineProtocol.RejectReason.BAD_PROTOCOL, "bad protocol")
	_expect(session.occupied_count() == 0, "no seat on bad protocol")
	session.stop()
	session.queue_free()


func _case_bad_token_rejected() -> void:
	var session: DsSession = _make_session(4, "secret")
	var bad: Dictionary = session.try_admit(31, OnlineProtocol.PROTOCOL_VERSION, "x", "wrong")
	_expect(int(bad["reason"]) == OnlineProtocol.RejectReason.BAD_TOKEN, "bad token")
	var good: Dictionary = session.try_admit(32, OnlineProtocol.PROTOCOL_VERSION, "x", "secret")
	_expect(int(good["reason"]) == OnlineProtocol.RejectReason.NONE, "good token")
	session.stop()
	session.queue_free()


func _case_server_peer_is_not_a_player_seat() -> void:
	var session: DsSession = _make_session(4)
	var result: Dictionary = session.try_admit(1, OnlineProtocol.PROTOCOL_VERSION, "server", "")
	_expect(int(result["reason"]) == OnlineProtocol.RejectReason.MALFORMED, "peer 1 cannot admit as player")
	session.stop()
	session.queue_free()


func _case_lan_seat_policy_untouched() -> void:
	_expect(GameLaunch.NET_MAX_SEATS == 5, "LAN NET_MAX_SEATS == 5")
	_expect(Room.MAX_PLAYERS == GameLaunch.NET_MAX_SEATS, "Room still uses LAN seats")
	_expect(OnlineProtocol.MAX_PLAYERS == 4, "Online max is 4")
	_expect(OnlineProtocol.MAX_PLAYERS != GameLaunch.NET_MAX_SEATS, "Online/LAN seat caps differ")


func _case_movement_is_server_authoritative() -> void:
	var state := DsPlayerState.new(1, 2, "mover")
	var origin: Vector2 = state.position
	_expect(state.apply_input(1.0, 0.0, 1000), "first input accepted")
	_expect(not state.apply_input(1.0, 0.0, 1001), "rate-limited input dropped")
	state.simulate(0.5)
	_expect(state.position.x > origin.x, "server simulation moves player")
	_expect(is_equal_approx(state.position.y, origin.y), "y unchanged for mx-only")


func _expect(cond: bool, label: String) -> void:
	if not cond:
		_failures.append(label)


func _finish() -> void:
	if _failures.is_empty():
		print("DS_ADMISSION_OK")
		quit(0)
		return
	for failure: String in _failures:
		printerr("DS_ADMISSION_FAIL: %s" % failure)
	quit(1)
