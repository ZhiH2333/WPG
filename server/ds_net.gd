extends Node
class_name DsNet

## Dedicated Server 的 ENet 所有者（Online 路径）。
## 与 LobbyNet 并行、互不接管：LobbyNet 只管 LAN/P2P；本类只管 DS listen。
## 禁止改 LobbyNet / NetSession；Architecture Guard 白名单允许本文件 new ENetMultiplayerPeer。

signal listen_ok
signal listen_failed
signal peer_connected(peer_id: int)
signal peer_disconnected(peer_id: int)

var _wired: bool = false
var _listening: bool = false
var _port: int = OnlineProtocol.DEFAULT_PORT


func is_listening() -> bool:
	return _listening and multiplayer.multiplayer_peer != null


func get_port() -> int:
	return _port


func host_listen(port: int, max_players: int) -> bool:
	close()
	_port = clampi(port, 1, 65535)
	## ENet 槽位比应用座位多 1：第 5 个连接能进到 hello，由 DsSession 回 FULL，而不是在传输层静默丢掉。
	var capped: int = clampi(max_players, 1, OnlineProtocol.MAX_PLAYERS)
	var max_clients: int = capped + 1
	var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	var err: Error = peer.create_server(_port, max_clients)
	if err != OK:
		push_warning("DsNet: create_server(%d) failed: %s" % [_port, error_string(err)])
		listen_failed.emit()
		return false
	multiplayer.multiplayer_peer = peer
	_wire()
	_listening = true
	listen_ok.emit()
	return true


var _connected_peers: Dictionary = {} ## peer_id -> true；避免对未连接 peer 调 disconnect。


func close() -> void:
	_unwire()
	_listening = false
	_connected_peers.clear()
	if multiplayer == null:
		return
	var peer: MultiplayerPeer = multiplayer.multiplayer_peer
	if peer != null:
		peer.close()
	multiplayer.multiplayer_peer = null


func disconnect_peer(peer_id: int) -> void:
	if multiplayer == null:
		return
	if not _connected_peers.has(peer_id):
		return
	var peer: MultiplayerPeer = multiplayer.multiplayer_peer
	if peer == null:
		return
	if peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	peer.disconnect_peer(peer_id)


func _wire() -> void:
	if _wired or multiplayer == null:
		return
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	_wired = true


func _unwire() -> void:
	if not _wired:
		return
	if multiplayer != null:
		if multiplayer.peer_connected.is_connected(_on_peer_connected):
			multiplayer.peer_connected.disconnect(_on_peer_connected)
		if multiplayer.peer_disconnected.is_connected(_on_peer_disconnected):
			multiplayer.peer_disconnected.disconnect(_on_peer_disconnected)
	_wired = false


func _on_peer_connected(peer_id: int) -> void:
	_connected_peers[peer_id] = true
	peer_connected.emit(peer_id)


func _on_peer_disconnected(peer_id: int) -> void:
	_connected_peers.erase(peer_id)
	peer_disconnected.emit(peer_id)


func _exit_tree() -> void:
	close()
