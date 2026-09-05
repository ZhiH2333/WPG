extends Area2D
class_name Projectile

## 地板 ±800×±450，出界再给 80px 余量，避免擦边瞬消失。
const WORLD_BOUNDS := Rect2(Vector2(-880.0, -530.0), Vector2(1760.0, 1060.0))

var _pool: ProjectilePool
var _in_flight: bool = false
var _velocity: Vector2 = Vector2.ZERO
var _damage: int = 0
var _lifetime_sec: float = 0.9
var _age_sec: float = 0.0
var _last_global_position: Vector2 = Vector2.ZERO

@onready var _visual: Node2D = $Visual

func _ready() -> void:
	collision_layer = GameCollisionLayers.MASK_PLAYER_BULLET
	collision_mask = GameCollisionLayers.MASK_ENEMY | GameCollisionLayers.MASK_WALL
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)
	park()

func bind_pool(pool: ProjectilePool) -> void:
	_pool = pool

func is_parked() -> bool:
	return not _in_flight

func reset(spawn_position: Vector2, flight_velocity: Vector2, damage: int, lifetime_sec: float, visual_scale: float = 1.0) -> void:
	_in_flight = true
	_damage = damage
	_lifetime_sec = lifetime_sec
	_age_sec = 0.0
	_velocity = flight_velocity
	global_position = spawn_position
	_last_global_position = spawn_position
	rotation = flight_velocity.angle()
	_visual.scale = Vector2.ONE * visual_scale
	visible = true
	monitorable = true
	monitoring = true
	set_physics_process(true)

func park() -> void:
	_in_flight = false
	_velocity = Vector2.ZERO
	_age_sec = 0.0
	if _visual != null:
		_visual.scale = Vector2.ONE
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
	var dummy: DummyTarget = hit as DummyTarget
	if dummy != null:
		dummy.apply_damage(_damage, global_position)
	_request_release()

func _request_release() -> void:
	if not _in_flight or _pool == null:
		return
	_in_flight = false
	_velocity = Vector2.ZERO
	set_physics_process(false)
	visible = false
	set_deferred("monitoring", false)
	_pool.call_deferred("release", self)
