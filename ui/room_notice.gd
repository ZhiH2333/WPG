extends CanvasLayer
class_name RoomNotice

## 联机关房提示：Guest 居中弹窗后回菜单；Host 右上角 toast。不是 Autoload。
## 弹窗层在暂停菜单之上、顶栏之下；dimmer 从顶栏下沿开始，顶栏始终最高。
signal dismissed

const TEXT_HOST_CLOSED: String = "Host closed the room. Returning to the menu."
const TEXT_GUEST_LEFT: String = "Guest left the room. Switched to solo."
const TEXT_OK: String = "OK"
const TOAST_LIFE_SEC: float = 2.8
const TOAST_FADE_SEC: float = 0.22
const BAR_HEIGHT: float = 60.0
const MODAL_PREFERRED := Vector2(560, 220)
const MODAL_MIN := Vector2(420, 160)
const TOAST_SIZE := Vector2(420, 72)
const TOAST_MARGIN := Vector2(24, 24)

var _modal_open: bool = false
var _toast_tween: Tween
var _modal_tween: Tween

@onready var _root: Control = $Root
@onready var _dimmer: ColorRect = $Root/Dimmer
@onready var _modal_root: Control = $Root/Center
@onready var _modal_panel: PanelContainer = $Root/Center/Panel
@onready var _modal_label: Label = $Root/Center/Panel/Column/Message
@onready var _ok_button: Button = $Root/Center/Panel/Column/Ok
@onready var _toast_panel: PanelContainer = $Root/Toast
@onready var _toast_label: Label = $Root/Toast/Message

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 40
	visible = true
	_ok_button.text = TEXT_OK
	_dimmer.visible = false
	_modal_root.visible = false
	_toast_panel.visible = false
	_toast_panel.modulate.a = 0.0
	_ok_button.pressed.connect(_on_ok_pressed)
	UiFit.connect_refit(_root, _on_refit)
	_on_refit()

func is_modal_open() -> bool:
	return _modal_open

func present_toast(text: String) -> void:
	_hide_modal()
	_toast_label.text = text
	_pin_root(false)
	_toast_panel.visible = true
	_pin_toast(UiFit.visible_size(_root))
	UiAnim.kill_tween(_toast_tween)
	_toast_panel.modulate.a = 0.0
	_toast_tween = create_tween()
	_toast_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_toast_tween.tween_property(_toast_panel, "modulate:a", 1.0, TOAST_FADE_SEC).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	_toast_tween.tween_interval(TOAST_LIFE_SEC)
	_toast_tween.tween_property(_toast_panel, "modulate:a", 0.0, TOAST_FADE_SEC).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_IN)
	_toast_tween.finished.connect(_hide_toast)

func present_modal(text: String) -> void:
	if _modal_open:
		return
	_hide_toast()
	_modal_open = true
	_modal_label.text = text
	_ok_button.text = TEXT_OK
	_dimmer.modulate.a = 0.0
	_modal_panel.modulate.a = 0.0
	_modal_panel.scale = Vector2.ONE
	_dimmer.visible = true
	_modal_root.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_pin_root(true)
	_fit_panel()
	call_deferred("_play_modal_enter")

func _play_modal_enter() -> void:
	if not _modal_open:
		return
	_pin_root(true)
	_fit_panel()
	UiAnim.kill_tween(_modal_tween)
	_modal_tween = UiAnim.enter_overlay(self, _dimmer, _modal_panel, [], true)
	_ok_button.grab_focus()

func _on_refit() -> void:
	_pin_root(_modal_open)
	_pin_toast(UiFit.visible_size(_root))
	if _modal_open:
		_fit_panel()

func _pin_root(leave_bar: bool) -> void:
	var vis: Vector2 = UiFit.visible_size(_root)
	_root.anchor_left = 0.0
	_root.anchor_top = 0.0
	_root.anchor_right = 0.0
	_root.anchor_bottom = 0.0
	_root.offset_left = 0.0
	_root.offset_top = BAR_HEIGHT if leave_bar else 0.0
	_root.offset_right = vis.x
	_root.offset_bottom = vis.y

func _fit_panel() -> void:
	if _modal_panel == null or _root == null:
		return
	UiFit.apply_floating_panel(_root, _modal_panel, MODAL_PREFERRED, MODAL_MIN)
	_modal_panel.reset_size()

func _pin_toast(vis: Vector2) -> void:
	_toast_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	# 宽固定 420，高由内容（FloatingPanel content margin + 文案换行）撑，72 只是下限。
	_toast_panel.custom_minimum_size = Vector2(TOAST_SIZE.x, 0.0)
	_toast_panel.offset_left = vis.x - TOAST_SIZE.x - TOAST_MARGIN.x
	_toast_panel.offset_top = TOAST_MARGIN.y
	_toast_panel.offset_right = vis.x - TOAST_MARGIN.x
	_toast_panel.offset_bottom = TOAST_MARGIN.y + TOAST_SIZE.y

func _on_ok_pressed() -> void:
	_finish_modal()

func _finish_modal() -> void:
	if not _modal_open:
		return
	_modal_open = false
	UiAnim.kill_tween(_modal_tween)
	_hide_modal()
	dismissed.emit()

func _hide_modal() -> void:
	_modal_open = false
	_dimmer.visible = false
	_modal_root.visible = false
	_dimmer.modulate.a = 1.0
	_modal_panel.modulate.a = 1.0
	_modal_panel.scale = Vector2.ONE
	_pin_root(false)

func _hide_toast() -> void:
	UiAnim.kill_tween(_toast_tween)
	_toast_panel.visible = false
	_toast_panel.modulate.a = 0.0
