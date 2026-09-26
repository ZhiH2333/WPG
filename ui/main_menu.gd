extends Control
class_name MainMenu

## 主菜单：舞台、一行玩家状态、Action Rail。顶栏负责导航。没有中央 PLAY。
const SANDBOX_SCENE := "res://sandbox/combat_sandbox.tscn"
const LOADING_SCREEN_SCRIPT := preload("res://ui/loading_screen.gd")
const TOP_BAR_HEIGHT: float = 60.0
const MUSIC_DB_NORMAL: float = -6.0
const MUSIC_DB_DIMMED: float = -16.0
const SILENCE_DB: float = -80.0
const BGM_FADE_SEC: float = 0.45
const BLUR_MAX: float = 2.6
const DIM_MAX: float = 0.35
const FOCUS_SMOOTH: float = 9.0

enum RecordOrigin { HOME, PLAY }

var _enter_tween: Tween
var _music_fade_tween: Tween
var _focus_amount: float = 0.0
var _music_fade: float = 0.0
var _leaving: bool = false
var _last_clock_second: int = -1
var _suppress_return: bool = false
var _record_origin: RecordOrigin = RecordOrigin.HOME
var _settings_return: Control = null
var _sfx_gate: Dictionary = {}

@onready var _stage: Control = $Home/Body/Stage
@onready var _player_name: Label = $Home/Body/Name
@onready var _player_status: Label = $Home/Body/Status
@onready var _continue_button: Button = $Home/Body/Rail/Continue
@onready var _solo_button: Button = $Home/Body/Rail/Solo
@onready var _multi_button: Button = $Home/Body/Rail/Multi
@onready var _continue_caption: Label = $Home/Body/Rail/Continue/Caption
@onready var _secondary: HBoxContainer = $Home/Body/Secondary
@onready var _best_button: Button = $Home/Body/Secondary/Best
@onready var _best_value: Label = $Home/Body/Secondary/Best/Value
@onready var _last_button: Button = $Home/Body/Secondary/Last
@onready var _last_value: Label = $Home/Body/Secondary/Last/Value
@onready var _quit_button: Button = $Quit
@onready var _top_bar: PanelContainer = $TopBar
@onready var _brand_button: Button = $TopBar/Row/BrandButton
@onready var _home_button: Button = $TopBar/Row/HomeButton
@onready var _top_play_button: Button = $TopBar/Row/PlayButton
@onready var _top_multi_button: Button = $TopBar/Row/MultiButton
@onready var _top_profile_button: Button = $TopBar/Row/ProfileButton
@onready var _top_settings_button: Button = $TopBar/Row/SettingsButton
@onready var _identity_button: Button = $TopBar/Row/Identity
@onready var _profile_name: Label = $TopBar/Row/Identity/Name
@onready var _profile_avatar: TextureRect = $TopBar/Row/Identity/Avatar
@onready var _clock_label: Label = $TopBar/Row/TimeBox/Clock
@onready var _music: AudioStreamPlayer = $Music
@onready var _hover_sfx: AudioStreamPlayer = $HoverSfx
@onready var _click_sfx: AudioStreamPlayer = $ClickSfx
@onready var _back_sfx: AudioStreamPlayer = $BackSfx
@onready var _overlay: SettingsOverlay = $SettingsOverlay
@onready var _record_selector: RecordSelector = $RecordSelector
@onready var _profile_overlay: ProfileOverlay = $ProfileOverlay
@onready var _leaderboard_overlay: RecordLeaderboardOverlay = $RecordLeaderboardOverlay
@onready var _lan_overlay: LanOverlay = $LanOverlay
@onready var _play_page: PlayPage = $PlayPage

func _ready() -> void:
	GameSettings.load_from_disk()
	GameSettings.apply()
	GameProgress.load_from_disk()
	GameRecords.load_from_disk()
	PlayerProfile.load_from_disk()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_hover_sfx.stream = GameAudio.load_wav("res://audio/ui_hover.wav")
	_click_sfx.stream = GameAudio.load_wav("res://audio/ui_click.wav")
	_back_sfx.stream = GameAudio.load_wav("res://audio/ui_back.wav")
	_start_music()
	_brand_button.pressed.connect(_on_home_pressed)
	_home_button.pressed.connect(_on_home_pressed)
	_top_play_button.pressed.connect(_on_play_nav_pressed)
	_top_multi_button.pressed.connect(_enter_multi_flow)
	_top_profile_button.pressed.connect(_on_profile_pressed)
	_top_settings_button.pressed.connect(_on_settings_pressed)
	_identity_button.pressed.connect(_on_profile_pressed)
	_continue_button.pressed.connect(_on_continue_pressed)
	_solo_button.pressed.connect(_on_home_solo_pressed)
	_multi_button.pressed.connect(_enter_multi_flow)
	_best_button.pressed.connect(_on_profile_pressed)
	_last_button.pressed.connect(_on_continue_pressed)
	_quit_button.pressed.connect(_on_quit_pressed)
	_play_page.continue_pressed.connect(_on_continue_pressed)
	_play_page.solo_pressed.connect(_on_play_solo_pressed)
	_play_page.multi_pressed.connect(_enter_multi_flow)
	_play_page.back_pressed.connect(_on_play_back_pressed)
	_lan_overlay.start_lan.connect(_enter_lan)
	_record_selector.selected_record.connect(_enter_record)
	_profile_overlay.view_ranking_pressed.connect(_enter_leaderboard)
	_wire_button_sounds()
	_wire_rail_hover(_continue_button)
	_wire_rail_hover(_solo_button)
	_wire_rail_hover(_multi_button)
	_refresh_clock(true)
	_refresh_profile_name()
	_refresh_home_facts()
	_apply_menu_type()
	_clear_top_bar_surface()
	_ensure_rail_marks()
	_play_enter_animation()
	_top_bar.move_to_front()
	_focus_home_default()

func _process(delta: float) -> void:
	var target: float = 1.0 if _should_blur_menu() else 0.0
	_focus_amount = lerpf(_focus_amount, target, 1.0 - exp(-FOCUS_SMOOTH * delta))
	var overlay_db: float = lerpf(MUSIC_DB_NORMAL, MUSIC_DB_DIMMED, _focus_amount)
	_music.volume_db = lerpf(SILENCE_DB, overlay_db, _music_fade)
	_refresh_clock(false)
	_refresh_nav_marks()

func _input(event: InputEvent) -> void:
	if event.is_pressed():
		GameAudio.unlock_driver(self)
		_ensure_music()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		return
	if event.is_action_pressed("ui_accept"):
		if _blocks_home_accept():
			return
		get_viewport().set_input_as_handled()
		_first_rail().pressed.emit()

func latest_record() -> GameRecord:
	return _find_last_record()

func restore_after_settings() -> void:
	if _can_focus(_settings_return):
		_settings_return.grab_focus()
		return
	if _play_page.is_open():
		return
	_focus_home_default()

func on_record_selector_closed() -> void:
	if _suppress_return:
		return
	if _record_origin == RecordOrigin.PLAY:
		_open_play_page()
		return
	_focus_control(_solo_button)

func refresh_identity() -> void:
	_refresh_profile_name()

func on_profile_closed() -> void:
	if _suppress_return:
		return
	_focus_control(_top_profile_button)

func on_lan_closed() -> void:
	if _suppress_return:
		return
	_focus_control(_top_multi_button)

func _blocks_home_accept() -> bool:
	return _overlay.is_open() or _play_page.is_open() or _record_selector.is_open() or _profile_overlay.is_open() or _leaderboard_overlay.is_open() or _lan_overlay.is_open()

func _should_blur_menu() -> bool:
	return _play_page.is_open() or _record_selector.is_open() or _profile_overlay.is_open() or _leaderboard_overlay.is_open() or _lan_overlay.is_open() or _overlay.is_credits_open()

func _on_play_nav_pressed() -> void:
	if _record_selector.is_open() or _lan_overlay.is_open():
		_refresh_nav_marks()
		return
	if _play_page.is_open():
		return
	_open_play_page()

func _open_play_page() -> void:
	_close_other_pages(&"play")
	_play_page.open()
	_refresh_nav_marks()

func _on_play_back_pressed() -> void:
	if _play_page.is_open():
		_play_page.close()
	_focus_control(_top_play_button)

func _on_home_solo_pressed() -> void:
	_open_records(RecordOrigin.HOME)

func _on_play_solo_pressed() -> void:
	_open_records(RecordOrigin.PLAY)

func _open_records(origin: RecordOrigin) -> void:
	_record_origin = origin
	_close_other_pages(&"records")
	_record_selector.open()
	_refresh_nav_marks()

func _enter_multi_flow() -> void:
	if _lan_overlay.is_open():
		_refresh_nav_marks()
		return
	_close_other_pages(&"lan")
	_lan_overlay.open()
	_refresh_nav_marks()

func _on_profile_pressed() -> void:
	if _profile_overlay.is_open():
		return
	_close_other_pages(&"profile")
	_profile_overlay.open()
	_refresh_nav_marks()

func _enter_leaderboard() -> void:
	_close_other_pages(&"ranking")
	_leaderboard_overlay.open()
	_refresh_nav_marks()

func _on_settings_pressed() -> void:
	if _overlay.is_open() or _overlay.is_credits_open():
		return
	_settings_return = get_viewport().gui_get_focus_owner() as Control
	_overlay.open()
	_overlay.move_to_front()
	_top_bar.move_to_front()

func _on_home_pressed() -> void:
	_suppress_return = true
	if _overlay.is_open():
		_overlay.close()
	_close_other_pages(&"")
	_suppress_return = false
	_refresh_home_facts()
	_focus_home_default()
	_refresh_nav_marks()

func _close_other_pages(keep: StringName) -> void:
	_suppress_return = true
	if keep != &"play" and _play_page.is_open():
		_play_page.close()
	if keep != &"records" and _record_selector.is_open():
		_record_selector.close()
	if keep != &"profile" and _profile_overlay.is_open():
		_profile_overlay.close()
	if keep != &"ranking" and _leaderboard_overlay.is_open():
		_leaderboard_overlay.close()
	if keep != &"lan" and _lan_overlay.is_open():
		_lan_overlay.close()
	_suppress_return = false

func _on_continue_pressed() -> void:
	var record: GameRecord = _find_last_record()
	if record == null:
		return
	_enter_record(record.id)

func _enter_record(id: String) -> void:
	if _leaving:
		return
	var record: GameRecord = GameRecords.get_record(id)
	GameLaunch.set_active_record_id(id)
	GameLaunch.set_arena_id(record.arena_id if record != null else "yard")
	_leave_to_sandbox()

func _enter_lan() -> void:
	if _leaving:
		return
	_leave_to_sandbox()

func _leave_to_sandbox() -> void:
	if _leaving:
		return
	_leaving = true
	LOADING_SCREEN_SCRIPT.present_on(self, SANDBOX_SCENE)
	UiAnim.kill_tween(_music_fade_tween)
	_music_fade_tween = create_tween()
	_music_fade_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_music_fade_tween.tween_property(self, "_music_fade", 0.0, BGM_FADE_SEC).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_IN)
	_music_fade_tween.finished.connect(_finish_leave_to_sandbox)

func _finish_leave_to_sandbox() -> void:
	LOADING_SCREEN_SCRIPT.switch_current(get_tree())

func _refresh_profile_name() -> void:
	var display_name: String = PlayerProfile.get_display_name()
	_profile_name.text = display_name
	_player_name.text = display_name
	_player_status.text = "Ready to play"
	_profile_avatar.texture = RecordCard.resolve_body_texture(PlayerProfile.get_avatar_id())

func _refresh_home_facts() -> void:
	var record: GameRecord = _find_last_record()
	var has_record: bool = record != null
	_continue_button.visible = has_record
	if has_record:
		_continue_caption.text = _loop_caption(record.loop_goal)
	var has_best: bool = GameProgress.get_runs_played() > 0 or GameProgress.get_best_loop() > 0
	_best_button.visible = has_best
	if has_best:
		_best_value.text = str(GameProgress.get_best_loop())
	_last_button.visible = has_record
	if has_record:
		_last_value.text = _format_stamp(_record_stamp(record))
	_secondary.visible = has_best or has_record
	_wire_home_focus()

func _loop_caption(loop_goal: int) -> String:
	if loop_goal > 0:
		return "Loop %d" % loop_goal
	return "Inf"

func _find_last_record() -> GameRecord:
	var newest: GameRecord = null
	var newest_stamp: int = -1
	for record: GameRecord in GameRecords.list_records():
		var stamp: int = _record_stamp(record)
		if newest == null or stamp >= newest_stamp:
			newest = record
			newest_stamp = stamp
	return newest

func _record_stamp(record: GameRecord) -> int:
	var stamp: int = record.created_at
	for entry: Dictionary in record.history:
		var played_at: int = int(entry.get("timestamp", 0))
		if played_at > stamp:
			stamp = played_at
	return stamp

func _format_stamp(unix_sec: int) -> String:
	if unix_sec <= 0:
		return "--:--"
	var bias: int = int(Time.get_time_zone_from_system().get("bias", 0))
	var local: Dictionary = Time.get_datetime_dict_from_unix_time(unix_sec - bias * 60)
	return "%02d:%02d" % [int(local["hour"]), int(local["minute"])]

func _on_quit_pressed() -> void:
	get_tree().quit()

func _start_music() -> void:
	var mp3: AudioStreamMP3 = _music.stream as AudioStreamMP3
	if mp3 != null:
		mp3.loop = true
	_music_fade = 0.0
	_music.volume_db = SILENCE_DB
	_ensure_music()
	UiAnim.kill_tween(_music_fade_tween)
	_music_fade_tween = create_tween()
	_music_fade_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_music_fade_tween.tween_property(self, "_music_fade", 1.0, BGM_FADE_SEC).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)

func _ensure_music() -> void:
	if _music.stream != null and not _music.playing:
		_music.play()

func _wire_button_sounds() -> void:
	for entry: Variant in find_children("*", "BaseButton", true, false):
		var button: BaseButton = entry as BaseButton
		if button == null or _is_overlay_owned(button):
			continue
		button.mouse_entered.connect(_play_hover)
		button.focus_entered.connect(_play_hover)
		if button == _home_button or button == _brand_button or button == _quit_button:
			button.pressed.connect(_play_back)
		else:
			button.pressed.connect(_play_click)

func _wire_rail_hover(button: Button) -> void:
	button.mouse_entered.connect(_set_rail_hover.bind(button, true))
	button.mouse_exited.connect(_set_rail_hover.bind(button, false))
	button.focus_entered.connect(_set_rail_hover.bind(button, true))
	button.focus_exited.connect(_set_rail_hover.bind(button, false))

func _set_rail_hover(button: Button, hovered: bool) -> void:
	_paint_rail(button, hovered)

func _paint_rail(button: Button, hovered: bool = false) -> void:
	var title: Label = button.get_node_or_null("Title") as Label
	var mark: ColorRect = button.get_node_or_null("FocusMark") as ColorRect
	if title == null or mark == null:
		return
	var focused: bool = button.has_focus()
	var hot: bool = hovered or button.is_hovered() or focused
	title.theme_type_variation = &"RailTitle"
	mark.visible = hot
	mark.color = UiTokens.ACCENT if focused else UiTokens.PAPER
	mark.offset_top = -3.0
	mark.offset_bottom = 0.0

func _apply_menu_type() -> void:
	UiStyle.present($Home, false)
	UiStyle.present($TopBar, false)
	UiStyle.present($Quit, false)
	_player_name.theme_type_variation = &"PlayerName"
	_player_status.theme_type_variation = &"Caption"
	_profile_name.theme_type_variation = &"Navigation"
	_clock_label.theme_type_variation = &"Technical"
	for button: Button in [_brand_button, _home_button, _top_play_button, _top_multi_button, _top_profile_button, _top_settings_button]:
		button.theme_type_variation = &"NavItem"
	_quit_button.theme_type_variation = &"TextAction"
	for button: Button in [_continue_button, _solo_button, _multi_button]:
		(button.get_node("Title") as Label).theme_type_variation = &"RailTitle"
		(button.get_node("Caption") as Label).theme_type_variation = &"Caption"
	(_best_button.get_node("Title") as Label).theme_type_variation = &"Section"
	_best_value.theme_type_variation = &"Numeric"
	(_last_button.get_node("Title") as Label).theme_type_variation = &"Section"
	_last_value.theme_type_variation = &"Numeric"

func _clear_top_bar_surface() -> void:
	var empty: StyleBoxEmpty = StyleBoxEmpty.new()
	_top_bar.add_theme_stylebox_override("panel", empty)

func _ensure_rail_marks() -> void:
	for button: Button in [_continue_button, _solo_button, _multi_button]:
		if button.get_node_or_null("FocusMark") != null:
			_paint_rail(button)
			continue
		var mark: ColorRect = ColorRect.new()
		mark.name = "FocusMark"
		mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
		mark.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
		mark.offset_top = -2.0
		mark.offset_bottom = 0.0
		mark.visible = false
		button.add_child(mark)
		_paint_rail(button)

func _first_rail() -> Button:
	if _continue_button.visible:
		return _continue_button
	return _solo_button

func _focus_home_default() -> void:
	_first_rail().grab_focus()

func _focus_control(control: Control) -> void:
	if _can_focus(control):
		control.grab_focus()

func _wire_home_focus() -> void:
	var slots: Array[Button] = []
	if _continue_button.visible:
		slots.append(_continue_button)
	slots.append(_solo_button)
	slots.append(_multi_button)
	for index: int in slots.size():
		var slot: Button = slots[index]
		var left: Button = slots[index] if index == 0 else slots[index - 1]
		var right: Button = slots[index] if index == slots.size() - 1 else slots[index + 1]
		var below: Control = _secondary_focus()
		slot.focus_neighbor_left = left.get_path()
		slot.focus_neighbor_right = right.get_path()
		slot.focus_neighbor_top = _home_button.get_path()
		slot.focus_neighbor_bottom = below.get_path()
	var after_rail: Control = _secondary_focus()
	if _secondary.visible:
		_best_button.focus_neighbor_top = slots[0].get_path()
		_best_button.focus_neighbor_bottom = _quit_button.get_path()
		_last_button.focus_neighbor_top = slots[0].get_path()
		_last_button.focus_neighbor_bottom = _quit_button.get_path()
		_best_button.focus_neighbor_right = _last_button.get_path() if _last_button.visible else _best_button.get_path()
		_last_button.focus_neighbor_left = _best_button.get_path() if _best_button.visible else _last_button.get_path()
		after_rail = _best_button if _best_button.visible else _last_button
	_quit_button.focus_neighbor_top = after_rail.get_path()
	_quit_button.focus_neighbor_bottom = _quit_button.get_path()
	_set_horizontal(_home_button, _home_button, _top_play_button)
	_set_horizontal(_top_play_button, _home_button, _top_multi_button)
	_set_horizontal(_top_multi_button, _top_play_button, _top_profile_button)
	_set_horizontal(_top_profile_button, _top_multi_button, _top_settings_button)
	_set_horizontal(_top_settings_button, _top_profile_button, _top_settings_button)
	for nav: Button in [_home_button, _top_play_button, _top_multi_button, _top_profile_button, _top_settings_button]:
		nav.focus_neighbor_bottom = slots[0].get_path()

func _secondary_focus() -> Control:
	if _best_button.visible:
		return _best_button
	if _last_button.visible:
		return _last_button
	return _quit_button

func _set_horizontal(control: Control, left: Control, right: Control) -> void:
	control.focus_neighbor_left = left.get_path()
	control.focus_neighbor_right = right.get_path()

func _refresh_nav_marks() -> void:
	var current: Button = _home_button
	if _record_selector.is_open() or _play_page.is_open():
		current = _top_play_button
	elif _lan_overlay.is_open():
		current = _top_multi_button
	elif _profile_overlay.is_open() or _leaderboard_overlay.is_open():
		current = _top_profile_button
	for nav: Button in [_home_button, _top_play_button, _top_multi_button, _top_profile_button, _top_settings_button]:
		var mark: ColorRect = nav.get_node_or_null("Mark") as ColorRect
		var hot: bool = nav.is_hovered() or nav.has_focus()
		nav.theme_type_variation = &"NavItem"
		nav.remove_theme_color_override("font_color")
		if mark != null:
			mark.visible = nav == current or hot
			mark.color = UiTokens.ACCENT if nav == current or nav.has_focus() else UiTokens.PAPER

func _is_overlay_owned(node: Node) -> bool:
	var current: Node = node
	while current != null and current != self:
		if current is SettingsOverlay or current is RecordSelector or current is LanOverlay or current is ProfileOverlay or current is RecordLeaderboardOverlay or current is PlayPage or current is CreditsOverlay:
			return true
		current = current.get_parent()
	return false

func _can_focus(control: Control) -> bool:
	return control != null and is_instance_valid(control) and control.is_visible_in_tree() and control.focus_mode != Control.FOCUS_NONE

func _play_hover() -> void:
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

func _play_enter_animation() -> void:
	UiAnim.kill_tween(_enter_tween)
	_top_bar.offset_top = -TOP_BAR_HEIGHT
	_top_bar.offset_bottom = 0.0
	_stage.modulate.a = 0.0
	var rail: Array[CanvasItem] = [_continue_button, _solo_button, _multi_button]
	_enter_tween = create_tween().set_parallel(true)
	_enter_tween.tween_property(_top_bar, "offset_top", 0.0, UiAnim.PANEL_MOVE_SEC).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	_enter_tween.tween_property(_top_bar, "offset_bottom", TOP_BAR_HEIGHT, UiAnim.PANEL_MOVE_SEC).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	_enter_tween.tween_property(_stage, "modulate:a", 1.0, UiAnim.PAGE_MOVE_SEC).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	var order: int = 0
	for item: CanvasItem in rail:
		item.modulate.a = 0.0
		_enter_tween.tween_property(item, "modulate:a", 1.0, UiAnim.MENU_ITEM_FADE_SEC).set_delay(UiAnim.MENU_ITEM_STAGGER_SEC * float(order)).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
		order += 1

func _refresh_clock(force: bool) -> void:
	var now: Dictionary = Time.get_time_dict_from_system()
	var sec: int = int(now["second"])
	if not force and sec == _last_clock_second:
		return
	_last_clock_second = sec
	_clock_label.text = "%02d:%02d:%02d" % [int(now["hour"]), int(now["minute"]), sec]
