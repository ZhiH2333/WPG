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
const SHELF_STAGGER_SEC: float = 0.04
const SHELF_STAGGER_MAX: int = 6
const CARD_START_SCALE: float = 0.9
const CARD_PUNCH_SCALE: float = 1.06
const CARD_PUNCH_SEC: float = 0.12
const CARD_OUT_SEC: float = 0.12
const GOLD_ROLL_SEC: float = 0.28
const BAR_SMOOTHING: float = 10.0
const HOVER_SCALE: float = 1.02
const HOVER_SEC: float = 0.12
const GUN_ROW_FADE_SEC: float = 0.18
const CARD_DIM_ALPHA: float = 0.45
const META_IDENTITY: StringName = &"shop_identity"
const META_DISABLED: StringName = &"shop_disabled"
const META_RETIRING: StringName = &"shop_retiring"

var _cards_data: Array[ShopCard] = []
var _open: bool = false
var _view: View = View.BROWSE
var _pending_companion: CompanionDef
var _cards: Array[Button] = []
var _gun_buttons: Array[Button] = []
var _player_input: PlayerInput
var _session: RunSession
var _player: Player
var _companions: Array[CompanionBase] = []
var _presented_gold: int = 0
var _displayed_gold: float = 0.0
var _anim_tween: Tween
var _gold_tween: Tween
var _card_enter_tween: Tween
var _view_tweens: Array[Tween] = []
var _hover_tweens: Dictionary = {}
var _punch_tweens: Dictionary = {}
var _out_tweens: Dictionary = {}
var _sfx_gate: Dictionary = {}
var _catalog_mode: bool = false
var _stim_bought: bool = false
var _hp_is_low: bool = false
var _last_bought_identity: StringName = &""

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
@onready var _hover_sfx: AudioStreamPlayer = $HoverSfx
@onready var _click_sfx: AudioStreamPlayer = $ClickSfx
@onready var _back_sfx: AudioStreamPlayer = $BackSfx
@onready var _error_sfx: AudioStreamPlayer = $ErrorSfx

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	layer = 20
	_stack_shelf_and_guns()
	_hover_sfx.stream = GameAudio.load_wav("res://audio/ui_hover.wav")
	_click_sfx.stream = GameAudio.load_wav("res://audio/ui_click.wav")
	_back_sfx.stream = GameAudio.load_wav("res://audio/ui_back.wav")
	_error_sfx.stream = GameAudio.load_wav("res://audio/click.wav")
	_gun_buttons = [
		_gun_row.get_node("Gun0") as Button,
		_gun_row.get_node("Gun1") as Button,
		_gun_row.get_node("Gun2") as Button,
		_gun_row.get_node("Gun3") as Button,
	]
	for i: int in _gun_buttons.size():
		var gun: Button = _gun_buttons[i]
		gun.pressed.connect(_on_gun_pressed.bind(i))
		gun.text = GUN_TITLES[i]
		gun.disabled = false
		gun.pivot_offset = gun.custom_minimum_size * 0.5
		_wire_hover(gun, _on_gun_hover_entered.bind(gun), _on_gun_hover_exited.bind(gun))
	_continue_button.pressed.connect(_on_skip_or_back)
	_continue_button.pivot_offset = _continue_button.custom_minimum_size * 0.5
	_wire_hover(_continue_button, _on_continue_hover_entered, _on_continue_hover_exited)
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

func bind_companions(companions: Array[CompanionBase]) -> void:
	_companions = companions.duplicate()

func is_open() -> bool:
	return _open

func get_shop_mode_label() -> String:
	if not _open:
		return "closed"
	if _catalog_mode:
		return "catalog"
	return "lan3"

func present(cards: Array[ShopCard], gold: int) -> void:
	_kill_shop_tweens()
	_clear_shelf()
	_stim_bought = false
	_last_bought_identity = &""
	_presented_gold = gold
	_displayed_gold = float(_read_gold())
	_pending_companion = null
	_view = View.BROWSE
	_apply_stock(cards)
	_open = not _cards_data.is_empty()
	visible = _open
	_root.modulate.a = 1.0
	_refresh_view()
	if not _open:
		return
	_snap_vitals()
	_show_browse_view()
	_sync_shelf(true)
	_fit_panel()
	_anim_tween = UiAnim.enter_overlay(self, _dimmer, _panel, [], true)

func refresh_stock(cards: Array[ShopCard]) -> void:
	if not _open:
		return
	_pending_companion = null
	_view = View.BROWSE
	_apply_stock(cards)
	_refresh_view()
	_show_browse_view()
	_sync_shelf(false)
	_roll_gold()

func close() -> void:
	_open = false
	_view = View.BROWSE
	_pending_companion = null
	if not visible:
		_finish_close()
		return
	_kill_shop_tweens()
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
	_last_bought_identity = &""
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
	if _panel == null or _root == null:
		return
	UiFit.apply_floating_panel(_root, _panel, UiFit.SHOP_PANEL_MAX)

func _process(delta: float) -> void:
	if not _open:
		return
	_tick_vitals(delta)
	if _view != View.PICK_GUN or _player_input == null:
		return
	var slot: int = _player_input.get_weapon_slot_just_pressed()
	if slot >= 0 and slot <= 3:
		_pick_gun(slot)

func _input(event: InputEvent) -> void:
	if not _open:
		return
	if event.is_pressed():
		GameAudio.unlock_driver(self)
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_cancel_or_back()
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
		get_viewport().set_input_as_handled()
		_cancel_or_back()
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

func _on_gun_pressed(index: int) -> void:
	_pick_gun(index)

func _on_skip_or_back() -> void:
	if _view == View.PICK_GUN:
		_play_back()
		_enter_browse()
		return
	_play_click()
	_skip()

func _cancel_or_back() -> void:
	_play_back()
	if _view == View.PICK_GUN:
		_enter_browse()
		return
	cancelled.emit()

func _on_shelf_card_pressed(button: Button) -> void:
	if not _open or _view != View.BROWSE:
		return
	if not is_instance_valid(button):
		return
	if bool(button.get_meta(META_RETIRING, false)):
		return
	var identity: StringName = button.get_meta(META_IDENTITY, &"") as StringName
	var card: ShopCard = _find_card(identity)
	if card == null:
		return
	_pick_card(card)

func _pick_card(card: ShopCard) -> void:
	var gold: int = _read_gold()
	var cost: int = card.get_cost(_session)
	if _is_card_disabled(card, gold, cost):
		_play_error()
		return
	_play_click()
	if card.kind == ShopCard.Kind.COMPANION:
		_enter_pick_gun(card.companion)
		return
	if card.kind == ShopCard.Kind.CONSUMABLE:
		if card.consumable == null:
			return
		if card.consumable.id == STIM_ID:
			_stim_bought = true
		_last_bought_identity = _card_identity(card)
		picked_consumable.emit(card.consumable.id)
		return
	if card.upgrade == null:
		return
	_last_bought_identity = _card_identity(card)
	bought.emit(card.upgrade.id)

func _pick_gun(index: int) -> void:
	if not _open or _view != View.PICK_GUN:
		return
	if index < 0 or index >= GUN_TITLES.size():
		return
	if _pending_companion == null:
		return
	_play_click()
	var companion_id: StringName = _pending_companion.id
	_pending_companion = null
	_view = View.BROWSE
	_show_browse_view()
	_refresh_view()
	picked_companion.emit(companion_id, index)

func _enter_pick_gun(def: CompanionDef) -> void:
	if def == null:
		return
	_pending_companion = def
	_view = View.PICK_GUN
	_refresh_view()
	_play_pick_gun_view()

func _enter_browse() -> void:
	_pending_companion = null
	_view = View.BROWSE
	_refresh_view()
	_play_browse_view()

func _skip() -> void:
	if not _open or _view != View.BROWSE:
		return
	skipped.emit()

func _refresh_view() -> void:
	_gold_label.text = "gold  %d" % roundi(_displayed_gold)
	var picking: bool = _open and _view == View.PICK_GUN
	_title_label.text = PICK_TITLE if picking else BROWSE_TITLE
	_continue_button.text = BACK_TEXT if picking else CONTINUE_TEXT
	_refresh_status_text()

func _refresh_status_text() -> void:
	var hp: int = _read_hp()
	var max_hp: int = _read_max_hp()
	_hp_bar.max_value = float(max_hp)
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
	_xp_label.text = "Lv.%d  %d/%d" % [level, xp, need]
	_companion_label.text = _format_companion()
	_owned_label.text = _format_owned()

func _snap_vitals() -> void:
	var hp: int = _read_hp()
	var max_hp: int = _read_max_hp()
	_hp_bar.max_value = float(max_hp)
	_hp_bar.value = float(hp)
	_hp_label.text = "%d/%d" % [hp, max_hp]
	_apply_hp_fill(hp)
	var xp: int = 0
	var need: int = 30
	if _session != null:
		xp = _session.get_xp()
		need = _session.get_xp_to_next()
	_xp_bar.max_value = float(need)
	_xp_bar.value = float(xp)

func _tick_vitals(delta: float) -> void:
	var hp: int = _read_hp()
	var max_hp: int = _read_max_hp()
	_hp_bar.max_value = float(max_hp)
	_hp_bar.value = _approach_bar(_hp_bar.value, float(hp), delta)
	_hp_label.text = "%d/%d" % [hp, max_hp]
	_apply_hp_fill(hp)
	var level: int = 1
	var xp: int = 0
	var need: int = 30
	if _session != null:
		level = _session.get_level()
		xp = _session.get_xp()
		need = _session.get_xp_to_next()
	_xp_bar.max_value = float(need)
	_xp_bar.value = _approach_bar(_xp_bar.value, float(xp), delta)
	_xp_label.text = "Lv.%d  %d/%d" % [level, xp, need]

func _approach_bar(current: float, target: float, delta: float) -> float:
	if absf(target - current) < 0.5:
		return target
	return lerpf(current, target, 1.0 - exp(-BAR_SMOOTHING * delta))

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
	var alive: int = 0
	for companion: CompanionBase in _companions:
		if companion == null or not is_instance_valid(companion) or companion.is_defeated():
			continue
		alive += 1
	return "Gunner %d/%d" % [alive, RunSession.COMPANION_CAP]

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

func _sync_shelf(is_present: bool) -> void:
	var gold: int = _read_gold()
	var wanted_ids: Array[StringName] = []
	var wanted: Dictionary = {}
	for card: ShopCard in _cards_data:
		var identity: StringName = _card_identity(card)
		if identity == &"":
			continue
		wanted_ids.append(identity)
		wanted[identity] = card
	var live: Dictionary = {}
	for button: Button in _cards:
		if not is_instance_valid(button):
			continue
		live[button.get_meta(META_IDENTITY, &"") as StringName] = button
	for identity_value: Variant in live.keys():
		var gone_id: StringName = identity_value as StringName
		if wanted.has(gone_id):
			continue
		var retired: Button = live[gone_id] as Button
		_cards.erase(retired)
		_retire_card(retired)
	var kept: Array[Button] = []
	var spawned: Array[Button] = []
	for identity: StringName in wanted_ids:
		var card: ShopCard = wanted[identity] as ShopCard
		if live.has(identity):
			var kept_button: Button = live[identity] as Button
			_fill_item_card(kept_button, card, gold, true)
			kept.append(kept_button)
			continue
		var spawned_button: Button = _spawn_card()
		_fill_item_card(spawned_button, card, gold, false)
		kept.append(spawned_button)
		spawned.append(spawned_button)
	_cards = kept
	if is_present:
		_stagger_shelf_cards(_cards)
		_last_bought_identity = &""
		return
	if not spawned.is_empty():
		_stagger_shelf_cards(spawned)
	_punch_bought_card()
	_last_bought_identity = &""

func _spawn_card() -> Button:
	var button: Button = ITEM_CARD_SCENE.instantiate() as Button
	button.custom_minimum_size = ITEM_CARD_SIZE
	button.theme_type_variation = &"OfferButton"
	button.pivot_offset = ITEM_CARD_SIZE * 0.5
	button.disabled = false
	button.pressed.connect(_on_shelf_card_pressed.bind(button))
	_wire_hover(button, _on_shelf_hover_entered.bind(button), _on_shelf_hover_exited.bind(button))
	_grid.add_child(button)
	return button

func _clear_shelf() -> void:
	UiAnim.kill_tween(_card_enter_tween)
	for child: Node in _grid.get_children():
		if child is Button:
			_kill_control_tweens(child as Button)
		_grid.remove_child(child)
		child.queue_free()
	_cards.clear()
	_out_tweens.clear()
	_punch_tweens.clear()

func _fill_item_card(button: Button, card: ShopCard, gold: int, snap_visual: bool) -> void:
	button.visible = true
	button.disabled = false
	button.set_meta(META_IDENTITY, _card_identity(card))
	button.set_meta(META_RETIRING, false)
	var kind_label: Label = button.get_node("VBox/Kind") as Label
	var title_label: Label = button.get_node("VBox/Title") as Label
	var desc_label: Label = button.get_node("VBox/Desc") as Label
	var cost_label: Label = button.get_node("VBox/Cost") as Label
	var cost: int = card.get_cost(_session)
	kind_label.text = card.get_kind_label()
	title_label.text = card.get_title()
	desc_label.text = card.get_description()
	cost_label.text = "%d" % cost
	var dim: bool = _is_card_disabled(card, gold, cost)
	button.set_meta(META_DISABLED, dim)
	if _view == View.BROWSE:
		button.mouse_filter = Control.MOUSE_FILTER_STOP
		button.focus_mode = Control.FOCUS_ALL
	else:
		button.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.focus_mode = Control.FOCUS_NONE
	if dim:
		_kill_hover(button)
	if not snap_visual:
		return
	button.modulate.a = CARD_DIM_ALPHA if dim else 1.0
	if not _is_punching(button):
		button.scale = Vector2.ONE

func _is_card_disabled(card: ShopCard, gold: int, cost: int) -> bool:
	if gold < cost:
		return true
	if card.kind == ShopCard.Kind.CONSUMABLE:
		if card.consumable == null:
			return true
		if card.consumable.id == STIM_ID and _stim_bought:
			return true
		if card.consumable.kind == ConsumableDef.Kind.HEAL_FLAT and _is_player_full_hp():
			return true
		if card.consumable.kind == ConsumableDef.Kind.HEAL_FULL and _is_full_heal_unneeded():
			return true
	return false

func _is_player_full_hp() -> bool:
	if _player == null:
		return false
	var health: PlayerHealth = _player.get_player_health()
	return health.get_hp() >= health.get_max_hp()

func _is_full_heal_unneeded() -> bool:
	return _is_player_full_hp() and _are_living_companions_full_hp()

func _are_living_companions_full_hp() -> bool:
	for companion: CompanionBase in _companions:
		if companion == null or not is_instance_valid(companion) or companion.is_defeated():
			continue
		if companion.get_hp() < companion.get_max_hp():
			return false
	return true

func _read_gold() -> int:
	if _session != null:
		return _session.get_gold()
	return _presented_gold

func _read_hp() -> int:
	if _player == null:
		return 0
	return _player.get_player_health().get_hp()

func _read_max_hp() -> int:
	if _player == null:
		return 100
	return _player.get_player_health().get_max_hp()

func _card_identity(card: ShopCard) -> StringName:
	if card == null:
		return &""
	if card.kind == ShopCard.Kind.CONSUMABLE:
		if card.consumable == null:
			return &""
		return StringName("c:%s" % String(card.consumable.id))
	if card.kind == ShopCard.Kind.COMPANION:
		if card.companion == null:
			return &""
		return StringName("n:%s" % String(card.companion.id))
	if card.upgrade == null:
		return &""
	return StringName("u:%s" % String(card.upgrade.id))

func _find_card(identity: StringName) -> ShopCard:
	if identity == &"":
		return null
	for card: ShopCard in _cards_data:
		if _card_identity(card) == identity:
			return card
	return null

func _stagger_shelf_cards(buttons: Array[Button]) -> void:
	UiAnim.kill_tween(_card_enter_tween)
	if buttons.is_empty():
		return
	_card_enter_tween = create_tween().set_parallel(true)
	_card_enter_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	for i: int in buttons.size():
		var button: Button = buttons[i]
		if not is_instance_valid(button):
			continue
		var delay: float = float(mini(i, SHELF_STAGGER_MAX - 1)) * SHELF_STAGGER_SEC
		var dim: bool = bool(button.get_meta(META_DISABLED, false))
		var to_alpha: float = CARD_DIM_ALPHA if dim else 1.0
		button.pivot_offset = ITEM_CARD_SIZE * 0.5
		button.modulate.a = 0.0
		button.scale = Vector2(CARD_START_SCALE, CARD_START_SCALE)
		_card_enter_tween.tween_property(button, "modulate:a", to_alpha, UiAnim.CARD_FADE_SEC).set_delay(delay).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
		_card_enter_tween.tween_property(button, "scale", Vector2.ONE, UiAnim.CARD_SCALE_SEC).set_delay(delay).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _punch_bought_card() -> void:
	if _last_bought_identity == &"":
		return
	for button: Button in _cards:
		if button.get_meta(META_IDENTITY, &"") as StringName != _last_bought_identity:
			continue
		_punch_card(button)
		return

func _punch_card(button: Button) -> void:
	if not is_instance_valid(button):
		return
	_kill_hover(button)
	var key: int = button.get_instance_id()
	UiAnim.kill_tween(_punch_tweens.get(key) as Tween)
	var tween: Tween = UiAnim.punch_scale(self, button, CARD_PUNCH_SCALE, CARD_PUNCH_SEC, true)
	_punch_tweens[key] = tween
	if tween != null:
		tween.finished.connect(_on_punch_finished.bind(key))

func _on_punch_finished(key: int) -> void:
	_punch_tweens.erase(key)

func _retire_card(button: Button) -> void:
	if not is_instance_valid(button):
		return
	if bool(button.get_meta(META_RETIRING, false)):
		return
	button.set_meta(META_RETIRING, true)
	button.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.focus_mode = Control.FOCUS_NONE
	_kill_control_tweens(button)
	button.pivot_offset = ITEM_CARD_SIZE * 0.5
	var tween: Tween = create_tween().set_parallel(true)
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_out_tweens[button.get_instance_id()] = tween
	tween.tween_property(button, "scale", Vector2(CARD_START_SCALE, CARD_START_SCALE), CARD_OUT_SEC).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_IN)
	tween.tween_property(button, "modulate:a", 0.0, CARD_OUT_SEC).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_IN)
	tween.finished.connect(_on_card_out_finished.bind(button))

func _on_card_out_finished(button: Button) -> void:
	if is_instance_valid(button):
		_out_tweens.erase(button.get_instance_id())
		if button.get_parent() == _grid:
			_grid.remove_child(button)
		button.queue_free()

func _stack_shelf_and_guns() -> void:
	var body: Control = _shelf_scroll.get_parent() as Control
	if body == null:
		return
	if body.get_node_or_null("ShelfStack") != null:
		return
	var stack: Control = Control.new()
	stack.name = "ShelfStack"
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var insert_at: int = _shelf_scroll.get_index()
	body.add_child(stack)
	body.move_child(stack, insert_at)
	_shelf_scroll.reparent(stack)
	_gun_row.reparent(stack)
	_apply_full_rect(_shelf_scroll)
	_apply_full_rect(_gun_row)
	_gun_row.visible = true
	_gun_row.modulate.a = 0.0
	_set_gun_interactive(false)

func _apply_full_rect(control: Control) -> void:
	control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	control.size_flags_vertical = Control.SIZE_EXPAND_FILL

func _show_browse_view() -> void:
	_kill_view_tweens()
	_shelf_scroll.visible = true
	_shelf_scroll.modulate.a = 1.0
	_gun_row.visible = true
	_gun_row.modulate.a = 0.0
	_apply_shelf_input(true)
	_set_gun_interactive(false)
	for gun: Button in _gun_buttons:
		gun.scale = Vector2.ONE

func _play_pick_gun_view() -> void:
	_kill_view_tweens()
	_apply_shelf_input(false)
	_set_gun_interactive(true)
	_gun_row.visible = true
	_track_view_tween(UiAnim.fade_modulate(self, _shelf_scroll, 0.0, CARD_OUT_SEC, true))
	_track_view_tween(UiAnim.fade_modulate(self, _gun_row, 1.0, GUN_ROW_FADE_SEC, true))
	var scale_tween: Tween = create_tween().set_parallel(true)
	scale_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	for i: int in _gun_buttons.size():
		var gun: Button = _gun_buttons[i]
		gun.pivot_offset = gun.custom_minimum_size * 0.5
		gun.scale = Vector2(CARD_START_SCALE, CARD_START_SCALE)
		var delay: float = SHELF_STAGGER_SEC * float(i)
		scale_tween.tween_property(gun, "scale", Vector2.ONE, GUN_ROW_FADE_SEC).set_delay(delay).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_track_view_tween(scale_tween)

func _play_browse_view() -> void:
	_kill_view_tweens()
	_apply_shelf_input(true)
	_set_gun_interactive(false)
	_shelf_scroll.visible = true
	_gun_row.visible = true
	_track_view_tween(UiAnim.fade_modulate(self, _gun_row, 0.0, GUN_ROW_FADE_SEC, true))
	_track_view_tween(UiAnim.fade_modulate(self, _shelf_scroll, 1.0, CARD_OUT_SEC, true))
	var scale_tween: Tween = create_tween().set_parallel(true)
	scale_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	for i: int in _gun_buttons.size():
		var gun: Button = _gun_buttons[i]
		gun.pivot_offset = gun.custom_minimum_size * 0.5
		var delay: float = SHELF_STAGGER_SEC * float(i)
		scale_tween.tween_property(gun, "scale", Vector2(CARD_START_SCALE, CARD_START_SCALE), GUN_ROW_FADE_SEC).set_delay(delay).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_IN)
	_track_view_tween(scale_tween)

func _apply_shelf_input(enabled: bool) -> void:
	_shelf_scroll.mouse_filter = Control.MOUSE_FILTER_STOP if enabled else Control.MOUSE_FILTER_IGNORE
	for button: Button in _cards:
		if not is_instance_valid(button):
			continue
		if bool(button.get_meta(META_RETIRING, false)):
			button.mouse_filter = Control.MOUSE_FILTER_IGNORE
			button.focus_mode = Control.FOCUS_NONE
			continue
		button.mouse_filter = Control.MOUSE_FILTER_STOP if enabled else Control.MOUSE_FILTER_IGNORE
		button.focus_mode = Control.FOCUS_ALL if enabled else Control.FOCUS_NONE

func _set_gun_interactive(enabled: bool) -> void:
	for gun: Button in _gun_buttons:
		gun.disabled = false
		gun.mouse_filter = Control.MOUSE_FILTER_STOP if enabled else Control.MOUSE_FILTER_IGNORE
		gun.focus_mode = Control.FOCUS_ALL if enabled else Control.FOCUS_NONE

func _roll_gold() -> void:
	var target: int = _read_gold()
	if is_equal_approx(_displayed_gold, float(target)):
		_assign_displayed_gold(float(target))
		return
	UiAnim.kill_tween(_gold_tween)
	_gold_tween = create_tween()
	_gold_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_gold_tween.tween_method(_assign_displayed_gold, _displayed_gold, float(target), GOLD_ROLL_SEC).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)

func _assign_displayed_gold(value: float) -> void:
	_displayed_gold = value
	_gold_label.text = "gold  %d" % roundi(_displayed_gold)

func _wire_hover(control: Control, entered: Callable, exited: Callable) -> void:
	control.mouse_entered.connect(entered)
	control.mouse_exited.connect(exited)
	control.focus_entered.connect(entered)
	control.focus_exited.connect(exited)

func _on_shelf_hover_entered(button: Button) -> void:
	if not _open or _view != View.BROWSE:
		return
	if not is_instance_valid(button):
		return
	if bool(button.get_meta(META_DISABLED, false)) or bool(button.get_meta(META_RETIRING, false)):
		return
	if _is_punching(button):
		return
	_play_hover()
	_tween_hover(button, true)

func _on_shelf_hover_exited(button: Button) -> void:
	if not is_instance_valid(button):
		return
	if _is_punching(button):
		return
	_tween_hover(button, false)

func _on_gun_hover_entered(button: Button) -> void:
	if not _open or _view != View.PICK_GUN:
		return
	_play_hover()
	_tween_hover(button, true)

func _on_gun_hover_exited(button: Button) -> void:
	if _view != View.PICK_GUN:
		return
	_tween_hover(button, false)

func _on_continue_hover_entered() -> void:
	if not _open:
		return
	_play_hover()
	_tween_hover(_continue_button, true)

func _on_continue_hover_exited() -> void:
	_tween_hover(_continue_button, false)

func _tween_hover(control: Control, hovered: bool) -> void:
	if not is_instance_valid(control):
		return
	if _is_punching(control):
		return
	_kill_hover(control)
	var tween: Tween = create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_hover_tweens[control.get_instance_id()] = tween
	control.pivot_offset = control.custom_minimum_size * 0.5
	var target: Vector2 = Vector2(HOVER_SCALE, HOVER_SCALE) if hovered else Vector2.ONE
	tween.tween_property(control, "scale", target, HOVER_SEC).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)

func _is_punching(control: Control) -> bool:
	var tween: Tween = _punch_tweens.get(control.get_instance_id()) as Tween
	return tween != null and tween.is_valid()

func _kill_hover(control: Control) -> void:
	var key: int = control.get_instance_id()
	UiAnim.kill_tween(_hover_tweens.get(key) as Tween)
	_hover_tweens.erase(key)

func _kill_control_tweens(control: Control) -> void:
	_kill_hover(control)
	var key: int = control.get_instance_id()
	UiAnim.kill_tween(_punch_tweens.get(key) as Tween)
	_punch_tweens.erase(key)
	UiAnim.kill_tween(_out_tweens.get(key) as Tween)
	_out_tweens.erase(key)

func _kill_view_tweens() -> void:
	for tween: Tween in _view_tweens:
		UiAnim.kill_tween(tween)
	_view_tweens.clear()

func _track_view_tween(tween: Tween) -> void:
	if tween != null:
		_view_tweens.append(tween)

func _kill_shop_tweens() -> void:
	UiAnim.kill_tween(_anim_tween)
	UiAnim.kill_tween(_gold_tween)
	UiAnim.kill_tween(_card_enter_tween)
	_kill_view_tweens()

func _play_hover() -> void:
	_play_stream(_hover_sfx, &"hover")

func _play_click() -> void:
	_play_stream(_click_sfx, &"click")

func _play_back() -> void:
	_play_stream(_back_sfx, &"back")

func _play_error() -> void:
	_play_stream(_error_sfx, &"error")

func _play_stream(player: AudioStreamPlayer, key: StringName) -> void:
	if player == null or player.stream == null:
		return
	var frame: int = Engine.get_process_frames()
	if int(_sfx_gate.get(key, -1)) == frame:
		return
	_sfx_gate[key] = frame
	player.play()
