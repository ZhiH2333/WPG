extends CharacterBody2D
class_name EnemyBase

## 廉价 seek 移动 + 受击链（闪白 / 击退 / squash / 局部 hitstop / 死亡塌缩）。
## 禁止 NavigationAgent、每帧 group 扫描、queue_redraw、Engine.time_scale。
const DAMAGE_NUMBER_SCENE: PackedScene = preload("res://combat/damage_number.tscn")
const FLASH_DURATION_SEC: float = 0.1
const DEAD_COLOR: Color = Color(0.42, 0.42, 0.44, 1)
const DEATH_SLIDE_STOP_SPEED: float = 12.0

@export var max_hp: int = 36
@export var move_speed: float = 175.0
@export var acceleration: float = 1400.0
@export var knockback_impulse: float = 260.0
@export var knockback_max_speed: float = 420.0
@export var knockback_damping: float = 1800.0
@export var hitstop_sec: float = 0.012

var _hp: int = 36
var _defeated: bool = false
var _flash_left_sec: float = 0.0
var _player: Player
var _knockback_velocity: Vector2 = Vector2.ZERO
var _hitstop_left_sec: float = 0.0
var _was_in_hitstop: bool = false
var _hit_reaction: HitReaction

@onready var _visual: Polygon2D = $Visual

func _ready() -> void:
	motion_mode = MOTION_MODE_FLOATING
	collision_layer = GameCollisionLayers.MASK_ENEMY
	collision_mask = GameCollisionLayers.MASK_WALL
	_hp = max_hp
	_bind_hit_reaction()

func bind_player(player: Player) -> void:
	_player = player

func get_hp() -> int:
	return _hp

func is_defeated() -> bool:
	return _defeated

func is_in_hitstop() -> bool:
	return _hitstop_left_sec > 0.0

func get_hitstop_left_sec() -> float:
	return _hitstop_left_sec

func get_knockback_speed() -> float:
	return _knockback_velocity.length()

func get_kind_name() -> String:
	return "Enemy"

func apply_damage(amount: int, hit_position: Vector2, hit_direction: Vector2 = Vector2.ZERO) -> void:
	if _defeated or amount <= 0:
		return
	var direction: Vector2 = _resolve_hit_direction(hit_direction)
	_hp = maxi(0, _hp - amount)
	_spawn_damage_number(amount, hit_position)
	_start_flash()
	_apply_knockback(direction)
	_start_hitstop()
	_hit_reaction.play(direction)
	if _hp <= 0:
		_defeat()

func _physics_process(delta: float) -> void:
	if _defeated:
		_tick_death_slide(delta)
		return
	if _hitstop_left_sec > 0.0:
		_hitstop_left_sec = maxf(0.0, _hitstop_left_sec - delta)
		_was_in_hitstop = true
		return
	_apply_post_hitstop_velocity()
	_tick_ai(delta)
	_knockback_velocity = _knockback_velocity.move_toward(Vector2.ZERO, knockback_damping * delta)
	move_and_slide()
	_face_player()

func _process(delta: float) -> void:
	_tick_flash(delta)

func _tick_ai(_delta: float) -> void:
	pass

func _steer_toward(delta: float, desired_velocity: Vector2) -> void:
	velocity = velocity.move_toward(desired_velocity, acceleration * delta)

func _desired_velocity_to_player() -> Vector2:
	var to_player: Vector2 = _to_player()
	if to_player.is_zero_approx():
		return Vector2.ZERO
	return to_player.normalized() * move_speed

func _player_alive() -> bool:
	return _player != null and not _player.is_defeated()

func _to_player() -> Vector2:
	if _player == null:
		return Vector2.ZERO
	return _player.global_position - global_position

func _face_player() -> void:
	var to_player: Vector2 = _to_player()
	if to_player.is_zero_approx():
		return
	_hit_reaction.apply_facing(to_player.angle())

func _tick_flash(delta: float) -> void:
	if _flash_left_sec <= 0.0:
		return
	_flash_left_sec -= delta
	if _flash_left_sec <= 0.0:
		_restore_color()

func _start_flash() -> void:
	_flash_left_sec = FLASH_DURATION_SEC
	_visual.modulate = Color(2.2, 2.2, 2.2, 1)

func _restore_color() -> void:
	_visual.modulate = Color.WHITE
	if _defeated:
		_visual.color = DEAD_COLOR

func _defeat() -> void:
	_defeated = true
	collision_layer = GameCollisionLayers.MASK_NONE
	collision_mask = GameCollisionLayers.MASK_NONE
	_visual.color = DEAD_COLOR
	_visual.modulate = Color.WHITE
	_hit_reaction.begin_death(true)
	_on_defeated()

func _on_defeated() -> void:
	pass

func _spawn_damage_number(amount: int, hit_position: Vector2) -> void:
	var number: DamageNumber = DAMAGE_NUMBER_SCENE.instantiate() as DamageNumber
	var host: Node = owner
	if host == null:
		host = get_parent()
	host.add_child(number)
	number.play(amount, hit_position)

func _bind_hit_reaction() -> void:
	_hit_reaction = HitReaction.new()
	_hit_reaction.name = "HitReaction"
	add_child(_hit_reaction)
	_hit_reaction.bind_visual(_visual)

func _resolve_hit_direction(hit_direction: Vector2) -> Vector2:
	if not hit_direction.is_zero_approx():
		return hit_direction.normalized()
	var away: Vector2 = -_to_player()
	if away.is_zero_approx():
		return Vector2.RIGHT
	return away.normalized()

func _apply_knockback(direction: Vector2) -> void:
	_knockback_velocity += direction * knockback_impulse
	var speed: float = _knockback_velocity.length()
	if speed > knockback_max_speed:
		_knockback_velocity = _knockback_velocity * (knockback_max_speed / speed)

func _start_hitstop() -> void:
	_hitstop_left_sec = maxf(_hitstop_left_sec, hitstop_sec)

func _apply_post_hitstop_velocity() -> void:
	if not _was_in_hitstop:
		return
	velocity = _knockback_velocity
	_was_in_hitstop = false

func _tick_death_slide(delta: float) -> void:
	if _hitstop_left_sec > 0.0:
		_hitstop_left_sec = maxf(0.0, _hitstop_left_sec - delta)
		_was_in_hitstop = true
		return
	_apply_post_hitstop_velocity()
	_knockback_velocity = _knockback_velocity.move_toward(Vector2.ZERO, knockback_damping * delta)
	if _knockback_velocity.length() < DEATH_SLIDE_STOP_SPEED:
		velocity = Vector2.ZERO
		_knockback_velocity = Vector2.ZERO
		set_physics_process(false)
		return
	velocity = _knockback_velocity
	move_and_slide()
