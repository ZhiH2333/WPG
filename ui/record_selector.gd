extends Control
class_name RecordSelector

## 存档列表叠层（Save Management UX）：一排一个存档，纵向排列，不再铺卡片墙。
## 一叠层三态 + 三层浮层：
##   LIST    —— 纵向 SaveRow 列表（§2/§3）
##   EDITOR  —— 选角色 / 场地 / loop_goal 建档（§8）
##   浮层    —— 详情（§4）/ 删除二次确认（§9）/ 已通关确认（§5）
##
## 状态**只**来自 SaveSlot：`SaveUiProjection.load_*()` -> GameSaveStore -> SaveSlot。
## 这里不读 records.json、不用 history 长度猜状态、不判断 active_run（§15）。
##
## selected_record = 用该档**新开一局**（START_NEW_RUN）。
## resume_record   = **继续这一局**（RESUME_RUN），只有 IN_PROGRESS 存档会走这条。
signal selected_record(id: String)
signal resume_record(id: String)

enum View { LIST, EDITOR }

const CATALOG: CharacterCatalog = preload("res://data/character_catalog.tres")
const DELETE_SIZE := Vector2(40, 40)
const DELETE_MARGIN: float = 12.0
const DELETE_ZONE: float = DELETE_SIZE.x + DELETE_MARGIN * 2.0
## 列表全宽：左右各留 48。别再写死 720/672 这种「1920 设计稿」的数字。
const CONTENT_MARGIN: float = 48.0
## 存档行不跟着铺满 4K：版心最宽 1200，窄视口按视口宽收缩。
const CONTENT_MAX_WIDTH: float = 1200.0
const SUBTITLE_LIST := "Pick a save, or brand a new one"
const SUBTITLE_EDITOR := "Brand a new save"
const DEFAULT_LOOP_GOAL: int = 20
const CHAR_BOAR := "boar"
const CHAR_CHICKEN := "chicken"

var _open: bool = false
var _view: View = View.LIST
var _anim_tween: Tween
var _modal_tween: Tween
var _detail_tween: Tween
var _completed_tween: Tween
var _sfx_gate: Dictionary = {}
var _pending_delete_id: String = ""
var _pending_completed_id: String = ""
var _detail_id: String = ""
var _synced_width: float = 0.0
var _selected_character_id: String = CHAR_BOAR
var _selected_arena_id: String = "yard"
var _list_drag: DragScroll
var _editor_drag: DragScroll

@onready var _dimmer: ColorRect = $Dimmer
@onready var _sheet: Control = $Sheet
@onready var _column: VBoxContainer = $Sheet/Column
@onready var _subtitle: Label = $Sheet/Column/Subtitle
@onready var _content: Control = $Sheet/Column/Content
@onready var _list_root: Control = $Sheet/Column/Content/ListRoot
@onready var _scroll: ScrollContainer = $Sheet/Column/Content/ListRoot/Scroll
@onready var _rows: VBoxContainer = $Sheet/Column/Content/ListRoot/Scroll/Rows
## New Record 现在是 Header 右上角的 CTA，不再挂在列表末尾。
@onready var _new_button: Button = $Sheet/Column/Header/NewRecord
@onready var _editor_root: Control = $Sheet/Column/Content/EditorRoot
@onready var _editor_scroll: ScrollContainer = $Sheet/Column/Content/EditorRoot/Scroll
@onready var _editor_column: VBoxContainer = $Sheet/Column/Content/EditorRoot/Scroll/Column
@onready var _boar_button: Button = $Sheet/Column/Content/EditorRoot/Scroll/Column/Characters/Boar
@onready var _chicken_button: Button = $Sheet/Column/Content/EditorRoot/Scroll/Column/Characters/Chicken
@onready var _yard_button: Button = $Sheet/Column/Content/EditorRoot/Scroll/Column/Arenas/Yard
@onready var _pit_button: Button = $Sheet/Column/Content/EditorRoot/Scroll/Column/Arenas/Pit
@onready var _keep_button: Button = $Sheet/Column/Content/EditorRoot/Scroll/Column/Arenas/Keep
@onready var _loop_slider: HSlider = $Sheet/Column/Content/EditorRoot/Scroll/Column/LoopRow/Slider
@onready var _loop_label: Label = $Sheet/Column/Content/EditorRoot/Scroll/Column/LoopRow/LoopLabel
@onready var _name_edit: LineEdit = $Sheet/Column/Content/EditorRoot/Scroll/Column/NameEdit
## Confirm 也在 Header 右上角（和 + New Record 同一个槽位，按视图切换）
@onready var _confirm_button: Button = $Sheet/Column/Header/Confirm
## 删除二次确认（§9）：Name / Progress / History + "This cannot be undone."，默认焦点 CANCEL。
@onready var _delete_dimmer: ColorRect = $DeleteDimmer
@onready var _delete_center: CenterContainer = $DeleteCenter
@onready var _delete_panel: PanelContainer = $DeleteCenter/DeletePanel
@onready var _delete_body: Label = $DeleteCenter/DeletePanel/Column/Body
@onready var _delete_cancel: Button = $DeleteCenter/DeletePanel/Column/Buttons/Cancel
@onready var _delete_confirm: Button = $DeleteCenter/DeletePanel/Column/Buttons/Delete
## 已通关档的确认条（§5）：COMPLETED / "This save has already been cleared." / "Start over?"
@onready var _completed_dimmer: ColorRect = $CompletedDimmer
@onready var _completed_center: CenterContainer = $CompletedCenter
@onready var _completed_panel: PanelContainer = $CompletedCenter/CompletedPanel
@onready var _completed_name: Label = $CompletedCenter/CompletedPanel/Column/Name
@onready var _completed_yes: Button = $CompletedCenter/CompletedPanel/Column/Buttons/StartNew
@onready var _completed_no: Button = $CompletedCenter/CompletedPanel/Column/Buttons/Cancel
## 点开一排后的详情 / 确认浮层（§4）：12 个字段 + CONTINUE RUN / DELETE / CANCEL。
@onready var _detail_dimmer: ColorRect = $DetailDimmer
@onready var _detail_center: CenterContainer = $DetailCenter
@onready var _detail_panel: PanelContainer = $DetailCenter/DetailPanel
@onready var _detail_title: Label = $DetailCenter/DetailPanel/Column/Title
@onready var _detail_status: Label = $DetailCenter/DetailPanel/Column/Status
@onready var _detail_left: VBoxContainer = $DetailCenter/DetailPanel/Column/Grid/Left
@onready var _detail_right: VBoxContainer = $DetailCenter/DetailPanel/Column/Grid/Right
@onready var _detail_yes: Button = $DetailCenter/DetailPanel/Column/Buttons/Continue
@onready var _detail_delete: Button = $DetailCenter/DetailPanel/Column/Buttons/Delete
@onready var _detail_no: Button = $DetailCenter/DetailPanel/Column/Buttons/Cancel
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
	_delete_confirm.pressed.connect(_on_delete_yes_pressed)
	_delete_cancel.pressed.connect(_on_delete_no_pressed)
	_detail_yes.pressed.connect(_on_detail_yes_pressed)
	_detail_delete.pressed.connect(_on_detail_delete_pressed)
	_detail_no.pressed.connect(_on_detail_no_pressed)
	_completed_yes.pressed.connect(_on_completed_yes_pressed)
	_completed_no.pressed.connect(_on_completed_no_pressed)
	_back_button.pressed.connect(_on_back_pressed)
	for button: Button in [_new_button, _boar_button, _chicken_button, _yard_button, _pit_button, _keep_button, _confirm_button, _delete_cancel, _delete_confirm, _detail_yes, _detail_delete, _detail_no, _completed_yes, _completed_no, _back_button]:
		_wire_hover(button)
		UiAnim.wire_row_feedback(self, button, UiType.INK)
	_list_drag = DragScroll.attach(_scroll, _list_root)
	_editor_drag = DragScroll.attach(_editor_scroll, _editor_root)
	UiFit.connect_refit(self, _on_host_resized)
	_content.resized.connect(_on_content_resized)
	sync_content_width_for(_logical_viewport_width())
	_show_list_nodes()

func is_open() -> bool:
	return _open

func open(direction: int = 0) -> void:
	_open = true
	visible = true
	modulate.a = 1.0
	mouse_filter = Control.MOUSE_FILTER_STOP
	_pending_delete_id = ""
	_pending_completed_id = ""
	_reset_delete_modal()
	_reset_completed_modal()
	_reset_detail_modal()
	_show_list_nodes()
	## 叠层的 _ready 早于 MainMenu._ready 的 GameSettings.apply()，拿到的还是旧 UI Scale；
	## 打开这一刻按当前逻辑视口重算一遍版心 / 建档表单宽度 / 存档行宽度。
	sync_content_width_for(_logical_viewport_width())
	_fit_rows()
	_refresh_list()
	if _list_drag != null:
		_list_drag.reset()
	UiAnim.kill_tween(_anim_tween)
	_anim_tween = UiAnim.enter_page(self, _dimmer, _sheet, false, direction)
	UiAnim.enter_cards(self, _collect_list_cards())

func close(direction: int = 0) -> void:
	if not _open:
		return
	_open = false
	_pending_delete_id = ""
	_pending_completed_id = ""
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hide_delete_modal()
	_hide_completed_modal()
	_hide_detail_modal()
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

func _process(delta: float) -> void:
	if not _open:
		return
	if _list_drag != null:
		_list_drag.step(delta)
	if _editor_drag != null:
		_editor_drag.step(delta)

func _input(event: InputEvent) -> void:
	if not _open:
		return
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		print("PROBE_RS_INPUT ", event)
	## 触屏拖动滚动优先于按钮：越过 TOUCH_SLOP 才吞事件，tap 照旧落到卡片上。
	## 见 ui/drag_scroll.gd 顶部注释：emulate_mouse_from_touch 让 ScrollContainer 自带的
	## 触控拖动失效，只能在这里接管原生触摸事件。
	var drag: DragScroll = _editor_drag if _view == View.EDITOR else _list_drag
	var _handled: bool = drag != null and drag.handle_event(event)
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		print("PROBE_RS_HANDLED ", _handled, " list_rect=", _list_drag._area.get_global_rect() if _list_drag != null and _list_drag._area != null else Rect2())
	if _handled:
		get_viewport().set_input_as_handled()
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
	## 打开界面时不自动聚焦（见 UiFocus）：键盘 / 手柄第一次按导航键才建立焦点。
	## 放在 Esc / START 分支之后，避免这两键被当成「第一次导航输入」而改变返回行为。
	if UiFocus.handle_first_pad_input(self, event, _first_focus_target()):
		get_viewport().set_input_as_handled()
		return
	if _view != View.EDITOR or _is_deleting() or _is_completed_open() or _is_detail_open():
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
	if _is_completed_open():
		_cancel_completed()
		return
	if _is_deleting():
		_cancel_delete()
		return
	if _is_detail_open():
		_cancel_detail()
		return
	if _view == View.EDITOR:
		_enter_list(false)
		return
	close(-1)

func _on_back_pressed() -> void:
	_handle_back()

func _on_new_pressed() -> void:
	if not _open or _is_completed_open():
		return
	if GameRecords.list_records().size() >= GameRecords.get_max_records():
		_play_error()
		return
	_play_click()
	_enter_editor()

func _on_record_pressed(record_id: String) -> void:
	if not _open or _view != View.LIST or _is_deleting() or _is_completed_open() or _is_detail_open():
		return
	var proj: SaveUiProjection = SaveUiProjection.load_for(record_id)
	if proj == null:
		return
	_play_click()
	if proj.status == SaveUiProjection.STATUS_CLEARED:
		## 已通关的档：先问「COMPLETED / This save has already been cleared. / Start over?」，
		## 绝不静默开新局、绝不直接进沙盒（§5）。
		show_completed(record_id)
		return
	## 进行中 / 新档 / 失败：都先进详情确认浮层（§4），主按钮按状态换文案。
	show_detail(record_id)

## 外部（Continue）也能直接把已通关确认条顶出来。
func show_completed(record_id: String) -> void:
	if record_id.is_empty():
		return
	var proj: SaveUiProjection = SaveUiProjection.load_for(record_id)
	if proj == null:
		return
	if not _open:
		open()
	_pending_completed_id = record_id
	_completed_name.text = proj.display_name
	_show_completed_modal()

func _is_completed_open() -> bool:
	return not _pending_completed_id.is_empty()

## 详情 / 确认浮层（§4）。任何非 CLEARED 的存档都先走这里，绝不一点击就开新局。
func show_detail(record_id: String) -> void:
	if record_id.is_empty():
		return
	var proj: SaveUiProjection = SaveUiProjection.load_for(record_id)
	if proj == null:
		return
	if not _open:
		open()
	_fill_detail(record_id)
	_detail_id = record_id
	_detail_dimmer.visible = true
	_detail_center.visible = true
	UiAnim.kill_tween(_detail_tween)
	_detail_tween = UiAnim.enter_modal(self, _detail_dimmer, _detail_panel)

func _is_detail_open() -> bool:
	return not _detail_id.is_empty()

func _fill_detail(record_id: String) -> void:
	var proj: SaveUiProjection = SaveUiProjection.load_for(record_id)
	if proj == null:
		return
	_detail_title.text = proj.display_name
	_detail_status.text = "%s  ·  %s" % [proj.status_label_text(), proj.identity_line()]
	_clear_detail_rows()
	var rows: Array[Dictionary] = proj.detail_rows()
	for i: int in rows.size():
		var entry: Dictionary = rows[i]
		var box: VBoxContainer = _detail_left if i % 2 == 0 else _detail_right
		box.add_child(_make_detail_row(str(entry.get("label", "")), str(entry.get("value", ""))))
	_detail_yes.text = _primary_label(proj)
	## 窄视口把详情面板收一收，别在 540 宽下横向溢出。
	_detail_panel.custom_minimum_size.x = clampf(UiFit.visible_size(self).x - CONTENT_MARGIN * 2.0, 360.0, 760.0)

func _make_detail_row(label: String, value: String) -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var key: Label = Label.new()
	key.theme_type_variation = &"SectionLabel"
	key.text = label
	key.custom_minimum_size.x = 150.0
	key.add_theme_color_override("font_color", Color(0.62, 0.58, 0.52, 1))
	key.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var val: Label = Label.new()
	val.theme_type_variation = &"Caption"
	val.text = value
	val.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	val.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	val.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(key)
	row.add_child(val)
	return row

func _clear_detail_rows() -> void:
	for box: VBoxContainer in [_detail_left, _detail_right]:
		for child: Node in box.get_children():
			box.remove_child(child)
			child.queue_free()

func _primary_label(proj: SaveUiProjection) -> String:
	match proj.status:
		SaveUiProjection.STATUS_IN_PROGRESS:
			return "Continue Run"
		SaveUiProjection.STATUS_FAILED:
			return "Retry Run"
		_:
			return "Start New Run"

func _on_detail_yes_pressed() -> void:
	_play_click()
	var record_id: String = _detail_id
	_detail_id = ""
	_hide_detail_modal()
	if record_id.is_empty():
		return
	var proj: SaveUiProjection = SaveUiProjection.load_for(record_id)
	## 档刚被删掉：什么都不发，别拿一个不存在的 slot 去开新局。
	if proj == null:
		return
	if proj.status == SaveUiProjection.STATUS_IN_PROGRESS:
		resume_record.emit(record_id)
		return
	## NEW / FAILED：该档还没有 active_run，用它**新开一局**（历史留着）。
	selected_record.emit(record_id)

func _on_detail_delete_pressed() -> void:
	if _is_deleting():
		return
	_play_click()
	_pending_delete_id = _detail_id
	if _pending_delete_id.is_empty():
		return
	_fill_delete_body(_pending_delete_id)
	_show_delete_modal()

func _on_detail_no_pressed() -> void:
	_handle_back()

func _cancel_detail() -> void:
	_detail_id = ""
	_hide_detail_modal()
	_enter_list(false)

func _on_completed_yes_pressed() -> void:
	_play_click()
	var record_id: String = _pending_completed_id
	_pending_completed_id = ""
	_hide_completed_modal()
	if record_id.is_empty():
		return
	## START OVER = 用该档**新开一局**（START_NEW_RUN）。
	## 旧 history 挂在 slot.history 上，mark_cleared / mark_failed 只追加不覆盖，不会丢。
	selected_record.emit(record_id)

func _on_completed_no_pressed() -> void:
	_handle_back()

func _cancel_completed() -> void:
	_pending_completed_id = ""
	_hide_completed_modal()
	_enter_list(true)

## 行尾的 ×：直接进删除二次确认（§9）。
func _on_delete_pressed(record_id: String) -> void:
	if not _open or _view != View.LIST or _is_completed_open():
		return
	_play_click()
	_pending_delete_id = record_id
	_fill_delete_body(record_id)
	_show_delete_modal()

## §9：确认条必须写出 Name / Progress / History，并且明说 This cannot be undone.。
func _fill_delete_body(record_id: String) -> void:
	var proj: SaveUiProjection = SaveUiProjection.load_for(record_id)
	if proj == null:
		_delete_body.text = ""
		return
	_delete_body.text = "Name: %s\nProgress: %s\nHistory: %s" % [
		proj.display_name, proj.delete_progress_line(), proj.delete_history_line()
	]

func _on_delete_yes_pressed() -> void:
	_play_click()
	var record_id: String = _pending_delete_id
	_pending_delete_id = ""
	## 从详情浮层里点的删除：这一档没了，详情一起收。
	_detail_id = ""
	if record_id.is_empty():
		_enter_list(true)
		return
	GameRecords.delete_record(record_id)
	_enter_list(true)

func _on_delete_no_pressed() -> void:
	_handle_back()

func _cancel_delete() -> void:
	_pending_delete_id = ""
	_hide_delete_modal()
	if _is_detail_open():
		return
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
	if _list_drag != null:
		_list_drag.reset()
	if refresh:
		_refresh_list()
	_play_card_enter(_collect_list_cards())

func _enter_editor() -> void:
	_view = View.EDITOR
	_pending_delete_id = ""
	_pending_completed_id = ""
	_detail_id = ""
	_list_root.visible = false
	_editor_root.visible = true
	## 右上角同一个槽位：建档态换成 Create，列表态是 + New Record。
	_new_button.visible = false
	_confirm_button.visible = true
	_subtitle.text = SUBTITLE_EDITOR
	_hide_delete_modal()
	_hide_completed_modal()
	_hide_detail_modal()
	sync_content_width_for(_logical_viewport_width())
	_reset_editor()
	if _editor_drag != null:
		_editor_drag.reset()
	_play_card_enter([_boar_button, _chicken_button, _yard_button, _pit_button, _keep_button, _confirm_button, _back_button])

func _show_list_nodes() -> void:
	_view = View.LIST
	_list_root.visible = true
	_editor_root.visible = false
	_new_button.visible = true
	_confirm_button.visible = false
	_subtitle.text = SUBTITLE_LIST
	_hide_delete_modal()
	_hide_completed_modal()
	_hide_detail_modal()

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
	_delete_body.text = ""

func _is_deleting() -> bool:
	return not _pending_delete_id.is_empty()

func _hide_detail_modal() -> void:
	_detail_id = ""
	if not _detail_center.visible:
		return
	UiAnim.kill_tween(_detail_tween)
	_detail_tween = UiAnim.exit_modal(self, _detail_dimmer, _detail_panel)
	_detail_tween.finished.connect(_finish_detail_modal_close)

func _finish_detail_modal_close() -> void:
	if _is_detail_open():
		return
	_detail_dimmer.visible = false
	_detail_center.visible = false

func _reset_detail_modal() -> void:
	UiAnim.kill_tween(_detail_tween)
	_detail_id = ""
	_detail_dimmer.visible = false
	_detail_center.visible = false
	_detail_dimmer.modulate.a = 1.0
	_detail_panel.modulate.a = 1.0
	_detail_panel.scale = Vector2.ONE
	_clear_detail_rows()

func _show_completed_modal() -> void:
	_completed_dimmer.visible = true
	_completed_center.visible = true
	UiAnim.kill_tween(_completed_tween)
	_completed_tween = UiAnim.enter_modal(self, _completed_dimmer, _completed_panel)

func _hide_completed_modal() -> void:
	if not _completed_center.visible:
		return
	UiAnim.kill_tween(_completed_tween)
	_completed_tween = UiAnim.exit_modal(self, _completed_dimmer, _completed_panel)
	_completed_tween.finished.connect(_finish_completed_modal_close)

func _finish_completed_modal_close() -> void:
	if _is_completed_open():
		return
	_completed_dimmer.visible = false
	_completed_center.visible = false

func _reset_completed_modal() -> void:
	UiAnim.kill_tween(_completed_tween)
	_completed_dimmer.visible = false
	_completed_center.visible = false
	_completed_dimmer.modulate.a = 1.0
	_completed_panel.modulate.a = 1.0
	_completed_panel.scale = Vector2.ONE
	_completed_name.text = ""

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
	## §15：列表只从 SaveStore + SaveSlot 取数，一排 = 一个存档。
	## 这里不读 records.json、不用 history 长度猜状态。
	_clear_record_rows()
	var width: float = _row_width()
	for proj: SaveUiProjection in SaveUiProjection.load_all():
		_rows.add_child(_make_save_row(proj, width))
	_update_new_button()
	_fit_scroll()
	_scroll.scroll_vertical = 0
	_mark_selected_row()

func _clear_record_rows() -> void:
	var stale: Array[Node] = []
	for child: Node in _rows.get_children():
		stale.append(child)
	for child: Node in stale:
		_rows.remove_child(child)
		child.queue_free()

func _update_new_button() -> void:
	_new_button.disabled = false
	_new_button.focus_mode = Control.FOCUS_ALL

func _fit_scroll() -> void:
	_scroll.scroll_vertical = 0

## 当前状态的首选焦点：只在玩家第一次按键盘 / 手柄导航键时用（界面打开时不自动聚焦）。
## 删除确认的「取消」必须排在「删除」前面（§9：DELETE 的默认焦点是 CANCEL）；
## 已通关确认条的「Cancel」同理排在「Start New Run」前面。
func _first_focus_target() -> Array:
	if _is_deleting():
		return [_delete_cancel, _delete_confirm]
	if _is_completed_open():
		return [_completed_no, _completed_yes]
	if _is_detail_open():
		return [_detail_yes, _detail_delete, _detail_no]
	if _view == View.EDITOR:
		return _editor_focus_target()
	return _list_focus_target()

func _editor_focus_target() -> Array:
	for button: Button in [_boar_button, _chicken_button, _yard_button, _pit_button, _keep_button, _confirm_button, _back_button]:
		if UiFocus.is_focusable(button):
			return [button]
	return [_back_button]

## LIST 状态的首选焦点：第一排存档 → New → Back。
func _list_focus_target() -> Array:
	_fit_rows()
	for child: Node in _rows.get_children():
		var button: Button = child as Button
		if button != null and UiFocus.is_focusable(button):
			return [button]
	if UiFocus.is_focusable(_new_button):
		return [_new_button]
	return [_back_button]

func _collect_list_cards() -> Array:
	var cards: Array = []
	for child: Node in _rows.get_children():
		var button: Button = child as Button
		if button != null:
			cards.append(button)
	cards.append(_new_button)
	cards.append(_back_button)
	return cards

func _play_card_enter(cards: Array) -> void:
	UiAnim.kill_tween(_anim_tween)
	_anim_tween = UiAnim.enter_cards(self, cards)

func _make_save_row(proj: SaveUiProjection, width: float) -> Button:
	var button: Button = SaveRow.make(proj, width)
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	button.custom_minimum_size.x = width
	button.pressed.connect(_on_record_pressed.bind(proj.slot_id))
	## 行尾给 × 让出一条槽，别压到右边的更新时间。
	var content: Control = button.get_node_or_null("Content") as Control
	if content != null:
		content.offset_right = -(DELETE_SIZE.x + DELETE_MARGIN + 4.0)
	var delete_button: Button = _make_delete_button(proj.slot_id)
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
	_wire_hover(button)
	UiAnim.wire_row_feedback(self, button, UiType.INK)
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

## Home / Play 的 Continue 看哪一档，列表就把哪一排标成选中态（§12：选中态必须明显）。
func _mark_selected_row() -> void:
	var cont: SaveUiProjection = SaveUiProjection.load_continue()
	var target: String = cont.slot_id if cont != null else ""
	for child: Node in _rows.get_children():
		var button: Button = child as Button
		if button == null:
			continue
		SaveRow.set_selected(button, not target.is_empty() and SaveRow.slot_id_of(button) == target)

## 存档行宽度：跟版心一起收缩，最宽 1200；窄视口（1140 / 960 / 540）按同一套公式收。
## 再用实际 Content 宽度兜一层，避免行比容器还宽被裁掉。
func _row_width() -> float:
	var vw: float = _synced_width if _synced_width > 1.0 else _logical_viewport_width()
	var want: float = UiFit.content_width_for(vw, CONTENT_MARGIN, CONTENT_MAX_WIDTH)
	var actual: float = _content.size.x if _content != null else 0.0
	if actual > 1.0:
		return minf(want, actual)
	return want

func _fill_editor_character(button: Button, character_id: String) -> void:
	var def: CharacterDef = CATALOG.get_by_id(StringName(character_id))
	var portrait: TextureRect = button.get_node("Card/Portrait") as TextureRect
	var title: Label = button.get_node("Card/Text/Title") as Label
	var desc: Label = button.get_node("Card/Text/Desc") as Label
	if portrait != null:
		portrait.texture = RecordCard.resolve_body_texture(character_id)
	if title != null:
		title.text = def.display_name if def != null else character_id
	if desc != null:
		desc.text = def.description if def != null else ""

func _on_host_resized() -> void:
	if not _open:
		return
	sync_content_width_for(_logical_viewport_width())

## 参数化版本：测试要能强制 1920 / 1140 / 960 / 540（手机 200%）这几档。
func sync_content_width_for(viewport_width: float) -> void:
	var vw: float = viewport_width if viewport_width > 1.0 else UiFit.DESIGN.x
	_synced_width = vw
	if _column != null:
		_column.offset_left = CONTENT_MARGIN
		_column.offset_right = -CONTENT_MARGIN
	if _editor_column != null:
		_editor_column.custom_minimum_size.x = UiFit.content_width_for(vw, CONTENT_MARGIN, CONTENT_MAX_WIDTH)
	_fit_rows()

func _logical_viewport_width() -> float:
	return get_viewport_rect().size.x

## Content 是 Page 里唯一随窗口变宽的那一段；它的 resized 带新宽度，比 host.resized 早一步可用。
func _on_content_resized() -> void:
	if not _open:
		return
	_fit_rows()

## 每排按当前版心重新定档（宽度分档决定露出几行进度 / 要不要时间列）。
func _fit_rows() -> void:
	if _view != View.LIST:
		return
	var width: float = _row_width()
	for child: Node in _rows.get_children():
		var button: Button = child as Button
		if button == null:
			continue
		button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		SaveRow.apply_width(button, width)
		button.custom_minimum_size.x = width

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
