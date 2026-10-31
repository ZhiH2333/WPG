extends SceneTree

## Phase 2D.1：验证真实 InputMap → PlayerInput → CombatSandbox._flush_online_input → DS。
## 禁止测试侧直接 OnlineChannel.send_input；只用 action_press 驱动移动键。

const SANDBOX_SCENE := "res://sandbox/combat_sandbox.tscn"

var _result_file := ""
var _host := "127.0.0.1"
var _port := OnlineProtocol.DEFAULT_PORT
var _display_name := "input"
var _dev_token := ""
var _claimed_match_id := ""
var _move_action := "move_right"
var _deadline_at := 0
var _client: DedicatedClient
var _lobby_net: LobbyNet = null
var _sandbox: CombatSandbox = null
var _finished := false
var _setup_done := false
var _admitted := false
var _entered := false
var _reject_reason := -1
var _local_seat := 0
var _saw_two_pawns := false
var _local_moved := false
var _remote_moved := false
var _local_start_x := 0.0
var _local_start_set := false
var _remote_start_x := 0.0
var _remote_start_set := false
var _input_frames := 0
var _action_held := false
var _last_move_x := 0.0
var _peer_alive_after_handoff := false
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
		_drive_inputmap()
		_input_frames += 1
		_observe_world()
		if _saw_two_pawns and _local_moved and _remote_moved and _input_frames >= 50:
			_finish_ok()
	if _reject_reason >= 0 and not _admitted:
		_ev["REJECT_REASON"] = _reject_reason
		_finish("CLIENT_REJECTED")
	if Time.get_ticks_msec() >= _deadline_at:
		_ev["REASON"] = "client_timeout"
		_ev["ADMITTED"] = 1 if _admitted else 0
		_ev["ENTERED"] = 1 if _entered else 0
		_ev["SAW_TWO_PAWNS"] = 1 if _saw_two_pawns else 0
		_ev["LOCAL_MOVED"] = 1 if _local_moved else 0
		_ev["REMOTE_MOVED"] = 1 if _remote_moved else 0
		_ev["LAST_MOVE_X"] = _last_move_x
		_ev["INPUT_FRAMES"] = _input_frames
		_finish("CLIENT_FAIL")
	return false


func _setup() -> void:
	_result_file = _env("RESULT_FILE", "")
	_host = _env("GAME_HOST", "127.0.0.1")
	_port = int(_env("GAME_PORT", str(OnlineProtocol.DEFAULT_PORT)))
	_display_name = _env("DISPLAY_NAME", "input")
	_dev_token = _env("GAME_TICKET", _env("DEV_TOKEN", ""))
	_claimed_match_id = _env("CLAIMED_MATCH_ID", "")
	_move_action = _env("MOVE_ACTION", "move_right")
	_deadline_at = Time.get_ticks_msec() + int(_env("DEADLINE_SEC", "35")) * 1000
	if _result_file.is_empty():
		_ev["REASON"] = "missing_env"
		_finish("CLIENT_FAIL")
		return
	## 模拟 MainMenu 上的 LobbyNet：换场销毁时若未 handoff 会掐断 Online peer。
	_lobby_net = LobbyNet.new()
	_lobby_net.name = "LobbyNet"
	root.add_child(_lobby_net)
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
	## 模拟 MainMenu._enter_online → handoff_online_peer，再换场释放 LobbyNet。
	## 只 release，不要先 close()：close() 会把 _released_for_handoff 清回 false，
	## 随后 _exit_tree→close() 会第二次掐断 peer（与真实 LAN/Online 换场合同不一致）。
	if _lobby_net != null and is_instance_valid(_lobby_net):
		_lobby_net.release_peer_for_handoff()
		_lobby_net.queue_free()
		_lobby_net = null
	## queue_free 在帧末生效；这里立刻检查 peer 仍在 SceneTree 上。
	_peer_alive_after_handoff = (
		_client != null
		and is_instance_valid(_client)
		and _client.multiplayer != null
		and _client.multiplayer.multiplayer_peer != null
	)
	_ev["PEER_ALIVE_AFTER_HANDOFF"] = 1 if _peer_alive_after_handoff else 0
	if not _peer_alive_after_handoff:
		_ev["REASON"] = "peer_killed_on_lobby_teardown"
		_finish("CLIENT_FAIL")


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
	## 禁止测试侧注入 RPC；只靠沙盒 flush 真实输入路径。


func _drive_inputmap() -> void:
	if not _action_held:
		Input.action_press(_move_action)
		_action_held = true
	## 采样本地 PlayerInput，供失败诊断（不调用 send_input）。
	if _sandbox == null or not is_instance_valid(_sandbox):
		return
	var local_player: Variant = _sandbox.get("_local_player")
	var player: Player = local_player as Player
	if player == null or not is_instance_valid(player):
		return
	var pi: PlayerInput = player.get_player_input()
	if pi == null:
		return
	_last_move_x = pi.move_vector.x
	_ev["LAST_MOVE_X"] = _last_move_x


func _observe_world() -> void:
	if _sandbox == null or not is_instance_valid(_sandbox):
		return
	var pawns: Array = _sandbox.get("_pawns")
	if typeof(pawns) != TYPE_ARRAY:
		return
	var alive: int = 0
	var local_x: float = 0.0
	var remote_x: float = 0.0
	var has_local := false
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
		if seat == _local_seat:
			has_local = true
			local_x = player.global_position.x
		else:
			has_remote = true
			remote_x = player.global_position.x
	if alive >= 2 and has_local and has_remote:
		_saw_two_pawns = true
		if not _local_start_set:
			_local_start_x = local_x
			_local_start_set = true
		elif absf(local_x - _local_start_x) > 5.0:
			_local_moved = true
		if not _remote_start_set:
			_remote_start_x = remote_x
			_remote_start_set = true
		elif absf(remote_x - _remote_start_x) > 5.0:
			_remote_moved = true
	_ev["PAWN_ALIVE"] = alive
	_ev["LOCAL_X"] = local_x
	_ev["REMOTE_X"] = remote_x


func _finish_ok() -> void:
	_ev["SAW_TWO_PAWNS"] = 1 if _saw_two_pawns else 0
	_ev["LOCAL_MOVED"] = 1 if _local_moved else 0
	_ev["REMOTE_MOVED"] = 1 if _remote_moved else 0
	_ev["ENTERED"] = 1
	_ev["LAST_MOVE_X"] = _last_move_x
	_finish("CLIENT_OK")


func _finish(status: String) -> void:
	if _finished:
		return
	_finished = true
	if _action_held:
		Input.action_release(_move_action)
		_action_held = false
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
