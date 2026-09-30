extends CanvasLayer
class_name TouchControls

## Touch Controls 容器：固定双摇杆 + 右下 Action Cluster。
## 屏幕空间常驻，不随 world/camera 移动。视觉来自 ui/game_theme.tres。
## 由 GameSettings.is_touch_controls_enabled() 决定整体显示，并支持临时 modal 屏蔽。
## 不包含战斗逻辑，只负责组合 VirtualStick / TouchActionButton / TouchInput。

signal touch_visibility_changed(visible: bool)

@onready var _move_stick: VirtualStick = $Root/SafeAreaRoot/MoveStick
@onready var _aim_stick: VirtualStick = $Root/SafeAreaRoot/AimStick
@onready var _fire_button: TouchActionButton = $Root/SafeAreaRoot/ActionCluster/FireButton
@onready var _dash_button: TouchActionButton = $Root/SafeAreaRoot/ActionCluster/DashButton
@onready var _ability0_button: TouchActionButton = $Root/SafeAreaRoot/ActionCluster/Ability0Button
@onready var _ability1_button: TouchActionButton = $Root/SafeAreaRoot/ActionCluster/Ability1Button
@onready var _touch_input: TouchInput = $Root/TouchInput
@onready var _root: Control = $Root
@onready var _safe_area: SafeAreaRoot = $Root/SafeAreaRoot

var _modal_blocked: bool = false

func _ready() -> void:
	_update_visibility()

func _process(delta: float) -> void:
	_update_visibility()

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

func get_aim_stick() -> VirtualStick:
	return _aim_stick

func get_fire_button() -> TouchActionButton:
	return _fire_button

func get_dash_button() -> TouchActionButton:
	return _dash_button

func get_ability0_button() -> TouchActionButton:
	return _ability0_button

func get_ability1_button() -> TouchActionButton:
	return _ability1_button

func refresh_visibility() -> void:
	_update_visibility()
