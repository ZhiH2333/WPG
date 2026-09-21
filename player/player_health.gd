extends Node
class_name PlayerHealth

## 玩家生命与无敌帧。HP 不写进 Player 上帝对象。受击：闪白 + 数字 + 轻击退 + 轻 squash；无 hitstop。
const FLASH_DURATION_SEC: float = 0.1
const DEAD_COLOR: Color = Color(0.42, 0.42, 0.44, 1)

@export var max_hp: int = 100
@export var i_frame_sec: float = 0.45

var _hp: int = 100
var _defeated: bool = false
var _i_frame_left_sec: float = 0.0
var _flash_left_sec: float = 0.0
var _debug_god: bool = false

@onready var _player: Player = get_parent() as Player
@onready var _visual: Node2D = get_parent().get_node("Visual") as Node2D

func _ready() -> void:
	_hp = max_hp

func get_hp() -> int:
	return _hp

func get_max_hp() -> int:
	return max_hp

func set_full_max_hp(new_max: int) -> void:
	max_hp = maxi(1, new_max)
	if _defeated:
		return
	_hp = max_hp

func fill_hp() -> void:
	if _defeated:
		return
	_hp = max_hp

func heal(amount: int) -> int:
	if _defeated or amount <= 0:
		return 0
	var before: int = _hp
	_hp = mini(max_hp, _hp + amount)
	return _hp - before

func apply_bonus_i_frame(sec: float) -> void:
	if _defeated or sec <= 0.0:
		return
	_i_frame_left_sec = maxf(_i_frame_left_sec, sec)

func apply_max_hp(new_max: int) -> void:
	new_max = maxi(1, new_max)
	var delta: int = new_max - max_hp
	max_hp = new_max
	if delta > 0:
		_hp = mini(max_hp, _hp + delta)
		return
	_hp = mini(_hp, max_hp)

func is_defeated() -> bool:
	return _defeated

func is_invincible() -> bool:
	return _i_frame_left_sec > 0.0

func set_debug_god(enabled: bool) -> void:
	_debug_god = enabled

func is_debug_god() -> bool:
	return _debug_god

func reset_for_sandbox() -> void:
	_hp = max_hp
	_defeated = false
	_i_frame_left_sec = 0.0
	_flash_left_sec = 0.0
	if _visual == null:
		return
	_visual.modulate = Color.WHITE

func apply_net_state(hp: int, new_max_hp: int, defeated: bool) -> void:
	max_hp = maxi(1, new_max_hp)
	var was_defeated: bool = _defeated
	var old_hp: int = _hp
	_hp = clampi(hp, 0, max_hp)
	if defeated:
		_hp = 0
		if not was_defeated:
			_defeat()
		return
	_defeated = false
	if old_hp > _hp:
		_start_flash()
	if _visual != null and not _player.is_dashing():
		_visual.modulate = Color.WHITE

func apply_damage(amount: int, hit_position: Vector2, hit_direction: Vector2 = Vector2.ZERO) -> void:
	if _defeated or _i_frame_left_sec > 0.0 or amount <= 0 or _debug_god or _player.is_dashing():
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
	if _player != null and _player.is_dashing():
		return
	if _defeated:
		_visual.modulate = DEAD_COLOR
		return
	_visual.modulate = Color.WHITE

func _defeat() -> void:
	_defeated = true
	_i_frame_left_sec = 0.0
	if _player != null:
		_player.begin_death_pose()
		_player.on_defeated()
	if _visual != null:
		_visual.modulate = DEAD_COLOR

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
	DamageNumber.spawn(self, amount, hit_position)
