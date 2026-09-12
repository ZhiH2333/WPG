extends CanvasLayer
class_name RunSummary

## 死亡/通关结算条：只读 RunSession getter。禁止暂停场景树、禁止按钮、禁止全屏 Dimmer。出现时 osu 式缩放进场。
var _session: RunSession
var _shown: bool = false
var _anim_tween: Tween

@onready var _panel: PanelContainer = $Root/Center/Panel
@onready var _title: Label = $Root/Center/Panel/Column/Title
@onready var _time_label: Label = $Root/Center/Panel/Column/TimeLabel
@onready var _loop_label: Label = $Root/Center/Panel/Column/LoopLabel
@onready var _kills_label: Label = $Root/Center/Panel/Column/KillsLabel
@onready var _gold_label: Label = $Root/Center/Panel/Column/GoldLabel
@onready var _owned_label: Label = $Root/Center/Panel/Column/OwnedLabel
@onready var _best_label: Label = $Root/Center/Panel/Column/BestLabel

func bind_run_session(session: RunSession) -> void:
	_session = session

func _process(_delta: float) -> void:
	if _session == null or (not _session.is_player_dead() and not _session.is_cleared()):
		visible = false
		_shown = false
		return
	if _session.is_cleared():
		_title.text = "CLEARED"
		_title.theme_type_variation = &"ClearedTitle"
	else:
		_title.text = "DEAD"
		_title.theme_type_variation = &"RunSummaryTitle"
	_time_label.text = "time  %.1fs" % _session.get_elapsed_sec()
	_loop_label.text = "loop  %d" % _session.get_loop_index()
	_kills_label.text = "kills  %d" % _session.get_kill_count()
	_gold_label.text = "gold  %d" % _session.get_gold()
	_owned_label.text = "owned  %s" % _format_owned()
	_best_label.text = "best  %d" % GameProgress.get_best_loop()
	visible = true
	if not _shown:
		_shown = true
		UiAnim.kill_tween(_anim_tween)
		_anim_tween = UiAnim.enter_overlay(self, null, null, [_panel])

func _format_owned() -> String:
	var ids: PackedStringArray = _session.get_owned_upgrade_ids()
	if ids.is_empty():
		return "-"
	return ",".join(ids)
