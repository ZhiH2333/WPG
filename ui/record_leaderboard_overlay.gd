extends Control
class_name RecordLeaderboardOverlay

## 主菜单档位排行叠层：只读 GameRecords，按 best_score 降序可视化。不是跨设备排行，不写档。
var _open: bool = false
var _anim_tween: Tween
var _sfx_gate: Dictionary = {}

@onready var _dimmer: ColorRect = $Dimmer
@onready var _sheet: Control = $Sheet
@onready var _rows: VBoxContainer = $Sheet/Column/Content/Rows
@onready var _back_button: Button = $Sheet/Column/Header/Back
@onready var _hover_sfx: AudioStreamPlayer = $HoverSfx
@onready var _click_sfx: AudioStreamPlayer = $ClickSfx
@onready var _back_sfx: AudioStreamPlayer = $BackSfx

func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hover_sfx.stream = GameAudio.load_wav("res://audio/ui_hover.wav")
	_click_sfx.stream = GameAudio.load_wav("res://audio/ui_click.wav")
	_back_sfx.stream = GameAudio.load_wav("res://audio/ui_back.wav")
	_back_button.pressed.connect(_on_back_pressed)
	_wire_hover(_back_button)
	UiAnim.wire_row_feedback(self, _back_button, UiType.INK)
	UiFit.connect_refit(self, _on_host_resized)

func is_open() -> bool:
	return _open

func open() -> void:
	_open = true
	visible = true
	GameRecords.load_from_disk()
	_rebuild_rows()
	modulate.a = 1.0
	mouse_filter = Control.MOUSE_FILTER_STOP
	UiAnim.kill_tween(_anim_tween)
	_anim_tween = UiAnim.enter_page(self, _dimmer, _sheet)
	_back_button.grab_focus()

func close() -> void:
	if not _open:
		return
	_open = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiAnim.kill_tween(_anim_tween)
	_anim_tween = UiAnim.exit_page(self, _dimmer, _sheet)
	_anim_tween.finished.connect(_finish_close)

func return_to_profile() -> void:
	var profile: ProfileOverlay = get_parent().get_node_or_null("ProfileOverlay") as ProfileOverlay
	if profile == null:
		return
	profile.open()
	profile.focus_rank()

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
	close()
	return_to_profile()

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

func _on_host_resized() -> void:
	if not _open:
		return
	_rows.notification(Container.NOTIFICATION_SORT_CHILDREN)

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
