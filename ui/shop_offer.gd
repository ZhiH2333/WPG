extends CanvasLayer
class_name ShopOffer

## P8 目录商店：左状态右货架。PROCESS_MODE_ALWAYS：单机选购时 CombatSandbox 会冻场景树。不自己 spend / close。
enum View { BROWSE, PICK_GUN }

signal bought(upgrade_id: StringName)
signal picked_companion(companion_id: StringName, weapon_index: int)
signal picked_consumable(consumable_id: StringName)
signal skipped
signal cancelled

const BROWSE_TITLE: String = "SHOP"
const PICK_TITLE: String = "Pick a gun"
const CONTINUE_TEXT: String = "Continue"
const BACK_TEXT: String = "Back"
const GUN_TITLES: PackedStringArray = ["Pistol", "Shotgun", "Rifle", "Smg"]
const STIM_ID: StringName = &"stim"
const ITEM_CARD_SIZE := Vector2(240, 148)
const HP_LOW_THRESHOLD: int = 20
const ITEM_CARD_SCENE: PackedScene = preload("res://ui/shop_item_card.tscn")

var _cards_data: Array[ShopCard] = []
var _open: bool = false
var _view: View = View.BROWSE
var _pending_companion: CompanionDef
var _cards: Array[Button] = []
var _gun_buttons: Array[Button] = []
var _player_input: PlayerInput
var _session: RunSession
var _player: Player
var _companion: CompanionBase
var _presented_gold: int = 0
var _anim_tween: Tween
var _catalog_mode: bool = false
var _stim_bought: bool = false
var _hp_is_low: bool = false

@onready var _root: Control = $Root
@onready var _dimmer: ColorRect = $Root/Dimmer
@onready var _panel: PanelContainer = $Root/Center/Panel
@onready var _title_label: Label = $Root/Center/Panel/Column/Header/Title
@onready var _gold_label: Label = $Root/Center/Panel/Column/Header/GoldLabel
@onready var _hp_bar: ProgressBar = $Root/Center/Panel/Column/Content/Body/Status/HpRow/HpBar
@onready var _hp_label: Label = $Root/Center/Panel/Column/Content/Body/Status/HpRow/HpLabel
@onready var _weapon_label: Label = $Root/Center/Panel/Column/Content/Body/Status/WeaponLabel
@onready var _xp_bar: ProgressBar = $Root/Center/Panel/Column/Content/Body/Status/XpRow/XpBar
@onready var _xp_label: Label = $Root/Center/Panel/Column/Content/Body/Status/XpRow/XpLabel
@onready var _companion_label: Label = $Root/Center/Panel/Column/Content/Body/Status/CompanionLabel
@onready var _owned_label: Label = $Root/Center/Panel/Column/Content/Body/Status/OwnedLabel
@onready var _shelf_scroll: ScrollContainer = $Root/Center/Panel/Column/Content/Body/Scroll
@onready var _grid: GridContainer = $Root/Center/Panel/Column/Content/Body/Scroll/Grid
@onready var _gun_row: HBoxContainer = $Root/Center/Panel/Column/Content/Body/GunRow
@onready var _continue_button: Button = $Root/Center/Panel/Column/Continue

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	layer = 20
	_gun_buttons = [
		$Root/Center/Panel/Column/Content/Body/GunRow/Gun0 as Button,
		$Root/Center/Panel/Column/Content/Body/GunRow/Gun1 as Button,
		$Root/Center/Panel/Column/Content/Body/GunRow/Gun2 as Button,
		$Root/Center/Panel/Column/Content/Body/GunRow/Gun3 as Button,
	]
	for i: int in _gun_buttons.size():
		_gun_buttons[i].pressed.connect(_on_gun_pressed.bind(i))
		_gun_buttons[i].text = GUN_TITLES[i]
	_continue_button.pressed.connect(_on_skip_or_back)
	var viewport: Viewport = get_viewport()
	if viewport != null and not viewport.size_changed.is_connected(_on_viewport_size_changed):
		viewport.size_changed.connect(_on_viewport_size_changed)
	_root.resized.connect(_on_viewport_size_changed)

func bind_player_input(player_input: PlayerInput) -> void:
	_player_input = player_input

func bind_session(session: RunSession) -> void:
	_session = session

func bind_player(player: Player) -> void:
	_player = player

func bind_companion(companion: CompanionBase) -> void:
	_companion = companion

func is_open() -> bool:
	return _open

func get_shop_mode_label() -> String:
	if not _open:
		return "closed"
	if _catalog_mode:
		return "catalog"
	return "lan3"

func present(cards: Array[ShopCard], gold: int) -> void:
	UiAnim.kill_tween(_anim_tween)
	_stim_bought = false
	_presented_gold = gold
	_pending_companion = null
	_view = View.BROWSE
	_apply_stock(cards)
	_open = not _cards_data.is_empty()
	visible = _open
	_root.modulate.a = 1.0
	_refresh_view()
	if not _open:
		return
	_anim_tween = UiAnim.enter_overlay(self, _dimmer, _panel, [], true)

func refresh_stock(cards: Array[ShopCard]) -> void:
	if not _open:
		return
	_pending_companion = null
	_view = View.BROWSE
	_apply_stock(cards)
	_refresh_view()

func close() -> void:
	_open = false
	_view = View.BROWSE
	_pending_companion = null
	if not visible:
		_finish_close()
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
	_stim_bought = false
	_catalog_mode = false
	_clear_shelf()
	_refresh_view()

func _apply_stock(cards: Array[ShopCard]) -> void:
	_cards_data = cards.duplicate()
	_catalog_mode = _detect_catalog_mode(_cards_data)
	_fit_panel()

func _detect_catalog_mode(cards: Array[ShopCard]) -> bool:
	if cards.size() > 3:
		return true
	for card: ShopCard in cards:
		if card != null and card.kind == ShopCard.Kind.CONSUMABLE:
			return true
	return false

func _on_viewport_size_changed() -> void:
	if not _open:
		return
	_fit_panel()

func _fit_panel() -> void:
	if _panel == null:
		return
	_panel.custom_minimum_size = UiFit.shop_panel_size(_root)

func _process(_delta: float) -> void:
	if not _open or _player_input == null:
		return
	if _view != View.PICK_GUN:
		return
	var slot: int = _player_input.get_weapon_slot_just_pressed()
	if slot >= 0 and slot <= 3:
		_pick_gun(slot)

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
	if _view != View.PICK_GUN:
		return
	if event.is_action_pressed("weapon_pistol"):
		_pick_gun(0)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("weapon_shotgun"):
		_pick_gun(1)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("weapon_rifle"):
		_pick_gun(2)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("weapon_smg"):
		_pick_gun(3)
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
	if _view != View.PICK_GUN:
		return
	if joy_button.button_index == JOY_BUTTON_DPAD_LEFT:
		get_viewport().set_input_as_handled()
		_pick_gun(0)
		return
	if joy_button.button_index == JOY_BUTTON_DPAD_UP:
		get_viewport().set_input_as_handled()
		_pick_gun(1)
		return
	if joy_button.button_index == JOY_BUTTON_DPAD_RIGHT:
		get_viewport().set_input_as_handled()
		_pick_gun(2)
		return
	if joy_button.button_index == JOY_BUTTON_DPAD_DOWN:
		get_viewport().set_input_as_handled()
		_pick_gun(3)

func _on_card_pressed(index: int) -> void:
	_pick_index(index)

func _on_gun_pressed(index: int) -> void:
	_pick_gun(index)

func _on_skip_or_back() -> void:
	if _view == View.PICK_GUN:
		_enter_browse()
		return
	_skip()

func _pick_index(index: int) -> void:
	if not _open or _view != View.BROWSE:
		return
	if index < 0 or index >= _cards_data.size() or index >= _cards.size():
		return
	if _cards[index].disabled:
		return
	var card: ShopCard = _cards_data[index]
	if card.kind == ShopCard.Kind.COMPANION:
		_enter_pick_gun(card.companion)
		return
	if card.kind == ShopCard.Kind.CONSUMABLE:
		if card.consumable == null:
			return
		if card.consumable.id == STIM_ID:
			if _stim_bought:
				return
			_stim_bought = true
		_cards[index].disabled = true
		picked_consumable.emit(card.consumable.id)
		return
	if card.upgrade == null:
		return
	_cards[index].disabled = true
	bought.emit(card.upgrade.id)

func _pick_gun(index: int) -> void:
	if not _open or _view != View.PICK_GUN:
		return
	if index < 0 or index >= GUN_TITLES.size():
		return
	if _pending_companion == null:
		return
	var companion_id: StringName = _pending_companion.id
	picked_companion.emit(companion_id, index)
	_enter_browse()

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
	_continue_button.text = BACK_TEXT if picking else CONTINUE_TEXT
	_shelf_scroll.visible = _open and not picking
	_gun_row.visible = picking
	_refresh_status()
	_refresh_browse_cards(gold)
	_refresh_gun_buttons(picking)

func _refresh_status() -> void:
	var health: PlayerHealth = _player.get_player_health() if _player != null else null
	var hp: int = 0
	var max_hp: int = 100
	if health != null:
		hp = health.get_hp()
		max_hp = health.get_max_hp()
	_hp_bar.max_value = float(max_hp)
	_hp_bar.value = float(hp)
	_hp_label.text = "%d/%d" % [hp, max_hp]
	_apply_hp_fill(hp)
	_weapon_label.text = _read_weapon_name()
	var level: int = 1
	var xp: int = 0
	var need: int = 30
	if _session != null:
		level = _session.get_level()
		xp = _session.get_xp()
		need = _session.get_xp_to_next()
	_xp_bar.max_value = float(need)
	_xp_bar.value = float(xp)
	_xp_label.text = "Lv.%d  %d/%d" % [level, xp, need]
	_companion_label.text = _format_companion()
	_owned_label.text = _format_owned()

func _apply_hp_fill(hp: int) -> void:
	var is_low: bool = hp <= HP_LOW_THRESHOLD
	if is_low == _hp_is_low:
		if is_low:
			_hp_bar.theme_type_variation = &"ProgressBarLow"
		return
	_hp_is_low = is_low
	if is_low:
		_hp_bar.theme_type_variation = &"ProgressBarLow"
		return
	_hp_bar.theme_type_variation = &""

func _read_weapon_name() -> String:
	if _player == null:
		return "-"
	var host: WeaponHost = _player.get_weapon_host()
	if host == null:
		return "-"
	var weapon: Weapon = host.get_current_weapon()
	if weapon == null:
		return "-"
	return weapon.get_display_name()

func _format_companion() -> String:
	if _companion == null or not is_instance_valid(_companion):
		return "none"
	var title: String = String(_companion.get_companion_id()).capitalize()
	if title.is_empty():
		title = "Companion"
	if _companion.is_defeated():
		return "%s (down)" % title
	var ranged: RangedCompanion = _companion as RangedCompanion
	if ranged == null:
		return title
	return "%s · %s" % [title, ranged.get_weapon_display_name()]

func _format_owned() -> String:
	if _session == null:
		return "none"
	var titles: PackedStringArray = PackedStringArray()
	var seen: Dictionary = {}
	var catalog: UpgradeCatalog = _session.get_catalog()
	for upgrade_id: String in _session.get_owned_upgrade_ids():
		var title: String = upgrade_id
		if catalog != null:
			var def: UpgradeDef = catalog.get_by_id(StringName(upgrade_id))
			if def != null:
				title = def.title
		if seen.has(title):
			continue
		seen[title] = true
		titles.append(title)
	if titles.is_empty():
		return "none"
	return ", ".join(titles)

func _refresh_browse_cards(gold: int) -> void:
	_rebuild_shelf()
	for i: int in _cards.size():
		if i >= _cards_data.size():
			_cards[i].visible = false
			_cards[i].disabled = true
			continue
		var card: ShopCard = _cards_data[i]
		_fill_item_card(_cards[i], card, gold)

func _rebuild_shelf() -> void:
	if _cards.size() == _cards_data.size():
		return
	_clear_shelf()
	for i: int in _cards_data.size():
		var button: Button = ITEM_CARD_SCENE.instantiate() as Button
		button.custom_minimum_size = ITEM_CARD_SIZE
		button.theme_type_variation = &"OfferButton"
		button.pressed.connect(_on_card_pressed.bind(i))
		_grid.add_child(button)
		_cards.append(button)

func _clear_shelf() -> void:
	for child: Node in _grid.get_children():
		_grid.remove_child(child)
		child.queue_free()
	_cards.clear()

func _fill_item_card(button: Button, card: ShopCard, gold: int) -> void:
	button.visible = true
	var kind_label: Label = button.get_node("VBox/Kind") as Label
	var title_label: Label = button.get_node("VBox/Title") as Label
	var desc_label: Label = button.get_node("VBox/Desc") as Label
	var cost_label: Label = button.get_node("VBox/Cost") as Label
	var cost: int = card.get_cost(_session)
	kind_label.text = card.get_kind_label()
	title_label.text = card.get_title()
	desc_label.text = card.get_description()
	cost_label.text = "%d" % cost
	button.disabled = _is_card_disabled(card, gold, cost)

func _is_card_disabled(card: ShopCard, gold: int, cost: int) -> bool:
	if gold < cost:
		return true
	if card.kind == ShopCard.Kind.CONSUMABLE:
		if card.consumable == null:
			return true
		if card.consumable.id == STIM_ID and _stim_bought:
			return true
		if _is_heal_kind(card.consumable.kind) and _is_player_full_hp():
			return true
	return false

func _is_heal_kind(kind: ConsumableDef.Kind) -> bool:
	return kind == ConsumableDef.Kind.HEAL_FLAT or kind == ConsumableDef.Kind.HEAL_FULL

func _is_player_full_hp() -> bool:
	if _player == null:
		return false
	var health: PlayerHealth = _player.get_player_health()
	return health.get_hp() >= health.get_max_hp()

func _refresh_gun_buttons(picking: bool) -> void:
	for i: int in _gun_buttons.size():
		_gun_buttons[i].visible = picking
		_gun_buttons[i].disabled = not picking

func _read_gold() -> int:
	if _session != null:
		return _session.get_gold()
	return _presented_gold
