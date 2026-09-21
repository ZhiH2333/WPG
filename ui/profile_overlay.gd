extends Control
class_name ProfileOverlay

## 主菜单 Profile 叠层：左侧只读 GameProgress，右侧只读档位概览。不是战斗 CanvasLayer，不暂停场景树。
signal view_ranking_pressed

var _open: bool = false
var _anim_tween: Tween

@onready var _dimmer: ColorRect = $Dimmer
@onready var _panel: PanelContainer = $Center/Panel
@onready var _best_loop_label: Label = $Center/Panel/Column/Content/Center/Columns/Stats/BestLoop
@onready var _last_loop_label: Label = $Center/Panel/Column/Content/Center/Columns/Stats/LastLoop
@onready var _last_kills_label: Label = $Center/Panel/Column/Content/Center/Columns/Stats/LastKills
@onready var _last_gold_label: Label = $Center/Panel/Column/Content/Center/Columns/Stats/LastGold
@onready var _runs_label: Label = $Center/Panel/Column/Content/Center/Columns/Stats/Runs
@onready var _owned_label: Label = $Center/Panel/Column/Content/Center/Columns/Stats/OwnedHint
@onready var _records_rows: VBoxContainer = $Center/Panel/Column/Content/Center/Columns/RecordsColumn/Rows
@onready var _rank_button: Button = $Center/Panel/Column/Header/RankButton
@onready var _back_button: Button = $Center/Panel/Column/Back

func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rank_button.pressed.connect(_emit_view_ranking)
	_back_button.pressed.connect(close)
	UiFit.connect_refit(self, _on_host_resized)

func is_open() -> bool:
	return _open

func open() -> void:
	_open = true
	visible = true
	_fit_panel()
	_refresh_stats()
	_refresh_records()
	modulate.a = 1.0
	mouse_filter = Control.MOUSE_FILTER_STOP
	UiAnim.kill_tween(_anim_tween)
	_anim_tween = UiAnim.enter_overlay(self, _dimmer, _panel, [_back_button])
	_back_button.grab_focus()

func close() -> void:
	if not _open:
		return
	_open = false
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

func _unhandled_input(event: InputEvent) -> void:
	if not _open:
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()

func _emit_view_ranking() -> void:
	view_ranking_pressed.emit()

func _refresh_stats() -> void:
	_best_loop_label.text = "best loop  %d" % GameProgress.get_best_loop()
	_last_loop_label.text = "last loop  %d" % GameProgress.get_last_loop()
	_last_kills_label.text = "last kills  %d" % GameProgress.get_last_kills()
	_last_gold_label.text = "last gold  %d" % GameProgress.get_last_gold()
	_runs_label.text = "runs  %d" % GameProgress.get_runs_played()
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

func _on_host_resized() -> void:
	if not _open:
		return
	_fit_panel()

func _fit_panel() -> void:
	UiFit.apply_floating_panel(self, _panel)
