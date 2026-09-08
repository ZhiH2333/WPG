extends Control
class_name SettingsOverlay

## 主菜单设置叠层：Master 音量 + 全屏。瞬间 visible，禁止 Tween。
const MIX_RATE: int = 22050
const WAV_HEADER_BYTES: int = 44

var _open: bool = false

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
	_volume_slider.grab_focus()

func close() -> void:
	if not _open:
		return
	_open = false
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var play: Button = get_parent().get_node_or_null("Center/Column/Play") as Button
	if play != null:
		play.grab_focus()

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
