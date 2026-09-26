extends Control
class_name UiGallery

## UI 2.0 回归面。不进主菜单。18 个画面，Idle / Focus / 关键状态，三个视口。
const SCREENS: PackedStringArray = [
	"Main Menu", "Play", "Profile", "Settings", "Record Selector",
	"Multiplayer Home", "Create Room", "Join Room", "Lobby", "Connecting",
	"Error", "Pause", "Winner", "Loading", "HUD", "Shop", "Upgrade", "Credits",
]
const STATES: PackedStringArray = ["Idle", "Focus", "State"]
const VIEWPORTS: Array[Vector2] = [Vector2(1920, 1080), Vector2(1600, 900), Vector2(1280, 720)]

var _screen_index: int = 0
var _state_index: int = 0
var _viewport_index: int = 0
var _stage: Control
var _readout: Label

func _ready() -> void:
	theme = load("res://ui/game_theme.tres")
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var backdrop: ColorRect = ColorRect.new()
	backdrop.color = UiTokens.BACKGROUND
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)
	var column: VBoxContainer = VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	column.offset_left = 24
	column.offset_top = 16
	column.offset_right = -24
	column.offset_bottom = -16
	column.add_theme_constant_override("separation", 12)
	add_child(column)
	_readout = Label.new()
	_readout.theme_type_variation = &"Caption"
	column.add_child(_readout)
	var screen_row: HBoxContainer = HBoxContainer.new()
	screen_row.add_theme_constant_override("separation", 8)
	column.add_child(screen_row)
	for index: int in SCREENS.size():
		var button: Button = Button.new()
		button.text = SCREENS[index]
		button.theme_type_variation = &"TextAction"
		button.pressed.connect(_select_screen.bind(index))
		screen_row.add_child(button)
	var state_row: HBoxContainer = HBoxContainer.new()
	state_row.add_theme_constant_override("separation", 8)
	column.add_child(state_row)
	for index: int in STATES.size():
		var button: Button = Button.new()
		button.text = STATES[index]
		button.theme_type_variation = &"SecondaryAction"
		button.pressed.connect(_select_state.bind(index))
		state_row.add_child(button)
	for index: int in VIEWPORTS.size():
		var button: Button = Button.new()
		var size: Vector2 = VIEWPORTS[index]
		button.text = "%d×%d" % [int(size.x), int(size.y)]
		button.theme_type_variation = &"TextAction"
		button.pressed.connect(_select_viewport.bind(index))
		state_row.add_child(button)
	_stage = Control.new()
	_stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(_stage)
	_rebuild()

func run_probe() -> PackedStringArray:
	var failures: PackedStringArray = PackedStringArray()
	for screen_index: int in SCREENS.size():
		for state_index: int in STATES.size():
			for viewport_index: int in VIEWPORTS.size():
				_screen_index = screen_index
				_state_index = state_index
				_viewport_index = viewport_index
				var page: Control = _build_page()
				var size: Vector2 = VIEWPORTS[viewport_index]
				page.custom_minimum_size = size
				var focus: Control = _first_focus(page)
				if state_index == 1 and focus == null:
					failures.append("%s / %s / %s has no focus" % [SCREENS[screen_index], STATES[state_index], _viewport_label()])
				if _overflows(page, size):
					failures.append("%s / %s / %s overflows" % [SCREENS[screen_index], STATES[state_index], _viewport_label()])
				page.free()
	return failures

func _select_screen(index: int) -> void:
	_screen_index = index
	_rebuild()

func _select_state(index: int) -> void:
	_state_index = index
	_rebuild()

func _select_viewport(index: int) -> void:
	_viewport_index = index
	_rebuild()

func _rebuild() -> void:
	for child: Node in _stage.get_children():
		child.queue_free()
	var page: Control = _build_page()
	page.set_anchors_preset(Control.PRESET_FULL_RECT)
	_stage.add_child(page)
	if _state_index == 1:
		var focus: Control = _first_focus(page)
		if focus != null:
			focus.grab_focus()
	_readout.text = "%s  ·  %s  ·  %s" % [SCREENS[_screen_index], STATES[_state_index], _viewport_label()]

func _viewport_label() -> String:
	var size: Vector2 = VIEWPORTS[_viewport_index]
	return "%d×%d" % [int(size.x), int(size.y)]

func _build_page() -> Control:
	var page: Control = Control.new()
	var long_name: bool = _state_index == 2 and (_screen_index == 2 or _screen_index == 8)
	var empty: bool = _state_index == 2 and (_screen_index == 4 or _screen_index == 5 or _screen_index == 6)
	var focused: bool = _state_index == 1
	var box: VBoxContainer = VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 48
	box.offset_top = 24
	box.offset_right = -48
	box.offset_bottom = -24
	box.add_theme_constant_override("separation", 16)
	page.add_child(box)
	match _screen_index:
		0:
			_add_main_menu(box, long_name, empty, focused)
		1:
			_add_play(box, empty, focused)
		2:
			_add_profile(box, long_name, empty, focused)
		3:
			_add_settings(box, focused)
		4:
			_add_records(box, empty, focused)
		5:
			_add_multi_home(box, empty, focused)
		6:
			_add_create(box, focused)
		7:
			_add_join(box, focused)
		8:
			_add_lobby(box, long_name, empty, focused)
		9:
			_add_status_page(box, "Connecting.", &"StatusWarning", focused)
		10:
			_add_status_page(box, _error_copy(), &"StatusError", focused)
		11:
			_add_pause(box, focused)
		12:
			_add_winner(box, empty, focused)
		13:
			_add_loading(box, focused)
		14:
			_add_hud(box, focused)
		15:
			_add_shop(box, focused)
		16:
			_add_shop(box, focused)
		17:
			_add_credits(box, focused)
	return page

func _add_main_menu(box: VBoxContainer, long_name: bool, empty: bool, focused: bool) -> void:
	box.add_child(_nav_bar(focused))
	box.add_child(_label("WPG", &"Display"))
	var name_text: String = "Nightfox With A Very Long Name" if long_name else "Nightfox"
	box.add_child(_label(name_text, &"PlayerName"))
	box.add_child(_label("No recent run." if empty else "Ready to play.", &"Caption"))
	box.add_child(_button("Continue", &"RailTitle", focused and not empty))
	box.add_child(_button("Solo", &"TextAction", focused and empty))
	box.add_child(_button("Multiplayer", &"TextAction", false))

func _add_play(box: VBoxContainer, empty: bool, focused: bool) -> void:
	box.add_child(_label("Play", &"Page"))
	box.add_child(_button("Continue", &"ActionRow", focused and not empty))
	box.add_child(_button("Solo", &"ActionRow", focused and empty))
	box.add_child(_button("Multiplayer", &"ActionRow", false))
	if empty:
		box.add_child(_label("No recent run.", &"Caption"))

func _add_profile(box: VBoxContainer, long_name: bool, empty: bool, focused: bool) -> void:
	box.add_child(_label("Profile", &"Page"))
	box.add_child(_label("Nightfox With A Very Long Name" if long_name else "Nightfox", &"PlayerName"))
	box.add_child(_label("No avatar." if empty else "Boar", &"Caption"))
	box.add_child(_button("Display name", &"InkTextAction", focused))
	box.add_child(_label("STATISTICS", &"Section"))
	box.add_child(_label("Best  24" if not empty else "No runs yet.", &"Body"))
	box.add_child(_label("RECORDS", &"Section"))
	box.add_child(_label("No records." if empty else "Yard  ·  24", &"Caption"))

func _add_settings(box: VBoxContainer, focused: bool) -> void:
	box.add_child(_label("Settings", &"InkPage"))
	box.add_child(_label("Change game settings", &"InkBody"))
	box.add_child(_button("Audio", &"InkNav", focused))
	box.add_child(_button("Display", &"InkNav", false))
	var slider: HSlider = HSlider.new()
	slider.min_value = 0
	slider.max_value = 100
	slider.value = 70
	slider.custom_minimum_size = Vector2(280, 32)
	slider.focus_mode = Control.FOCUS_ALL
	if focused:
		slider.set_meta("gallery_focus", true)
	box.add_child(slider)
	var check: CheckBox = CheckBox.new()
	check.text = "Fullscreen"
	check.focus_mode = Control.FOCUS_ALL
	box.add_child(check)
	box.add_child(_label("Music  70%", &"InkNumeric"))

func _add_records(box: VBoxContainer, empty: bool, focused: bool) -> void:
	box.add_child(_label("Records", &"Page"))
	if empty:
		box.add_child(_label("No records.", &"Caption"))
		box.add_child(_button("New record", &"PrimaryAction", focused))
		return
	box.add_child(_button("Yard  ·  Boar  ·  24", &"RecordRow", focused))
	box.add_child(_button("Pit  ·  Chicken  ·  11", &"RecordRow", false))

func _add_multi_home(box: VBoxContainer, empty: bool, focused: bool) -> void:
	box.add_child(_label("Multiplayer", &"Page"))
	box.add_child(_button("Create Room", &"PrimaryAction", focused))
	box.add_child(_button("Join Room", &"ActionRow", false))
	box.add_child(_button("LAN Rooms", &"ActionRow", false))
	box.add_child(_button("Recent Rooms", &"ActionRow", false))
	box.add_child(_label("No LAN rooms." if empty else "LAN Rooms is a local beacon. Not an internet directory.", &"Caption"))

func _add_create(box: VBoxContainer, focused: bool) -> void:
	box.add_child(_label("Character", &"Page"))
	box.add_child(_button("Boar", &"SelectedRow", true))
	box.add_child(_button("Chicken", &"CharacterChoice", focused))
	box.add_child(_button("Next", &"PrimaryAction", false))

func _add_join(box: VBoxContainer, focused: bool) -> void:
	box.add_child(_label("Join", &"Page"))
	box.add_child(_button("Invite", &"ActionRow", focused))
	box.add_child(_button("Paste", &"ActionRow", false))
	var edit: LineEdit = LineEdit.new()
	edit.placeholder_text = "Address"
	edit.text = "192.168.0.20"
	edit.custom_minimum_size = Vector2(320, 40)
	box.add_child(edit)
	box.add_child(_button("QR", &"ActionRow", false))
	box.add_child(_label("QR and short code arrive with JoinInvite.", &"Caption"))

func _add_lobby(box: VBoxContainer, long_name: bool, full: bool, focused: bool) -> void:
	box.add_child(_label("Lobby", &"Page"))
	box.add_child(_label("PLAYERS", &"Section"))
	var host_name: String = "Nightfox With A Very Long Name" if long_name else "Nightfox"
	box.add_child(_button("%s   Host   Boar   Ready" % host_name, &"PlayerRow", focused))
	if full:
		box.add_child(_label("Room is full. 5/5.", &"StatusWarning"))
	else:
		box.add_child(_button("Empty seat", &"PlayerRow", false))
	box.add_child(_label("ROOM", &"Section"))
	box.add_child(_label("Co-op    Yard    Goal 20", &"Body"))
	box.add_child(_label("192.168.0.12:17777", &"Technical"))
	box.add_child(_button("Start", &"PrimaryAction", false))

func _add_status_page(box: VBoxContainer, message: String, kind: StringName, focused: bool) -> void:
	box.add_child(_label(message, kind))
	box.add_child(_button("Back", &"TextAction", focused))

func _add_pause(box: VBoxContainer, focused: bool) -> void:
	box.add_child(_label("Paused", &"Page"))
	box.add_child(_button("Continue", &"PrimaryAction", focused))
	box.add_child(_button("Retry", &"TextAction", false))
	box.add_child(_button("Quit", &"DangerAction", false))

func _add_winner(box: VBoxContainer, empty: bool, focused: bool) -> void:
	box.add_child(_label("Cleared", &"Page"))
	box.add_child(_label("0" if empty else "24", &"Numeric"))
	box.add_child(_label("No previous best." if empty else "Best  18", &"Caption"))
	box.add_child(_button("Menu", &"PrimaryAction", focused))

func _add_loading(box: VBoxContainer, focused: bool) -> void:
	box.add_child(_label("WPG", &"Page"))
	box.add_child(_label("Loading", &"Caption"))
	box.add_child(_button("Continue", &"TextAction", focused))

func _add_hud(box: VBoxContainer, focused: bool) -> void:
	box.add_child(_label("HP  86", &"Numeric"))
	var bar: ProgressBar = ProgressBar.new()
	bar.max_value = 100
	bar.value = 24 if _state_index == 2 else 86
	if _state_index == 2:
		bar.theme_type_variation = &"ProgressBarLow"
	bar.custom_minimum_size = Vector2(240, 12)
	box.add_child(bar)
	box.add_child(_label("Low health." if _state_index == 2 else "Pistol", &"Caption"))
	box.add_child(_button("Pause", &"TextAction", focused))

func _add_shop(box: VBoxContainer, focused: bool) -> void:
	box.add_child(_label("Shop" if _screen_index == 15 else "Upgrade", &"InkPage"))
	box.add_child(_button("Thick Hide    30", &"OfferRow", focused))
	box.add_child(_button("Swift    20", &"OfferRow", false))
	box.add_child(_label("Not enough gold." if _state_index == 2 else "Choose one.", &"InkCaption"))
	box.add_child(_button("Continue", &"PrimaryAction", false))

func _add_credits(box: VBoxContainer, focused: bool) -> void:
	box.add_child(_label("Credits", &"InkPage"))
	box.add_child(_label("WPG", &"InkBody"))
	box.add_child(_button("Back", &"InkTextAction", focused))

func _error_copy() -> String:
	if _state_index == 0:
		return "Could not connect."
	if _state_index == 1:
		return "Host closed the room."
	return "Version mismatch."

func _nav_bar(focused: bool) -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	row.custom_minimum_size = Vector2(0, UiTokens.TOP_BAR_HEIGHT)
	for item: String in ["WPG", "Home", "Play", "Multiplayer", "Profile", "Settings"]:
		var button: Button = Button.new()
		button.text = item
		button.theme_type_variation = &"NavItem"
		button.focus_mode = Control.FOCUS_ALL
		if focused and item == "Play":
			button.set_meta("gallery_focus", true)
		row.add_child(button)
	return row

func _label(text: String, role: StringName) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.theme_type_variation = role
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.clip_text = false
	return label

func _button(text: String, role: StringName, focused: bool) -> Button:
	var button: Button = Button.new()
	button.text = text
	button.theme_type_variation = role
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.focus_mode = Control.FOCUS_ALL
	button.clip_text = true
	if focused:
		button.set_meta("gallery_focus", true)
	return button

func _first_focus(node: Node) -> Control:
	if node is Control and node.has_meta("gallery_focus"):
		return node as Control
	for child: Node in node.get_children():
		var marked: Control = _marked_focus(child)
		if marked != null:
			return marked
	if node is Control and (node as Control).focus_mode != Control.FOCUS_NONE:
		return node as Control
	for child: Node in node.get_children():
		var found: Control = _first_focus(child)
		if found != null:
			return found
	return null

func _marked_focus(node: Node) -> Control:
	if node is Control and node.has_meta("gallery_focus"):
		return node as Control
	for child: Node in node.get_children():
		var found: Control = _marked_focus(child)
		if found != null:
			return found
	return null

func _overflows(node: Node, size: Vector2) -> bool:
	var control: Control = node as Control
	if control != null:
		var minimum: Vector2 = control.get_combined_minimum_size()
		if minimum.x > size.x + 8.0 or minimum.y > size.y + 8.0:
			return true
	return false
