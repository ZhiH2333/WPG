extends Node
class_name PlayerDash

## 短冲刺：穿怪不穿墙。不写进 Player / Motor。不用 Engine.time_scale。
const DASH_DISTANCE: float = 260.0 ## 像素
const DASH_DURATION_SEC: float = 0.16
const DASH_COOLDOWN_SEC: float = 1.05 ## 从起冲那一帧起算，含冲刺本身
const CAMERA_KICK: float = 4.0
const AFTERIMAGE_INTERVAL_SEC: float = 0.035
const DASH_MODULATE := Color(1.35, 1.35, 1.45, 1)

signal dash_started(origin: Vector2, direction: Vector2)
signal dash_finished(origin: Vector2)

var _player_input: PlayerInput
var _player_camera: PlayerCamera
var _sfx_pool: SfxPool
var _player: Player
var _visual: Node2D
var _body: Sprite2D
var _dashing: bool = false
var _dash_left_sec: float = 0.0
var _cooldown_left_sec: float = 0.0
var _direction: Vector2 = Vector2.RIGHT
var _afterimage_left_sec: float = 0.0

func _ready() -> void:
	_player = get_parent() as Player
	if _player != null:
		_visual = _player.get_node_or_null("Visual") as Node2D
		_body = _player.get_node_or_null("Visual/Body") as Sprite2D

func bind_player_input(player_input: PlayerInput) -> void:
	_player_input = player_input

func bind_player_camera(player_camera: PlayerCamera) -> void:
	_player_camera = player_camera

func bind_sfx_pool(sfx_pool: SfxPool) -> void:
	_sfx_pool = sfx_pool

func is_dashing() -> bool:
	return _dashing

func get_cooldown_left() -> float:
	return _cooldown_left_sec

func get_direction() -> Vector2:
	return _direction

func try_dash() -> bool:
	if _dashing or _cooldown_left_sec > 0.0:
		return false
	if _player_input == null or not _player_input.dash_just_pressed or _player_input.is_dash_suppressed():
		return false
	if _player == null or _player.is_defeated():
		return false
	var session: RunSession = _find_run_session()
	if session != null and not session.is_playing():
		return false
	_direction = _resolve_direction()
	_dashing = true
	_dash_left_sec = DASH_DURATION_SEC
	_cooldown_left_sec = DASH_COOLDOWN_SEC
	_afterimage_left_sec = 0.0
	_player.clear_knockback()
	_apply_visual(true)
	_spawn_dash_burst(34.0)
	_spawn_afterimage()
	dash_started.emit(_player.global_position, _direction)
	if _player_camera != null:
		_player_camera.apply_kick(_direction, CAMERA_KICK)
	if _sfx_pool != null:
		_sfx_pool.play_dash(_player.global_position)
	return true

func tick(delta: float, current_velocity: Vector2) -> Vector2:
	if _cooldown_left_sec > 0.0:
		_cooldown_left_sec = maxf(0.0, _cooldown_left_sec - delta)
	if not _dashing:
		return current_velocity
	_afterimage_left_sec -= delta
	if _afterimage_left_sec <= 0.0:
		_spawn_afterimage()
		_afterimage_left_sec = AFTERIMAGE_INTERVAL_SEC
	_dash_left_sec = maxf(0.0, _dash_left_sec - delta)
	var dash_velocity: Vector2 = _direction * (DASH_DISTANCE / DASH_DURATION_SEC)
	if _dash_left_sec <= 0.0:
		_stop_dash()
	return dash_velocity

func reset_for_sandbox() -> void:
	_dashing = false
	_dash_left_sec = 0.0
	_cooldown_left_sec = 0.0
	_afterimage_left_sec = 0.0
	_apply_visual(false)

func apply_net_state(dashing: bool, cooldown: float, direction: Vector2) -> void:
	_cooldown_left_sec = maxf(0.0, cooldown)
	if direction.is_finite() and not direction.is_zero_approx():
		_direction = direction.normalized()
	if dashing and not _dashing:
		play_remote_fx(_direction)
	_dashing = dashing
	_apply_visual(_dashing)

func play_remote_fx(direction: Vector2) -> void:
	if direction.is_finite() and not direction.is_zero_approx():
		_direction = direction.normalized()
	_spawn_dash_burst(34.0)
	_spawn_afterimage()
	if _sfx_pool != null and _player != null:
		_sfx_pool.play_dash(_player.global_position)

func _stop_dash() -> void:
	_dashing = false
	_dash_left_sec = 0.0
	_apply_visual(false)
	_spawn_dash_burst(24.0)
	if _player != null:
		dash_finished.emit(_player.global_position)

func _find_run_session() -> RunSession:
	var node: Node = _player
	while node != null:
		var session: RunSession = node.get_node_or_null("RunSession") as RunSession
		if session != null:
			return session
		node = node.get_parent()
	return null

func _resolve_direction() -> Vector2:
	var move: Vector2 = _player_input.move_vector
	if move.is_finite() and not move.is_zero_approx():
		return move.normalized()
	var aim: Vector2 = _player_input.aim_vector
	if aim.is_finite() and not aim.is_zero_approx():
		return aim.normalized()
	return Vector2.RIGHT

func _move_speed() -> float:
	if _player == null:
		return 420.0
	return _player.get_player_motor().move_speed

func _apply_visual(dashing: bool) -> void:
	if _visual == null:
		return
	if dashing:
		_visual.modulate = DASH_MODULATE
		return
	_visual.modulate = Color.WHITE

func _spawn_afterimage() -> void:
	if _player == null or _body == null or _body.texture == null:
		return
	var parent: Node = _player.get_parent()
	if parent == null:
		return
	var ghost: DashAfterimage = DashAfterimage.new()
	parent.add_child(ghost)
	ghost.setup(_body)

func _spawn_dash_burst(radius: float) -> void:
	if _player == null:
		return
	var parent: Node = _player.get_parent()
	if parent == null:
		return
	var burst: AbilityPulse = AbilityPulse.new()
	burst.name = "DashBurst"
	parent.add_child(burst)
	burst.setup(_player.global_position, radius, 0.18, Color(0.34, 0.9, 1.0, 1.0))
