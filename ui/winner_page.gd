extends CanvasLayer
class_name WinnerPage

## 死亡/通关结算叠层：叠在沙盒上，不卸场景、不暂停树。分数只调 GameRecords.compute_score。
signal retry_pressed
signal menu_pressed

const HIST_ROWS: int = 10
const SCORE_STAGGER_SEC: float = 0.08
const SCORE_ROLL_SEC: float = 0.32
const SCORE_TOTAL_SEC: float = 0.40
const SCORE_FADE_SEC: float = 0.18

var _open: bool = false
var _anim_tween: Tween
var _score_tween: Tween
var _sfx_gate: Dictionary = {}
var _hist_labels: Array[Label] = []
var _this_score: int = 0
var _this_timestamp: int = 0
var _retry_allowed: bool = true
var _roll_done: bool = true
var _is_lan: bool = false
var _is_battle_result: bool = false
var _previous_best: int = 0
var _final_loop: int = 0
var _final_kills: int = 0
var _final_gold: int = 0
var _final_time_sec: float = 0.0
var _summary_text: String = ""

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
@onready var _back_sfx: AudioStreamPlayer = $BackSfx

func _ready() -> void:
	layer = 22
	visible = false
	_open = false
	_hover_sfx.stream = GameAudio.load_wav("res://audio/ui_hover.wav")
	_click_sfx.stream = GameAudio.load_wav("res://audio/ui_click.wav")
	_back_sfx.stream = GameAudio.load_wav("res://audio/ui_back.wav")
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

func set_retry_allowed(allowed: bool) -> void:
	_retry_allowed = allowed
	if _open:
		_retry_button.disabled = not allowed

func present(record_id: String, session: RunSession, previous_best: int, winner_seat: int = 0, local_seat: int = 1, battle: bool = false) -> void:
	if _open:
		return
	if session == null:
		return
	UiAnim.kill_tween(_score_tween)
	_roll_done = false
	_is_battle_result = battle
	var lan: bool = record_id.is_empty()
	var record: GameRecord = null
	if not lan:
		GameRecords.load_from_disk()
		record = GameRecords.get_record(record_id)
	var outcome: String = "cleared" if session.is_cleared() else "dead"
	var loop_index: int = session.get_loop_index()
	var kills: int = session.get_kill_count()
	var gold: int = session.get_gold()
	var time_sec: float = session.get_elapsed_sec()
	if battle:
		_this_score = 0
	else:
		_this_score = GameRecords.compute_score(loop_index, kills, gold, time_sec, outcome)
	_this_timestamp = int(Time.get_unix_time_from_system())
	_fill_left(record, session, outcome, loop_index, kills, gold, time_sec, previous_best, lan)
	if battle:
		_apply_battle_result(winner_seat, local_seat)
	if lan:
		_fill_history(null)
	else:
		_fill_history(record)
	_reset_score_visuals()
	_open = true
	visible = true
	_root.modulate.a = 1.0
	_set_interactive(true)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	UiAnim.kill_tween(_anim_tween)
	_anim_tween = UiAnim.enter_overlay(self, _dimmer, _panel, [_retry_button, _menu_button])
	_play_score_roll()
	_retry_button.grab_focus()

func close() -> void:
	if not _open:
		return
	_open = false
	_set_interactive(false)
	UiAnim.kill_tween(_score_tween)
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
	if not _open or not _retry_allowed:
		return
	_snap_score_roll()
	_play_click()
	retry_pressed.emit()

func _emit_menu() -> void:
	if not _open:
		return
	_snap_score_roll()
	_play_back()
	menu_pressed.emit()

func _fill_left(record: GameRecord, session: RunSession, outcome: String, loop_index: int, kills: int, gold: int, time_sec: float, previous_best: int, lan: bool = false) -> void:
	_is_lan = lan
	_previous_best = previous_best
	_final_loop = loop_index
	_final_kills = kills
	_final_gold = gold
	_final_time_sec = time_sec
	_loop_break.visible = true
	_kills_break.visible = true
	_gold_break.visible = true
	_time_break.visible = true
	if outcome == "cleared":
		_title.text = "CLEARED"
		_title.theme_type_variation = &"ClearedTitle"
	else:
		_title.text = "DEAD"
		_title.theme_type_variation = &"RunSummaryTitle"
	if lan:
		_record_name.text = "LAN"
	elif record != null and not record.name.is_empty():
		_record_name.text = record.name
	else:
		_record_name.text = "-"
	_cleared_bonus.visible = outcome == "cleared"
	_cleared_bonus.text = "cleared  +5000"
	_summary_text = "loop  %d    kills  %d    gold  %d    time  %.1fs    owned  %s" % [
		loop_index,
		kills,
		gold,
		time_sec,
		_format_owned(session),
	]
	_summary.text = _summary_text
	_write_break_texts(0, 0, 0, 0)
	_score_label.text = "score  0"
	_new_best.visible = false

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

func _apply_battle_result(winner_seat: int, local_seat: int) -> void:
	if winner_seat == 0:
		_title.text = "DRAW"
		_title.theme_type_variation = &"RunSummaryTitle"
	elif local_seat == winner_seat:
		_title.text = "KO"
		_title.theme_type_variation = &"ClearedTitle"
	else:
		_title.text = "KO"
		_title.theme_type_variation = &"RunSummaryTitle"
	_record_name.text = "BATTLE"
	_loop_break.visible = false
	_kills_break.visible = false
	_gold_break.visible = false
	_time_break.visible = false
	_cleared_bonus.visible = false
	_new_best.visible = false
	_score_label.text = "time  0.0s"

func _reset_score_visuals() -> void:
	_new_best.visible = false
	if _is_battle_result:
		_score_label.text = "time  0.0s"
	else:
		_score_label.text = "score  0"
	_write_break_texts(0, 0, 0, 0)
	for item: CanvasItem in _list_roll_fade_items():
		item.modulate.a = 0.0

func _play_score_roll() -> void:
	UiAnim.kill_tween(_score_tween)
	_roll_done = false
	_score_tween = create_tween().set_parallel(true)
	_score_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	if _is_battle_result:
		_score_tween.tween_method(_assign_battle_time, 0.0, _final_time_sec, SCORE_TOTAL_SEC).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
		_append_fade(_summary, 0)
		_append_history_fades(SCORE_TOTAL_SEC)
		_score_tween.finished.connect(_mark_roll_done)
		return
	var beat: int = 0
	_append_break_roll(beat, _assign_loop_points, float(_final_loop * 1000), _loop_break)
	beat += 1
	_append_break_roll(beat, _assign_kills_points, float(_final_kills * 5), _kills_break)
	beat += 1
	_append_break_roll(beat, _assign_gold_points, float(_final_gold * 2), _gold_break)
	beat += 1
	_append_break_roll(beat, _assign_time_points, float(floori(_final_time_sec)), _time_break)
	beat += 1
	if _cleared_bonus.visible:
		_append_fade(_cleared_bonus, beat)
		beat += 1
	var total_delay: float = SCORE_STAGGER_SEC * float(beat)
	_score_tween.tween_method(_assign_score_points, 0.0, float(_this_score), SCORE_TOTAL_SEC).set_delay(total_delay).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	_append_fade(_summary, beat)
	_score_tween.tween_callback(_reveal_new_best).set_delay(total_delay + SCORE_TOTAL_SEC)
	_append_history_fades(total_delay)
	_score_tween.finished.connect(_mark_roll_done)

func _append_break_roll(beat: int, assign: Callable, to_value: float, item: CanvasItem) -> void:
	var delay: float = SCORE_STAGGER_SEC * float(beat)
	_append_fade(item, beat)
	_score_tween.tween_method(assign, 0.0, to_value, SCORE_ROLL_SEC).set_delay(delay).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)

func _append_fade(item: CanvasItem, beat: int) -> void:
	_append_fade_at(item, SCORE_STAGGER_SEC * float(beat))

func _append_fade_at(item: CanvasItem, delay: float) -> void:
	if item == null or not item.visible:
		return
	_score_tween.tween_property(item, "modulate:a", 1.0, SCORE_FADE_SEC).set_delay(delay).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)

func _append_history_fades(start_delay: float) -> void:
	_append_fade_at(_rank_label, start_delay)
	if _hist_empty.visible:
		_append_fade_at(_hist_empty, start_delay)
		return
	var hist_index: int = 0
	for row: Label in _hist_labels:
		if not row.visible:
			continue
		_append_fade_at(row, start_delay + SCORE_STAGGER_SEC * float(hist_index))
		hist_index += 1

func _assign_loop_points(value: float) -> void:
	_loop_break.text = "loop  %d  ×1000  =  %d" % [_final_loop, roundi(value)]

func _assign_kills_points(value: float) -> void:
	_kills_break.text = "kills  %d  ×5  =  %d" % [_final_kills, roundi(value)]

func _assign_gold_points(value: float) -> void:
	_gold_break.text = "gold  %d  ×2  =  %d" % [_final_gold, roundi(value)]

func _assign_time_points(value: float) -> void:
	_time_break.text = "time  %.1fs  →  %d" % [_final_time_sec, roundi(value)]

func _assign_score_points(value: float) -> void:
	_score_label.text = "score  %d" % roundi(value)

func _assign_battle_time(value: float) -> void:
	_score_label.text = "time  %.1fs" % value

func _snap_score_roll() -> void:
	if _roll_done:
		return
	UiAnim.kill_tween(_score_tween)
	_write_final_score_texts()
	_reveal_new_best()
	_roll_done = true

func _write_final_score_texts() -> void:
	_write_break_texts(_final_loop * 1000, _final_kills * 5, _final_gold * 2, floori(_final_time_sec))
	if _is_battle_result:
		_score_label.text = "time  %.1fs" % _final_time_sec
	else:
		_score_label.text = "score  %d" % _this_score
	_summary.text = _summary_text
	for item: CanvasItem in _list_roll_fade_items():
		item.modulate.a = 1.0

func _write_break_texts(loop_pts: int, kill_pts: int, gold_pts: int, time_pts: int) -> void:
	_loop_break.text = "loop  %d  ×1000  =  %d" % [_final_loop, loop_pts]
	_kills_break.text = "kills  %d  ×5  =  %d" % [_final_kills, kill_pts]
	_gold_break.text = "gold  %d  ×2  =  %d" % [_final_gold, gold_pts]
	_time_break.text = "time  %.1fs  →  %d" % [_final_time_sec, time_pts]

func _reveal_new_best() -> void:
	if _is_lan or _is_battle_result:
		_new_best.visible = false
		return
	_new_best.visible = _this_score > _previous_best

func _mark_roll_done() -> void:
	_roll_done = true
	_reveal_new_best()

func _list_roll_fade_items() -> Array[CanvasItem]:
	var items: Array[CanvasItem] = [_loop_break, _kills_break, _gold_break, _time_break, _summary, _rank_label]
	if _cleared_bonus.visible:
		items.append(_cleared_bonus)
	if _hist_empty.visible:
		items.append(_hist_empty)
	for row: Label in _hist_labels:
		if row.visible:
			items.append(row)
	return items

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
	_retry_button.disabled = (not enabled) or (not _retry_allowed)
	_menu_button.disabled = not enabled

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
