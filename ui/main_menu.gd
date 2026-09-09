extends Control
class_name MainMenu

## osu 式主菜单：字标在上，Settings / Play / Exit 三颗平行四边形按钮并排在下。
## 顶栏只留设置、主页、Profile、时钟。叠层打开时背景模糊 + 音乐衰减。
const SANDBOX_SCENE := "res://sandbox/combat_sandbox.tscn"
const TOP_BAR_HEIGHT: float = 48.0
const MIX_RATE: int = 22050
const WAV_HEADER_BYTES: int = 44
const MUSIC_DB_NORMAL: float = -6.0
const MUSIC_DB_DIMMED: float = -16.0
const BLUR_MAX: float = 2.6
const DIM_MAX: float = 0.35
const FOCUS_SMOOTH: float = 9.0
const LOGO_POP_SEC: float = 0.5
const STRIP_HOVER_SEC: float = 0.12

var _enter_tween: Tween
var _focus_amount: float = 0.0
var _last_clock_second: int = -1
var _hover_tweens: Dictionary = {}

@onready var _blur_layer: ColorRect = $BlurLayer
@onready var _logo_button: TextureButton = $Center/Column/Logo
@onready var _play_button: Button = $Center/Column/Buttons/Play
@onready var _settings_button: Button = $Center/Column/Buttons/Settings
@onready var _quit_button: Button = $Center/Column/Buttons/Quit
@onready var _top_bar: PanelContainer = $TopBar
@onready var _home_button: Button = $TopBar/Row/HomeButton
@onready var _top_settings_button: Button = $TopBar/Row/SettingsButton
@onready var _clock_label: Label = $TopBar/Row/TimeBox/Clock
@onready var _music: AudioStreamPlayer = $Music
@onready var _hover_sfx: AudioStreamPlayer = $HoverSfx
@onready var _click_sfx: AudioStreamPlayer = $ClickSfx
@onready var _back_sfx: AudioStreamPlayer = $BackSfx
@onready var _overlay: SettingsOverlay = $SettingsOverlay
@onready var _mode_overlay: ModeOverlay = $ModeOverlay

func _ready() -> void:
	GameSettings.load_from_disk()
	GameSettings.apply()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_hover_sfx.stream = _load_wav("res://audio/ui_hover.wav")
	_click_sfx.stream = _load_wav("res://audio/ui_click.wav")
	_back_sfx.stream = _load_wav("res://audio/ui_back.wav")
	_start_music()
	_logo_button.pressed.connect(_on_play_pressed)
	_play_button.pressed.connect(_on_play_pressed)
	_settings_button.pressed.connect(_on_settings_pressed)
	_top_settings_button.pressed.connect(_on_settings_pressed)
	_home_button.pressed.connect(_on_home_pressed)
	_quit_button.pressed.connect(_on_quit_pressed)
	_mode_overlay.selected_solo.connect(_enter_sandbox)
	_mode_overlay.selected_infinite.connect(_enter_sandbox)
	_wire_strip_hover(_settings_button)
	_wire_strip_hover(_play_button)
	_wire_strip_hover(_quit_button)
	_wire_button_sounds()
	_refresh_clock(true)
	_play_enter_animation()
	_play_button.grab_focus()

func _process(delta: float) -> void:
	var target: float = 1.0 if _any_overlay_open() else 0.0
	_focus_amount = lerpf(_focus_amount, target, 1.0 - exp(-FOCUS_SMOOTH * delta))
	var mat: ShaderMaterial = _blur_layer.material as ShaderMaterial
	mat.set_shader_parameter("blur_amount", BLUR_MAX * _focus_amount)
	mat.set_shader_parameter("dim_amount", DIM_MAX * _focus_amount)
	_music.volume_db = lerpf(MUSIC_DB_NORMAL, MUSIC_DB_DIMMED, _focus_amount)
	_refresh_clock(false)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if _overlay.is_open():
			get_viewport().set_input_as_handled()
			_overlay.close()
			return
		if _mode_overlay.is_open():
			get_viewport().set_input_as_handled()
			_mode_overlay.close()
		return
	if event.is_action_pressed("ui_accept"):
		if _any_overlay_open():
			return
		get_viewport().set_input_as_handled()
		_mode_overlay.open()

func _any_overlay_open() -> bool:
	return _overlay.is_open() or _mode_overlay.is_open()

func _on_play_pressed() -> void:
	if _overlay.is_open():
		return
	_mode_overlay.open()

func _enter_sandbox() -> void:
	get_tree().change_scene_to_file(SANDBOX_SCENE)

func _on_settings_pressed() -> void:
	if _mode_overlay.is_open():
		_mode_overlay.close()
	_overlay.open()

func _on_home_pressed() -> void:
	if _overlay.is_open():
		_overlay.close()
	if _mode_overlay.is_open():
		_mode_overlay.close()
	_play_button.grab_focus()

func _on_quit_pressed() -> void:
	get_tree().quit()

func _start_music() -> void:
	var mp3: AudioStreamMP3 = _music.stream as AudioStreamMP3
	if mp3 != null:
		mp3.loop = true
	_music.volume_db = MUSIC_DB_NORMAL
	if not _music.playing:
		_music.play()

func _wire_button_sounds() -> void:
	for entry: Variant in find_children("*", "BaseButton", true, false):
		var button: BaseButton = entry as BaseButton
		if button == null:
			continue
		button.mouse_entered.connect(_play_hover)
		button.focus_entered.connect(_play_hover)
		if button == _home_button or button == _quit_button:
			button.pressed.connect(_back_sfx.play)
		else:
			button.pressed.connect(_click_sfx.play)

func _wire_strip_hover(button: Button) -> void:
	var bg: ColorRect = button.get_node("Bg") as ColorRect
	var mat: ShaderMaterial = bg.material as ShaderMaterial
	button.mouse_entered.connect(func() -> void: _set_strip_hover(button, mat, true))
	button.mouse_exited.connect(func() -> void: _set_strip_hover(button, mat, false))
	button.focus_entered.connect(func() -> void: _set_strip_hover(button, mat, true))
	button.focus_exited.connect(func() -> void: _set_strip_hover(button, mat, false))

func _set_strip_hover(button: Button, mat: ShaderMaterial, hovered: bool) -> void:
	var key: String = str(button.get_path())
	var old: Tween = _hover_tweens.get(key) as Tween
	UiAnim.kill_tween(old)
	var tween: Tween = create_tween().set_parallel(true)
	_hover_tweens[key] = tween
	var from_hover: float = float(mat.get_shader_parameter("hover"))
	var to_hover: float = 1.0 if hovered else 0.0
	var to_scale: Vector2 = Vector2(1.04, 1.04) if hovered else Vector2.ONE
	tween.tween_method(
		func(value: float) -> void: mat.set_shader_parameter("hover", value),
		from_hover,
		to_hover,
		STRIP_HOVER_SEC
	)
	tween.tween_property(button, "scale", to_scale, STRIP_HOVER_SEC).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)

func _play_hover() -> void:
	if _hover_sfx.stream == null:
		return
	_hover_sfx.play()

func _play_enter_animation() -> void:
	UiAnim.kill_tween(_enter_tween)
	_top_bar.offset_top = -TOP_BAR_HEIGHT
	_top_bar.offset_bottom = 0.0
	_logo_button.scale = Vector2(0.7, 0.7)
	_logo_button.modulate.a = 0.0
	_enter_tween = create_tween().set_parallel(true)
	_enter_tween.tween_property(_top_bar, "offset_top", 0.0, UiAnim.PANEL_MOVE_SEC).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	_enter_tween.tween_property(_top_bar, "offset_bottom", TOP_BAR_HEIGHT, UiAnim.PANEL_MOVE_SEC).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	_enter_tween.tween_property(_logo_button, "scale", Vector2.ONE, LOGO_POP_SEC).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_enter_tween.tween_property(_logo_button, "modulate:a", 1.0, UiAnim.CONTENT_FADE_SEC).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	var order: int = 0
	for entry: Variant in [_settings_button, _play_button, _quit_button]:
		var button: Button = entry as Button
		var delay: float = UiAnim.CARD_STAGGER_SEC * float(order)
		button.modulate.a = 0.0
		button.scale = Vector2(UiAnim.CARD_START_SCALE, UiAnim.CARD_START_SCALE)
		_enter_tween.tween_property(button, "modulate:a", 1.0, UiAnim.CARD_FADE_SEC).set_delay(delay).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
		_enter_tween.tween_property(button, "scale", Vector2.ONE, UiAnim.CARD_SCALE_SEC).set_delay(delay).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		order += 1

func _refresh_clock(force: bool) -> void:
	var now: Dictionary = Time.get_time_dict_from_system()
	var sec: int = int(now["second"])
	if not force and sec == _last_clock_second:
		return
	_last_clock_second = sec
	_clock_label.text = "%02d:%02d:%02d" % [int(now["hour"]), int(now["minute"]), sec]

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
