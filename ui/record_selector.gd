extends Control
class_name RecordSelector

## 主菜单档位叠层：一个叠层两个状态。LIST 点已有档进沙盒；EDITOR 选角色与 loop_goal 建档。删除走本叠层确认条，不要 AcceptDialog。
signal selected_record(id: String)

enum View { LIST, EDITOR }

const CATALOG: CharacterCatalog = preload("res://data/character_catalog.tres")
const DELETE_SIZE := Vector2(64, 64)
const DEFAULT_LOOP_GOAL: int = 20
const CHAR_BOAR := "boar"
const CHAR_CHICKEN := "chicken"

var _open: bool = false
var _view: View = View.LIST
var _anim_tween: Tween
var _pending_delete_id: String = ""
var _selected_character_id: String = CHAR_BOAR
var _selected_arena_id: String = "yard"

@onready var _dimmer: ColorRect = $Dimmer
@onready var _panel: PanelContainer = $Center/Panel
@onready var _list_root: Control = $Center/Panel/Column/Content/ListRoot
@onready var _scroll: ScrollContainer = $Center/Panel/Column/Content/ListRoot/Scroll
@onready var _cards: GridContainer = $Center/Panel/Column/Content/ListRoot/Scroll/Cards
@onready var _new_button: Button = $Center/Panel/Column/Content/ListRoot/Scroll/Cards/NewRecord
@onready var _editor_root: Control = $Center/Panel/Column/Content/EditorRoot
@onready var _boar_button: Button = $Center/Panel/Column/Content/EditorRoot/Center/Column/Characters/Boar
@onready var _chicken_button: Button = $Center/Panel/Column/Content/EditorRoot/Center/Column/Characters/Chicken
@onready var _yard_button: Button = $Center/Panel/Column/Content/EditorRoot/Center/Column/Arenas/Yard
@onready var _pit_button: Button = $Center/Panel/Column/Content/EditorRoot/Center/Column/Arenas/Pit
@onready var _loop_slider: HSlider = $Center/Panel/Column/Content/EditorRoot/Center/Column/LoopRow/Slider
@onready var _loop_label: Label = $Center/Panel/Column/Content/EditorRoot/Center/Column/LoopRow/LoopLabel
@onready var _name_edit: LineEdit = $Center/Panel/Column/Content/EditorRoot/Center/Column/NameEdit
@onready var _confirm_button: Button = $Center/Panel/Column/Content/EditorRoot/Center/Column/Confirm
@onready var _delete_root: Control = $Center/Panel/Column/Content/DeleteRoot
@onready var _delete_yes: Button = $Center/Panel/Column/Content/DeleteRoot/Center/Panel/Column/Buttons/Yes
@onready var _delete_no: Button = $Center/Panel/Column/Content/DeleteRoot/Center/Panel/Column/Buttons/No
@onready var _back_button: Button = $Center/Panel/Column/Back

func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fill_editor_character(_boar_button, CHAR_BOAR)
	_fill_editor_character(_chicken_button, CHAR_CHICKEN)
	_new_button.pressed.connect(_on_new_pressed)
	_boar_button.pressed.connect(_on_boar_pressed)
	_chicken_button.pressed.connect(_on_chicken_pressed)
	_yard_button.pressed.connect(_on_yard_pressed)
	_pit_button.pressed.connect(_on_pit_pressed)
	_loop_slider.value_changed.connect(_on_loop_changed)
	_confirm_button.pressed.connect(_on_confirm_pressed)
	_delete_yes.pressed.connect(_on_delete_yes_pressed)
	_delete_no.pressed.connect(_on_delete_no_pressed)
	_back_button.pressed.connect(_on_back_pressed)
	UiFit.connect_refit(self, _on_host_resized)
	_show_list_nodes()

func is_open() -> bool:
	return _open

func open() -> void:
	_open = true
	visible = true
	modulate.a = 1.0
	mouse_filter = Control.MOUSE_FILTER_STOP
	_pending_delete_id = ""
	_fit_panel()
	_show_list_nodes()
	_refresh_list()
	UiAnim.kill_tween(_anim_tween)
	_anim_tween = UiAnim.enter_overlay(self, _dimmer, _panel, _collect_list_cards())
	_focus_list()

func close() -> void:
	if not _open:
		return
	_open = false
	_pending_delete_id = ""
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiAnim.kill_tween(_anim_tween)
	_anim_tween = UiAnim.exit_overlay(self, self)
	_anim_tween.finished.connect(_finish_close)
	_refocus_menu()

func _refocus_menu() -> void:
	var play: Button = get_parent().get_node_or_null("Center/Column/Buttons/Play") as Button
	if play != null:
		play.grab_focus()

func _finish_close() -> void:
	if _open:
		return
	visible = false
	modulate.a = 1.0

func _input(event: InputEvent) -> void:
	if not _open:
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_handle_back()
		return
	if event is InputEventJoypadButton:
		var joy: InputEventJoypadButton = event as InputEventJoypadButton
		if joy.pressed and joy.button_index == JOY_BUTTON_START:
			get_viewport().set_input_as_handled()
			_handle_back()
			return
	if _view != View.EDITOR or _is_deleting():
		return
	if _name_edit.has_focus():
		return
	if event.is_action_pressed("weapon_pistol"):
		get_viewport().set_input_as_handled()
		_select_character(CHAR_BOAR)
		return
	if event.is_action_pressed("weapon_shotgun"):
		get_viewport().set_input_as_handled()
		_select_character(CHAR_CHICKEN)

func _handle_back() -> void:
	if _is_deleting():
		_cancel_delete()
		return
	if _view == View.EDITOR:
		_enter_list(false)
		return
	close()

func _on_back_pressed() -> void:
	_handle_back()

func _on_new_pressed() -> void:
	if not _open or _new_button.disabled:
		return
	_enter_editor()

func _on_record_pressed(record_id: String) -> void:
	if not _open or _view != View.LIST or _is_deleting():
		return
	selected_record.emit(record_id)

func _on_delete_pressed(record_id: String) -> void:
	if not _open or _view != View.LIST:
		return
	_pending_delete_id = record_id
	_list_root.visible = false
	_editor_root.visible = false
	_delete_root.visible = true
	_delete_no.grab_focus()

func _on_delete_yes_pressed() -> void:
	if _pending_delete_id.is_empty():
		_enter_list(true)
		return
	GameRecords.delete_record(_pending_delete_id)
	_pending_delete_id = ""
	_enter_list(true)

func _on_delete_no_pressed() -> void:
	_cancel_delete()

func _cancel_delete() -> void:
	_pending_delete_id = ""
	_enter_list(false)

func _on_boar_pressed() -> void:
	_select_character(CHAR_BOAR)

func _on_chicken_pressed() -> void:
	_select_character(CHAR_CHICKEN)

func _on_yard_pressed() -> void:
	_select_arena("yard")

func _on_pit_pressed() -> void:
	_select_arena("pit")

func _on_loop_changed(_value: float) -> void:
	_refresh_loop_label()

func _on_confirm_pressed() -> void:
	if not _open or _view != View.EDITOR:
		return
	var loop_goal: int = maxi(roundi(_loop_slider.value), 0)
	var record: GameRecord = GameRecords.create_record(_name_edit.text, _selected_character_id, loop_goal, _selected_arena_id)
	if record == null:
		return
	selected_record.emit(record.id)

func _enter_list(refresh: bool) -> void:
	_view = View.LIST
	_show_list_nodes()
	if refresh:
		_refresh_list()
	_play_card_enter(_collect_list_cards())
	_focus_list()

func _enter_editor() -> void:
	_view = View.EDITOR
	_pending_delete_id = ""
	_list_root.visible = false
	_delete_root.visible = false
	_editor_root.visible = true
	_reset_editor()
	_play_card_enter([_boar_button, _chicken_button, _yard_button, _pit_button, _confirm_button, _back_button])
	_boar_button.grab_focus()

func _show_list_nodes() -> void:
	_view = View.LIST
	_list_root.visible = true
	_editor_root.visible = false
	_delete_root.visible = false

func _is_deleting() -> bool:
	return not _pending_delete_id.is_empty()

func _reset_editor() -> void:
	_select_character(CHAR_BOAR)
	_select_arena("yard")
	_loop_slider.set_value_no_signal(float(DEFAULT_LOOP_GOAL))
	_refresh_loop_label()
	_name_edit.text = ""

func _select_character(character_id: String) -> void:
	_selected_character_id = character_id
	_boar_button.set_pressed_no_signal(character_id == CHAR_BOAR)
	_chicken_button.set_pressed_no_signal(character_id == CHAR_CHICKEN)

func _select_arena(arena_id: String) -> void:
	_selected_arena_id = GameLaunch._sanitize_arena_id(arena_id)
	_yard_button.set_pressed_no_signal(_selected_arena_id == "yard")
	_pit_button.set_pressed_no_signal(_selected_arena_id == "pit")

func _refresh_loop_label() -> void:
	_loop_label.text = RecordCard.format_loop_badge(maxi(roundi(_loop_slider.value), 0))

func _refresh_list() -> void:
	GameRecords.load_from_disk()
	_clear_record_rows()
	var card: Vector2 = _fit_card_size()
	_new_button.custom_minimum_size = card
	for record: GameRecord in GameRecords.list_records():
		_cards.add_child(_make_record_row(record))
	_cards.move_child(_new_button, -1)
	_update_new_button()
	_fit_scroll()
	_scroll.scroll_vertical = 0

func _clear_record_rows() -> void:
	var stale: Array[Node] = []
	for child: Node in _cards.get_children():
		if child == _new_button:
			continue
		stale.append(child)
	for child: Node in stale:
		_cards.remove_child(child)
		child.queue_free()

func _update_new_button() -> void:
	var is_full: bool = GameRecords.list_records().size() >= GameRecords.get_max_records()
	_new_button.disabled = is_full
	_new_button.focus_mode = Control.FOCUS_NONE if is_full else Control.FOCUS_ALL

func _fit_scroll() -> void:
	_scroll.scroll_vertical = 0

func _focus_list() -> void:
	if _cards.get_child_count() <= 0:
		_back_button.grab_focus()
		return
	if _new_button.disabled == false and _cards.get_child_count() <= 1:
		_new_button.grab_focus()
		return
	var first: Node = _cards.get_child(0)
	if first == _new_button:
		_new_button.grab_focus()
		return
	var main: Button = first as Button
	if main == null:
		_back_button.grab_focus()
		return
	main.grab_focus()

func _collect_list_cards() -> Array:
	var cards: Array = []
	for child: Node in _cards.get_children():
		var button: Button = child as Button
		if button != null:
			cards.append(button)
	cards.append(_back_button)
	return cards

func _play_card_enter(cards: Array) -> void:
	UiAnim.kill_tween(_anim_tween)
	_anim_tween = UiAnim.enter_overlay(self, null, null, cards)

func _make_record_row(record: GameRecord) -> Button:
	var button: Button = _make_main_card(record)
	var delete_button: Button = _make_delete_button(record.id)
	delete_button.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	delete_button.anchor_left = 1.0
	delete_button.anchor_top = 0.5
	delete_button.anchor_right = 1.0
	delete_button.anchor_bottom = 0.5
	delete_button.offset_left = -DELETE_SIZE.x - 16.0
	delete_button.offset_top = -DELETE_SIZE.y * 0.5
	delete_button.offset_right = -16.0
	delete_button.offset_bottom = DELETE_SIZE.y * 0.5
	button.add_child(delete_button)
	return button

func _make_delete_button(record_id: String) -> Button:
	var button: Button = Button.new()
	button.custom_minimum_size = DELETE_SIZE
	button.theme_type_variation = &"OfferButton"
	button.text = "×"
	button.pressed.connect(_on_delete_pressed.bind(record_id))
	return button

func _fit_card_size() -> Vector2:
	var panel_w: float = _panel.custom_minimum_size.x
	var columns: int = UiFit.card_columns(panel_w)
	_cards.columns = columns
	return UiFit.card_size(panel_w, columns)

func _make_main_card(record: GameRecord) -> Button:
	var card: Vector2 = _fit_card_size()
	var button: Button = RecordCard.make_main_card(record, card, UiFit.portrait_px(card))
	button.pressed.connect(_on_record_pressed.bind(record.id))
	return button

func _fill_editor_character(button: Button, character_id: String) -> void:
	var def: CharacterDef = CATALOG.get_by_id(StringName(character_id))
	var portrait: TextureRect = button.get_node("VBox/Portrait") as TextureRect
	var title: Label = button.get_node("VBox/Title") as Label
	var desc: Label = button.get_node("VBox/Desc") as Label
	if portrait != null:
		portrait.texture = RecordCard.resolve_body_texture(character_id)
	if title != null:
		title.text = def.display_name if def != null else character_id
	if desc != null:
		desc.text = def.description if def != null else ""

func _on_host_resized() -> void:
	if not _open:
		return
	_fit_panel()

func _fit_panel() -> void:
	UiFit.apply_floating_panel(self, _panel)
	if _view != View.LIST:
		return
	var card: Vector2 = _fit_card_size()
	_new_button.custom_minimum_size = card
	for child: Node in _cards.get_children():
		var button: Button = child as Button
		if button != null:
			button.custom_minimum_size = card
