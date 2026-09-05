extends CanvasLayer
class_name DebugOverlay

var _player_input: PlayerInput

@onready var _label: Label = $Label

func bind_player_input(player_input: PlayerInput) -> void:
	_player_input = player_input

func _process(_delta: float) -> void:
	_refresh_label()

func _refresh_label() -> void:
	if _player_input == null:
		_label.text = "PlayerInput 未绑定"
		return
	_label.text = _compose_status_text()

func _compose_status_text() -> String:
	var fps: int = Engine.get_frames_per_second()
	return "move_vector: %s\naim_vector: %s\nfire_held: %s\nmouse_world: %s\nFPS: %d" % [
		_format_vector(_player_input.move_vector),
		_format_vector(_player_input.aim_vector),
		_player_input.fire_held,
		_format_vector(_player_input.mouse_world_position),
		fps,
	]

func _format_vector(value: Vector2) -> String:
	return "(%.2f, %.2f)" % [value.x, value.y]
