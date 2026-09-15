extends Node2D
class_name DeathShard

## 敌人死亡额外碎块：三角片沿飞出方向平移并自旋，0.28s 淡出后回池。不碰撞。
const LIFE_SEC: float = 0.28
const FLY_SPEED: float = 220.0
const SPIN_RAD_PER_SEC: float = 12.0
const SHARD_COLOR := Color(0.62, 0.46, 0.34, 1)

var _pool: DeathShardPool
var _age_sec: float = 0.0
var _fly_dir: Vector2 = Vector2.RIGHT
var _spin_sign: float = 1.0

@onready var _visual: Polygon2D = $Visual

func _ready() -> void:
	if _visual != null:
		_visual.color = SHARD_COLOR
	park()

func bind_pool(pool: DeathShardPool) -> void:
	_pool = pool

func play(world_position: Vector2, fly_direction: Vector2) -> void:
	global_position = world_position
	if fly_direction.is_zero_approx():
		_fly_dir = Vector2.RIGHT
	else:
		_fly_dir = fly_direction.normalized()
	rotation = _fly_dir.angle()
	_spin_sign = 1.0 if _fly_dir.x >= 0.0 else -1.0
	_age_sec = 0.0
	modulate = Color(1, 1, 1, 1)
	scale = Vector2.ONE
	visible = true
	set_process(true)

func park() -> void:
	_age_sec = 0.0
	_fly_dir = Vector2.RIGHT
	visible = false
	modulate = Color(1, 1, 1, 1)
	scale = Vector2.ONE
	rotation = 0.0
	set_process(false)

func _process(delta: float) -> void:
	_age_sec += delta
	global_position += _fly_dir * FLY_SPEED * delta
	rotation += _spin_sign * SPIN_RAD_PER_SEC * delta
	var t: float = clampf(_age_sec / LIFE_SEC, 0.0, 1.0)
	modulate.a = 1.0 - t
	if _age_sec >= LIFE_SEC:
		_request_release()

func _request_release() -> void:
	if _pool != null:
		_pool.release(self)
		return
	park()
