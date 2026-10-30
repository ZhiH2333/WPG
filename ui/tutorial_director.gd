extends Object
class_name TutorialDirector

## 新手引导状态机（全 static，禁止 Autoload）。旗标只经 GameSettings 写 settings.cfg [tutorial]。
enum Step {
	INACTIVE,
	T00_WELCOME,
	T00_SETTINGS_HINT,
	T01_HIGHLIGHT_SOLO,
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

const LOBBY_Z: int = 110
const COMBAT_LAYER: int = 28
const COMBAT_TOUCH_LAYER: int = 105
const COMBAT_ACTION_COUNT: int = 5

static var _step: Step = Step.INACTIVE
static var _active: bool = false
static var _combat_bound: bool = false
static var _upgrade_done: bool = false
static var _shop_done: bool = false
static var _pending_combat_return: bool = false
static var _start_on_next_main_menu: bool = false
static var _online_blocked: bool = false

static func current_step() -> Step:
	return _step

static func is_active() -> bool:
	return _active

static func is_combat_coach_step(step: Step = _step) -> bool:
	return step >= Step.T10_MOVE and step <= Step.T14_ABILITY

static func combat_action_index(step: Step = _step) -> int:
	match step:
		Step.T10_MOVE:
			return 1
		Step.T11_AIM_FIRE:
			return 2
		Step.T12_DASH:
			return 3
		Step.T13_SWITCH_WEAPON:
			return 4
		Step.T14_ABILITY:
			return 5
		_:
			return 0

static func set_online_blocked(blocked: bool) -> void:
	_online_blocked = blocked

static func should_auto_show() -> bool:
	if _online_blocked:
		return false
	if _start_on_next_main_menu:
		return true
	if GameSettings.is_tutorial_replay_requested():
		return true
	return not GameSettings.is_tutorial_seen()

static func try_begin_on_main_menu() -> void:
	var force_replay: bool = GameSettings.is_tutorial_replay_requested() or _start_on_next_main_menu
	if force_replay:
		## 重开：无论当前是否在引导中，都从 T00 重跑。
		_active = false
		_combat_bound = false
		_upgrade_done = false
		_shop_done = false
	elif _active and (_combat_bound or is_combat_coach_step() or _step >= Step.T20_UPGRADE):
		## 战斗中途回大厅：未 seen 则回到 SOLO 高亮，方便续跑进战场段。
		_combat_bound = false
		_step = Step.T01_HIGHLIGHT_SOLO
		return
	elif _active:
		return
	if not should_auto_show():
		return
	_active = true
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
	## 引导中进联机：写 seen 并卸层（终稿）。
	if not _active:
		return
	GameSettings.mark_tutorial_seen()
	_teardown(false)

static func advance_from_host() -> void:
	if not _active:
		return
	match _step:
		Step.T00_WELCOME:
			_step = Step.T00_SETTINGS_HINT
		Step.T00_SETTINGS_HINT:
			_step = Step.T01_HIGHLIGHT_SOLO
		Step.T40_LOOP_GOAL:
			_finish_success()
		_:
			pass

static func notify_solo_rail_pressed() -> void:
	## 禁止假 pressed：只在玩家真点 SOLO 后推进。
	if _step == Step.T01_HIGHLIGHT_SOLO:
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
	_teardown(false)

static func request_replay() -> void:
	GameSettings.set_tutorial_replay_requested(true)
	GameSettings.save_to_disk()

static func on_settings_closed(from_combat: bool) -> void:
	if not GameSettings.is_tutorial_replay_requested() and not _start_on_next_main_menu:
		return
	if from_combat:
		## 战斗内重开：回主菜单后再播 T00（旗标改由 try_begin 消费）。
		_start_on_next_main_menu = true
		_pending_combat_return = true
		GameSettings.clear_tutorial_replay_requested()
		GameSettings.save_to_disk()
		return
	## 大厅：勿先清 replay，否则 should_auto_show 在已 seen 时会失败。
	try_begin_on_main_menu()

static func consume_combat_return_to_menu() -> bool:
	if not _pending_combat_return:
		return false
	_pending_combat_return = false
	return true

static func blocks_upgrade_cancel() -> bool:
	return _active and _step == Step.T20_UPGRADE and not _upgrade_done

static func blocks_shop_skip() -> bool:
	return _active and _step == Step.T30_SHOP and not _shop_done

static func needs_shop_affordable() -> bool:
	return _active and _step == Step.T30_SHOP and not _shop_done

static func ui_layer_for_step() -> int:
	if is_combat_coach_step() and GameSettings.is_touch_controls_enabled():
		return COMBAT_TOUCH_LAYER
	if is_combat_coach_step():
		return COMBAT_LAYER
	return COMBAT_LAYER

static func _finish_success() -> void:
	GameSettings.mark_tutorial_seen()
	_teardown(true)

static func _teardown(mark_done_step: bool) -> void:
	_step = Step.T99_DONE if mark_done_step else Step.INACTIVE
	_active = false
	_combat_bound = false
