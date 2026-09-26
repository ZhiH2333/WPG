extends Control
class_name RecordSelector

## 主菜单档位叠层：一个叠层两个状态。LIST 点已有档进沙盒；EDITOR 选角色与 loop_goal 建档。删除走本叠层确认条，不要 AcceptDialog。
signal selected_record(id: String)

enum View { LIST, EDITOR }

const CATALOG: CharacterCatalog = preload("res://data/character_catalog.tres")
const DELETE_SIZE := Vector2(40, 40)
const DELETE_MARGIN: float = 12.0
const CARD_RIGHT_RESERVE: float = DELETE_SIZE.x + DELETE_MARGIN * 2.0
const PAGE_MARGIN_X: float = 720.0
const SUBTITLE_LIST := "Pick a save, or brand a new one"
const SUBTITLE_EDITOR := "Brand a new save"
const DEFAULT_LOOP_GOAL: int = 20
const CHAR_BOAR := "boar"
const CHAR_CHICKEN := "chicken"

var _open: bool = false
var _view: View = View.LIST
var _anim_tween: Tween
var _modal_tween: Tween
var _sfx_gate: Dictionary = {}
var _pending_delete_id: String = ""
var _selected_character_id: String = CHAR_BOAR
var _selected_arena_id: String = "yard"

@onready var _dimmer: ColorRect = $Dimmer
@onready var _sheet: Control = $Sheet
@onready var _subtitle: Label = $Sheet/Column/Subtitle
@onready var _content: Control = $Sheet/Column/Content
@onready var _list_root: Control = $Sheet/Column/Content/ListRoot
@onready var _scroll: ScrollContainer = $Sheet/Column/Content/ListRoot/Scroll
@onready var _cards: GridContainer = $Sheet/Column/Content/ListRoot/Scroll/Cards
@onready var _new_button: Button = $Sheet/Column/Content/ListRoot/Scroll/Cards/NewRecord
@onready var _editor_root: Control = $Sheet/Column/Content/EditorRoot
@onready var _boar_button: Button = $Sheet/Column/Content/EditorRoot/Center/Column/Characters/Boar
@onready var _chicken_button: Button = $Sheet/Column/Content/EditorRoot/Center/Column/Characters/Chicken
@onready var _yard_button: Button = $Sheet/Column/Content/EditorRoot/Center/Column/Arenas/Yard
@onready var _pit_button: Button = $Sheet/Column/Content/EditorRoot/Center/Column/Arenas/Pit
@onready var _keep_button: Button = $Sheet/Column/Content/EditorRoot/Center/Column/Arenas/Keep
@onready var _loop_slider: HSlider = $Sheet/Column/Content/EditorRoot/Center/Column/LoopRow/Slider
@onready var _loop_label: Label = $Sheet/Column/Content/EditorRoot/Center/Column/LoopRow/LoopLabel
@onready var _name_edit: LineEdit = $Sheet/Column/Content/EditorRoot/Center/Column/NameEdit
@onready var _confirm_button: Button = $Sheet/Column/Content/EditorRoot/Center/Column/Confirm
@onready var _delete_dimmer: ColorRect = $DeleteDimmer
@onready var _delete_center: CenterContainer = $DeleteCenter
@onready var _delete_panel: PanelContainer = $DeleteCenter/DeletePanel
@onready var _delete_yes: Button = $DeleteCenter/DeletePanel/Column/Buttons/Yes
@onready var _delete_no: Button = $DeleteCenter/DeletePanel/Column/Buttons/No
@onready var _back_button: Button = $Sheet/Column/Header/Back
@onready var _hover_sfx: AudioStreamPlayer = $HoverSfx
@onready var _click_sfx: AudioStreamPlayer = $ClickSfx
@onready var _back_sfx: AudioStreamPlayer = $BackSfx
@onready var _error_sfx: AudioStreamPlayer = $ErrorSfx

func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hover_sfx.stream = GameAudio.load_wav("res://audio/ui_hover.wav")
	_click_sfx.stream = GameAudio.load_wav("res://audio/ui_click.wav")
	_back_sfx.stream = GameAudio.load_wav("res://audio/ui_back.wav")
	_error_sfx.stream = GameAudio.load_wav("res://audio/click.wav")
	_fill_editor_character(_boar_button, CHAR_BOAR)
	_fill_editor_character(_chicken_button, CHAR_CHICKEN)
	_new_button.pressed.connect(_on_new_pressed)
	_boar_button.pressed.connect(_on_boar_pressed)
	_chicken_button.pressed.connect(_on_chicken_pressed)
	_yard_button.pressed.connect(_on_yard_pressed)
	_pit_button.pressed.connect(_on_pit_pressed)
	_keep_button.pressed.connect(_on_keep_pressed)
	_loop_slider.value_changed.connect(_on_loop_changed)
	_confirm_button.pressed.connect(_on_confirm_pressed)
	_delete_yes.pressed.connect(_on_delete_yes_pressed)
	_delete_no.pressed.connect(_on_delete_no_pressed)
	_back_button.pressed.connect(_on_back_pressed)
	for button: Button in [_new_button, _boar_button, _chicken_button, _yard_button, _pit_button, _keep_button, _confirm_button, _delete_yes, _delete_no, _back_button]:
		_wire_hover(button)
		UiAnim.wire_row_feedback(self, button, UiType.INK)
	UiFit.connect_refit(self, _on_host_resized)
	_content.resized.connect(_on_content_resized)
	_show_list_nodes()

func is_open() -> bool:
	return _open

func open(direction: int = 0) -> void:
	_open = true
	visible = true
	modulate.a = 1.0
	mouse_filter = Control.MOUSE_FILTER_STOP
	_pending_delete_id = ""
	_reset_delete_modal()
	_show_list_nodes()
	_fit_cards()
	_refresh_list()
	UiAnim.kill_tween(_anim_tween)
	_anim_tween = UiAnim.enter_page(self, _dimmer, _sheet, false, direction)
	UiAnim.enter_cards(self, _collect_list_cards())
	_focus_list()

func close(direction: int = 0) -> void:
	if not _open:
		return
	_open = false
	_pending_delete_id = ""
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hide_delete_modal()
	UiAnim.kill_tween(_anim_tween)
	_anim_tween = UiAnim.exit_page(self, _dimmer, _sheet, false, direction)
	_anim_tween.finished.connect(_finish_close)
	_refocus_menu()

func _refocus_menu() -> void:
	var menu: MainMenu = get_parent() as MainMenu
	if menu != null:
		menu.on_record_selector_closed()

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
		_play_click()
		_select_character(CHAR_BOAR)
		return
	if event.is_action_pressed("weapon_shotgun"):
		get_viewport().set_input_as_handled()
		_play_click()
		_select_character(CHAR_CHICKEN)

func _handle_back() -> void:
	_play_back()
	if _is_deleting():
		_cancel_delete()
		return
	if _view == View.EDITOR:
		_enter_list(false)
		return
	close(-1)

func _on_back_pressed() -> void:
	_handle_back()

func _on_new_pressed() -> void:
	if not _open:
		return
	if GameRecords.list_records().size() >= GameRecords.get_max_records():
		_play_error()
		return
	_play_click()
	_enter_editor()

func _on_record_pressed(record_id: String) -> void:
	if not _open or _view != View.LIST or _is_deleting():
		return
	_play_click()
	selected_record.emit(record_id)

func _on_delete_pressed(record_id: String) -> void:
	if not _open or _view != View.LIST:
		return
	_play_click()
	_pending_delete_id = record_id
	_show_delete_modal()
	_delete_no.grab_focus()

func _on_delete_yes_pressed() -> void:
	_play_click()
	if _pending_delete_id.is_empty():
		_enter_list(true)
		return
	GameRecords.delete_record(_pending_delete_id)
	_pending_delete_id = ""
	_enter_list(true)

func _on_delete_no_pressed() -> void:
	_handle_back()

func _cancel_delete() -> void:
	_pending_delete_id = ""
	_enter_list(false)

func _on_boar_pressed() -> void:
	_play_click()
	_select_character(CHAR_BOAR)

func _on_chicken_pressed() -> void:
	_play_click()
	_select_character(CHAR_CHICKEN)

func _on_yard_pressed() -> void:
	_play_click()
	_select_arena("yard")

func _on_pit_pressed() -> void:
	_play_click()
	_select_arena("pit")

func _on_keep_pressed() -> void:
	_play_click()
	_select_arena("keep")

func _on_loop_changed(_value: float) -> void:
	_refresh_loop_label()

func _on_confirm_pressed() -> void:
	if not _open or _view != View.EDITOR:
		return
	_play_click()
	var loop_goal: int = maxi(roundi(_loop_slider.value), 0)
	var record: GameRecord = GameRecords.create_record(_name_edit.text, _selected_character_id, loop_goal, _selected_arena_id)
	if record == null:
		_play_error()
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
	_editor_root.visible = true
	_subtitle.text = SUBTITLE_EDITOR
	_hide_delete_modal()
	_reset_editor()
	_play_card_enter([_boar_button, _chicken_button, _yard_button, _pit_button, _keep_button, _confirm_button, _back_button])
	_boar_button.grab_focus()

func _show_list_nodes() -> void:
	_view = View.LIST
	_list_root.visible = true
	_editor_root.visible = false
	_subtitle.text = SUBTITLE_LIST
	_hide_delete_modal()

func _show_delete_modal() -> void:
	_delete_dimmer.visible = true
	_delete_center.visible = true
	UiAnim.kill_tween(_modal_tween)
	_modal_tween = UiAnim.enter_modal(self, _delete_dimmer, _delete_panel)

func _hide_delete_modal() -> void:
	if not _delete_center.visible:
		return
	UiAnim.kill_tween(_modal_tween)
	_modal_tween = UiAnim.exit_modal(self, _delete_dimmer, _delete_panel)
	_modal_tween.finished.connect(_finish_delete_modal_close)

func _finish_delete_modal_close() -> void:
	if _is_deleting():
		return
	_delete_dimmer.visible = false
	_delete_center.visible = false

func _reset_delete_modal() -> void:
	UiAnim.kill_tween(_modal_tween)
	_delete_dimmer.visible = false
	_delete_center.visible = false
	_delete_dimmer.modulate.a = 1.0
	_delete_panel.modulate.a = 1.0
	_delete_panel.scale = Vector2.ONE

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
	_keep_button.set_pressed_no_signal(_selected_arena_id == "keep")

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
	_new_button.disabled = false
	_new_button.focus_mode = Control.FOCUS_ALL

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
	_anim_tween = UiAnim.enter_cards(self, cards)

func _make_record_row(record: GameRecord) -> Button:
	var button: Button = _make_main_card(record)
	var delete_button: Button = _make_delete_button(record.id)
	delete_button.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	delete_button.anchor_left = 1.0
	delete_button.anchor_top = 0.5
	delete_button.anchor_right = 1.0
	delete_button.anchor_bottom = 0.5
	delete_button.offset_left = -DELETE_SIZE.x - DELETE_MARGIN
	delete_button.offset_top = -DELETE_SIZE.y * 0.5
	delete_button.offset_right = -DELETE_MARGIN
	delete_button.offset_bottom = DELETE_SIZE.y * 0.5
	button.add_child(delete_button)
	return button

func _make_delete_button(record_id: String) -> Button:
	var button: Button = Button.new()
	button.name = "Delete"
	button.custom_minimum_size = DELETE_SIZE
	button.theme_type_variation = &"EmptyButtonMuted"
	button.text = "×"
	button.add_child(RecordCard.make_mark())
	button.pressed.connect(_on_delete_pressed.bind(record_id))
	_wire_hover(button)
	UiAnim.wire_row_feedback(self, button, UiType.INK)
	return button

func _fit_card_size() -> Vector2:
	var content_w: float = _content_width()
	var columns: int = UiFit.card_columns(content_w)
	_cards.columns = columns
	return UiFit.card_size(content_w, columns)

func _content_width() -> float:
	var width: float = _content.size.x
	if width > 1.0:
		return width
	return maxf(UiFit.visible_size(self).x - PAGE_MARGIN_X, 320.0)

func _make_main_card(record: GameRecord) -> Button:
	var card: Vector2 = _fit_card_size()
	var button: Button = RecordCard.make_main_card(record, card, UiFit.portrait_px(card), CARD_RIGHT_RESERVE)
	button.pressed.connect(_on_record_pressed.bind(record.id))
	_wire_hover(button)
	UiAnim.wire_row_feedback(self, button, UiType.INK)
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
	_fit_cards.call_deferred()

## Content 是 Page 里唯一随窗口变宽的那一段；它的 resized 带新宽度，比 host.resized 早一步可用。
func _on_content_resized() -> void:
	if not _open:
		return
	_fit_cards()

func _fit_cards() -> void:
	if _view != View.LIST:
		return
	var card: Vector2 = _fit_card_size()
	var portrait: float = UiFit.portrait_px(card)
	_new_button.custom_minimum_size = card
	for child: Node in _cards.get_children():
		var button: Button = child as Button
		if button == null:
			continue
		button.custom_minimum_size = card
		var portrait_rect: TextureRect = button.get_node_or_null("Content/Portrait") as TextureRect
		if portrait_rect != null:
			portrait_rect.custom_minimum_size = Vector2(portrait, portrait)

func _wire_hover(button: BaseButton) -> void:
	if button.mouse_entered.is_connected(_play_hover):
		return
	button.mouse_entered.connect(_play_hover)
	button.focus_entered.connect(_play_hover)

func _play_hover() -> void:
	if not _open:
		return
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
