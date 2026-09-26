extends Label
class_name StatusText

func _ready() -> void:
	theme_type_variation = &"Body"
	autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func show_status(message: String, kind: StringName = &"body") -> void:
	text = message
	match kind:
		&"success", &"ready", &"connected":
			theme_type_variation = &"StatusSuccess"
		&"warning", &"connecting", &"authenticating":
			theme_type_variation = &"StatusWarning"
		&"error", &"failed", &"host_closed", &"version_mismatch":
			theme_type_variation = &"StatusError"
		_:
			theme_type_variation = &"Body"
