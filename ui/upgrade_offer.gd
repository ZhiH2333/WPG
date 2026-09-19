extends CanvasLayer
class_name UpgradeOffer

## 句间三选一。只负责展示与点选，不自己 grant。PROCESS_MODE_ALWAYS：单机选卡时 CombatSandbox 会冻场景树。卡片 osu 式错峰进场，逻辑开关仍瞬时。
signal picked(upgrade_id: StringName)
signal cancelled

var _defs: Array[UpgradeDef] = []
var _open: bool = false
var _cards: Array[Button] = []
var _titles: Array[Label] = []
var _descs: Array[Label] = []
var _player_input: PlayerInput
var _anim_tween: Tween

@onready var _root: Control = $Root
@onready var _dimmer: ColorRect = $Root/Dimmer
@onready var _center: CenterContainer = $Root/Center
@onready var _card_root: HBoxContainer = $Root/Center/Column/Cards

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
	for i: int in _cards.size():
		var card: Button = _cards[i]
		card.pressed.connect(_on_card_pressed.bind(i))

func bind_session(_session: RunSession) -> void:
	pass

func bind_player_input(player_input: PlayerInput) -> void:
	_player_input = player_input

func is_open() -> bool:
	return _open

func present(defs: Array[UpgradeDef]) -> void:
	UiAnim.kill_tween(_anim_tween)
	_defs = defs.duplicate()
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

func get_offer_ids_label() -> String:
	if not _open or _defs.is_empty():
		return "-"
	var parts: PackedStringArray = PackedStringArray()
	for def: UpgradeDef in _defs:
		parts.append(String(def.id))
	return ",".join(parts)

func _process(_delta: float) -> void:
	if not _open or _player_input == null:
		return
	var slot: int = _player_input.get_weapon_slot_just_pressed()
	if slot >= 0 and slot <= 2:
		_pick_index(slot)

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

func _on_card_pressed(index: int) -> void:
	_pick_index(index)

func _pick_index(index: int) -> void:
	if not _open:
		return
	if index < 0 or index >= _defs.size():
		return
	picked.emit(_defs[index].id)

func _refresh_cards() -> void:
	for i: int in _cards.size():
		var show_card: bool = _open and i < _defs.size()
		_cards[i].visible = show_card
		if not show_card:
			_titles[i].text = ""
			_descs[i].text = ""
			continue
		_titles[i].text = _defs[i].title
		_descs[i].text = _defs[i].description
