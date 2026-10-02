extends Control
class_name LanOverlay

## 主菜单局域网叠层：JOIN 房间列表 / PICK / HOST。Multi 直接进发现。Create a room 开房。Host 可借已有档预填角色、loop_goal 和地图，联机仍不写档。禁止 Autoload，禁止 AcceptDialog。座位 1～5，第三人进房不踢，满 5 才踢。大厅 Host 听 17778，Guest 探针。
signal start_lan

enum View { HOME, PICK, HOST, JOIN, LOBBY }

const CATALOG: CharacterCatalog = preload("res://data/character_catalog.tres")
const FALLBACK_BODY: Texture2D = preload("res://images/player.png")
const CHAR_BOAR := "boar"
const CHAR_CHICKEN := "chicken"
const DEFAULT_LOOP_GOAL: int = 20
const SEAT_ROW_HEIGHT: float = 24.0

var _open: bool = false
var _view: View = View.HOME
var _anim_tween: Tween
var _sfx_gate: Dictionary = {}
var _selected_character_id: String = CHAR_BOAR
var _host_started: bool = false
var _picked_record_id: String = ""
var _selected_arena_id: String = "yard"
var _net_play: GameLaunch.NetPlay = GameLaunch.NetPlay.COOP
var _beacon: LanBeacon
## Lobby domain 的唯一入口，由 MainMenu 注入（不是 Autoload）。座位 / ready / 网络状态全归它。
var _lobby: LobbyManager = null
var _seat_rows: Array[HBoxContainer] = []
## Guest 的 Lobby 视图座位行（与 Host 视图分开维护）。
var _guest_seat_rows: Array[HBoxContainer] = []
## 掉线提示播放中：期间不接受 room_changed 的整体刷新，先把 PLAYERxx LEFT 播完。
var _lobby_notice_playing: bool = false

@onready var _dimmer: ColorRect = $Dimmer
@onready var _sheet: Control = $Sheet
@onready var _column: VBoxContainer = $Sheet/Column
@onready var _content: Control = $Sheet/Column/Content
@onready var _home_root: Control = $Sheet/Column/Content/HomeRoot
@onready var _pick_root: Control = $Sheet/Column/Content/PickRoot
@onready var _host_root: Control = $Sheet/Column/Content/HostRoot
@onready var _join_root: Control = $Sheet/Column/Content/JoinRoot
@onready var _lobby_root: Control = $Sheet/Column/Content/LobbyRoot
@onready var _host_button: Button = $Sheet/Column/Content/HomeRoot/Center/Column/Host
@onready var _join_button: Button = $Sheet/Column/Content/HomeRoot/Center/Column/Join
@onready var _pick_scroll: ScrollContainer = $Sheet/Column/Content/PickRoot/Scroll
@onready var _pick_cards: GridContainer = $Sheet/Column/Content/PickRoot/Scroll/Cards
@onready var _custom_button: Button = $Sheet/Column/Content/PickRoot/Scroll/Cards/Custom
@onready var _host_address: Label = $Sheet/Column/Content/HostRoot/Body/Left/AddressList
@onready var _host_status: Label = $Sheet/Column/Content/HostRoot/Body/Left/Status
@onready var _seats: VBoxContainer = $Sheet/Column/Content/HostRoot/Body/Left/Seats
@onready var _record_hint: Label = $Sheet/Column/Content/HostRoot/Body/Left/RecordHint
@onready var _host_boar: Button = $Sheet/Column/Content/HostRoot/Body/Left/Characters/Boar
@onready var _host_chicken: Button = $Sheet/Column/Content/HostRoot/Body/Left/Characters/Chicken
@onready var _host_yard: Button = $Sheet/Column/Content/HostRoot/Body/Right/Arenas/Yard
@onready var _host_pit: Button = $Sheet/Column/Content/HostRoot/Body/Right/Arenas/Pit
@onready var _host_keep: Button = $Sheet/Column/Content/HostRoot/Body/Right/Arenas/Keep
@onready var _host_coop: Button = $Sheet/Column/Content/HostRoot/Body/Right/Modes/Coop
@onready var _host_battle: Button = $Sheet/Column/Content/HostRoot/Body/Right/Modes/Battle
@onready var _loop_slider: HSlider = $Sheet/Column/Content/HostRoot/Body/Right/LoopRow/Slider
@onready var _loop_label: Label = $Sheet/Column/Content/HostRoot/Body/Right/LoopRow/LoopLabel
@onready var _start_button: Button = $Sheet/Column/Content/HostRoot/Body/Right/Start
@onready var _host_invite: Button = $Sheet/Column/Content/HostRoot/Body/Right/Invite
@onready var _join_search: LineEdit = $Sheet/Column/Content/JoinRoot/Row/Browse/Search
@onready var _create_room_button: Button = $Sheet/Column/Content/JoinRoot/Row/Browse/CreateRoom
@onready var _join_empty: Label = $Sheet/Column/Content/JoinRoot/Row/Browse/EmptyHint
@onready var _join_cards: VBoxContainer = $Sheet/Column/Content/JoinRoot/Row/Browse/Scroll/Cards
@onready var _join_edit: LineEdit = $Sheet/Column/Content/JoinRoot/Row/Form/Address
@onready var _connect_button: Button = $Sheet/Column/Content/JoinRoot/Row/Form/Connect
@onready var _join_status: Label = $Sheet/Column/Content/JoinRoot/Row/Form/Status
@onready var _join_boar: Button = $Sheet/Column/Content/JoinRoot/Row/Form/Characters/Boar
@onready var _join_chicken: Button = $Sheet/Column/Content/JoinRoot/Row/Form/Characters/Chicken
@onready var _join_goal: Label = $Sheet/Column/Content/JoinRoot/Row/Form/GoalLabel
@onready var _join_map: Label = $Sheet/Column/Content/JoinRoot/Row/Form/MapLabel
@onready var _join_mode: Label = $Sheet/Column/Content/JoinRoot/Row/Form/ModeLabel
@onready var _join_seat: Label = $Sheet/Column/Content/JoinRoot/Row/Form/SeatLabel
@onready var _join_wait: Label = $Sheet/Column/Content/JoinRoot/Row/Form/WaitingLabel
@onready var _back_button: Button = $Sheet/Column/Header/Back
@onready var _lobby_room_name: Label = $Sheet/Column/Content/LobbyRoot/Body/RoomHeader/RoomName
@onready var _lobby_mode_tag: Label = $Sheet/Column/Content/LobbyRoot/Body/RoomHeader/ModeTag
@onready var _lobby_room_facts: Label = $Sheet/Column/Content/LobbyRoot/Body/RoomFacts
@onready var _lobby_seats: VBoxContainer = $Sheet/Column/Content/LobbyRoot/Body/Seats
@onready var _lobby_connection: Label = $Sheet/Column/Content/LobbyRoot/Body/Connection
@onready var _lobby_boar: Button = $Sheet/Column/Content/LobbyRoot/Body/Actions/Boar
@onready var _lobby_chicken: Button = $Sheet/Column/Content/LobbyRoot/Body/Actions/Chicken
@onready var _lobby_invite: Button = $Sheet/Column/Content/LobbyRoot/Body/Actions/Invite
@onready var _lobby_ready: Button = $Sheet/Column/Content/LobbyRoot/Body/Actions/Ready
@onready var _hover_sfx: AudioStreamPlayer = $HoverSfx
@onready var _click_sfx: AudioStreamPlayer = $ClickSfx
@onready var _back_sfx: AudioStreamPlayer = $BackSfx
@onready var _error_sfx: AudioStreamPlayer = $ErrorSfx

func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hover_sfx.stream = GameAudio.load_wav("res://audio/ui_hover.wav")
	_click_sfx.stream = GameAudio.load_wav("res://audio/ui_click.wav")
	_back_sfx.stream = GameAudio.load_wav("res://audio/ui_back.wav")
	_error_sfx.stream = GameAudio.load_wav("res://audio/click.wav")
	_fill_character(_host_boar, CHAR_BOAR)
	_fill_character(_host_chicken, CHAR_CHICKEN)
	_fill_character(_join_boar, CHAR_BOAR)
	_fill_character(_join_chicken, CHAR_CHICKEN)
	_host_button.pressed.connect(_on_home_host_pressed)
	_join_button.pressed.connect(_on_home_join_pressed)
	_create_room_button.pressed.connect(_on_home_host_pressed)
	_custom_button.pressed.connect(_on_custom_pressed)
	_host_boar.pressed.connect(_on_character_pressed.bind(CHAR_BOAR))
	_host_chicken.pressed.connect(_on_character_pressed.bind(CHAR_CHICKEN))
	_host_yard.pressed.connect(_on_arena_pressed.bind("yard"))
	_host_pit.pressed.connect(_on_arena_pressed.bind("pit"))
	_host_keep.pressed.connect(_on_arena_pressed.bind("keep"))
	_host_coop.pressed.connect(_on_mode_pressed.bind(GameLaunch.NetPlay.COOP))
	_host_battle.pressed.connect(_on_mode_pressed.bind(GameLaunch.NetPlay.BATTLE))
	_join_boar.pressed.connect(_on_character_pressed.bind(CHAR_BOAR))
	_join_chicken.pressed.connect(_on_character_pressed.bind(CHAR_CHICKEN))
	_lobby_boar.pressed.connect(_on_lobby_character_pressed.bind(CHAR_BOAR))
	_lobby_chicken.pressed.connect(_on_lobby_character_pressed.bind(CHAR_CHICKEN))
	_lobby_ready.pressed.connect(_on_lobby_ready_pressed)
	_lobby_invite.pressed.connect(_on_invite_pressed)
	_host_invite.pressed.connect(_on_invite_pressed)
	_loop_slider.value_changed.connect(_on_loop_changed)
	_start_button.pressed.connect(_on_start_pressed)
	_connect_button.pressed.connect(_on_connect_pressed)
	_back_button.pressed.connect(_handle_back)
	for button: Button in [_host_button, _join_button, _create_room_button, _custom_button, _host_boar, _host_chicken, _host_yard, _host_pit, _host_keep, _host_coop, _host_battle, _start_button, _connect_button, _join_boar, _join_chicken, _lobby_boar, _lobby_chicken, _lobby_ready, _lobby_invite, _host_invite, _back_button]:
		_wire_hover(button)
	UiFit.connect_refit(self, _on_host_resized)
	_content.resized.connect(_on_content_resized)
	_build_seat_rows()
	_build_guest_seat_rows()
	_ensure_beacon()
	_join_search.text_changed.connect(_on_join_search_changed)
	_enter_join()

func _exit_tree() -> void:
	_stop_beacon()

func is_open() -> bool:
	return _open

## MainMenu 在 _ready 注入 LobbyManager。UI 只发命令、只读 snapshot，不碰 Room 内部数组、不碰 ENet。
func bind_lobby(manager: LobbyManager) -> void:
	_lobby = manager
	if _lobby == null:
		return
	if not _lobby.room_changed.is_connected(_on_lobby_changed):
		_lobby.room_changed.connect(_on_lobby_changed)
	if not _lobby.room_closed.is_connected(_on_lobby_closed):
		_lobby.room_closed.connect(_on_lobby_closed)
	if not _lobby.player_left.is_connected(_on_lobby_player_left):
		_lobby.player_left.connect(_on_lobby_player_left)
	_refresh_lobby_view()

func _on_lobby_changed() -> void:
	if not _open:
		return
	# 掉线提示播放期间按兵不动：座位墙要先把 PLAYERxx LEFT 播完，再画回 EMPTY SEAT。
	# 座位本身在 domain 侧已经立刻释放（Room 里已经没有这个人），这里只是把过程播给玩家看。
	if _lobby_notice_playing:
		return
	_refresh_lobby_view()

## 掉线 / 离房提示：该行淡出 + 盖一条 PLAYERxx LEFT，1.5s 后才重画座位墙。
func _on_lobby_player_left(display_name: String, seat: int) -> void:
	if not _open or _view != View.LOBBY:
		return
	var row: HBoxContainer = _lobby_seat_row(seat)
	if row != null:
		UiAnim.fade_modulate(self, row, 0.0, 0.18, true)
	var who: String = display_name.strip_edges().to_upper()
	if who.is_empty():
		who = "PLAYER %02d" % seat
	_lobby_connection.text = "%s LEFT" % who
	UiAnim.flash_error(self, _lobby_connection)
	_play_error()
	_lobby_notice_playing = true
	var timer: SceneTreeTimer = get_tree().create_timer(1.5)
	timer.timeout.connect(_finish_lobby_left_notice)

func _finish_lobby_left_notice() -> void:
	_lobby_notice_playing = false
	if _open and _view == View.LOBBY:
		_refresh_lobby_view()

## 座位号 -> Lobby 视图的固定座位行（Lobby 只有 LobbyRoot 可见，Host 视图另有 _seat_rows）。
func _lobby_seat_row(seat: int) -> HBoxContainer:
	if seat < Room.HOST_SEAT or seat > _guest_seat_rows.size():
		return null
	return _guest_seat_rows[seat - 1]

func _on_lobby_closed() -> void:
	if not _open:
		return
	_refresh_lobby_view()

## 座位墙：5 行固定结构，只按 Room 快照改字，不重建节点。
func _build_seat_rows() -> void:
	_build_rows_into(_seats, _seat_rows)

func _build_guest_seat_rows() -> void:
	_build_rows_into(_lobby_seats, _guest_seat_rows)

func _build_rows_into(container: VBoxContainer, store: Array[HBoxContainer]) -> void:
	store.clear()
	for seat: int in range(1, GameLaunch.NET_MAX_SEATS + 1):
		var row: HBoxContainer = HBoxContainer.new()
		row.name = "Seat%d" % seat
		row.custom_minimum_size = Vector2(0, SEAT_ROW_HEIGHT)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_theme_constant_override("separation", 12)
		row.add_child(_make_seat_label("Name", &"OfferTitle", 260.0, Control.SIZE_EXPAND_FILL, HORIZONTAL_ALIGNMENT_LEFT))
		row.add_child(_make_seat_label("Tag", &"Caption", 72.0, Control.SIZE_SHRINK_END, HORIZONTAL_ALIGNMENT_LEFT))
		row.add_child(_make_seat_label("Character", &"OfferDesc", 96.0, Control.SIZE_SHRINK_END, HORIZONTAL_ALIGNMENT_LEFT))
		row.add_child(_make_seat_label("State", &"StatValue", 104.0, Control.SIZE_SHRINK_END, HORIZONTAL_ALIGNMENT_RIGHT))
		container.add_child(row)
		store.append(row)

func _make_seat_label(node_name: String, variation: StringName, min_width: float, size_flags: int, align: int) -> Label:
	var label: Label = Label.new()
	label.name = node_name
	label.theme_type_variation = variation
	label.custom_minimum_size = Vector2(min_width, 0)
	label.size_flags_horizontal = size_flags
	label.horizontal_alignment = align
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.clip_text = true
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _refresh_lobby_view() -> void:
	if _lobby == null:
		return
	var snapshot: Dictionary = _lobby.get_snapshot()
	var seats: Array = snapshot.get("seats", [])
	for index: int in _seat_rows.size():
		var seat_data: Dictionary = seats[index] if index < seats.size() else {"occupied": false}
		_apply_seat_row(_seat_rows, index, seat_data)
	for index: int in _guest_seat_rows.size():
		var seat_data: Dictionary = seats[index] if index < seats.size() else {"occupied": false}
		_apply_seat_row(_guest_seat_rows, index, seat_data)
	_host_status.text = _lobby_status_text(snapshot)
	_refresh_host_start()
	_refresh_guest_lobby(snapshot)

func _apply_seat_row(rows: Array[HBoxContainer], index: int, seat_data: Dictionary) -> void:
	var row: HBoxContainer = rows[index]
	var name_label: Label = row.get_node("Name") as Label
	var tag_label: Label = row.get_node("Tag") as Label
	var character_label: Label = row.get_node("Character") as Label
	var state_label: Label = row.get_node("State") as Label
	if not bool(seat_data.get("occupied", false)):
		name_label.text = "EMPTY SEAT"
		tag_label.text = ""
		character_label.text = ""
		state_label.text = ""
		row.modulate.a = 0.5
		return
	row.modulate.a = 1.0
	var display_name: String = str(seat_data.get("display_name", "")).to_upper()
	name_label.text = display_name if not display_name.is_empty() else "CONNECTING"
	tag_label.text = "HOST" if bool(seat_data.get("is_host", false)) else "PLAYER"
	character_label.text = _seat_character_text(str(seat_data.get("selected_character_id", "")))
	state_label.text = _seat_state_text(seat_data)

## Guest Lobby 视图：房间事实、连接句、角色选择、Ready 文案。
func _refresh_guest_lobby(snapshot: Dictionary) -> void:
	if not bool(snapshot.get("has_room", false)):
		return
	_lobby_room_name.text = _room_title(snapshot).to_upper()
	_lobby_mode_tag.text = _mode_name(int(snapshot.get("net_play", 0))).to_upper()
	_lobby_room_facts.text = _room_facts(snapshot)
	var networked: bool = bool(snapshot.get("networked", false))
	_lobby_connection.text = "%s  ·  %s" % ["LAN" if networked else "OFFLINE", _connection_word(snapshot)]
	_sync_lobby_character_buttons()
	var local_ready: bool = bool(snapshot.get("local_ready", false))
	_lobby_ready.text = "NOT READY" if local_ready else "READY"
	var local_host: bool = bool(snapshot.get("local_is_host", false))
	_lobby_ready.visible = not local_host
	_lobby_boar.visible = not local_host
	_lobby_chicken.visible = not local_host

func _room_title(snapshot: Dictionary) -> String:
	var host_name: String = str(snapshot.get("host_display_name", ""))
	if host_name.is_empty():
		return "ROOM"
	return "%s'S ROOM" % host_name

func _room_facts(snapshot: Dictionary) -> String:
	var arena: String = RecordCard.format_arena_name(str(snapshot.get("arena_id", "yard")))
	var mode: String = _mode_name(int(snapshot.get("net_play", 0)))
	var goal: String = _goal_text(snapshot)
	return "%s  ·  %s  ·  %s" % [mode, arena, goal]

func _goal_text(snapshot: Dictionary) -> String:
	if int(snapshot.get("net_play", 0)) == int(GameLaunch.NetPlay.BATTLE):
		return "BATTLE"
	return RecordCard.format_loop_badge(int(snapshot.get("loop_goal", 0)))

func _mode_name(net_play: int) -> String:
	return "BATTLE" if net_play == int(GameLaunch.NetPlay.BATTLE) else "CO-OP"

func _connection_word(snapshot: Dictionary) -> String:
	var occupied: int = int(snapshot.get("occupied_count", 0))
	var max_players: int = int(snapshot.get("max_players", GameLaunch.NET_MAX_SEATS))
	if occupied <= 1:
		return "WAITING"
	return "CONNECTED  %d/%d" % [occupied, max_players]

func _sync_lobby_character_buttons() -> void:
	var local: LobbyPlayer = _lobby.get_local_player() if _lobby != null else null
	var character_id: String = local.selected_character_id if local != null else _selected_character_id
	_lobby_boar.button_pressed = character_id == CHAR_BOAR
	_lobby_chicken.button_pressed = character_id == CHAR_CHICKEN

## 本地玩家在 Guest Lobby 的座位行（用于行级 ready 反馈）。
func _local_lobby_row() -> HBoxContainer:
	if _lobby == null:
		return null
	var seat: int = _lobby.get_local_seat()
	if seat < Room.HOST_SEAT or seat > _guest_seat_rows.size():
		return null
	return _guest_seat_rows[seat - 1]

func _seat_character_text(character_id: String) -> String:
	if character_id.is_empty():
		return ""
	var def: CharacterDef = CATALOG.get_by_id(StringName(character_id))
	return (def.display_name if def != null else character_id).to_upper()

func _seat_state_text(seat_data: Dictionary) -> String:
	if bool(seat_data.get("pending", false)):
		return "CONNECTING"
	## Host 恒显示 HOST：它不参与 Start 判定，不该被画成 READY / WAITING。
	if bool(seat_data.get("is_host", false)):
		return "HOST"
	match int(seat_data.get("connection_state", LobbyPlayer.ConnectionState.CONNECTED)):
		LobbyPlayer.ConnectionState.CONNECTING:
			return "CONNECTING"
		LobbyPlayer.ConnectionState.LOST:
			return "LOST"
	return "READY" if bool(seat_data.get("ready", false)) else "WAITING"

func _lobby_status_text(snapshot: Dictionary) -> String:
	if not bool(snapshot.get("has_room", false)):
		return "waiting"
	if bool(snapshot.get("networked", false)):
		var occupied: int = int(snapshot.get("occupied_count", 0))
		if occupied <= 1:
			return "waiting"
		return "%d/%d connected" % [occupied, int(snapshot.get("max_players", GameLaunch.NET_MAX_SEATS))]
	if int(snapshot.get("player_count", 0)) <= 1:
		return "offline mock"
	return "offline mock · %d seats" % int(snapshot.get("player_count", 0))

func open(direction: int = 0) -> void:
	_open = true
	visible = true
	modulate.a = 1.0
	mouse_filter = Control.MOUSE_FILTER_STOP
	_picked_record_id = ""
	_reset_play_mode()
	_enter_join()
	UiAnim.kill_tween(_anim_tween)
	_anim_tween = UiAnim.enter_page(self, _dimmer, _sheet, false, direction)
	_create_room_button.grab_focus()

func close(direction: int = 0) -> void:
	if not _open:
		return
	_open = false
	_picked_record_id = ""
	_clear_peer()
	_leave_lobby_room()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiAnim.kill_tween(_anim_tween)
	_anim_tween = UiAnim.exit_page(self, _dimmer, _sheet, false, direction)
	_anim_tween.finished.connect(_finish_close)
	var menu: MainMenu = get_parent() as MainMenu
	if menu != null:
		menu.on_lan_closed()

func _finish_close() -> void:
	if _open:
		return
	visible = false
	modulate.a = 1.0

func _input(event: InputEvent) -> void:
	if not _open:
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_handle_back()
		return
	if event is InputEventJoypadButton:
		var joy: InputEventJoypadButton = event as InputEventJoypadButton
		if joy.pressed and joy.button_index == JOY_BUTTON_START:
			get_viewport().set_input_as_handled()
			_handle_back()
			return
	if _handle_lobby_debug_key(event):
		get_viewport().set_input_as_handled()
		return
	if _view == View.HOME or _view == View.PICK:
		return
	if _is_host_locked():
		return
	if _view == View.JOIN and (_join_edit.has_focus() or _join_search.has_focus()):
		return
	if event.is_action_pressed("weapon_pistol"):
		get_viewport().set_input_as_handled()
		_play_click()
		_select_character(CHAR_BOAR)
		return
	if event.is_action_pressed("weapon_shotgun"):
		get_viewport().set_input_as_handled()
		_play_click()
		_select_character(CHAR_CHICKEN)

## 离线 mock 调试键（仅 debug 构建，只在 HOST 视图生效；不是玩家功能，不进 InputMap）：
## F10 = 加一个假座位，F11 = 移除最后一个假座位，F12 = 断开 ENet 退回离线 mock。
## 假座位只为验证 roster / seat / ready / 上限 / start 条件，不上网也不参战。
func _handle_lobby_debug_key(event: InputEvent) -> bool:
	if not OS.is_debug_build() or _view != View.HOST or _lobby == null:
		return false
	var key: InputEventKey = event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return false
	match key.physical_keycode:
		KEY_F10:
			if _lobby.add_mock_player() == null:
				_play_error()
				return true
			_play_click()
			return true
		KEY_F11:
			if not _lobby.remove_mock_player():
				_play_error()
				return true
			_play_back()
			return true
		KEY_F12:
			if _occupied() > 1 or _lobby.has_pending():
				_play_error()
				return true
			_play_click()
			_clear_peer()
			_lobby.mark_offline()
			_refresh_host_status()
			return true
	return false

func _handle_back() -> void:
	_play_back()
	if _view == View.HOST or _view == View.JOIN:
		_leave_lobby_room()
	# Guest 已进 Lobby：Back = 断线离房回多人大厅（1.0 无 reconnect）。
	if _view == View.LOBBY:
		_leave_lobby_room()
		_clear_peer()
		close(-1)
		return
	if _view == View.HOME or _view == View.JOIN:
		close(-1)
		return
	if _view == View.PICK:
		_enter_join()
		return
	_clear_peer()
	if _view == View.HOST and not _picked_record_id.is_empty():
		_enter_pick()
		return
	_enter_join()

## 离开 HOST 视图 / 关页 = 离房。Host 离房即关房（1.0 不做 Host 迁移）。
## 已开战（_host_started）时不碰房间，交给换场。
func _leave_lobby_room() -> void:
	if _host_started or _lobby == null or not _lobby.has_room():
		return
	_lobby.leave_room()

func _show_home(_animate: bool) -> void:
	_picked_record_id = ""
	_reset_play_mode()
	_enter_join()

func _on_home_host_pressed() -> void:
	if not _open:
		return
	if _view != View.JOIN and _view != View.HOME and _view != View.PICK:
		return
	_play_click()
	GameRecords.load_from_disk()
	if GameRecords.list_records().is_empty():
		_enter_host()
		return
	_enter_pick()

func _on_custom_pressed() -> void:
	if not _open or _view != View.PICK:
		return
	_play_click()
	_enter_host()

func _on_pick_record_pressed(record_id: String) -> void:
	if not _open or _view != View.PICK:
		return
	var record: GameRecord = GameRecords.get_record(record_id)
	if record == null:
		return
	_play_click()
	_picked_record_id = record.id
	_enter_host_from_record(record)

func _enter_pick() -> void:
	_stop_beacon()
	_view = View.PICK
	_home_root.visible = false
	_host_root.visible = false
	_join_root.visible = false
	_lobby_root.visible = false
	_pick_root.visible = true
	_refresh_pick()
	_play_pick_enter()
	_focus_pick()

func _enter_host() -> void:
	_picked_record_id = ""
	_reset_character()
	_reset_play_mode()
	_select_arena("yard")
	_loop_slider.value = float(DEFAULT_LOOP_GOAL)
	_refresh_loop_label()
	_apply_host_config_lock(false)
	_begin_host()

func _enter_host_from_record(record: GameRecord) -> void:
	_picked_record_id = record.id
	_select_character(record.character_id)
	_select_arena(record.arena_id)
	_loop_slider.value = float(mini(maxi(record.loop_goal, 0), 50))
	_refresh_loop_label()
	_record_hint.text = record.name
	_reset_play_mode()
	_apply_host_config_lock(true)
	_begin_host()

func _begin_host() -> void:
	_view = View.HOST
	_home_root.visible = false
	_pick_root.visible = false
	_join_root.visible = false
	_lobby_root.visible = false
	_host_root.visible = true
	_host_address.text = _format_addresses()
	if not _lobby.host_room(_selected_arena_id, _net_play, _host_loop_goal(), _picked_record_id):
		_refresh_host_start()
		_host_status.text = "bind failed"
		_play_error()
		return
	_lobby.set_local_character(_selected_character_id)
	_start_host_beacon()
	_refresh_host_status()
	if _picked_record_id.is_empty():
		_host_boar.grab_focus()
		return
	_back_button.grab_focus()

## Guest 的 Lobby 视图：握手成功后进入，只画 Room 快照 + Ready / Character。
func _enter_lobby() -> void:
	_view = View.LOBBY
	_home_root.visible = false
	_pick_root.visible = false
	_host_root.visible = false
	_join_root.visible = false
	_lobby_root.visible = true
	_refresh_lobby_view()
	if not _is_lobby_frozen():
		_lobby_ready.grab_focus()

## 建房先于 bind：房间是领域状态，有没有 ENet peer 只是它的一种形态（离线 mock / 真 LAN）。
## 命令与网络执行都归 LobbyManager / LobbyNet，UI 不碰 ENet。
func _enter_join() -> void:
	_view = View.JOIN
	_home_root.visible = false
	_pick_root.visible = false
	_host_root.visible = false
	_lobby_root.visible = false
	_join_root.visible = true
	_reset_character()
	_join_edit.text = GameLaunch.DEFAULT_JOIN_ADDRESS
	_join_status.text = ""
	_hide_join_session_labels()
	_connect_button.disabled = false
	if not _open:
		return
	_start_guest_beacon()
	_create_room_button.grab_focus()

func _on_connect_pressed() -> void:
	if _view != View.JOIN:
		return
	_play_click()
	_start_guest_beacon()
	_join_status.text = "connecting"
	_hide_join_session_labels()
	_connect_button.disabled = true
	# 连接执行归 LobbyNet（经 LobbyManager 命令），UI 不建 peer。
	if _lobby == null or not _lobby.join_room_address(_join_edit.text):
		_join_status.text = "refused"
		_connect_button.disabled = false

func _on_start_pressed() -> void:
	if not _can_start():
		_play_error()
		return
	_play_click()
	# 信封与 begin 广播都由 LobbyManager / LobbyNet 负责：UI 不拼 GameLaunch、不发 RPC。
	if _lobby == null or not _lobby.start_match():
		_play_error()
		return
	_host_started = true
	_stop_beacon()
	start_lan.emit()

func _on_loop_changed(_value: float) -> void:
	_refresh_loop_label()
	if _lobby != null:
		_lobby.set_loop_goal(_host_loop_goal())
	_sync_host_beacon()

func _select_character(character_id: String) -> void:
	_selected_character_id = GameLaunch._sanitize_character_id(character_id)
	_host_boar.button_pressed = _selected_character_id == CHAR_BOAR
	_host_chicken.button_pressed = _selected_character_id == CHAR_CHICKEN
	_join_boar.button_pressed = _selected_character_id == CHAR_BOAR
	_join_chicken.button_pressed = _selected_character_id == CHAR_CHICKEN
	if _lobby != null and _lobby.has_room():
		_lobby.set_local_character(_selected_character_id)

func _select_arena(arena_id: String) -> void:
	_selected_arena_id = GameLaunch._sanitize_arena_id(arena_id)
	_host_yard.button_pressed = _selected_arena_id == "yard"
	_host_pit.button_pressed = _selected_arena_id == "pit"
	_host_keep.button_pressed = _selected_arena_id == "keep"
	if _lobby != null:
		_lobby.set_arena_id(_selected_arena_id)
	_sync_host_beacon()

func _reset_character() -> void:
	_selected_character_id = CHAR_BOAR
	_host_boar.button_pressed = true
	_host_chicken.button_pressed = false
	_join_boar.button_pressed = true
	_join_chicken.button_pressed = false

func _reset_play_mode() -> void:
	_select_net_play(GameLaunch.NetPlay.COOP)

func _play_from_net(net_play: int) -> GameLaunch.NetPlay:
	if net_play == int(GameLaunch.NetPlay.BATTLE):
		return GameLaunch.NetPlay.BATTLE
	return GameLaunch.NetPlay.COOP

func _on_mode_pressed(play: GameLaunch.NetPlay) -> void:
	_play_click()
	_select_net_play(play)

func _select_net_play(play: GameLaunch.NetPlay) -> void:
	_net_play = play
	_host_coop.button_pressed = play == GameLaunch.NetPlay.COOP
	_host_battle.button_pressed = play == GameLaunch.NetPlay.BATTLE
	if _lobby != null:
		_lobby.set_net_play(play)
	_refresh_mode_ui()
	_refresh_host_start()
	_sync_host_beacon()

func _refresh_mode_ui() -> void:
	if _net_play == GameLaunch.NetPlay.BATTLE:
		_loop_slider.editable = false
		_loop_label.text = "battle"
		return
	_loop_slider.editable = _picked_record_id.is_empty()
	_refresh_loop_label()

func _refresh_loop_label() -> void:
	if _net_play == GameLaunch.NetPlay.BATTLE:
		_loop_label.text = "battle"
		return
	_loop_label.text = RecordCard.format_loop_badge(maxi(roundi(_loop_slider.value), 0))

func _refresh_host_start() -> void:
	var can_start: bool = _can_start()
	_start_button.disabled = not can_start
	_start_button.focus_mode = Control.FOCUS_ALL if can_start else Control.FOCUS_NONE
	_start_button.text = _start_button_text()

## Start 按钮文案由 LobbyManager 的条件驱动，UI 不自己猜。
func _start_button_text() -> String:
	if _lobby == null:
		return "START"
	match _lobby.start_block_reason():
		"":
			return "START"
		"need 2":
			return "NEED 2 PLAYERS"
		"not ready":
			return "WAITING FOR PLAYERS"
		"connecting", "no peer":
			return "CONNECTING..."
		"pending":
			return "CONNECTING..."
		_:
			return "START"

func _is_host_locked() -> bool:
	return _view == View.HOST and not _picked_record_id.is_empty()

func _apply_host_config_lock(locked: bool) -> void:
	_host_boar.disabled = locked
	_host_chicken.disabled = locked
	_host_boar.focus_mode = Control.FOCUS_NONE if locked else Control.FOCUS_ALL
	_host_chicken.focus_mode = Control.FOCUS_NONE if locked else Control.FOCUS_ALL
	_host_yard.disabled = locked
	_host_pit.disabled = locked
	_host_keep.disabled = locked
	_host_yard.focus_mode = Control.FOCUS_NONE if locked else Control.FOCUS_ALL
	_host_pit.focus_mode = Control.FOCUS_NONE if locked else Control.FOCUS_ALL
	_host_keep.focus_mode = Control.FOCUS_NONE if locked else Control.FOCUS_ALL
	_loop_slider.editable = not locked
	_record_hint.visible = locked
	if not locked:
		_record_hint.text = ""
	_refresh_mode_ui()

func _refresh_pick() -> void:
	GameRecords.load_from_disk()
	_clear_pick_rows()
	var card: Vector2 = _fit_card_size()
	_custom_button.custom_minimum_size = card
	for record: GameRecord in GameRecords.list_records():
		_pick_cards.add_child(_make_pick_card(record))
	_pick_cards.move_child(_custom_button, -1)
	_fit_pick_scroll()
	_pick_scroll.scroll_vertical = 0

func _clear_pick_rows() -> void:
	var stale: Array[Node] = []
	for child: Node in _pick_cards.get_children():
		if child == _custom_button:
			continue
		stale.append(child)
	for child: Node in stale:
		_pick_cards.remove_child(child)
		child.queue_free()

## 卡片宽度取 Content 的实际布局宽度（Page 已排版），按宽度排满 2～4 列；极早期为 0 时退回 Sheet 宽度推算。
func _content_width() -> float:
	var width: float = _content.size.x
	if width <= 1.0:
		width = _sheet.size.x + _column.offset_right - _column.offset_left
	return maxf(width, UiFit.MIN_CARD_WIDTH + UiFit.CARD_INSET)

func _fit_card_size() -> Vector2:
	var content_w: float = _content_width()
	var columns: int = UiFit.card_columns_for(content_w, 4)
	_pick_cards.columns = columns
	return UiFit.card_size(content_w, columns)

func _make_pick_card(record: GameRecord) -> Button:
	var card: Vector2 = _fit_card_size()
	var button: Button = RecordCard.make_main_card(record, card, UiFit.portrait_px(card))
	button.pressed.connect(_on_pick_record_pressed.bind(record.id))
	_wire_hover(button)
	return button

func _fit_pick_scroll() -> void:
	_pick_scroll.scroll_vertical = 0

func _collect_pick_cards() -> Array:
	var cards: Array = []
	for child: Node in _pick_cards.get_children():
		if child == _custom_button:
			cards.append(_custom_button)
			continue
		var button: Button = child as Button
		if button != null:
			cards.append(button)
	cards.append(_back_button)
	return cards

func _play_pick_enter() -> void:
	UiAnim.kill_tween(_anim_tween)
	_anim_tween = UiAnim.enter_cards(self, _collect_pick_cards())

func _focus_pick() -> void:
	var first: Node = _pick_cards.get_child(0)
	if first == _custom_button:
		_custom_button.grab_focus()
		return
	var button: Button = first as Button
	if button != null:
		button.grab_focus()
		return
	_back_button.grab_focus()

func _format_addresses() -> String:
	var lines: PackedStringArray = PackedStringArray()
	for addr: String in IP.get_local_addresses():
		if addr == "127.0.0.1":
			continue
		if addr.find(":") >= 0:
			continue
		lines.append(addr)
	if lines.is_empty():
		return "127.0.0.1"
	return "\n".join(lines)

func _fill_character(button: Button, character_id: String) -> void:
	var def: CharacterDef = CATALOG.get_by_id(StringName(character_id))
	var portrait: TextureRect = button.get_node("VBox/Portrait") as TextureRect
	var title: Label = button.get_node("VBox/Title") as Label
	var desc: Label = button.get_node("VBox/Desc") as Label
	if portrait != null:
		portrait.texture = FALLBACK_BODY
		if def != null and def.body_texture != null:
			portrait.texture = def.body_texture
	if title != null:
		title.text = def.display_name if def != null else character_id
	if desc != null:
		desc.text = def.description if def != null else ""

## 关网络：执行归 LobbyManager / LobbyNet，UI 只发命令 + 停自己的 Beacon。
func _clear_peer() -> void:
	_stop_beacon()
	if _lobby != null:
		_lobby.close_network()

func _on_host_resized() -> void:
	if not _open:
		return
	_fit_cards.call_deferred()

## Content 是 Page 里唯一随窗口变宽的那一段；它的 resized 带新宽度，比 host.resized 早一步可用。
func _on_content_resized() -> void:
	if not _open:
		return
	_fit_cards()

func _fit_cards() -> void:
	if _view != View.PICK:
		return
	var card: Vector2 = _fit_card_size()
	var portrait: float = UiFit.portrait_px(card)
	_custom_button.custom_minimum_size = card
	for child: Node in _pick_cards.get_children():
		var button: Button = child as Button
		if button == null:
			continue
		button.custom_minimum_size = card
		var portrait_rect: TextureRect = button.get_node_or_null("Content/Portrait") as TextureRect
		if portrait_rect != null:
			portrait_rect.custom_minimum_size = Vector2(portrait, portrait)

func _on_home_join_pressed() -> void:
	_play_click()
	_enter_join()

func _on_character_pressed(character_id: String) -> void:
	_play_click()
	_select_character(character_id)

func _on_lobby_character_pressed(character_id: String) -> void:
	if _is_lobby_frozen():
		_play_error()
		return
	_play_click()
	_selected_character_id = GameLaunch._sanitize_character_id(character_id)
	if _lobby != null:
		_lobby.set_local_character(_selected_character_id)
	_sync_lobby_character_buttons()

## Guest 的 Ready / Not Ready。按钮文案与真实状态都由 LobbyManager 快照驱动。
func _on_lobby_ready_pressed() -> void:
	if _is_lobby_frozen():
		_play_error()
		return
	if _lobby == null:
		return
	var was_ready: bool = _lobby.get_local_ready()
	var now_ready: bool = _lobby.toggle_local_ready()
	if now_ready:
		_play_click()
		_flash_lobby_ready()
	else:
		_play_back()
	_refresh_lobby_view()
	if was_ready == now_ready:
		_play_error()

func _on_invite_pressed() -> void:
	_play_click()
	# Invite 是 shell：本阶段只复制地址，不实现 WAN / token / QR 真连接。
	DisplayServer.clipboard_set(_format_addresses())

## Starting 冻结：已点 Start 之后不允许再改角色 / Ready / 房间设置。
func _is_lobby_frozen() -> bool:
	if _lobby == null:
		return true
	if _host_started:
		return true
	var snapshot: Dictionary = _lobby.get_snapshot()
	return int(snapshot.get("room_state", Room.RoomState.FORMING)) != int(Room.RoomState.FORMING)

func _flash_lobby_ready() -> void:
	var row: HBoxContainer = _local_lobby_row()
	if row == null:
		return
	UiAnim.flash_ready(self, row)

func _on_arena_pressed(arena_id: String) -> void:
	_play_click()
	_select_arena(arena_id)

func _wire_hover(button: BaseButton) -> void:
	if not button.mouse_entered.is_connected(_play_hover):
		button.mouse_entered.connect(_play_hover)
	if not button.focus_entered.is_connected(_play_hover):
		button.focus_entered.connect(_play_hover)
	if button.has_meta(&"lan_row_feedback"):
		return
	button.set_meta(&"lan_row_feedback", true)
	UiAnim.wire_row_feedback(self, button, UiType.INK)

func _play_hover() -> void:
	if not _open:
		return
	_play_stream(_hover_sfx, &"hover")

func _play_click() -> void:
	_play_stream(_click_sfx, &"click")

func _play_back() -> void:
	_play_stream(_back_sfx, &"back")

func _play_error() -> void:
	_play_stream(_error_sfx, &"error")

func _play_stream(player: AudioStreamPlayer, key: StringName) -> void:
	if player == null or player.stream == null:
		return
	var frame: int = Engine.get_process_frames()
	if int(_sfx_gate.get(key, -1)) == frame:
		return
	_sfx_gate[key] = frame
	player.play()

## Start 合同归 LobbyManager（Room 的 can_start + 有没有真实 peer 背书），UI 只读结果。
func _can_start() -> bool:
	return _lobby != null and _lobby.can_start()

## 占位人数（含 pending）：只读 LobbyManager 快照，UI 不维护第二份座位缓存。
func _occupied() -> int:
	if _lobby == null:
		return 0
	return int(_lobby.get_snapshot().get("occupied_count", 0))

func _refresh_host_status() -> void:
	_refresh_lobby_view()
	_sync_host_beacon()

func _hide_join_session_labels() -> void:
	_join_wait.visible = false
	_join_goal.visible = false
	_join_map.visible = false
	_join_mode.visible = false
	_join_seat.visible = false

func _ensure_beacon() -> void:
	if _beacon != null:
		return
	_beacon = LanBeacon.new()
	_beacon.rooms_changed.connect(_on_rooms_changed)
	add_child(_beacon)

func _stop_beacon() -> void:
	if _beacon == null:
		return
	_beacon.stop()
	_clear_room_cards()

func _start_host_beacon() -> void:
	if _view != View.HOST or _host_started:
		return
	_ensure_beacon()
	_beacon.start_host(_occupied(), GameLaunch.NET_MAX_SEATS, int(_net_play), _host_loop_goal(), GameLaunch._sanitize_arena_id(_selected_arena_id))

func _sync_host_beacon() -> void:
	if _view != View.HOST or _host_started or _beacon == null:
		return
	_beacon.update_host(_occupied(), GameLaunch.NET_MAX_SEATS, int(_net_play), _host_loop_goal(), GameLaunch._sanitize_arena_id(_selected_arena_id))

func _start_guest_beacon() -> void:
	if _view != View.JOIN or not _open:
		return
	_ensure_beacon()
	_beacon.start_guest()
	_rebuild_room_cards()

func _host_loop_goal() -> int:
	return maxi(roundi(_loop_slider.value), 0)

func _on_rooms_changed() -> void:
	if _view != View.JOIN:
		return
	_rebuild_room_cards()

func _on_join_search_changed(_text: String) -> void:
	if _view != View.JOIN:
		return
	_rebuild_room_cards()

func _rebuild_room_cards() -> void:
	_clear_room_cards()
	if _beacon != null and _beacon.has_bind_failed():
		_join_empty.text = "discover bind failed"
		_join_empty.visible = true
		return
	_join_empty.text = "no rooms"
	if _beacon == null:
		_join_empty.visible = true
		return
	var shown: int = 0
	for room: Dictionary in _beacon.get_rooms():
		if not _matches_room_query(room, _join_search.text):
			continue
		_join_cards.add_child(_make_room_card(room))
		shown += 1
	_join_empty.visible = shown == 0

func _clear_room_cards() -> void:
	if _join_cards == null:
		return
	var stale: Array[Node] = []
	for child: Node in _join_cards.get_children():
		stale.append(child)
	for child: Node in stale:
		_join_cards.remove_child(child)
		child.queue_free()

func _make_room_card(room: Dictionary) -> Button:
	var button: Button = Button.new()
	button.custom_minimum_size = Vector2(0, 72)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.theme_type_variation = &"EmptyButton"
	var full: bool = _is_room_full(room)
	button.disabled = full
	if full:
		button.modulate.a = 0.5
	button.add_child(_make_row_mark())
	button.add_child(_make_room_row(room))
	if full:
		button.gui_input.connect(_on_full_room_gui_input)
	else:
		button.pressed.connect(_on_room_card_pressed.bind(str(room["address"])))
	_wire_hover(button)
	return button

func _make_row_mark() -> ColorRect:
	var mark: ColorRect = ColorRect.new()
	mark.name = "Mark"
	mark.visible = false
	mark.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	mark.offset_top = -2.0
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mark.color = UiType.INK
	return mark

func _make_room_row(room: Dictionary) -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	row.name = "Text"
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 16.0
	row.offset_right = -16.0
	row.offset_bottom = -6.0
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 16)
	row.add_child(_make_room_title_label(str(room["address"])))
	row.add_child(_make_room_meta_label(room))
	row.add_child(_make_room_badge_label(room))
	return row

func _make_room_title_label(address: String) -> Label:
	var label: Label = Label.new()
	label.name = "Title"
	label.theme_type_variation = &"OfferTitle"
	label.text = address
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _make_room_meta_label(room: Dictionary) -> Label:
	var label: Label = Label.new()
	label.name = "Caption"
	label.theme_type_variation = &"Caption"
	label.text = _format_room_meta(room)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _make_room_badge_label(room: Dictionary) -> Label:
	var label: Label = Label.new()
	label.name = "Badge"
	label.theme_type_variation = &"StatValue"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.text = "%d/%d" % [int(room["occupied"]), int(room["max_seats"])]
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _format_room_meta(room: Dictionary) -> String:
	var arena_name: String = RecordCard.format_arena_name(str(room["arena_id"]))
	var is_battle: bool = int(room["net_play"]) == int(GameLaunch.NetPlay.BATTLE)
	var mode_name: String = "Battle" if is_battle else "Co-op"
	var loop_text: String = "battle" if is_battle else RecordCard.format_loop_badge(int(room["loop_goal"]))
	return "%s  ·  %s  ·  %s" % [arena_name, mode_name, loop_text]

func _is_room_full(room: Dictionary) -> bool:
	return int(room["occupied"]) >= int(room["max_seats"])

func _matches_room_query(room: Dictionary, query: String) -> bool:
	var needle: String = query.strip_edges().to_lower()
	if needle.is_empty():
		return true
	var haystacks: PackedStringArray = PackedStringArray()
	haystacks.append(str(room["address"]).to_lower())
	haystacks.append(RecordCard.format_arena_name(str(room["arena_id"])).to_lower())
	if int(room["net_play"]) == int(GameLaunch.NetPlay.BATTLE):
		haystacks.append("battle")
	else:
		haystacks.append("coop")
		haystacks.append("co-op")
	haystacks.append("%d/%d" % [int(room["occupied"]), int(room["max_seats"])])
	for hay: String in haystacks:
		if hay.find(needle) >= 0:
			return true
	return false

func _on_room_card_pressed(address: String) -> void:
	if _view != View.JOIN:
		return
	_join_edit.text = address
	_on_connect_pressed()

func _on_full_room_gui_input(event: InputEvent) -> void:
	if _view != View.JOIN:
		return
	if not (event is InputEventMouseButton):
		return
	var mouse: InputEventMouseButton = event as InputEventMouseButton
	if not mouse.pressed or mouse.button_index != MOUSE_BUTTON_LEFT:
		return
	_play_error()
