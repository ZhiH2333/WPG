extends Node2D
class_name AimReticle

## 世界准星：钉在鼠标世界坐标，不是屏幕 HUD。
var _player_input: PlayerInput

func bind_player_input(player_input: PlayerInput) -> void:
	_player_input = player_input
	_follow_mouse()

func _process(_delta: float) -> void:
	_follow_mouse()

func _follow_mouse() -> void:
	if _player_input == null:
		return
	global_position = _player_input.mouse_world_position
