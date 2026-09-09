extends Control
class_name SettingsOverlay

## 主菜单设置叠层：Master 音量 + 全屏。osu 式左侧滑入（OutQuint），逻辑开关仍瞬时生效。
const MIX_RATE: int = 22050
const WAV_HEADER_BYTES: int = 44
const SHELL_WIDTH: float = 520.0

var _open: bool = false
var _anim_tween: Tween

@onready var _dimmer: ColorRect = $Dimmer
@onready var _shell: Control = $Shell
@onready var _audio_button: Button = $Shell/Panel/Column/Body/Sidebar/AudioButton
@onready var _display_button: Button = $Shell/Panel/Column/Body/Sidebar/DisplayButton
@onready var _audio_page: VBoxContainer = $Shell/Panel/Column/Body/Pages/AudioPage
@onready var _display_page: VBoxContainer = $Shell/Panel/Column/Body/Pages/DisplayPage
@onready var _volume_slider: HSlider = $Shell/Panel/Column/Body/Pages/AudioPage/VolumeSlider
@onready var _fullscreen_check: CheckBox = $Shell/Panel/Column/Body/Pages/DisplayPage/FullscreenCheck
@onready var _back_button: Button = $Shell/Panel/Column/Back
@onready var _preview: AudioStreamPlayer = $Preview

func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_preview.stream = _load_wav("res://audio/click.wav")
	_audio_button.pressed.connect(_on_audio_pressed)
	_display_button.pressed.connect(_on_display_pressed)
	_back_button.pressed.connect(close)
	_volume_slider.value_changed.connect(_on_volume_changed)
	_volume_slider.drag_ended.connect(_on_volume_drag_ended)
	_fullscreen_check.toggled.connect(_on_fullscreen_toggled)
	_show_audio_page()

func is_open() -> bool:
	return _open

func open() -> void:
	_volume_slider.set_value_no_signal(GameSettings.get_volume())
	_fullscreen_check.set_pressed_no_signal(GameSettings.is_fullscreen())
	_show_audio_page()
	_open = true
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_play_open_animation()
	_volume_slider.grab_focus()

func close() -> void:
	if not _open:
		return
	_open = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_play_close_animation()
	_refocus_menu()

func _refocus_menu() -> void:
	var play: Button = get_parent().get_node_or_null("Center/Buttons/Play") as Button
	if play != null and play.is_visible_in_tree():
		play.grab_focus()
		return
	var logo: Button = get_parent().get_node_or_null("Center/Logo") as Button
	if logo != null:
		logo.grab_focus()

func _play_open_animation() -> void:
	UiAnim.kill_tween(_anim_tween)
	_shell.offset_left = -SHELL_WIDTH
	_shell.offset_right = 0.0
	_dimmer.modulate.a = 0.0
	_anim_tween = create_tween().set_parallel(true)
	_anim_tween.tween_property(_shell, "offset_left", 0.0, UiAnim.PANEL_MOVE_SEC).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	_anim_tween.tween_property(_shell, "offset_right", SHELL_WIDTH, UiAnim.PANEL_MOVE_SEC).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	_anim_tween.tween_property(_dimmer, "modulate:a", 1.0, UiAnim.DIMMER_FADE_SEC).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)

func _play_close_animation() -> void:
	UiAnim.kill_tween(_anim_tween)
	_anim_tween = create_tween().set_parallel(true)
	_anim_tween.tween_property(_shell, "offset_left", -SHELL_WIDTH, UiAnim.PANEL_EXIT_SEC).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	_anim_tween.tween_property(_shell, "offset_right", 0.0, UiAnim.PANEL_EXIT_SEC).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	_anim_tween.tween_property(_dimmer, "modulate:a", 0.0, UiAnim.PANEL_EXIT_SEC * 0.5).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_IN)
	_anim_tween.finished.connect(hide)

func _unhandled_input(event: InputEvent) -> void:
	if not _open:
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()

func _on_audio_pressed() -> void:
	_show_audio_page()
	if _open:
		_volume_slider.grab_focus()

func _on_display_pressed() -> void:
	_show_display_page()
	if _open:
		_fullscreen_check.grab_focus()

func _show_audio_page() -> void:
	_audio_page.visible = true
	_display_page.visible = false

func _show_display_page() -> void:
	_audio_page.visible = false
	_display_page.visible = true

func _on_volume_changed(value: float) -> void:
	GameSettings.set_volume(value)
	GameSettings.apply()

func _on_volume_drag_ended(_value_changed: bool) -> void:
	GameSettings.save_to_disk()
	if GameSettings.get_volume() > 0.0:
		_play_preview()

func _on_fullscreen_toggled(pressed: bool) -> void:
	GameSettings.set_fullscreen(pressed)
	GameSettings.apply()
	GameSettings.save_to_disk()

func _play_preview() -> void:
	if _preview.stream == null:
		return
	_preview.stop()
	_preview.play()

func _load_wav(path: String) -> AudioStreamWAV:
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
	if bytes.size() <= WAV_HEADER_BYTES:
		return null
	var stream: AudioStreamWAV = AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = MIX_RATE
	stream.stereo = false
	stream.data = bytes.slice(WAV_HEADER_BYTES)
	return stream
