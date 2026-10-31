extends Object
class_name OnlineProtocol

## Online Dedicated Server 协议常量。与 LAN/P2P 的 GameLaunch.NET_* 严格分离。
## Phase 2B：hello 携带 game_ticket（短命 scoped）；dev/stub 仅本地。不复用 LAN room ticket。

const PROTOCOL_VERSION: int = 1
## 默认游戏 UDP 端口。与 LAN 的 17777 分离，避免本地双路径撞端口。
const DEFAULT_PORT: int = 24567
## Online 初始匹配上限 4；LAN 仍使用 GameLaunch.NET_MAX_SEATS=5。
const MAX_PLAYERS: int = 4
## Phase 2D：tick + match_id + seat/pos/facing。旧 v1 解码器拒绝。
const SNAPSHOT_VERSION: int = 2
const SNAPSHOT_HZ: float = 20.0
const SNAPSHOT_INTERVAL: float = 1.0 / SNAPSHOT_HZ
const INPUT_HZ: float = 20.0
const INPUT_MIN_INTERVAL_MS: int = int(1000.0 / INPUT_HZ)
const MAX_DISPLAY_NAME_LEN: int = 24
const MAX_DEV_TOKEN_LEN: int = 64
## game_ticket 长度上界（WildBoat opaque / stub / 短 JWT）。
const MAX_GAME_TICKET_LEN: int = 512
## match_id 写入 snapshot 的长度上界（防畸形包）。
const MAX_MATCH_ID_LEN: int = 64
## 权威移动速度（单位/秒）。Phase 2A 最小仿真。
const MOVE_SPEED: float = 220.0
const CHANNEL_NODE_NAME := "OnlineChannel"
const READY_FILE_DEFAULT := "user://wpg_ds_ready"

enum RejectReason {
	NONE = 0,
	BAD_PROTOCOL = 1,
	BAD_TOKEN = 2,
	FULL = 3,
	DUPLICATE = 4,
	MALFORMED = 5,
	TICKET_EXPIRED = 6,
	TICKET_REPLAYED = 7,
	TICKET_MISMATCH = 8,
	BACKEND_UNAVAILABLE = 9,
	## 客户端侧：ENet 未能连上 DS（尚未收到 welcome/reject）。
	CONNECTION_FAILED = 10,
}

enum AdmissionMode {
	DEV = 0,
	STUB = 1,
	WILDBOAT = 2,
}


static func clamp_display_name(name: String) -> String:
	var cleaned: String = name.strip_edges()
	if cleaned.is_empty():
		return "player"
	if cleaned.length() > MAX_DISPLAY_NAME_LEN:
		return cleaned.substr(0, MAX_DISPLAY_NAME_LEN)
	return cleaned


## 面向玩家的拒绝原因文案。不得把后端不可用说成匹配成功。
static func reject_reason_text(reason: int) -> String:
	match reason:
		RejectReason.NONE:
			return "OK"
		RejectReason.BAD_PROTOCOL:
			return "Protocol mismatch — update client/server"
		RejectReason.BAD_TOKEN:
			return "Invalid ticket — request assignment again"
		RejectReason.FULL:
			return "Match full (max 4 players)"
		RejectReason.DUPLICATE:
			return "Already in this match"
		RejectReason.MALFORMED:
			return "Malformed join request"
		RejectReason.TICKET_EXPIRED:
			return "Ticket expired — request assignment again"
		RejectReason.TICKET_REPLAYED:
			return "Ticket already used — request a new assignment"
		RejectReason.TICKET_MISMATCH:
			return "Ticket does not match this server"
		RejectReason.BACKEND_UNAVAILABLE:
			return "WildBoat unreachable — match NOT joined (backend down)"
		RejectReason.CONNECTION_FAILED:
			return "Cannot reach Dedicated Server — is it running?"
		_:
			return "Rejected (code %d)" % reason


static func encode_snapshot(tick: int, players: Array, match_id: String = "") -> PackedByteArray:
	var buf := StreamPeerBuffer.new()
	buf.put_u8(SNAPSHOT_VERSION)
	buf.put_u32(tick)
	var mid: String = match_id.strip_edges()
	if mid.length() > MAX_MATCH_ID_LEN:
		mid = mid.substr(0, MAX_MATCH_ID_LEN)
	buf.put_utf8_string(mid)
	buf.put_u8(players.size())
	for entry in players:
		var state: DsPlayerState = entry as DsPlayerState
		if state == null:
			continue
		buf.put_u8(state.seat)
		buf.put_float(state.position.x)
		buf.put_float(state.position.y)
		buf.put_float(state.facing.x)
		buf.put_float(state.facing.y)
	return buf.data_array


static func decode_snapshot(data: PackedByteArray) -> Dictionary:
	var out: Dictionary = {
		"ok": false,
		"version": 0,
		"tick": 0,
		"match_id": "",
		"players": [],
	}
	if data.is_empty():
		return out
	var buf := StreamPeerBuffer.new()
	buf.data_array = data
	if buf.get_available_bytes() < 6:
		return out
	var version: int = buf.get_u8()
	if version != SNAPSHOT_VERSION:
		return out
	var tick: int = int(buf.get_u32())
	if buf.get_available_bytes() < 4:
		return out
	var match_id: String = buf.get_utf8_string()
	if match_id.length() > MAX_MATCH_ID_LEN:
		return out
	if buf.get_available_bytes() < 1:
		return out
	var count: int = buf.get_u8()
	if count < 0 or count > MAX_PLAYERS:
		return out
	var players: Array = []
	for _i in count:
		## seat(1) + pos(8) + facing(8)
		if buf.get_available_bytes() < 17:
			return out
		var seat: int = buf.get_u8()
		var x: float = buf.get_float()
		var y: float = buf.get_float()
		var fx: float = buf.get_float()
		var fy: float = buf.get_float()
		if seat < 1 or seat > MAX_PLAYERS:
			return out
		if not is_finite(x) or not is_finite(y) or not is_finite(fx) or not is_finite(fy):
			return out
		var facing := Vector2(fx, fy)
		if facing.length_squared() > 1.0001:
			facing = facing.normalized()
		elif facing.length_squared() < 0.0001:
			facing = Vector2.RIGHT
		players.append({
			"seat": seat,
			"position": Vector2(x, y),
			"facing": facing,
		})
	out["ok"] = true
	out["version"] = version
	out["tick"] = tick
	out["match_id"] = match_id
	out["players"] = players
	return out
