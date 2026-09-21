extends CanvasLayer
class_name ShopOffer

## P8 后买一张已有升级、跟班，或 Skip。跟班点了先进选枪，不自己 spend。PROCESS_MODE_ALWAYS：单机选卡时 CombatSandbox 会冻场景树。
enum View { BROWSE, PICK_GUN }

signal bought(upgrade_id: StringName)
signal picked_companion(companion_id: StringName, weapon_index: int)
signal skipped
signal cancelled

const BROWSE_TITLE: String = "SHOP"
const PICK_TITLE: String = "Pick a gun"
const SKIP_TEXT: String = "Skip"
const BACK_TEXT: String = "Back"
const GUN_TITLES: PackedStringArray = ["Pistol", "Shotgun", "Rifle", "Smg"]

var _cards_data: Array[ShopCard] = []
var _open: bool = false
var _view: View = View.BROWSE
var _pending_companion: CompanionDef
var _cards: Array[Button] = []
var _titles: Array[Label] = []
var _descs: Array[Label] = []
var _costs: Array[Label] = []
var _gun_buttons: Array[Button] = []
var _player_input: PlayerInput
var _session: RunSession
var _presented_gold: int = 0
var _anim_tween: Tween

@onready var _root: Control = $Root
@onready var _dimmer: ColorRect = $Root/Dimmer
@onready var _center: CenterContainer = $Root/Center
@onready var _title_label: Label = $Root/Center/Column/Title
@onready var _gold_label: Label = $Root/Center/Column/GoldLabel
@onready var _card_row: HBoxContainer = $Root/Center/Column/Cards
@onready var _gun_row: HBoxContainer = $Root/Center/Column/GunRow
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
	_gun_buttons = [
		$Root/Center/Column/GunRow/Gun0 as Button,
		$Root/Center/Column/GunRow/Gun1 as Button,
		$Root/Center/Column/GunRow/Gun2 as Button,
		$Root/Center/Column/GunRow/Gun3 as Button,
	]
	for i: int in _cards.size():
		_cards[i].pressed.connect(_on_card_pressed.bind(i))
	for i: int in _gun_buttons.size():
		_gun_buttons[i].pressed.connect(_on_gun_pressed.bind(i))
		_gun_buttons[i].text = GUN_TITLES[i]
	_skip_button.pressed.connect(_on_skip_or_back)

func bind_player_input(player_input: PlayerInput) -> void:
	_player_input = player_input

func bind_session(session: RunSession) -> void:
	_session = session

func is_open() -> bool:
	return _open

func present(cards: Array[ShopCard], gold: int) -> void:
	UiAnim.kill_tween(_anim_tween)
	_cards_data = cards.duplicate()
	_presented_gold = gold
	_pending_companion = null
	_view = View.BROWSE
	_open = not _cards_data.is_empty()
	visible = _open
	_root.modulate.a = 1.0
	_refresh_view()
	if not _open:
		return
	_anim_tween = UiAnim.enter_overlay(self, _dimmer, _center, _cards, true)

func close() -> void:
	_open = false
	_view = View.BROWSE
	_pending_companion = null
	if not visible:
		return
	UiAnim.kill_tween(_anim_tween)
	_anim_tween = UiAnim.exit_overlay(self, _root, true)
	_anim_tween.finished.connect(_finish_close)

func _finish_close() -> void:
	visible = false
	_root.modulate.a = 1.0
	_cards_data.clear()
	_pending_companion = null
	_view = View.BROWSE
	_refresh_view()

func _process(_delta: float) -> void:
	if not _open or _player_input == null:
		return
	var slot: int = _player_input.get_weapon_slot_just_pressed()
	if _view == View.PICK_GUN:
		if slot >= 0 and slot <= 3:
			_pick_gun(slot)
		return
	if slot >= 0 and slot <= 2:
		_pick_index(slot)
		return
	if slot == 3:
		_skip()

func _input(event: InputEvent) -> void:
	if not _open:
		return
	if event.is_action_pressed("ui_cancel"):
		if _view != View.PICK_GUN:
			cancelled.emit()
			get_viewport().set_input_as_handled()
			return
		get_viewport().set_input_as_handled()
		_enter_browse()
		return
	var joy_button: InputEventJoypadButton = event as InputEventJoypadButton
	if joy_button != null and joy_button.pressed:
		_handle_joy_button(joy_button)
		return
	if event.is_action_pressed("weapon_pistol"):
		_pick_hotkey(0)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("weapon_shotgun"):
		_pick_hotkey(1)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("weapon_rifle"):
		_pick_hotkey(2)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("weapon_smg"):
		_pick_hotkey(3)
		get_viewport().set_input_as_handled()

func _handle_joy_button(joy_button: InputEventJoypadButton) -> void:
	if joy_button.button_index == JOY_BUTTON_START:
		if _view != View.PICK_GUN:
			cancelled.emit()
			get_viewport().set_input_as_handled()
			return
		get_viewport().set_input_as_handled()
		_enter_browse()
		return
	if joy_button.button_index == JOY_BUTTON_DPAD_LEFT:
		get_viewport().set_input_as_handled()
		_pick_hotkey(0)
		return
	if joy_button.button_index == JOY_BUTTON_DPAD_UP:
		get_viewport().set_input_as_handled()
		_pick_hotkey(1)
		return
	if joy_button.button_index == JOY_BUTTON_DPAD_RIGHT:
		get_viewport().set_input_as_handled()
		_pick_hotkey(2)
		return
	if joy_button.button_index == JOY_BUTTON_DPAD_DOWN:
		get_viewport().set_input_as_handled()
		if _view == View.PICK_GUN:
			_pick_gun(3)
			return
		_skip()

func _pick_hotkey(index: int) -> void:
	if _view == View.PICK_GUN:
		_pick_gun(index)
		return
	if index <= 2:
		_pick_index(index)
		return
	_skip()

func _on_card_pressed(index: int) -> void:
	_pick_index(index)

func _on_gun_pressed(index: int) -> void:
	_pick_gun(index)

func _on_skip_or_back() -> void:
	if _view == View.PICK_GUN:
		_enter_browse()
		return
	_skip()

func _on_cancel_or_back() -> void:
	if _view == View.PICK_GUN:
		_enter_browse()
		return
	cancelled.emit()

func _pick_index(index: int) -> void:
	if not _open or _view != View.BROWSE:
		return
	if index < 0 or index >= _cards_data.size():
		return
	if _cards[index].disabled:
		return
	var card: ShopCard = _cards_data[index]
	if card.kind == ShopCard.Kind.COMPANION:
		_enter_pick_gun(card.companion)
		return
	if card.upgrade == null:
		return
	bought.emit(card.upgrade.id)

func _pick_gun(index: int) -> void:
	if not _open or _view != View.PICK_GUN:
		return
	if index < 0 or index >= GUN_TITLES.size():
		return
	if _pending_companion == null:
		return
	picked_companion.emit(_pending_companion.id, index)

func _enter_pick_gun(def: CompanionDef) -> void:
	if def == null:
		return
	_pending_companion = def
	_view = View.PICK_GUN
	_refresh_view()

func _enter_browse() -> void:
	_pending_companion = null
	_view = View.BROWSE
	_refresh_view()

func _skip() -> void:
	if not _open or _view != View.BROWSE:
		return
	skipped.emit()

func _refresh_view() -> void:
	var gold: int = _read_gold()
	_gold_label.text = "gold  %d" % gold
	var picking: bool = _open and _view == View.PICK_GUN
	_title_label.text = PICK_TITLE if picking else BROWSE_TITLE
	_skip_button.text = BACK_TEXT if picking else SKIP_TEXT
	_card_row.visible = _open and not picking
	_gun_row.visible = picking
	_refresh_browse_cards(gold)
	_refresh_gun_buttons(picking)

func _refresh_browse_cards(gold: int) -> void:
	for i: int in _cards.size():
		var show_card: bool = _open and _view == View.BROWSE and i < _cards_data.size()
		_cards[i].visible = show_card
		if not show_card:
			_titles[i].text = ""
			_descs[i].text = ""
			_costs[i].text = ""
			_cards[i].disabled = true
			continue
		var card: ShopCard = _cards_data[i]
		var cost: int = card.get_cost(_session)
		_titles[i].text = card.get_title()
		_descs[i].text = card.get_description()
		_costs[i].text = "%d" % cost
		_cards[i].disabled = gold < cost

func _refresh_gun_buttons(picking: bool) -> void:
	for i: int in _gun_buttons.size():
		_gun_buttons[i].visible = picking
		_gun_buttons[i].disabled = not picking

func _read_gold() -> int:
	if _session != null:
		return _session.get_gold()
	return _presented_gold
