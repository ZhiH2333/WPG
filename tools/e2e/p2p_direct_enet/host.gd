#!/usr/bin/env godot -s
## Phase 9.2.3 E2E — Host 进程（真实生产入口，无 mock）。
##
## 本进程做的事**全部走生产 API**：
##   LobbyManager.create_room() / host_room()  -> 真实 ENet server（唯一 peer）
##   LobbyManager.create_p2p_invite()          -> 真实 invite（真实 room_id / ticket / 端口）
##   LobbyManager.start_p2p_hosting()          -> 真实 rendezvous 注册 + 真实 UDP hole punch
##
## 角色硬规则（9.2.3）：Host **不发起** Direct ENet。它保持 host_listen() 建好的 server，
## 等 Guest 主动 client_connect()，然后走 protocol 6 握手（rpc_hello -> check_ticket ->
## rpc_hello_ok / rpc_join_rejected -> rpc_assign_seat）。
## 因此本进程里只有一个 multiplayer_peer，且从 listen 到退出必须是**同一个**。
##
## 环境变量：
##   RV_HOST / RV_PORT           - rendezvous 服务端
##   LAN_HOST                    - 本机对 Guest 公布的地址（默认 127.0.0.1）
##   INVITE_FILE                 - 写出真实 invite URI 的文件（Guest 只读这个）
##   RESULT_FILE / READY_FILE    - 结果 / 就绪标记
##   CASE                        - success | wrong_ticket | wrong_protocol
##   DEADLINE_SEC                - 本进程整体预算（默认 25）
##
## 结果文件是 key=value（STATUS 在第一行），由 python runner 逐条断言；
## 本文件不打印大段日志，也不写任何仓库内文件。

@tool
extends SceneTree

const NET_STATE_NAMES: PackedStringArray = [
	"DISCONNECTED", "HOSTING", "CONNECTING", "HANDSHAKING", "CONNECTED",
	"LOBBY", "STARTING", "FAILED", "VERSION_MISMATCH", "HOST_CLOSED",
]

var _rv_host := "127.0.0.1"
var _rv_port := 0
var _lan_host := "127.0.0.1"
var _invite_file := ""
var _result_file := ""
var _ready_file := ""
var _case := "success"
var _deadline_ms := 25000

var _net: LobbyNet
var _mgr: LobbyManager

var _setup_done := false
var _deadline_at := 0
var _ready_written := false
var _invite_uri := ""
var _finished := false
var _since_confirm_ms := -1

## 证据（每条都由真实对象状态/信号产生，不写死）。
var _ev: Dictionary = {}
var _p2p_states: Array[String] = []
var _net_states: Array[String] = []
var _rejected_reason := -1
var _confirmed_pid := 0
var _ticket_ok_at_confirm := false
var _players_at_confirm := -1
var _occupied_at_confirm := -1
var _server_peer_id := 0
var _single_peer_preserved := false


func _process(_delta: float) -> bool:
	if not _setup_done:
		_setup_done = true
		_setup()
		return false
	if _finished:
		return true
	## Host 每帧推进 rendezvous poll + hole punch（与生产 MainMenu 每帧 tick 一致）。
	_mgr.tick_join(0.016)
	_maybe_write_ready()
	_check_terminal()
	if Time.get_ticks_msec() >= _deadline_at:
		_ev["REASON"] = "host_timeout"
		_finish("HOST_FAIL")
	return false


func _setup() -> void:
	_rv_host = _env("RV_HOST", "127.0.0.1")
	_rv_port = int(_env("RV_PORT", "0"))
	_lan_host = _env("LAN_HOST", "127.0.0.1")
	_invite_file = _env("INVITE_FILE", "")
	_result_file = _env("RESULT_FILE", "")
	_ready_file = _env("READY_FILE", "")
	_case = _env("CASE", "success")
	_deadline_ms = int(_env("DEADLINE_SEC", "25")) * 1000
	_deadline_at = Time.get_ticks_msec() + _deadline_ms
	_ev["CASE"] = _case
	if _rv_port < 1 or _invite_file.is_empty() or _result_file.is_empty() or _ready_file.is_empty():
		_ev["REASON"] = "missing_env"
		_finish("HOST_FAIL")
		return

	PlayerProfile.load_from_disk()
	_net = LobbyNet.new()
	root.add_child(_net)
	_mgr = LobbyManager.new()
	root.add_child(_mgr)
	_mgr.bind_net(_net)
	_mgr.set_rendezvous_endpoint(_rv_host, _rv_port)

	_net.peer_joined.connect(_on_peer_joined)
	_net.peer_confirmed.connect(_on_peer_confirmed)
	_net.peer_rejected.connect(_on_peer_rejected)
	_net.peer_left.connect(_on_peer_left)
	_net.state_changed.connect(_on_net_state_changed)

	# 1) 真实建房 + 真实 ENet server（本进程唯一 multiplayer_peer）。
	if not _mgr.host_room("yard", GameLaunch.NetPlay.COOP, 0):
		_ev["REASON"] = "host_room_failed"
		_finish("HOST_FAIL")
		return
	_ev["ENET_SERVER"] = _b(_net.is_server())
	## 生产协议号（Host 侧从未被覆盖）：证明负向用例靠的是 hello 内容，不是改协议号。
	_ev["PROTOCOL"] = str(GameLaunch.NET_PROTOCOL)
	_server_peer_id = _peer_instance_id()

	# 2) 真实 invite（真实 room_id / ticket / ENet 端口），写到 Guest 唯一能读的位置。
	var invite: JoinInvite = _mgr.create_p2p_invite(_lan_host)
	if invite == null or not invite.is_valid():
		_ev["REASON"] = "create_p2p_invite_failed"
		_finish("HOST_FAIL")
		return
	_invite_uri = invite.to_uri()
	var f: FileAccess = FileAccess.open(_invite_file, FileAccess.WRITE)
	if f == null:
		_ev["REASON"] = "invite_write_failed"
		_finish("HOST_FAIL")
		return
	f.store_line(_invite_uri)
	f.close()
	_ev["INVITE_WRITTEN"] = _b(true)
	_ev["INVITE_IS_P2P"] = _b(invite.is_p2p())
	_ev["ENTRY"] = "host_room+create_p2p_invite+start_p2p_hosting"

	# 3) 真实 rendezvous 注册 + hole punch（Host 只注册，不建 ENet）。
	if not _mgr.start_p2p_hosting():
		_ev["REASON"] = "start_p2p_hosting_failed"
		_finish("HOST_FAIL")
		return
	var p2p: P2PConnection = _mgr.get_p2p_connection()
	if p2p == null:
		_ev["REASON"] = "no_p2p_connection"
		_finish("HOST_FAIL")
		return
	p2p.state_changed.connect(_on_p2p_state_changed)
	p2p.finished.connect(_on_p2p_finished)
	_ev["P2P_ROLE"] = "host" if p2p.is_host_role() else "guest"


func _on_p2p_state_changed(_from: int, to: int, _event: int) -> void:
	var name := P2PConnectionState.state_name(to)
	if not _p2p_states.has(name):
		_p2p_states.append(name)


func _on_p2p_finished(success: bool, reason: String) -> void:
	_ev["P2P_FINISH_OK"] = _b(success)
	_ev["P2P_FINISH_REASON"] = reason


func _on_net_state_changed(state: int) -> void:
	var name := NET_STATE_NAMES[state] if state >= 0 and state < NET_STATE_NAMES.size() else "?"
	if not _net_states.has(name):
		_net_states.append(name)


func _on_peer_joined(peer_id: int, _seat: int) -> void:
	_ev["PEER_CONNECTED"] = _b(true)
	_ev["PEER_ID"] = str(peer_id)


func _on_peer_confirmed(peer_id: int, seat: int) -> void:
	_ev["PEER_CONFIRMED"] = _b(true)
	_ev["SEAT"] = str(seat)
	_confirmed_pid = peer_id
	## ticket 通过是 hello 被受理的**直接**证据：未过 ticket 的 peer 拿不到 seat。
	_ticket_ok_at_confirm = _net.is_peer_ticket_ok(peer_id)
	_players_at_confirm = _mgr.get_room().player_count() if _mgr.get_room() != null else -1
	_occupied_at_confirm = _net.occupied_count()


func _on_peer_rejected(peer_id: int, reason: int) -> void:
	_ev["PEER_REJECTED"] = _b(true)
	_ev["REJECT_REASON_CODE"] = str(reason)
	_rejected_reason = reason


func _on_peer_left(_peer_id: int) -> void:
	_ev["PEER_LEFT"] = _b(true)


func _maybe_write_ready() -> void:
	if _ready_written or _mgr == null:
		return
	var p2p: P2PConnection = _mgr.get_p2p_connection()
	if p2p == null:
		return
	if p2p.get_state_value() < P2PConnectionState.State.RENDEZVOUS_REGISTERED:
		return
	_ready_written = true
	var f: FileAccess = FileAccess.open(_ready_file, FileAccess.WRITE)
	if f != null:
		f.store_line("ready")
		f.close()


func _check_terminal() -> void:
	if _case == "success":
		if _ev.get("PEER_CONFIRMED", "") != "1":
			return
		## 可靠 RPC（hello_ok / assign_seat）先落地，再收尾退出，别把 Host 的 socket 提前关掉。
		if _since_confirm_ms < 0:
			_since_confirm_ms = Time.get_ticks_msec()
			return
		if Time.get_ticks_msec() - _since_confirm_ms < 1200:
			return
		_finish_success()
		return
	## 负向用例：Host 只负责「拒绝 + 不占座 + 继续 hosting」。
	if _rejected_reason < 0:
		return
	if _since_confirm_ms < 0:
		_since_confirm_ms = Time.get_ticks_msec()
		return
	var waited: int = Time.get_ticks_msec() - _since_confirm_ms
	## 等 rejected peer 真的被断开（peer_left = 座位已被释放），最多 2.5s。
	var settled: bool = _ev.get("PEER_LEFT", "") == "1" or waited >= 2500
	if waited < 600 or not settled:
		return
	_finish_rejected()


func _finish_success() -> void:
	var room: Room = _mgr.get_room()
	_ev["ENET_SERVER"] = _b(_net.is_server())
	_ev["SINGLE_PEER"] = _b(_single_peer_preserved)
	_ev["TICKET_ACCEPTED"] = _b(_ticket_ok_at_confirm)
	_ev["PLAYERS"] = str(_players_at_confirm)
	_ev["OCCUPIED"] = str(_occupied_at_confirm)
	_ev["REJECTED_NONE"] = _b(_rejected_reason < 0)
	_ev["P2P_STATES"] = ",".join(_p2p_states)
	_ev["NET_STATES"] = ",".join(_net_states)
	_ev["NET_STATE"] = _net_state_name()
	_ev["ROOM_OPEN"] = _b(room != null and not room.is_closed())
	_finish("HOST_OK")


func _finish_rejected() -> void:
	var room: Room = _mgr.get_room()
	_ev["ENET_SERVER"] = _b(_net.is_server())
	_ev["SINGLE_PEER"] = _b(_single_peer_preserved)
	_ev["PEER_CONFIRMED"] = "1" if _ev.get("PEER_CONFIRMED", "") == "1" else "0"
	_ev["PLAYERS"] = str(room.player_count() if room != null else -1)
	_ev["OCCUPIED"] = str(_net.occupied_count())
	_ev["SEAT2_PEER"] = str(_net.seat_peer(2))
	_ev["SEAT2_IS_GUEST"] = _b(room != null and room.get_player_in_seat(2) != null)
	_ev["P2P_STATES"] = ",".join(_p2p_states)
	_ev["NET_STATES"] = ",".join(_net_states)
	_ev["NET_STATE"] = _net_state_name()
	_finish("HOST_REJECTED")


func _net_state_name() -> String:
	var state: int = int(_net.get_state())
	return NET_STATE_NAMES[state] if state >= 0 and state < NET_STATE_NAMES.size() else "?"


func _peer_instance_id() -> int:
	var peer: MultiplayerPeer = root.multiplayer.multiplayer_peer
	return peer.get_instance_id() if peer != null else 0


func _finish(status: String) -> void:
	if _finished:
		return
	_finished = true
	## 结构性断言：整场只有 listen 时那一个 peer，Host 从未把自己换成 client。
	_single_peer_preserved = _server_peer_id != 0 and _peer_instance_id() == _server_peer_id
	_ev["SINGLE_PEER"] = _b(_single_peer_preserved)
	_ev["P2P_ROLE"] = "host" if (_mgr != null and _mgr.get_p2p_connection() != null and _mgr.get_p2p_connection().is_host_role()) else "none"
	## 失败诊断：状态轨迹必须留下，否则排障只能靠猜。
	_ev["P2P_STATES"] = ",".join(_p2p_states)
	_ev["NET_STATES"] = ",".join(_net_states)
	_ev["NET_STATE"] = _net_state_name() if _net != null else ""
	var lines: PackedStringArray = PackedStringArray()
	lines.append("STATUS=%s" % status)
	var keys: Array = _ev.keys()
	keys.sort()
	for key: String in keys:
		lines.append("%s=%s" % [key, str(_ev[key])])
	var f: FileAccess = FileAccess.open(_result_file, FileAccess.WRITE)
	if f != null:
		for line: String in lines:
			f.store_line(line)
		f.close()
	quit(0 if status == "HOST_OK" or status == "HOST_REJECTED" else 1)


func _env(key: String, fallback: String = "") -> String:
	var value = OS.get_environment(key)
	if typeof(value) == TYPE_BOOL:
		return fallback
	var text := str(value).strip_edges()
	return text if not text.is_empty() else fallback


func _b(value) -> String:
	return "1" if value else "0"
