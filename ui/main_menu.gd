extends Control
class_name MainMenu

## osu 式主菜单壳：中央 Title + Play，瘦顶栏 Home/Settings，底栏 Play/Settings/Quit。
## 进场用非线性缓动（UiAnim）。禁止暂停树、禁止 Autoload。
const SANDBOX_SCENE := "res://sandbox/combat_sandbox.tscn"
const TOP_BAR_HEIGHT: float = 44.0
const BOTTOM_BAR_HEIGHT: float = 64.0

var _enter_tween: Tween

@onready var _title_label: Label = $Center/Column/Title
@onready var _play_button: Button = $Center/Column/Play
@onready var _top_bar: PanelContainer = $TopBar
@onready var _bottom_bar: PanelContainer = $BottomBar
@onready var _home_button: Button = $TopBar/Row/HomeButton
@onready var _top_settings_button: Button = $TopBar/Row/SettingsButton
@onready var _bottom_play_button: Button = $BottomBar/Row/PlayButton
@onready var _bottom_settings_button: Button = $BottomBar/Row/SettingsButton
@onready var _bottom_quit_button: Button = $BottomBar/Row/QuitButton
@onready var _overlay: SettingsOverlay = $SettingsOverlay
@onready var _mode_overlay: ModeOverlay = $ModeOverlay

func _ready() -> void:
	GameSettings.load_from_disk()
	GameSettings.apply()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_play_button.pressed.connect(_on_play_pressed)
	_bottom_play_button.pressed.connect(_on_play_pressed)
	_top_settings_button.pressed.connect(_on_settings_pressed)
	_bottom_settings_button.pressed.connect(_on_settings_pressed)
	_home_button.pressed.connect(_on_home_pressed)
	_bottom_quit_button.pressed.connect(_on_quit_pressed)
	_mode_overlay.selected_solo.connect(_enter_sandbox)
	_mode_overlay.selected_infinite.connect(_enter_sandbox)
	_play_enter_animation()
	_play_button.grab_focus()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if _overlay.is_open():
			get_viewport().set_input_as_handled()
			_overlay.close()
			_play_button.grab_focus()
			return
		if _mode_overlay.is_open():
			get_viewport().set_input_as_handled()
			_mode_overlay.close()
			_play_button.grab_focus()
		return
	if event.is_action_pressed("ui_accept"):
		if _overlay.is_open():
			return
		if _mode_overlay.is_open():
			return
		get_viewport().set_input_as_handled()
		_mode_overlay.open()

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

func _play_enter_animation() -> void:
	UiAnim.kill_tween(_enter_tween)
	_top_bar.offset_top = -TOP_BAR_HEIGHT
	_top_bar.offset_bottom = 0.0
	_bottom_bar.offset_top = 0.0
	_bottom_bar.offset_bottom = BOTTOM_BAR_HEIGHT
	_enter_tween = create_tween().set_parallel(true)
	_enter_tween.tween_property(_top_bar, "offset_top", 0.0, UiAnim.PANEL_MOVE_SEC).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	_enter_tween.tween_property(_top_bar, "offset_bottom", TOP_BAR_HEIGHT, UiAnim.PANEL_MOVE_SEC).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	_enter_tween.tween_property(_bottom_bar, "offset_top", -BOTTOM_BAR_HEIGHT, UiAnim.PANEL_MOVE_SEC).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	_enter_tween.tween_property(_bottom_bar, "offset_bottom", 0.0, UiAnim.PANEL_MOVE_SEC).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	UiAnim.enter_stagger_fade(self, [_title_label, _play_button])
