extends Control
class_name SettingsOverlay

## osu 式设置抽屉：左侧目录锚点，右侧一篇长文档。当前节可点，其它节压暗。
const IN_USE_FLASH_SEC: float = 0.6
const SIDEBAR_RATIO: float = 1.0 / 7.0
## 面板占比：0.4 那一档在 200% UI Scale（逻辑 540）下只剩 ~187px，绑定行必然溢出。
## 0.55 是「面板微宽」——但真正兜底的是下面的 PANEL_MIN_W，比例档只在宽屏上生效。
const PANEL_OF_REMAINDER: float = 0.55
## 面板最小宽度 = 一行绑定并排两个按钮所需的宽度 + Body 的左右缩进：
##   按钮下限 88 × 2 + 按钮间距 12 + Body 缩进 52 = 240。
## 200% UI Scale 下逻辑视口只剩 540，0.55 档是 0.55 × (540-190) ≈ 192px，
## 不给下限就会算出容不下两个按钮的面板。取 240 后 540 下抽屉 = 190 + 240 = 430
## （屏幕的 79.6%，右侧留出 110px 可见背景），不会像旧的 560 下限那样铺满整屏。
## 240 同时是「零裁切」的下界：控制面板内宽 = 240 - 52 = 188，正好放下 Dash 那行的
## 两个 chip（88 + 12 + 88）；Display 最宽的 Fullscreen 行要 178；折行后的长文案
## 最长一行 <= 188。1920 宽下 0.55 档本来就是 905 (> 240)，所以这个下限不影响原设计。
const PANEL_MIN_W: float = 240.0
## 目录栏最小宽度。一个 tab = 左缩进 32 + 图标 32 + 间距 16 + 文案 + 右缩进 12，
## 文案最宽是 "Controls"（22px 粗体实测 90px）→ 32+32+16+90+12 = 182。
## 取 190 留一点余量，否则最宽的 tab 文案会被压掉。1920 宽下 1/7 本来就是 274，不受影响。
const SIDEBAR_MIN_W: float = 190.0
## 绑定按钮的最小宽度。旧的固定 160 在窄面板里会把行顶出去；改成 88 并配合
## SIZE_EXPAND_FILL，按钮可以随面板收缩，"W" / "SPACE" 这类短标签仍然读得出来。
const BIND_BTN_MIN_W: float = 88.0
## 两个绑定按钮之间的间距（也是竖排时的行距）。
const BIND_GAP: float = 12.0
## SettingsSection.Body 的左右缩进（20 + 32），面板宽减去它才是绑定行的可用宽度。
const BODY_INSET: float = 52.0
## 手动折行时留的安全余量：Label 画字带 outline（SettingsHeader outline_size=2），
## get_string_size() 不含 outline，所以按 可用宽度 - 这个余量 折行，避免折出来仍然超宽。
const WRAP_SAFE_GAP: float = 8.0
## 折行时宁可让这一行用满可用宽度、也不要让它落到下一行行首的短分隔符。
const WRAP_TRAILING_TOKENS: PackedStringArray = ["/", "|", "-", "+"]
## 下拉选择行：面板内宽比这个还宽时（100% UI Scale 的桌面），OptionButton 保持 160 宽；
## 更窄时（200% 手机）让它占满自己那一行。
const CHOICE_OPTION_W: float = 160.0
const CHOICE_STACK_BELOW: float = 360.0
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
var _bind_status: Label
var _scroll_current: float = 0.0
var _scroll_target: float = 0.0
var _distance_decay: float = DISTANCE_DECAY_SCROLL
var _user_scrolling: bool = false
var _clicked_section: SettingsSection = null
var _current_section: SettingsSection = null
var _close_on_up: bool = false
var _sections: Array[SettingsSection] = []
var _navs: Array[SettingsNavButton] = []
## Controls 每个绑定行里的按钮网格（列数随面板宽度在 1 / 2 之间切）。
var _bind_grids: Array[GridContainer] = []
## 需要按可用宽度手动折行的 Label -> 不含换行的原文。
## Godot 的 Label 最小宽度永远是整段文字的宽度（autowrap 也不会让它变小），
## 窄面板下这些文案会把 SettingsSection.Body 撑宽、被 Panel.clip_contents 裁掉。
var _wrapped_sources: Dictionary = {}
## Touch Controls / Manual Fire 的 OptionButton（宽度随面板宽在「占满一行 / 固定 160」间切）。
var _choice_options: Array[OptionButton] = []
## Manual Fire 行只在 Touch Controls = AUTO / ON 时出现：OFF 时虚拟按键整层不存在，
## 这行既不该显示，也不该被搜索命中。_touch_hint 跟随同一开关。
var _manual_fire_row: VBoxContainer = null
var _touch_hint: Label = null
var _touch_mode_option: OptionButton = null
var _manual_fire_option: OptionButton = null
var _sfx_gate: Dictionary = {}
## Touch drag scroll：区分 tap / drag，只有越过 slop 才接管为滚动。
const TOUCH_SLOP: float = 12.0
var _touch_index: int = -1
var _touch_origin: Vector2 = Vector2.ZERO
var _touch_dragging: bool = false

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
@onready var _error_sfx: AudioStreamPlayer = $ErrorSfx
@onready var _credits: CreditsOverlay = $CreditsOverlay

func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(false)
	_preview.stream = GameAudio.load_wav("res://audio/click.wav")
	_hover_sfx.stream = GameAudio.load_wav("res://audio/ui_hover.wav")
	_click_sfx.stream = GameAudio.load_wav("res://audio/ui_click.wav")
	_back_sfx.stream = GameAudio.load_wav("res://audio/ui_back.wav")
	_error_sfx.stream = GameAudio.load_wav("res://audio/click.wav")
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
	_register_responsive_text()
	_audio_nav.pressed.connect(_on_nav_pressed.bind(_audio_section))
	_display_nav.pressed.connect(_on_nav_pressed.bind(_display_section))
	_controls_nav.pressed.connect(_on_nav_pressed.bind(_controls_section))
	_data_nav.pressed.connect(_on_nav_pressed.bind(_data_section))
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
	_clear_bind_status()
	_open = true
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

func close() -> void:
	if not _open:
		return
	_cancel_listen()
	if _credits != null and _credits.is_open():
		_credits.close()
	_open = false
	_close_on_up = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process_input(false)
	set_process_unhandled_input(false)
	_play_close_animation()
	_refocus_menu()

func _refocus_menu() -> void:
	var menu: MainMenu = get_parent() as MainMenu
	if menu != null:
		menu.restore_after_settings()

func _play_open_animation() -> void:
	UiAnim.kill_tween(_anim_tween)
	_anim_tween = UiAnim.enter_drawer(self, _drawer, _dimmer, _content, _navs, _drawer_w())

func _play_close_animation() -> void:
	UiAnim.kill_tween(_anim_tween)
	_anim_tween = UiAnim.exit_drawer(self, _drawer, _dimmer, _drawer_w())
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
	if _handle_touch_scroll(event):
		get_viewport().set_input_as_handled()
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

## 真正的触屏滚动：InputEventScreenDrag 垂直位移 -> _scroll_target。
## 低于 TOUCH_SLOP 视为 tap，交还给 Button/Slider/OptionButton；越过 slop 后吞掉本次事件。
## 返回 true 表示事件已被本层消费，调用方应 set_input_as_handled()。
func _handle_touch_scroll(event: InputEvent) -> bool:
	var touch: InputEventScreenTouch = event as InputEventScreenTouch
	if touch != null:
		if touch.pressed:
			if _point_over_content(touch.position):
				_begin_touch(touch.index, touch.position)
			return false
		if touch.index != _touch_index:
			return false
		var was_dragging: bool = _touch_dragging
		_reset_touch_tracking()
		return was_dragging
	var drag: InputEventScreenDrag = event as InputEventScreenDrag
	if drag == null or drag.index != _touch_index:
		return false
	## screen_relative 是未受 Content Scale 影响的屏幕坐标增量，比 relative 更适合触控拖动。
	if not _touch_dragging:
		if absf(drag.position.y - _touch_origin.y) < TOUCH_SLOP:
			return false
		_touch_dragging = true
		return true
	var delta_y: float = drag.screen_relative.y
	## 触控直接拖内容：手指下移内容跟着下移（target 减小），手指上移内容上滚（target 增大）。
	if not is_zero_approx(delta_y):
		_scroll_by(-delta_y, true)
	return true

func _begin_touch(index: int, position: Vector2) -> void:
	_touch_index = index
	_touch_origin = position
	_touch_dragging = false

func _reset_touch_tracking() -> void:
	_touch_index = -1
	_touch_dragging = false

func _point_over_content(position: Vector2) -> bool:
	if _panel == null:
		return false
	return _panel.get_global_rect().has_point(position)

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
	var screen_w: float = _screen_w()
	return clampf(screen_w * SIDEBAR_RATIO, minf(SIDEBAR_MIN_W, screen_w), screen_w)

func _panel_w() -> float:
	var available: float = _screen_w() - _sidebar_w()
	return clampf(available * PANEL_OF_REMAINDER, minf(PANEL_MIN_W, available), available)

func _drawer_w() -> float:
	return _sidebar_w() + _panel_w()

## 绑定行真正能用的宽度：面板宽减去 SettingsSection.Body 的左右缩进。
func _bind_body_w() -> float:
	return maxf(0.0, _panel_w() - BODY_INSET)

## 网格里所有按钮并排所需的宽度。不能只算 88 × 个数：Button 的最小宽度还包含文案
## （"D-pad Down" 这类长标签比 88 宽），只按 custom_minimum_size 算会得出偏小的值，
## 结果按钮被挤到容器外。这里按子节点真实最小宽度求和。
func _bind_grid_w(grid: GridContainer) -> float:
	if grid == null:
		return 0.0
	var sep: float = float(grid.get_theme_constant("h_separation"))
	var total: float = 0.0
	var count: int = 0
	for child: Node in grid.get_children():
		var item: Control = child as Control
		if item == null:
			continue
		total += item.get_combined_minimum_size().x
		count += 1
	if count > 1:
		total += sep * float(count - 1)
	return total

## 面板宽度变化后重排绑定行：两个按钮并排放得下就用 2 列，放不下（长手柄标签）就退回
## 1 列竖排。两种情况下行的最小宽度都不会超过 body 可用宽度，所以不会被面板裁掉。
func _apply_bind_columns() -> void:
	var body_w: float = _bind_body_w()
	for entry: Variant in _bind_grids:
		var grid: GridContainer = entry as GridContainer
		if grid == null or not is_instance_valid(grid):
			continue
		var columns: int = 2 if _bind_grid_w(grid) <= body_w + 0.5 else 1
		if grid.columns != columns:
			grid.columns = columns

## 下拉选择行的 OptionButton：窄面板占满一行，宽面板收成 160 宽。
func _apply_choice_options() -> void:
	var body_w: float = _bind_body_w()
	for entry: Variant in _choice_options:
		var option: OptionButton = entry as OptionButton
		if option == null or not is_instance_valid(option):
			continue
		if body_w >= CHOICE_STACK_BELOW:
			option.custom_minimum_size = Vector2(CHOICE_OPTION_W, 44.0)
			option.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		else:
			option.custom_minimum_size = Vector2(0.0, 44.0)
			option.size_flags_horizontal = Control.SIZE_EXPAND_FILL

## 登记一个「窄面板时要折行」的 Label。原文存在 _wrapped_sources 里，宽度变化时重排。
func _wrap_label(label: Label) -> void:
	if label == null or _wrapped_sources.has(label):
		return
	_wrapped_sources[label] = label.text

## 运行时改文案的折行 Label（UI Scale / Render Resolution 的读数）：更新原文后立即重排。
func _set_wrapped_text(label: Label, text: String) -> void:
	if _wrapped_sources.has(label):
		_wrapped_sources[label] = text
		_apply_wrapped_texts()
		return
	label.text = text

## 按当前可用宽度重排所有折行文案。宽屏下原文本来就放得下一行，会原样还原。
func _apply_wrapped_texts() -> void:
	if _wrapped_sources.is_empty():
		return
	var width: float = maxf(1.0, _bind_body_w())
	for entry: Variant in _wrapped_sources.keys():
		var label: Label = entry as Label
		if label == null or not is_instance_valid(label):
			continue
		label.text = _wrapped_text(label, str(_wrapped_sources[label]), width)

## 贪心按空格折行，保证每行不超过 width（单个超长单词无法再拆，保持原样）。
func _wrapped_text(label: Label, text: String, width: float) -> String:
	var font: Font = label.get_theme_font("font")
	if font == null or width <= 1.0 or text.is_empty():
		return text
	var font_size: int = label.get_theme_font_size("font_size")
	if _line_w(font, text, font_size) <= width:
		return text
	var limit: float = maxf(1.0, width - WRAP_SAFE_GAP)
	var out: String = ""
	var line: String = ""
	for word: String in text.split(" ", false):
		if line.is_empty():
			line = word
			continue
		var candidate: String = line + " " + word
		var candidate_w: float = _line_w(font, candidate, font_size)
		if candidate_w <= limit or (WRAP_TRAILING_TOKENS.has(word) and candidate_w <= width):
			line = candidate
			continue
		out += line + "\n"
		line = word
	return out + line

func _line_w(font: Font, text: String, font_size: int) -> float:
	return font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x

## 宽按钮（RESTORE DEFAULTS / HOLD TO DELETE ALL DATA）在窄面板里也必须能收缩：
## Button 开了 autowrap 后最小宽度就只剩 stylebox 内边距，文字换成多行、按钮长高，
## 不会再把 Body 撑出去，也不会像 clip_text 那样把字裁掉。
func _make_wide_button_shrinkable(button: Button) -> void:
	if button == null:
		return
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.custom_minimum_size = Vector2(0.0, button.custom_minimum_size.y)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL

## 把场景里固定宽度的长文案 / 宽按钮交给响应式处理（都在代码里做，避免和其它
## 并发改动抢 settings_overlay.tscn）。MSAA 的 OptionButton（72px）本来就放得下。
func _register_responsive_text() -> void:
	_wrap_label(_render_scale_label)
	_wrap_label(_ui_scale_label)
	_wrap_label(_render_scale_slider.get_parent().get_node_or_null("RenderScaleHint") as Label)
	_wrap_label(_data_section.body.get_node_or_null("Warning") as Label)
	_wrap_label(_touch_hint)
	_make_wide_button_shrinkable(_delete_button)

func _apply_split_layout() -> void:
	var side: float = _sidebar_w()
	var total: float = _drawer_w()
	_sidebar.offset_left = 0.0
	_sidebar.offset_right = side
	_panel.offset_left = side
	_panel.offset_right = total
	_apply_bind_columns()
	_apply_choice_options()
	_apply_wrapped_texts()

func _apply_drawer_layout() -> void:
	_apply_split_layout()
	## 折行后 section 的高度取决于当时宽度，宽度一变就必须重算高度（否则文案会叠在一起）。
	_fit_sections()
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
		return
	close()

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
			var show: bool = (header_hit or _matches(child, query)) and _search_row_allowed(child)
			item.visible = show
			if show:
				any_item = true
		section.visible = any_item
		section._fit()
	for i: int in _sections.size():
		_navs[i].modulate.a = 1.0 if _sections[i].visible else 0.28

## 被 Touch Controls 开关挡住的行不显示、也不参与搜索命中。
func _search_row_allowed(node: Node) -> bool:
	if node == _manual_fire_row or node == _touch_hint:
		return GameSettings.is_touch_controls_option_visible()
	return true

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
	## Touch 两个下拉的选中值也要跟当前 settings 对齐（open() 时重进抽屉不会显示旧值）。
	## OptionButton.select() 不发 item_selected，不会反向写回。
	if _touch_mode_option != null:
		_touch_mode_option.select(int(GameSettings.get_touch_controls_mode()))
	if _manual_fire_option != null:
		_manual_fire_option.select(1 if GameSettings.is_touch_manual_fire() else 0)
	_sync_touch_choice_visibility()

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

func _on_touch_controls_selected(index: int) -> void:
	_play_click()
	GameSettings.set_touch_controls_mode(index)
	GameSettings.apply()
	GameSettings.save_to_disk()
	## 开关本身决定 Manual Fire 行是否出现：立刻按新状态重排（搜索态一起刷新）。
	if _touch_mode_option != null:
		_touch_mode_option.select(index)
	_sync_touch_choice_visibility()
	_apply_search(_search.text)
	_fit_sections()
	_layout_scroll()

func _on_touch_manual_fire_selected(index: int) -> void:
	_play_click()
	GameSettings.set_touch_manual_fire(index == 1)
	GameSettings.apply()
	GameSettings.save_to_disk()

## Manual Fire 行 + 提示只在 Touch Controls = AUTO / ON 时出现。
## 只切 visible，不删节点：OptionButton 的选中值与宽度档位原样保留。
func _sync_touch_choice_visibility() -> void:
	var enabled: bool = GameSettings.is_touch_controls_option_visible()
	if _manual_fire_row != null:
		_manual_fire_row.visible = enabled
	if _touch_hint != null:
		_touch_hint.visible = enabled
		_set_wrapped_text(
			_touch_hint,
			"ON adds a FIRE button; the right pad then only aims." if enabled else "")

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
	
	# Touch Controls Mode
	var touch_option: OptionButton = OptionButton.new()
	touch_option.add_item("AUTO")
	touch_option.add_item("ON")
	touch_option.add_item("OFF")
	touch_option.select(int(GameSettings.get_touch_controls_mode()))
	touch_option.item_selected.connect(_on_touch_controls_selected)
	_touch_mode_option = touch_option
	body.add_child(_build_choice_row("Touch Controls", "touch controls mobile on screen", touch_option))

	# Manual Fire Button（默认 OFF：右摇杆 = Aim + Fire）。
	# 只有 Touch Controls = AUTO / ON 才显示这一行：OFF 时整层虚拟按键都不存在。
	var fire_option: OptionButton = OptionButton.new()
	fire_option.add_item("OFF")
	fire_option.add_item("ON")
	fire_option.select(1 if GameSettings.is_touch_manual_fire() else 0)
	fire_option.item_selected.connect(_on_touch_manual_fire_selected)
	_manual_fire_option = fire_option
	_manual_fire_row = _build_choice_row(
		"Manual Fire Button", "touch manual fire button aim stick", fire_option)
	body.add_child(_manual_fire_row)

	var hint: Label = Label.new()
	hint.theme_type_variation = &"RunSummaryHint"
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_touch_hint = hint
	body.add_child(hint)
	_sync_touch_choice_visibility()

	var bind_status: Label = Label.new()
	bind_status.name = "BindStatus"
	bind_status.theme_type_variation = &"Caption"
	bind_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bind_status.text = ""
	body.add_child(bind_status)
	bind_status.owner = self
	bind_status.unique_name_in_owner = true
	_bind_status = bind_status
	for action: String in GameSettings.REBINDABLE_ACTIONS:
		## 每个绑定 = 两行：第一行动作名，第二行键盘/手柄按钮（放得下就并排，放不下就竖排）。
		var row: VBoxContainer = VBoxContainer.new()
		row.set_meta("settings_search", GameSettings.action_display_name(action))
		row.set_meta("settings_bind_row", true)
		row.mouse_filter = Control.MOUSE_FILTER_STOP
		row.add_theme_constant_override("separation", 6)
		var name_label: Label = Label.new()
		name_label.theme_type_variation = &"SettingsHeader"
		name_label.text = GameSettings.action_display_name(action)
		name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var chips: GridContainer = GridContainer.new()
		chips.name = "Chips"
		chips.mouse_filter = Control.MOUSE_FILTER_STOP
		chips.add_theme_constant_override("h_separation", int(BIND_GAP))
		chips.add_theme_constant_override("v_separation", int(BIND_GAP))
		var button: Button = _make_bind_button(GameSettings.key_label_for_action(action))
		button.pressed.connect(_on_rebind_pressed.bind(button))
		_action_by_button[button] = action
		chips.add_child(button)
		if GameSettings.REBINDABLE_JOY_ACTIONS.has(action):
			var pad: Button = _make_bind_button(GameSettings.joy_label_for_action(action))
			pad.set_meta("settings_search", "gamepad joypad pad dash gun")
			pad.pressed.connect(_on_rebind_joy_pressed.bind(pad))
			_joy_button_by_action[pad] = action
			chips.add_child(pad)
		row.add_child(name_label)
		row.add_child(chips)
		_bind_grids.append(chips)
		body.add_child(row)
	_apply_bind_columns()
	var restore: Button = Button.new()
	restore.name = "RestoreButton"
	restore.theme_type_variation = &"PillNeutral"
	restore.custom_minimum_size = Vector2(0, 48)
	restore.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	restore.mouse_filter = Control.MOUSE_FILTER_STOP
	restore.text = "RESTORE DEFAULTS"
	restore.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	restore.set_meta("settings_search", "restore defaults reset keys gamepad")
	restore.pressed.connect(_on_restore_pressed)
	body.add_child(restore)
	restore.owner = self
	restore.unique_name_in_owner = true
	_controls_section._fit()

## 下拉选择行：标签一行、OptionButton 一行（占满宽度）。
## 窄面板下 161/199 的标签 + 160 的 OptionButton 并排是放不下的（旧的 333/371），
## 拆成两行后行的最小宽度 = max(标签, 控件)，再长也让标签自己折行。
func _build_choice_row(text: String, search_meta: String, option: OptionButton) -> VBoxContainer:
	var row: VBoxContainer = VBoxContainer.new()
	row.set_meta("settings_search", search_meta)
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	row.add_theme_constant_override("separation", 6)
	var label: Label = Label.new()
	label.theme_type_variation = &"SettingsHeader"
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	option.theme_type_variation = ""
	option.custom_minimum_size = Vector2(0, 44)
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	option.mouse_filter = Control.MOUSE_FILTER_STOP
	row.add_child(label)
	row.add_child(option)
	_choice_options.append(option)
	_wrap_label(label)
	return row

func _make_bind_button(label: String) -> Button:
	var button: Button = Button.new()
	button.theme_type_variation = &"OfferButtonSmall"
	button.custom_minimum_size = Vector2(BIND_BTN_MIN_W, 44)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.text = label
	return button

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
	_clear_bind_status()

func _handle_listen_event(event: InputEvent) -> void:
	var key_event: InputEventKey = event as InputEventKey
	if key_event != null and key_event.pressed and not key_event.echo:
		if _listening_joy:
			if key_event.keycode == KEY_ESCAPE or event.is_action_pressed("ui_cancel"):
				_cancel_listen()
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
		return
	_listening_action = ""
	_listening_button = null
	_listening_joy = false
	if button == null or not is_instance_valid(button):
		return
	var keycode: int = key_event.physical_keycode
	var occupier: String = GameSettings.find_key_conflict(action, keycode)
	if occupier.is_empty() and GameSettings.set_key_for_action(action, keycode):
		GameSettings.apply()
		GameSettings.save_to_disk()
		button.text = GameSettings.key_label_for_action(action)
		_clear_bind_status()
		return
	_fail_bind(button, action, _key_conflict_text(keycode, occupier))

func _handle_rebind_joy(joy_event: InputEventJoypadButton) -> void:
	var action: String = _listening_action
	var button: Button = _listening_button
	_listening_action = ""
	_listening_button = null
	_listening_joy = false
	if button == null or not is_instance_valid(button):
		return
	var joy_button: int = joy_event.button_index
	var conflict: String = GameSettings.find_joy_conflict(action, joy_button)
	if conflict.is_empty() and GameSettings.set_joy_button_for_action(action, joy_button):
		GameSettings.save_to_disk()
		button.text = GameSettings.joy_label_for_action(action)
		_clear_bind_status()
		return
	_fail_bind(button, action, _joy_conflict_text(joy_button, conflict))

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

func _on_restore_pressed() -> void:
	_play_click()
	_cancel_listen()
	GameSettings.reset_controls()
	GameSettings.apply()
	GameSettings.save_to_disk()
	_refresh_key_labels()
	_set_bind_status("Controls restored.")

func _clear_bind_status() -> void:
	_set_bind_status("")

func _set_bind_status(text: String) -> void:
	if _bind_status == null:
		return
	_bind_status.text = text

func _key_conflict_text(keycode: int, occupier: String) -> String:
	if occupier.is_empty():
		return ""
	return "%s is used by %s." % [OS.get_keycode_string(keycode as Key), GameSettings.action_display_name(occupier)]

func _joy_conflict_text(joy_button: int, conflict: String) -> String:
	if conflict == "reserved":
		if joy_button == JOY_BUTTON_START:
			return "Start is reserved."
		if joy_button == JOY_BUTTON_GUIDE:
			return "Guide is reserved."
		return ""
	if conflict.is_empty() or conflict == "invalid":
		return ""
	return "%s is used by %s." % [GameSettings.joy_label_for_action(conflict), GameSettings.action_display_name(conflict)]

func _fail_bind(button: Button, action: String, status: String) -> void:
	button.text = "IN USE"
	_set_bind_status(status)
	_play_error()
	var tree: SceneTree = get_tree()
	if tree == null:
		return
	tree.create_timer(IN_USE_FLASH_SEC).timeout.connect(_restore_bind_label.bind(button, action))

func _sync_render_scale_label(slider_value: float) -> void:
	_set_wrapped_text(_render_scale_label, "Render Resolution  %d%%" % int(slider_value))

func _sync_ui_scale_label(slider_value: float) -> void:
	_set_wrapped_text(_ui_scale_label, "UI Scale  %d%%" % int(slider_value))

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

func _play_error() -> void:
	_play_stream(_error_sfx, &"error")

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
