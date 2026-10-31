extends Node
class_name OnlineChannel

## Online Dedicated Server 共享 RPC 通道。
## Server 与 Client 必须以相同节点名 OnlineProtocol.CHANNEL_NODE_NAME 挂到 SceneTree，
## 以便 Godot 按路径路由 RPC。本通道与 LobbyNet / NetSession 的 RPC 表完全隔离。
##
## Phase 2A 消息：
## - Client -> Server: hello(dev identity), input(intent)
## - Server -> Client: welcome / reject, snapshot(authoritative)

signal admitted(seat: int, match_id: String)
signal rejected(reason: int)
signal snapshot_received(tick: int, players: Array)
signal peer_left_seat(seat: int)
signal server_closed

enum Role { UNSET, SERVER, CLIENT }

var role: Role = Role.UNSET
var _session: DsSession = null
var _local_seat: int = 0
var _match_id: String = ""
var _display_name: String = "player"
var _dev_token: String = ""
var _wired_client: bool = false


func configure_server(session: DsSession) -> void:
	role = Role.SERVER
	_session = session
	name = OnlineProtocol.CHANNEL_NODE_NAME


func configure_client(display_name: String = "player", dev_token: String = "") -> void:
	role = Role.CLIENT
	_display_name = OnlineProtocol.clamp_display_name(display_name)
	_dev_token = dev_token.substr(0, OnlineProtocol.MAX_DEV_TOKEN_LEN)
	name = OnlineProtocol.CHANNEL_NODE_NAME
	## multiplayer 只在进树后可用；configure 可能发生在 add_child 之前。
	if is_inside_tree():
		_wire_client_peer_signals()


func _enter_tree() -> void:
	if role == Role.CLIENT:
		_wire_client_peer_signals()


func get_local_seat() -> int:
	return _local_seat


func get_match_id() -> String:
	return _match_id


func connect_to_server(address: String, port: int = OnlineProtocol.DEFAULT_PORT) -> bool:
	if role != Role.CLIENT:
		return false
	var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	var err: Error = peer.create_client(address.strip_edges(), clampi(port, 1, 65535))
	if err != OK:
		push_warning("OnlineChannel: create_client failed: %s" % error_string(err))
		return false
	multiplayer.multiplayer_peer = peer
	return true


func close_client() -> void:
	_unwire_client_peer_signals()
	if multiplayer != null:
		var peer: MultiplayerPeer = multiplayer.multiplayer_peer
		if peer != null:
			peer.close()
		multiplayer.multiplayer_peer = null
	_local_seat = 0
	_match_id = ""


func send_hello() -> void:
	if role != Role.CLIENT:
		return
	if multiplayer.multiplayer_peer == null:
		return
	rpc_hello.rpc_id(1, OnlineProtocol.PROTOCOL_VERSION, _display_name, _dev_token)


func send_input(mx: float, my: float) -> void:
	if role != Role.CLIENT or _local_seat < 1:
		return
	if multiplayer.multiplayer_peer == null:
		return
	rpc_input.rpc_id(1, mx, my)


@rpc("any_peer", "reliable")
func rpc_hello(protocol: int, display_name: String, dev_token: String) -> void:
	if role != Role.SERVER or _session == null:
		return
	var peer_id: int = multiplayer.get_remote_sender_id()
	var result: Dictionary = _session.try_admit(peer_id, protocol, display_name, dev_token)
	var reason: int = int(result.get("reason", OnlineProtocol.RejectReason.MALFORMED))
	if reason != OnlineProtocol.RejectReason.NONE:
		## 先回执再踢：与 LobbyNet KICK_GRACE 同理，避免拒信与 disconnect 同批被 ENet 丢掉。
		rpc_reject.rpc_id(peer_id, reason)
		_kick_peer_deferred(peer_id)
		return
	var seat: int = int(result.get("seat", 0))
	rpc_welcome.rpc_id(peer_id, seat, _session.get_match_id(), OnlineProtocol.PROTOCOL_VERSION)


func _kick_peer_deferred(peer_id: int) -> void:
	await get_tree().create_timer(0.4).timeout
	if _session == null:
		return
	_session.kick_peer(peer_id)


@rpc("authority", "reliable")
func rpc_welcome(seat: int, match_id: String, protocol: int) -> void:
	if role != Role.CLIENT:
		return
	if protocol != OnlineProtocol.PROTOCOL_VERSION:
		rejected.emit(OnlineProtocol.RejectReason.BAD_PROTOCOL)
		return
	_local_seat = seat
	_match_id = match_id
	admitted.emit(seat, match_id)


@rpc("authority", "reliable")
func rpc_reject(reason: int) -> void:
	if role != Role.CLIENT:
		return
	rejected.emit(reason)


@rpc("any_peer", "unreliable")
func rpc_input(mx: float, my: float) -> void:
	if role != Role.SERVER or _session == null:
		return
	var peer_id: int = multiplayer.get_remote_sender_id()
	_session.apply_input(peer_id, mx, my)


@rpc("authority", "unreliable")
func rpc_snapshot(data: PackedByteArray) -> void:
	if role != Role.CLIENT:
		return
	if data.size() > 512:
		return
	var decoded: Dictionary = OnlineProtocol.decode_snapshot(data)
	if not bool(decoded.get("ok", false)):
		return
	snapshot_received.emit(int(decoded["tick"]), decoded["players"] as Array)


@rpc("authority", "reliable")
func rpc_peer_left(seat: int) -> void:
	if role != Role.CLIENT:
		return
	peer_left_seat.emit(seat)


func broadcast_snapshot(data: PackedByteArray) -> void:
	if role != Role.SERVER:
		return
	if multiplayer.multiplayer_peer == null:
		return
	rpc_snapshot.rpc(data)


func notify_peer_left(seat: int) -> void:
	if role != Role.SERVER:
		return
	if multiplayer.multiplayer_peer == null:
		return
	rpc_peer_left.rpc(seat)


func _wire_client_peer_signals() -> void:
	if _wired_client or multiplayer == null:
		return
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	_wired_client = true


func _unwire_client_peer_signals() -> void:
	if not _wired_client:
		return
	if multiplayer != null:
		if multiplayer.connected_to_server.is_connected(_on_connected_to_server):
			multiplayer.connected_to_server.disconnect(_on_connected_to_server)
		if multiplayer.connection_failed.is_connected(_on_connection_failed):
			multiplayer.connection_failed.disconnect(_on_connection_failed)
		if multiplayer.server_disconnected.is_connected(_on_server_disconnected):
			multiplayer.server_disconnected.disconnect(_on_server_disconnected)
	_wired_client = false


func _on_connected_to_server() -> void:
	send_hello()


func _on_connection_failed() -> void:
	rejected.emit(OnlineProtocol.RejectReason.MALFORMED)


func _on_server_disconnected() -> void:
	server_closed.emit()
	_local_seat = 0


func _exit_tree() -> void:
	if role == Role.CLIENT:
		close_client()
