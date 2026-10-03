extends Node
class_name LobbyNet

## Lobby 大厅网络层（roadmap Phase 7 / docs/ui_lobby_architecture.md §4）。
## 职责只有：建连 / 关连 / 大厅 RPC / 网络状态。不决定 UI，不持有 Room / LobbyPlayer。
##
## 分层：LanOverlay → LobbyManager → LobbyNet → SceneTree.multiplayer → ENet
## - ENetMultiplayerPeer.new() 只允许出现在本文件。
## - 大厅 @rpc 只允许出现在本文件。
## - LobbyManager 通过本文件的抽象方法发/收，不直接碰 multiplayer。
##
## 本刀是「搬家 + Ready 同步」：RPC / 座位缓存 / roster 编解码 / 握手校验从 LanOverlay 原样迁入，
## 协议仍 5、roster 包格式不变；Ready 走独立的权威 RPC（不动 roster 包、不 bump 协议）。

## 网络状态（供 LobbyManager / UI 统一识别，不再散落在 if 里）。
enum NetState {
	DISCONNECTED,
	HOSTING,
	CONNECTING,
	HANDSHAKING,
	CONNECTED,
	LOBBY,
	STARTING,
	FAILED,
	VERSION_MISMATCH,
	HOST_CLOSED,
}

## 建房监听成功 / 失败。
signal listen_ok
signal listen_failed
## Guest 连上 Host（TCP/ENet 层），尚未握手。
signal connected
## Guest 连接失败 / 被拒。
signal connection_failed
## 协议不符。
signal version_mismatch
## Host 关闭 / 掉线（Guest 侧）。
signal host_closed
## Host 侧：一个 peer 连上，需要占座。seat = 0 表示满员，应断开该 peer。
signal peer_joined(peer_id: int, seat: int)
## Host 侧：peer 断开。
signal peer_left(peer_id: int)
## Host 侧：某 peer 握手完成（可正式入座）。
signal peer_confirmed(peer_id: int, seat: int)
## Host 侧：某 peer 的 ticket 校验失败，已被拒（原因见 TicketReject）。
signal peer_rejected(peer_id: int, reason: int)
## Guest 侧：自己的 ticket 被 Host 拒绝。
signal join_rejected(reason: int)
## Host 侧：收到 Guest 的角色。
signal guest_character(peer_id: int, character_id: String)
## Guest 侧：收到自己座位。
signal seat_assigned(seat: int)
## Guest 侧：收到房间事实。
signal goal_changed(loop_goal: int)
signal arena_changed(arena_id: String)
signal mode_changed(net_play: int)
signal roster_changed(character_ids: PackedStringArray)
## Guest 侧：Host 宣布开战。
signal match_begin(loop_goal: int, arena_id: String, net_play: int)
## Host 侧：收到 Guest 的 Ready 请求（座位 / 房间状态 / 权限校验在 LobbyManager）。
signal ready_requested(peer_id: int, ready: bool)
## Guest 侧：Host 广播的座位 Ready 权威值。
signal ready_applied(seat: int, ready: bool)
## 状态变化。
signal state_changed(state: int)

## 协议 6：Guest hello 被拒的原因。Host 是唯一裁判。
enum TicketReject {
	NONE,
	BAD_PROTOCOL,
	BAD_TOKEN,
	NO_ROOM,
	FULL,
	NO_SEAT,
}

const MAX_SEATS: int = GameLaunch.NET_MAX_SEATS
const HOST_PEER: int = 1

var _state: NetState = NetState.DISCONNECTED
var _wired: bool = false
## seat(int, 1-based) -> peer_id(int)。Host 侧座位路由缓存。
var _seat_peer_ids: PackedInt32Array = PackedInt32Array()
## seat(int) -> character_id。Host 侧角色缓存。
var _seat_character_ids: PackedStringArray = PackedStringArray()
## seat(int) -> 0/1，握手是否完成。
var _seat_handshake: PackedByteArray = PackedByteArray()
## Guest 侧：最后一次收到的 roster。
var _roster_character_ids: PackedStringArray = PackedStringArray()
## Host 侧：本房门票（协议 6）。由 LobbyManager 在建房时通过 set_ticket() 注入。
## 只用于比对 Guest 出示的 ticket，绝不当作身份 —— 身份永远看 profile_id 握手。
var _ticket: String = ""
## Guest 侧：本次连接携带的 ticket。
var _guest_ticket: String = ""
## Host 侧：peer_id -> 已通过 ticket 校验（0/1）。未通过的 peer 不得进 Room、不得占正式座位。
var _peer_ticket_ok: Dictionary = {}

func _ready() -> void:
	_reset_seats()

func _exit_tree() -> void:
	close()

# ---- 状态 ----

func get_state() -> NetState:
	return _state

func set_state(value: NetState) -> void:
	if _state == value:
		return
	_state = value
	state_changed.emit(int(_state))

func is_active() -> bool:
	return _state != NetState.DISCONNECTED and _state != NetState.FAILED and _state != NetState.VERSION_MISMATCH and _state != NetState.HOST_CLOSED

func is_server() -> bool:
	return multiplayer.multiplayer_peer != null and multiplayer.is_server()

## 从粘贴文本里取出可连接的地址（JoinInvite 解析的第一刀：只认 LAN IPv4，端口固定 17777）。
## "192.168.1.5" / "192.168.1.5:17777" / "join 192.168.1.5 wpg" / "wpg://192.168.1.5" 都能取出；
## 取不到（含非法 IPv4 段）返回 ""，调用方再决定是报错还是把原文当主机名。
static func parse_address(raw: String) -> String:
	var text: String = raw.strip_edges()
	if text.is_empty():
		return ""
	var regex: RegEx = RegEx.new()
	regex.compile("(\\d{1,3})\\.(\\d{1,3})\\.(\\d{1,3})\\.(\\d{1,3})")
	var found: RegExMatch = regex.search(text)
	if found == null:
		return ""
	for index: int in range(1, 5):
		var part: int = int(found.get_string(index))
		if part > 255:
			return ""
	return found.get_string(0)

# ---- 建 / 关 ----

## Host 监听。成功返回 true，失败 false（调用方显示 bind failed）。
func host_listen() -> bool:
	close()
	var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	var err: Error = peer.create_server(GameLaunch.NET_PORT, MAX_SEATS - 1)
	if err != OK:
		set_state(NetState.FAILED)
		listen_failed.emit()
		return false
	multiplayer.multiplayer_peer = peer
	_reset_seats()
	_wire()
	set_state(NetState.HOSTING)
	listen_ok.emit()
	return true

## Guest 连接（Phase 8：按候选路径带 address / port / ticket）。
## 一次只建一个 peer —— 调用方负责在失败后 close() 再试下一个候选。
func client_connect(address: String, port: int = GameLaunch.NET_PORT, ticket: String = "") -> bool:
	close()
	_guest_ticket = ticket
	var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	var err: Error = peer.create_client(address.strip_edges(), clampi(port, 1, 65535))
	if err != OK:
		set_state(NetState.FAILED)
		connection_failed.emit()
		return false
	multiplayer.multiplayer_peer = peer
	_wire()
	set_state(NetState.CONNECTING)
	return true

## Host 侧：注入本房 ticket（由 LobbyManager 在建房时给出）。
func set_ticket(ticket: String) -> void:
	_ticket = ticket.strip_edges()

func get_ticket() -> String:
	return _ticket

## Guest 侧：本次连接携带的 ticket。
func set_guest_ticket(ticket: String) -> void:
	_guest_ticket = ticket.strip_edges()

func get_guest_ticket() -> String:
	return _guest_ticket

func close() -> void:
	_unwire()
	_reset_seats()
	_roster_character_ids = PackedStringArray()
	_peer_ticket_ok.clear()
	## _ticket 是房间级凭据，由 LobbyManager 显式注入 / 清空，这里不擅自丢，
	## 否则 Host 一关连重开就变成「无 ticket 房间」而拒绝所有 Guest。
	var peer: MultiplayerPeer = multiplayer.multiplayer_peer
	if peer != null:
		peer.close()
	multiplayer.multiplayer_peer = null
	set_state(NetState.DISCONNECTED)

# ---- 发送（Guest 侧）----

func send_guest_character(character_id: String) -> void:
	if multiplayer.multiplayer_peer == null:
		return
	rpc_guest_character.rpc_id(HOST_PEER, character_id)

## Guest 提交自己的 Ready 意图。Host 才是权威：受理后会用 rpc_apply_ready 广播回来。
func send_ready(ready: bool) -> void:
	if multiplayer.multiplayer_peer == null:
		return
	rpc_ready.rpc_id(HOST_PEER, ready)

## Guest 侧：向 Host 出示 ticket（协议 6 握手第一步）。ticket 是入场券，不是身份。
## 方向必须是 Guest -> Host：否则 Host 把自己的 ticket 发给 Guest，校验就失去意义。
func send_hello() -> void:
	if is_server() or multiplayer.multiplayer_peer == null:
		return
	set_state(NetState.HANDSHAKING)
	rpc_hello.rpc_id(HOST_PEER, GameLaunch.NET_PROTOCOL, _guest_ticket)

## Host 侧：ticket 校验通过后回执握手，并把座位发给该 Guest。
## 座位是握手成功的产物 —— 没通过 ticket 的 peer 永远走不到这里。
func send_hello_ok(peer_id: int) -> void:
	if not is_server() or peer_id <= 1:
		return
	rpc_hello_ok.rpc_id(peer_id)
	var seat: int = seat_for_peer(peer_id)
	if seat < Room.HOST_SEAT + 1 or seat > MAX_SEATS:
		return
	rpc_assign_seat.rpc_id(peer_id, seat)

## Host 拒绝一个 peer（占座失败 / 满员 / 无房）。
func disconnect_peer(peer_id: int) -> void:
	if multiplayer.multiplayer_peer == null:
		return
	multiplayer.multiplayer_peer.disconnect_peer(peer_id)

# ---- 发送（Host 侧）----

## 广播 roster 到所有已握手的 Guest。
func broadcast_roster(character_ids: PackedStringArray, peer_ids: PackedInt32Array) -> void:
	if not is_server():
		return
	var packed: PackedByteArray = encode_roster(character_ids, peer_ids)
	for peer: int in _handshake_guest_peers():
		rpc_roster.rpc_id(peer, packed)

func broadcast_goal(loop_goal: int) -> void:
	if not is_server():
		return
	for peer: int in _handshake_guest_peers():
		rpc_goal.rpc_id(peer, loop_goal)

func broadcast_arena(arena_id: String) -> void:
	if not is_server():
		return
	for peer: int in _handshake_guest_peers():
		rpc_arena.rpc_id(peer, arena_id)

func broadcast_mode(net_play: int) -> void:
	if not is_server():
		return
	for peer: int in _handshake_guest_peers():
		rpc_play_mode.rpc_id(peer, net_play)

## Host 权威：把某个座位的 Ready 广播给所有已握手 Guest（含请求者自己）。
func broadcast_ready(seat: int, ready: bool) -> void:
	if not is_server():
		return
	for peer: int in _handshake_guest_peers():
		rpc_apply_ready.rpc_id(peer, seat, ready)

## Host 权威：新 Guest 入房时补齐 5 个座位的 Ready 快照（协议 5 不带身份，只带座位）。
func send_ready_snapshot_to_peer(peer_id: int, ready_flags: PackedByteArray) -> void:
	if peer_id <= 1 or not is_server():
		return
	for seat: int in range(1, MAX_SEATS + 1):
		var ready: bool = seat - 1 < ready_flags.size() and ready_flags[seat - 1] != 0
		rpc_apply_ready.rpc_id(peer_id, seat, ready)

## Host 宣布开战并广播给所有已握手 Guest。
func begin_match(character_ids: PackedStringArray, peer_ids: PackedInt32Array, loop_goal: int, arena_id: String, net_play: int) -> void:
	if not is_server():
		return
	var packed: PackedByteArray = encode_roster(character_ids, peer_ids)
	for peer: int in _handshake_guest_peers():
		rpc_roster.rpc_id(peer, packed)
		rpc_goal.rpc_id(peer, loop_goal)
		rpc_arena.rpc_id(peer, arena_id)
		rpc_play_mode.rpc_id(peer, net_play)
		rpc_begin.rpc_id(peer, loop_goal, arena_id, net_play)

# ---- RPC（大厅）----

## Guest -> Host：出示 (protocol, ticket)。Host 是唯一裁判。
## 协议不匹配 -> VERSION_MISMATCH；ticket 不匹配 -> 明确 rejected，且不占座。
@rpc("any_peer", "call_remote", "reliable")
func rpc_hello(protocol: int, ticket: String) -> void:
	## 协议门放在最前面：它既不依赖 peer 也不依赖 server 角色，
	## 这样离线状态机自检（单进程测试）也能走通，与 v5 行为保持一致。
	if protocol != GameLaunch.NET_PROTOCOL:
		set_state(NetState.VERSION_MISMATCH)
		version_mismatch.emit()
		## 只有真有 peer 时才谈得上回执 / 踢人；离线自检没有 sender。
		if multiplayer.multiplayer_peer != null:
			var mismatched: int = multiplayer.get_remote_sender_id()
			peer_rejected.emit(mismatched, int(TicketReject.BAD_PROTOCOL))
			rpc_join_rejected.rpc_id(mismatched, int(TicketReject.BAD_PROTOCOL))
			disconnect_peer(mismatched)
		return
	## 没有 peer = 离线状态机自检 / 收尾关连：不回执、不校验 ticket，但状态照常推进
	##（与协议 5 行为一致，单进程测试依赖这条）。
	if multiplayer.multiplayer_peer == null:
		set_state(NetState.CONNECTED)
		return
	if not multiplayer.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	var reject: TicketReject = check_ticket(sender, ticket)
	if reject != TicketReject.NONE:
		## ticket 不过 = 不确认、不占正式座位、不进 Room.players，并立刻断开。
		_peer_ticket_ok.erase(sender)
		peer_rejected.emit(sender, int(reject))
		rpc_join_rejected.rpc_id(sender, int(reject))
		disconnect_peer(sender)
		return
	_peer_ticket_ok[sender] = 1
	## ticket 过了才走座位确认：未过 ticket 的 peer 永远拿不到 seat，
	## 也就不会进 Room.players（LobbyManager 只在 peer_confirmed 时 confirm_peer）。
	var seat: int = accept_hello_ok(sender)
	if seat == 0:
		## 没座位（满员 / 未占 pending）-> 明确拒绝，不静默丢包。
		_peer_ticket_ok.erase(sender)
		peer_rejected.emit(sender, int(TicketReject.NO_SEAT))
		rpc_join_rejected.rpc_id(sender, int(TicketReject.NO_SEAT))
		disconnect_peer(sender)
		return
	send_hello_ok(sender)
	set_state(NetState.CONNECTED)

## Host 权威 ticket 校验（纯逻辑，便于单测）。
## 注意：ticket 只证明「持有本房门票」，不映射 profile_id、不与 seat / peer_id 混用。
func check_ticket(peer_id: int, ticket: String) -> TicketReject:
	if not is_server():
		return TicketReject.NO_ROOM
	if _ticket.is_empty():
		## 没建 ticket 的房间不接受任何 ticket 连接（避免"空 ticket 放行"）。
		return TicketReject.NO_ROOM
	if ticket.is_empty():
		return TicketReject.BAD_TOKEN
	## 定长比较，避免长度差异提前退出。
	if ticket.length() != _ticket.length():
		return TicketReject.BAD_TOKEN
	var diff: int = 0
	for i: int in ticket.length():
		diff |= ticket.unicode_at(i) ^ _ticket.unicode_at(i)
	if diff != 0:
		return TicketReject.BAD_TOKEN
	if seat_for_peer(peer_id) < Room.HOST_SEAT + 1:
		return TicketReject.NO_SEAT
	return TicketReject.NONE

## Host 侧：某 peer 是否已通过 ticket 校验。未通过的 peer 不得进 Room。
func is_peer_ticket_ok(peer_id: int) -> bool:
	return _peer_ticket_ok.get(peer_id, 0) == 1

## Host -> Guest：ticket 已通过，握手确认，随后 Host 分配座位。
@rpc("authority", "call_remote", "reliable")
func rpc_hello_ok() -> void:
	set_state(NetState.CONNECTED)

## Host → Guest：ticket 被拒。Guest 侧据此进入明确的失败状态，不重试、不静默。
@rpc("authority", "call_remote", "reliable")
func rpc_join_rejected(reason: int) -> void:
	set_state(NetState.FAILED)
	join_rejected.emit(reason)
	connection_failed.emit()

## 握手回执的座位校验（纯逻辑，便于单测）：只有已占座的 Guest 才被确认。
## 返回 seat；0 = 没有座位（没占座 / 是 Host 自己 / 座位号越界）。
func accept_hello_ok(peer_id: int) -> int:
	var seat: int = seat_for_peer(peer_id)
	if seat < Room.HOST_SEAT + 1 or seat > MAX_SEATS:
		return 0
	_seat_handshake[seat - 1] = 1
	peer_confirmed.emit(peer_id, seat)
	return seat

@rpc("any_peer", "call_remote", "reliable")
func rpc_guest_character(character_id: String) -> void:
	if not multiplayer.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	var seat: int = seat_for_peer(sender)
	if seat < 2 or seat > MAX_SEATS:
		return
	_seat_character_ids[seat - 1] = GameLaunch._sanitize_character_id(character_id)
	guest_character.emit(sender, _seat_character_ids[seat - 1])

## Guest → Host：Ready 意图。这里只确认「谁在说」，座位 / 状态 / 权限校验在 LobbyManager。
@rpc("any_peer", "call_remote", "reliable")
func rpc_ready(ready: bool) -> void:
	if not multiplayer.is_server():
		return
	ready_requested.emit(multiplayer.get_remote_sender_id(), ready)

## Host → Guest：座位的 Ready 权威值。Guest 不被本地乐观值欺骗，最终以这个为准。
@rpc("authority", "call_remote", "reliable")
func rpc_apply_ready(seat: int, ready: bool) -> void:
	if seat < 1 or seat > MAX_SEATS:
		return
	ready_applied.emit(seat, ready)

@rpc("authority", "call_remote", "reliable")
func rpc_assign_seat(seat: int) -> void:
	set_state(NetState.LOBBY)
	seat_assigned.emit(clampi(seat, 1, MAX_SEATS))

@rpc("authority", "call_remote", "reliable")
func rpc_roster(data: PackedByteArray) -> void:
	_roster_character_ids = decode_roster(data)
	roster_changed.emit(_roster_character_ids)

@rpc("authority", "call_remote", "reliable")
func rpc_goal(loop_goal: int) -> void:
	goal_changed.emit(loop_goal)

@rpc("authority", "call_remote", "reliable")
func rpc_arena(arena_id: String) -> void:
	arena_changed.emit(GameLaunch._sanitize_arena_id(arena_id))

@rpc("authority", "call_remote", "reliable")
func rpc_play_mode(net_play: int) -> void:
	mode_changed.emit(net_play)

@rpc("authority", "call_remote", "reliable")
func rpc_begin(loop_goal: int, arena_id: String, net_play: int) -> void:
	set_state(NetState.STARTING)
	match_begin.emit(loop_goal, arena_id, net_play)

# ---- 座位 ----

func seat_for_peer(peer_id: int) -> int:
	if peer_id <= 0:
		return 0
	for i: int in _seat_peer_ids.size():
		if _seat_peer_ids[i] == peer_id:
			return i + 1
	return 0

func seat_peer(seat: int) -> int:
	if seat < 1 or seat > _seat_peer_ids.size():
		return 0
	return _seat_peer_ids[seat - 1]

func seat_character(seat: int) -> String:
	if seat < 1 or seat > _seat_character_ids.size():
		return ""
	return _seat_character_ids[seat - 1]

func set_seat_peer(seat: int, peer_id: int) -> void:
	if seat < 1 or seat > MAX_SEATS:
		return
	_seat_peer_ids[seat - 1] = peer_id

func clear_seat_of_peer(peer_id: int) -> void:
	for seat: int in range(2, MAX_SEATS + 1):
		if _seat_peer_ids[seat - 1] != peer_id:
			continue
		_seat_peer_ids[seat - 1] = 0
		_seat_character_ids[seat - 1] = ""
		_seat_handshake[seat - 1] = 0
		return

func occupied_count() -> int:
	var n: int = 0
	for i: int in _seat_peer_ids.size():
		if _seat_peer_ids[i] != 0:
			n += 1
	return n

func get_roster_characters() -> PackedStringArray:
	return _roster_character_ids.duplicate()

# ---- 编解码（协议 5 格式，不 bump）----

func encode_roster(character_ids: PackedStringArray, peer_ids: PackedInt32Array) -> PackedByteArray:
	var buf: StreamPeerBuffer = StreamPeerBuffer.new()
	var peers: PackedInt32Array = _roster_peer_list(peer_ids)
	buf.put_u8(peers.size())
	for seat: int in range(1, MAX_SEATS + 1):
		var peer_id: int = seat_peer(seat)
		if peer_id == 0:
			continue
		var character: String = seat_character(seat)
		if character.is_empty():
			character = character_ids[seat - 1] if seat - 1 < character_ids.size() else ""
		buf.put_u8(seat)
		buf.put_utf8_string(character)
	return buf.data_array

## 用传入的 peer_ids 重排座位缓存（Host 用自己的权威座位；LanOverlay 迁移期兼容）。
func _roster_peer_list(peer_ids: PackedInt32Array) -> PackedInt32Array:
	var peers: PackedInt32Array = PackedInt32Array()
	for seat: int in range(1, MAX_SEATS + 1):
		var pid: int = seat_peer(seat)
		if pid != 0:
			peers.append(pid)
	return peers

func decode_roster(data: PackedByteArray) -> PackedStringArray:
	var ids: PackedStringArray = PackedStringArray()
	ids.resize(MAX_SEATS)
	if data.is_empty():
		return ids
	var buf: StreamPeerBuffer = StreamPeerBuffer.new()
	buf.data_array = data
	buf.seek(0)
	var n: int = buf.get_u8()
	for _i: int in n:
		var seat: int = buf.get_u8()
		var character_id: String = buf.get_utf8_string()
		if seat < 1 or seat > MAX_SEATS:
			continue
		if character_id.is_empty():
			ids[seat - 1] = ""
			continue
		ids[seat - 1] = GameLaunch._sanitize_character_id(character_id)
	return ids

# ---- 内部 ----

func _reset_seats() -> void:
	_seat_peer_ids = PackedInt32Array()
	_seat_peer_ids.resize(MAX_SEATS)
	_seat_peer_ids.fill(0)
	_seat_peer_ids[0] = HOST_PEER
	_seat_character_ids = PackedStringArray()
	_seat_character_ids.resize(MAX_SEATS)
	_seat_character_ids.fill("")
	_seat_handshake = PackedByteArray()
	_seat_handshake.resize(MAX_SEATS)
	_seat_handshake.fill(0)
	_seat_handshake[0] = 1
	_roster_character_ids = PackedStringArray()
	_roster_character_ids.resize(MAX_SEATS)

func _handshake_guest_peers() -> PackedInt32Array:
	var peers: PackedInt32Array = PackedInt32Array()
	for seat: int in range(2, MAX_SEATS + 1):
		if _seat_peer_ids[seat - 1] == 0 or _seat_handshake[seat - 1] == 0:
			continue
		peers.append(_seat_peer_ids[seat - 1])
	return peers

## 把当前房间事实（roster / goal / arena / mode）推给单个已握手 Guest。
func send_session_to_peer(peer: int, character_ids: PackedStringArray, loop_goal: int, arena_id: String, net_play: int) -> void:
	if peer <= 1 or not is_server():
		return
	rpc_roster.rpc_id(peer, encode_roster(character_ids, PackedInt32Array()))
	rpc_goal.rpc_id(peer, loop_goal)
	rpc_arena.rpc_id(peer, arena_id)
	rpc_play_mode.rpc_id(peer, net_play)

func _wire() -> void:
	if _wired:
		return
	_wired = true
	if not multiplayer.peer_connected.is_connected(_on_peer_connected):
		multiplayer.peer_connected.connect(_on_peer_connected)
	if not multiplayer.peer_disconnected.is_connected(_on_peer_disconnected):
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	if not multiplayer.connected_to_server.is_connected(_on_connected_to_server):
		multiplayer.connected_to_server.connect(_on_connected_to_server)
	if not multiplayer.connection_failed.is_connected(_on_connection_failed):
		multiplayer.connection_failed.connect(_on_connection_failed)
	if not multiplayer.server_disconnected.is_connected(_on_server_disconnected):
		multiplayer.server_disconnected.connect(_on_server_disconnected)

func _unwire() -> void:
	if not _wired:
		return
	_wired = false
	if multiplayer.peer_connected.is_connected(_on_peer_connected):
		multiplayer.peer_connected.disconnect(_on_peer_connected)
	if multiplayer.peer_disconnected.is_connected(_on_peer_disconnected):
		multiplayer.peer_disconnected.disconnect(_on_peer_disconnected)
	if multiplayer.connected_to_server.is_connected(_on_connected_to_server):
		multiplayer.connected_to_server.disconnect(_on_connected_to_server)
	if multiplayer.connection_failed.is_connected(_on_connection_failed):
		multiplayer.connection_failed.disconnect(_on_connection_failed)
	if multiplayer.server_disconnected.is_connected(_on_server_disconnected):
		multiplayer.server_disconnected.disconnect(_on_server_disconnected)

func _on_peer_connected(id: int) -> void:
	if not multiplayer.is_server():
		return
	set_state(NetState.LOBBY if _state == NetState.HOSTING else _state)
	peer_joined.emit(id, 0)

func _on_peer_disconnected(id: int) -> void:
	if not multiplayer.is_server():
		return
	clear_seat_of_peer(id)
	peer_left.emit(id)

func _on_connected_to_server() -> void:
	set_state(NetState.HANDSHAKING)
	connected.emit()
	## 协议 6：连上后由 Guest 主动出示 ticket。Host 校验通过才会 assign seat。
	send_hello()

func _on_connection_failed() -> void:
	set_state(NetState.FAILED)
	connection_failed.emit()

func _on_server_disconnected() -> void:
	set_state(NetState.HOST_CLOSED)
	host_closed.emit()
