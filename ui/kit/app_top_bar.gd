extends HBoxContainer
class_name AppTopBar

func _ready() -> void:
	custom_minimum_size = Vector2(0, UiTokens.TOP_BAR_HEIGHT)
	add_theme_constant_override("separation", UiTokens.SPACE_LG)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
