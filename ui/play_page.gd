extends Control
class_name PlayPage

## Play 页。三条 Rail 与 Home 同一目的地。不是 ModeChoice，也不是大面板。
signal continue_pressed
signal solo_pressed
signal multi_pressed
signal back_pressed

const RAIL_HEIGHT: float = 88.0

var _open: bool = false
var _anim_tween: Tween

## 版心参数（与 winner_page / profile_overlay 一致）：1920 宽下内容 1200px。
## 原来写死的 offset_right = -672 是按 1920 算的；UI Scale 放大后逻辑视口变窄，
## 同一组缩进会把内容列压扁，右侧控件被挤出画面。
const CONTENT_MARGIN: float = 48.0
const CONTENT_MAX_WIDTH: float = 1200.0

@onready var _dimmer: ColorRect = $Dimmer
@onready var _sheet: Control = $Sheet
@onready var _column: VBoxContainer = $Sheet/Column
@onready var _continue_button: Button = $Sheet/Column/Rail/Continue
@onready var _solo_button: Button = $Sheet/Column/Rail/Solo
@onready var _multi_button: Button = $Sheet/Column/Rail/Multi
@onready var _continue_caption: Label = $Sheet/Column/Rail/Continue/Text/Caption
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
	_continue_button.pressed.connect(_on_continue_pressed)
	_solo_button.pressed.connect(_on_solo_pressed)
	_multi_button.pressed.connect(_on_multi_pressed)
	_back_button.pressed.connect(_on_back_pressed)
	## 视口变化（窗口缩放 / UI Scale 改变）时重算版心宽度。
	_column.get_viewport().size_changed.connect(_sync_content_width)
	_sync_content_width()
	for button: Button in [_continue_button, _solo_button, _multi_button, _back_button]:
		_wire_hover(button)
		UiAnim.wire_row_feedback(self, button, UiType.INK)

func is_open() -> bool:
	return _open

func open(direction: int = 0) -> void:
	_open = true
	visible = true
	modulate.a = 1.0
	mouse_filter = Control.MOUSE_FILTER_STOP
	_refresh_continue()
	_wire_focus()
	UiAnim.kill_tween(_anim_tween)
	_anim_tween = UiAnim.enter_page(self, _dimmer, _sheet, false, direction)

func close(direction: int = 0) -> void:
	if not _open:
		return
	_open = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiAnim.kill_tween(_anim_tween)
	_anim_tween = UiAnim.exit_page(self, _dimmer, _sheet, false, direction)
	_anim_tween.finished.connect(_finish_close)

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
		return
	## 打开界面时不自动聚焦（见 UiFocus）：键盘 / 手柄第一次按导航键才建立焦点。
	if UiFocus.handle_first_pad_input(self, event, [_first_rail()]):
		get_viewport().set_input_as_handled()
		return

func _refresh_continue() -> void:
	var menu: MainMenu = get_parent() as MainMenu
	var record: GameRecord = menu.latest_record() if menu != null else null
	var has_record: bool = record != null
	_continue_button.visible = has_record
	if not has_record:
		return
	_continue_caption.text = _loop_caption(record.loop_goal)

func _loop_caption(loop_goal: int) -> String:
	if loop_goal > 0:
		return "Loop %d" % loop_goal
	return "Inf"

func _first_rail() -> Button:
	if _continue_button.visible:
		return _continue_button
	return _solo_button

func _wire_focus() -> void:
	var slots: Array[Button] = []
	if _continue_button.visible:
		slots.append(_continue_button)
	slots.append(_solo_button)
	slots.append(_multi_button)
	var nav: Control = get_node_or_null("../TopBar/Row/PlayButton") as Control
	var top: NodePath = nav.get_path() if nav != null else slots[0].get_path()
	for index: int in slots.size():
		var slot: Button = slots[index]
		var left: Button = slots[index] if index == 0 else slots[index - 1]
		var right: Button = slots[index] if index == slots.size() - 1 else slots[index + 1]
		slot.focus_neighbor_left = left.get_path()
		slot.focus_neighbor_right = right.get_path()
		slot.focus_neighbor_top = top
		slot.focus_neighbor_bottom = _back_button.get_path()
	_back_button.focus_neighbor_top = slots[0].get_path()
	_back_button.focus_neighbor_bottom = _back_button.get_path()

func _on_continue_pressed() -> void:
	_play_click()
	continue_pressed.emit()

func _on_solo_pressed() -> void:
	_play_click()
	solo_pressed.emit()

func _on_multi_pressed() -> void:
	_play_click()
	multi_pressed.emit()

func _on_back_pressed() -> void:
	if not _open:
		return
	_play_back()
	back_pressed.emit()

func _wire_hover(button: BaseButton) -> void:
	button.mouse_entered.connect(_play_hover)
	button.focus_entered.connect(_play_hover)

func _play_hover() -> void:
	if not _open:
		return
	_play_stream(_hover_sfx)

func _play_click() -> void:
	_play_stream(_click_sfx)

func _play_back() -> void:
	_play_stream(_back_sfx)

func _play_stream(player: AudioStreamPlayer) -> void:
	if player == null or player.stream == null:
		return
	player.play()

## 按当前视口重算版心宽度，避免窄视口把内容列压扁。
func _sync_content_width() -> void:
	if _column == null:
		return
	sync_content_width_for(_column.get_viewport_rect().size.x)

## 参数化版本：测试要能强制 960（UI Scale 200%）这一档，而不是碰运气。
func sync_content_width_for(viewport_width: float) -> void:
	if _column == null:
		return
	_column.offset_left = CONTENT_MARGIN
	_column.offset_right = UiFit.content_offset_right(viewport_width, CONTENT_MARGIN, CONTENT_MAX_WIDTH)
