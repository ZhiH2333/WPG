extends Control
class_name TestBuildNotice

## 测试版提示页：只在网页版出现，出现时后台已经在加载主菜单。
##
## 出场顺序（见 `ui/boot_screen.gd`）：
##   1. 开屏 `_ready()` 立刻把这一页盖在最上面（纯黑底，玩家只看到这一页），
##      同一帧继续在线程里加载 `res://ui/main_menu.tscn` —— 主场景已经在加载，
##      但没有挂进树，所以不显示。
##   2. 玩家点「开始游玩」。这一次点击是真正的用户手势，`GameSettings.apply()`
##      就在这个回调里申请全屏：浏览器只允许在用户手势里进全屏，放到 `_process`
##      里申请会被静默拒绝。主菜单还没加载完时，按钮切成「正在加载…」等它。
##   3. 交给 `boot_screen` 交叉渐入主菜单。
##
## 中文必须用 `res://ui/fonts/wpg_notice_cjk_*.ttf`：Web 导出的系统字体回退不生效
## （godotengine/godot#78921），仓库又没有自带中文字体，用主题字会渲染成空白。
## 这两份子集由 `tools/fonts/subset_notice_font.py` 从本文件与
## `ui/test_build_notice.tscn` 的文案里扫出字形，改文案后要重跑一次。

## 玩家确认过设置、可以进主菜单了。宿主负责换场。
signal started

const LOADING_TEXT := "正在加载…"
## 整页左右留白（逻辑像素）。
const PAGE_MARGIN: float = 40.0
## 内容列最大宽度。1920 宽下不再拉成一行长文；窄视口由 UiFit 收窄。
const MAX_COLUMN_W: float = 720.0
const TOUCH_HINT_ON := "ON adds a FIRE button; the right pad then only aims."

var _started: bool = false

@onready var _column: VBoxContainer = %Column
@onready var _lead: Label = %Lead
@onready var _fullscreen_check: CheckBox = %FullscreenCheck
@onready var _render_label: Label = %RenderScaleLabel
@onready var _render_slider: HSlider = %RenderScaleSlider
@onready var _ui_label: Label = %UiScaleLabel
@onready var _ui_slider: HSlider = %UiScaleSlider
@onready var _touch_option: OptionButton = %TouchOption
@onready var _touch_hint: Label = %TouchHint
@onready var _manual_fire_row: VBoxContainer = %ManualFireRow
@onready var _manual_fire_option: OptionButton = %ManualFireOption
@onready var _mute_check: CheckBox = %MuteCheck
@onready var _start_button: Button = %StartButton


## 只在网页版、且玩家没有勾过「不再提示」时出现。桌面版永远不出现。
static func should_show() -> bool:
	return GameSettings.is_web_platform() and not GameSettings.is_test_build_notice_muted()


func _ready() -> void:
	_fill_options()
	_auto_check_fullscreen()
	_sync_from_settings()
	_fullscreen_check.toggled.connect(_on_fullscreen_toggled)
	_render_slider.value_changed.connect(_on_render_scale_changed)
	_render_slider.drag_ended.connect(_on_slider_drag_ended)
	_ui_slider.value_changed.connect(_on_ui_scale_changed)
	_ui_slider.drag_ended.connect(_on_slider_drag_ended)
	_touch_option.item_selected.connect(_on_touch_controls_selected)
	_manual_fire_option.item_selected.connect(_on_manual_fire_selected)
	_start_button.pressed.connect(_on_start_pressed)
	resized.connect(_layout)
	_layout()
	# 键盘 / 手柄直接落在「开始游玩」上；延后一帧，免得被宿主的焦点抢走。
	_start_button.call_deferred("grab_focus")


func has_started() -> bool:
	return _started


## 主菜单还在后台加载：玩家已经点过，别让他点第二次。
func lock_for_loading() -> void:
	if not _started:
		return
	_start_button.text = LOADING_TEXT
	_start_button.disabled = true
	_set_settings_enabled(false)


## 两个下拉的档位在代码里建，和 ui/settings_overlay.gd 的 Controls 区保持一致，
## 免得选项文案出现第二份。
func _fill_options() -> void:
	_touch_option.clear()
	_touch_option.add_item("AUTO")
	_touch_option.add_item("ON")
	_touch_option.add_item("OFF")
	_manual_fire_option.clear()
	_manual_fire_option.add_item("OFF")
	_manual_fire_option.add_item("ON")


## 网页版进这一页就把全屏勾上。只写设置、不在这里调 apply()：
## 进全屏要用户手势，真正的申请发生在点「开始游玩」或手动切换复选框时。
func _auto_check_fullscreen() -> void:
	if GameSettings.is_web_platform():
		GameSettings.set_fullscreen(true)


func _sync_from_settings() -> void:
	_fullscreen_check.set_pressed_no_signal(GameSettings.is_fullscreen())
	var render: float = GameSettings.get_render_scale() * 100.0
	_render_slider.set_value_no_signal(render)
	_sync_render_label(render)
	var ui: float = GameSettings.get_ui_scale() * 100.0
	_ui_slider.set_value_no_signal(ui)
	_sync_ui_label(ui)
	_touch_option.select(int(GameSettings.get_touch_controls_mode()))
	_manual_fire_option.select(1 if GameSettings.is_touch_manual_fire() else 0)
	_mute_check.set_pressed_no_signal(GameSettings.is_test_build_notice_muted())
	_sync_touch_visibility()


## 内容列宽度跟着逻辑视口走：UI Scale 拉到 200% 时视口只剩 960 逻辑宽，
## 固定 720 会把 SettingsHeader 那些行顶出屏幕。
func _layout() -> void:
	sync_content_width_for(UiFit.visible_size(self).x)


## 按给定逻辑视口宽度重算内容列宽度。参数化是为了让测试能强制 960 / 540 这两档，
## 而不是只能在 headless 默认视口下碰运气（与 winner_page 同一套约定）。
func sync_content_width_for(viewport_width: float) -> void:
	if _column == null:
		return
	_column.custom_minimum_size = Vector2(
		UiFit.content_width_for(viewport_width, PAGE_MARGIN, MAX_COLUMN_W), 0.0
	)


## Manual Fire 只在 Touch Controls = AUTO / ON 时有意义：OFF 时虚拟按键整层不存在。
func _sync_touch_visibility() -> void:
	var enabled: bool = GameSettings.is_touch_controls_option_visible()
	_manual_fire_row.visible = enabled
	_touch_hint.visible = enabled
	_touch_hint.text = TOUCH_HINT_ON if enabled else ""


func _set_settings_enabled(enabled: bool) -> void:
	_fullscreen_check.disabled = not enabled
	_render_slider.editable = enabled
	_ui_slider.editable = enabled
	_touch_option.disabled = not enabled
	_manual_fire_option.disabled = not enabled
	_mute_check.disabled = not enabled


func _sync_render_label(value: float) -> void:
	_render_label.text = "Render Resolution  %d%%" % int(value)


func _sync_ui_label(value: float) -> void:
	_ui_label.text = "UI Scale  %d%%" % int(value)


func _on_fullscreen_toggled(pressed: bool) -> void:
	GameSettings.set_fullscreen(pressed)
	# 这次切换本身就是用户手势，网页端能借此真的进全屏。
	GameSettings.apply()
	GameSettings.save_to_disk()


func _on_render_scale_changed(value: float) -> void:
	GameSettings.set_render_scale(value / 100.0)
	_sync_render_label(value)


func _on_ui_scale_changed(value: float) -> void:
	GameSettings.set_ui_scale(value / 100.0)
	GameSettings.apply()
	_sync_ui_label(value)
	_layout()


func _on_slider_drag_ended(_value_changed: bool) -> void:
	GameSettings.save_to_disk()


func _on_touch_controls_selected(index: int) -> void:
	GameSettings.set_touch_controls_mode(index)
	GameSettings.apply()
	GameSettings.save_to_disk()
	_touch_option.select(index)
	_sync_touch_visibility()


func _on_manual_fire_selected(index: int) -> void:
	GameSettings.set_touch_manual_fire(index == 1)
	GameSettings.apply()
	GameSettings.save_to_disk()


func _on_start_pressed() -> void:
	if _started:
		return
	_started = true
	GameSettings.set_test_build_notice_muted(_mute_check.button_pressed)
	GameSettings.apply()
	GameSettings.save_to_disk()
	_set_settings_enabled(false)
	started.emit()
