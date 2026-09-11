extends CanvasLayer
class_name PauseOverlay

## 战斗暂停叠层：唯一允许 get_tree().paused 的地方。Continue / Retry / Quit；Esc 走 Continue。
signal resumed
signal retried
signal quit_pressed

const MIX_RATE: int = 22050
const WAV_HEADER_BYTES: int = 44
const STRIP_HOVER_SEC: float = 0.12

var _open: bool = false
var _session: RunSession
var _anim_tween: Tween
var _hover_tweens: Dictionary = {}

@onready var _root: Control = $Root
@onready var _dimmer: ColorRect = $Root/Dimmer
@onready var _column: VBoxContainer = $Root/Center/Column
@onready var _continue_button: Button = $Root/Center/Column/Continue
@onready var _retry_button: Button = $Root/Center/Column/Retry
@onready var _quit_button: Button = $Root/Center/Column/Quit
@onready var _stats_label: Label = $Root/Center/Column/Stats
@onready var _hover_sfx: AudioStreamPlayer = $HoverSfx
@onready var _click_sfx: AudioStreamPlayer = $ClickSfx

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 25
	visible = false
	_open = false
	_hover_sfx.stream = _load_wav("res://audio/ui_hover.wav")
	_click_sfx.stream = _load_wav("res://audio/ui_click.wav")
	_continue_button.pressed.connect(_on_continue_pressed)
	_retry_button.pressed.connect(_on_retry_pressed)
	_quit_button.pressed.connect(_on_quit_pressed)
	_wire_strip_hover(_continue_button)
	_wire_strip_hover(_retry_button)
	_wire_strip_hover(_quit_button)
	_continue_button.mouse_entered.connect(_play_hover)
	_retry_button.mouse_entered.connect(_play_hover)
	_quit_button.mouse_entered.connect(_play_hover)
	_continue_button.focus_entered.connect(_play_hover)
	_retry_button.focus_entered.connect(_play_hover)
	_quit_button.focus_entered.connect(_play_hover)
	_set_interactive(false)

func bind_run_session(session: RunSession) -> void:
	_session = session

func is_open() -> bool:
	return _open

func open() -> void:
	if _open:
		return
	_open = true
	visible = true
	_root.modulate.a = 1.0
	_set_interactive(true)
	_refresh_stats()
	var tree: SceneTree = get_tree()
	if tree != null:
		tree.paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	UiAnim.kill_tween(_anim_tween)
	_anim_tween = UiAnim.enter_overlay(self, _dimmer, _column, [_continue_button, _retry_button, _quit_button], true)
	_continue_button.grab_focus()

func close() -> void:
	if not _open:
		return
	_open = false
	_set_interactive(false)
	var tree: SceneTree = get_tree()
	if tree != null:
		tree.paused = false
	resumed.emit()
	UiAnim.kill_tween(_anim_tween)
	_anim_tween = UiAnim.exit_overlay(self, _root, true)
	_anim_tween.finished.connect(_finish_close)

func _finish_close() -> void:
	if _open:
		return
	visible = false
	_root.modulate.a = 1.0

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if not _is_pause_toggle(event):
		return
	get_viewport().set_input_as_handled()
	if _open:
		_on_continue_pressed()

func _is_pause_toggle(event: InputEvent) -> bool:
	if event.is_action_pressed("ui_cancel"):
		return true
	var joy_button: InputEventJoypadButton = event as InputEventJoypadButton
	if joy_button != null and joy_button.pressed and joy_button.button_index == JOY_BUTTON_START:
		return true
	return false

func _on_continue_pressed() -> void:
	if not _open:
		return
	_play_click()
	close()

func _on_retry_pressed() -> void:
	if not _open:
		return
	_play_click()
	retried.emit()

func _on_quit_pressed() -> void:
	if not _open:
		return
	_play_click()
	_open = false
	_set_interactive(false)
	var tree: SceneTree = get_tree()
	if tree != null:
		tree.paused = false
	quit_pressed.emit()

func _refresh_stats() -> void:
	if _session == null:
		_stats_label.text = "loop  0    gold  0    kills  0"
		return
	_stats_label.text = "loop  %d    gold  %d    kills  %d" % [
		_session.get_loop_index(),
		_session.get_gold(),
		_session.get_kill_count(),
	]

func _set_interactive(enabled: bool) -> void:
	if enabled:
		_root.mouse_filter = Control.MOUSE_FILTER_STOP
		_dimmer.mouse_filter = Control.MOUSE_FILTER_STOP
	else:
		_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_dimmer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_continue_button.disabled = not enabled
	_retry_button.disabled = not enabled
	_quit_button.disabled = not enabled

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
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_hover_tweens[key] = tween
	var from_hover: float = float(mat.get_shader_parameter("hover"))
	var to_hover: float = 1.0 if hovered else 0.0
	var to_scale: Vector2 = Vector2(1.02, 1.02) if hovered else Vector2.ONE
	tween.tween_method(
		func(value: float) -> void: mat.set_shader_parameter("hover", value),
		from_hover,
		to_hover,
		STRIP_HOVER_SEC
	)
	tween.tween_property(button, "scale", to_scale, STRIP_HOVER_SEC).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)

func _play_hover() -> void:
	if not _open or _hover_sfx.stream == null:
		return
	_hover_sfx.play()

func _play_click() -> void:
	if _click_sfx.stream == null:
		return
	_click_sfx.play()

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
