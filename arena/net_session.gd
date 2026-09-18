extends Node
class_name NetSession

## 沙盒内局域网会话。不是 Autoload。Host 权威，Guest 发输入收快照。手写 RPC，不要 MultiplayerSynchronizer。
signal peer_lost
signal input_received(move: Vector2, aim: Vector2, fire: bool, dash: bool, weapon_slot: int)
signal snapshot_received(data: PackedByteArray)
signal fire_fx_received(seat: int, origin: Vector2, direction: Vector2, weapon_index: int)
signal offer_open_received(kind: int, id0: String, id1: String, id2: String, gold: int)
signal offer_close_received(picked_id: String)
signal winner_received(outcome: String, loop_index: int, kills: int, gold: int, time_sec: float)
signal reset_received
signal return_menu_received
signal try_pick_received(upgrade_id: String)
signal try_unpause_received
signal try_pause_received

const SEND_HZ: float = 20.0
const SEND_INTERVAL: float = 1.0 / SEND_HZ

var _role: GameLaunch.NetRole = GameLaunch.NetRole.OFFLINE
var _send_acc: float = 0.0
var _wired: bool = false
var _sandbox: CombatSandbox

func configure(role: GameLaunch.NetRole, sandbox: CombatSandbox) -> void:
	_role = role
	_sandbox = sandbox
	_send_acc = 0.0
	_wire_peer_signals()

func is_online() -> bool:
	return _role != GameLaunch.NetRole.OFFLINE

func is_host() -> bool:
	return _role == GameLaunch.NetRole.HOST

func is_guest() -> bool:
	return _role == GameLaunch.NetRole.GUEST

func get_local_seat() -> int:
	if _role == GameLaunch.NetRole.GUEST:
		return 2
	return 1

func get_unique_id() -> int:
	if multiplayer.multiplayer_peer == null:
		return 0
	return multiplayer.get_unique_id()

func close_peer() -> void:
	_unwire_peer_signals()
	var peer: MultiplayerPeer = multiplayer.multiplayer_peer
	if peer != null:
		peer.close()
	multiplayer.multiplayer_peer = null
	_role = GameLaunch.NetRole.OFFLINE

func send_input(payload: Dictionary) -> void:
	if not is_guest():
		return
	rpc_input.rpc_id(
		1,
		2,
		float(payload.get("mx", 0.0)),
		float(payload.get("my", 0.0)),
		float(payload.get("ax", 1.0)),
		float(payload.get("ay", 0.0)),
		bool(payload.get("fire", false)),
		bool(payload.get("dash", false)),
		int(payload.get("weapon_slot", -1)),
	)

func send_snapshot(data: PackedByteArray) -> void:
	if not is_host():
		return
	rpc_snapshot.rpc(data)

func send_fire_fx(seat: int, origin: Vector2, direction: Vector2, weapon_index: int) -> void:
	if not is_host():
		return
	rpc_fire_fx.rpc(seat, origin.x, origin.y, direction.x, direction.y, weapon_index)

func send_offer_open(kind: int, id0: String, id1: String, id2: String, gold: int) -> void:
	if not is_host():
		return
	rpc_offer_open.rpc(kind, id0, id1, id2, gold)

func send_offer_close(picked_id: String) -> void:
	if not is_host():
		return
	rpc_offer_close.rpc(picked_id)

func send_winner(outcome: String, loop_index: int, kills: int, gold: int, time_sec: float) -> void:
	if not is_host():
		return
	rpc_winner.rpc(outcome, loop_index, kills, gold, time_sec)

func send_reset() -> void:
	if not is_host():
		return
	rpc_reset.rpc()

func send_return_menu() -> void:
	if not is_host():
		return
	rpc_return_menu.rpc()

func send_try_pick(upgrade_id: String) -> void:
	if not is_guest():
		return
	rpc_try_pick.rpc_id(1, upgrade_id)

func send_try_unpause() -> void:
	if not is_guest():
		return
	rpc_try_unpause.rpc_id(1)

func send_try_pause() -> void:
	if not is_guest():
		return
	rpc_try_pause.rpc_id(1)

func _process(delta: float) -> void:
	if not is_online() or _sandbox == null:
		return
	_send_acc += delta
	if _send_acc < SEND_INTERVAL:
		return
	_send_acc -= SEND_INTERVAL
	if is_guest():
		_sandbox.flush_guest_input()
		return
	if is_host():
		_sandbox.flush_net_snapshot()

func _wire_peer_signals() -> void:
	if _wired:
		return
	_wired = true
	if not multiplayer.peer_disconnected.is_connected(_on_peer_disconnected):
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	if not multiplayer.server_disconnected.is_connected(_on_server_disconnected):
		multiplayer.server_disconnected.connect(_on_server_disconnected)

func _unwire_peer_signals() -> void:
	if not _wired:
		return
	_wired = false
	if multiplayer.peer_disconnected.is_connected(_on_peer_disconnected):
		multiplayer.peer_disconnected.disconnect(_on_peer_disconnected)
	if multiplayer.server_disconnected.is_connected(_on_server_disconnected):
		multiplayer.server_disconnected.disconnect(_on_server_disconnected)

func _on_peer_disconnected(_id: int) -> void:
	if not is_online():
		return
	peer_lost.emit()

func _on_server_disconnected() -> void:
	if not is_online():
		return
	peer_lost.emit()

@rpc("any_peer", "call_remote", "unreliable")
func rpc_input(seat: int, mx: float, my: float, ax: float, ay: float, fire: bool, dash: bool, weapon_slot: int) -> void:
	if not is_host():
		return
	if seat != 2:
		return
	input_received.emit(Vector2(mx, my), Vector2(ax, ay), fire, dash, weapon_slot)

@rpc("authority", "call_remote", "unreliable")
func rpc_snapshot(data: PackedByteArray) -> void:
	if not is_guest():
		return
	snapshot_received.emit(data)

@rpc("authority", "call_remote", "reliable")
func rpc_fire_fx(seat: int, ox: float, oy: float, dx: float, dy: float, weapon_index: int) -> void:
	if not is_guest():
		return
	fire_fx_received.emit(seat, Vector2(ox, oy), Vector2(dx, dy), weapon_index)

@rpc("authority", "call_remote", "reliable")
func rpc_offer_open(kind: int, id0: String, id1: String, id2: String, gold: int) -> void:
	if not is_guest():
		return
	offer_open_received.emit(kind, id0, id1, id2, gold)

@rpc("authority", "call_remote", "reliable")
func rpc_offer_close(picked_id: String) -> void:
	if not is_guest():
		return
	offer_close_received.emit(picked_id)

@rpc("authority", "call_remote", "reliable")
func rpc_winner(outcome: String, loop_index: int, kills: int, gold: int, time_sec: float) -> void:
	if not is_guest():
		return
	winner_received.emit(outcome, loop_index, kills, gold, time_sec)

@rpc("authority", "call_remote", "reliable")
func rpc_reset() -> void:
	if not is_guest():
		return
	reset_received.emit()

@rpc("authority", "call_remote", "reliable")
func rpc_return_menu() -> void:
	if not is_guest():
		return
	return_menu_received.emit()

@rpc("any_peer", "call_remote", "reliable")
func rpc_try_pick(upgrade_id: String) -> void:
	if not is_host():
		return
	try_pick_received.emit(upgrade_id)

@rpc("any_peer", "call_remote", "reliable")
func rpc_try_unpause() -> void:
	if not is_host():
		return
	try_unpause_received.emit()

@rpc("any_peer", "call_remote", "reliable")
func rpc_try_pause() -> void:
	if not is_host():
		return
	try_pause_received.emit()
