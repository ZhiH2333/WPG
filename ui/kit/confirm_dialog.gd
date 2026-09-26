extends PanelContainer
class_name ConfirmDialog

signal confirmed
signal cancelled

func _ready() -> void:
	theme_type_variation = &"Modal"
	mouse_filter = Control.MOUSE_FILTER_STOP
