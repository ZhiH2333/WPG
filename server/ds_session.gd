extends Node
class_name DsSession

## Dedicated Server 权威会话：准入、身份绑定、移动仿真、快照广播。
## peer 1 = 服务器进程本身，不占玩家座位。座位 1..4 全部是已准入客户端。
## 身份来自 TicketValidator 结果，不信任客户端自报 player_id。

signal player_admitted(seat: int, peer_id: int, display_name: String, player_id: String)
signal player_rejected(peer_id: int, reason: int)
signal player_left(seat: int, peer_id: int)
signal listening(port: int)
signal settlement_submitted(ok: bool, settlement_id: String)

var config: ServerConfig = null
var ticket_validator: TicketValidator = null
var server_client: WildboatServerClient = null
var _net: DsNet = null
var _channel: OnlineChannel = null
var _players_by_peer: Dictionary = {} ## peer_id -> DsPlayerState
var _players_by_seat: Dictionary = {} ## seat -> DsPlayerState
var _players_by_player_id: Dictionary = {} ## player_id -> peer_id
var _tick: int = 0
var _acc: float = 0.0
var _started: bool = false
var _stopped: bool = true
var _admit_inflight: Dictionary = {} ## peer_id -> true
var _match_started_at: String = ""
var _last_settlement_id: String = ""
var _settlement_done: bool = false


func setup(cfg: ServerConfig) -> void:
	config = cfg
	_net = DsNet.new()
	_net.name = "DsNet"
	add_child(_net)
	_channel = OnlineChannel.new()
	_channel.configure_server(self)
	get_tree().root.add_child(_channel)
	_net.peer_disconnected.connect(_on_peer_disconnected)
	_install_validator()
	_match_started_at = Time.get_datetime_string_from_system(true) + "Z"


func _install_validator() -> void:
	if ticket_validator != null:
		return
	match config.admission_mode:
		OnlineProtocol.AdmissionMode.STUB:
			ticket_validator = StubTicketValidator.new()
		OnlineProtocol.AdmissionMode.WILDBOAT:
			server_client = WildboatServerClient.new()
			server_client.name = "WildboatServerClient"
			add_child(server_client)
			server_client.configure(
				config.wildboat_base_url,
				config.wildboat_server_token,
				5.0
			)
			ticket_validator = WildboatTicketValidator.new(server_client, config.server_build)
		_:
			ticket_validator = DevTicketValidator.new(
				config.dev_token, config.match_id, config.game_instance_id
			)


func start() -> bool:
	if config == null:
		config = ServerConfig.from_environment()
	if _net == null:
		setup(config)
	var ok: bool = _net.host_listen(config.port, config.max_players)
	if not ok:
		return false
	_write_ready_file()
	_started = true
	_stopped = false
	listening.emit(config.port)
	print("WPG_DS_LISTEN port=%d max_players=%d protocol=%d admission=%d" % [
		config.port, config.max_players, OnlineProtocol.PROTOCOL_VERSION, config.admission_mode
	])
	return true


func stop() -> void:
	if _stopped:
		return
	_stopped = true
	_started = false
	## 结算走显式 submit_settlement_minimal()；stop 路径不 await 网络，避免退出卡死。
	_clear_ready_file()
	_players_by_peer.clear()
	_players_by_seat.clear()
	_players_by_player_id.clear()
	if _net != null:
		_net.close()
	if _channel != null and is_instance_valid(_channel):
		var ch: OnlineChannel = _channel
		_channel = null
		if ch.get_parent() != null:
			ch.get_parent().remove_child(ch)
		ch.free()


func get_match_id() -> String:
	if config == null:
		return "dev_match"
	return config.match_id


func get_game_instance_id() -> String:
	if config == null:
		return "dev_instance"
	return config.game_instance_id


func get_tick() -> int:
	return _tick


func occupied_count() -> int:
	return _players_by_seat.size()


func get_players() -> Array:
	var seats: Array = _players_by_seat.keys()
	seats.sort()
	var out: Array = []
	for seat in seats:
		out.append(_players_by_seat[seat])
	return out


## 同步准入（dev/stub 或已完成校验的结果注入）。WildBoat 模式请用 try_admit_async。
func try_admit(peer_id: int, protocol: int, display_name: String, game_ticket: String) -> Dictionary:
	if peer_id <= 1:
		return {"reason": OnlineProtocol.RejectReason.MALFORMED, "seat": 0}
	if protocol != OnlineProtocol.PROTOCOL_VERSION:
		player_rejected.emit(peer_id, OnlineProtocol.RejectReason.BAD_PROTOCOL)
		return {"reason": OnlineProtocol.RejectReason.BAD_PROTOCOL, "seat": 0}
	if ticket_validator == null:
		_install_validator()
	var ticket: String = game_ticket.substr(0, OnlineProtocol.MAX_GAME_TICKET_LEN)
	var validated: Dictionary
	if ticket_validator is WildboatTicketValidator:
		## 同步路径对在线校验直接失败，避免假成功。
		validated = ticket_validator.validate(ticket, get_match_id(), get_game_instance_id())
	else:
		validated = ticket_validator.validate(ticket, get_match_id(), get_game_instance_id())
	return _finish_admit(peer_id, display_name, validated)


func try_admit_async(peer_id: int, protocol: int, display_name: String, game_ticket: String) -> Dictionary:
	if peer_id <= 1:
		return {"reason": OnlineProtocol.RejectReason.MALFORMED, "seat": 0}
	if protocol != OnlineProtocol.PROTOCOL_VERSION:
		player_rejected.emit(peer_id, OnlineProtocol.RejectReason.BAD_PROTOCOL)
		return {"reason": OnlineProtocol.RejectReason.BAD_PROTOCOL, "seat": 0}
	if _admit_inflight.get(peer_id, false):
		return {"reason": OnlineProtocol.RejectReason.DUPLICATE, "seat": 0}
	_admit_inflight[peer_id] = true
	if ticket_validator == null:
		_install_validator()
	var ticket: String = game_ticket.substr(0, OnlineProtocol.MAX_GAME_TICKET_LEN)
	var validated: Dictionary
	if ticket_validator is WildboatTicketValidator:
		validated = await (ticket_validator as WildboatTicketValidator).validate_async(
			ticket, get_match_id(), get_game_instance_id()
		)
	else:
		validated = ticket_validator.validate(ticket, get_match_id(), get_game_instance_id())
	var result: Dictionary = _finish_admit(peer_id, display_name, validated)
	_admit_inflight.erase(peer_id)
	return result


func _finish_admit(peer_id: int, client_display_name: String, validated: Dictionary) -> Dictionary:
	if not bool(validated.get("ok", false)):
		var reason: int = int(validated.get("reason", OnlineProtocol.RejectReason.BAD_TOKEN))
		player_rejected.emit(peer_id, reason)
		return {"reason": reason, "seat": 0}
	if _players_by_peer.has(peer_id):
		player_rejected.emit(peer_id, OnlineProtocol.RejectReason.DUPLICATE)
		return {"reason": OnlineProtocol.RejectReason.DUPLICATE, "seat": 0}
	var player_id: String = str(validated.get("player_id", ""))
	if not player_id.is_empty() and _players_by_player_id.has(player_id):
		player_rejected.emit(peer_id, OnlineProtocol.RejectReason.DUPLICATE)
		return {"reason": OnlineProtocol.RejectReason.DUPLICATE, "seat": 0}
	if occupied_count() >= config.max_players:
		player_rejected.emit(peer_id, OnlineProtocol.RejectReason.FULL)
		return {"reason": OnlineProtocol.RejectReason.FULL, "seat": 0}
	var seat: int = _allocate_seat()
	if seat < 1:
		player_rejected.emit(peer_id, OnlineProtocol.RejectReason.FULL)
		return {"reason": OnlineProtocol.RejectReason.FULL, "seat": 0}
	## 显示名：优先校验结果，其次客户端（截断）；绝不采用客户端 player_id。
	var display: String = str(validated.get("display_name", ""))
	if display.is_empty():
		display = client_display_name
	var state := DsPlayerState.new(seat, peer_id, display, player_id)
	_players_by_peer[peer_id] = state
	_players_by_seat[seat] = state
	if not player_id.is_empty():
		_players_by_player_id[player_id] = peer_id
	player_admitted.emit(seat, peer_id, state.display_name, player_id)
	print("WPG_DS_ADMIT seat=%d peer=%d occupied=%d" % [seat, peer_id, occupied_count()])
	return {"reason": OnlineProtocol.RejectReason.NONE, "seat": seat, "player_id": player_id}


func kick_peer(peer_id: int) -> void:
	if _net != null:
		_net.disconnect_peer(peer_id)


func apply_input(peer_id: int, mx: float, my: float) -> void:
	if not _players_by_peer.has(peer_id):
		return
	if not is_finite(mx) or not is_finite(my):
		return
	if absf(mx) > 1.5 or absf(my) > 1.5:
		return
	var state: DsPlayerState = _players_by_peer[peer_id]
	state.apply_input(mx, my, Time.get_ticks_msec())


func submit_settlement_minimal(result: String = "completed") -> Dictionary:
	if _settlement_done and not _last_settlement_id.is_empty():
		return {"ok": true, "duplicate": true, "settlement_id": _last_settlement_id}
	var payload: SettlementPayload = SettlementPayload.make_minimal(
		get_match_id(),
		get_game_instance_id(),
		get_players(),
		"coop_survival",
		result
	)
	payload.started_at = _match_started_at
	payload.ended_at = Time.get_datetime_string_from_system(true) + "Z"
	_last_settlement_id = payload.settlement_id
	if server_client == null:
		if config != null and config.admission_mode == OnlineProtocol.AdmissionMode.WILDBOAT:
			settlement_submitted.emit(false, payload.settlement_id)
			return {"ok": false, "settlement_id": payload.settlement_id, "error": "no_server_client"}
		## stub/dev：本地记录成功结构，不伪装云端已入账。
		_settlement_done = true
		print("WPG_DS_SETTLEMENT_LOCAL id=%s players=%d" % [payload.settlement_id, payload.players.size()])
		settlement_submitted.emit(true, payload.settlement_id)
		return {"ok": true, "local": true, "settlement_id": payload.settlement_id, "payload": payload.to_dict()}
	var res: Dictionary = await server_client.submit_settlement(
		payload.match_id, payload.to_dict(), payload.settlement_id
	)
	var ok: bool = bool(res.get("ok", false))
	if ok:
		_settlement_done = true
		print("WPG_DS_SETTLEMENT_OK id=%s" % payload.settlement_id)
	else:
		## 失败不得伪装成功。
		print("WPG_DS_SETTLEMENT_FAIL id=%s" % payload.settlement_id)
	settlement_submitted.emit(ok, payload.settlement_id)
	res["settlement_id"] = payload.settlement_id
	return res


func _process(delta: float) -> void:
	if not _started:
		return
	for state in _players_by_peer.values():
		(state as DsPlayerState).simulate(delta)
	_acc += delta
	var interval: float = config.snapshot_interval() if config != null else OnlineProtocol.SNAPSHOT_INTERVAL
	if _acc < interval:
		return
	_acc = 0.0
	_tick += 1
	var data: PackedByteArray = OnlineProtocol.encode_snapshot(_tick, get_players())
	_channel.broadcast_snapshot(data)


func _allocate_seat() -> int:
	for seat in range(1, config.max_players + 1):
		if not _players_by_seat.has(seat):
			return seat
	return 0


func _on_peer_disconnected(peer_id: int) -> void:
	_admit_inflight.erase(peer_id)
	if not _players_by_peer.has(peer_id):
		return
	var state: DsPlayerState = _players_by_peer[peer_id]
	_players_by_peer.erase(peer_id)
	_players_by_seat.erase(state.seat)
	if not state.player_id.is_empty():
		_players_by_player_id.erase(state.player_id)
	_channel.notify_peer_left(state.seat)
	player_left.emit(state.seat, peer_id)
	print("WPG_DS_LEAVE seat=%d peer=%d occupied=%d" % [state.seat, peer_id, occupied_count()])


func _write_ready_file() -> void:
	if config == null or config.ready_file.is_empty():
		return
	var path: String = config.ready_file
	var body: String = "ready\nport=%d\nmax_players=%d\nprotocol=%d\nmatch_id=%s\ninstance_id=%s\nadmission=%d\n" % [
		config.port, config.max_players, OnlineProtocol.PROTOCOL_VERSION,
		config.match_id, config.game_instance_id, config.admission_mode
	]
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_warning("DsSession: cannot write ready file %s" % path)
		return
	file.store_string(body)


func _clear_ready_file() -> void:
	if config == null or config.ready_file.is_empty():
		return
	var path: String = config.ready_file
	var absolute: String = path
	if path.begins_with("user://") or path.begins_with("res://"):
		absolute = ProjectSettings.globalize_path(path)
	if FileAccess.file_exists(path) or FileAccess.file_exists(absolute):
		DirAccess.remove_absolute(absolute)


func _exit_tree() -> void:
	stop()
