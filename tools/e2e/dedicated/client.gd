extends SceneTree

## Dedicated Server E2E 客户端：连接、准入、发送输入、接收权威快照。

var _result_file := ""
var _admit_file := ""
var _hold_file := ""
var _host := "127.0.0.1"
var _port := OnlineProtocol.DEFAULT_PORT
var _display_name := "client"
var _dev_token := ""
var _hold_after_admit := false
var _deadline_ms := 15000
var _deadline_at := 0
var _client: DedicatedClient
var _finished := false
var _setup_done := false
var _admitted := false
var _reject_reason := -1
var _last_tick := 0
var _last_players: Array = []
var _input_frames := 0
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
		_client.send_input(1.0, 0.0)
		if _hold_after_admit:
			if not _hold_file.is_empty() and FileAccess.file_exists(_hold_file):
				_finish_ok()
		elif _input_frames >= 30 and _last_tick > 0:
			_finish_ok()
	if _reject_reason >= 0 and not _admitted:
		_ev["REJECT_REASON"] = _reject_reason
		_finish("CLIENT_REJECTED")
	if Time.get_ticks_msec() >= _deadline_at:
		_ev["REASON"] = "client_timeout"
		_ev["ADMITTED"] = 1 if _admitted else 0
		_ev["LAST_TICK"] = _last_tick
		_finish("CLIENT_FAIL")
	return false


func _setup() -> void:
	_result_file = _env("RESULT_FILE", "")
	_admit_file = _env("ADMIT_FILE", "")
	_hold_file = _env("HOLD_RELEASE_FILE", "")
	_host = _env("GAME_HOST", "127.0.0.1")
	_port = int(_env("GAME_PORT", str(OnlineProtocol.DEFAULT_PORT)))
	_display_name = _env("DISPLAY_NAME", "client")
	_dev_token = _env("DEV_TOKEN", "")
	_hold_after_admit = _env("HOLD_AFTER_ADMIT", "0") == "1"
	_deadline_ms = int(_env("DEADLINE_SEC", "15")) * 1000
	_deadline_at = Time.get_ticks_msec() + _deadline_ms
	if _result_file.is_empty():
		_ev["REASON"] = "missing_env"
		_finish("CLIENT_FAIL")
		return
	_client = DedicatedClient.create(_display_name, _dev_token)
	root.add_child(_client)
	_client.admitted.connect(_on_admitted)
	_client.rejected.connect(_on_rejected)
	_client.snapshot_received.connect(_on_snapshot)
	_client.server_closed.connect(_on_server_closed)
	if not _client.connect_to_server(_host, _port):
		_ev["REASON"] = "connect_failed"
		_finish("CLIENT_FAIL")


func _on_admitted(seat: int, match_id: String) -> void:
	_admitted = true
	_ev["SEAT"] = seat
	_ev["MATCH_ID"] = match_id
	if not _admit_file.is_empty():
		var file := FileAccess.open(_admit_file, FileAccess.WRITE)
		if file != null:
			file.store_string("SEAT=%d\n" % seat)


func _on_rejected(reason: int) -> void:
	_reject_reason = reason


func _on_snapshot(tick: int, players: Array) -> void:
	_last_tick = tick
	_last_players = players


func _on_server_closed() -> void:
	if not _finished and not _hold_after_admit:
		_ev["REASON"] = "server_closed"
		_finish("CLIENT_FAIL")


func _finish_ok() -> void:
	_ev["LAST_TICK"] = _last_tick
	_ev["PLAYER_COUNT"] = _last_players.size()
	var local_seat: int = _client.get_local_seat()
	_ev["LOCAL_SEAT"] = local_seat
	for entry in _last_players:
		var d: Dictionary = entry as Dictionary
		if int(d.get("seat", 0)) == local_seat:
			var pos: Vector2 = d.get("position", Vector2.ZERO)
			_ev["POS_X"] = "%.3f" % pos.x
			_ev["POS_Y"] = "%.3f" % pos.y
			_ev["MOVED"] = 1 if absf(pos.x) > 0.1 else 0
	_finish("CLIENT_OK")


func _finish(status: String) -> void:
	if _finished:
		return
	_finished = true
	_ev["STATUS"] = status
	_write_result()
	if _client != null:
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
