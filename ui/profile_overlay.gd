extends Control
class_name ProfileOverlay

## 主菜单 Profile 页：身份可写，统计只读 GameProgress，档位只读 GameRecords。
signal view_ranking_pressed

const SPECIES_BOAR := "boar"
const SPECIES_CHICKEN := "chicken"
const COLOR_SELECTED := Color(0.96, 0.93, 0.88, 1)
const COLOR_IDLE := Color(0.62, 0.58, 0.52, 1)

var _open: bool = false
var _editing_name: bool = false
var _anim_tween: Tween
var _sfx_gate: Dictionary = {}
var _character_group: ButtonGroup = ButtonGroup.new()

@onready var _dimmer: ColorRect = $Dimmer
@onready var _panel: Control = $Sheet
@onready var _avatar_button: Button = $Sheet/Column/Avatar
@onready var _avatar_portrait: TextureRect = $Sheet/Column/Avatar/Portrait
@onready var _name_button: Button = $Sheet/Column/Name
@onready var _name_edit: LineEdit = $Sheet/Column/NameEdit
@onready var _best_loop_label: Label = $Sheet/Column/Stats/BestLoop
@onready var _last_loop_label: Label = $Sheet/Column/Stats/LastLoop
@onready var _last_kills_label: Label = $Sheet/Column/Facts/LastKills
@onready var _last_gold_label: Label = $Sheet/Column/Facts/LastGold
@onready var _runs_label: Label = $Sheet/Column/Stats/Runs
@onready var _owned_label: Label = $Sheet/Column/Facts/OwnedHint
@onready var _records_rows: VBoxContainer = $Sheet/Column/Rows
@onready var _rank_button: Button = $Sheet/Column/Header/RankButton
@onready var _boar_button: Button = $Sheet/Column/Characters/Boar
@onready var _chicken_button: Button = $Sheet/Column/Characters/Chicken
@onready var _back_button: Button = $Sheet/Column/Back
@onready var _hover_sfx: AudioStreamPlayer = $HoverSfx
@onready var _click_sfx: AudioStreamPlayer = $ClickSfx
@onready var _back_sfx: AudioStreamPlayer = $BackSfx

func _ready() -> void:
	UiStyle.present(self, false)
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hover_sfx.stream = GameAudio.load_wav("res://audio/ui_hover.wav")
	_click_sfx.stream = GameAudio.load_wav("res://audio/ui_click.wav")
	_back_sfx.stream = GameAudio.load_wav("res://audio/ui_back.wav")
	_boar_button.button_group = _character_group
	_chicken_button.button_group = _character_group
	_rank_button.pressed.connect(_emit_view_ranking)
	_back_button.pressed.connect(_on_back_pressed)
	_name_button.pressed.connect(_begin_name_edit)
	_name_edit.text_submitted.connect(_on_name_submitted)
	_name_edit.focus_exited.connect(_on_name_edit_focus_exited)
	_avatar_button.pressed.connect(_on_avatar_pressed)
	_boar_button.pressed.connect(_on_character_pressed.bind(SPECIES_BOAR))
	_chicken_button.pressed.connect(_on_character_pressed.bind(SPECIES_CHICKEN))
	_wire_hover(_name_button)
	_wire_hover(_avatar_button)
	_wire_hover(_rank_button)
	_wire_hover(_back_button)
	_wire_hover(_boar_button)
	_wire_hover(_chicken_button)

func focus_rank() -> void:
	_rank_button.grab_focus()

func is_open() -> bool:
	return _open

func open() -> void:
	_open = true
	visible = true
	_editing_name = false
	_name_edit.visible = false
	_name_button.visible = true
	_refresh_identity()
	_refresh_stats()
	var record_row: Control = _refresh_records()
	_wire_focus(record_row)
	modulate.a = 1.0
	mouse_filter = Control.MOUSE_FILTER_STOP
	UiAnim.kill_tween(_anim_tween)
	_anim_tween = UiAnim.enter_page(self, _dimmer, _panel)
	_name_button.grab_focus()

func close() -> void:
	if not _open:
		return
	if _editing_name:
		_finish_name_edit(true)
	_open = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiAnim.kill_tween(_anim_tween)
	_anim_tween = UiAnim.exit_page(self, _dimmer, _panel)
	_anim_tween.finished.connect(_finish_close)
	var menu: MainMenu = get_parent() as MainMenu
	if menu != null:
		menu.on_profile_closed()

func _finish_close() -> void:
	if _open:
		return
	visible = false
	modulate.a = 1.0

func _input(event: InputEvent) -> void:
	if not _open or not _editing_name:
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_finish_name_edit(false)
		_name_button.grab_focus()

func _unhandled_input(event: InputEvent) -> void:
	if not _open or _editing_name:
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_on_back_pressed()

func _on_back_pressed() -> void:
	if not _open:
		return
	if _editing_name:
		_finish_name_edit(false)
		_name_button.grab_focus()
		return
	_play_back()
	close()

func _emit_view_ranking() -> void:
	_play_click()
	view_ranking_pressed.emit()

func _begin_name_edit() -> void:
	if not _open or _editing_name:
		return
	_play_click()
	_editing_name = true
	_name_edit.text = PlayerProfile.get_display_name()
	_name_edit.visible = true
	_name_button.visible = false
	_name_edit.grab_focus()
	_name_edit.caret_column = _name_edit.text.length()

func _on_name_submitted(_text: String) -> void:
	if not _editing_name:
		return
	_finish_name_edit(true)
	if _open:
		_name_button.grab_focus()

func _on_name_edit_focus_exited() -> void:
	if not _editing_name:
		return
	_finish_name_edit(true)

func _finish_name_edit(commit: bool) -> void:
	if not _editing_name:
		return
	_editing_name = false
	if commit and PlayerProfile.set_display_name(_name_edit.text):
		_notify_identity()
	_name_edit.visible = false
	_name_button.visible = true
	_name_button.text = PlayerProfile.get_display_name()

func _on_avatar_pressed() -> void:
	_play_click()
	var next_id: String = SPECIES_CHICKEN if PlayerProfile.get_avatar_id() == SPECIES_BOAR else SPECIES_BOAR
	if not PlayerProfile.set_avatar_id(next_id):
		return
	_refresh_identity()
	_notify_identity()

func _on_character_pressed(character_id: String) -> void:
	_play_click()
	PlayerProfile.set_preferred_character_id(character_id)
	_refresh_character_marks()

func _refresh_identity() -> void:
	_name_button.text = PlayerProfile.get_display_name()
	_avatar_portrait.texture = RecordCard.resolve_body_texture(PlayerProfile.get_avatar_id())
	_refresh_character_marks()

func _refresh_character_marks() -> void:
	var character_id: String = PlayerProfile.get_preferred_character_id()
	_mark_character(_boar_button, character_id == SPECIES_BOAR)
	_mark_character(_chicken_button, character_id == SPECIES_CHICKEN)

func _mark_character(button: Button, selected: bool) -> void:
	button.set_pressed_no_signal(selected)
	var color: Color = COLOR_SELECTED if selected else COLOR_IDLE
	button.add_theme_color_override("font_color", color)
	button.add_theme_color_override("font_pressed_color", color)
	button.add_theme_color_override("font_hover_color", color)
	button.add_theme_color_override("font_focus_color", color)

func _refresh_stats() -> void:
	_best_loop_label.text = "BEST LOOP  %d" % GameProgress.get_best_loop()
	_last_loop_label.text = "LAST LOOP  %d" % GameProgress.get_last_loop()
	_last_kills_label.text = "Last kills  %d" % GameProgress.get_last_kills()
	_last_gold_label.text = "Last gold  %d" % GameProgress.get_last_gold()
	_runs_label.text = "RUNS  %d" % GameProgress.get_runs_played()
	var owned: String = GameProgress.get_last_owned()
	if owned.is_empty():
		owned = "-"
	_owned_label.text = "last owned  %s" % owned

func _refresh_records() -> Control:
	GameRecords.load_from_disk()
	_clear_record_rows()
	var records: Array[GameRecord] = GameRecords.list_records()
	records.sort_custom(_is_best_score_higher)
	if records.is_empty():
		_records_rows.add_child(_make_empty_hint())
		return null
	var first_row: Control = null
	for record: GameRecord in records:
		var row: Control = RecordCard.make_overview_row(record)
		_records_rows.add_child(row)
		if first_row == null:
			row.focus_mode = Control.FOCUS_ALL
			row.mouse_filter = Control.MOUSE_FILTER_STOP
			first_row = row
	return first_row

func _clear_record_rows() -> void:
	var stale: Array[Node] = []
	for child: Node in _records_rows.get_children():
		stale.append(child)
	for child: Node in stale:
		_records_rows.remove_child(child)
		child.queue_free()

func _make_empty_hint() -> Label:
	var hint: Label = Label.new()
	hint.theme_type_variation = &"Caption"
	hint.text = "NO RECORDS YET"
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return hint

func _is_best_score_higher(left: GameRecord, right: GameRecord) -> bool:
	return left.best_score > right.best_score

func _wire_focus(record_row: Control) -> void:
	var chain: Array[Control] = [_name_button, _avatar_button, _boar_button, _chicken_button, _rank_button]
	if record_row != null:
		chain.append(record_row)
	chain.append(_back_button)
	for index: int in chain.size():
		var current: Control = chain[index]
		var previous: Control = chain[(index + chain.size() - 1) % chain.size()]
		var next: Control = chain[(index + 1) % chain.size()]
		current.focus_neighbor_top = previous.get_path()
		current.focus_neighbor_bottom = next.get_path()
		current.focus_neighbor_left = current.get_path()
		current.focus_neighbor_right = current.get_path()
	_boar_button.focus_neighbor_right = _chicken_button.get_path()
	_chicken_button.focus_neighbor_left = _boar_button.get_path()

func _notify_identity() -> void:
	var menu: MainMenu = get_parent() as MainMenu
	if menu != null:
		menu.refresh_identity()

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

func _play_stream(player: AudioStreamPlayer, key: StringName) -> void:
	if player == null or player.stream == null:
		return
	var frame: int = Engine.get_process_frames()
	if int(_sfx_gate.get(key, -1)) == frame:
		return
	_sfx_gate[key] = frame
	player.play()
