extends Button
class_name CharacterChoice

var chosen: bool = false

func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	_apply_choice()

func set_chosen(is_chosen: bool) -> void:
	chosen = is_chosen
	_apply_choice()

func _apply_choice() -> void:
	theme_type_variation = &"SelectedRow" if chosen else &"CharacterChoice"
