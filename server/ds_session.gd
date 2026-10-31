extends Node
class_name DsSession

## Dedicated Server 权威会话：准入、身份绑定、移动仿真、快照广播。
## peer 1 = 服务器进程本身，不占玩家座位。座位 1..4 全部是已准入客户端。

signal player_admitted(seat: int, peer_id: int, display_name: String)
signal player_rejected(peer_id: int, reason: int)
signal player_left(seat: int, peer_id: int)
signal listening(port: int)

var config: ServerConfig = null
var _net: DsNet = null
var _channel: OnlineChannel = null
var _players_by_peer: Dictionary = {} ## peer_id -> DsPlayerState
var _players_by_seat: Dictionary = {} ## seat -> DsPlayerState
var _tick: int = 0
var _acc: float = 0.0
var _started: bool = false
var _stopped: bool = true


func setup(cfg: ServerConfig) -> void:
	config = cfg
	_net = DsNet.new()
	_net.name = "DsNet"
	add_child(_net)
	## OnlineChannel 必须挂在 SceneTree.root 下的固定名，才能与客户端 RPC 路径对齐。
	_channel = OnlineChannel.new()
	_channel.configure_server(self)
	get_tree().root.add_child(_channel)
	_net.peer_disconnected.connect(_on_peer_disconnected)


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
	print("WPG_DS_LISTEN port=%d max_players=%d protocol=%d" % [
		config.port, config.max_players, OnlineProtocol.PROTOCOL_VERSION
	])
	return true


func stop() -> void:
	if _stopped:
		return
	_stopped = true
	_started = false
	_clear_ready_file()
	_players_by_peer.clear()
	_players_by_seat.clear()
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


func try_admit(peer_id: int, protocol: int, display_name: String, dev_token: String) -> Dictionary:
	if peer_id <= 1:
		return {"reason": OnlineProtocol.RejectReason.MALFORMED, "seat": 0}
	if protocol != OnlineProtocol.PROTOCOL_VERSION:
		player_rejected.emit(peer_id, OnlineProtocol.RejectReason.BAD_PROTOCOL)
		return {"reason": OnlineProtocol.RejectReason.BAD_PROTOCOL, "seat": 0}
	if not _dev_token_ok(dev_token):
		player_rejected.emit(peer_id, OnlineProtocol.RejectReason.BAD_TOKEN)
		return {"reason": OnlineProtocol.RejectReason.BAD_TOKEN, "seat": 0}
	if _players_by_peer.has(peer_id):
		player_rejected.emit(peer_id, OnlineProtocol.RejectReason.DUPLICATE)
		return {"reason": OnlineProtocol.RejectReason.DUPLICATE, "seat": 0}
	if occupied_count() >= config.max_players:
		player_rejected.emit(peer_id, OnlineProtocol.RejectReason.FULL)
		## 不在这里 disconnect：必须先让 OnlineChannel 发出 rpc_reject，再延迟踢人。
		return {"reason": OnlineProtocol.RejectReason.FULL, "seat": 0}
	var seat: int = _allocate_seat()
	if seat < 1:
		player_rejected.emit(peer_id, OnlineProtocol.RejectReason.FULL)
		return {"reason": OnlineProtocol.RejectReason.FULL, "seat": 0}
	var state := DsPlayerState.new(seat, peer_id, display_name)
	_players_by_peer[peer_id] = state
	_players_by_seat[seat] = state
	player_admitted.emit(seat, peer_id, state.display_name)
	print("WPG_DS_ADMIT seat=%d peer=%d name=%s occupied=%d" % [
		seat, peer_id, state.display_name, occupied_count()
	])
	return {"reason": OnlineProtocol.RejectReason.NONE, "seat": seat}


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


func _dev_token_ok(dev_token: String) -> bool:
	## 空配置 = 本地开放开发模式。配置了 token 则必须精确匹配。
	if config == null or config.dev_token.is_empty():
		return true
	var offered: String = dev_token.substr(0, OnlineProtocol.MAX_DEV_TOKEN_LEN)
	return offered == config.dev_token


func _on_peer_disconnected(peer_id: int) -> void:
	if not _players_by_peer.has(peer_id):
		return
	var state: DsPlayerState = _players_by_peer[peer_id]
	_players_by_peer.erase(peer_id)
	_players_by_seat.erase(state.seat)
	_channel.notify_peer_left(state.seat)
	player_left.emit(state.seat, peer_id)
	print("WPG_DS_LEAVE seat=%d peer=%d occupied=%d" % [state.seat, peer_id, occupied_count()])


func _write_ready_file() -> void:
	if config == null or config.ready_file.is_empty():
		return
	var path: String = config.ready_file
	var body: String = "ready\nport=%d\nmax_players=%d\nprotocol=%d\nmatch_id=%s\n" % [
		config.port, config.max_players, OnlineProtocol.PROTOCOL_VERSION, config.match_id
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
