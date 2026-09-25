extends CanvasLayer
class_name PauseOverlay

## 战斗暂停叠层：单机 Continue / Retry / Quit；Esc 走 Continue。选卡时 CombatSandbox 也会冻场景树。
## 顶栏保留 Settings / 资料 / 时钟，Home / Solo / Multi 换成 Phase 与 playtime。
signal resumed
signal retried
signal quit_pressed

const STRIP_HOVER_SEC: float = 0.12

var _open: bool = false
var _session: RunSession
var _encounter: EncounterPhrases
var _anim_tween: Tween
var _hover_tweens: Dictionary = {}
var _sfx_gate: Dictionary = {}
var _last_clock_second: int = -1
var _owns_tree_pause: bool = false

@onready var _root: Control = $Root
@onready var _dimmer: ColorRect = $Root/Dimmer
@onready var _column: VBoxContainer = $Root/Center/Column
@onready var _continue_button: Button = $Root/Center/Column/Continue
@onready var _retry_button: Button = $Root/Center/Column/Retry
@onready var _quit_button: Button = $Root/Center/Column/Quit
@onready var _stats_label: Label = $Root/Center/Column/Stats
@onready var _top_bar_layer: CanvasLayer = $TopBarLayer
@onready var _top_bar: PanelContainer = $TopBarLayer/TopBar
@onready var _settings_button: Button = $TopBarLayer/TopBar/Row/SettingsButton
@onready var _phase_label: Label = $TopBarLayer/TopBar/Row/PhaseBox/Phase
@onready var _playtime_label: Label = $TopBarLayer/TopBar/Row/PlaytimeBox/Playtime
@onready var _profile_button: Button = $TopBarLayer/TopBar/Row/Profile
@onready var _profile_name: Label = $TopBarLayer/TopBar/Row/Profile/Layout/Name
@onready var _profile_avatar: TextureRect = $TopBarLayer/TopBar/Row/Profile/Layout/Avatar
@onready var _clock_label: Label = $TopBarLayer/TopBar/Row/TimeBox/Clock
@onready var _overlay: SettingsOverlay = $SettingsOverlay
@onready var _hover_sfx: AudioStreamPlayer = $HoverSfx
@onready var _click_sfx: AudioStreamPlayer = $ClickSfx
@onready var _back_sfx: AudioStreamPlayer = $BackSfx

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 25
	visible = false
	_open = false
	_hover_sfx.stream = GameAudio.load_wav("res://audio/ui_hover.wav")
	_click_sfx.stream = GameAudio.load_wav("res://audio/ui_click.wav")
	_back_sfx.stream = GameAudio.load_wav("res://audio/ui_back.wav")
	_continue_button.pressed.connect(_on_continue_pressed)
	_retry_button.pressed.connect(_on_retry_pressed)
	_quit_button.pressed.connect(_on_quit_pressed)
	_settings_button.pressed.connect(_on_settings_pressed)
	_wire_strip_hover(_continue_button)
	_wire_strip_hover(_retry_button)
	_wire_strip_hover(_quit_button)
	_continue_button.mouse_entered.connect(_play_hover)
	_retry_button.mouse_entered.connect(_play_hover)
	_quit_button.mouse_entered.connect(_play_hover)
	_settings_button.mouse_entered.connect(_play_hover)
	_continue_button.focus_entered.connect(_play_hover)
	_retry_button.focus_entered.connect(_play_hover)
	_quit_button.focus_entered.connect(_play_hover)
	_settings_button.focus_entered.connect(_play_hover)
	_set_interactive(false)

func bind_run_session(session: RunSession) -> void:
	_session = session

func bind_encounter(encounter: EncounterPhrases) -> void:
	_encounter = encounter

func is_open() -> bool:
	return _open

func show_top_bar() -> void:
	visible = true
	_top_bar_layer.visible = true
	_top_bar.visible = true
	_top_bar.modulate.a = 1.0
	if not _open:
		_root.visible = false
	_refresh_clock(true)
	_refresh_run_status()
	_refresh_profile_name()

func hide_top_bar() -> void:
	_root.visible = true
	if _open:
		return
	_top_bar_layer.visible = false
	visible = false

func adopt_tree_pause() -> void:
	if not _open:
		return
	_owns_tree_pause = true
	var tree: SceneTree = get_tree()
	if tree != null:
		tree.paused = true

func open(freeze_tree: bool = true) -> void:
	if _open:
		return
	_open = true
	visible = true
	_root.visible = true
	_root.modulate.a = 1.0
	_top_bar_layer.visible = true
	_top_bar.visible = true
	_top_bar.modulate.a = 1.0
	_set_interactive(true)
	_refresh_stats()
	_refresh_run_status()
	_refresh_profile_name()
	_refresh_clock(true)
	_owns_tree_pause = freeze_tree
	if freeze_tree:
		var tree: SceneTree = get_tree()
		if tree != null:
			tree.paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	UiAnim.kill_tween(_anim_tween)
	_anim_tween = UiAnim.enter_overlay(self, _dimmer, _column, [_continue_button, _retry_button, _quit_button], true)
	_continue_button.grab_focus()

func close(emit_resumed: bool = true) -> void:
	if not _open:
		return
	_open = false
	_set_interactive(false)
	if _overlay.is_open():
		_overlay.close()
	var tree: SceneTree = get_tree()
	if tree != null and _owns_tree_pause:
		tree.paused = false
	_owns_tree_pause = false
	if emit_resumed:
		resumed.emit()
	UiAnim.kill_tween(_anim_tween)
	_anim_tween = UiAnim.exit_overlay(self, _root, true)
	_anim_tween.finished.connect(_finish_close)

func _finish_close() -> void:
	if _open:
		return
	_top_bar_layer.visible = false
	visible = false
	_root.visible = true
	_root.modulate.a = 1.0
	_top_bar.modulate.a = 1.0

func _process(_delta: float) -> void:
	if not visible:
		return
	_refresh_clock(false)
	if _open:
		_refresh_run_status()

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_pressed():
		GameAudio.unlock_driver(self)
	if _overlay.is_open():
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
	_play_back()
	close()

func _on_retry_pressed() -> void:
	if not _open:
		return
	_play_click()
	retried.emit()

func _on_quit_pressed() -> void:
	if not _open:
		return
	_play_back()
	_open = false
	_set_interactive(false)
	if _overlay.is_open():
		_overlay.close()
	var tree: SceneTree = get_tree()
	if tree != null:
		tree.paused = false
	quit_pressed.emit()

func _on_settings_pressed() -> void:
	if not _open:
		return
	_play_click()
	if _overlay.is_open():
		_overlay.close()
		_continue_button.grab_focus()
		return
	_overlay.open()
	_overlay.move_to_front()
	_top_bar.move_to_front()

func _refresh_stats() -> void:
	if _session == null:
		_stats_label.text = "loop  0    gold  0    kills  0"
		return
	_stats_label.text = "loop  %d    gold  %d    kills  %d" % [
		_session.get_loop_index(),
		_session.get_gold(),
		_session.get_kill_count(),
	]

func _refresh_run_status() -> void:
	var phase: String = "-"
	if _encounter != null:
		phase = _encounter.get_phrase_label()
	_phase_label.text = "Phase  %s" % phase
	var elapsed: float = 0.0
	if _session != null:
		elapsed = _session.get_elapsed_sec()
	_playtime_label.text = "playtime  %s" % GameAudio.format_playtime(elapsed)

func _refresh_profile_name() -> void:
	PlayerProfile.load_from_disk()
	_profile_name.text = PlayerProfile.get_display_name()
	_profile_avatar.texture = RecordCard.resolve_body_texture(PlayerProfile.get_avatar_id())

func _refresh_clock(force: bool) -> void:
	var now: Dictionary = Time.get_time_dict_from_system()
	var sec: int = int(now["second"])
	if not force and sec == _last_clock_second:
		return
	_last_clock_second = sec
	_clock_label.text = "%02d:%02d:%02d" % [int(now["hour"]), int(now["minute"]), sec]

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
	_settings_button.disabled = not enabled

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
