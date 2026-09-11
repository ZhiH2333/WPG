extends Control
class_name ProfileOverlay

## 主菜单 Profile 叠层：只读 GameProgress。不是战斗 CanvasLayer，不暂停场景树。
var _open: bool = false
var _anim_tween: Tween

@onready var _dimmer: ColorRect = $Dimmer
@onready var _panel: PanelContainer = $Center/Panel
@onready var _best_loop_label: Label = $Center/Panel/Column/BestLoop
@onready var _last_loop_label: Label = $Center/Panel/Column/LastLoop
@onready var _last_kills_label: Label = $Center/Panel/Column/LastKills
@onready var _last_gold_label: Label = $Center/Panel/Column/LastGold
@onready var _runs_label: Label = $Center/Panel/Column/Runs
@onready var _owned_label: Label = $Center/Panel/Column/OwnedHint
@onready var _back_button: Button = $Back

func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_back_button.pressed.connect(close)

func is_open() -> bool:
	return _open

func open() -> void:
	_refresh_stats()
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
