extends Node
class_name HitReaction

## 只驱动 Visual 的 squash / 微转 / 弹回 / 死亡塌缩。不改碰撞、不 move_and_slide。
const SQUASH_ALONG: float = 0.82
const STRETCH_ACROSS: float = 1.12
const TILT_DEG: float = 4.5
const RECOVER_SEC: float = 0.1
const DEATH_POSE_SEC: float = 0.15
const DEATH_COLLAPSE_SCALE := Vector2(1.15, 0.55)
const DEATH_COLLAPSE_TILT_DEG: float = 80.0
const DEATH_UPRIGHT_SCALE := Vector2(1.08, 0.78)

var _visual: Node2D
var _base_rotation: float = 0.0
var _extra_tilt: float = 0.0
var _recover_from_scale: Vector2 = Vector2.ONE
var _recover_from_tilt: float = 0.0
var _recover_left_sec: float = 0.0
var _dead: bool = false
var _death_from_scale: Vector2 = Vector2.ONE
var _death_from_tilt: float = 0.0
var _death_to_scale: Vector2 = Vector2.ONE
var _death_to_tilt: float = 0.0
var _death_left_sec: float = 0.0

func bind_visual(visual: Node2D) -> void:
	_visual = visual
	if _visual == null:
		return
	_base_rotation = _visual.rotation

func play(hit_direction: Vector2) -> void:
	if _dead or _visual == null:
		return
	var direction: Vector2 = _normalize_or_right(hit_direction)
	_visual.scale = _squash_scale_for(direction)
	_extra_tilt = _tilt_for(direction)
	_recover_from_scale = _visual.scale
	_recover_from_tilt = _extra_tilt
	_recover_left_sec = RECOVER_SEC
	_sync_rotation()

func begin_death(collapse: bool) -> void:
	if _visual == null:
		return
	_dead = true
	_recover_left_sec = 0.0
	_death_from_scale = _visual.scale
	_death_from_tilt = _extra_tilt
	_death_left_sec = DEATH_POSE_SEC
	if collapse:
		_death_to_scale = DEATH_COLLAPSE_SCALE
		_death_to_tilt = deg_to_rad(DEATH_COLLAPSE_TILT_DEG) * _tilt_sign(_extra_tilt, _base_rotation)
	else:
		_death_to_scale = DEATH_UPRIGHT_SCALE
		_death_to_tilt = 0.0

func apply_facing(base_rotation: float) -> void:
	if _dead:
		return
	_base_rotation = base_rotation
	_sync_rotation()

func is_dead() -> bool:
	return _dead

func _process(delta: float) -> void:
	if _visual == null:
		return
	if _dead:
		_tick_death(delta)
		return
	_tick_recover(delta)

func _tick_recover(delta: float) -> void:
	if _recover_left_sec <= 0.0:
		return
	_recover_left_sec = maxf(0.0, _recover_left_sec - delta)
	var alpha: float = 1.0 - (_recover_left_sec / RECOVER_SEC)
	_visual.scale = _recover_from_scale.lerp(Vector2.ONE, alpha)
	_extra_tilt = lerpf(_recover_from_tilt, 0.0, alpha)
	if _recover_left_sec <= 0.0:
		_visual.scale = Vector2.ONE
		_extra_tilt = 0.0
	_sync_rotation()

func _tick_death(delta: float) -> void:
	if _death_left_sec <= 0.0:
		return
	_death_left_sec = maxf(0.0, _death_left_sec - delta)
	var alpha: float = 1.0 - (_death_left_sec / DEATH_POSE_SEC)
	_visual.scale = _death_from_scale.lerp(_death_to_scale, alpha)
	_extra_tilt = lerpf(_death_from_tilt, _death_to_tilt, alpha)
	if _death_left_sec <= 0.0:
		_visual.scale = _death_to_scale
		_extra_tilt = _death_to_tilt
	_sync_rotation()

func _squash_scale_for(direction: Vector2) -> Vector2:
	var local_hit: Vector2 = direction.rotated(-_base_rotation)
	if absf(local_hit.x) >= absf(local_hit.y):
		return Vector2(SQUASH_ALONG, STRETCH_ACROSS)
	return Vector2(STRETCH_ACROSS, SQUASH_ALONG)

func _tilt_for(direction: Vector2) -> float:
	return deg_to_rad(TILT_DEG) * _tilt_sign(direction.x, direction.y)

func _tilt_sign(primary: float, fallback: float) -> float:
	if primary > 0.0:
		return 1.0
	if primary < 0.0:
		return -1.0
	if fallback < 0.0:
		return -1.0
	return 1.0

func _normalize_or_right(direction: Vector2) -> Vector2:
	if direction.is_zero_approx():
		return Vector2.RIGHT
	return direction.normalized()

func _sync_rotation() -> void:
	if _visual == null:
		return
	_visual.rotation = _base_rotation + _extra_tilt
