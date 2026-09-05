extends Node
class_name PlayerHealth

## 玩家生命与无敌帧。HP 不写进 Player 上帝对象。受击：闪白 + 数字 + 轻击退 + 轻 squash；无 hitstop。
const DAMAGE_NUMBER_SCENE: PackedScene = preload("res://combat/damage_number.tscn")
const FLASH_DURATION_SEC: float = 0.1
const DEAD_COLOR: Color = Color(0.42, 0.42, 0.44, 1)

@export var max_hp: int = 100
@export var i_frame_sec: float = 0.45

var _hp: int = 100
var _defeated: bool = false
var _i_frame_left_sec: float = 0.0
var _flash_left_sec: float = 0.0
var _alive_color: Color = Color(1, 0.62, 0.18, 1)

@onready var _player: Player = get_parent() as Player
@onready var _visual: Polygon2D = get_parent().get_node("Visual") as Polygon2D

func _ready() -> void:
	_hp = max_hp
	if _visual != null:
		_alive_color = _visual.color

func get_hp() -> int:
	return _hp

func get_max_hp() -> int:
	return max_hp

func is_defeated() -> bool:
	return _defeated

func is_invincible() -> bool:
	return _i_frame_left_sec > 0.0

func reset_for_sandbox() -> void:
	_hp = max_hp
	_defeated = false
	_i_frame_left_sec = 0.0
	_flash_left_sec = 0.0
	if _visual == null:
		return
	_visual.color = _alive_color
	_visual.modulate = Color.WHITE

func apply_damage(amount: int, hit_position: Vector2, hit_direction: Vector2 = Vector2.ZERO) -> void:
	if _defeated or _i_frame_left_sec > 0.0 or amount <= 0:
		return
	var direction: Vector2 = _resolve_hit_direction(hit_direction, hit_position)
	_hp = maxi(0, _hp - amount)
	_spawn_damage_number(amount, hit_position)
	_start_flash()
	_i_frame_left_sec = i_frame_sec
	_player.notify_hurt(direction)
	if _hp <= 0:
		_defeat()
		return
	_player.apply_hit_knockback(direction)
	_player.play_hit_reaction(direction)

func _process(delta: float) -> void:
	_tick_i_frame(delta)
	_tick_flash(delta)

func _tick_i_frame(delta: float) -> void:
	if _i_frame_left_sec <= 0.0:
		return
	_i_frame_left_sec = maxf(0.0, _i_frame_left_sec - delta)

func _tick_flash(delta: float) -> void:
	if _flash_left_sec <= 0.0:
		return
	_flash_left_sec -= delta
	if _flash_left_sec <= 0.0:
		_restore_color()

func _start_flash() -> void:
	if _visual == null:
		return
	_flash_left_sec = FLASH_DURATION_SEC
	_visual.modulate = Color(2.2, 2.2, 2.2, 1)

func _restore_color() -> void:
	if _visual == null:
		return
	_visual.modulate = Color.WHITE
	if _defeated:
		_visual.color = DEAD_COLOR
		return
	_visual.color = _alive_color

func _defeat() -> void:
	_defeated = true
	_i_frame_left_sec = 0.0
	if _visual != null:
		_visual.color = DEAD_COLOR
		_visual.modulate = Color.WHITE
	if _player != null:
		_player.begin_death_pose()
		_player.on_defeated()

func _resolve_hit_direction(hit_direction: Vector2, hit_position: Vector2) -> Vector2:
	if not hit_direction.is_zero_approx():
		return hit_direction.normalized()
	if _player == null:
		return Vector2.RIGHT
	var away: Vector2 = _player.global_position - hit_position
	if away.is_zero_approx():
		return Vector2.RIGHT
	return away.normalized()

func _spawn_damage_number(amount: int, hit_position: Vector2) -> void:
	var number: DamageNumber = DAMAGE_NUMBER_SCENE.instantiate() as DamageNumber
	var host: Node = owner
	if host == null:
		host = get_parent()
	host.add_child(number)
	number.play(amount, hit_position)
