extends HBoxContainer
class_name PlayerIdentity

@export var display_name: String = "Player"

func _ready() -> void:
	add_theme_constant_override("separation", UiTokens.SPACE_MD)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if get_child_count() > 0:
		return
	var name_label: Label = Label.new()
	name_label.theme_type_variation = &"PlayerName"
	name_label.text = display_name
	name_label.clip_text = true
	name_label.custom_minimum_size = Vector2(160, 0)
	add_child(name_label)
