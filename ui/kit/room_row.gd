extends Button
class_name RoomRow

func _ready() -> void:
	theme_type_variation = &"RoomRow"
	alignment = HORIZONTAL_ALIGNMENT_LEFT
	focus_mode = Control.FOCUS_ALL
