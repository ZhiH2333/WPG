extends RefCounted
class_name LobbyPlayer

## 房间里的一名玩家。进房时从 Profile 复制公开字段，退房即丢，不写盘。
enum ConnectionState { CONNECTING, CONNECTED }

const PATH_LAN_IPV4: int = 0
const MOCK_PEER_BASE: int = 1000

var profile_id: String = ""
var display_name: String = ""
var avatar_id: String = "boar"
var peer_id: int = 0
var seat: int = 0
var selected_character_id: String = "boar"
var ready: bool = true
var connection_state: ConnectionState = ConnectionState.CONNECTED
var is_host: bool = false
var path: int = PATH_LAN_IPV4
var rtt_ms: int = 0

func is_mock() -> bool:
	return peer_id >= MOCK_PEER_BASE

func has_joined() -> bool:
	return connection_state == ConnectionState.CONNECTED
