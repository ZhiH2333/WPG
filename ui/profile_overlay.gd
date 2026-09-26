extends Control
class_name ProfileOverlay

## 主菜单 Profile 叠层：左侧只读 GameProgress，右侧只读档位概览。不是战斗 CanvasLayer，不暂停场景树。
signal view_ranking_pressed

var _open: bool = false
var _anim_tween: Tween
var _sfx_gate: Dictionary = {}

@onready var _dimmer: ColorRect = $Dimmer
@onready var _panel: Control = $Sheet
@onready var _name_button: Button = $Sheet/Column/Name
@onready var _best_loop_value: Label = $Sheet/Column/Stats/BestLoopValue
@onready var _last_loop_value: Label = $Sheet/Column/Stats/LastLoopValue
@onready var _last_kills_label: Label = $Sheet/Column/Facts/LastKills
@onready var _last_gold_label: Label = $Sheet/Column/Facts/LastGold
@onready var _runs_value: Label = $Sheet/Column/Stats/RunsValue
@onready var _owned_label: Label = $Sheet/Column/Facts/OwnedHint
@onready var _records_rows: VBoxContainer = $Sheet/Column/Rows
@onready var _ranking_button: Button = $Sheet/Column/Header/Ranking
@onready var _back_button: Button = $Sheet/Column/Back
@onready var _hover_sfx: AudioStreamPlayer = $HoverSfx
@onready var _click_sfx: AudioStreamPlayer = $ClickSfx
@onready var _back_sfx: AudioStreamPlayer = $BackSfx

func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hover_sfx.stream = GameAudio.load_wav("res://audio/ui_hover.wav")
	_click_sfx.stream = GameAudio.load_wav("res://audio/ui_click.wav")
	_back_sfx.stream = GameAudio.load_wav("res://audio/ui_back.wav")
	_ranking_button.pressed.connect(_emit_view_ranking)
	_back_button.pressed.connect(_on_back_pressed)
	for row: Button in [_name_button, _ranking_button, $Sheet/Column/Characters/Boar, $Sheet/Column/Characters/Chicken, _back_button]:
		_wire_hover(row)
		UiAnim.wire_row_feedback(self, row, UiType.INK)

func focus_rank() -> void:
	_ranking_button.grab_focus()

func is_open() -> bool:
	return _open

func open(direction: int = 0) -> void:
	_open = true
	visible = true
	_refresh_stats()
	_refresh_records()
	modulate.a = 1.0
	mouse_filter = Control.MOUSE_FILTER_STOP
	UiAnim.kill_tween(_anim_tween)
	_anim_tween = UiAnim.enter_page(self, _dimmer, _panel, false, direction)
	_name_button.grab_focus()

func close(direction: int = 0) -> void:
	if not _open:
		return
	_open = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiAnim.kill_tween(_anim_tween)
	_anim_tween = UiAnim.exit_page(self, _dimmer, _panel, false, direction)
	_anim_tween.finished.connect(_finish_close)
	var menu: MainMenu = get_parent() as MainMenu
	if menu != null:
		menu.on_profile_closed()

func _finish_close() -> void:
	if _open:
		return
	visible = false
	modulate.a = 1.0

func _unhandled_input(event: InputEvent) -> void:
	if not _open:
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_on_back_pressed()

func _on_back_pressed() -> void:
	if not _open:
		return
	_play_back()
	close(-1)

func _emit_view_ranking() -> void:
	_play_click()
	view_ranking_pressed.emit()

func _refresh_stats() -> void:
	_best_loop_value.text = "%d" % GameProgress.get_best_loop()
	_last_loop_value.text = "%d" % GameProgress.get_last_loop()
	_last_kills_label.text = "Last kills  %d" % GameProgress.get_last_kills()
	_last_gold_label.text = "Last gold  %d" % GameProgress.get_last_gold()
	_runs_value.text = "%d" % GameProgress.get_runs_played()
	var owned: String = GameProgress.get_last_owned()
	if owned.is_empty():
		owned = "-"
	_owned_label.text = "last owned  %s" % owned

func _refresh_records() -> void:
	GameRecords.load_from_disk()
	_clear_record_rows()
	var records: Array[GameRecord] = GameRecords.list_records()
	records.sort_custom(_is_best_score_higher)
	if records.is_empty():
		_records_rows.add_child(_make_empty_hint())
		return
	for record: GameRecord in records:
		_records_rows.add_child(RecordCard.make_overview_row(record))

func _clear_record_rows() -> void:
	var stale: Array[Node] = []
	for child: Node in _records_rows.get_children():
		stale.append(child)
	for child: Node in stale:
		_records_rows.remove_child(child)
		child.queue_free()

func _make_empty_hint() -> Label:
	var hint: Label = Label.new()
	hint.theme_type_variation = &"RunSummaryHint"
	hint.text = "NO RECORDS YET"
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return hint

func _is_best_score_higher(left: GameRecord, right: GameRecord) -> bool:
	return left.best_score > right.best_score

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
