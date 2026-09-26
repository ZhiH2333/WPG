extends Control
class_name CreditsOverlay

## Settings 子叠层：制作组名单。不是独立场景，不换 BGM，不 change_scene。
const PANEL_PREFERRED := Vector2(720, 560)
const GITHUB_URL := "https://github.com/ZhiH2333"

var _open: bool = false
var _anim_tween: Tween
var _sfx_gate: Dictionary = {}

@onready var _dimmer: ColorRect = $Dimmer
@onready var _panel: PanelContainer = $Center/Panel
@onready var _version_label: Label = $Center/Panel/Column/VersionLabel
@onready var _back_button: Button = $Center/Panel/Column/Back
@onready var _github_button: Button = $Center/Panel/Column/Scroll/Body/GithubButton
@onready var _hover_sfx: AudioStreamPlayer = $HoverSfx
@onready var _click_sfx: AudioStreamPlayer = $ClickSfx
@onready var _back_sfx: AudioStreamPlayer = $BackSfx

func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process_input(false)
	_version_label.text = "version  %s" % GameSettings.get_version()
	_hover_sfx.stream = GameAudio.load_wav("res://audio/ui_hover.wav")
	_click_sfx.stream = GameAudio.load_wav("res://audio/ui_click.wav")
	_back_sfx.stream = GameAudio.load_wav("res://audio/ui_back.wav")
	_back_button.pressed.connect(close_from_user)
	_github_button.pressed.connect(_on_github_pressed)
	_dimmer.gui_input.connect(_on_dimmer_gui_input)
	for row: Button in [_back_button, _github_button]:
		_wire_hover(row)
		UiAnim.wire_row_feedback(self, row, UiType.INK)
	UiFit.connect_refit(self, _on_host_resized)

func is_open() -> bool:
	return _open

func open() -> void:
	if _open:
		return
	_open = true
	visible = true
	modulate.a = 1.0
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_process_input(true)
	_fit_panel()
	move_to_front()
	UiAnim.kill_tween(_anim_tween)
	_anim_tween = UiAnim.enter_modal(self, _dimmer, _panel, true)
	_back_button.grab_focus()

func close() -> void:
	if not _open:
		return
	_open = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process_input(false)
	UiAnim.kill_tween(_anim_tween)
	_anim_tween = UiAnim.exit_modal(self, _dimmer, _panel, true)
	_anim_tween.finished.connect(_finish_close)

func close_from_user() -> void:
	if not _open:
		return
	_play_back()
	close()

func _finish_close() -> void:
	if _open:
		return
	visible = false
	modulate.a = 1.0

func _input(event: InputEvent) -> void:
	if not _open:
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close_from_user()
		return
	var joy: InputEventJoypadButton = event as InputEventJoypadButton
	if joy != null and joy.pressed and joy.button_index == JOY_BUTTON_START:
		get_viewport().set_input_as_handled()
		close_from_user()

func _on_github_pressed() -> void:
	if not _open:
		return
	_play_click()
	OS.shell_open(GITHUB_URL)

func _on_dimmer_gui_input(event: InputEvent) -> void:
	var mouse: InputEventMouseButton = event as InputEventMouseButton
	if mouse == null or not mouse.pressed or mouse.button_index != MOUSE_BUTTON_LEFT:
		return
	if _panel.get_global_rect().has_point(get_global_mouse_position()):
		return
	close_from_user()

func _on_host_resized() -> void:
	if not _open:
		return
	_fit_panel()

func _fit_panel() -> void:
	var host: Control = get_parent() as Control
	if host == null:
		host = self
	UiFit.apply_floating_panel(host, _panel, PANEL_PREFERRED)

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
