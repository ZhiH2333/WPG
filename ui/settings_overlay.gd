extends Control
class_name SettingsOverlay

## osu 式设置抽屉：左侧目录锚点，右侧一篇长文档。当前节可点，其它节压暗。
const IN_USE_FLASH_SEC: float = 0.6
const SIDEBAR_RATIO: float = 1.0 / 7.0
const PANEL_OF_REMAINDER: float = 0.4
const TRANSITION_SEC: float = 0.6
const FADE_SEC: float = 0.3
const CONTENT_FADE_SEC: float = 0.5
const NAV_STAGGER_SEC: float = 0.04
# osu.Framework ScrollContainer: 80px per scroll unit.
const SCROLL_DISTANCE: float = 80.0
# DistanceDecayScroll = 0.01 / ms  ->  10 / s
const DISTANCE_DECAY_SCROLL: float = 10.0
# Precise devices use 0.05 / ms  ->  50 / s (trackpad / high-res wheel).
const DISTANCE_DECAY_PRECISE: float = 50.0
# DistanceDecayJump = 0.01 / ms, used when clicking a section.
const DISTANCE_DECAY_JUMP: float = 10.0
const SCROLL_CENTRE: float = 0.1

var _open: bool = false
var _anim_tween: Tween
var _action_by_button: Dictionary = {}
var _joy_button_by_action: Dictionary = {}
var _listening_action: String = ""
var _listening_button: Button = null
var _listening_joy: bool = false
var _scroll_current: float = 0.0
var _scroll_target: float = 0.0
var _distance_decay: float = DISTANCE_DECAY_SCROLL
var _user_scrolling: bool = false
var _hold_search_focus: bool = false
var _clicked_section: SettingsSection = null
var _current_section: SettingsSection = null
var _close_on_up: bool = false
var _sections: Array[SettingsSection] = []
var _navs: Array[SettingsNavButton] = []
var _sfx_gate: Dictionary = {}

@onready var _dimmer: ColorRect = %Dimmer
@onready var _drawer: Control = %Drawer
@onready var _sidebar: Control = %Sidebar
@onready var _panel: Control = %Panel
@onready var _content: VBoxContainer = %Content
@onready var _header_bg: ColorRect = %HeaderBg
@onready var _expandable: Control = %ExpandableHeader
@onready var _search_wrap: Control = %SearchWrap
@onready var _search: LineEdit = %Search
@onready var _audio_nav: SettingsNavButton = %AudioButton
@onready var _display_nav: SettingsNavButton = %DisplayButton
@onready var _controls_nav: SettingsNavButton = %ControlsButton
@onready var _data_nav: SettingsNavButton = %DataButton
@onready var _audio_section: SettingsSection = %AudioSection
@onready var _display_section: SettingsSection = %DisplaySection
@onready var _controls_section: SettingsSection = %ControlsSection
@onready var _data_section: SettingsSection = %DataSection
@onready var _volume_slider: HSlider = %VolumeSlider
@onready var _music_slider: HSlider = %MusicSlider
@onready var _sfx_slider: HSlider = %SfxSlider
@onready var _fullscreen_check: CheckBox = %FullscreenCheck
@onready var _render_scale_label: Label = %RenderScaleLabel
@onready var _render_scale_slider: HSlider = %RenderScaleSlider
@onready var _ui_scale_label: Label = %UiScaleLabel
@onready var _ui_scale_slider: HSlider = %UiScaleSlider
@onready var _vsync_check: CheckBox = %VsyncCheck
@onready var _msaa_option: OptionButton = %MsaaOption
@onready var _delete_button: HoldConfirmButton = %DeleteButton
@onready var _status_label: Label = %StatusLabel
@onready var _preview: AudioStreamPlayer = %Preview
@onready var _version_label: Label = %VersionLabel
@onready var _credits_button: Button = %CreditsButton
@onready var _hover_sfx: AudioStreamPlayer = $HoverSfx
@onready var _click_sfx: AudioStreamPlayer = $ClickSfx
@onready var _back_sfx: AudioStreamPlayer = $BackSfx
@onready var _credits: CreditsOverlay = $CreditsOverlay

func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(false)
	_preview.stream = GameAudio.load_wav("res://audio/click.wav")
	_hover_sfx.stream = GameAudio.load_wav("res://audio/ui_hover.wav")
	_click_sfx.stream = GameAudio.load_wav("res://audio/ui_click.wav")
	_back_sfx.stream = GameAudio.load_wav("res://audio/ui_back.wav")
	_version_label.text = "version  %s" % GameSettings.get_version()
	_msaa_option.clear()
	_msaa_option.add_item("Off")
	_msaa_option.add_item("2x")
	_msaa_option.add_item("4x")
	_msaa_option.add_item("8x")
	_sections = [_audio_section, _display_section, _controls_section, _data_section]
	_navs = [_audio_nav, _display_nav, _controls_nav, _data_nav]
	_tag_searchable()
	_build_bind_rows()
	_audio_nav.pressed.connect(_on_nav_pressed.bind(_audio_section))
	_display_nav.pressed.connect(_on_nav_pressed.bind(_display_section))
	_controls_nav.pressed.connect(_on_nav_pressed.bind(_controls_section))
	_data_nav.pressed.connect(_on_nav_pressed.bind(_data_section))
	_audio_section.selected_requested.connect(_on_nav_pressed.bind(_audio_section))
	_display_section.selected_requested.connect(_on_nav_pressed.bind(_display_section))
	_controls_section.selected_requested.connect(_on_nav_pressed.bind(_controls_section))
	_data_section.selected_requested.connect(_on_nav_pressed.bind(_data_section))
	_dimmer.gui_input.connect(_on_dimmer_gui_input)
	_search.text_changed.connect(_on_search_changed)
	_volume_slider.value_changed.connect(_on_volume_changed)
	_volume_slider.drag_ended.connect(_on_volume_drag_ended)
	_music_slider.value_changed.connect(_on_music_changed)
	_music_slider.drag_ended.connect(_on_music_drag_ended)
	_sfx_slider.value_changed.connect(_on_sfx_changed)
	_sfx_slider.drag_ended.connect(_on_sfx_drag_ended)
	_fullscreen_check.toggled.connect(_on_fullscreen_toggled)
	_render_scale_slider.value_changed.connect(_on_render_scale_changed)
	_render_scale_slider.drag_ended.connect(_on_render_scale_drag_ended)
	_ui_scale_slider.value_changed.connect(_on_ui_scale_changed)
	_ui_scale_slider.drag_ended.connect(_on_ui_scale_drag_ended)
	_vsync_check.toggled.connect(_on_vsync_toggled)
	_msaa_option.item_selected.connect(_on_msaa_selected)
	_delete_button.confirmed.connect(_on_delete_all_confirmed)
	_credits_button.pressed.connect(_on_credits_pressed)
	_volume_slider.scrollable = false
	_music_slider.scrollable = false
	_sfx_slider.scrollable = false
	_render_scale_slider.scrollable = false
	_ui_scale_slider.scrollable = false
	_search.focus_mode = Control.FOCUS_ALL
	var viewport: Viewport = get_viewport()
	if viewport != null:
		viewport.gui_focus_changed.connect(_on_gui_focus_changed)
	resized.connect(_apply_drawer_layout)
	_apply_drawer_layout()
	_fit_sections()
	_wire_overlay_sounds()

func is_open() -> bool:
	return _open

func is_credits_open() -> bool:
	return _credits != null and _credits.is_open()

func open() -> void:
	_search.set_block_signals(true)
	_search.text = ""
	_search.set_block_signals(false)
	_apply_search("")
	_scroll_current = 0.0
	_scroll_target = 0.0
	_user_scrolling = false
	_clicked_section = null
	_sync_from_settings()
	_cancel_listen()
	_refresh_key_labels()
	_status_label.text = ""
	_open = true
	_hold_search_focus = true
	_distance_decay = DISTANCE_DECAY_JUMP
	visible = true
	modulate.a = 1.0
	_drawer.modulate.a = 1.0
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_process(true)
	set_process_input(true)
	set_process_unhandled_input(true)
	move_to_front()
	var top_bar: Control = _find_top_bar()
	if top_bar != null:
		top_bar.move_to_front()
	_apply_split_layout()
	_fit_sections()
	_layout_scroll()
	_set_current(_audio_section)
	_play_open_animation()
	_search.grab_focus()

func close() -> void:
	if not _open:
		return
	_cancel_listen()
	if _credits != null and _credits.is_open():
		_credits.close()
	_open = false
	_hold_search_focus = false
	_close_on_up = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process_input(false)
	set_process_unhandled_input(false)
	_play_close_animation()
	_refocus_menu()

func _refocus_menu() -> void:
	if _another_overlay_open():
		return
	var play: Button = get_parent().get_node_or_null("Center/Column/Buttons/Play") as Button
	if play != null:
		play.grab_focus()

func _another_overlay_open() -> bool:
	var parent: Node = get_parent()
	if parent == null:
		return false
	var mode: ModeChoiceOverlay = parent.get_node_or_null("ModeChoiceOverlay") as ModeChoiceOverlay
	if mode != null and mode.is_open():
		return true
	var records: RecordSelector = parent.get_node_or_null("RecordSelector") as RecordSelector
	if records != null and records.is_open():
		return true
	var profile: ProfileOverlay = parent.get_node_or_null("ProfileOverlay") as ProfileOverlay
	if profile != null and profile.is_open():
		return true
	var leaderboard: RecordLeaderboardOverlay = parent.get_node_or_null("RecordLeaderboardOverlay") as RecordLeaderboardOverlay
	if leaderboard != null and leaderboard.is_open():
		return true
	var lan: LanOverlay = parent.get_node_or_null("LanOverlay") as LanOverlay
	return lan != null and lan.is_open()

func _play_open_animation() -> void:
	UiAnim.kill_tween(_anim_tween)
	var drawer_w: float = _drawer_w()
	_drawer.offset_left = -drawer_w
	_drawer.offset_right = 0.0
	_dimmer.modulate.a = 0.0
	_content.modulate.a = 0.0
	_anim_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS).set_parallel(true)
	_anim_tween.tween_property(_drawer, "offset_left", 0.0, TRANSITION_SEC).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	_anim_tween.tween_property(_drawer, "offset_right", drawer_w, TRANSITION_SEC).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	_anim_tween.tween_property(_dimmer, "modulate:a", 1.0, FADE_SEC).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	_anim_tween.tween_property(_content, "modulate:a", 1.0, CONTENT_FADE_SEC).set_delay(TRANSITION_SEC / 3.0).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	var delay: float = 0.0
	for nav: SettingsNavButton in _navs:
		nav.modulate.a = 0.0
		_anim_tween.tween_property(nav, "modulate:a", 1.0, CONTENT_FADE_SEC).set_delay(delay).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
		delay += NAV_STAGGER_SEC

func _play_close_animation() -> void:
	UiAnim.kill_tween(_anim_tween)
	var drawer_w: float = _drawer_w()
	_anim_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS).set_parallel(true)
	_anim_tween.tween_property(_drawer, "offset_left", -drawer_w, TRANSITION_SEC).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	_anim_tween.tween_property(_drawer, "offset_right", 0.0, TRANSITION_SEC).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	_anim_tween.tween_property(_dimmer, "modulate:a", 0.0, FADE_SEC).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_IN)
	_anim_tween.tween_property(_drawer, "modulate:a", 0.0, FADE_SEC).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	_anim_tween.finished.connect(_finish_close, CONNECT_ONE_SHOT)

func _finish_close() -> void:
	if _open:
		return
	visible = false
	modulate.a = 1.0
	_drawer.modulate.a = 1.0
	set_process(false)

func _process(delta: float) -> void:
	if not _open:
		return
	var blend: float = 1.0 - exp(-_distance_decay * delta)
	_scroll_current += (_scroll_target - _scroll_current) * blend
	if absf(_scroll_target - _scroll_current) < 0.25:
		_scroll_current = _scroll_target
	_layout_scroll()
	_update_current_from_scroll()

func _input(event: InputEvent) -> void:
	if not _open:
		return
	if not _listening_action.is_empty():
		_handle_listen_event(event)
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		if _credits != null and _credits.is_open():
			_credits.close_from_user()
			return
		_on_back_pressed()
		return
	if _mouse_over_drawer() and _consume_keyboard_scroll(event):
		get_viewport().set_input_as_handled()
		return
	if _is_scroll_event(event) and _mouse_over_drawer() and _consume_scroll_event(event):
		get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if not _open:
		return
	if _is_scroll_event(event) and _mouse_over_drawer() and _consume_scroll_event(event):
		get_viewport().set_input_as_handled()

func _on_dimmer_gui_input(event: InputEvent) -> void:
	var mouse: InputEventMouseButton = event as InputEventMouseButton
	if mouse == null:
		return
	if mouse.button_index == MOUSE_BUTTON_WHEEL_UP or mouse.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		accept_event()
		return
	if mouse.button_index != MOUSE_BUTTON_LEFT:
		return
	if mouse.pressed:
		_close_on_up = true
		return
	if not _close_on_up:
		return
	_close_on_up = false
	if not _drawer.get_global_rect().has_point(get_global_mouse_position()):
		_play_back()
		close()

func _screen_w() -> float:
	if size.x > 1.0:
		return size.x
	var vp: float = get_viewport_rect().size.x
	return vp if vp > 1.0 else 1920.0

func _sidebar_w() -> float:
	return _screen_w() * SIDEBAR_RATIO

func _panel_w() -> float:
	return (_screen_w() - _sidebar_w()) * PANEL_OF_REMAINDER

func _drawer_w() -> float:
	return _sidebar_w() + _panel_w()

func _apply_split_layout() -> void:
	var side: float = _sidebar_w()
	var total: float = _drawer_w()
	_sidebar.offset_left = 0.0
	_sidebar.offset_right = side
	_panel.offset_left = side
	_panel.offset_right = total

func _apply_drawer_layout() -> void:
	_apply_split_layout()
	var total: float = _drawer_w()
	var tweening: bool = _anim_tween != null and is_instance_valid(_anim_tween) and _anim_tween.is_running()
	if tweening:
		return
	if _open:
		_drawer.offset_left = 0.0
		_drawer.offset_right = total
	else:
		_drawer.offset_left = -total
		_drawer.offset_right = 0.0
	_layout_scroll()

func _mouse_over_drawer() -> bool:
	var mouse_pos: Vector2 = get_global_mouse_position()
	if _drawer.get_global_rect().has_point(mouse_pos):
		return true
	if _panel.get_global_rect().has_point(mouse_pos):
		return true
	return _sidebar.get_global_rect().has_point(mouse_pos)

func _is_scroll_event(event: InputEvent) -> bool:
	var mouse: InputEventMouseButton = event as InputEventMouseButton
	if mouse != null:
		return mouse.button_index == MOUSE_BUTTON_WHEEL_UP or mouse.button_index == MOUSE_BUTTON_WHEEL_DOWN
	var pan: InputEventPanGesture = event as InputEventPanGesture
	return pan != null and not is_zero_approx(pan.delta.y)

func _consume_scroll_event(event: InputEvent) -> bool:
	var mouse: InputEventMouseButton = event as InputEventMouseButton
	if mouse != null:
		if mouse.button_index != MOUSE_BUTTON_WHEEL_UP and mouse.button_index != MOUSE_BUTTON_WHEEL_DOWN:
			return false
		if not mouse.pressed:
			return true
		var direction: float = -1.0 if mouse.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0
		var factor: float = mouse.factor
		if factor <= 0.0:
			factor = 1.0
		# osu: offset = ScrollDistance * delta; precise if the device sends fractional notches.
		var precise: bool = factor < 0.9
		_scroll_by(direction * SCROLL_DISTANCE * factor, precise)
		return true
	var pan: InputEventPanGesture = event as InputEventPanGesture
	if pan == null or is_zero_approx(pan.delta.y):
		return false
	# Godot pan.delta is already in pixels (osu precise path maps 1:1 to user motion).
	_scroll_by(pan.delta.y, true)
	return true

func _consume_keyboard_scroll(event: InputEvent) -> bool:
	if event.is_echo():
		return false
	if event.is_action_pressed("ui_page_up"):
		_scroll_by(-_panel.size.y, false)
		return true
	if event.is_action_pressed("ui_page_down"):
		_scroll_by(_panel.size.y, false)
		return true
	return false

func _on_back_pressed() -> void:
	# osu FocusedTextBox: first Back clears search, second hides the overlay.
	_play_back()
	if not _search.text.is_empty():
		_search.text = ""
		_search.grab_focus()
		return
	close()

func _on_gui_focus_changed(control: Control) -> void:
	if not _open or not _hold_search_focus:
		return
	if not _listening_action.is_empty():
		return
	if control == _search:
		if not _search.text.is_empty():
			_search.select_all()
		return
	if _should_keep_focus(control):
		return
	_search.grab_focus()

func _should_keep_focus(control: Control) -> bool:
	if control == null:
		return false
	if control is LineEdit or control is TextEdit:
		return true
	if control is HSlider or control is VSlider:
		return true
	if control is CheckBox or control is OptionButton:
		return true
	if control is SpinBox:
		return true
	if control is Button:
		return true
	return false

func _fit_sections() -> void:
	for section: SettingsSection in _sections:
		section._fit()

func _header_stack() -> float:
	return _expandable.size.y + _search_wrap.size.y

func _content_height() -> float:
	var content_h: float = 0.0
	var visible_count: int = 0
	var sep: int = _content.get_theme_constant("separation")
	for child: Node in _content.get_children():
		var item: Control = child as Control
		if item == null or not item.visible:
			continue
		content_h += item.get_combined_minimum_size().y
		visible_count += 1
	if visible_count > 1:
		content_h += float(sep * (visible_count - 1))
	return content_h

func _max_scroll() -> float:
	return maxf(0.0, _content_height() + _header_stack() - _panel.size.y)

func _layout_scroll() -> void:
	var pad: Control = _content.get_node_or_null("BottomPad") as Control
	if pad != null:
		var pad_h: float = maxf(240.0, _panel.size.y * 0.45)
		if not is_equal_approx(pad.custom_minimum_size.y, pad_h):
			pad.custom_minimum_size.y = pad_h
	var title_h: float = _expandable.size.y
	var search_h: float = _search_wrap.size.y
	var stack: float = title_h + search_h
	var content_h: float = maxf(_content_height(), 1.0)
	_content.position = Vector2(0.0, stack - _scroll_current)
	_content.size = Vector2(_panel.size.x, content_h)
	var eat: float = minf(title_h, _scroll_current)
	_expandable.offset_top = -eat
	_expandable.offset_bottom = title_h - eat
	_search_wrap.offset_top = title_h - eat
	_search_wrap.offset_bottom = title_h - eat + search_h
	_header_bg.position = Vector2(0.0, -eat)
	_header_bg.size = Vector2(_panel.size.x, stack)
	if title_h > 0.5:
		_header_bg.modulate.a = eat / title_h
	else:
		_header_bg.modulate.a = 0.0

func _scroll_by(offset: float, precise: bool) -> void:
	_user_scrolling = true
	_clicked_section = null
	_distance_decay = DISTANCE_DECAY_PRECISE if precise else DISTANCE_DECAY_SCROLL
	_scroll_target = clampf(_scroll_target + offset, 0.0, _max_scroll())

func _scroll_to_section(section: SettingsSection) -> void:
	if section == null or not section.visible:
		return
	_user_scrolling = false
	_clicked_section = section
	_distance_decay = DISTANCE_DECAY_JUMP
	_set_current(section)
	var target: float = _header_stack() + section.position.y - _panel.size.y * SCROLL_CENTRE
	_scroll_target = clampf(target, 0.0, _max_scroll())

func _set_current(section: SettingsSection) -> void:
	_current_section = section
	for i: int in _sections.size():
		_sections[i].set_current(_sections[i] == section)
		_navs[i].selected = _sections[i] == section

func _update_current_from_scroll() -> void:
	if _clicked_section != null and not _user_scrolling:
		_set_current(_clicked_section)
		return
	var visible_sections: Array[SettingsSection] = []
	for section: SettingsSection in _sections:
		if section.visible:
			visible_sections.append(section)
	if visible_sections.is_empty():
		return
	if _scroll_current >= _max_scroll() - 1.0:
		_set_current(visible_sections[visible_sections.size() - 1])
		return
	var centre: float = _search_wrap.size.y + _panel.size.y * SCROLL_CENTRE
	var picked: SettingsSection = visible_sections[0]
	for section: SettingsSection in visible_sections:
		var top: float = _content.position.y + section.position.y
		if top <= centre:
			picked = section
		else:
			break
	_set_current(picked)

func _on_search_changed(text: String) -> void:
	_apply_search(text)
	_clicked_section = null
	_scroll_target = clampf(_scroll_target, 0.0, _max_scroll())

func _apply_search(text: String) -> void:
	var query: String = text.strip_edges().to_lower()
	for section: SettingsSection in _sections:
		var header_hit: bool = query.is_empty() or query in section.search_name.to_lower() or query in section.header_text.to_lower()
		var any_item: bool = header_hit
		for child: Node in section.body.get_children():
			if child.name == "Separator" or child.name == "Header":
				continue
			var item: CanvasItem = child as CanvasItem
			if item == null:
				continue
			var show: bool = header_hit or _matches(child, query)
			item.visible = show
			if show:
				any_item = true
		section.visible = any_item
		section._fit()
	for i: int in _sections.size():
		_navs[i].modulate.a = 1.0 if _sections[i].visible else 0.28

func _matches(node: Node, query: String) -> bool:
	if query.is_empty():
		return true
	var blob: String = str(node.get_meta("settings_search", "")).to_lower()
	var label: Label = node as Label
	if label != null:
		blob += " " + label.text.to_lower()
	var button: Button = node as Button
	if button != null:
		blob += " " + button.text.to_lower()
	for child: Node in node.get_children():
		if _matches(child, query):
			return true
	return query in blob

func _tag_searchable() -> void:
	_volume_slider.get_parent().set_meta("settings_search", "volume audio master")
	_music_slider.get_parent().set_meta("settings_search", "volume audio music bgm")
	_sfx_slider.get_parent().set_meta("settings_search", "volume audio sfx sound")
	_fullscreen_check.get_parent().set_meta("settings_search", "fullscreen display")
	_render_scale_slider.get_parent().set_meta("settings_search", "render resolution scale")
	_ui_scale_slider.get_parent().set_meta("settings_search", "ui scale")
	_vsync_check.get_parent().set_meta("settings_search", "vsync display")
	_msaa_option.get_parent().set_meta("settings_search", "msaa antialias")
	_delete_button.set_meta("settings_search", "delete data progress records")
	_credits_button.set_meta("settings_search", "credits about version")
	var warning: Node = _data_section.body.get_node_or_null("Warning")
	if warning != null:
		warning.set_meta("settings_search", "delete data progress records")

func _sync_from_settings() -> void:
	_volume_slider.set_value_no_signal(GameSettings.get_volume())
	_music_slider.set_value_no_signal(GameSettings.get_music_volume())
	_sfx_slider.set_value_no_signal(GameSettings.get_sfx_volume())
	_fullscreen_check.set_pressed_no_signal(GameSettings.is_fullscreen())
	var render_percent: float = GameSettings.get_render_scale() * 100.0
	_render_scale_slider.set_value_no_signal(render_percent)
	_sync_render_scale_label(render_percent)
	var ui_percent: float = GameSettings.get_ui_scale() * 100.0
	_ui_scale_slider.set_value_no_signal(ui_percent)
	_sync_ui_scale_label(ui_percent)
	_vsync_check.set_pressed_no_signal(GameSettings.is_vsync_enabled())
	_msaa_option.select(GameSettings.get_msaa_index())

func _on_volume_changed(value: float) -> void:
	GameSettings.set_volume(value)
	GameSettings.apply()

func _on_volume_drag_ended(_value_changed: bool) -> void:
	GameSettings.save_to_disk()
	if GameSettings.get_volume() > 0.0 and GameSettings.get_sfx_volume() > 0.0:
		_play_preview()

func _on_music_changed(value: float) -> void:
	GameSettings.set_music_volume(value)
	GameSettings.apply()

func _on_music_drag_ended(_value_changed: bool) -> void:
	GameSettings.save_to_disk()

func _on_sfx_changed(value: float) -> void:
	GameSettings.set_sfx_volume(value)
	GameSettings.apply()

func _on_sfx_drag_ended(_value_changed: bool) -> void:
	GameSettings.save_to_disk()
	if GameSettings.get_volume() > 0.0 and GameSettings.get_sfx_volume() > 0.0:
		_play_preview()

func _on_fullscreen_toggled(pressed: bool) -> void:
	_play_click()
	GameSettings.set_fullscreen(pressed)
	GameSettings.apply()
	GameSettings.save_to_disk()

func _on_render_scale_changed(value: float) -> void:
	GameSettings.set_render_scale(value / 100.0)
	_sync_render_scale_label(value)

func _on_render_scale_drag_ended(_value_changed: bool) -> void:
	GameSettings.save_to_disk()

func _on_ui_scale_changed(value: float) -> void:
	GameSettings.set_ui_scale(value / 100.0)
	GameSettings.apply()
	_sync_ui_scale_label(value)
	_apply_drawer_layout()
	_fit_sections()
	_layout_scroll()

func _on_ui_scale_drag_ended(_value_changed: bool) -> void:
	GameSettings.save_to_disk()

func _on_vsync_toggled(pressed: bool) -> void:
	_play_click()
	GameSettings.set_vsync_enabled(pressed)
	GameSettings.apply()
	GameSettings.save_to_disk()

func _on_msaa_selected(index: int) -> void:
	_play_click()
	GameSettings.set_msaa_index(index)
	GameSettings.apply()
	GameSettings.save_to_disk()

func _on_delete_all_confirmed() -> void:
	_play_click()
	var dir: DirAccess = DirAccess.open("user://")
	if dir != null:
		if FileAccess.file_exists("user://progress.cfg"):
			dir.remove("progress.cfg")
		if FileAccess.file_exists("user://records.json"):
			dir.remove("records.json")
	GameProgress.load_from_disk()
	GameRecords.load_from_disk()
	_status_label.text = "All data deleted."

func _build_bind_rows() -> void:
	var body: VBoxContainer = _controls_section.body
	var hint: Label = Label.new()
	hint.theme_type_variation = &"RunSummaryHint"
	hint.text = "Sticks stay analog. Pad column rebinds Dash and guns."
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(hint)
	for action: String in GameSettings.REBINDABLE_ACTIONS:
		var row: HBoxContainer = HBoxContainer.new()
		row.set_meta("settings_search", GameSettings.action_display_name(action))
		row.mouse_filter = Control.MOUSE_FILTER_STOP
		row.add_theme_constant_override("separation", 12)
		var name_label: Label = Label.new()
		name_label.theme_type_variation = &"SettingsHeader"
		name_label.text = GameSettings.action_display_name(action)
		name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var button: Button = Button.new()
		button.theme_type_variation = &"OfferButton"
		button.custom_minimum_size = Vector2(160, 44)
		button.mouse_filter = Control.MOUSE_FILTER_STOP
		button.text = GameSettings.key_label_for_action(action)
		button.pressed.connect(_on_rebind_pressed.bind(button))
		_action_by_button[button] = action
		row.add_child(name_label)
		row.add_child(button)
		if GameSettings.REBINDABLE_JOY_ACTIONS.has(action):
			var pad: Button = Button.new()
			pad.theme_type_variation = &"OfferButton"
			pad.custom_minimum_size = Vector2(160, 44)
			pad.mouse_filter = Control.MOUSE_FILTER_STOP
			pad.text = GameSettings.joy_label_for_action(action)
			pad.set_meta("settings_search", "gamepad joypad pad dash gun")
			pad.pressed.connect(_on_rebind_joy_pressed.bind(pad))
			_joy_button_by_action[pad] = action
			row.add_child(pad)
		body.add_child(row)
	_controls_section._fit()

func _on_rebind_pressed(button: Button) -> void:
	_play_click()
	_begin_listen(button)

func _on_rebind_joy_pressed(button: Button) -> void:
	_play_click()
	_begin_listen_joy(button)

func _restore_other_listen_button(next_button: Button) -> void:
	if _listening_button == null or not is_instance_valid(_listening_button) or _listening_button == next_button:
		return
	_listening_button.text = _bind_label_for_button(_listening_button)

func _bind_label_for_button(button: Button) -> String:
	if _joy_button_by_action.has(button):
		return GameSettings.joy_label_for_action(str(_joy_button_by_action[button]))
	var action: String = str(_action_by_button.get(button, ""))
	if action.is_empty():
		return ""
	return GameSettings.key_label_for_action(action)

func _begin_listen(button: Button) -> void:
	_restore_other_listen_button(button)
	_listening_button = button
	_listening_action = str(_action_by_button[button])
	_listening_joy = false
	button.text = "..."
	var viewport: Viewport = get_viewport()
	if viewport != null:
		viewport.gui_release_focus()

func _begin_listen_joy(button: Button) -> void:
	_restore_other_listen_button(button)
	_listening_button = button
	_listening_action = str(_joy_button_by_action[button])
	_listening_joy = true
	button.text = "..."
	var viewport: Viewport = get_viewport()
	if viewport != null:
		viewport.gui_release_focus()

func _cancel_listen() -> void:
	if _listening_button != null and is_instance_valid(_listening_button):
		_listening_button.text = _bind_label_for_button(_listening_button)
	_listening_button = null
	_listening_action = ""
	_listening_joy = false

func _handle_listen_event(event: InputEvent) -> void:
	var key_event: InputEventKey = event as InputEventKey
	if key_event != null and key_event.pressed and not key_event.echo:
		if _listening_joy:
			if key_event.keycode == KEY_ESCAPE or event.is_action_pressed("ui_cancel"):
				_cancel_listen()
				_search.grab_focus()
		else:
			_handle_rebind_key(key_event)
		get_viewport().set_input_as_handled()
		return
	var joy_event: InputEventJoypadButton = event as InputEventJoypadButton
	if joy_event != null and joy_event.pressed:
		if _listening_joy:
			_handle_rebind_joy(joy_event)
		get_viewport().set_input_as_handled()

func _handle_rebind_key(key_event: InputEventKey) -> void:
	var action: String = _listening_action
	var button: Button = _listening_button
	if key_event.keycode == KEY_ESCAPE:
		_cancel_listen()
		_search.grab_focus()
		return
	_listening_action = ""
	_listening_button = null
	_listening_joy = false
	if button == null or not is_instance_valid(button):
		_search.grab_focus()
		return
	if GameSettings.set_key_for_action(action, key_event.physical_keycode):
		GameSettings.apply()
		GameSettings.save_to_disk()
		button.text = GameSettings.key_label_for_action(action)
		_search.grab_focus()
		return
	button.text = "IN USE"
	_search.grab_focus()
	var tree: SceneTree = get_tree()
	if tree == null:
		return
	tree.create_timer(IN_USE_FLASH_SEC).timeout.connect(_restore_bind_label.bind(button, action))

func _handle_rebind_joy(joy_event: InputEventJoypadButton) -> void:
	var action: String = _listening_action
	var button: Button = _listening_button
	_listening_action = ""
	_listening_button = null
	_listening_joy = false
	if button == null or not is_instance_valid(button):
		_search.grab_focus()
		return
	if GameSettings.set_joy_button_for_action(action, joy_event.button_index):
		GameSettings.save_to_disk()
		button.text = GameSettings.joy_label_for_action(action)
		_search.grab_focus()
		return
	button.text = "IN USE"
	_search.grab_focus()
	var tree: SceneTree = get_tree()
	if tree == null:
		return
	tree.create_timer(IN_USE_FLASH_SEC).timeout.connect(_restore_bind_label.bind(button, action))

func _restore_bind_label(button: Button, action: String) -> void:
	if not is_instance_valid(button):
		return
	if _listening_button == button:
		return
	if _joy_button_by_action.has(button):
		button.text = GameSettings.joy_label_for_action(action)
		return
	button.text = GameSettings.key_label_for_action(action)

func _refresh_key_labels() -> void:
	for entry: Variant in _action_by_button.keys():
		var button: Button = entry as Button
		if button == null or button == _listening_button:
			continue
		button.text = GameSettings.key_label_for_action(str(_action_by_button[button]))
	for entry: Variant in _joy_button_by_action.keys():
		var button: Button = entry as Button
		if button == null or button == _listening_button:
			continue
		button.text = GameSettings.joy_label_for_action(str(_joy_button_by_action[button]))
func _sync_render_scale_label(slider_value: float) -> void:
	_render_scale_label.text = "Render Resolution  %d%%" % int(slider_value)

func _sync_ui_scale_label(slider_value: float) -> void:
	_ui_scale_label.text = "UI Scale  %d%%" % int(slider_value)

func _play_preview() -> void:
	if _preview.stream == null:
		return
	_preview.stop()
	_preview.play()

func _on_nav_pressed(section: SettingsSection) -> void:
	_play_click()
	_scroll_to_section(section)

func _on_credits_pressed() -> void:
	if not _open:
		return
	_play_click()
	_credits.open()

func _wire_overlay_sounds() -> void:
	for entry: Variant in find_children("*", "BaseButton", true, false):
		var button: BaseButton = entry as BaseButton
		if button == null or _is_credits_owned(button):
			continue
		_wire_hover(button)

func _is_credits_owned(node: Node) -> bool:
	var current: Node = node
	while current != null and current != self:
		if current is CreditsOverlay:
			return true
		current = current.get_parent()
	return false

func _wire_hover(button: BaseButton) -> void:
	if button.mouse_entered.is_connected(_play_hover):
		return
	button.mouse_entered.connect(_play_hover)
	button.focus_entered.connect(_play_hover)

func _play_hover() -> void:
	if not _open:
		return
	_play_stream(_hover_sfx, &"hover")

func _play_click() -> void:
	_play_stream(_click_sfx, &"click")

func _play_back() -> void:
	_play_stream(_back_sfx, &"back")

func _play_stream(player: AudioStreamPlayer, key: StringName) -> void:
	if player == null or player.stream == null:
		return
	var frame: int = Engine.get_process_frames()
	if int(_sfx_gate.get(key, -1)) == frame:
		return
	_sfx_gate[key] = frame
	player.play()

func _find_top_bar() -> Control:
	var parent: Node = get_parent()
	if parent == null:
		return null
	var top_bar: Control = parent.get_node_or_null("TopBar") as Control
	if top_bar != null:
		return top_bar
	top_bar = parent.get_node_or_null("TopBarLayer/TopBar") as Control
	if top_bar != null:
		return top_bar
	return parent.get_node_or_null("Root/TopBar") as Control
