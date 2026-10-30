extends Control
class_name TutorialHost

## 新手引导 UI：大厅 Spotlight+Callout；战斗 CoachBar+Chip。Skip 在面板右侧。PROCESS_MODE_ALWAYS。
const CALLOUT_MAX_W: float = 360.0
const CALLOUT_PAD: float = 16.0
const COACH_H: float = 64.0
const COACH_BOTTOM: float = 32.0
const COMBAT_VEIL_CAP: float = 0.20
const MOVE_THRESHOLD: float = 0.35
const ENTER_RISE: float = 14.0

enum HostContext { MAIN_MENU, COMBAT }

var _context: HostContext = HostContext.MAIN_MENU
var _sandbox: CombatSandbox
var _menu: MainMenu
var _move_latched: bool = false
var _local_player: Player
var _ability_hooked: bool = false
var _last_step: TutorialDirector.Step = TutorialDirector.Step.INACTIVE
var _enter_tween: Tween
var _layer: CanvasLayer

@onready var _spotlight: TutorialSpotlight = $Spotlight
@onready var _callout: PanelContainer = $Callout
@onready var _callout_margin: MarginContainer = $Callout/Margin
@onready var _title: Label = $Callout/Margin/Column/Header/Title
@onready var _underline: ColorRect = $Callout/Margin/Column/Underline
@onready var _body: Label = $Callout/Margin/Column/Body
@onready var _continue: Button = $Callout/Margin/Column/Continue
@onready var _callout_skip: Button = $Callout/Margin/Column/Header/Skip
@onready var _coach: PanelContainer = $CoachBar
@onready var _chip: Label = $CoachBar/Row/Chip
@onready var _coach_label: Label = $CoachBar/Row/Text
@onready var _coach_skip: Button = $CoachBar/Row/Skip

func _ready() -> void:
	add_to_group("wpg_locale")
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_layer = get_parent() as CanvasLayer
	_callout.theme_type_variation = &"FloatingPanel"
	_callout.custom_minimum_size.x = CALLOUT_MAX_W
	_callout_margin.add_theme_constant_override("margin_left", int(CALLOUT_PAD))
	_callout_margin.add_theme_constant_override("margin_top", int(CALLOUT_PAD))
	_callout_margin.add_theme_constant_override("margin_right", int(CALLOUT_PAD))
	_callout_margin.add_theme_constant_override("margin_bottom", int(CALLOUT_PAD))
	_underline.color = UiType.INK
	_underline.custom_minimum_size = Vector2(48, 2)
	_coach.theme_type_variation = &"FloatingPanel"
	_coach.custom_minimum_size = Vector2(0, COACH_H)
	_chip.theme_type_variation = &"Caption"
	_coach_label.theme_type_variation = &"OfferTitle"
	_callout_skip.theme_type_variation = &"EmptyButtonMuted"
	_coach_skip.theme_type_variation = &"EmptyButtonMuted"
	_continue.theme_type_variation = &"PillPink"
	## 面板本身穿透；只有 Skip / Continue 接点击，避免盖住建档页与升级/商店选卡。
	_callout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_callout_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_coach.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child: Node in _callout.find_children("*", "Control", true, false):
		var control: Control = child as Control
		if control == _callout_skip or control == _continue:
			control.mouse_filter = Control.MOUSE_FILTER_STOP
		else:
			control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child: Node in _coach.find_children("*", "Control", true, false):
		var control: Control = child as Control
		if control == _coach_skip:
			control.mouse_filter = Control.MOUSE_FILTER_STOP
		else:
			control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_refresh_static_copy()
	_callout_skip.pressed.connect(_on_skip_pressed)
	_coach_skip.pressed.connect(_on_skip_pressed)
	_continue.pressed.connect(_on_continue_pressed)
	_layout_coach_bar()
	if _find_main_menu() != null:
		_context = HostContext.MAIN_MENU
		_menu = _find_main_menu()
		z_index = TutorialDirector.LOBBY_Z
		call_deferred("_boot_main_menu")
	elif _find_sandbox() != null:
		_context = HostContext.COMBAT
		_sandbox = _find_sandbox()
		call_deferred("_boot_combat")

func refresh_locale() -> void:
	_refresh_static_copy()
	if TutorialDirector.is_active():
		_refresh()

func notify_solo_pressed() -> void:
	TutorialDirector.notify_solo_rail_pressed()
	_refresh()

func notify_record_committed() -> void:
	TutorialDirector.notify_record_committed()
	_refresh()

func refresh_from_director() -> void:
	_refresh()

func _boot_main_menu() -> void:
	TutorialDirector.try_begin_on_main_menu()
	_refresh()

func _boot_combat() -> void:
	if not TutorialDirector.is_active():
		visible = false
		return
	await get_tree().process_frame
	TutorialDirector.notify_sandbox_ready()
	_bind_combat_player()
	_refresh()

func _find_main_menu() -> MainMenu:
	var node: Node = self
	while node != null:
		if node is MainMenu:
			return node as MainMenu
		node = node.get_parent()
	return null

func _find_sandbox() -> CombatSandbox:
	var node: Node = self
	while node != null:
		if node is CombatSandbox:
			return node as CombatSandbox
		node = node.get_parent()
	return null

func _bind_combat_player() -> void:
	if _sandbox == null:
		return
	_local_player = _sandbox.get_local_player_for_tutorial()
	if _local_player == null:
		return
	if not _local_player.shot_fired.is_connected(_on_player_shot):
		_local_player.shot_fired.connect(_on_player_shot)
	var ability: AbilityController = _local_player.get_ability_controller()
	if ability != null and not _ability_hooked:
		ability.ability_activated.connect(_on_ability_activated)
		_ability_hooked = true

func _process(_delta: float) -> void:
	if not TutorialDirector.is_active():
		if visible:
			_end_combat_freeze()
			visible = false
		return
	var step: TutorialDirector.Step = TutorialDirector.current_step()
	if step != _last_step:
		_last_step = step
		_refresh()
	elif _context == HostContext.COMBAT:
		_poll_combat_actions()

func _poll_combat_actions() -> void:
	if _local_player == null:
		return
	var input: PlayerInput = _local_player.get_player_input()
	if input == null:
		return
	var step: TutorialDirector.Step = TutorialDirector.current_step()
	if step == TutorialDirector.Step.T10_MOVE and input.move_vector.length() > MOVE_THRESHOLD:
		if not _move_latched:
			_move_latched = true
			TutorialDirector.notify_combat_action(&"move")
	elif step == TutorialDirector.Step.T12_DASH and input.dash_just_pressed:
		TutorialDirector.notify_combat_action(&"dash")
	elif step == TutorialDirector.Step.T13_SWITCH_WEAPON and input.get_weapon_slot_just_pressed() >= 0:
		TutorialDirector.notify_combat_action(&"weapon")

func _on_player_shot(_aim: Vector2, _weapon: Weapon) -> void:
	if TutorialDirector.current_step() == TutorialDirector.Step.T11_AIM_FIRE:
		TutorialDirector.notify_combat_action(&"fire")

func _on_ability_activated(_index: int, _def: Resource) -> void:
	if TutorialDirector.current_step() == TutorialDirector.Step.T14_ABILITY:
		TutorialDirector.notify_combat_action(&"ability")

func _on_continue_pressed() -> void:
	TutorialDirector.advance_from_host()
	_refresh()

func _on_skip_pressed() -> void:
	TutorialDirector.skip_all()
	_end_combat_freeze()
	visible = false

func _refresh_static_copy() -> void:
	_callout_skip.text = tr("TUTORIAL_SKIP")
	_coach_skip.text = tr("TUTORIAL_SKIP")
	_continue.text = tr("TUTORIAL_CONTINUE")

func _refresh() -> void:
	if not TutorialDirector.is_active():
		visible = false
		_end_combat_freeze()
		return
	visible = true
	if _layer != null:
		_layer.layer = TutorialDirector.ui_layer_for_step()
	if _context == HostContext.MAIN_MENU:
		z_index = TutorialDirector.LOBBY_Z
	move_to_front()
	_apply_step_ui(TutorialDirector.current_step())

func _apply_step_ui(step: TutorialDirector.Step) -> void:
	_spotlight.clear_target()
	_spotlight.set_veil_strength(0.0)
	_callout.visible = false
	_coach.visible = false
	match step:
		TutorialDirector.Step.T00_WELCOME:
			_show_callout("TUTORIAL_WELCOME_TITLE", "TUTORIAL_WELCOME_BODY", true, null, false)
		TutorialDirector.Step.T00_SETTINGS_HINT:
			_show_callout("TUTORIAL_SETTINGS_HINT_TITLE", "TUTORIAL_SETTINGS_HINT_BODY", true, null, false)
		TutorialDirector.Step.T01_HIGHLIGHT_SOLO:
			var solo: Control = _menu.get_solo_button() if _menu != null else null
			_show_callout("TUTORIAL_SOLO_TITLE", "TUTORIAL_SOLO_BODY", false, solo, true)
		TutorialDirector.Step.T02_CREATE_OR_PICK:
			## 建/选档页：无全屏罩，Callout 贴顶，避免挡住 RecordSelector。
			_show_callout("TUTORIAL_RECORDS_TITLE", "TUTORIAL_RECORDS_BODY", false, null, false, true)
		TutorialDirector.Step.T03_ENTER_RUN:
			_show_callout("TUTORIAL_LOADING_TITLE", "TUTORIAL_LOADING_BODY", false, null, false, true)
		TutorialDirector.Step.T10_MOVE:
			_show_combat(_move_copy_key(), step)
		TutorialDirector.Step.T11_AIM_FIRE:
			_show_combat(_fire_copy_key(), step)
		TutorialDirector.Step.T12_DASH:
			_show_combat(_dash_copy_key(), step)
		TutorialDirector.Step.T13_SWITCH_WEAPON:
			_show_combat(_weapon_copy_key(), step)
		TutorialDirector.Step.T14_ABILITY:
			_show_combat(_ability_copy_key(), step)
		TutorialDirector.Step.T20_UPGRADE:
			## 升级层在 CanvasLayer 20；教程不得盖住选卡（旧 Callout+罩会挡点击）。
			_end_combat_freeze()
			_show_offer_coach("TUTORIAL_UPGRADE_TITLE", "TUTORIAL_UPGRADE_BODY")
		TutorialDirector.Step.T30_SHOP:
			_end_combat_freeze()
			_show_offer_coach("TUTORIAL_SHOP_TITLE", "TUTORIAL_SHOP_BODY")
		TutorialDirector.Step.T40_LOOP_GOAL:
			_end_combat_freeze()
			_show_callout("TUTORIAL_LOOP_TITLE", "TUTORIAL_LOOP_BODY", true, null, false)
		_:
			visible = false

func _show_callout(
	title_key: String,
	body_key: String,
	show_continue: bool,
	spotlight: Control,
	use_page_veil: bool = false,
	top_compact: bool = false
) -> void:
	_callout.visible = true
	_title.text = tr(title_key)
	_body.text = tr(body_key)
	_body.visible = not body_key.is_empty()
	_continue.visible = show_continue
	_callout_skip.visible = true
	if spotlight != null:
		_spotlight.set_target(spotlight, true)
		if use_page_veil:
			_spotlight.set_veil_strength(-1.0)
		else:
			_spotlight.set_veil_strength(0.0)
	elif use_page_veil:
		_spotlight.set_veil_strength(-1.0)
	else:
		_spotlight.set_veil_strength(0.0)
	_layout_callout(spotlight, top_compact)
	_play_enter(_callout)

func _show_offer_coach(chip_key: String, body_key: String) -> void:
	## 底栏提示，无遮罩；不挡 UpgradeOffer/ShopOffer（layer 20）选卡。
	_spotlight.clear_target()
	_spotlight.set_veil_strength(0.0)
	if _layer != null:
		_layer.layer = TutorialDirector.COMBAT_LAYER
	_coach.visible = true
	_chip.text = tr(chip_key)
	_chip.visible = true
	_coach_label.text = tr(body_key)
	_coach_skip.visible = true
	_layout_coach_bar()
	_play_enter(_coach)

func _move_copy_key() -> String:
	return "TUTORIAL_MOVE_TOUCH" if GameSettings.is_touch_controls_enabled() else "TUTORIAL_MOVE_DESKTOP"

func _fire_copy_key() -> String:
	return "TUTORIAL_FIRE_TOUCH" if GameSettings.is_touch_controls_enabled() else "TUTORIAL_FIRE_DESKTOP"

func _dash_copy_key() -> String:
	return "TUTORIAL_DASH_TOUCH" if GameSettings.is_touch_controls_enabled() else "TUTORIAL_DASH_DESKTOP"

func _weapon_copy_key() -> String:
	return "TUTORIAL_WEAPON_TOUCH" if GameSettings.is_touch_controls_enabled() else "TUTORIAL_WEAPON_DESKTOP"

func _ability_copy_key() -> String:
	return "TUTORIAL_ABILITY_TOUCH" if GameSettings.is_touch_controls_enabled() else "TUTORIAL_ABILITY_DESKTOP"

func _show_combat(text_key: String, step: TutorialDirector.Step) -> void:
	_coach.visible = true
	_coach_label.text = tr(text_key)
	var index: int = TutorialDirector.combat_action_index(step)
	_chip.text = tr("TUTORIAL_STEP_CHIP") % [index, TutorialDirector.COMBAT_ACTION_COUNT]
	_chip.visible = index > 0
	## 战斗操作罩默认无；上限黑 α 0.20。当前步骤用轻罩帮助聚焦条。
	_spotlight.set_veil_strength(COMBAT_VEIL_CAP * 0.55)
	if _sandbox != null:
		_sandbox.request_tutorial_world_freeze(true)
	_layout_coach_bar()
	_play_enter(_coach)

func _end_combat_freeze() -> void:
	if _sandbox != null:
		_sandbox.request_tutorial_world_freeze(false)

func _layout_callout(spotlight: Control, top_compact: bool = false) -> void:
	var view: Vector2 = size
	if view.x <= 1.0:
		view = get_viewport_rect().size
	var panel_w: float = minf(CALLOUT_MAX_W, view.x - 48.0)
	_callout.custom_minimum_size.x = panel_w
	var x: float = (view.x - panel_w) * 0.5
	var y: float = 112.0
	if top_compact:
		## 顶栏下贴右，给建档/选角表单让出中部。
		panel_w = minf(300.0, view.x - 48.0)
		_callout.custom_minimum_size.x = panel_w
		x = maxf(24.0, view.x - panel_w - 24.0)
		y = 72.0
	elif spotlight != null and is_instance_valid(spotlight):
		var hole: Rect2 = _spotlight.hole_rect()
		if hole.size.y > 0.0:
			## 优先放在高亮上方；空间不够则落到下方。
			var above: float = hole.position.y - 24.0 - 160.0
			if above >= 72.0:
				y = above
			else:
				y = hole.end.y + 28.0
			x = clampf(hole.get_center().x - panel_w * 0.5, 24.0, maxf(24.0, view.x - panel_w - 24.0))
	_callout.position = Vector2(x, y)
	_callout.size = Vector2(panel_w, 0.0)
	_callout.reset_size()

func _layout_coach_bar() -> void:
	_coach.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_coach.anchor_left = 0.5
	_coach.anchor_right = 0.5
	_coach.anchor_top = 1.0
	_coach.anchor_bottom = 1.0
	var width: float = minf(720.0, maxf(480.0, size.x * 0.62))
	_coach.offset_left = -width * 0.5
	_coach.offset_right = width * 0.5
	_coach.offset_top = -(COACH_BOTTOM + COACH_H)
	_coach.offset_bottom = -COACH_BOTTOM

func _play_enter(panel: Control) -> void:
	UiAnim.kill_tween(_enter_tween)
	panel.modulate.a = 0.0
	var rest_y: float = panel.position.y
	panel.position.y = rest_y + ENTER_RISE
	_enter_tween = create_tween()
	_enter_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_enter_tween.set_parallel(true)
	_enter_tween.tween_property(panel, "modulate:a", 1.0, UiAnim.CONTENT_FADE_SEC).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	_enter_tween.tween_property(panel, "position:y", rest_y, UiAnim.CONTENT_FADE_SEC).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
