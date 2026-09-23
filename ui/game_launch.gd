extends Object
class_name GameLaunch

## 一次性把模式、档位 id、局域网身份、对局模式、竞技场 id 和换场目标带进下一场。不是 Autoload，不是 Node，禁止 get_tree()。默认 Infinite / OFFLINE / COOP / yard，take 后打回缺省。只传 id，不塞 Record / ArenaDef 对象。NetPlay 不进 records.json。
enum Mode { SOLO, INFINITE }
enum NetRole { OFFLINE, HOST, GUEST }
enum NetPlay { COOP, BATTLE }

const SOLO_LOOP_GOAL: int = 20 ## 滑杆默认与缺档 Solo 隐式档，不是运行时硬锁终点
const NET_PORT: int = 17777
const NET_PROTOCOL: int = 4
const DEFAULT_JOIN_ADDRESS := "127.0.0.1"
const ARENA_CATALOG: ArenaCatalog = preload("res://data/arena_catalog.tres")

static var _mode: Mode = Mode.INFINITE
static var _active_record_id: String = ""
static var _net_role: NetRole = NetRole.OFFLINE
static var _net_play: NetPlay = NetPlay.COOP
static var _join_address: String = DEFAULT_JOIN_ADDRESS
static var _lan_host_character_id: String = "boar"
static var _lan_guest_character_id: String = "boar"
static var _lan_loop_goal: int = 0
static var _arena_id: String = "yard"
static var _next_scene: String = ""

static func set_mode(mode: Mode) -> void:
	_mode = mode

static func take_mode() -> Mode:
	var current: Mode = _mode
	_mode = Mode.INFINITE
	return current

static func set_active_record_id(id: String) -> void:
	_active_record_id = id

static func take_active_record_id() -> String:
	var current: String = _active_record_id
	_active_record_id = ""
	return current

static func set_net_role(role: NetRole) -> void:
	_net_role = role

static func take_net_role() -> NetRole:
	var current: NetRole = _net_role
	_net_role = NetRole.OFFLINE
	return current

static func set_net_play(play: NetPlay) -> void:
	_net_play = play

static func take_net_play() -> NetPlay:
	var current: NetPlay = _net_play
	_net_play = NetPlay.COOP
	return current

static func set_join_address(address: String) -> void:
	var trimmed: String = address.strip_edges()
	if trimmed.is_empty():
		_join_address = DEFAULT_JOIN_ADDRESS
		return
	_join_address = trimmed

static func take_join_address() -> String:
	var current: String = _join_address
	_join_address = DEFAULT_JOIN_ADDRESS
	return current

static func set_lan_loadout(host_character_id: String, guest_character_id: String, loop_goal: int) -> void:
	_lan_host_character_id = _sanitize_character_id(host_character_id)
	_lan_guest_character_id = _sanitize_character_id(guest_character_id)
	_lan_loop_goal = maxi(loop_goal, 0)

static func take_lan_loadout() -> Dictionary:
	var loadout: Dictionary = {
		"host_character_id": _lan_host_character_id,
		"guest_character_id": _lan_guest_character_id,
		"loop_goal": _lan_loop_goal,
	}
	_lan_host_character_id = "boar"
	_lan_guest_character_id = "boar"
	_lan_loop_goal = 0
	return loadout

static func set_arena_id(id: String) -> void:
	_arena_id = _sanitize_arena_id(id)

static func take_arena_id() -> String:
	var current: String = _arena_id
	_arena_id = "yard"
	return _sanitize_arena_id(current)

static func set_next_scene(path: String) -> void:
	_next_scene = path

static func peek_next_scene() -> String:
	return _next_scene

static func take_next_scene() -> String:
	var current: String = _next_scene
	_next_scene = ""
	return current

static func _sanitize_character_id(requested: String) -> String:
	if requested == "chicken":
		return "chicken"
	return "boar"

static func _sanitize_arena_id(requested: String) -> String:
	return ARENA_CATALOG.sanitize(requested)
