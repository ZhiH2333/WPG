extends Button
class_name ActionRow

func _ready() -> void:
	theme_type_variation = &"ActionRow"
	alignment = HORIZONTAL_ALIGNMENT_LEFT
	focus_mode = Control.FOCUS_ALL
