extends CanvasLayer
class_name RunSummary

## 死亡结算条：只读 RunSession getter。禁止暂停场景树、禁止按钮、禁止全屏 Dimmer。
var _session: RunSession

@onready var _time_label: Label = $Root/Center/Panel/Column/TimeLabel
@onready var _loop_label: Label = $Root/Center/Panel/Column/LoopLabel
@onready var _kills_label: Label = $Root/Center/Panel/Column/KillsLabel
@onready var _gold_label: Label = $Root/Center/Panel/Column/GoldLabel
@onready var _owned_label: Label = $Root/Center/Panel/Column/OwnedLabel

func bind_run_session(session: RunSession) -> void:
	_session = session

func _process(_delta: float) -> void:
	if _session == null or not _session.is_player_dead():
		visible = false
		return
	_time_label.text = "time  %.1fs" % _session.get_elapsed_sec()
	_loop_label.text = "loop  %d" % _session.get_loop_index()
	_kills_label.text = "kills  %d" % _session.get_kill_count()
	_gold_label.text = "gold  %d" % _session.get_gold()
	_owned_label.text = "owned  %s" % _format_owned()
	visible = true

func _format_owned() -> String:
	var ids: PackedStringArray = _session.get_owned_upgrade_ids()
	if ids.is_empty():
		return "-"
	return ",".join(ids)
