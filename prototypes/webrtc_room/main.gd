extends Control

## 原型入口。无命令行参数时给人手工建房；有 --role 时给验收脚本。

const RoomSession = preload("res://room_session.gd")

var _session = null
var _cli: bool = false
var _signaling_edit: LineEdit
var _mode_button: OptionButton
var _turn_url_edit: LineEdit
var _turn_user_edit: LineEdit
var _turn_secret_edit: LineEdit
var _room_label: Label
var _room_edit: LineEdit
var _send_edit: LineEdit
var _status_label: Label
var _log: TextEdit

func _ready() -> void:
	_bind_ui()
	var args: Dictionary = _parse_args(OS.get_cmdline_user_args())
	var scenario: String = str(args.get("scenario", ""))
	if scenario == "extension":
		get_tree().quit(_check_extension())
		return
	if scenario == "selftest":
		get_tree().quit(RoomSession.selftest())
		return
	if args.has("role"):
		_cli = true
		_start_session(_options_from_args(args))
		return
	_status_label.text = "先启动信令服务，再创建房间或输入房间码加入"

func _process(_delta: float) -> void:
	if _session != null:
		_session.poll()

func _bind_ui() -> void:
	_signaling_edit = $Margin/VBox/SignalingEdit
	_mode_button = $Margin/VBox/ModeButton
	_turn_url_edit = $Margin/VBox/TurnUrl
	_turn_user_edit = $Margin/VBox/TurnUser
	_turn_secret_edit = $Margin/VBox/TurnSecret
	_room_label = $Margin/VBox/HostRow/RoomLabel
	_room_edit = $Margin/VBox/JoinRow/RoomEdit
	_send_edit = $Margin/VBox/ActionRow/SendEdit
	_status_label = $Margin/VBox/StatusLabel
	_log = $Margin/VBox/Log
	_mode_button.clear()
	_mode_button.add_item("直连")
	_mode_button.add_item("TURN")
	$Margin/VBox/HostRow/HostButton.pressed.connect(_on_host_pressed)
	$Margin/VBox/JoinRow/JoinButton.pressed.connect(_on_join_pressed)
	$Margin/VBox/ActionRow/SendButton.pressed.connect(_on_send_pressed)
	$Margin/VBox/ActionRow/CancelButton.pressed.connect(_on_cancel_pressed)

func _on_host_pressed() -> void:
	var options: Dictionary = _manual_options("host")
	options.erase("room")
	_start_session(options)

func _on_join_pressed() -> void:
	var options: Dictionary = _manual_options("guest")
	options["room"] = _room_edit.text.strip_edges()
	_start_session(options)

func _on_send_pressed() -> void:
	if _session == null:
		return
	var text: String = _send_edit.text
	if text == "":
		return
	if _session.send_text(text):
		_append_log("发出 %s" % text)
		_send_edit.text = ""

func _on_cancel_pressed() -> void:
	if _session != null:
		_session.cancel()

func _manual_options(role: String) -> Dictionary:
	return {
		"role": role,
		"scenario": "manual",
		"signaling": _signaling_edit.text.strip_edges(),
		"mode": "turn" if _mode_button.selected == 1 else "direct",
		"turn_url": _turn_url_edit.text.strip_edges(),
		"turn_user": _turn_user_edit.text.strip_edges(),
		"turn_credential": _turn_secret_edit.text,
		"connect_timeout_ms": 30000,
	}

func _start_session(options: Dictionary) -> void:
	if _session != null:
		_session.cancel()
	_session = RoomSession.new()
	_session.finished.connect(_on_finished)
	_session.link_ready.connect(_on_link_ready)
	_session.text_received.connect(_on_text)
	_session.status_changed.connect(_on_status)
	_session.start(options)

func _on_finished(result: Dictionary) -> void:
	var status: String = str(result.get("status", ""))
	var error: String = str(result.get("error", ""))
	_append_log("结果 %s %s" % [status, error])
	if not _cli:
		return
	get_tree().quit(_exit_code(result))

func _on_link_ready() -> void:
	_append_log("双向数据已通")

func _on_text(text: String) -> void:
	_append_log("收到 %s" % text)

func _on_status(text: String) -> void:
	_status_label.text = text
	if text.begins_with("房间 "):
		_room_label.text = text.trim_prefix("房间 ")

func _exit_code(result: Dictionary) -> int:
	var status: String = str(result.get("status", ""))
	var scenario: String = str(result.get("scenario", ""))
	if scenario == "data" and status == "DATA_OK" and bool(result.get("pong_seen", false)) and bool(result.get("ping_seen", false)):
		return 0
	if scenario == "disconnect" and status == "DISCONNECTED_OK" and bool(result.get("data_was_open", false)):
		return 0
	if scenario == "timeout" and status == "TIMEOUT" and not bool(result.get("data_was_open", false)):
		return 0
	if scenario == "cancel" and status == "CANCELLED" and not bool(result.get("data_was_open", false)):
		return 0
	return 1

func _options_from_args(args: Dictionary) -> Dictionary:
	return {
		"role": str(args.get("role", "")),
		"scenario": str(args.get("scenario", "data")),
		"signaling": str(args.get("signaling", "")),
		"room": str(args.get("room", "")),
		"mode": str(args.get("mode", "direct")),
		"turn_url": str(args.get("turn_url", "")),
		"turn_user": str(args.get("turn_user", "")),
		"turn_credential": str(args.get("turn_credential", "")),
		"stun_url": str(args.get("stun_url", "")),
		"connect_timeout_ms": int(str(args.get("connect_timeout_ms", "20000"))),
		"room_file": str(args.get("room_file", "")),
		"result_file": str(args.get("result_file", "")),
		"port_begin": int(str(args.get("port_begin", "0"))),
		"port_end": int(str(args.get("port_end", "0"))),
	}

func _parse_args(args: PackedStringArray) -> Dictionary:
	var parsed: Dictionary = {}
	for arg in args:
		if not arg.begins_with("--"):
			continue
		var body: String = arg.substr(2)
		var eq: int = body.find("=")
		if eq < 0:
			parsed[body.replace("-", "_")] = "true"
		else:
			parsed[body.substr(0, eq).replace("-", "_")] = body.substr(eq + 1)
	return parsed

func _check_extension() -> int:
	var peer: WebRTCPeerConnection = WebRTCPeerConnection.new()
	var err: Error = peer.initialize({})
	var native: bool = ClassDB.class_exists("WebRTCLibPeerConnection")
	if err != OK or not native:
		print("EXTENSION_FAIL initialize=%s native=%s" % [err, native])
		peer.close()
		return 1
	print("EXTENSION_OK native=WebRTCLibPeerConnection")
	peer.close()
	return 0

func _append_log(line: String) -> void:
	_log.text = "%s%s\n" % [_log.text, line]
	if _cli:
		print(line)
