extends RefCounted
class_name OnlineReplica

## 客户端 Online 世界复制状态：过滤过期/重复 snapshot，跟踪可见座位。
## 不拥有 Player 节点；由 CombatSandbox 根据 accept 结果生成/更新/销毁实体。
## 权威位置只来自 DS snapshot；客户端不得用本地输入改写远端座位。

var expected_match_id: String = ""
var local_seat: int = 0
var last_tick: int = -1
var visible_seats: Dictionary = {} ## seat -> true


func configure(match_id: String, seat: int) -> void:
	expected_match_id = match_id.strip_edges()
	local_seat = clampi(seat, 0, OnlineProtocol.MAX_PLAYERS)
	last_tick = -1
	visible_seats.clear()


func reset() -> void:
	last_tick = -1
	visible_seats.clear()


## 返回 {ok, tick, players, spawned, removed}；ok=false 表示丢弃本包。
func accept_snapshot(tick: int, players: Array, match_id: String) -> Dictionary:
	var out: Dictionary = {
		"ok": false,
		"tick": tick,
		"players": [],
		"spawned": [],
		"removed": [],
	}
	if tick < 0:
		return out
	if tick <= last_tick:
		return out
	var mid: String = match_id.strip_edges()
	if not expected_match_id.is_empty() and not mid.is_empty() and mid != expected_match_id:
		return out
	var cleaned: Array = []
	var seen: Dictionary = {}
	for entry in players:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = entry
		var seat: int = int(d.get("seat", 0))
		if seat < 1 or seat > OnlineProtocol.MAX_PLAYERS:
			continue
		if seen.has(seat):
			continue
		var pos: Variant = d.get("position", Vector2.ZERO)
		if typeof(pos) != TYPE_VECTOR2:
			continue
		var facing: Variant = d.get("facing", Vector2.RIGHT)
		if typeof(facing) != TYPE_VECTOR2:
			facing = Vector2.RIGHT
		seen[seat] = true
		cleaned.append({
			"seat": seat,
			"position": pos,
			"facing": facing,
		})
	var spawned: Array = []
	for seat in seen.keys():
		if not visible_seats.has(seat):
			spawned.append(seat)
		visible_seats[seat] = true
	var removed: Array = []
	var stale: Array = visible_seats.keys()
	for seat in stale:
		if seen.has(seat):
			continue
		visible_seats.erase(seat)
		removed.append(seat)
	last_tick = tick
	out["ok"] = true
	out["players"] = cleaned
	out["spawned"] = spawned
	out["removed"] = removed
	return out


func note_peer_left(seat: int) -> bool:
	if seat < 1 or seat > OnlineProtocol.MAX_PLAYERS:
		return false
	if not visible_seats.has(seat):
		return false
	visible_seats.erase(seat)
	return true


func is_local_seat(seat: int) -> bool:
	return seat == local_seat and local_seat > 0
