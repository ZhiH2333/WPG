extends RefCounted

## 房间码会话。信令只交换 SDP/ICE；游戏字节走 WebRTC DataChannel。
## 这个对象不属于生产 LobbyNet，也不会去改 SceneTree.multiplayer_peer。

signal finished(result: Dictionary)
signal link_ready
signal text_received(text: String)
signal status_changed(text: String)

const DEFAULT_TIMEOUT_MS: int = 20000

const SignalingClient = preload("res://signaling_client.gd")

var _signaling = SignalingClient.new()
var _role: String = ""
var _scenario: String = ""
var _mode: String = "direct"
var _room_code: String = ""
var _token: String = ""
var _after: int = 0
var _timeout_ms: int = DEFAULT_TIMEOUT_MS
var _started_ms: int = 0
var _room_file: String = ""
var _result_file: String = ""
var _turn_url: String = ""
var _turn_user: String = ""
var _turn_credential: String = ""
var _stun_url: String = ""
var _port_begin: int = 0
var _port_end: int = 0
var _pc: WebRTCPeerConnection = null
var _channel: WebRTCDataChannel = null
var _outbox: Array = []
var _inflight_kind: String = ""
var _remote_set: bool = false
var _pending_ice: Array = []
var _cancel_pending: bool = false
var _did_finish: bool = false
var _data_was_open: bool = false
var _ping_sent: bool = false
var _ping_seen: bool = false
var _pong_seen: bool = false
var _done_sent: bool = false
var _done_seen: bool = false
var _handshake_completed: bool = false
var _pending_status: String = ""
var _exit_polls: int = 0
var _local_nonce: String = ""
var _disconnect_closing: bool = false
var _bye_posted: bool = false
var _relay_candidates: int = 0
var _host_candidates: int = 0
var _srflx_candidates: int = 0
var _other_candidates: int = 0

static func classify_candidate(candidate: String) -> String:
	if candidate.find(" typ relay") >= 0:
		return "relay"
	if candidate.find(" typ srflx") >= 0:
		return "srflx"
	if candidate.find(" typ host") >= 0:
		return "host"
	return "other"

func start(options: Dictionary) -> void:
	_role = str(options.get("role", ""))
	_scenario = str(options.get("scenario", "manual"))
	_mode = str(options.get("mode", "direct"))
	_room_code = str(options.get("room", "")).strip_edges()
	_timeout_ms = int(options.get("connect_timeout_ms", DEFAULT_TIMEOUT_MS))
	_room_file = str(options.get("room_file", ""))
	_result_file = str(options.get("result_file", ""))
	_turn_url = str(options.get("turn_url", ""))
	_turn_user = str(options.get("turn_user", ""))
	_turn_credential = str(options.get("turn_credential", ""))
	_stun_url = str(options.get("stun_url", ""))
	_port_begin = int(options.get("port_begin", 0))
	_port_end = int(options.get("port_end", 0))
	_started_ms = Time.get_ticks_msec()
	if not _signaling.setup(str(options.get("signaling", ""))):
		_finish("FAILED", "BAD_SIGNALING_URL")
		return
	if _role != "host" and _role != "guest":
		_finish("FAILED", "BAD_ROLE")
		return
	if _mode == "turn" and _turn_url == "":
		_finish("FAILED", "MISSING_TURN")
		return
	if _role == "guest" and _room_code == "":
		_finish("FAILED", "MISSING_ROOM")
		return
	_signaling.completed.connect(_on_http)
	_set_status("正在连接信令")
	if _role == "host":
		if not _signaling.create_room():
			_finish("FAILED", "HTTP_START")
	else:
		if not _signaling.join_room(_room_code):
			_finish("FAILED", "HTTP_START")

func poll() -> void:
	if _did_finish:
		return
	_signaling.poll()
	if not _signaling.is_busy():
		_pump_http()
	_poll_link()
	_check_deadline()

func send_text(text: String) -> bool:
	if _channel == null or _channel.get_ready_state() != WebRTCDataChannel.STATE_OPEN:
		return false
	_send_json({"t": "text", "text": text})
	return true

func cancel() -> void:
	if _did_finish:
		return
	_cancel_pending = true
	_queue_bye()
	_close_pc()

static func selftest() -> int:
	if classify_candidate("candidate:1 1 UDP 1 10.0.0.1 9 typ host") != "host":
		print("SELFTEST_FAIL host")
		return 1
	if classify_candidate("candidate:2 1 UDP 1 1.2.3.4 9 typ srflx") != "srflx":
		print("SELFTEST_FAIL srflx")
		return 1
	if classify_candidate("candidate:3 1 UDP 1 5.6.7.8 9 typ relay raddr 0.0.0.0 rport 0") != "relay":
		print("SELFTEST_FAIL relay")
		return 1
	if classify_candidate("candidate:4 typ unknown") != "other":
		print("SELFTEST_FAIL other")
		return 1
	print("SELFTEST_OK")
	return 0

func _on_http(op: String, http_status: int, payload: Dictionary, error: String) -> void:
	if _did_finish:
		return
	if error == "HTTP_TIMEOUT" or error == "HTTP_CONNECT" or error == "HTTP_DISCONNECTED" or error == "HTTP_REQUEST" or error == "BAD_JSON":
		_finish("FAILED", error)
		return
	if op == "create":
		_on_created(http_status, payload, error)
		return
	if op == "join":
		_on_joined(http_status, payload, error)
		return
	if op == "post":
		_on_posted(http_status, error)
		return
	if op == "get":
		_on_polled(http_status, payload, error)

func _on_created(http_status: int, payload: Dictionary, error: String) -> void:
	if http_status != 201 or error != "":
		_finish("FAILED", _http_error(error, http_status))
		return
	_room_code = str(payload.get("room_code", ""))
	_token = str(payload.get("token", ""))
	_write_text(_room_file, _room_code)
	print("ROOM %s" % _room_code)
	_set_status("房间 %s" % _room_code)
	_begin_link()

func _on_joined(http_status: int, payload: Dictionary, error: String) -> void:
	if http_status != 200 or error != "":
		_finish("FAILED", _http_error(error, http_status))
		return
	_token = str(payload.get("token", ""))
	_set_status("已加入 %s" % _room_code)
	_begin_link()

func _on_posted(http_status: int, error: String) -> void:
	var kind: String = _inflight_kind
	_inflight_kind = ""
	if http_status != 200 or error != "":
		if _cancel_pending and (http_status == 410 or error == "ROOM_CLOSED"):
			_finish("CANCELLED")
			return
		_finish("FAILED", _http_error(error, http_status))
		return
	if kind == "bye":
		_bye_posted = true
		if _cancel_pending or _scenario == "cancel":
			_close_pc()
			_finish("CANCELLED")
			return
	_maybe_disconnect_done()

func _on_polled(http_status: int, payload: Dictionary, error: String) -> void:
	if http_status != 200 or error != "":
		_finish("FAILED", _http_error(error, http_status))
		return
	_after = int(payload.get("cursor", _after))
	var messages: Variant = payload.get("messages", [])
	if typeof(messages) != TYPE_ARRAY:
		_finish("FAILED", "BAD_INBOX")
		return
	for item in messages:
		if typeof(item) == TYPE_DICTIONARY:
			_apply_signal(item)

func _begin_link() -> void:
	if not _setup_pc():
		return
	if _scenario == "cancel" and _role == "guest":
		_cancel_pending = true
		_queue_bye()
		return
	if _role == "host":
		_channel = _pc.create_data_channel("wpg", {})
		if _channel == null:
			_finish("FAILED", "NO_CHANNEL")
			return
		var offer_err: Error = _pc.create_offer()
		if offer_err != OK:
			_finish("FAILED", "OFFER_%s" % offer_err)

func _setup_pc() -> bool:
	_pc = WebRTCPeerConnection.new()
	var err: Error = _pc.initialize(_ice_config())
	if err != OK:
		_finish("FAILED", "WEBRTC_INIT_%s" % err)
		return false
	_pc.session_description_created.connect(_on_local_description)
	_pc.ice_candidate_created.connect(_on_local_candidate)
	_pc.data_channel_received.connect(_on_data_channel)
	_set_status("正在建立 WebRTC")
	return true

func _ice_config() -> Dictionary:
	var config: Dictionary = {}
	var servers: Array = []
	if _stun_url != "":
		servers.append({"urls": [_stun_url]})
	if _mode == "turn":
		servers.append({
			"urls": [_turn_url],
			"username": _turn_user,
			"credential": _turn_credential,
		})
	if servers.size() > 0:
		config["iceServers"] = servers
	if _port_begin > 0 and _port_end >= _port_begin:
		config["libdatachannel"] = {
			"portRangeBegin": _port_begin,
			"portRangeEnd": _port_end,
			"enableIceTcp": false,
		}
	return config

func _on_local_description(type: String, sdp: String) -> void:
	if _cancel_pending:
		return
	_outbox.append({"kind": type, "sdp": sdp})

func _on_local_candidate(media: String, index: int, name: String) -> void:
	var kind: String = classify_candidate(name)
	if kind == "relay":
		_relay_candidates += 1
	elif kind == "host":
		_host_candidates += 1
	elif kind == "srflx":
		_srflx_candidates += 1
	else:
		_other_candidates += 1
	if _cancel_pending:
		return
	_outbox.append({"kind": "ice", "candidate": name, "mid": media})

func _on_data_channel(channel: WebRTCDataChannel) -> void:
	if _channel != null:
		return
	_channel = channel

func _apply_signal(message: Dictionary) -> void:
	var kind: String = str(message.get("kind", ""))
	if kind == "bye":
		_on_peer_bye()
		return
	if _cancel_pending:
		return
	if kind == "offer" or kind == "answer":
		_apply_description(kind, str(message.get("sdp", "")))
		return
	if kind == "ice":
		_apply_ice(str(message.get("mid", "")), str(message.get("candidate", "")))

func _apply_description(type: String, sdp: String) -> void:
	if _remote_set:
		_finish("FAILED", "DUPLICATE_DESCRIPTION")
		return
	var err: Error = _pc.set_remote_description(type, sdp)
	if err != OK:
		_finish("FAILED", "REMOTE_SDP_%s" % err)
		return
	_remote_set = true
	for item in _pending_ice:
		_add_ice(str(item[0]), str(item[1]))
	_pending_ice.clear()

func _apply_ice(mid: String, candidate: String) -> void:
	if candidate == "":
		return
	if not _remote_set:
		_pending_ice.append([mid, candidate])
		return
	_add_ice(mid, candidate)

func _add_ice(mid: String, candidate: String) -> void:
	if _pc == null or not is_instance_valid(_pc):
		return
	var err: Error = _pc.add_ice_candidate(mid, 0, candidate)
	if err != OK and not _data_was_open and not _handshake_completed and not _disconnect_closing:
		_finish("FAILED", "REMOTE_ICE_%s" % err)

func _on_peer_bye() -> void:
	if _scenario == "cancel" or _cancel_pending:
		_close_pc()
		if _data_was_open:
			_finish("FAILED", "CANCEL_AFTER_DATA")
			return
		_finish("CANCELLED")
		return
	if _scenario == "disconnect" and _data_was_open:
		_close_pc()
		_maybe_disconnect_done()
		return
	if _scenario == "manual" and _data_was_open:
		_close_pc()
		_finish("DISCONNECTED_OK")
		return
	_close_pc()
	_finish("FAILED", "PEER_BYE")

func _poll_link() -> void:
	if _pc != null:
		_pc.poll()
	if _channel != null:
		_channel.poll()
		_drain_channel()
		_check_channel_open()
	_maybe_handshake()
	_drain_exit()
	_maybe_disconnect_done()

func _check_channel_open() -> void:
	if _ping_sent or _channel.get_ready_state() != WebRTCDataChannel.STATE_OPEN:
		return
	_data_was_open = true
	_ping_sent = true
	_local_nonce = Crypto.new().generate_random_bytes(8).hex_encode()
	_send_json({"t": "ping", "n": _local_nonce, "from": _role})
	_set_status("数据通道已打开")

func _drain_channel() -> void:
	while _channel.get_available_packet_count() > 0:
		var text: String = _channel.get_packet().get_string_from_utf8()
		var parsed: Variant = JSON.parse_string(text)
		if typeof(parsed) != TYPE_DICTIONARY:
			text_received.emit(text)
			continue
		_on_packet(parsed)

func _on_packet(packet: Dictionary) -> void:
	var kind: String = str(packet.get("t", ""))
	if kind == "ping":
		_ping_seen = true
		_send_json({"t": "pong", "n": str(packet.get("n", "")), "from": _role})
		return
	if kind == "pong" and str(packet.get("n", "")) == _local_nonce:
		_pong_seen = true
		return
	if kind == "done":
		_done_seen = true
		return
	if kind == "text":
		text_received.emit(str(packet.get("text", "")))
		return
	if kind == "close":
		_close_pc()

func _maybe_handshake() -> void:
	if _handshake_completed or not _pong_seen or not _ping_seen:
		return
	if _channel == null or _channel.get_ready_state() != WebRTCDataChannel.STATE_OPEN:
		return
	if not _done_sent:
		_done_sent = true
		_send_json({"t": "done", "from": _role})
	if _done_sent and _done_seen:
		_on_handshake_complete()

func _on_handshake_complete() -> void:
	if _handshake_completed:
		return
	_handshake_completed = true
	if _scenario == "data":
		_pending_status = "DATA_OK"
		_exit_polls = 2
		return
	if _scenario == "manual":
		_set_status("双向数据已通")
		link_ready.emit()
		return
	if _scenario == "disconnect" and _role == "host":
		_send_json({"t": "close", "from": _role})
		_pending_status = "CLOSE_LINK"
		_exit_polls = 2

func _drain_exit() -> void:
	if _exit_polls <= 0:
		return
	_exit_polls -= 1
	if _exit_polls > 0:
		return
	if _pending_status == "DATA_OK":
		_finish("DATA_OK")
		return
	if _pending_status == "CLOSE_LINK":
		_disconnect_closing = true
		_close_pc()
		_queue_bye()

func _maybe_disconnect_done() -> void:
	if _did_finish or _scenario != "disconnect" or not _data_was_open or not _pong_seen:
		return
	if not _link_is_down():
		return
	if _role == "host" and not _bye_posted:
		return
	_finish("DISCONNECTED_OK")

func _link_is_down() -> bool:
	if _pc == null:
		return true
	var state: int = _pc.get_connection_state()
	if state == WebRTCPeerConnection.STATE_DISCONNECTED or state == WebRTCPeerConnection.STATE_FAILED or state == WebRTCPeerConnection.STATE_CLOSED:
		return true
	if _channel != null and _channel.get_ready_state() == WebRTCDataChannel.STATE_CLOSED:
		return true
	return false

func _pump_http() -> void:
	if _did_finish or _token == "" or _signaling.is_busy():
		return
	if _outbox.size() > 0:
		var fields: Dictionary = _outbox.pop_front()
		_inflight_kind = str(fields.get("kind", ""))
		if not _signaling.post_signal(_room_code, _token, fields):
			_finish("FAILED", "HTTP_START")
		return
	if not _signaling.get_signals(_room_code, _token, _after):
		_finish("FAILED", "HTTP_START")

func _queue_bye() -> void:
	for item in _outbox:
		if str(item.get("kind", "")) == "bye":
			return
	if _inflight_kind == "bye":
		return
	_outbox.append({"kind": "bye"})

func _send_json(packet: Dictionary) -> void:
	if _channel == null or _channel.get_ready_state() != WebRTCDataChannel.STATE_OPEN:
		return
	_channel.put_packet(JSON.stringify(packet).to_utf8_buffer())

func _close_pc() -> void:
	if _channel != null and is_instance_valid(_channel):
		var channel_state: int = _channel.get_ready_state()
		if channel_state == WebRTCDataChannel.STATE_OPEN or channel_state == WebRTCDataChannel.STATE_CONNECTING:
			_channel.close()
	if _pc != null and is_instance_valid(_pc):
		_pc.close()

func _check_deadline() -> void:
	if _did_finish:
		return
	if Time.get_ticks_msec() - _started_ms < _timeout_ms:
		return
	_close_pc()
	if _scenario == "timeout" and not _data_was_open:
		_finish("TIMEOUT")
		return
	_finish("FAILED", "DEADLINE")

func _finish(status: String, error: String = "") -> void:
	if _did_finish:
		return
	_did_finish = true
	var result: Dictionary = {
		"status": status,
		"error": error,
		"room_code": _room_code,
		"elapsed_ms": Time.get_ticks_msec() - _started_ms,
		"data_was_open": _data_was_open,
		"relay_candidates": _relay_candidates,
		"host_candidates": _host_candidates,
		"srflx_candidates": _srflx_candidates,
		"other_candidates": _other_candidates,
		"pong_seen": _pong_seen,
		"ping_seen": _ping_seen,
		"role": _role,
		"scenario": _scenario,
		"mode": _mode,
	}
	_write_text(_result_file, JSON.stringify(result))
	print("RESULT %s" % JSON.stringify(result))
	_set_status("%s %s" % [status, error])
	finished.emit(result)

func _set_status(text: String) -> void:
	status_changed.emit(text)

func _http_error(error: String, http_status: int) -> String:
	if error != "":
		return error
	return "HTTP_%d" % http_status

func _write_text(path: String, text: String) -> void:
	if path == "":
		return
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(text)
	file.close()
