extends ColorRect
class_name Divider

func _ready() -> void:
	color = UiTokens.LINE
	custom_minimum_size = Vector2(0, 1)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
