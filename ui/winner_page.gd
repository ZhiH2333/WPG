extends CanvasLayer
class_name WinnerPage

## 死亡/通关结算叠层：叠在沙盒上，不卸场景、不暂停树。分数只调 GameRecords.compute_score。
signal retry_pressed
signal menu_pressed

const MIX_RATE: int = 22050
const WAV_HEADER_BYTES: int = 44
const HIST_ROWS: int = 10

var _open: bool = false
var _anim_tween: Tween
var _hist_labels: Array[Label] = []
var _this_score: int = 0
var _this_timestamp: int = 0

@onready var _root: Control = $Root
@onready var _dimmer: ColorRect = $Root/Dimmer
@onready var _panel: PanelContainer = $Root/Center/Panel
@onready var _title: Label = $Root/Center/Panel/Column/Body/Left/Title
@onready var _record_name: Label = $Root/Center/Panel/Column/Body/Left/RecordName
@onready var _score_label: Label = $Root/Center/Panel/Column/Body/Left/Score
@onready var _new_best: Label = $Root/Center/Panel/Column/Body/Left/NewBest
@onready var _loop_break: Label = $Root/Center/Panel/Column/Body/Left/LoopBreak
@onready var _kills_break: Label = $Root/Center/Panel/Column/Body/Left/KillsBreak
@onready var _gold_break: Label = $Root/Center/Panel/Column/Body/Left/GoldBreak
@onready var _time_break: Label = $Root/Center/Panel/Column/Body/Left/TimeBreak
@onready var _cleared_bonus: Label = $Root/Center/Panel/Column/Body/Left/ClearedBonus
@onready var _summary: Label = $Root/Center/Panel/Column/Body/Left/Summary
@onready var _hist_list: VBoxContainer = $Root/Center/Panel/Column/Body/Right/HistList
@onready var _hist_empty: Label = $Root/Center/Panel/Column/Body/Right/HistEmpty
@onready var _rank_label: Label = $Root/Center/Panel/Column/Body/Right/Rank
@onready var _retry_button: Button = $Root/Center/Panel/Column/Buttons/Retry
@onready var _menu_button: Button = $Root/Center/Panel/Column/Buttons/Menu
@onready var _hover_sfx: AudioStreamPlayer = $HoverSfx
@onready var _click_sfx: AudioStreamPlayer = $ClickSfx

func _ready() -> void:
	layer = 22
	visible = false
	_open = false
	_hover_sfx.stream = _load_wav("res://audio/ui_hover.wav")
	_click_sfx.stream = _load_wav("res://audio/ui_click.wav")
	_retry_button.pressed.connect(_on_retry_pressed)
	_menu_button.pressed.connect(_on_menu_pressed)
	_retry_button.mouse_entered.connect(_play_hover)
	_menu_button.mouse_entered.connect(_play_hover)
	_retry_button.focus_entered.connect(_play_hover)
	_menu_button.focus_entered.connect(_play_hover)
	_build_hist_rows()
	_set_interactive(false)

func is_open() -> bool:
	return _open

func present(record_id: String, session: RunSession, previous_best: int) -> void:
	if _open:
		return
	if session == null:
		return
	GameRecords.load_from_disk()
	var record: GameRecord = GameRecords.get_record(record_id)
	var outcome: String = "cleared" if session.is_cleared() else "dead"
	var loop_index: int = session.get_loop_index()
	var kills: int = session.get_kill_count()
	var gold: int = session.get_gold()
	var time_sec: float = session.get_elapsed_sec()
	_this_score = GameRecords.compute_score(loop_index, kills, gold, time_sec, outcome)
	_this_timestamp = int(Time.get_unix_time_from_system())
	_fill_left(record, session, outcome, loop_index, kills, gold, time_sec, previous_best)
	_fill_history(record)
	_open = true
	visible = true
	_root.modulate.a = 1.0
	_set_interactive(true)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	UiAnim.kill_tween(_anim_tween)
	_anim_tween = UiAnim.enter_overlay(self, _dimmer, _panel, [_retry_button, _menu_button])
	_retry_button.grab_focus()

func close() -> void:
	if not _open:
		return
	_open = false
	_set_interactive(false)
	UiAnim.kill_tween(_anim_tween)
	_anim_tween = UiAnim.exit_overlay(self, _root)
	_anim_tween.finished.connect(_finish_close)

func _finish_close() -> void:
	if _open:
		return
	visible = false
	_root.modulate.a = 1.0

func _unhandled_input(event: InputEvent) -> void:
	if not _open:
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_emit_menu()
		return
	if event is InputEventJoypadButton:
		var joy: InputEventJoypadButton = event as InputEventJoypadButton
		if joy.pressed and joy.button_index == JOY_BUTTON_START:
			get_viewport().set_input_as_handled()
			_emit_menu()

func _on_retry_pressed() -> void:
	_emit_retry()

func _on_menu_pressed() -> void:
	_emit_menu()

func _emit_retry() -> void:
	if not _open:
		return
	_play_click()
	retry_pressed.emit()

func _emit_menu() -> void:
	if not _open:
		return
	_play_click()
	menu_pressed.emit()

func _fill_left(record: GameRecord, session: RunSession, outcome: String, loop_index: int, kills: int, gold: int, time_sec: float, previous_best: int) -> void:
	if outcome == "cleared":
		_title.text = "CLEARED"
		_title.theme_type_variation = &"ClearedTitle"
	else:
		_title.text = "DEAD"
		_title.theme_type_variation = &"RunSummaryTitle"
	if record != null and not record.name.is_empty():
		_record_name.text = record.name
	else:
		_record_name.text = "-"
	_score_label.text = "score  %d" % _this_score
	_new_best.visible = _this_score > previous_best
	_loop_break.text = "loop  %d  ×1000  =  %d" % [loop_index, loop_index * 1000]
	_kills_break.text = "kills  %d  ×5  =  %d" % [kills, kills * 5]
	_gold_break.text = "gold  %d  ×2  =  %d" % [gold, gold * 2]
	_time_break.text = "time  %.1fs  →  %d" % [time_sec, floori(time_sec)]
	_cleared_bonus.visible = outcome == "cleared"
	_cleared_bonus.text = "cleared  +5000"
	_summary.text = "loop  %d    kills  %d    gold  %d    time  %.1fs    owned  %s" % [
		loop_index,
		kills,
		gold,
		time_sec,
		_format_owned(session),
	]

func _fill_history(record: GameRecord) -> void:
	if record == null or record.history.is_empty():
		_hist_empty.visible = true
		_hist_empty.text = "-"
		_rank_label.text = "rank  -"
		for row: Label in _hist_labels:
			row.visible = false
		return
	_hist_empty.visible = false
	var highlight: int = _find_highlight_index(record.history)
	var shown: int = mini(record.history.size(), HIST_ROWS)
	for i: int in HIST_ROWS:
		var row: Label = _hist_labels[i]
		if i >= shown:
			row.visible = false
			continue
		var entry: Dictionary = record.history[i]
		row.visible = true
		row.text = "#%d  %d   L%d  %s  %.1fs" % [
			i + 1,
			int(entry.get("score", 0)),
			int(entry.get("loop", 0)),
			_format_outcome(str(entry.get("outcome", "quit"))),
			float(entry.get("time_sec", 0.0)),
		]
		row.theme_type_variation = &"WinnerHistHi" if i == highlight else &"WinnerHist"
	if highlight < 0:
		_rank_label.text = "rank  -"
	else:
		_rank_label.text = "rank  %d / %d" % [highlight + 1, record.history.size()]

func _find_highlight_index(history: Array[Dictionary]) -> int:
	for i: int in history.size():
		var entry: Dictionary = history[i]
		if int(entry.get("score", 0)) != _this_score:
			continue
		if absi(int(entry.get("timestamp", 0)) - _this_timestamp) <= 1:
			return i
	return -1

func _format_outcome(value: String) -> String:
	if value == "cleared":
		return "CLEARED"
	if value == "dead":
		return "DEAD"
	return "QUIT"

func _format_owned(session: RunSession) -> String:
	var ids: PackedStringArray = session.get_owned_upgrade_ids()
	if ids.is_empty():
		return "-"
	return ",".join(ids)

func _build_hist_rows() -> void:
	_hist_labels.clear()
	var i: int = 0
	while i < HIST_ROWS:
		var row: Label = Label.new()
		row.theme_type_variation = &"WinnerHist"
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.visible = false
		_hist_list.add_child(row)
		_hist_labels.append(row)
		i += 1

func _set_interactive(enabled: bool) -> void:
	if enabled:
		_root.mouse_filter = Control.MOUSE_FILTER_STOP
		_dimmer.mouse_filter = Control.MOUSE_FILTER_STOP
	else:
		_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_dimmer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_retry_button.disabled = not enabled
	_menu_button.disabled = not enabled

func _play_hover() -> void:
	if not _open or _hover_sfx.stream == null:
		return
	_hover_sfx.play()

func _play_click() -> void:
	if _click_sfx.stream == null:
		return
	_click_sfx.play()

func _load_wav(path: String) -> AudioStreamWAV:
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
	if bytes.size() <= WAV_HEADER_BYTES:
		return null
	var stream: AudioStreamWAV = AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = MIX_RATE
	stream.stereo = false
	stream.data = bytes.slice(WAV_HEADER_BYTES)
	return stream
