extends CanvasLayer
class_name UpgradeOffer

## 句间三选一。只负责展示与点选，不自己 grant。禁止暂停场景树。
signal picked(upgrade_id: StringName)

var _defs: Array[UpgradeDef] = []
var _open: bool = false
var _cards: Array[Button] = []
var _titles: Array[Label] = []
var _descs: Array[Label] = []

@onready var _card_root: HBoxContainer = $Root/Center/Column/Cards

func _ready() -> void:
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

func is_open() -> bool:
	return _open

func present(defs: Array[UpgradeDef]) -> void:
	_defs = defs.duplicate()
	_open = not _defs.is_empty()
	visible = _open
	_refresh_cards()

func close() -> void:
	_open = false
	visible = false
	_defs.clear()
	_refresh_cards()

func get_offer_ids_label() -> String:
	if not _open or _defs.is_empty():
		return "-"
	var parts: PackedStringArray = PackedStringArray()
	for def: UpgradeDef in _defs:
		parts.append(String(def.id))
	return ",".join(parts)

func _input(event: InputEvent) -> void:
	if not _open:
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
