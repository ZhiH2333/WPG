extends Control
class_name MainMenu

## 主菜单：舞台、一行玩家状态、Action Rail。顶栏负责导航。没有中央 PLAY。
const SANDBOX_SCENE := "res://sandbox/combat_sandbox.tscn"
const LOADING_SCREEN_SCRIPT := preload("res://ui/loading_screen.gd")
const PLACEHOLDER_NAME := "Player"
const TOP_BAR_HEIGHT: float = 60.0
const MUSIC_DB_NORMAL: float = -6.0
const MUSIC_DB_DIMMED: float = -16.0
const SILENCE_DB: float = -80.0
const BGM_FADE_SEC: float = 0.45
const BLUR_MAX: float = 2.6
const DIM_MAX: float = 0.35
const FOCUS_SMOOTH: float = 9.0
## 版心：1920 宽下内容列 1200px（旧设计）。窄视口按 UiFit 收缩，别再往场景里写死 672 缩进。
const CONTENT_MARGIN: float = 48.0
const CONTENT_MAX_WIDTH: float = 1200.0

enum RecordOrigin { HOME, PLAY }

## app 式翻页：tab 顺序决定滑动方向（direction = +1 表示新页从右侧滑入、旧页向左滑出）。
const PAGE_HOME: StringName = &"home"
const PAGE_PLAY: StringName = &"play"
const PAGE_RECORDS: StringName = &"records"
const PAGE_MULTIPLAYER: StringName = &"multiplayer"
const PAGE_PROFILE: StringName = &"profile"
const PAGE_RANKING: StringName = &"ranking"
const PAGE_ORDER: Dictionary = {
	PAGE_HOME: 0, PAGE_PLAY: 1, PAGE_RECORDS: 2, PAGE_MULTIPLAYER: 3, PAGE_PROFILE: 4, PAGE_RANKING: 5,
}

var _enter_tween: Tween
var _music_fade_tween: Tween
var _focus_amount: float = 0.0
var _music_fade: float = 0.0
var _leaving: bool = false
var _last_clock_second: int = -1
var _suppress_return: bool = false
var _record_origin: RecordOrigin = RecordOrigin.HOME
var _page: StringName = PAGE_HOME
var _home_slid_out: bool = false
## 翻页途中再点 tab：排队到这一趟走完再走下一趟，避免出页从半路起步破坏刚性。
var _pending_page: StringName = &""
var _switch_left: float = 0.0
var _settings_return: Control = null
var _sfx_gate: Dictionary = {}
var _top_bar_full_min: float = 0.0
var _top_bar_nav_min: float = 0.0

@onready var _blur_layer: ColorRect = $BlurLayer
@onready var _home: MarginContainer = $Home
@onready var _stage: Control = $Home/Body/Stage
@onready var _player_name: Label = $Home/Body/Name
@onready var _player_status: Label = $Home/Body/Status
@onready var _continue_button: Button = $Home/Body/Rail/Continue
@onready var _solo_button: Button = $Home/Body/Rail/Solo
@onready var _multi_button: Button = $Home/Body/Rail/Multi
@onready var _continue_caption: Label = $Home/Body/Rail/Continue/Text/Caption
@onready var _rail_top_line: ColorRect = $Home/Body/TopLine
@onready var _rail_bottom_line: ColorRect = $Home/Body/BottomLine
@onready var _secondary: HBoxContainer = $Home/Body/Secondary
@onready var _best_button: Button = $Home/Body/Secondary/Best
@onready var _best_value: Label = $Home/Body/Secondary/Best/Text/Value
@onready var _last_button: Button = $Home/Body/Secondary/Last
@onready var _last_value: Label = $Home/Body/Secondary/Last/Text/Value
@onready var _quit_button: Button = $Quit
@onready var _top_bar: PanelContainer = $TopBar
@onready var _brand_button: Button = $TopBar/Row/BrandButton
@onready var _home_button: Button = $TopBar/Row/HomeButton
@onready var _top_play_button: Button = $TopBar/Row/PlayButton
@onready var _top_multi_button: Button = $TopBar/Row/MultiButton
@onready var _top_profile_button: Button = $TopBar/Row/ProfileButton
@onready var _top_settings_button: Button = $TopBar/Row/SettingsButton
@onready var _clock_label: Label = $TopBar/Row/TimeBox/Clock
@onready var _time_box: HBoxContainer = $TopBar/Row/TimeBox
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
@onready var _lobby: LobbyManager = $LobbyManager

func _ready() -> void:
	GameSettings.load_from_disk()
	GameSettings.apply()
	GameProgress.load_from_disk()
	GameRecords.load_from_disk()
	PlayerProfile.load_from_disk()
	refresh_profile_label()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_hover_sfx.stream = GameAudio.load_wav("res://audio/ui_hover.wav")
	_click_sfx.stream = GameAudio.load_wav("res://audio/ui_click.wav")
	_back_sfx.stream = GameAudio.load_wav("res://audio/ui_back.wav")
	_start_music()
	## 网页版没有「退出应用」：浏览器标签不归游戏管，`get_tree().quit()` 点了也没反应。
	## 直接藏掉 Quit，别在货架上留一个按不动的按钮；暂停叠层里的 Quit 是回主菜单，不受影响。
	if _quit_hidden_by_platform():
		_quit_button.visible = false
		_quit_button.focus_mode = Control.FOCUS_NONE
	_brand_button.pressed.connect(_on_home_pressed)
	_home_button.pressed.connect(_on_home_pressed)
	_top_play_button.pressed.connect(_on_play_nav_pressed)
	_top_multi_button.pressed.connect(_enter_multi_flow)
	_top_profile_button.pressed.connect(_on_profile_pressed)
	_top_settings_button.pressed.connect(_on_settings_pressed)
	_continue_button.pressed.connect(_on_continue_pressed)
	_solo_button.pressed.connect(_on_home_solo_pressed)
	_multi_button.pressed.connect(_enter_multi_flow)
	_best_button.pressed.connect(_on_profile_pressed)
	_last_button.pressed.connect(_on_continue_pressed)
	if _quit_button.visible:
		_quit_button.pressed.connect(_on_quit_pressed)
	_play_page.continue_pressed.connect(_on_continue_pressed)
	_play_page.solo_pressed.connect(_on_play_solo_pressed)
	_play_page.multi_pressed.connect(_enter_multi_flow)
	_play_page.back_pressed.connect(_on_play_back_pressed)
	_lan_overlay.start_lan.connect(_enter_lan)
	# LobbyNet 必须挂上：没有它 host_room() 只能返回失败，建房页会一直显示 bind failed。
	_lobby.bind_net($LobbyNet)
	_lan_overlay.bind_lobby(_lobby)
	_record_selector.selected_record.connect(_enter_record)
	_profile_overlay.view_ranking_pressed.connect(_enter_leaderboard)
	_wire_button_sounds()
	for row: Button in [_continue_button, _solo_button, _multi_button, _best_button, _last_button]:
		UiAnim.wire_row_feedback(self, row, UiType.INK)
	_refresh_clock(true)
	_refresh_player_labels()
	_refresh_home_facts()
	_sync_responsive()
	UiFit.connect_refit(self, _sync_responsive)
	_play_enter_animation()
	_top_bar.move_to_front()

func _process(delta: float) -> void:
	if _switch_left > 0.0:
		_switch_left = maxf(_switch_left - delta, 0.0)
		if is_zero_approx(_switch_left) and _pending_page != &"":
			var queued: StringName = _pending_page
			_pending_page = &""
			_switch_page(queued)
	var target: float = 1.0 if _should_blur_menu() else 0.0
	_focus_amount = lerpf(_focus_amount, target, 1.0 - exp(-FOCUS_SMOOTH * delta))
	var mat: ShaderMaterial = _blur_layer.material as ShaderMaterial
	mat.set_shader_parameter("blur_amount", BLUR_MAX * _focus_amount)
	mat.set_shader_parameter("dim_amount", DIM_MAX * _focus_amount)
	var overlay_db: float = lerpf(MUSIC_DB_NORMAL, MUSIC_DB_DIMMED, _focus_amount)
	_music.volume_db = lerpf(SILENCE_DB, overlay_db, _music_fade)
	_refresh_clock(false)
	_refresh_nav_marks()
	## Lobby domain 的时间推进：LAN join 的 attempt 超时与 P2P 的 rendezvous /
	## hole punch 都需要每帧推进。放在 MainMenu 这一层，保证叠层关掉时也照常推进。
	if _lobby != null:
		_lobby.tick_join(delta)

func _input(event: InputEvent) -> void:
	if event.is_pressed():
		GameAudio.unlock_driver(self)
		_ensure_music()

func _unhandled_input(event: InputEvent) -> void:
	## 逐层返回：Esc / Android 返回键先把打开的叠层与子页收掉（见 UiBack）。
	## 已到根页面（没叠层、已在 Home）时，Android 返回键才真正退出应用 ——
	## 这条分支必须在这里处理：叠层们对 `ui_cancel` 调用了 set_input_as_handled()，
	## 引擎自带的「返回键退出」永远等不到这个事件（见 ui/ui_back.gd 的说明）。
	if UiBack.is_back(event):
		if _back_once():
			get_viewport().set_input_as_handled()
		elif UiBack.is_root_back(event):
			get_viewport().set_input_as_handled()
			UiBack.quit_app(self)
		return
	if event.is_action_pressed("ui_accept"):
		if _blocks_home_accept():
			return
		get_viewport().set_input_as_handled()
		_first_rail().pressed.emit()
		return
	## 打开界面时不自动聚焦（见 UiFocus）：键盘 / 手柄第一次按导航键才建立焦点。
	## ui_accept 已在上面的分支里映射成「按 Home 首选 Rail」，所以钩子只处理方向键 / Tab。
	if UiFocus.handle_first_pad_input(self, event, [_first_rail()]):
		get_viewport().set_input_as_handled()
		return

func latest_record() -> GameRecord:
	return _find_last_record()

func restore_after_settings() -> void:
	# 关掉 Settings 不再把焦点抢回 Rail：交给 UiFocus，第一次按导航键才建立焦点。
	if _can_focus(_settings_return):
		_settings_return.grab_focus()
		return
	if _play_page.is_open():
		return

func on_record_selector_closed() -> void:
	if _suppress_return:
		return
	if _record_origin == RecordOrigin.PLAY:
		_switch_page(PAGE_PLAY)
		return
	_return_home(PAGE_RECORDS)
	_focus_control(_solo_button)

func on_profile_closed() -> void:
	if _suppress_return:
		return
	_return_home(PAGE_PROFILE)
	_focus_control(_top_profile_button)

func on_lan_closed() -> void:
	if _suppress_return:
		return
	_return_home(PAGE_MULTIPLAYER)
	_focus_control(_top_multi_button)

func _blocks_home_accept() -> bool:
	return _overlay.is_open() or _play_page.is_open() or _record_selector.is_open() or _profile_overlay.is_open() or _leaderboard_overlay.is_open() or _lan_overlay.is_open()

func _should_blur_menu() -> bool:
	return _play_page.is_open() or _record_selector.is_open() or _profile_overlay.is_open() or _leaderboard_overlay.is_open() or _lan_overlay.is_open() or _overlay.is_credits_open()

## 顶栏 tab 一律导航：不管当前在 Records / Multiplayer / Profile，点 PLAY 都翻到 Play 页。
func _on_play_nav_pressed() -> void:
	if _page == PAGE_PLAY:
		_refresh_nav_marks()
		return
	_switch_page(PAGE_PLAY)

func _open_play_page() -> void:
	_switch_page(PAGE_PLAY)

func _on_play_back_pressed() -> void:
	_switch_page(PAGE_HOME)
	_focus_control(_top_play_button)

func _on_home_solo_pressed() -> void:
	_open_records(RecordOrigin.HOME)

func _on_play_solo_pressed() -> void:
	_open_records(RecordOrigin.PLAY)

func _open_records(origin: RecordOrigin) -> void:
	_record_origin = origin
	_switch_page(PAGE_RECORDS)

func _enter_multi_flow() -> void:
	if _page == PAGE_MULTIPLAYER:
		_refresh_nav_marks()
		return
	_switch_page(PAGE_MULTIPLAYER)

func _on_profile_pressed() -> void:
	if _page == PAGE_PROFILE:
		_refresh_nav_marks()
		return
	_switch_page(PAGE_PROFILE)

func _enter_leaderboard() -> void:
	_switch_page(PAGE_RANKING)

func _on_settings_pressed() -> void:
	## 顶栏 SETTINGS 是开关键：抽屉开着再点一次就关掉（Credits 开着时先不动，交给它自己的 Esc/Back）。
	if _overlay.is_open():
		if not _overlay.is_credits_open():
			_overlay.close()
		return
	_settings_return = get_viewport().gui_get_focus_owner() as Control
	_overlay.open()
	_overlay.move_to_front()
	_top_bar.move_to_front()

func _on_home_pressed() -> void:
	if _overlay.is_open():
		_overlay.close()
	_switch_page(PAGE_HOME)
	_refresh_home_facts()

## 唯一的页面切换入口：旧页与新页同帧反向滑动，方向由 PAGE_ORDER 决定。
func _switch_page(target: StringName) -> void:
	if target == _page:
		_refresh_nav_marks()
		return
	if _switch_left > 0.0:
		_pending_page = target
		return
	var from_index: int = int(PAGE_ORDER.get(_page, 0))
	var to_index: int = int(PAGE_ORDER.get(target, 0))
	var direction: int = 1 if to_index >= from_index else -1
	_switch_left = UiAnim.PAGE_SLIDE_SEC
	_suppress_return = true
	if _page != target:
		_close_page(_page, direction)
		_set_home_slid(target != PAGE_HOME, direction)
		if target != PAGE_HOME:
			_open_page(target, direction)
		_page = target
	_suppress_return = false
	_refresh_nav_marks()

## 页面自己 Back 关掉后回到 Home：Home 从左侧滑回。
func _return_home(from: StringName) -> void:
	if _page == PAGE_HOME:
		return
	_page = PAGE_HOME
	_switch_left = UiAnim.PAGE_SLIDE_SEC
	_set_home_slid(false, -1)

## 收掉一层界面，成功返回 true。
##
## 子页 / 叠层自己带 `ui_cancel` 处理（它们走 `_input`，比本节点的 `_unhandled_input` 更早），
## 正常情况下轮不到这里。剩下的两种情况必须由主菜单兜住：
##   1) 设置抽屉开着（它不是 `_blocks_home_accept()` 的一员，且 Credits 可能盖在上面）；
##   2) 当前停在非 Home 的子页 —— 对齐 `_on_play_back_pressed()` 的观感，退回 Home。
## 都没得收才返回 false，交由调用方决定要不要退出应用。
func _back_once() -> bool:
	if _overlay.is_open():
		## `SettingsOverlay.close()` 会连带关掉盖在上面的 Credits（见其实现），
		## 所以这里不用单独判 credits。
		_overlay.close()
		return true
	if _page != PAGE_HOME:
		_return_home(_page)
		_refresh_nav_marks()
		return true
	return false

func _page_node(name: StringName) -> Node:
	match name:
		PAGE_PLAY: return _play_page
		PAGE_RECORDS: return _record_selector
		PAGE_MULTIPLAYER: return _lan_overlay
		PAGE_PROFILE: return _profile_overlay
		PAGE_RANKING: return _leaderboard_overlay
	return null

func _open_page(name: StringName, direction: int) -> void:
	var node: Node = _page_node(name)
	if node != null:
		node.call("open", direction)

func _close_page(name: StringName, direction: int) -> void:
	var node: Node = _page_node(name)
	if node == null or not node.has_method("close"):
		return
	node.call("close", direction)

## Home 舞台块与页面互斥：滑出/滑回，方向跟页面切换一致。
func _set_home_slid(slid_out: bool, direction: int) -> void:
	if slid_out == _home_slid_out:
		return
	_home_slid_out = slid_out
	var home: Control = $Home
	if slid_out:
		UiAnim.slide_out(self, home, direction)
	else:
		UiAnim.slide_in(self, home, direction)

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

func _refresh_player_labels() -> void:
	_player_name.text = PlayerProfile.get_display_name()
	_player_status.text = "Ready to play"

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
	_sync_rail_lines()

## Rail 上下两条细线与按钮行同宽。ColorRect 默认 fill，会被版心拉成 1200px，
## 比按钮（220×3 + 48×2 = 756）长出一截；场景里已把两条线改成不填充（SHRINK_BEGIN），
## 这里再按「实际可见按钮的最小宽度 + separation」定宽：
## Continue 没存档时只挂两个按钮，线也要跟着短，否则右端又会悬出一截。
func _sync_rail_lines() -> void:
	var rail: Container = _solo_button.get_parent() as Container
	if rail == null:
		return
	var separation: int = rail.get_theme_constant("separation")
	var total: float = 0.0
	var shown: int = 0
	for button: Button in [_continue_button, _solo_button, _multi_button]:
		if not button.visible:
			continue
		if shown > 0:
			total += float(separation)
		total += button.get_combined_minimum_size().x
		shown += 1
	if shown == 0:
		return
	for line: ColorRect in [_rail_top_line, _rail_bottom_line]:
		line.custom_minimum_size = Vector2(total, 1.0)

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

func _first_rail() -> Button:
	if _continue_button.visible:
		return _continue_button
	return _solo_button

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
		slot.focus_neighbor_bottom = (below if below != null else slot).get_path()
	var after_rail: Control = _secondary_focus()
	if _secondary.visible:
		var bottom: Control = _quit_button if _quit_button.visible else _last_button
		_best_button.focus_neighbor_top = slots[0].get_path()
		_best_button.focus_neighbor_bottom = bottom.get_path()
		_last_button.focus_neighbor_top = slots[0].get_path()
		_last_button.focus_neighbor_bottom = bottom.get_path()
		_best_button.focus_neighbor_right = _last_button.get_path() if _last_button.visible else _best_button.get_path()
		_last_button.focus_neighbor_left = _best_button.get_path() if _best_button.visible else _last_button.get_path()
		after_rail = _best_button if _best_button.visible else _last_button
	if _quit_button.visible:
		_quit_button.focus_neighbor_top = after_rail.get_path()
		_quit_button.focus_neighbor_bottom = _quit_button.get_path()
	_set_horizontal(_home_button, _home_button, _top_play_button)
	_set_horizontal(_top_play_button, _home_button, _top_multi_button)
	_set_horizontal(_top_multi_button, _top_play_button, _top_profile_button)
	_set_horizontal(_top_profile_button, _top_multi_button, _top_settings_button)
	_set_horizontal(_top_settings_button, _top_profile_button, _top_settings_button)
	for nav: Button in [_home_button, _top_play_button, _top_multi_button, _top_profile_button, _top_settings_button]:
		nav.focus_neighbor_bottom = slots[0].get_path()

## Quit 是否被平台藏掉。网页版 `get_tree().quit()` 退不出标签页，所以整条按钮不出现。
## 平台判定统一走 GameSettings.is_web_platform()，UI 里不再散写 OS.has_feature。
func _quit_hidden_by_platform() -> bool:
	return GameSettings.is_web_platform()

## 没有 Quit（网页版）时返回 null：调用方必须自己兜底，不要把焦点指向隐藏控件。
func _secondary_focus() -> Control:
	if _best_button.visible:
		return _best_button
	if _last_button.visible:
		return _last_button
	if _quit_button.visible:
		return _quit_button
	return null

func _set_horizontal(control: Control, left: Control, right: Control) -> void:
	control.focus_neighbor_left = left.get_path()
	control.focus_neighbor_right = right.get_path()

## 顶栏 PROFILE 项显示 display_name（不再是 "best  0"，也没有第二处名字槽）。
## 名字长度会改顶栏最小宽度，所以刷新完必须重新量一次、重算时钟放不放得下。
func refresh_profile_label() -> void:
	_top_profile_button.text = PlayerProfile.get_display_name()
	_refresh_nav_marks()
	_measure_top_bar()
	sync_top_bar_for(_logical_viewport_width())

## ---- UI Scale 响应式 ----
## 200% UI Scale 会把 1920x1080 的逻辑视口压成 960x540。场景里写死的 margin_right=672
## 编码的是「1920 下版心 1200px」，到 960 会把内容列压到 240px，容器装不下自己的最小宽度
## 就整块居中溢出（左边 CONTINUE 被切掉一半、右边顶栏时钟被切）。这里按视口重算。

func _sync_responsive() -> void:
	sync_content_width_for(_logical_viewport_width())

func _logical_viewport_width() -> float:
	return get_viewport_rect().size.x

## 参数化版本：测试要能强制 960（UI Scale 200%）这一档，不是碰运气。
func sync_content_width_for(viewport_width: float) -> void:
	if _home != null:
		## MarginContainer 的 margin_right 等于「-offset_right」：1920 -> 672（旧值一字不变），
		## 960 -> 48。margin 不能为负，所以取下限 CONTENT_MARGIN。
		var offset_right: float = UiFit.content_offset_right(viewport_width, CONTENT_MARGIN, CONTENT_MAX_WIDTH)
		_home.add_theme_constant_override("margin_right", int(maxf(CONTENT_MARGIN, -offset_right)))
	sync_top_bar_for(viewport_width)

## 顶栏整排放不下时先摘掉右端时钟：它只报时，不是导航。不摘就是整排居中溢出，
## 左边 HOME 被切、右边时钟被切 —— 两个都看不见，比少个时钟更糟。
## 名字越长 PROFILE 越宽，所以按实测最小宽度判，不写死 1084。
func sync_top_bar_for(viewport_width: float) -> void:
	if _time_box == null:
		return
	_time_box.visible = _top_bar_full_min <= viewport_width + 0.5

## 量两档最小宽度：带时钟（full）与只留导航（nav）。容器的最小宽度缓存必须先标脏再读。
func _measure_top_bar() -> void:
	if _time_box == null or _top_bar == null:
		return
	_time_box.visible = true
	_top_bar.update_minimum_size()
	_top_bar_full_min = _top_bar.get_combined_minimum_size().x
	_time_box.visible = false
	_top_bar.update_minimum_size()
	_top_bar_nav_min = _top_bar.get_combined_minimum_size().x
	_time_box.visible = true

func get_top_bar_full_min_width() -> float:
	return _top_bar_full_min

func get_top_bar_nav_min_width() -> float:
	return _top_bar_nav_min

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
		if mark != null:
			mark.visible = nav == current
		nav.add_theme_color_override("font_color", UiType.INK if nav == current else UiType.MUTED)

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
