extends Node
class_name Pistol

## 射速间隔，秒。用时间戳开火，不用 Timer 节点。
@export var fire_interval: float = 0.18
## 弹速，像素/秒。
@export var projectile_speed: float = 980.0
## 单发伤害。准、快、伤害低。
@export var damage: int = 8
## 子弹存活秒数。
@export var lifetime: float = 0.9

var _player_input: PlayerInput
var _pool: ProjectilePool
var _player: Player
var _next_fire_at_msec: int = 0
var _shot_refused_count: int = 0

func _ready() -> void:
	_player = get_parent() as Player

func bind_player_input(player_input: PlayerInput) -> void:
	_player_input = player_input

func bind_projectile_pool(pool: ProjectilePool) -> void:
	_pool = pool

func get_cooldown_remaining_sec() -> float:
	var remaining_msec: int = maxi(0, _next_fire_at_msec - Time.get_ticks_msec())
	return float(remaining_msec) / 1000.0

func get_refused_count() -> int:
	return _shot_refused_count

func _process(_delta: float) -> void:
	_ensure_player_input()
	_tick_fire()

func _ensure_player_input() -> void:
	if _player_input != null:
		return
	if _player == null:
		_player = get_parent() as Player
	if _player != null:
		bind_player_input(_player.get_player_input())

func _tick_fire() -> void:
	var now_msec: int = Time.get_ticks_msec()
	if _player_input == null or _pool == null or _player == null:
		return
	if not _player_input.fire_held:
		_next_fire_at_msec = mini(_next_fire_at_msec, now_msec)
		return
	if now_msec < _next_fire_at_msec:
		return
	_try_fire()
	_next_fire_at_msec = now_msec + _get_fire_interval_msec()

func _try_fire() -> void:
	var projectile: Projectile = _pool.acquire()
	if projectile == null:
		_shot_refused_count += 1
		return
	var direction: Vector2 = _resolve_aim_direction()
	projectile.reset(
		_player.get_muzzle_global_position(),
		direction * projectile_speed,
		damage,
		lifetime
	)

func _resolve_aim_direction() -> Vector2:
	var aim: Vector2 = _player_input.aim_vector
	if aim.is_zero_approx():
		return Vector2.RIGHT
	return aim.normalized()

func _get_fire_interval_msec() -> int:
	return maxi(1, int(round(fire_interval * 1000.0)))
