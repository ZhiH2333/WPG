extends SceneTree

## OnlineReplica + snapshot v2 + DS 输入隔离回归（Phase 2D）。
## 跑法：godot --headless --path . --script res://tests/unit/online_replica_test.gd

var _failures: PackedStringArray = PackedStringArray()


func _initialize() -> void:
	_run_all.call_deferred()


func _run_all() -> void:
	_case_snapshot_v2_roundtrip()
	_case_replica_stale_and_duplicate()
	_case_replica_match_filter_and_leave()
	_case_ds_input_cannot_forge_other_seat()
	_case_online_role_not_lan()
	_finish()


func _case_snapshot_v2_roundtrip() -> void:
	_expect(OnlineProtocol.SNAPSHOT_VERSION == 2, "snapshot version 2")
	var p1 := DsPlayerState.new(1, 2, "a", "pid-a")
	p1.position = Vector2(10.5, -3.25)
	p1.facing = Vector2(-1, 0)
	var p2 := DsPlayerState.new(2, 3, "b", "pid-b")
	p2.position = Vector2(0, 80)
	p2.facing = Vector2(0, 1)
	var data: PackedByteArray = OnlineProtocol.encode_snapshot(7, [p1, p2], "match-abc")
	var decoded: Dictionary = OnlineProtocol.decode_snapshot(data)
	_expect(bool(decoded["ok"]), "v2 decode ok")
	_expect(int(decoded["tick"]) == 7, "tick")
	_expect(str(decoded["match_id"]) == "match-abc", "match_id")
	_expect((decoded["players"] as Array).size() == 2, "player count")
	var first: Dictionary = (decoded["players"] as Array)[0]
	_expect(int(first["seat"]) == 1, "seat")
	_expect(is_equal_approx((first["facing"] as Vector2).x, -1.0), "facing x")
	## 旧 v1 载荷必须拒绝
	var v1 := PackedByteArray([1, 0, 0, 0, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0])
	_expect(not bool(OnlineProtocol.decode_snapshot(v1)["ok"]), "v1 rejected")


func _case_replica_stale_and_duplicate() -> void:
	var replica := OnlineReplica.new()
	replica.configure("m1", 1)
	var a: Dictionary = replica.accept_snapshot(5, [{"seat": 1, "position": Vector2.ZERO, "facing": Vector2.RIGHT}], "m1")
	_expect(bool(a["ok"]), "first accept")
	var dup: Dictionary = replica.accept_snapshot(5, [{"seat": 1, "position": Vector2(1, 0), "facing": Vector2.RIGHT}], "m1")
	_expect(not bool(dup["ok"]), "duplicate tick rejected")
	var stale: Dictionary = replica.accept_snapshot(4, [{"seat": 1, "position": Vector2(2, 0), "facing": Vector2.RIGHT}], "m1")
	_expect(not bool(stale["ok"]), "stale tick rejected")
	var next: Dictionary = replica.accept_snapshot(6, [
		{"seat": 1, "position": Vector2.ZERO, "facing": Vector2.RIGHT},
		{"seat": 2, "position": Vector2(80, 0), "facing": Vector2.RIGHT},
	], "m1")
	_expect(bool(next["ok"]), "newer tick ok")
	_expect((next["spawned"] as Array).has(2), "seat 2 spawned")


func _case_replica_match_filter_and_leave() -> void:
	var replica := OnlineReplica.new()
	replica.configure("match-a", 2)
	var wrong: Dictionary = replica.accept_snapshot(1, [{"seat": 2, "position": Vector2.ZERO, "facing": Vector2.RIGHT}], "match-b")
	_expect(not bool(wrong["ok"]), "wrong match rejected")
	var ok: Dictionary = replica.accept_snapshot(1, [
		{"seat": 1, "position": Vector2.ZERO, "facing": Vector2.RIGHT},
		{"seat": 2, "position": Vector2(80, 0), "facing": Vector2.RIGHT},
	], "match-a")
	_expect(bool(ok["ok"]), "matching match ok")
	_expect(replica.visible_seats.has(1), "seat 1 visible")
	var left: Dictionary = replica.accept_snapshot(2, [
		{"seat": 2, "position": Vector2(80, 0), "facing": Vector2.RIGHT},
	], "match-a")
	_expect(bool(left["ok"]), "leave snapshot ok")
	_expect((left["removed"] as Array).has(1), "seat 1 removed")
	_expect(replica.note_peer_left(2) == true, "peer_left local seat tracked")
	_expect(not replica.visible_seats.has(2), "local seat cleared from visible")


func _case_ds_input_cannot_forge_other_seat() -> void:
	var cfg := ServerConfig.new()
	cfg.port = 24991
	cfg.max_players = 4
	cfg.ready_file = ""
	cfg.match_id = "dev_match"
	cfg.game_instance_id = "dev_instance"
	cfg.admission_mode = OnlineProtocol.AdmissionMode.STUB
	var session := DsSession.new()
	root.add_child(session)
	session.setup(cfg)
	_expect(session.start(), "listen for forge case")
	var t_a: String = StubTicketCodec.issue(
		"pa", "A", "dev_match", "dev_instance",
		int(Time.get_unix_time_from_system()) + 60, "forge_a"
	)
	var t_b: String = StubTicketCodec.issue(
		"pb", "B", "dev_match", "dev_instance",
		int(Time.get_unix_time_from_system()) + 60, "forge_b"
	)
	var a: Dictionary = session.try_admit(10, OnlineProtocol.PROTOCOL_VERSION, "A", t_a)
	var b: Dictionary = session.try_admit(11, OnlineProtocol.PROTOCOL_VERSION, "B", t_b)
	_expect(int(a.get("reason", -1)) == OnlineProtocol.RejectReason.NONE, "admit A")
	_expect(int(b.get("reason", -1)) == OnlineProtocol.RejectReason.NONE, "admit B")
	var before_b: Vector2 = Vector2.ZERO
	var move_b_before: Vector2 = Vector2.ZERO
	for p in session.get_players():
		var st: DsPlayerState = p as DsPlayerState
		if st.peer_id == 11:
			before_b = st.position
			move_b_before = st.move_input
	## peer 10 的输入只能绑定到 peer 10；不能改 peer 11。
	session.apply_input(10, 1.0, 0.0)
	for p in session.get_players():
		(p as DsPlayerState).simulate(0.1)
	for p in session.get_players():
		var st: DsPlayerState = p as DsPlayerState
		if st.peer_id == 10:
			_expect(st.move_input.x > 0.5 or st.position.x > before_b.x, "peer10 moved/input")
		if st.peer_id == 11:
			_expect(st.move_input == move_b_before, "peer11 input untouched")
			_expect(is_equal_approx(st.position.x, before_b.x), "peer11 position untouched")
	session.apply_input(99, 1.0, 0.0)
	_expect(session.occupied_count() == 2, "unknown peer does not admit")
	session.stop()
	session.queue_free()


func _case_online_role_not_lan() -> void:
	_expect(int(GameLaunch.NetRole.ONLINE) != int(GameLaunch.NetRole.HOST), "ONLINE != HOST")
	_expect(int(GameLaunch.NetRole.ONLINE) != int(GameLaunch.NetRole.GUEST), "ONLINE != GUEST")
	GameLaunch.set_net_role(GameLaunch.NetRole.ONLINE)
	var role: GameLaunch.NetRole = GameLaunch.take_net_role()
	_expect(role == GameLaunch.NetRole.ONLINE, "take ONLINE")
	GameLaunch.set_online_match_id("abc")
	_expect(GameLaunch.take_online_match_id() == "abc", "online match id")
	_expect(GameLaunch.take_online_match_id() == "", "online match id cleared")


func _expect(cond: bool, label: String) -> void:
	if not cond:
		_failures.append(label)


func _finish() -> void:
	if _failures.is_empty():
		print("ONLINE_REPLICA_OK")
		quit(0)
		return
	for failure: String in _failures:
		printerr("ONLINE_REPLICA_FAIL: %s" % failure)
	quit(1)
