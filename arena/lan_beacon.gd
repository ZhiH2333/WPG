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
## 协议 6：房间身份、Host 名，以及 LAN_VISIBLE 房间的门票副本。
## 门票只是让 Guest 能在 hello 里出示同一张票；本对象不校验、不接受、不拒绝任何人。
## 校验仍在 LobbyNet.check_ticket()。INVITE ONLY 不起信标，票不会广播出去。
var _room_id: String = ""
var _host_display_name: String = ""
var _ticket: String = ""
var _rooms: Dictionary = {}
var _bind_failed: bool = false

func start_host(occupied: int, max_seats: int, net_play: int, loop_goal: int, arena_id: String, room_id: String = "", host_display_name: String = "", ticket: String = "") -> void:
	stop()
	_apply_host_fields(occupied, max_seats, net_play, loop_goal, arena_id, room_id, host_display_name, ticket)
	_udp = PacketPeerUDP.new()
	var err: Error = _udp.bind(GameLaunch.NET_DISCOVER_PORT, "*")
	if err != OK:
		_udp.close()
		_udp = null
		return
	_udp.set_broadcast_enabled(true)
	_role = _Role.HOST
	set_process(true)

func update_host(occupied: int, max_seats: int, net_play: int, loop_goal: int, arena_id: String, room_id: String = "", host_display_name: String = "", ticket: String = "") -> void:
	if _role != _Role.HOST:
		return
	_apply_host_fields(occupied, max_seats, net_play, loop_goal, arena_id, room_id, host_display_name, ticket)

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

## 按发现到的地址取出门票，供 Guest 在 hello 里出示。列表展示不走这里，避免把票画到房间卡上。
func ticket_for_address(address: String) -> String:
	var key: String = _canonical_ipv4(address.strip_edges())
	if key.is_empty() or not _rooms.has(key):
		return ""
	var room: Dictionary = _rooms[key] as Dictionary
	return str(room.get("ticket", ""))

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

func _apply_host_fields(occupied: int, max_seats: int, net_play: int, loop_goal: int, arena_id: String, room_id: String = "", host_display_name: String = "", ticket: String = "") -> void:
	_occupied = clampi(occupied, 1, 5)
	_max_seats = max_seats
	_net_play = net_play
	_loop_goal = maxi(loop_goal, 0)
	_arena_id = GameLaunch._sanitize_arena_id(arena_id)
	_room_id = _sanitize_display(room_id, 32)
	_host_display_name = _sanitize_display(host_display_name, 24)
	_ticket = _sanitize_ticket(ticket)

## Beacon 字段只用于显示，统一走保守字符集，避免广播包里塞控制字符 / 分隔符。
static func _sanitize_display(value: String, limit: int) -> String:
	var text: String = value.strip_edges()
	if text.length() > limit:
		text = text.substr(0, limit)
	var out: String = ""
	for i: int in text.length():
		var c: int = text.unicode_at(i)
		var is_digit: bool = c >= 48 and c <= 57
		var is_lower: bool = c >= 97 and c <= 122
		var is_upper: bool = c >= 65 and c <= 90
		if is_digit or is_lower or is_upper or c == 45 or c == 95:
			out += char(c)
	return out

## 发现包里的门票必须是完整 hex。截断或夹带其它字符一律变成空票，让 Host 去拒绝，而不是放行半张票。
static func _sanitize_ticket(value: String) -> String:
	var text: String = value.strip_edges()
	if text.length() < 8 or text.length() > 64:
		return ""
	for i: int in text.length():
		var c: int = text.unicode_at(i)
		var is_digit: bool = c >= 48 and c <= 57
		var is_lower: bool = c >= 97 and c <= 102
		var is_upper: bool = c >= 65 and c <= 70
		if not (is_digit or is_lower or is_upper):
			return ""
	return text

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
	## 协议 6 追加：room_id / host_display_name。解析侧按可见字节兜底，缺失即空串。
	buf.put_utf8_string(_room_id)
	buf.put_utf8_string(_host_display_name)
	buf.put_utf8_string(_ticket)
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
	if _is_same_public_room(prev, parsed) and str(prev.get("ticket", "")) == str(parsed.get("ticket", "")):
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
	## 协议 6 的可选尾巴：老包 / 截断包不该让整条房间记录失效，缺失就是空。
	var room_id: String = ""
	var host_display_name: String = ""
	if buf.get_available_bytes() > 0:
		room_id = _sanitize_display(buf.get_utf8_string(), 32)
	if buf.get_available_bytes() > 0:
		host_display_name = _sanitize_display(buf.get_utf8_string(), 24)
	var ticket: String = ""
	if buf.get_available_bytes() > 0:
		ticket = _sanitize_ticket(buf.get_utf8_string())
	return {
		"occupied": occupied,
		"max_seats": max_seats,
		"net_play": net_play,
		"loop_goal": loop_goal,
		"arena_id": arena_id,
		"room_id": room_id,
		"host_display_name": host_display_name,
		"ticket": ticket,
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
		"room_id": str(room.get("room_id", "")),
		"host_display_name": str(room.get("host_display_name", "")),
	}

func _is_same_public_room(a: Dictionary, b: Dictionary) -> bool:
	if a.is_empty():
		return false
	return str(a.get("address", "")) == str(b.get("address", "")) and int(a.get("occupied", -1)) == int(b.get("occupied", -1)) and int(a.get("max_seats", -1)) == int(b.get("max_seats", -1)) and int(a.get("net_play", -1)) == int(b.get("net_play", -1)) and int(a.get("loop_goal", -1)) == int(b.get("loop_goal", -1)) and str(a.get("arena_id", "")) == str(b.get("arena_id", "")) and str(a.get("room_id", "")) == str(b.get("room_id", "")) and str(a.get("host_display_name", "")) == str(b.get("host_display_name", ""))

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
