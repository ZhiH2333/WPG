extends Control
class_name RecordLeaderboardOverlay

## 主菜单档位排行叠层：只读 GameRecords，按 best_score 降序可视化。不是跨设备排行，不写档。
var _open: bool = false
var _anim_tween: Tween

@onready var _dimmer: ColorRect = $Dimmer
@onready var _panel: PanelContainer = $Center/Panel
@onready var _rows: VBoxContainer = $Center/Panel/Column/Content/Scroll/Rows
@onready var _back_button: Button = $Center/Panel/Column/Header/Back

func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_back_button.pressed.connect(close)

func is_open() -> bool:
	return _open

func open() -> void:
	GameRecords.load_from_disk()
	_rebuild_rows()
	_open = true
	visible = true
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

func _rebuild_rows() -> void:
	_clear_rows()
	var records: Array[GameRecord] = GameRecords.list_records()
	records.sort_custom(_is_best_score_higher)
	if records.is_empty():
		_rows.add_child(_make_empty_hint())
		return
	var max_score: int = records[0].best_score
	if max_score <= 0:
		max_score = 1
	var rank: int = 1
	for record: GameRecord in records:
		_rows.add_child(RecordCard.make_rank_row(rank, record, max_score))
		rank += 1

func _clear_rows() -> void:
	var stale: Array[Node] = []
	for child: Node in _rows.get_children():
		stale.append(child)
	for child: Node in stale:
		_rows.remove_child(child)
		child.queue_free()

func _make_empty_hint() -> Label:
	var hint: Label = Label.new()
	hint.theme_type_variation = &"RunSummaryHint"
	hint.text = "NO RECORDS YET"
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return hint

func _is_best_score_higher(left: GameRecord, right: GameRecord) -> bool:
	return left.best_score > right.best_score
