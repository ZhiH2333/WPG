extends Control
class_name OnlinePanel

## Online 最小入口：登录 WildBoat → 请求 Assignment → 连接 Dedicated Server。
## 不替代 LAN；本面板与 LanOverlay 并行。
## Assignment 默认 wildboat（POST /v1/games/assign）。local_stub 仅显式联调，失败时不静默降级。

signal closed

const STATUS_IDLE := "Idle"
const STATUS_BUSY := "Working…"

var auth: AuthSession = null
var assignment_client: AssignmentClient = null
var _client: DedicatedClient = null
var _busy: bool = false

@onready var _base_url: LineEdit = %BaseUrl
@onready var _email: LineEdit = %Email
@onready var _password: LineEdit = %Password
@onready var _display: LineEdit = %DisplayName
@onready var _status: Label = %Status
@onready var _identity: Label = %Identity
@onready var _assign_mode: OptionButton = %AssignMode
@onready var _host: LineEdit = %Host
@onready var _port: LineEdit = %Port
@onready var _register_btn: Button = %RegisterButton
@onready var _verify_btn: Button = %VerifyButton
@onready var _login_btn: Button = %LoginButton
@onready var _logout_btn: Button = %LogoutButton
@onready var _assign_btn: Button = %AssignButton
@onready var _connect_btn: Button = %ConnectButton
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
	_assign_mode.add_item("wildboat (real)", 0)
	_assign_mode.add_item("local_stub (dev only)", 1)
	_assign_mode.select(0)
	_wire_buttons()
	_set_status(STATUS_IDLE)
	_refresh_identity()
	var restored: Dictionary = await auth.restore_session()
	if bool(restored.get("ok", false)):
		_set_status("Session restored")
		_refresh_identity()


func _wire_buttons() -> void:
	_register_btn.pressed.connect(_on_register)
	_verify_btn.pressed.connect(_on_verify)
	_login_btn.pressed.connect(_on_login)
	_logout_btn.pressed.connect(_on_logout)
	_assign_btn.pressed.connect(_on_assign)
	_connect_btn.pressed.connect(_on_connect)
	_close_btn.pressed.connect(_on_close)


func _on_close() -> void:
	_disconnect_client()
	closed.emit()
	visible = false


func _on_register() -> void:
	if _busy:
		return
	_busy = true
	_set_status(STATUS_BUSY)
	auth.configure(_base_url.text.strip_edges())
	var res: Dictionary = await auth.register(_email.text, _password.text, _display.text)
	_busy = false
	if bool(res.get("ok", false)):
		var body: Variant = res.get("body")
		var tip: String = "Registered"
		if typeof(body) == TYPE_DICTIONARY:
			var d: Dictionary = body
			if d.has("dev_verification_token"):
				_dev_token_edit.text = str(d["dev_verification_token"])
				tip = "Registered — paste token then Verify"
		_set_status(tip)
	else:
		_show_err(res.get("error") as WildboatError)


func _on_verify() -> void:
	if _busy:
		return
	_busy = true
	_set_status(STATUS_BUSY)
	var res: Dictionary = await auth.verify_email(_dev_token_edit.text)
	_busy = false
	if bool(res.get("ok", false)):
		_set_status("Email verified — login next")
	else:
		_show_err(res.get("error") as WildboatError)


func _on_login() -> void:
	if _busy:
		return
	_busy = true
	_set_status(STATUS_BUSY)
	auth.configure(_base_url.text.strip_edges())
	var res: Dictionary = await auth.login(_email.text, _password.text)
	_busy = false
	if bool(res.get("ok", false)):
		_set_status("Logged in")
		_refresh_identity()
	else:
		_show_err(res.get("error") as WildboatError)
		_refresh_identity()


func _on_logout() -> void:
	if _busy:
		return
	_busy = true
	await auth.logout()
	_busy = false
	_disconnect_client()
	_set_status("Logged out")
	_refresh_identity()


func _on_assign() -> void:
	if _busy:
		return
	if not auth.is_authenticated():
		_set_status("Login required for assignment")
		return
	_busy = true
	_set_status(STATUS_BUSY)
	## 显式选择；wildboat 失败时绝不静默切 local_stub。
	assignment_client.mode = "local_stub" if _assign_mode.selected == 1 else "wildboat"
	assignment_client.stub_host = _host.text.strip_edges()
	assignment_client.stub_port = int(_port.text.strip_edges())
	var res: Dictionary = await assignment_client.request_assignment("coop_survival")
	_busy = false
	if not bool(res.get("ok", false)):
		_show_err(res.get("error") as WildboatError)
		return
	var assignment: MatchAssignment = res.get("assignment") as MatchAssignment
	if assignment == null:
		_set_status("Assignment missing")
		return
	if assignment_client.mode == "wildboat" and assignment.source != "wildboat":
		_set_status("Refusing non-wildboat ticket in wildboat mode")
		return
	_host.text = assignment.host
	_port.text = str(assignment.port)
	set_meta("last_assignment", assignment)
	_set_status("Assigned match=%s source=%s" % [assignment.match_id, assignment.source])


func _on_connect() -> void:
	if _busy:
		return
	_disconnect_client()
	var assignment: MatchAssignment = get_meta("last_assignment", null) as MatchAssignment
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
			_set_status("Missing wildboat game_ticket")
			return
	else:
		## 无 assignment 时允许手工填 host/port + 空 ticket（仅 DS admission=dev 开放模式）。
		ticket = ""
	_busy = true
	_set_status("Connecting…")
	_client = DedicatedClient.create(display_name, ticket, player_id, match_id)
	add_child(_client)
	_client.admitted.connect(_on_admitted)
	_client.rejected.connect(_on_rejected)
	_client.server_closed.connect(_on_server_closed)
	if not _client.connect_to_server(host, port):
		_busy = false
		_set_status("Connect failed")
		_disconnect_client()


func _on_admitted(seat: int, match_id: String) -> void:
	_busy = false
	_set_status("Admitted seat=%d match=%s" % [seat, match_id])


func _on_rejected(reason: int) -> void:
	_busy = false
	_set_status("Rejected reason=%d" % reason)
	_disconnect_client()


func _on_server_closed() -> void:
	_set_status("Server closed")
	_disconnect_client()


func _disconnect_client() -> void:
	if _client != null and is_instance_valid(_client):
		_client.close_client()
		_client.queue_free()
	_client = null


func _refresh_identity() -> void:
	if not auth.credentials_storage_is_secure():
		_identity.text = "Storage: user:// (NOT secure OS vault)"
	if auth.is_authenticated():
		var idn: PlayerIdentity = auth.get_identity()
		_identity.text = "Player %s (%s) — storage NOT secure" % [idn.display_name, idn.player_id.substr(0, 8)]
	elif _identity != null:
		_identity.text = "Not logged in — storage NOT secure"


func _show_err(err: WildboatError) -> void:
	if err == null:
		_set_status("Error")
		return
	_set_status("%s (%s)" % [err.code, err.message])


func _set_status(text: String) -> void:
	_status.text = text
