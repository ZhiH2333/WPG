extends Object
class_name TutorialDirector

## 新手引导状态机（全 static，非 Autoload）。旗标只经 GameSettings 写入 settings.cfg。
enum Step {
	INACTIVE,
	T00_WELCOME,
	T00_SETTINGS_HINT,
	T01_OPEN_PLAY,
	T02_CREATE_OR_PICK,
	T03_ENTER_RUN,
	T10_MOVE,
	T11_AIM_FIRE,
	T12_DASH,
	T13_SWITCH_WEAPON,
	T14_ABILITY,
	T20_UPGRADE,
	T30_SHOP,
	T40_LOOP_GOAL,
	T99_DONE,
}

const COMBAT_LAYER: int = 28
const COMBAT_TOUCH_LAYER: int = 105

static var _step: Step = Step.INACTIVE
static var _active: bool = false
static var _awaiting_solo: bool = false
static var _combat_bound: bool = false
static var _upgrade_done: bool = false
static var _shop_done: bool = false
static var _pending_combat_return: bool = false
static var _start_on_next_main_menu: bool = false

static func current_step() -> Step:
	return _step

static func is_active() -> bool:
	return _active

static func is_combat_step(step: Step = _step) -> bool:
	return step >= Step.T10_MOVE and step <= Step.T14_ABILITY

static func should_auto_start_on_main_menu() -> bool:
	if _start_on_next_main_menu:
		return true
	if GameSettings.is_tutorial_replay_requested():
		return true
	return not GameSettings.is_tutorial_seen()

static func try_begin_on_main_menu() -> void:
	if not should_auto_start_on_main_menu():
		return
	_active = true
	_awaiting_solo = true
	_combat_bound = false
	_upgrade_done = false
	_shop_done = false
	if GameSettings.is_tutorial_replay_requested():
		GameSettings.clear_tutorial_replay_requested()
		GameSettings.save_to_disk()
	if _start_on_next_main_menu:
		_start_on_next_main_menu = false
	_step = Step.T00_WELCOME

static func on_multiplayer_entered() -> void:
	if not _active:
		return
	_step = Step.INACTIVE
	_active = false
	_awaiting_solo = false

static func advance_from_host() -> void:
	if not _active:
		return
	match _step:
		Step.T00_WELCOME:
			_step = Step.T00_SETTINGS_HINT
		Step.T00_SETTINGS_HINT:
			_step = Step.T01_OPEN_PLAY
		Step.T01_OPEN_PLAY:
			_step = Step.T02_CREATE_OR_PICK
		Step.T02_CREATE_OR_PICK:
			_step = Step.T03_ENTER_RUN
		Step.T40_LOOP_GOAL:
			_finish_success()
		_:
			pass

static func notify_solo_rail_pressed() -> void:
	if _step == Step.T01_OPEN_PLAY:
		_step = Step.T02_CREATE_OR_PICK

static func notify_record_committed() -> void:
	if _step == Step.T02_CREATE_OR_PICK:
		_step = Step.T03_ENTER_RUN

static func notify_sandbox_ready() -> void:
	if not _active or _step != Step.T03_ENTER_RUN:
		return
	_combat_bound = true
	_step = Step.T10_MOVE

static func notify_combat_action(kind: StringName) -> void:
	if not _active or not _combat_bound:
		return
	match _step:
		Step.T10_MOVE:
			if kind == &"move":
				_step = Step.T11_AIM_FIRE
		Step.T11_AIM_FIRE:
			if kind == &"fire":
				_step = Step.T12_DASH
		Step.T12_DASH:
			if kind == &"dash":
				_step = Step.T13_SWITCH_WEAPON
		Step.T13_SWITCH_WEAPON:
			if kind == &"weapon":
				_step = Step.T14_ABILITY
		Step.T14_ABILITY:
			if kind == &"ability":
				_step = Step.T20_UPGRADE

static func notify_upgrade_open() -> bool:
	if not _active or _upgrade_done:
		return false
	if _step < Step.T20_UPGRADE:
		_step = Step.T20_UPGRADE
	return _step == Step.T20_UPGRADE

static func notify_upgrade_picked() -> void:
	if _step != Step.T20_UPGRADE:
		return
	_upgrade_done = true
	_step = Step.T30_SHOP

static func notify_shop_open() -> bool:
	if not _active or _shop_done:
		return false
	if _step < Step.T30_SHOP and not _upgrade_done:
		return false
	if _step == Step.T20_UPGRADE:
		_step = Step.T30_SHOP
	return _step == Step.T30_SHOP

static func notify_shop_purchased() -> void:
	if _step != Step.T30_SHOP:
		return
	_shop_done = true
	_step = Step.T40_LOOP_GOAL

static func skip_all() -> void:
	GameSettings.mark_tutorial_skipped()
	_finish_success()

static func request_replay() -> void:
	GameSettings.set_tutorial_replay_requested(true)
	GameSettings.save_to_disk()

static func on_settings_closed(from_combat: bool) -> void:
	if not GameSettings.is_tutorial_replay_requested():
		return
	if from_combat:
		_start_on_next_main_menu = true
		_pending_combat_return = true
		GameSettings.clear_tutorial_replay_requested()
		GameSettings.save_to_disk()
		return
	GameSettings.clear_tutorial_replay_requested()
	GameSettings.save_to_disk()
	try_begin_on_main_menu()

static func consume_combat_return_to_menu() -> bool:
	if not _pending_combat_return:
		return false
	_pending_combat_return = false
	return true

static func blocks_upgrade_cancel() -> bool:
	return _active and _step == Step.T20_UPGRADE

static func blocks_shop_skip() -> bool:
	return _active and _step == Step.T30_SHOP

static func needs_shop_affordable() -> bool:
	return _active and _step == Step.T30_SHOP and not _shop_done

static func copy_key(base: String) -> String:
	if GameSettings.is_touch_controls_enabled():
		return "%s_TOUCH" % base
	return "%s_DESKTOP" % base

static func ui_layer_for_step() -> int:
	if is_combat_step() and GameSettings.is_touch_controls_enabled():
		return COMBAT_TOUCH_LAYER
	if is_combat_step():
		return COMBAT_LAYER
	return 110

static func _finish_success() -> void:
	GameSettings.mark_tutorial_seen()
	_step = Step.T99_DONE
	_active = false
	_awaiting_solo = false
	_combat_bound = false
