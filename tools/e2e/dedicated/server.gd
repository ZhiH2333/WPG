extends SceneTree

## Dedicated Server E2E 进程：listen + 等待准入 + 保持权威仿真。

var _result_file := ""
var _ready_file := ""
var _release_file := ""
var _port := OnlineProtocol.DEFAULT_PORT
var _max_players := OnlineProtocol.MAX_PLAYERS
var _dev_token := ""
var _expect_players := 2
var _stay_up := false
var _deadline_ms := 20000
var _deadline_at := 0
var _close_at := 0
var _session: DsSession
var _result_written := false
var _setup_done := false
var _peak_occupied := 0
var _ev: Dictionary = {}


func _process(_delta: float) -> bool:
	if not _setup_done:
		_setup_done = true
		_setup()
		return false
	if _close_at > 0 and Time.get_ticks_msec() >= _close_at:
		_shutdown(0 if str(_ev.get("STATUS", "")).ends_with("_OK") else 1)
		return true
	if _result_written:
		if _stay_up and not _release_file.is_empty() and FileAccess.file_exists(_release_file):
			_close_at = Time.get_ticks_msec() + 200
		return false
	if _session != null:
		_peak_occupied = maxi(_peak_occupied, _session.occupied_count())
		if (not _stay_up) and _peak_occupied >= _expect_players and _session.get_tick() >= 5:
			var moved := _count_moved()
			if moved > 0:
				_mark_ok(moved)
				## 给客户端一点窗口写完自己的结果，再关服。
				_close_at = Time.get_ticks_msec() + 2500
	if Time.get_ticks_msec() >= _deadline_at:
		if not _result_written:
			_ev["REASON"] = "server_timeout"
			_ev["OCCUPIED"] = _session.occupied_count() if _session != null else -1
			_ev["PEAK_OCCUPIED"] = _peak_occupied
			_ev["STATUS"] = "SERVER_FAIL"
			_write_result()
			_result_written = true
		_shutdown(1)
		return true
	return false


func _setup() -> void:
	_result_file = _env("RESULT_FILE", "")
	_ready_file = _env("READY_FILE", "")
	_release_file = _env("RELEASE_FILE", "")
	_port = int(_env("GAME_PORT", str(OnlineProtocol.DEFAULT_PORT)))
	_max_players = int(_env("MAX_PLAYERS", str(OnlineProtocol.MAX_PLAYERS)))
	_dev_token = _env("DEV_TOKEN", "")
	_expect_players = int(_env("EXPECT_PLAYERS", "2"))
	_stay_up = _env("STAY_UP", "0") == "1"
	_deadline_ms = int(_env("DEADLINE_SEC", "20")) * 1000
	_deadline_at = Time.get_ticks_msec() + _deadline_ms
	if _result_file.is_empty() or _ready_file.is_empty():
		_ev["REASON"] = "missing_env"
		_ev["STATUS"] = "SERVER_FAIL"
		_write_result()
		_shutdown(1)
		return
	var cfg := ServerConfig.new()
	cfg.port = _port
	cfg.max_players = clampi(_max_players, 1, OnlineProtocol.MAX_PLAYERS)
	cfg.dev_token = _dev_token
	cfg.ready_file = _ready_file
	cfg.match_id = "e2e_ds"
	_session = DsSession.new()
	root.add_child(_session)
	_session.setup(cfg)
	if not _session.start():
		_ev["REASON"] = "listen_failed"
		_ev["STATUS"] = "SERVER_FAIL"
		_write_result()
		_shutdown(1)
		return
	_ev["PORT"] = cfg.port
	_ev["MAX_PLAYERS"] = cfg.max_players
	if _stay_up:
		## 满员拒绝用例：服务端一直活着，结果在 release 时落盘。
		_ev["STATUS"] = "SERVER_HOLDING"
		_write_result()
		_result_written = true


func _count_moved() -> int:
	var moved := 0
	for state in _session.get_players():
		var ps: DsPlayerState = state as DsPlayerState
		if ps == null:
			continue
		var spawn: Vector2 = DsPlayerState._spawn_for_seat(ps.seat)
		if not ps.position.is_equal_approx(spawn):
			moved += 1
		_ev["SEAT_%d_X" % ps.seat] = "%.3f" % ps.position.x
		_ev["SEAT_%d_Y" % ps.seat] = "%.3f" % ps.position.y
	return moved


func _mark_ok(moved: int) -> void:
	_ev["OCCUPIED"] = _session.occupied_count()
	_ev["PEAK_OCCUPIED"] = _peak_occupied
	_ev["TICK"] = _session.get_tick()
	_ev["MOVED_PLAYERS"] = moved
	_ev["AUTHORITATIVE"] = 1
	_ev["STATUS"] = "SERVER_OK"
	_write_result()
	_result_written = true


func _shutdown(code: int) -> void:
	if _stay_up and _session != null:
		_ev["OCCUPIED"] = _session.occupied_count()
		_ev["PEAK_OCCUPIED"] = _peak_occupied
		_ev["TICK"] = _session.get_tick()
		_ev["STATUS"] = "SERVER_OK" if _peak_occupied >= _expect_players else str(_ev.get("STATUS", "SERVER_FAIL"))
		_write_result()
	if _session != null:
		_session.stop()
	quit(code)


func _write_result() -> void:
	if _result_file.is_empty():
		return
	var lines: PackedStringArray = PackedStringArray()
	lines.append("STATUS=%s" % str(_ev.get("STATUS", "SERVER_FAIL")))
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
