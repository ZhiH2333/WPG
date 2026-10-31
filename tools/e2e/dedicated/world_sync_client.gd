extends SceneTree

## Phase 2D 世界同步 E2E 客户端：双向看到对方位移，并可观察 Leave。

var _result_file := ""
var _host := "127.0.0.1"
var _port := OnlineProtocol.DEFAULT_PORT
var _display_name := "client"
var _dev_token := ""
var _claimed_match_id := ""
var _move_x := 1.0
var _move_y := 0.0
var _expect_remote := true
var _wait_peer_left := false
var _leave_after_move := false
var _deadline_at := 0
var _client: DedicatedClient
var _finished := false
var _setup_done := false
var _admitted := false
var _reject_reason := -1
var _local_seat := 0
var _last_tick := 0
var _peak_players := 0
var _saw_remote := false
var _remote_moved := false
var _remote_spawn_x := 0.0
var _remote_spawn_set := false
var _peer_left := false
var _input_frames := 0
var _moved_ok := false
var _leave_sent := false
var _ev: Dictionary = {}


func _process(_delta: float) -> bool:
	if not _setup_done:
		_setup_done = true
		_setup()
		return false
	if _finished:
		return true
	if _admitted:
		_input_frames += 1
		if not _leave_sent and _client != null and is_instance_valid(_client):
			_client.send_input(_move_x, _move_y)
		## 先证明双向可见移动，再处理 Leave。
		if not (_moved_ok and _saw_remote and _remote_moved):
			pass
		elif _leave_after_move and not _leave_sent:
			_leave_sent = true
			## 稍留几帧让对端先记下 REMOTE_MOVED，再断开。
			if _input_frames >= 45:
				_client.close_client()
				_finish_ok()
		elif _wait_peer_left:
			if _peer_left:
				_finish_ok()
		else:
			_finish_ok()
	if _reject_reason >= 0 and not _admitted:
		_ev["REJECT_REASON"] = _reject_reason
		_finish("CLIENT_REJECTED")
	if Time.get_ticks_msec() >= _deadline_at:
		_ev["REASON"] = "client_timeout"
		_ev["ADMITTED"] = 1 if _admitted else 0
		_ev["SAW_REMOTE"] = 1 if _saw_remote else 0
		_ev["REMOTE_MOVED"] = 1 if _remote_moved else 0
		_ev["PEER_LEFT"] = 1 if _peer_left else 0
		_finish("CLIENT_FAIL")
	return false


func _setup() -> void:
	_result_file = _env("RESULT_FILE", "")
	_host = _env("GAME_HOST", "127.0.0.1")
	_port = int(_env("GAME_PORT", str(OnlineProtocol.DEFAULT_PORT)))
	_display_name = _env("DISPLAY_NAME", "client")
	_dev_token = _env("GAME_TICKET", _env("DEV_TOKEN", ""))
	_claimed_match_id = _env("CLAIMED_MATCH_ID", "")
	_move_x = float(_env("MOVE_X", "1.0"))
	_move_y = float(_env("MOVE_Y", "0.0"))
	_expect_remote = _env("EXPECT_REMOTE", "1") == "1"
	_wait_peer_left = _env("WAIT_PEER_LEFT", "0") == "1"
	_leave_after_move = _env("LEAVE_AFTER_MOVE", "0") == "1"
	_deadline_at = Time.get_ticks_msec() + int(_env("DEADLINE_SEC", "25")) * 1000
	if _result_file.is_empty():
		_ev["REASON"] = "missing_env"
		_finish("CLIENT_FAIL")
		return
	_client = DedicatedClient.create(_display_name, _dev_token, "", _claimed_match_id)
	root.add_child(_client)
	_client.admitted.connect(_on_admitted)
	_client.rejected.connect(_on_rejected)
	_client.snapshot_received.connect(_on_snapshot)
	_client.peer_left_seat.connect(_on_peer_left)
	_client.server_closed.connect(_on_server_closed)
	if not _client.connect_to_server(_host, _port):
		_ev["REASON"] = "connect_failed"
		_finish("CLIENT_FAIL")


func _on_admitted(seat: int, match_id: String) -> void:
	_admitted = true
	_local_seat = seat
	_ev["SEAT"] = seat
	_ev["MATCH_ID"] = match_id


func _on_rejected(reason: int) -> void:
	_reject_reason = reason


func _on_snapshot(tick: int, players: Array, match_id: String) -> void:
	_last_tick = tick
	_peak_players = maxi(_peak_players, players.size())
	_ev["MATCH_ID_SNAP"] = match_id
	var remote_pos := Vector2.ZERO
	var has_remote := false
	for entry in players:
		var d: Dictionary = entry as Dictionary
		var seat: int = int(d.get("seat", 0))
		var pos: Vector2 = d.get("position", Vector2.ZERO)
		if seat == _local_seat:
			if absf(pos.x - DsPlayerState._spawn_for_seat(seat).x) > 5.0:
				_moved_ok = true
			continue
		has_remote = true
		remote_pos = pos
	if has_remote:
		_saw_remote = true
		if not _remote_spawn_set:
			_remote_spawn_x = remote_pos.x
			_remote_spawn_set = true
		elif absf(remote_pos.x - _remote_spawn_x) > 5.0:
			_remote_moved = true
	elif _expect_remote and _saw_remote and _wait_peer_left:
		## snapshot 已不含远端，等同 Leave 可视清理。
		_peer_left = true


func _on_peer_left(seat: int) -> void:
	if seat != _local_seat:
		_peer_left = true
		_ev["LEFT_SEAT"] = seat


func _on_server_closed() -> void:
	if _leave_sent:
		return
	if not _finished:
		_ev["REASON"] = "server_closed"
		_finish("CLIENT_FAIL")


func _finish_ok() -> void:
	_ev["LAST_TICK"] = _last_tick
	_ev["PLAYER_COUNT_PEAK"] = _peak_players
	_ev["LOCAL_SEAT"] = _local_seat
	_ev["SAW_REMOTE"] = 1 if _saw_remote else 0
	_ev["REMOTE_MOVED"] = 1 if _remote_moved else 0
	_ev["PEER_LEFT"] = 1 if _peer_left else 0
	_ev["MOVED"] = 1 if _moved_ok else 0
	_finish("CLIENT_OK")


func _finish(status: String) -> void:
	if _finished:
		return
	_finished = true
	_ev["STATUS"] = status
	_write_result()
	if _client != null and is_instance_valid(_client) and not _leave_sent:
		_client.close_client()
	quit(0 if status == "CLIENT_OK" or status == "CLIENT_REJECTED" else 1)


func _write_result() -> void:
	if _result_file.is_empty():
		return
	var lines: PackedStringArray = PackedStringArray()
	lines.append("STATUS=%s" % str(_ev.get("STATUS", "CLIENT_FAIL")))
	for key in _ev.keys():
		if str(key) == "STATUS":
			continue
		lines.append("%s=%s" % [str(key), str(_ev[key])])
	var file := FileAccess.open(_result_file, FileAccess.WRITE)
	if file != null:
		file.store_string("\n".join(lines) + "\n")


func _env(key: String, fallback: String) -> String:
	var value: String = OS.get_environment(key)
	if value.is_empty():
		return fallback
	return value
