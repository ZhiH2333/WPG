extends Control
class_name OnlinePanel

## Online 玩家可操作入口：登录 WildBoat → 真实 assign → 真实 game_ticket 连 DS。
## 与 LanOverlay 并行；不替代 Solo / LAN。禁止 stub 冒充真实 Online 成功。

signal closed
## 准入成功且 OnlineChannel 已挂在 /root：交给 MainMenu 进入战斗世界。
signal enter_world(seat: int, match_id: String)

const STATUS_IDLE := "Ready — login with a real WildBoat account"
const PHASE_IDLE := "idle"
const PHASE_BUSY := "busy"
const PHASE_CONNECTING := "connecting"
const PHASE_IN_MATCH := "in_match"

var auth: AuthSession = null
var assignment_client: AssignmentClient = null
var _client: DedicatedClient = null
var _busy: bool = false
var _phase: String = PHASE_IDLE
var _last_player_count: int = 0
var _last_tick: int = 0
var _admitted_seat: int = 0
var _admitted_match: String = ""

@onready var _base_url: LineEdit = %BaseUrl
@onready var _email: LineEdit = %Email
@onready var _password: LineEdit = %Password
@onready var _display: LineEdit = %DisplayName
@onready var _status: Label = %Status
@onready var _match_status: Label = %MatchStatus
@onready var _identity: Label = %Identity
@onready var _assign_mode: OptionButton = %AssignMode
@onready var _host: LineEdit = %Host
@onready var _port: LineEdit = %Port
@onready var _register_btn: Button = %RegisterButton
@onready var _verify_btn: Button = %VerifyButton
@onready var _login_btn: Button = %LoginButton
@onready var _logout_btn: Button = %LogoutButton
@onready var _assign_btn: Button = %AssignButton
@onready var _join_btn: Button = %JoinMatchButton
@onready var _connect_btn: Button = %ConnectButton
@onready var _leave_btn: Button = %LeaveButton
@onready var _close_btn: Button = %CloseButton
@onready var _dev_token_edit: LineEdit = %DevVerifyToken


func _ready() -> void:
	if auth == null:
		auth = AuthSession.new()
		auth.name = "AuthSession"
		add_child(auth)
	auth.configure(_base_url.text.strip_edges())
	assignment_client = AssignmentClient.new()
	assignment_client.auth = auth
	assignment_client.mode = "wildboat"
	_assign_mode.clear()
	_assign_mode.add_item("wildboat (real Online)", 0)
	_assign_mode.add_item("local_stub (dev only — NOT real Online)", 1)
	_assign_mode.select(0)
	_wire_buttons()
	_set_status(STATUS_IDLE)
	_refresh_match_status()
	_refresh_identity()
	_refresh_action_buttons()
	var restored: Dictionary = await auth.restore_session()
	if bool(restored.get("ok", false)):
		_set_status("Session restored — you can Join Match")
		_refresh_identity()
		_refresh_action_buttons()


func _wire_buttons() -> void:
	_register_btn.pressed.connect(_on_register)
	_verify_btn.pressed.connect(_on_verify)
	_login_btn.pressed.connect(_on_login)
	_logout_btn.pressed.connect(_on_logout)
	_assign_btn.pressed.connect(_on_assign)
	_join_btn.pressed.connect(_on_join_match)
	_connect_btn.pressed.connect(_on_connect)
	_leave_btn.pressed.connect(_on_leave)
	_close_btn.pressed.connect(_on_close)


func _on_close() -> void:
	_disconnect_client("Closed Online panel")
	closed.emit()
	visible = false


func _on_leave() -> void:
	if _phase == PHASE_IN_MATCH or _phase == PHASE_CONNECTING or _client != null:
		_disconnect_client("Left match — back in Online lobby")
	else:
		_set_status("Not in a match")
	_refresh_match_status()
	_refresh_action_buttons()


func _on_register() -> void:
	if _busy:
		return
	_busy = true
	_phase = PHASE_BUSY
	_set_status("Registering…")
	_refresh_action_buttons()
	auth.configure(_base_url.text.strip_edges())
	var res: Dictionary = await auth.register(_email.text, _password.text, _display.text)
	_busy = false
	_phase = PHASE_IDLE
	if bool(res.get("ok", false)):
		var body: Variant = res.get("body")
		var tip: String = "Registered"
		if typeof(body) == TYPE_DICTIONARY:
			var d: Dictionary = body
			if d.has("dev_verification_token"):
				_dev_token_edit.text = str(d["dev_verification_token"])
				tip = "Registered — token filled; click Verify"
		_set_status(tip)
	else:
		_show_err(res.get("error") as WildboatError)
	_refresh_action_buttons()


func _on_verify() -> void:
	if _busy:
		return
	_busy = true
	_phase = PHASE_BUSY
	_set_status("Verifying email…")
	_refresh_action_buttons()
	var res: Dictionary = await auth.verify_email(_dev_token_edit.text)
	_busy = false
	_phase = PHASE_IDLE
	if bool(res.get("ok", false)):
		_set_status("Email verified — click Login")
	else:
		_show_err(res.get("error") as WildboatError)
	_refresh_action_buttons()


func _on_login() -> void:
	if _busy:
		return
	_busy = true
	_phase = PHASE_BUSY
	_set_status("Logging in…")
	_refresh_action_buttons()
	auth.configure(_base_url.text.strip_edges())
	var res: Dictionary = await auth.login(_email.text, _password.text)
	_busy = false
	_phase = PHASE_IDLE
	if bool(res.get("ok", false)):
		_set_status("Logged in — click Join Match (or Assign then Connect)")
		_refresh_identity()
	else:
		_show_err(res.get("error") as WildboatError)
		_refresh_identity()
	_refresh_action_buttons()


func _on_logout() -> void:
	if _busy:
		return
	_busy = true
	_phase = PHASE_BUSY
	await auth.logout()
	_busy = false
	_disconnect_client("Logged out")
	_set_status("Logged out")
	_refresh_identity()
	_refresh_action_buttons()


func _on_assign() -> void:
	if _busy:
		return
	var ok: bool = await _request_assignment()
	if ok:
		_set_status("Assigned — click Connect DS (or use Join Match next time)")


## 一键：真实 assign → 用返回的 game_ticket 连 DS。失败时绝不假装成功。
func _on_join_match() -> void:
	if _busy:
		return
	if not auth.is_authenticated():
		_set_status("Login required before Join Match")
		return
	if _assign_mode.selected == 1:
		_set_status("Join Match only uses wildboat (real). Switch mode or use Assign+Connect for stub.")
		return
	var ok: bool = await _request_assignment()
	if not ok:
		return
	await _connect_with_last_assignment()


func _request_assignment() -> bool:
	if not auth.is_authenticated():
		_set_status("Login required for assignment")
		return false
	_busy = true
	_phase = PHASE_BUSY
	_set_status("Requesting assignment…")
	_refresh_action_buttons()
	## 显式选择；wildboat 失败时绝不静默切 local_stub。
	assignment_client.mode = "local_stub" if _assign_mode.selected == 1 else "wildboat"
	assignment_client.stub_host = _host.text.strip_edges()
	assignment_client.stub_port = int(_port.text.strip_edges())
	var res: Dictionary = await assignment_client.request_assignment("coop_survival")
	_busy = false
	_phase = PHASE_IDLE
	_refresh_action_buttons()
	if not bool(res.get("ok", false)):
		_show_err(res.get("error") as WildboatError)
		return false
	var assignment: MatchAssignment = res.get("assignment") as MatchAssignment
	if assignment == null:
		_set_status("Assignment missing — NOT matched")
		return false
	if assignment_client.mode == "wildboat" and assignment.source != "wildboat":
		_set_status("Refusing non-wildboat ticket in wildboat mode — NOT matched")
		return false
	_host.text = assignment.host
	_port.text = str(assignment.port)
	set_meta("last_assignment", assignment)
	_set_status("Assigned match=%s source=%s" % [assignment.match_id, assignment.source])
	_refresh_match_status()
	return true


func _on_connect() -> void:
	if _busy:
		return
	await _connect_with_last_assignment()


func _connect_with_last_assignment() -> void:
	_disconnect_client("")
	var assignment: MatchAssignment = _last_assignment()
	var ticket: String = ""
	var host: String = _host.text.strip_edges()
	var port: int = int(_port.text.strip_edges())
	var display_name: String = _display.text.strip_edges()
	var player_id: String = ""
	var match_id: String = ""
	if auth.is_authenticated() and auth.get_identity() != null:
		display_name = auth.get_identity().display_name
		player_id = auth.get_identity().player_id
	if assignment != null:
		ticket = assignment.game_ticket
		host = assignment.host
		port = assignment.port
		match_id = assignment.match_id
		if assignment.source == "wildboat" and ticket.is_empty():
			_set_status("Missing wildboat game_ticket — NOT connected")
			_phase = PHASE_IDLE
			_refresh_action_buttons()
			return
	else:
		## 无 assignment 时允许手工填 host/port + 空 ticket（仅 DS admission=dev）。
		ticket = ""
		if _assign_mode.selected == 0:
			_set_status("No assignment yet — click Join Match or Request Assignment first")
			_phase = PHASE_IDLE
			_refresh_action_buttons()
			return
	_busy = true
	_phase = PHASE_CONNECTING
	_admitted_seat = 0
	_admitted_match = ""
	_last_player_count = 0
	_last_tick = 0
	_set_status("Connecting to Dedicated Server…")
	_refresh_match_status()
	_refresh_action_buttons()
	_client = DedicatedClient.create(display_name, ticket, player_id, match_id)
	## 必须与 DS 同路径：`/root/OnlineChannel`。挂在 OnlinePanel 下会导致 RPC 找不到节点。
	_mount_online_channel(_client)
	_client.admitted.connect(_on_admitted)
	_client.rejected.connect(_on_rejected)
	_client.server_closed.connect(_on_server_closed)
	_client.snapshot_received.connect(_on_snapshot)
	_client.peer_left_seat.connect(_on_peer_left)
	if not _client.connect_to_server(host, port):
		_busy = false
		_phase = PHASE_IDLE
		_set_status(OnlineProtocol.reject_reason_text(OnlineProtocol.RejectReason.CONNECTION_FAILED))
		_disconnect_client("")
		_refresh_action_buttons()


func _on_admitted(seat: int, match_id: String) -> void:
	_busy = false
	_phase = PHASE_IN_MATCH
	_admitted_seat = seat
	_admitted_match = match_id
	_set_status("Connected — entering game world · seat %d · match %s" % [seat, match_id])
	_refresh_match_status()
	_refresh_action_buttons()
	## 通道留在 /root；面板随主菜单销毁，不 close_client。
	GameLaunch.set_net_role(GameLaunch.NetRole.ONLINE)
	GameLaunch.set_local_seat(seat)
	GameLaunch.set_online_match_id(match_id)
	GameLaunch.set_net_play(GameLaunch.NetPlay.COOP)
	GameLaunch.set_arena_id("yard")
	## 脱钩：防止面板销毁时误关通道。
	_client = null
	enter_world.emit(seat, match_id)


func _on_rejected(reason: int) -> void:
	_busy = false
	_phase = PHASE_IDLE
	_set_status("Join failed: %s" % OnlineProtocol.reject_reason_text(reason))
	_disconnect_client("")
	_refresh_match_status()
	_refresh_action_buttons()


func _on_server_closed() -> void:
	_phase = PHASE_IDLE
	_set_status("Server closed — disconnected")
	_disconnect_client("")
	_refresh_match_status()
	_refresh_action_buttons()


func _on_snapshot(tick: int, players: Array, _match_id: String = "") -> void:
	_last_tick = tick
	_last_player_count = players.size()
	_refresh_match_status()


func _on_peer_left(_seat: int) -> void:
	_refresh_match_status()


func _mount_online_channel(client: DedicatedClient) -> void:
	## 先清掉 root 上残留的同名通道，避免二次 Join 撞名。
	var existing: Node = get_tree().root.get_node_or_null(OnlineProtocol.CHANNEL_NODE_NAME)
	if existing != null and existing != client:
		if existing is DedicatedClient:
			(existing as DedicatedClient).close_client()
		existing.queue_free()
	get_tree().root.add_child(client)


func _disconnect_client(status_if_any: String) -> void:
	if _client != null and is_instance_valid(_client):
		_client.close_client()
		_client.queue_free()
	_client = null
	## 兜底：面板关闭后仍可能残留 root 通道。
	## 已 enter_world 后 _client 为空；Leave/Close 仍需清 root 通道。
	var leftover: Node = get_tree().root.get_node_or_null(OnlineProtocol.CHANNEL_NODE_NAME)
	if leftover != null and is_instance_valid(leftover):
		if leftover is DedicatedClient or leftover is OnlineChannel:
			(leftover as OnlineChannel).close_client()
		leftover.queue_free()
	_admitted_seat = 0
	_admitted_match = ""
	_last_player_count = 0
	_last_tick = 0
	_busy = false
	if _phase == PHASE_CONNECTING or _phase == PHASE_IN_MATCH or _phase == PHASE_BUSY:
		_phase = PHASE_IDLE
	if not status_if_any.is_empty():
		_set_status(status_if_any)
	_refresh_match_status()


func _refresh_identity() -> void:
	if not auth.credentials_storage_is_secure():
		_identity.text = "Storage: user:// (NOT secure OS vault)"
	if auth.is_authenticated():
		var idn: PlayerIdentity = auth.get_identity()
		_identity.text = "Player %s (%s) — storage NOT secure" % [idn.display_name, idn.player_id.substr(0, 8)]
	elif _identity != null:
		_identity.text = "Not logged in — storage NOT secure"


func _last_assignment() -> MatchAssignment:
	if not has_meta("last_assignment"):
		return null
	return get_meta("last_assignment") as MatchAssignment


func _refresh_match_status() -> void:
	if _match_status == null:
		return
	var assignment: MatchAssignment = _last_assignment()
	var assign_line: String = "No assignment"
	if assignment != null:
		assign_line = "Assignment source=%s match=%s" % [assignment.source, assignment.match_id]
	var conn: String = "Disconnected"
	if _phase == PHASE_CONNECTING:
		conn = "Connecting…"
	elif _phase == PHASE_IN_MATCH:
		conn = "In match · seat %d · players %d/4 · tick %d" % [
			_admitted_seat, _last_player_count, _last_tick
		]
		if not _admitted_match.is_empty():
			conn += " · match %s" % _admitted_match
	_match_status.text = "%s\n%s" % [assign_line, conn]


func _refresh_action_buttons() -> void:
	var in_match: bool = _phase == PHASE_IN_MATCH
	var connecting: bool = _phase == PHASE_CONNECTING
	var locked: bool = _busy or connecting
	_register_btn.disabled = locked or in_match
	_verify_btn.disabled = locked or in_match
	_login_btn.disabled = locked or in_match
	_logout_btn.disabled = _busy and not in_match
	_assign_btn.disabled = locked or in_match
	_join_btn.disabled = locked or in_match
	_connect_btn.disabled = locked or in_match
	_assign_mode.disabled = locked or in_match
	_leave_btn.disabled = not (in_match or connecting or _client != null)


func _show_err(err: WildboatError) -> void:
	if err == null:
		_set_status("Error — NOT matched")
		return
	## 明确失败，避免被误读成匹配成功。
	_set_status("Failed: %s (%s) — NOT matched" % [err.code, err.message])


func _set_status(text: String) -> void:
	_status.text = text


## 供自动化测试读取当前 UI 相位（不暴露内部实现细节以外的契约）。
func get_connection_phase() -> String:
	return _phase


func get_reported_player_count() -> int:
	return _last_player_count
