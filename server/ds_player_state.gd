extends RefCounted
class_name DsPlayerState

## Dedicated Server 侧一名已准入玩家的权威状态。
## seat 与 peer_id 解耦：peer 1 永远是 Dedicated Server，不是人类 Host。

var seat: int = 0
var peer_id: int = 0
var player_id: String = ""
var display_name: String = ""
var position: Vector2 = Vector2.ZERO
var facing: Vector2 = Vector2.RIGHT
var move_input: Vector2 = Vector2.ZERO
var last_input_ms: int = 0
var admitted_ms: int = 0


func _init(p_seat: int = 0, p_peer_id: int = 0, p_name: String = "", p_player_id: String = "") -> void:
	seat = p_seat
	peer_id = p_peer_id
	player_id = p_player_id
	display_name = OnlineProtocol.clamp_display_name(p_name)
	position = _spawn_for_seat(p_seat)
	facing = Vector2.RIGHT
	admitted_ms = Time.get_ticks_msec()


func apply_input(mx: float, my: float, now_ms: int) -> bool:
	if now_ms - last_input_ms < OnlineProtocol.INPUT_MIN_INTERVAL_MS:
		return false
	last_input_ms = now_ms
	var raw := Vector2(mx, my)
	if raw.length_squared() > 1.0001:
		raw = raw.normalized()
	move_input = raw.clamp(Vector2(-1, -1), Vector2(1, 1))
	if move_input.length_squared() > 0.0001:
		facing = move_input.normalized()
	return true


func simulate(delta: float) -> void:
	position += move_input * OnlineProtocol.MOVE_SPEED * delta


static func _spawn_for_seat(seat: int) -> Vector2:
	match seat:
		1:
			return Vector2(0, 0)
		2:
			return Vector2(80, 0)
		3:
			return Vector2(-80, 0)
		4:
			return Vector2(0, 80)
		_:
			return Vector2.ZERO
