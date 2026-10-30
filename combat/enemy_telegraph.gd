extends RefCounted
class_name EnemyTelegraph

## 敌人攻击预警状态（数据，不负责绘制）。
## 权威端推进 remaining / direction；客户端只消费同步后的快照字段。

enum Kind { NONE = 0, AIM_LINE = 1, CHARGE_PATH = 2, FAN_VOLLEY = 3 }

const NET_NONE: int = Kind.NONE
const DEFAULT_AIM_COLOR := Color(239.0 / 255.0, 68.0 / 255.0, 68.0 / 255.0, 1.0)
const DEFAULT_CORE_COLOR := Color(254.0 / 255.0, 226.0 / 255.0, 226.0 / 255.0, 1.0)

var kind: int = Kind.NONE
var duration: float = 0.0
var remaining: float = 0.0
var direction: Vector2 = Vector2.RIGHT
var length: float = 0.0
var track_live: bool = true
var fan_count: int = 0
var fan_spread_deg: float = 0.0
var origin_local: Vector2 = Vector2.ZERO

func clear() -> void:
	kind = Kind.NONE
	duration = 0.0
	remaining = 0.0
	direction = Vector2.RIGHT
	length = 0.0
	track_live = true
	fan_count = 0
	fan_spread_deg = 0.0
	origin_local = Vector2.ZERO

func is_active() -> bool:
	return kind != Kind.NONE and remaining > 0.0

func progress() -> float:
	if duration <= 0.0:
		return 1.0
	return clampf(1.0 - remaining / duration, 0.0, 1.0)

func begin_aim_line(duration_sec: float, path_length: float, live_track: bool = true, local_origin: Vector2 = Vector2.ZERO) -> void:
	_begin(Kind.AIM_LINE, duration_sec, path_length, live_track, local_origin, 0, 0.0)

func begin_charge_path(duration_sec: float, path_length: float, live_track: bool = true, local_origin: Vector2 = Vector2.ZERO) -> void:
	_begin(Kind.CHARGE_PATH, duration_sec, path_length, live_track, local_origin, 0, 0.0)

func begin_fan_volley(
	duration_sec: float,
	path_length: float,
	count: int,
	spread_deg: float,
	live_track: bool = true,
	local_origin: Vector2 = Vector2.ZERO
) -> void:
	_begin(Kind.FAN_VOLLEY, duration_sec, path_length, live_track, local_origin, count, spread_deg)

func set_direction(dir: Vector2) -> void:
	if dir.is_finite() and not dir.is_zero_approx():
		direction = dir.normalized()
	else:
		direction = Vector2.RIGHT

func set_length(path_length: float) -> void:
	length = maxf(0.0, path_length)

func set_remaining(sec: float) -> void:
	remaining = maxf(0.0, sec)
	if remaining <= 0.0:
		clear()

func tick(delta: float) -> bool:
	## 返回 true 表示本帧倒计时刚走完；调用方读完 direction 后应 clear()。
	if not is_active():
		return false
	remaining = maxf(0.0, remaining - delta)
	return remaining <= 0.0

func aim_alpha() -> float:
	return 0.4 + progress() * 0.6

func charge_alpha() -> float:
	return 0.25 + progress() * 0.55

func write_net(buf: StreamPeerBuffer) -> void:
	if not is_active():
		buf.put_u8(Kind.NONE)
		return
	buf.put_u8(kind)
	buf.put_float(remaining)
	buf.put_float(duration)
	buf.put_float(direction.x)
	buf.put_float(direction.y)
	buf.put_float(length)
	buf.put_float(origin_local.x)
	buf.put_float(origin_local.y)
	buf.put_u8(clampi(fan_count, 0, 255))
	buf.put_float(fan_spread_deg)

func read_net(buf: StreamPeerBuffer) -> void:
	var next_kind: int = buf.get_u8()
	if next_kind == Kind.NONE:
		clear()
		return
	kind = next_kind
	remaining = buf.get_float()
	duration = buf.get_float()
	direction = Vector2(buf.get_float(), buf.get_float())
	if not direction.is_finite() or direction.is_zero_approx():
		direction = Vector2.RIGHT
	else:
		direction = direction.normalized()
	length = maxf(0.0, buf.get_float())
	origin_local = Vector2(buf.get_float(), buf.get_float())
	fan_count = buf.get_u8()
	fan_spread_deg = buf.get_float()
	track_live = false
	if remaining <= 0.0 or kind == Kind.NONE:
		clear()

func duplicate_state() -> EnemyTelegraph:
	var copy: EnemyTelegraph = EnemyTelegraph.new()
	copy.kind = kind
	copy.duration = duration
	copy.remaining = remaining
	copy.direction = direction
	copy.length = length
	copy.track_live = track_live
	copy.fan_count = fan_count
	copy.fan_spread_deg = fan_spread_deg
	copy.origin_local = origin_local
	return copy

func _begin(
	next_kind: int,
	duration_sec: float,
	path_length: float,
	live_track: bool,
	local_origin: Vector2,
	count: int,
	spread_deg: float
) -> void:
	kind = next_kind
	duration = maxf(0.01, duration_sec)
	remaining = duration
	length = maxf(0.0, path_length)
	track_live = live_track
	origin_local = local_origin
	fan_count = maxi(0, count)
	fan_spread_deg = spread_deg
