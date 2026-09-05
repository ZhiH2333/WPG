extends Area2D
class_name Projectile

## 地板 ±800×±450，出界再给 80px 余量，避免擦边瞬消失。
const WORLD_BOUNDS := Rect2(Vector2(-880.0, -530.0), Vector2(1760.0, 1060.0))
const PLAYER_COLOR := Color(1, 0.92, 0.45, 1)
const ENEMY_COLOR := Color(0.78, 0.12, 0.16, 1)

var _pool: ProjectilePool
var _in_flight: bool = false
var _is_player_shot: bool = true
var _velocity: Vector2 = Vector2.ZERO
var _damage: int = 0
var _lifetime_sec: float = 0.9
var _age_sec: float = 0.0
var _last_global_position: Vector2 = Vector2.ZERO

@onready var _visual: Polygon2D = $Visual
@onready var _collision: CollisionShape2D = $CollisionShape2D

func _ready() -> void:
	_apply_faction_collision()
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)
	park()

func bind_pool(pool: ProjectilePool) -> void:
	_pool = pool

func is_parked() -> bool:
	return not _in_flight

func reset(spawn_position: Vector2, flight_velocity: Vector2, damage: int, lifetime_sec: float, visual_scale: float = 1.0, is_player_shot: bool = true) -> void:
	_in_flight = true
	_is_player_shot = is_player_shot
	_damage = damage
	_lifetime_sec = lifetime_sec
	_age_sec = 0.0
	_velocity = flight_velocity
	global_position = spawn_position
	_last_global_position = spawn_position
	rotation = flight_velocity.angle()
	_apply_faction_collision()
	_apply_faction_visual(visual_scale)
	visible = true
	monitorable = true
	monitoring = true
	set_physics_process(true)

func park() -> void:
	_in_flight = false
	_velocity = Vector2.ZERO
	_age_sec = 0.0
	_is_player_shot = true
	_reset_visual()
	visible = false
	monitoring = false
	monitorable = false
	set_physics_process(false)

func _physics_process(delta: float) -> void:
	if not _in_flight:
		return
	_last_global_position = global_position
	global_position += _velocity * delta
	_age_sec += delta
	if _age_sec >= _lifetime_sec:
		_request_release()
		return
	if not WORLD_BOUNDS.has_point(global_position):
		_request_release()

func _on_body_entered(body: Node) -> void:
	_handle_hit(body)

func _on_area_entered(area: Area2D) -> void:
	_handle_hit(area)

func _handle_hit(hit: Node) -> void:
	if not _in_flight:
		return
	global_position = _last_global_position
	_apply_hit_damage(hit)
	_request_release()

func _apply_hit_damage(hit: Node) -> void:
	if _is_player_shot:
		_damage_enemy_side(hit)
		return
	_damage_player_side(hit)

func _damage_enemy_side(hit: Node) -> void:
	var direction: Vector2 = _hit_direction()
	var enemy: EnemyBase = hit as EnemyBase
	if enemy != null:
		enemy.apply_damage(_damage, global_position, direction)
		return
	var dummy: DummyTarget = hit as DummyTarget
	if dummy != null:
		dummy.apply_damage(_damage, global_position, direction)

func _damage_player_side(hit: Node) -> void:
	var player: Player = hit as Player
	if player == null:
		return
	player.get_player_health().apply_damage(_damage, global_position, _hit_direction())

func _hit_direction() -> Vector2:
	if _velocity.is_zero_approx():
		return Vector2.ZERO
	return _velocity.normalized()

func _apply_faction_collision() -> void:
	if _is_player_shot:
		collision_layer = GameCollisionLayers.MASK_PLAYER_BULLET
		collision_mask = GameCollisionLayers.MASK_ENEMY | GameCollisionLayers.MASK_WALL
		return
	collision_layer = GameCollisionLayers.MASK_ENEMY_BULLET
	collision_mask = GameCollisionLayers.MASK_PLAYER | GameCollisionLayers.MASK_WALL

func _apply_faction_visual(visual_scale: float) -> void:
	if _visual == null:
		return
	_visual.scale = Vector2.ONE * visual_scale
	if _is_player_shot:
		_visual.color = PLAYER_COLOR
	else:
		_visual.color = ENEMY_COLOR
	if _collision != null:
		_collision.scale = Vector2.ONE * visual_scale

func _reset_visual() -> void:
	if _visual != null:
		_visual.scale = Vector2.ONE
		_visual.color = PLAYER_COLOR
	if _collision != null:
		_collision.scale = Vector2.ONE

func _request_release() -> void:
	if not _in_flight or _pool == null:
		return
	_in_flight = false
	_velocity = Vector2.ZERO
	set_physics_process(false)
	visible = false
	set_deferred("monitoring", false)
	_pool.call_deferred("release", self)
