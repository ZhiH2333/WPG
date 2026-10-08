#!/usr/bin/env godot -s
## Phase 9.2.3 E2E — Guest 进程（真实生产入口，无 mock）。
##
## Guest **只**从生产入口进入：
##   LobbyManager.join_invite(raw_uri)
##     -> join_invite_p2p() -> P2PConnection -> RendezvousClient
##     -> CANDIDATES -> P2PHolePunch -> direct_path_established
##     -> begin_direct_enet() -> LobbyNet.client_connect()
##     -> connected_to_server -> protocol 6 rpc_hello -> rpc_assign_seat(2) -> CONNECTED
##
## 本进程**不调用** _get_or_create_p2p_connection() / begin_with_identity()，
## 也不自己拼 room_id / ticket / nonce：invite URI 完全来自 Host 真实生成的 invite。
##
## 负向用例只注入「非法 hello」（协议号 / ticket），不改协议号本身、不 fake Host 状态：
##   HELLO_PROTOCOL=<n>  -> LobbyNet.set_hello_protocol_for_test(n)
##   HELLO_TICKET=<hex>  -> LobbyNet.set_hello_ticket_for_test(hex)
##
## 环境变量：
##   INVITE_FILE / RESULT_FILE / READY_FILE
##   CASE / DEADLINE_SEC / HELLO_PROTOCOL / HELLO_TICKET
##
## 结果文件是 key=value（STATUS 在第一行），由 python runner 逐条断言。

@tool
extends SceneTree

const NET_STATE_NAMES: PackedStringArray = [
	"DISCONNECTED", "HOSTING", "CONNECTING", "HANDSHAKING", "CONNECTED",
	"LOBBY", "STARTING", "FAILED", "VERSION_MISMATCH", "HOST_CLOSED",
]

var _invite_file := ""
var _result_file := ""
var _ready_file := ""
var _case := "success"
var _deadline_ms := 25000
var _hello_protocol := 0
var _hello_ticket := ""

var _net: LobbyNet
var _mgr: LobbyManager
var _p2p: P2PConnection

var _setup_done := false
var _ready_written := false
var _finished := false
var _deadline_at := 0
var _settle_at := -1
var _reached_connected := false
## 负向用例的终态拒绝理由（由真实状态迁移记下；握手成功后 LobbyManager 会 reset 掉
## 这个 P2PConnection，所以不能事后读活状态）。
var _terminal_state := ""

var _ev: Dictionary = {}
var _p2p_states: Array[String] = []
var _net_states: Array[String] = []
var _client_peer_id := 0
var _seat := 0
var _reject_reason := -1


func _process(_delta: float) -> bool:
	if not _setup_done:
		_setup_done = true
		_setup()
		return false
	if _finished:
		return true
	if _mgr != null:
		_mgr.tick_join(0.016)
	_maybe_write_ready()
	_check_terminal()
	if Time.get_ticks_msec() >= _deadline_at:
		_ev["REASON"] = "guest_timeout"
		_finish("GUEST_FAIL")
	return false


func _setup() -> void:
	_invite_file = _env("INVITE_FILE", "")
	_result_file = _env("RESULT_FILE", "")
	_ready_file = _env("READY_FILE", "")
	_case = _env("CASE", "success")
	_deadline_ms = int(_env("DEADLINE_SEC", "25")) * 1000
	_hello_protocol = int(_env("HELLO_PROTOCOL", "0"))
	_hello_ticket = _env("HELLO_TICKET", "")
	_deadline_at = Time.get_ticks_msec() + _deadline_ms
	_ev["CASE"] = _case
	if _invite_file.is_empty() or _result_file.is_empty() or _ready_file.is_empty():
		_ev["REASON"] = "missing_env"
		_finish("GUEST_FAIL")
		return

	## Host 真实生成的 invite：还没落地就等下一帧（不自己造一条）。
	var raw: String = _read_file(_invite_file)
	if raw.is_empty():
		_setup_done = false
		return

	PlayerProfile.load_from_disk()
	_net = LobbyNet.new()
	root.add_child(_net)
	_mgr = LobbyManager.new()
	root.add_child(_mgr)
	_mgr.bind_net(_net)

	_net.connected.connect(_on_connected)
	_net.seat_assigned.connect(_on_seat_assigned)
	_net.join_rejected.connect(_on_join_rejected)
	_net.connection_failed.connect(_on_connection_failed)
	_net.version_mismatch.connect(_on_version_mismatch)
	_net.host_closed.connect(_on_host_closed)
	_net.state_changed.connect(_on_net_state_changed)

	## 负向注入（生产默认不设置；不 monkey patch、不改 GameLaunch.NET_PROTOCOL）。
	if _hello_protocol > 0:
		_net.set_hello_protocol_for_test(_hello_protocol)
	if not _hello_ticket.is_empty():
		_net.set_hello_ticket_for_test(_hello_ticket)
	_ev["HELLO_OVERRIDE_PROTOCOL"] = str(_hello_protocol)
	_ev["HELLO_OVERRIDE_TICKET"] = _b(not _hello_ticket.is_empty())

	## ---- 唯一入口：生产 join_invite(raw_uri) ----
	var invite: JoinInvite = _mgr.join_invite(raw)
	_ev["ENTRY"] = "join_invite"
	_ev["JOIN_INVITE_VALID"] = _b(invite != null and invite.is_valid())
	_ev["JOIN_INVITE_ERROR"] = str(int(invite.error) if invite != null else -1)
	_ev["JOIN_IS_P2P"] = _b(invite != null and invite.is_p2p())
	_ev["JOIN_ACCEPTED"] = _b(invite != null and invite.error == JoinInvite.InvalidReason.OK)

	_p2p = _mgr.get_p2p_connection()
	if _p2p == null:
		_ev["REASON"] = "join_invite_did_not_start_p2p"
		_finish("GUEST_FAIL")
		return
	_ev["USES_RENDEZVOUS"] = _b(_p2p.uses_rendezvous())
	_ev["P2P_ROLE"] = "guest" if _p2p.is_guest_role() else "host"
	_p2p.state_changed.connect(_on_p2p_state_changed)
	_p2p.finished.connect(_on_p2p_finished)


func _on_p2p_state_changed(_from: int, to: int, _event: int) -> void:
	var name := P2PConnectionState.state_name(to)
	if not _p2p_states.has(name):
		_p2p_states.append(name)
	## 成功终态要先记下来：握手成功后 LobbyManager 会 reset() 掉这个 P2PConnection，
	## 之后 get_state_value() 就回到 disconnected，不能拿它当判定依据。
	if to == P2PConnectionState.State.CONNECTED:
		_reached_connected = true
	if to == P2PConnectionState.State.TICKET_REJECTED or to == P2PConnectionState.State.VERSION_MISMATCH:
		_terminal_state = name


func _on_p2p_finished(success: bool, reason: String) -> void:
	_ev["P2P_FINISH_OK"] = _b(success)
	_ev["P2P_FINISH_REASON"] = reason


func _on_net_state_changed(state: int) -> void:
	var name := NET_STATE_NAMES[state] if state >= 0 and state < NET_STATE_NAMES.size() else "?"
	if not _net_states.has(name):
		_net_states.append(name)


func _on_connected() -> void:
	_ev["CONNECTED_TO_SERVER"] = _b(true)
	## ENet 连上 ≠ Lobby 连上：此刻 peer 是真实 client，但还没有 ticket 校验、没有座位。
	_client_peer_id = _peer_instance_id()


func _on_seat_assigned(seat: int) -> void:
	_ev["SEAT_ASSIGNED"] = _b(true)
	_seat = seat


func _on_join_rejected(reason: int) -> void:
	_ev["JOIN_REJECTED"] = _b(true)
	_reject_reason = reason


func _on_connection_failed() -> void:
	_ev["CONNECTION_FAILED"] = _b(true)


func _on_version_mismatch() -> void:
	_ev["VERSION_MISMATCH_SIGNAL"] = _b(true)


func _on_host_closed() -> void:
	_ev["HOST_CLOSED_SIGNAL"] = _b(true)


func _maybe_write_ready() -> void:
	if _ready_written or _p2p == null:
		return
	if _p2p.get_state_value() < P2PConnectionState.State.RENDEZVOUS_REGISTERED:
		return
	_ready_written = true
	var f: FileAccess = FileAccess.open(_ready_file, FileAccess.WRITE)
	if f != null:
		f.store_line("ready")
		f.close()


func _check_terminal() -> void:
	if _p2p == null:
		return
	if _case == "success":
		if _seat >= 2 and _reached_connected:
			## 握手已完成：再稳一拍，确认没有后续 transport 事件把结论改写。
			if _arm_settle(2):
				_finish_success()
		return
	## 负向用例：等状态机给出**终态**拒绝理由，而不是等进程超时。
	if not _terminal_state.is_empty():
		if _arm_settle(6):
			_finish_rejected()


func _arm_settle(frames: int) -> bool:
	if _settle_at < 0:
		_settle_at = Time.get_ticks_msec() + frames * 20
		return false
	return Time.get_ticks_msec() >= _settle_at


func _finish_success() -> void:
	_ev["SEAT"] = str(_seat)
	_ev["P2P_STATE"] = "connected" if _reached_connected else _p2p_state_name()
	_ev["NET_STATE"] = _net_state_name()
	_ev["P2P_STATES"] = ",".join(_p2p_states)
	_ev["NET_STATES"] = ",".join(_net_states)
	_ev["SINGLE_PEER"] = _b(_client_peer_id != 0 and _peer_instance_id() == _client_peer_id)
	_ev["TERMINAL"] = _mgr.get_terminal_failure()
	_finish("GUEST_OK")


func _finish_rejected() -> void:
	_ev["SEAT"] = str(_seat)
	_ev["SEAT_ASSIGNED"] = "1" if _ev.get("SEAT_ASSIGNED", "") == "1" else "0"
	_ev["P2P_STATE"] = _terminal_state if not _terminal_state.is_empty() else _p2p_state_name()
	_ev["NET_STATE"] = _net_state_name()
	_ev["P2P_STATES"] = ",".join(_p2p_states)
	_ev["NET_STATES"] = ",".join(_net_states)
	_ev["REJECT_TERMINAL"] = "version_mismatch" if _terminal_state == "version_mismatch" else ("ticket_rejected" if _terminal_state == "ticket_rejected" else "-1")
	_ev["REJECT_REASON_CODE"] = str(_reject_reason)
	_ev["SINGLE_PEER"] = _b(_client_peer_id != 0 and _peer_instance_id() == _client_peer_id)
	## 终态语义：状态机结论（VERSION_MISMATCH / TICKET_REJECTED）不得被
	## Host 主动断开带来的 transport 事件覆写成 HOST_CLOSED。
	_ev["TERMINAL"] = _mgr.get_terminal_failure()
	_ev["OVERRIDDEN_BY_HOST_CLOSED"] = _b(_net_state_name() == "HOST_CLOSED")
	_finish("GUEST_REJECTED")


func _p2p_state_name() -> String:
	return P2PConnectionState.state_name(_p2p.get_state_value()) if _p2p != null else "none"


func _net_state_name() -> String:
	var state: int = int(_net.get_state()) if _net != null else 0
	return NET_STATE_NAMES[state] if state >= 0 and state < NET_STATE_NAMES.size() else "?"


func _peer_instance_id() -> int:
	var peer: MultiplayerPeer = root.multiplayer.multiplayer_peer
	return peer.get_instance_id() if peer != null else 0


func _finish(status: String) -> void:
	if _finished:
		return
	_finished = true
	if not _ev.has("SINGLE_PEER"):
		_ev["SINGLE_PEER"] = _b(_client_peer_id != 0 and _peer_instance_id() == _client_peer_id)
	## 失败诊断：状态轨迹 + 终态原因必须一起留下，否则排障只能靠猜。
	if status == "GUEST_FAIL":
		_ev["P2P_STATE"] = _p2p_state_name()
		_ev["NET_STATE"] = _net_state_name()
		_ev["P2P_STATES"] = ",".join(_p2p_states)
		_ev["NET_STATES"] = ",".join(_net_states)
		_ev["TERMINAL"] = _mgr.get_terminal_failure() if _mgr != null else ""
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
	quit(0 if status == "GUEST_OK" or status == "GUEST_REJECTED" else 1)


func _read_file(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var text := f.get_as_text().strip_edges()
	f.close()
	return text


func _env(key: String, fallback: String = "") -> String:
	var value = OS.get_environment(key)
	if typeof(value) == TYPE_BOOL:
		return fallback
	var text := str(value).strip_edges()
	return text if not text.is_empty() else fallback


func _b(value) -> String:
	return "1" if value else "0"
