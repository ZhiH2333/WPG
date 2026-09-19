extends CanvasLayer
class_name ShopOffer

## P8 后买一张已有升级或 Skip。只展示与点选，不自己 spend。PROCESS_MODE_ALWAYS：单机选卡时 CombatSandbox 会冻场景树。卡片 osu 式错峰进场，逻辑开关仍瞬时。
signal bought(upgrade_id: StringName)
signal skipped
signal cancelled

var _defs: Array[UpgradeDef] = []
var _open: bool = false
var _cards: Array[Button] = []
var _titles: Array[Label] = []
var _descs: Array[Label] = []
var _costs: Array[Label] = []
var _player_input: PlayerInput
var _session: RunSession
var _presented_gold: int = 0
var _anim_tween: Tween

@onready var _root: Control = $Root
@onready var _dimmer: ColorRect = $Root/Dimmer
@onready var _center: CenterContainer = $Root/Center
@onready var _gold_label: Label = $Root/Center/Column/GoldLabel
@onready var _skip_button: Button = $Root/Center/Column/Skip

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	layer = 20
	_cards = [
		$Root/Center/Column/Cards/Card0 as Button,
		$Root/Center/Column/Cards/Card1 as Button,
		$Root/Center/Column/Cards/Card2 as Button,
	]
	_titles = [
		$Root/Center/Column/Cards/Card0/VBox/Title as Label,
		$Root/Center/Column/Cards/Card1/VBox/Title as Label,
		$Root/Center/Column/Cards/Card2/VBox/Title as Label,
	]
	_descs = [
		$Root/Center/Column/Cards/Card0/VBox/Desc as Label,
		$Root/Center/Column/Cards/Card1/VBox/Desc as Label,
		$Root/Center/Column/Cards/Card2/VBox/Desc as Label,
	]
	_costs = [
		$Root/Center/Column/Cards/Card0/VBox/Cost as Label,
		$Root/Center/Column/Cards/Card1/VBox/Cost as Label,
		$Root/Center/Column/Cards/Card2/VBox/Cost as Label,
	]
	for i: int in _cards.size():
		var card: Button = _cards[i]
		card.pressed.connect(_on_card_pressed.bind(i))
	_skip_button.pressed.connect(_skip)

func bind_player_input(player_input: PlayerInput) -> void:
	_player_input = player_input

func bind_session(session: RunSession) -> void:
	_session = session

func is_open() -> bool:
	return _open

func present(defs: Array[UpgradeDef], gold: int) -> void:
	UiAnim.kill_tween(_anim_tween)
	_defs = defs.duplicate()
	_presented_gold = gold
	_open = not _defs.is_empty()
	visible = _open
	_root.modulate.a = 1.0
	_refresh_cards()
	if not _open:
		return
	_anim_tween = UiAnim.enter_overlay(self, _dimmer, _center, _cards, true)

func close() -> void:
	_open = false
	if not visible:
		return
	UiAnim.kill_tween(_anim_tween)
	_anim_tween = UiAnim.exit_overlay(self, _root, true)
	_anim_tween.finished.connect(_finish_close)

func _finish_close() -> void:
	visible = false
	_root.modulate.a = 1.0
	_defs.clear()
	_refresh_cards()

func _process(_delta: float) -> void:
	if not _open or _player_input == null:
		return
	var slot: int = _player_input.get_weapon_slot_just_pressed()
	if slot >= 0 and slot <= 2:
		_pick_index(slot)
		return
	if slot == 3:
		_skip()

func _input(event: InputEvent) -> void:
	if not _open:
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		cancelled.emit()
		return
	var joy_button: InputEventJoypadButton = event as InputEventJoypadButton
	if joy_button != null and joy_button.pressed:
		if joy_button.button_index == JOY_BUTTON_START:
			get_viewport().set_input_as_handled()
			cancelled.emit()
			return
		if joy_button.button_index == JOY_BUTTON_DPAD_LEFT:
			get_viewport().set_input_as_handled()
			_pick_index(0)
			return
		if joy_button.button_index == JOY_BUTTON_DPAD_UP:
			get_viewport().set_input_as_handled()
			_pick_index(1)
			return
		if joy_button.button_index == JOY_BUTTON_DPAD_RIGHT:
			get_viewport().set_input_as_handled()
			_pick_index(2)
			return
		if joy_button.button_index == JOY_BUTTON_DPAD_DOWN:
			get_viewport().set_input_as_handled()
			_skip()
			return
	if event.is_action_pressed("weapon_pistol"):
		_pick_index(0)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("weapon_shotgun"):
		_pick_index(1)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("weapon_rifle"):
		_pick_index(2)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("weapon_smg"):
		_skip()
		get_viewport().set_input_as_handled()

func _on_card_pressed(index: int) -> void:
	_pick_index(index)

func _pick_index(index: int) -> void:
	if not _open:
		return
	if index < 0 or index >= _defs.size():
		return
	if _cards[index].disabled:
		return
	bought.emit(_defs[index].id)

func _skip() -> void:
	if not _open:
		return
	skipped.emit()

func _refresh_cards() -> void:
	var gold: int = _read_gold()
	_gold_label.text = "gold  %d" % gold
	for i: int in _cards.size():
		var show_card: bool = _open and i < _defs.size()
		_cards[i].visible = show_card
		if not show_card:
			_titles[i].text = ""
			_descs[i].text = ""
			_costs[i].text = ""
			_cards[i].disabled = true
			continue
		var def: UpgradeDef = _defs[i]
		var cost: int = _read_cost(def.id)
		_titles[i].text = def.title
		_descs[i].text = def.description
		_costs[i].text = "%d" % cost
		_cards[i].disabled = gold < cost

func _read_gold() -> int:
	if _session != null:
		return _session.get_gold()
	return _presented_gold

func _read_cost(upgrade_id: StringName) -> int:
	if _session != null:
		return _session.get_shop_cost(upgrade_id)
	return 30
