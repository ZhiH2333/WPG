extends Camera2D
class_name PlayerCamera

## 沿归一化 aim 前探的像素距离，锁在 80～120。
@export_range(80.0, 120.0, 1.0) var look_ahead: float = 100.0
## 越大越跟手。必须吃 delta：alpha = 1 - exp(-follow_smoothing * delta)。
@export var follow_smoothing: float = 8.0
## 方向踢的最大长度，像素。步枪连发靠这个钳住，禁止镜头飞走。
@export var shake_max: float = 12.0
## 震动衰减，像素/秒。必须吃 delta。
@export var shake_decay: float = 90.0

var _player: Player
var _shake_offset: Vector2 = Vector2.ZERO

func _ready() -> void:
	enabled = true
	ignore_rotation = true
	rotation = 0.0
	zoom = Vector2.ONE
	position_smoothing_enabled = false
	rotation_smoothing_enabled = false
	drag_horizontal_enabled = false
	drag_vertical_enabled = false
	make_current()

func bind_player(player: Player) -> void:
	_player = player
	if _player == null:
		return
	global_position = get_look_target()

func get_look_target() -> Vector2:
	if _player == null:
		return global_position
	return _player.global_position + get_camera_offset()

func get_camera_offset() -> Vector2:
	if _player == null:
		return Vector2.ZERO
	return _player.get_player_input().aim_vector * clampf(look_ahead, 80.0, 120.0)

func get_shake_offset() -> Vector2:
	return _shake_offset

func apply_kick(direction: Vector2, amplitude: float) -> void:
	var dir: Vector2 = direction
	if dir.is_zero_approx():
		dir = Vector2.RIGHT
	else:
		dir = dir.normalized()
	_shake_offset += dir * amplitude
	var length: float = _shake_offset.length()
	if length > shake_max:
		_shake_offset *= shake_max / length

func _process(delta: float) -> void:
	_follow_look_target(delta)

func _follow_look_target(delta: float) -> void:
	if _player == null:
		return
	var look_target: Vector2 = get_look_target()
	var alpha: float = 1.0 - exp(-follow_smoothing * delta)
	global_position = global_position.lerp(look_target, alpha)
	_shake_offset = _shake_offset.move_toward(Vector2.ZERO, shake_decay * delta)
	global_position += _shake_offset
