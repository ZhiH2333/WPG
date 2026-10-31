extends SceneTree

## Phase 2D：真实加载 combat_sandbox（ONLINE），断言世界里出现本地+远端 Player 实体，
## 并在对方移动后看到远端节点位置变化。

const SANDBOX_SCENE := "res://sandbox/combat_sandbox.tscn"

var _result_file := ""
var _host := "127.0.0.1"
var _port := OnlineProtocol.DEFAULT_PORT
var _display_name := "entity"
var _dev_token := ""
var _claimed_match_id := ""
var _move_x := 1.0
var _deadline_at := 0
var _client: DedicatedClient
var _sandbox: CombatSandbox = null
var _finished := false
var _setup_done := false
var _admitted := false
var _entered := false
var _reject_reason := -1
var _local_seat := 0
var _saw_two_pawns := false
var _remote_moved := false
var _remote_start_x := 0.0
var _remote_start_set := false
var _input_frames := 0
var _ev: Dictionary = {}


func _process(_delta: float) -> bool:
	if not _setup_done:
		_setup_done = true
		_setup()
		return false
	if _finished:
		return true
	if _admitted and not _entered:
		_enter_sandbox()
	if _entered and _sandbox != null:
		_input_frames += 1
		_observe_world()
		if _saw_two_pawns and _remote_moved and _input_frames >= 40:
			_finish_ok()
	if _reject_reason >= 0 and not _admitted:
		_ev["REJECT_REASON"] = _reject_reason
		_finish("CLIENT_REJECTED")
	if Time.get_ticks_msec() >= _deadline_at:
		_ev["REASON"] = "client_timeout"
		_ev["ADMITTED"] = 1 if _admitted else 0
		_ev["ENTERED"] = 1 if _entered else 0
		_ev["SAW_TWO_PAWNS"] = 1 if _saw_two_pawns else 0
		_ev["REMOTE_MOVED"] = 1 if _remote_moved else 0
		_finish("CLIENT_FAIL")
	return false


func _setup() -> void:
	_result_file = _env("RESULT_FILE", "")
	_host = _env("GAME_HOST", "127.0.0.1")
	_port = int(_env("GAME_PORT", str(OnlineProtocol.DEFAULT_PORT)))
	_display_name = _env("DISPLAY_NAME", "entity")
	_dev_token = _env("GAME_TICKET", _env("DEV_TOKEN", ""))
	_claimed_match_id = _env("CLAIMED_MATCH_ID", "")
	_move_x = float(_env("MOVE_X", "1.0"))
	_deadline_at = Time.get_ticks_msec() + int(_env("DEADLINE_SEC", "30")) * 1000
	if _result_file.is_empty():
		_ev["REASON"] = "missing_env"
		_finish("CLIENT_FAIL")
		return
	_client = DedicatedClient.create(_display_name, _dev_token, "", _claimed_match_id)
	root.add_child(_client)
	_client.admitted.connect(_on_admitted)
	_client.rejected.connect(func(r: int) -> void: _reject_reason = r)
	_client.server_closed.connect(func() -> void:
		if not _finished:
			_ev["REASON"] = "server_closed"
			_finish("CLIENT_FAIL")
	)
	if not _client.connect_to_server(_host, _port):
		_ev["REASON"] = "connect_failed"
		_finish("CLIENT_FAIL")


func _on_admitted(seat: int, match_id: String) -> void:
	_admitted = true
	_local_seat = seat
	_ev["SEAT"] = seat
	_ev["MATCH_ID"] = match_id
	GameLaunch.set_net_role(GameLaunch.NetRole.ONLINE)
	GameLaunch.set_local_seat(seat)
	GameLaunch.set_online_match_id(match_id)
	GameLaunch.set_net_play(GameLaunch.NetPlay.COOP)
	GameLaunch.set_arena_id("yard")


func _enter_sandbox() -> void:
	_entered = true
	var packed: PackedScene = load(SANDBOX_SCENE) as PackedScene
	if packed == null:
		_ev["REASON"] = "sandbox_missing"
		_finish("CLIENT_FAIL")
		return
	_sandbox = packed.instantiate() as CombatSandbox
	if _sandbox == null:
		_ev["REASON"] = "sandbox_bad"
		_finish("CLIENT_FAIL")
		return
	root.add_child(_sandbox)


func _observe_world() -> void:
	if _sandbox == null or not is_instance_valid(_sandbox):
		return
	## 通过 OnlineChannel 继续发输入（沙盒也会发；双发可接受）。
	if _client != null and is_instance_valid(_client):
		_client.send_input(_move_x, 0.0)
	var pawns: Array = _sandbox.get("_pawns")
	if typeof(pawns) != TYPE_ARRAY:
		return
	var alive: int = 0
	var remote_x: float = 0.0
	var has_remote := false
	for i in pawns.size():
		var pawn: Variant = pawns[i]
		if pawn == null:
			continue
		var player: Player = pawn as Player
		if player == null or not is_instance_valid(player):
			continue
		if not player.visible:
			continue
		alive += 1
		var seat: int = i + 1
		if seat != _local_seat:
			has_remote = true
			remote_x = player.global_position.x
	if alive >= 2 and has_remote:
		_saw_two_pawns = true
		if not _remote_start_set:
			_remote_start_x = remote_x
			_remote_start_set = true
		elif absf(remote_x - _remote_start_x) > 5.0:
			_remote_moved = true
	_ev["PAWN_ALIVE"] = alive


func _finish_ok() -> void:
	_ev["SAW_TWO_PAWNS"] = 1 if _saw_two_pawns else 0
	_ev["REMOTE_MOVED"] = 1 if _remote_moved else 0
	_ev["ENTERED"] = 1
	_finish("CLIENT_OK")


func _finish(status: String) -> void:
	if _finished:
		return
	_finished = true
	_ev["STATUS"] = status
	_write_result()
	if _sandbox != null and is_instance_valid(_sandbox):
		_sandbox.queue_free()
	if _client != null and is_instance_valid(_client):
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
