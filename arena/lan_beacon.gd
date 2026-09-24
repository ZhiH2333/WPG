extends Node
class_name LanBeacon

## 大厅局域网发现。Guest 探针，Host 在 17778 单播回房间包。不是 Autoload。禁止扫网段。Host 与 Guest 不得同时 start。
signal rooms_changed

const MAGIC: PackedByteArray = [87, 80, 71, 49] ## WPG1
const SEND_SEC: float = 1.0
const STALE_SEC: float = 3.0
const _MIN_ROOM: int = 14
const _MIN_QUERY: int = 6

enum _Role { IDLE, HOST, GUEST }

var _role: _Role = _Role.IDLE
var _udp: PacketPeerUDP
var _send_accum: float = 0.0
var _occupied: int = 1
var _max_seats: int = GameLaunch.NET_MAX_SEATS
var _net_play: int = 0
var _loop_goal: int = 0
var _arena_id: String = "yard"
var _rooms: Dictionary = {}
var _bind_failed: bool = false

func start_host(occupied: int, max_seats: int, net_play: int, loop_goal: int, arena_id: String) -> void:
	stop()
	_apply_host_fields(occupied, max_seats, net_play, loop_goal, arena_id)
	_udp = PacketPeerUDP.new()
	var err: Error = _udp.bind(GameLaunch.NET_DISCOVER_PORT, "*")
	if err != OK:
		_udp.close()
		_udp = null
		return
	_udp.set_broadcast_enabled(true)
	_role = _Role.HOST
	set_process(true)

func update_host(occupied: int, max_seats: int, net_play: int, loop_goal: int, arena_id: String) -> void:
	if _role != _Role.HOST:
		return
	_apply_host_fields(occupied, max_seats, net_play, loop_goal, arena_id)

func start_guest() -> void:
	stop()
	_udp = PacketPeerUDP.new()
	var err: Error = _udp.bind(0)
	if err != OK:
		_udp.close()
		_udp = null
		_bind_failed = true
		rooms_changed.emit()
		return
	_udp.set_broadcast_enabled(true)
	_role = _Role.GUEST
	_send_accum = 0.0
	set_process(true)
	_send_query()

func stop() -> void:
	set_process(false)
	_role = _Role.IDLE
	_bind_failed = false
	_send_accum = 0.0
	_rooms.clear()
	if _udp == null:
		return
	_udp.close()
	_udp = null

func get_rooms() -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	var addresses: Array[String] = _sorted_addresses()
	for address: String in addresses:
		list.append(_public_room(_rooms[address] as Dictionary))
	return list

func has_bind_failed() -> bool:
	return _bind_failed

func _process(delta: float) -> void:
	if _role == _Role.HOST:
		_ingest_host()
		return
	if _role == _Role.GUEST:
		_tick_guest(delta)

func _tick_guest(delta: float) -> void:
	_ingest_guest()
	_prune_stale()
	_send_accum += delta
	if _send_accum < SEND_SEC:
		return
	_send_accum = 0.0
	_send_query()

func _apply_host_fields(occupied: int, max_seats: int, net_play: int, loop_goal: int, arena_id: String) -> void:
	_occupied = clampi(occupied, 1, 5)
	_max_seats = max_seats
	_net_play = net_play
	_loop_goal = maxi(loop_goal, 0)
	_arena_id = GameLaunch._sanitize_arena_id(arena_id)

func _send_query() -> void:
	if _udp == null or _role != _Role.GUEST:
		return
	var packet: PackedByteArray = _encode_query()
	_udp.set_dest_address("255.255.255.255", GameLaunch.NET_DISCOVER_PORT)
	_udp.put_packet(packet)
	_udp.set_dest_address("127.0.0.1", GameLaunch.NET_DISCOVER_PORT)
	_udp.put_packet(packet)

func _encode_query() -> PackedByteArray:
	var buf: StreamPeerBuffer = StreamPeerBuffer.new()
	_write_magic(buf)
	buf.put_u8(GameLaunch.NET_PROTOCOL)
	buf.put_u8(0)
	return buf.data_array

func _encode_room() -> PackedByteArray:
	var buf: StreamPeerBuffer = StreamPeerBuffer.new()
	_write_magic(buf)
	buf.put_u8(GameLaunch.NET_PROTOCOL)
	buf.put_u8(_occupied)
	buf.put_u8(GameLaunch.NET_MAX_SEATS)
	buf.put_u8(_net_play)
	buf.put_u16(_loop_goal)
	buf.put_utf8_string(_arena_id)
	return buf.data_array

func _write_magic(buf: StreamPeerBuffer) -> void:
	for i: int in MAGIC.size():
		buf.put_u8(MAGIC[i])

func _ingest_host() -> void:
	if _udp == null:
		return
	while _udp.get_available_packet_count() > 0:
		var packet: PackedByteArray = _udp.get_packet()
		var ip: String = _udp.get_packet_ip()
		var port: int = _udp.get_packet_port()
		if not _is_query(packet):
			continue
		_reply_room(ip, port)

func _ingest_guest() -> void:
	if _udp == null:
		return
	while _udp.get_available_packet_count() > 0:
		var packet: PackedByteArray = _udp.get_packet()
		_ingest_room(_udp.get_packet_ip(), packet)

func _reply_room(ip: String, port: int) -> void:
	var address: String = _canonical_ipv4(ip)
	if address.is_empty() or port <= 0 or _udp == null:
		return
	_udp.set_dest_address(address, port)
	_udp.put_packet(_encode_room())

func _ingest_room(ip: String, packet: PackedByteArray) -> void:
	var address: String = _canonical_ipv4(ip)
	if address.is_empty():
		return
	var parsed: Dictionary = _parse_room(packet)
	if parsed.is_empty():
		return
	parsed["address"] = address
	parsed["last_msec"] = Time.get_ticks_msec()
	var prev: Dictionary = _rooms.get(address, {}) as Dictionary
	_rooms[address] = parsed
	if _is_same_public_room(prev, parsed):
		return
	rooms_changed.emit()

func _is_query(packet: PackedByteArray) -> bool:
	if packet.size() < _MIN_QUERY:
		return false
	var buf: StreamPeerBuffer = StreamPeerBuffer.new()
	buf.data_array = packet
	buf.seek(0)
	if not _match_magic(buf):
		return false
	if buf.get_u8() != GameLaunch.NET_PROTOCOL:
		return false
	return buf.get_u8() == 0

func _parse_room(packet: PackedByteArray) -> Dictionary:
	if packet.size() < _MIN_ROOM:
		return {}
	var buf: StreamPeerBuffer = StreamPeerBuffer.new()
	buf.data_array = packet
	buf.seek(0)
	if not _match_magic(buf):
		return {}
	var protocol: int = buf.get_u8()
	if protocol != GameLaunch.NET_PROTOCOL:
		return {}
	var occupied: int = buf.get_u8()
	if occupied < 1 or occupied > 5:
		return {}
	var max_seats: int = buf.get_u8()
	if max_seats != GameLaunch.NET_MAX_SEATS:
		return {}
	var net_play: int = buf.get_u8()
	if net_play != int(GameLaunch.NetPlay.COOP) and net_play != int(GameLaunch.NetPlay.BATTLE):
		return {}
	var loop_goal: int = buf.get_u16()
	if buf.get_available_bytes() < 4:
		return {}
	var arena_id: String = GameLaunch._sanitize_arena_id(buf.get_utf8_string())
	return {
		"occupied": occupied,
		"max_seats": max_seats,
		"net_play": net_play,
		"loop_goal": loop_goal,
		"arena_id": arena_id,
	}

func _match_magic(buf: StreamPeerBuffer) -> bool:
	if buf.get_available_bytes() < MAGIC.size():
		return false
	for i: int in MAGIC.size():
		if buf.get_u8() != MAGIC[i]:
			return false
	return true

func _prune_stale() -> void:
	var now_msec: int = Time.get_ticks_msec()
	var stale_ms: int = int(STALE_SEC * 1000.0)
	var stale: Array[String] = []
	for address: String in _sorted_addresses():
		var room: Dictionary = _rooms[address] as Dictionary
		if now_msec - int(room.get("last_msec", 0)) < stale_ms:
			continue
		stale.append(address)
	if stale.is_empty():
		return
	for address: String in stale:
		_rooms.erase(address)
	rooms_changed.emit()

func _sorted_addresses() -> Array[String]:
	var addresses: Array[String] = []
	for key: Variant in _rooms.keys():
		addresses.append(str(key))
	addresses.sort()
	return addresses

func _public_room(room: Dictionary) -> Dictionary:
	return {
		"address": str(room.get("address", "")),
		"occupied": int(room.get("occupied", 1)),
		"max_seats": int(room.get("max_seats", GameLaunch.NET_MAX_SEATS)),
		"net_play": int(room.get("net_play", 0)),
		"loop_goal": int(room.get("loop_goal", 0)),
		"arena_id": str(room.get("arena_id", "yard")),
	}

func _is_same_public_room(a: Dictionary, b: Dictionary) -> bool:
	if a.is_empty():
		return false
	return str(a.get("address", "")) == str(b.get("address", "")) and int(a.get("occupied", -1)) == int(b.get("occupied", -1)) and int(a.get("max_seats", -1)) == int(b.get("max_seats", -1)) and int(a.get("net_play", -1)) == int(b.get("net_play", -1)) and int(a.get("loop_goal", -1)) == int(b.get("loop_goal", -1)) and str(a.get("arena_id", "")) == str(b.get("arena_id", ""))

func _canonical_ipv4(ip: String) -> String:
	if ip.is_empty():
		return ""
	if ip.begins_with("::ffff:"):
		var mapped: String = ip.substr(7)
		if mapped.find(":") >= 0:
			return ""
		return mapped
	if ip.find(":") >= 0:
		return ""
	return ip
