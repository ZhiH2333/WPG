extends CanvasLayer
class_name UpgradeOffer

## 句间三选一。FloatingPanel 小面板 + 标题 PICK ONE，只负责展示与点选，不自己 grant。PROCESS_MODE_ALWAYS：单机选卡时 CombatSandbox 会冻场景树。卡片 osu 式错峰进场，逻辑开关仍瞬时。hover/click/back 与商店同套手感，punch 只装饰。
signal picked(upgrade_id: StringName)
signal cancelled

const HOVER_SCALE: float = 1.0
const HOVER_SEC: float = 0.12
const CARD_PUNCH_SCALE: float = 1.06
const CARD_PUNCH_SEC: float = 0.12

var _defs: Array[UpgradeDef] = []
var _open: bool = false
var _cards: Array[Button] = []
var _titles: Array[Label] = []
var _descs: Array[Label] = []
var _player_input: PlayerInput
var _anim_tween: Tween
var _hover_tweens: Dictionary = {}
var _punch_tweens: Dictionary = {}
var _sfx_gate: Dictionary = {}

@onready var _root: Control = $Root
@onready var _dimmer: ColorRect = $Root/Dimmer
@onready var _center: CenterContainer = $Root/Center
@onready var _panel: PanelContainer = $Root/Center/Panel
@onready var _card_root: HBoxContainer = $Root/Center/Panel/Column/Cards
@onready var _hover_sfx: AudioStreamPlayer = $HoverSfx
@onready var _click_sfx: AudioStreamPlayer = $ClickSfx
@onready var _back_sfx: AudioStreamPlayer = $BackSfx

func _ready() -> void:
	_panel.theme_type_variation = &"SurfaceGroup"
	UiStyle.present(self, true)
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	layer = 20
	_hover_sfx.stream = GameAudio.load_wav("res://audio/ui_hover.wav")
	_click_sfx.stream = GameAudio.load_wav("res://audio/ui_click.wav")
	_back_sfx.stream = GameAudio.load_wav("res://audio/ui_back.wav")
	_cards = [
		_card_root.get_node("Card0") as Button,
		_card_root.get_node("Card1") as Button,
		_card_root.get_node("Card2") as Button,
	]
	_titles = [
		_card_root.get_node("Card0/VBox/Title") as Label,
		_card_root.get_node("Card1/VBox/Title") as Label,
		_card_root.get_node("Card2/VBox/Title") as Label,
	]
	_descs = [
		_card_root.get_node("Card0/VBox/Desc") as Label,
		_card_root.get_node("Card1/VBox/Desc") as Label,
		_card_root.get_node("Card2/VBox/Desc") as Label,
	]
	for i: int in _cards.size():
		var card: Button = _cards[i]
		card.pressed.connect(_on_card_pressed.bind(i))
		card.pivot_offset = card.custom_minimum_size * 0.5
		_wire_hover(card, _on_card_hover_entered.bind(card), _on_card_hover_exited.bind(card))
	UiFit.connect_refit(_root, _on_viewport_size_changed)

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
	if _open:
		_fit_panel()
	_refresh_cards()
	_reset_card_motion()
	if not _open:
		return
	_anim_tween = UiAnim.enter_overlay(self, _dimmer, _panel, _cards, true)

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

func _on_viewport_size_changed() -> void:
	if not _open:
		return
	_fit_panel()

func _fit_panel() -> void:
	if _panel == null or _root == null:
		return
	UiFit.apply_floating_panel(_root, _panel, UiFit.OFFER_PANEL_MAX, UiFit.OFFER_PANEL_MIN)
	_panel.custom_minimum_size = UiFit.offer_panel_size(_root)
	if _center != null:
		_center.notification(Container.NOTIFICATION_SORT_CHILDREN)

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
		_cancel_offer()
		return
	var joy_button: InputEventJoypadButton = event as InputEventJoypadButton
	if joy_button != null and joy_button.pressed:
		if joy_button.button_index == JOY_BUTTON_START:
			get_viewport().set_input_as_handled()
			_cancel_offer()
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
		return

func _on_card_pressed(index: int) -> void:
	_pick_index(index)

func _pick_index(index: int) -> void:
	if not _open:
		return
	if index < 0 or index >= _defs.size():
		return
	_play_click()
	_punch_card(_cards[index])
	picked.emit(_defs[index].id)

func _cancel_offer() -> void:
	_play_back()
	cancelled.emit()

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

func _reset_card_motion() -> void:
	for card: Button in _cards:
		_kill_hover(card)
		_kill_punch(card)
		card.pivot_offset = card.custom_minimum_size * 0.5
		card.scale = Vector2.ONE

func _wire_hover(control: Control, entered: Callable, exited: Callable) -> void:
	control.mouse_entered.connect(entered)
	control.mouse_exited.connect(exited)
	control.focus_entered.connect(entered)
	control.focus_exited.connect(exited)

func _on_card_hover_entered(card: Button) -> void:
	if not _open:
		return
	if not is_instance_valid(card):
		return
	if _is_punching(card):
		return
	_play_hover()
	_tween_hover(card, true)

func _on_card_hover_exited(card: Button) -> void:
	if not is_instance_valid(card):
		return
	if _is_punching(card):
		return
	_tween_hover(card, false)

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

func _punch_card(card: Button) -> void:
	if not is_instance_valid(card):
		return
	_kill_hover(card)
	_kill_punch(card)
	var tween: Tween = UiAnim.punch_scale(self, card, CARD_PUNCH_SCALE, CARD_PUNCH_SEC, true)
	_punch_tweens[card.get_instance_id()] = tween
	if tween != null:
		tween.finished.connect(_on_punch_finished.bind(card.get_instance_id()))

func _on_punch_finished(key: int) -> void:
	_punch_tweens.erase(key)

func _is_punching(control: Control) -> bool:
	var tween: Tween = _punch_tweens.get(control.get_instance_id()) as Tween
	return tween != null and tween.is_valid()

func _kill_hover(control: Control) -> void:
	var key: int = control.get_instance_id()
	UiAnim.kill_tween(_hover_tweens.get(key) as Tween)
	_hover_tweens.erase(key)

func _kill_punch(control: Control) -> void:
	var key: int = control.get_instance_id()
	UiAnim.kill_tween(_punch_tweens.get(key) as Tween)
	_punch_tweens.erase(key)

func _play_hover() -> void:
	_play_stream(_hover_sfx, &"hover")

func _play_click() -> void:
	_play_stream(_click_sfx, &"click")

func _play_back() -> void:
	_play_stream(_back_sfx, &"back")

func _play_stream(player: AudioStreamPlayer, key: StringName) -> void:
	if player == null or player.stream == null:
		return
	var frame: int = Engine.get_process_frames()
	if int(_sfx_gate.get(key, -1)) == frame:
		return
	_sfx_gate[key] = frame
	player.play()
