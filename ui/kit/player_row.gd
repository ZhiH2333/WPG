extends Button
class_name PlayerRow

func _ready() -> void:
	theme_type_variation = &"PlayerRow"
	alignment = HORIZONTAL_ALIGNMENT_LEFT
	focus_mode = Control.FOCUS_ALL
