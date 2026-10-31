extends Control
class_name MultiplayerTestNotice

## 主菜单「多人」入口的测试期提示：联机尚未正式可用，点「继续测试」才进现有多人界面。
## 形态对齐 RoomNotice（dimmer + FloatingPanel），不用 AcceptDialog。
## 文案中英双语：无完整 i18n 包时按系统语言 / locale_override 选择；中文走 notice CJK 子集字体。

signal confirmed
signal cancelled

const MSG_EN := "Online multiplayer is currently unavailable! For testing only."
const MSG_ZH := "多人联机目前不可用！仅可用于测试。"
const BTN_EN := "Continue testing"
const BTN_ZH := "继续测试"
const MODAL_PREFERRED := Vector2(560, 220)
const MODAL_MIN := Vector2(420, 160)
const CJK_BOLD := preload("res://ui/fonts/wpg_notice_cjk_bold.ttf")
const CJK_REGULAR := preload("res://ui/fonts/wpg_notice_cjk_regular.ttf")

## 测试可强制语言（"en" / "zh_CN"）；空字符串 = 跟系统。
static var locale_override: String = ""

var _open: bool = false
var _enter_tween: Tween

@onready var _dimmer: ColorRect = $Dimmer
@onready var _center: CenterContainer = $Center
@onready var _panel: PanelContainer = $Center/Panel
@onready var _message: Label = $Center/Panel/Column/Message
@onready var _continue_button: Button = $Center/Panel/Column/Continue

func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dimmer.visible = false
	_center.visible = false
	_continue_button.pressed.connect(_on_continue_pressed)
	_dimmer.gui_input.connect(_on_dimmer_gui_input)
	UiFit.connect_refit(self, _fit_panel)

func is_open() -> bool:
	return _open

## 当前会展示的提示正文（供测试断言，不依赖场景树）。
static func message_for_locale(locale: String = "") -> String:
	return MSG_ZH if _is_zh(_resolve_locale(locale)) else MSG_EN

## 当前会展示的按钮文案。
static func continue_label_for_locale(locale: String = "") -> String:
	return BTN_ZH if _is_zh(_resolve_locale(locale)) else BTN_EN

static func supported_locales() -> PackedStringArray:
	return PackedStringArray(["en", "zh_CN"])

func open() -> void:
	if _open:
		return
	_open = true
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_apply_copy()
	_dimmer.modulate.a = 0.0
	_panel.modulate.a = 0.0
	_panel.scale = Vector2.ONE
	_dimmer.visible = true
	_center.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_fit_panel()
	move_to_front()
	call_deferred("_play_enter")

func cancel() -> void:
	if not _open:
		return
	_close_visual()
	cancelled.emit()

func _play_enter() -> void:
	if not _open:
		return
	_fit_panel()
	UiAnim.kill_tween(_enter_tween)
	_enter_tween = UiAnim.enter_overlay(self, _dimmer, _panel, [], true)

func _input(event: InputEvent) -> void:
	if not _open:
		return
	if UiBack.is_back(event):
		get_viewport().set_input_as_handled()
		cancel()
		return
	if UiFocus.handle_first_pad_input(self, event, [_continue_button]):
		get_viewport().set_input_as_handled()

func _on_continue_pressed() -> void:
	if not _open:
		return
	_close_visual()
	confirmed.emit()

func _on_dimmer_gui_input(event: InputEvent) -> void:
	if not _open:
		return
	var click: InputEventMouseButton = event as InputEventMouseButton
	if click == null or not click.pressed or click.button_index != MOUSE_BUTTON_LEFT:
		return
	accept_event()
	cancel()

func _close_visual() -> void:
	_open = false
	UiAnim.kill_tween(_enter_tween)
	_dimmer.visible = false
	_center.visible = false
	_dimmer.modulate.a = 1.0
	_panel.modulate.a = 1.0
	_panel.scale = Vector2.ONE
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _apply_copy() -> void:
	var locale: String = _resolve_locale("")
	_message.text = message_for_locale(locale)
	_continue_button.text = continue_label_for_locale(locale)
	if _is_zh(locale):
		_message.add_theme_font_override("font", CJK_REGULAR)
		_continue_button.add_theme_font_override("font", CJK_BOLD)
	else:
		_message.remove_theme_font_override("font")
		_continue_button.remove_theme_font_override("font")

func _fit_panel() -> void:
	if _panel == null or not _open:
		return
	UiFit.apply_floating_panel(self, _panel, MODAL_PREFERRED, MODAL_MIN)
	_panel.reset_size()

static func _resolve_locale(forced: String) -> String:
	var locale: String = forced.strip_edges()
	if locale.is_empty():
		locale = locale_override.strip_edges()
	if locale.is_empty():
		locale = OS.get_locale()
	if _is_zh(locale):
		return "zh_CN"
	return "en"

static func _is_zh(locale: String) -> bool:
	var lower: String = locale.to_lower().replace("-", "_")
	return lower == "zh" or lower.begins_with("zh_")
