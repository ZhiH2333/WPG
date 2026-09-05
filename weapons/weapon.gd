extends Node
class_name Weapon

## 射速间隔，秒。用时间戳开火，不用 Timer 节点。
@export var fire_interval: float = 0.18
## 弹速，像素/秒。
@export var projectile_speed: float = 980.0
## 单发（或每粒）伤害。
@export var damage: int = 8
## 子弹存活秒数。
@export var lifetime: float = 0.9

var _player_input: PlayerInput
var _pool: ProjectilePool
var _player: Player
var _next_fire_at_msec: int = 0
var _shot_refused_count: int = 0
var _is_active: bool = false
## 切枪后必须先松开火，避免按住左键走火。
var _block_held_fire: bool = false

func _ready() -> void:
	_player = _find_player()
	set_process(false)

func bind_player_input(player_input: PlayerInput) -> void:
	_player_input = player_input

func bind_projectile_pool(pool: ProjectilePool) -> void:
	_pool = pool

func get_display_name() -> String:
	return "Weapon"

func get_cooldown_remaining_sec() -> float:
	var remaining_msec: int = maxi(0, _next_fire_at_msec - Time.get_ticks_msec())
	return float(remaining_msec) / 1000.0

func get_refused_count() -> int:
	return _shot_refused_count

func get_current_spread_deg() -> float:
	return _spread_deg_for_this_shot()

func get_pellets_per_shot() -> int:
	return _pellets_per_shot()

func is_active() -> bool:
	return _is_active

func set_active(active: bool) -> void:
	_is_active = active
	set_process(active)
	if active:
		_block_held_fire = true
		return
	_on_deactivated()

func _process(delta: float) -> void:
	_ensure_bindings()
	_tick_idle(delta)
	_tick_fire()

func _ensure_bindings() -> void:
	if _player == null:
		_player = _find_player()
	if _player_input == null and _player != null:
		bind_player_input(_player.get_player_input())

func _tick_idle(_delta: float) -> void:
	pass

func _tick_fire() -> void:
	var now_msec: int = Time.get_ticks_msec()
	if _player_input == null or _pool == null or _player == null:
		return
	if not _player_input.fire_held:
		_block_held_fire = false
		_on_fire_released(now_msec)
		return
	if _block_held_fire:
		return
	if now_msec < _next_fire_at_msec:
		return
	if _try_fire():
		_on_shot_success()
	_next_fire_at_msec = now_msec + _get_fire_interval_msec()

func _on_fire_released(now_msec: int) -> void:
	if _should_reset_cooldown_on_release():
		_next_fire_at_msec = mini(_next_fire_at_msec, now_msec)

func _try_fire() -> bool:
	var pellet_count: int = _pellets_per_shot()
	var acquired: Array[Projectile] = []
	if not _acquire_pellets(pellet_count, acquired):
		_shot_refused_count += 1
		return false
	var aim: Vector2 = _resolve_aim_direction()
	var muzzle: Vector2 = _player.get_muzzle_global_position()
	var visual_scale: float = _pellet_visual_scale()
	for index: int in pellet_count:
		var direction: Vector2 = _direction_for_pellet(aim, index, pellet_count)
		acquired[index].reset(muzzle, direction * projectile_speed, damage, lifetime, visual_scale)
	return true

func _acquire_pellets(pellet_count: int, acquired: Array[Projectile]) -> bool:
	for _i: int in pellet_count:
		var projectile: Projectile = _pool.acquire()
		if projectile == null:
			_release_acquired(acquired)
			return false
		acquired.append(projectile)
	return true

func _release_acquired(acquired: Array[Projectile]) -> void:
	for projectile: Projectile in acquired:
		_pool.release(projectile)

func _resolve_aim_direction() -> Vector2:
	var aim: Vector2 = _player_input.aim_vector
	if aim.is_zero_approx():
		return Vector2.RIGHT
	return aim.normalized()

func _direction_for_pellet(aim: Vector2, index: int, pellet_count: int) -> Vector2:
	var half_spread: float = _spread_deg_for_this_shot() * 0.5
	var angle_deg: float = 0.0
	if pellet_count > 1:
		angle_deg = lerpf(-half_spread, half_spread, float(index) / float(pellet_count - 1))
	angle_deg += _pellet_jitter_deg()
	return aim.rotated(deg_to_rad(angle_deg))

func _should_reset_cooldown_on_release() -> bool:
	return true

func _pellets_per_shot() -> int:
	return 1

func _spread_deg_for_this_shot() -> float:
	return 0.0

func _pellet_jitter_deg() -> float:
	return 0.0

func _pellet_visual_scale() -> float:
	return 1.0

func _on_shot_success() -> void:
	pass

func _on_deactivated() -> void:
	_block_held_fire = false

func _get_fire_interval_msec() -> int:
	return maxi(1, int(round(fire_interval * 1000.0)))

func _find_player() -> Player:
	var node: Node = get_parent()
	while node != null:
		var player: Player = node as Player
		if player != null:
			return player
		node = node.get_parent()
	return null
