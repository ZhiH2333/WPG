extends Object
class_name OnlineProtocol

## Online Dedicated Server 协议常量。与 LAN/P2P 的 GameLaunch.NET_* 严格分离。
## Phase 2A：开发身份 + 最小权威复制环。不复用 LAN room ticket。

const PROTOCOL_VERSION: int = 1
## 默认游戏 UDP 端口。与 LAN 的 17777 分离，避免本地双路径撞端口。
const DEFAULT_PORT: int = 24567
## Online 初始匹配上限 4；LAN 仍使用 GameLaunch.NET_MAX_SEATS=5。
const MAX_PLAYERS: int = 4
const SNAPSHOT_VERSION: int = 1
const SNAPSHOT_HZ: float = 20.0
const SNAPSHOT_INTERVAL: float = 1.0 / SNAPSHOT_HZ
const INPUT_HZ: float = 20.0
const INPUT_MIN_INTERVAL_MS: int = int(1000.0 / INPUT_HZ)
const MAX_DISPLAY_NAME_LEN: int = 24
const MAX_DEV_TOKEN_LEN: int = 64
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
}


static func clamp_display_name(name: String) -> String:
	var cleaned: String = name.strip_edges()
	if cleaned.is_empty():
		return "player"
	if cleaned.length() > MAX_DISPLAY_NAME_LEN:
		return cleaned.substr(0, MAX_DISPLAY_NAME_LEN)
	return cleaned


static func encode_snapshot(tick: int, players: Array) -> PackedByteArray:
	var buf := StreamPeerBuffer.new()
	buf.put_u8(SNAPSHOT_VERSION)
	buf.put_u32(tick)
	buf.put_u8(players.size())
	for entry in players:
		var state: DsPlayerState = entry as DsPlayerState
		if state == null:
			continue
		buf.put_u8(state.seat)
		buf.put_float(state.position.x)
		buf.put_float(state.position.y)
	return buf.data_array


static func decode_snapshot(data: PackedByteArray) -> Dictionary:
	var out: Dictionary = {
		"ok": false,
		"version": 0,
		"tick": 0,
		"players": [],
	}
	if data.is_empty():
		return out
	var buf := StreamPeerBuffer.new()
	buf.data_array = data
	if buf.get_available_bytes() < 6:
		return out
	var version: int = buf.get_u8()
	var tick: int = int(buf.get_u32())
	var count: int = buf.get_u8()
	if version != SNAPSHOT_VERSION:
		return out
	if count < 0 or count > MAX_PLAYERS:
		return out
	var players: Array = []
	for _i in count:
		if buf.get_available_bytes() < 9:
			return out
		var seat: int = buf.get_u8()
		var x: float = buf.get_float()
		var y: float = buf.get_float()
		if seat < 1 or seat > MAX_PLAYERS:
			return out
		players.append({"seat": seat, "position": Vector2(x, y)})
	out["ok"] = true
	out["version"] = version
	out["tick"] = tick
	out["players"] = players
	return out
