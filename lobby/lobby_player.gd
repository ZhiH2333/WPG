extends RefCounted
class_name LobbyPlayer

## 房间内实例（docs/ui_lobby_architecture.md §3.3）。RefCounted 域对象：
## 不落盘、不持有 ENet / MultiplayerPeer、不碰 UI、不碰 SceneTree。
##
## 四个标识严格分开，禁止互相顶替：
## - profile_id：本机是谁（PlayerProfile，本机权威）。不是 token、不是 seat、不是 peer_id。
## - peer_id：这次套接字。Host 上恒为 1；0 表示还没有 ENet 连接（离线 mock / pending）。
## - seat：本房站位 1..5（1 = Host，2..5 = Guest）；0 = 未入座。
## - session token：房间门票，属于 JoinInvite（Phase 8），不是本对象字段。
##   preferred_character_id 是 Profile 的默认选角；selected_character_id 是它在本房内的投影。

enum ConnectionState { CONNECTED, CONNECTING, LOST }
enum Path { LAN_IPV4, IPV6, WAN_IPV4 }

const NO_SEAT: int = 0
const HOST_SEAT: int = 1
const NO_PEER: int = 0
## 离线 mock 占位 profile_id 前缀。只在本机假座位上出现，永不上网（Phase 7 真 roster 没有它）。
const MOCK_PROFILE_PREFIX := "mock:"

var profile_id: String = ""
var display_name: String = ""
var avatar_id: String = PlayerProfile.DEFAULT_AVATAR
var preferred_character_id: String = PlayerProfile.DEFAULT_CHARACTER
var peer_id: int = NO_PEER
var seat: int = NO_SEAT
var selected_character_id: String = PlayerProfile.DEFAULT_CHARACTER
## ready 第一刀默认 true（架构 §4.1 规则 4），Phase 5 才允许切换。
var ready: bool = true
var connection_state: ConnectionState = ConnectionState.CONNECTED
var is_host: bool = false
## 认证后才成立；1.0 恒 LAN_IPV4。
var path: Path = Path.LAN_IPV4
## 1.0 可恒 0。
var rtt_ms: int = 0

## PlayerProfile 进房时只复制公开字段（Profile 本身仍在盘上，房间对象销毁不影响它）。
static func from_profile(profile: Dictionary, peer: int, seat: int, host: bool) -> LobbyPlayer:
	var player: LobbyPlayer = LobbyPlayer.new()
	player.profile_id = str(profile.get("profile_id", ""))
	player.display_name = PlayerProfile.sanitize_name(str(profile.get("display_name", PlayerProfile.DEFAULT_NAME)))
	player.avatar_id = PlayerProfile.sanitize_character_id(str(profile.get("avatar_id", PlayerProfile.DEFAULT_AVATAR)))
	player.preferred_character_id = PlayerProfile.sanitize_character_id(str(profile.get("selected_character_id", PlayerProfile.DEFAULT_CHARACTER)))
	player.selected_character_id = player.preferred_character_id
	player.peer_id = peer
	player.seat = seat
	player.is_host = host
	return player

## LobbyNet 同步用：从快照字典还原（Phase 4/7 的 roster 包解出来就是这一步）。
static func from_dict(data: Dictionary) -> LobbyPlayer:
	var player: LobbyPlayer = LobbyPlayer.new()
	player.profile_id = str(data.get("profile_id", ""))
	player.display_name = PlayerProfile.sanitize_name(str(data.get("display_name", PlayerProfile.DEFAULT_NAME)))
	player.avatar_id = PlayerProfile.sanitize_character_id(str(data.get("avatar_id", PlayerProfile.DEFAULT_AVATAR)))
	player.preferred_character_id = PlayerProfile.sanitize_character_id(str(data.get("preferred_character_id", PlayerProfile.DEFAULT_CHARACTER)))
	player.selected_character_id = PlayerProfile.sanitize_character_id(str(data.get("selected_character_id", player.preferred_character_id)))
	player.peer_id = int(data.get("peer_id", NO_PEER))
	player.seat = int(data.get("seat", NO_SEAT))
	player.ready = bool(data.get("ready", true))
	player.is_host = bool(data.get("is_host", false))
	player.connection_state = _sanitize_state(int(data.get("connection_state", ConnectionState.CONNECTED)))
	player.path = _sanitize_path(int(data.get("path", Path.LAN_IPV4)))
	player.rtt_ms = maxi(int(data.get("rtt_ms", 0)), 0)
	return player

## 复制一份（Room 快照 / 未来 LobbyNet 发包都用副本，避免外部改到房内实例）。
func copy() -> LobbyPlayer:
	return LobbyPlayer.from_dict(to_dict())

func to_dict() -> Dictionary:
	return {
		"profile_id": profile_id,
		"display_name": display_name,
		"avatar_id": avatar_id,
		"preferred_character_id": preferred_character_id,
		"peer_id": peer_id,
		"seat": seat,
		"selected_character_id": selected_character_id,
		"ready": ready,
		"connection_state": int(connection_state),
		"is_host": is_host,
		"path": int(path),
		"rtt_ms": rtt_ms,
	}

func set_display_name(value: String) -> void:
	display_name = PlayerProfile.sanitize_name(value)

func set_selected_character_id(value: String) -> void:
	selected_character_id = PlayerProfile.sanitize_character_id(value)

func has_seat() -> bool:
	return seat >= HOST_SEAT

func is_seated_host() -> bool:
	return is_host and seat == HOST_SEAT

static func _sanitize_state(raw: int) -> ConnectionState:
	if raw == int(ConnectionState.CONNECTING):
		return ConnectionState.CONNECTING
	if raw == int(ConnectionState.LOST):
		return ConnectionState.LOST
	return ConnectionState.CONNECTED

static func _sanitize_path(raw: int) -> Path:
	if raw == int(Path.IPV6):
		return Path.IPV6
	if raw == int(Path.WAN_IPV4):
		return Path.WAN_IPV4
	return Path.LAN_IPV4
