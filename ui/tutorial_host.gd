extends Control
class_name TutorialHost

## 新手引导 UI 宿主：Spotlight / Callout / CoachBar / Skip。PROCESS_MODE_ALWAYS。
const CALLOUT_MAX_W: float = 360.0
const COMBAT_VEIL_ALPHA: float = 0.20

enum HostContext { MAIN_MENU, COMBAT }

var _context: HostContext = HostContext.MAIN_MENU
var _sandbox: CombatSandbox
var _menu: MainMenu
var _move_seen: bool = false
var _local_player: Player
var _ability_hooked: bool = false
var _last_step: TutorialDirector.Step = TutorialDirector.Step.INACTIVE

@onready var _spotlight: TutorialSpotlight = $Spotlight
@onready var _callout_panel: PanelContainer = $Callout
@onready var _callout_title: Label = $Callout/Column/Title
@onready var _callout_body: Label = $Callout/Column/Body
@onready var _callout_chip: Label = $Callout/Column/Chip
@onready var _callout_continue: Button = $Callout/Column/Continue
@onready var _coach_bar: PanelContainer = $CoachBar
@onready var _coach_label: Label = $CoachBar/Label
@onready var _skip_button: Button = $Skip

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_callout_panel.theme_type_variation = &"FloatingPanel"
	_callout_panel.custom_minimum_size.x = CALLOUT_MAX_W
	_coach_bar.theme_type_variation = &"FloatingPanel"
	_coach_bar.custom_minimum_size = Vector2(640, 64)
	_coach_label.theme_type_variation = &"OfferTitle"
	_skip_button.text = tr("TUTORIAL_SKIP")
	_callout_continue.text = tr("TUTORIAL_CONTINUE")
	_callout_continue.pressed.connect(_on_continue_pressed)
	_skip_button.pressed.connect(_on_skip_pressed)
	_coach_bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_coach_bar.anchor_left = 0.5
	_coach_bar.anchor_right = 0.5
	_coach_bar.anchor_top = 1.0
	_coach_bar.anchor_bottom = 1.0
	_coach_bar.offset_left = -320.0
	_coach_bar.offset_right = 320.0
	_coach_bar.offset_top = -96.0
	_coach_bar.offset_bottom = -32.0
	if get_parent() is MainMenu:
		_context = HostContext.MAIN_MENU
		_menu = get_parent() as MainMenu
		call_deferred("_boot_main_menu")
	elif get_parent() is CombatSandbox:
		_context = HostContext.COMBAT
		_sandbox = get_parent() as CombatSandbox
		call_deferred("_boot_combat")

func _boot_main_menu() -> void:
	TutorialDirector.try_begin_on_main_menu()
	_refresh()

func _boot_combat() -> void:
	if not TutorialDirector.is_active():
		return
	call_deferred("_notify_sandbox_ready")

func _notify_sandbox_ready() -> void:
	await get_tree().process_frame
	TutorialDirector.notify_sandbox_ready()
	_bind_combat_player()
	_refresh()

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
	if step == TutorialDirector.Step.T10_MOVE and input.move_vector.length() > 0.35:
		if not _move_seen:
			_move_seen = true
			TutorialDirector.notify_combat_action(&"move")
	if step == TutorialDirector.Step.T12_DASH and input.dash_just_pressed:
		TutorialDirector.notify_combat_action(&"dash")
	if step == TutorialDirector.Step.T13_SWITCH_WEAPON and input.get_weapon_slot_just_pressed() >= 0:
		TutorialDirector.notify_combat_action(&"weapon")

func _on_player_shot(_aim: Vector2, _weapon: Weapon) -> void:
	if TutorialDirector.current_step() == TutorialDirector.Step.T11_AIM_FIRE:
		TutorialDirector.notify_combat_action(&"fire")

func _on_ability_activated(_index: int, _def: Resource) -> void:
	if TutorialDirector.current_step() == TutorialDirector.Step.T14_ABILITY:
		TutorialDirector.notify_combat_action(&"ability")

func _on_continue_pressed() -> void:
	TutorialDirector.advance_from_host()

func _on_skip_pressed() -> void:
	TutorialDirector.skip_all()
	_end_combat_freeze()
	visible = false

func _refresh() -> void:
	if not TutorialDirector.is_active():
		visible = false
		_end_combat_freeze()
		return
	visible = true
	if get_parent() is CanvasLayer:
		(get_parent() as CanvasLayer).layer = TutorialDirector.ui_layer_for_step()
	z_index = 110 if _context == HostContext.MAIN_MENU else 0
	move_to_front()
	var step: TutorialDirector.Step = TutorialDirector.current_step()
	_apply_step_ui(step)

func _apply_step_ui(step: TutorialDirector.Step) -> void:
	_spotlight.clear_target()
	_callout_panel.visible = false
	_coach_bar.visible = false
	_skip_button.visible = true
	_spotlight.set_veil_strength(-1.0)
	match step:
		TutorialDirector.Step.T00_WELCOME:
			_show_callout("TUTORIAL_WELCOME_TITLE", "TUTORIAL_WELCOME_BODY", "", true)
		TutorialDirector.Step.T00_SETTINGS_HINT:
			_show_callout("TUTORIAL_SETTINGS_HINT_TITLE", "TUTORIAL_SETTINGS_HINT_BODY", "", true)
		TutorialDirector.Step.T01_OPEN_PLAY:
			if _menu != null:
				_spotlight.set_target(_menu.get_solo_button())
			_show_callout("TUTORIAL_SOLO_TITLE", "TUTORIAL_SOLO_BODY", "", false)
		TutorialDirector.Step.T02_CREATE_OR_PICK:
			_show_callout("TUTORIAL_RECORDS_TITLE", "TUTORIAL_RECORDS_BODY", "", false)
		TutorialDirector.Step.T03_ENTER_RUN:
			_show_callout("TUTORIAL_LOADING_TITLE", "TUTORIAL_LOADING_BODY", "", false)
		TutorialDirector.Step.T10_MOVE:
			_show_combat(TutorialDirector.copy_key("TUTORIAL_MOVE"))
		TutorialDirector.Step.T11_AIM_FIRE:
			_show_combat(TutorialDirector.copy_key("TUTORIAL_FIRE"))
		TutorialDirector.Step.T12_DASH:
			_show_combat(TutorialDirector.copy_key("TUTORIAL_DASH"))
		TutorialDirector.Step.T13_SWITCH_WEAPON:
			_show_combat(TutorialDirector.copy_key("TUTORIAL_WEAPON"))
		TutorialDirector.Step.T14_ABILITY:
			_show_combat(TutorialDirector.copy_key("TUTORIAL_ABILITY"))
		TutorialDirector.Step.T20_UPGRADE:
			_show_callout("TUTORIAL_UPGRADE_TITLE", "TUTORIAL_UPGRADE_BODY", "", false)
			_end_combat_freeze()
		TutorialDirector.Step.T30_SHOP:
			_show_callout("TUTORIAL_SHOP_TITLE", "TUTORIAL_SHOP_BODY", "", false)
		TutorialDirector.Step.T40_LOOP_GOAL:
			_show_callout("TUTORIAL_LOOP_TITLE", "TUTORIAL_LOOP_BODY", "", true)
			_end_combat_freeze()
		_:
			visible = false

func _show_callout(title_key: String, body_key: String, chip_key: String, show_continue: bool) -> void:
	_callout_panel.visible = true
	_callout_title.text = tr(title_key) if not title_key.is_empty() else ""
	_callout_title.visible = not title_key.is_empty()
	_callout_body.text = tr(body_key)
	_callout_chip.text = tr(chip_key) if not chip_key.is_empty() else ""
	_callout_chip.visible = not chip_key.is_empty()
	_callout_continue.visible = show_continue
	_layout_callout()

func _show_combat(text_key: String) -> void:
	_coach_bar.visible = true
	_coach_label.text = tr(text_key)
	_spotlight.set_veil_strength(COMBAT_VEIL_ALPHA)
	if _sandbox != null:
		_sandbox.request_tutorial_world_freeze(true)

func _end_combat_freeze() -> void:
	if _sandbox != null:
		_sandbox.request_tutorial_world_freeze(false)

func _layout_callout() -> void:
	_callout_panel.position = Vector2(maxf(48.0, (size.x - CALLOUT_MAX_W) * 0.5), 120.0)

func notify_solo_pressed() -> void:
	TutorialDirector.notify_solo_rail_pressed()

func notify_record_committed() -> void:
	TutorialDirector.notify_record_committed()

func refresh_from_director() -> void:
	_refresh()
