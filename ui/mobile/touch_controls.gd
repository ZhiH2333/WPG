extends CanvasLayer
class_name TouchControls

## Touch Controls 容器：固定双摇杆 + 武器/Dash Cluster + 右上 Pause。
## 屏幕空间常驻，不随 world/camera 移动。视觉来自 ui/game_theme.tres。
## 由 GameSettings.is_touch_controls_enabled() 决定整体显示，并支持临时 modal 屏蔽。
## 不包含战斗逻辑：输入经 TouchInput -> PlayerInput，Pause 只发信号给 CombatSandbox。

signal touch_visibility_changed(visible: bool)
signal pause_requested

@onready var _move_stick: VirtualStick = $Root/SafeAreaRoot/MoveStick
@onready var _aim_pad: TouchAimPad = $Root/SafeAreaRoot/AimPad
@onready var _dash_button: TouchActionButton = $Root/SafeAreaRoot/WeaponCluster/DashButton
@onready var _weapon1_button: TouchActionButton = $Root/SafeAreaRoot/WeaponCluster/Weapon1Button
@onready var _weapon2_button: TouchActionButton = $Root/SafeAreaRoot/WeaponCluster/Weapon2Button
@onready var _weapon3_button: TouchActionButton = $Root/SafeAreaRoot/WeaponCluster/Weapon3Button
@onready var _weapon4_button: TouchActionButton = $Root/SafeAreaRoot/WeaponCluster/Weapon4Button
@onready var _pause_button: TouchActionButton = $Root/SafeAreaRoot/SystemCluster/PauseButton
@onready var _touch_input: TouchInput = $Root/TouchInput
@onready var _root: Control = $Root
@onready var _safe_area: SafeAreaRoot = $Root/SafeAreaRoot

var _modal_blocked: bool = false
var _active: bool = false
var _debug_label: Label = null
var _debug_enabled: bool = false

func _ready() -> void:
	_connect_buttons()
	_sync_manual_fire_mode()
	_setup_debug_status()
	## 父节点 CombatSandbox._ready() 会 load_from_disk() 并 bind_player_input，
	## 晚于子节点 _ready。首帧延后到父 ready 之后，避免用陈旧 settings 决定 active。
	_update_visibility.call_deferred()

func _process(_delta: float) -> void:
	_sync_manual_fire_mode()
	_update_visibility()
	_update_debug_status()

## 开发诊断：仅 debug build 且 Touch Controls 开启时显示输入链路状态，验证
## ScreenTouch -> TouchControls -> TouchInput -> PlayerInput 在哪一级断掉。
func _setup_debug_status() -> void:
	_debug_enabled = OS.is_debug_build()
	if not _debug_enabled:
		return
	_debug_label = Label.new()
	_debug_label.name = "TouchDebugStatus"
	_debug_label.theme = _root.theme
	_debug_label.theme_type_variation = &"Caption"
	_debug_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_debug_label.position = Vector2(16.0, 16.0)
	_debug_label.visible = false
	_root.add_child(_debug_label)

func _update_debug_status() -> void:
	if _debug_label == null:
		return
	var show_status: bool = _root.visible and GameSettings.is_touch_controls_enabled()
	_debug_label.visible = show_status
	if not show_status:
		return
	var source: String = "TOUCH" if _touch_input != null and _touch_input.is_touch_active() else "IDLE"
	var pi: PlayerInput = _touch_input.get_player_input() if _touch_input != null else null
	var move: Vector2 = pi.move_vector if pi != null else Vector2.ZERO
	var aim: Vector2 = pi.aim_vector if pi != null else Vector2.ZERO
	var fire: bool = pi.fire_held if pi != null else false
	_debug_label.text = "Touch: ON  Source: %s\nMove: %.2f, %.2f  Aim: %.2f, %.2f  Fire: %s" % [
		source, move.x, move.y, aim.x, aim.y, str(fire),
	]

func _sync_manual_fire_mode() -> void:
	if _touch_input == null:
		return
	_touch_input.set_manual_fire_mode(GameSettings.is_touch_manual_fire())

func _connect_buttons() -> void:
	## Move/Aim/Fire/Dash/Weapon 全部由 TouchInput 通过 NodePath/slot 连接。
	## TouchControls 只负责 Pause：Pause 不进 gameplay PlayerInput。
	if _pause_button != null:
		if not _pause_button.just_pressed.is_connected(_on_pause_just_pressed):
			_pause_button.just_pressed.connect(_on_pause_just_pressed)
	var weapon_buttons: Array[TouchActionButton] = [
		_weapon1_button, _weapon2_button, _weapon3_button, _weapon4_button,
	]
	if _touch_input != null:
		_touch_input.bind_weapon_buttons(weapon_buttons)

func _should_show() -> bool:
	return GameSettings.is_touch_controls_enabled() and not _modal_blocked

func _update_visibility() -> void:
	var should_show: bool = _should_show()
	if _root.visible != should_show:
		_root.visible = should_show
		touch_visibility_changed.emit(should_show)
	_apply_input_policy(should_show)

## 隐藏时让出鼠标，避免 PC 正常操作被 Touch UI 拦截。
func _apply_input_policy(show: bool) -> void:
	_root.mouse_filter = Control.MOUSE_FILTER_PASS if show else Control.MOUSE_FILTER_IGNORE
	_root.process_mode = Node.PROCESS_MODE_INHERIT if show else Node.PROCESS_MODE_DISABLED
	if not show:
		_touch_input.reset()
	_set_gameplay_active(show)

## gameplay touch source 只在可见且非 modal 时激活，保证 Touch != Mouse。
func _set_gameplay_active(active: bool) -> void:
	if _active == active:
		return
	_active = active
	if _touch_input != null:
		_touch_input.set_active(active)

## Modal（Pause / Winner / Upgrade / Shop）打开时屏蔽 Touch Controls。
func set_modal_blocked(blocked: bool) -> void:
	if _modal_blocked == blocked:
		return
	_modal_blocked = blocked
	if blocked:
		_touch_input.reset()
	_update_visibility()

func is_modal_blocked() -> bool:
	return _modal_blocked

func set_touch_visible(visible: bool) -> void:
	_root.visible = visible

func is_touch_visible() -> bool:
	return _root.visible

func bind_player_input(player_input: PlayerInput) -> void:
	if _touch_input != null:
		_touch_input.bind_player_input(player_input)

func get_touch_input() -> TouchInput:
	return _touch_input

func get_move_stick() -> VirtualStick:
	return _move_stick

func get_aim_pad() -> TouchAimPad:
	return _aim_pad

func get_dash_button() -> TouchActionButton:
	return _dash_button

func get_weapon_button(slot: int) -> TouchActionButton:
	match slot:
		0:
			return _weapon1_button
		1:
			return _weapon2_button
		2:
			return _weapon3_button
		3:
			return _weapon4_button
	return null

func get_pause_button() -> TouchActionButton:
	return _pause_button

## 由 CombatSandbox 依据 WeaponHost.get_current_index() 同步选中态，与 HUD 一致。
func set_selected_weapon(index: int) -> void:
	for slot: int in 4:
		var btn: TouchActionButton = get_weapon_button(slot)
		if btn != null:
			btn.set_selected(slot == index)

func refresh_visibility() -> void:
	_update_visibility()

func _on_pause_just_pressed() -> void:
	pause_requested.emit()
