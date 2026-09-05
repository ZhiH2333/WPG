extends Camera2D
class_name PlayerCamera

## 沿归一化 aim 前探的像素距离，锁在 80～120。
@export_range(80.0, 120.0, 1.0) var look_ahead: float = 100.0
## 越大越跟手。必须吃 delta：alpha = 1 - exp(-follow_smoothing * delta)。
@export var follow_smoothing: float = 8.0

var _player: Player

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

func _process(delta: float) -> void:
	_follow_look_target(delta)

func _follow_look_target(delta: float) -> void:
	if _player == null:
		return
	var look_target: Vector2 = get_look_target()
	var alpha: float = 1.0 - exp(-follow_smoothing * delta)
	global_position = global_position.lerp(look_target, alpha)
