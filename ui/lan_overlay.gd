extends Control
class_name LanOverlay

## 主菜单局域网叠层。MULTIPLAYER 首页：Quick join / Create room / LAN rooms / Join invite / Recent。
## 大厅 Host 听 17778，Guest 探针；座位 1～5，第三人进房不踢，满 5 才踢。禁止 Autoload，禁止 AcceptDialog。
signal start_lan

enum View { HOME, PICK, HOST, JOIN, INVITE, LOBBY }

const CATALOG: CharacterCatalog = preload("res://data/character_catalog.tres")
const FALLBACK_BODY: Texture2D = preload("res://images/player.png")
const CHAR_BOAR := "boar"
const CHAR_CHICKEN := "chicken"
const DEFAULT_LOOP_GOAL: int = 20
const SEAT_ROW_HEIGHT: float = 22.0
## Recent 最多 3 行（screen spec §9），只保留本机最近几个房间（内存里的一次会话记录，不落盘、不上服务器）。
const RECENT_LIMIT: int = 3
## 首页导航行高：行式导航，不是大胶囊。
const HOME_ROW_HEIGHT: float = 54.0

var _open: bool = false
var _view: View = View.HOME
var _anim_tween: Tween
var _sfx_gate: Dictionary = {}
var _selected_character_id: String = CHAR_BOAR
var _host_started: bool = false
var _picked_record_id: String = ""
var _selected_arena_id: String = "yard"
var _net_play: GameLaunch.NetPlay = GameLaunch.NetPlay.COOP
var _privacy: Room.Privacy = Room.Privacy.LAN_VISIBLE
## 最近房间（本机内存，见 RECENT_LIMIT）。元素：address / arena_id / net_play / loop_goal / occupied / max_seats。
var _recent_rooms: Array[Dictionary] = []
## 首页导航行（代码生成，见 _build_home_nav）：行顺序 = 焦点顺序。
var _home_rows: Array[Button] = []
var _row_create: Button = null
var _row_join_invite: Button = null
var _row_lan_rooms: Button = null
var _row_quick_join: Button = null
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
@onready var _home_nav: VBoxContainer = $Sheet/Column/Content/HomeRoot/Column/Nav
@onready var _recent_title: Label = $Sheet/Column/Content/HomeRoot/Column/RecentTitle
@onready var _recent_list: VBoxContainer = $Sheet/Column/Content/HomeRoot/Column/Recent
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
@onready var _host_lan_visible: Button = $Sheet/Column/Content/HostRoot/Body/Right/Privacy/LanVisible
@onready var _host_invite_only: Button = $Sheet/Column/Content/HostRoot/Body/Right/Privacy/InviteOnly
@onready var _join_form: VBoxContainer = $Sheet/Column/Content/JoinRoot/Row/Form
@onready var _join_browse: VBoxContainer = $Sheet/Column/Content/JoinRoot/Row/Browse
@onready var _copy_invite_button: Button = $Sheet/Column/Content/JoinRoot/Row/Form/InviteShell/CopyInvite
@onready var _show_qr_button: Button = $Sheet/Column/Content/JoinRoot/Row/Form/InviteShell/ShowQr
@onready var _invite_notice: Label = $Sheet/Column/Content/JoinRoot/Row/Form/InviteNotice
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
	_host_lan_visible.pressed.connect(_on_privacy_pressed.bind(Room.Privacy.LAN_VISIBLE))
	_host_invite_only.pressed.connect(_on_privacy_pressed.bind(Room.Privacy.INVITE_ONLY))
	_copy_invite_button.pressed.connect(_on_copy_invite_pressed)
	_show_qr_button.pressed.connect(_on_show_qr_pressed)
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
	for button: Button in [_create_room_button, _custom_button, _host_boar, _host_chicken, _host_yard, _host_pit, _host_keep, _host_coop, _host_battle, _host_lan_visible, _host_invite_only, _start_button, _connect_button, _copy_invite_button, _show_qr_button, _join_boar, _join_chicken, _lobby_boar, _lobby_chicken, _lobby_ready, _lobby_invite, _host_invite, _back_button]:
		_wire_hover(button)
	UiFit.connect_refit(self, _on_host_resized)
	_content.resized.connect(_on_content_resized)
	_build_seat_rows()
	_build_guest_seat_rows()
	_build_borrow_record_button()
	_build_home_nav()
	_ensure_beacon()
	_join_search.text_changed.connect(_on_join_search_changed)
	_enter_multiplayer()

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
	if not _lobby.network_failed.is_connected(_on_lobby_network_failed):
		_lobby.network_failed.connect(_on_lobby_network_failed)
	if not _lobby.joined_lobby.is_connected(_on_lobby_joined):
		_lobby.joined_lobby.connect(_on_lobby_joined)
	_refresh_lobby_view()

## Guest 握手完成（座位已分配 + 本地投影建好）→ 进 Lobby 核心页。
## 之前 _enter_lobby() 没有任何调用点，Guest 的 Lobby 页在真机上永远看不到。
func _on_lobby_joined() -> void:
	if _open:
		_enter_lobby()

## 连接失败 / 协议不符 / Host 关闭：就在当前页的状态行写明原因，不再开第二个大面板。
## 已进 Lobby 的失败（Host closed）退回邀请页，1.0 不做 reconnect。
func _on_lobby_network_failed(reason: String) -> void:
	if not _open:
		return
	if _view == View.HOST:
		_host_status.text = reason
		_play_error()
		return
	if _view == View.JOIN or _view == View.INVITE:
		_join_status.text = reason
		_connect_button.disabled = false
		_play_error()
		return
	if _view == View.LOBBY:
		# 先切页再写文案：_enter_invite() 会清空状态行。
		_enter_invite()
		_join_status.text = reason
		_play_error()

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

## 座位墙：5 行固定结构 + 一行表头，只按 Room 快照改字，不重建节点。
## 三列固定列宽（PLAYER / CHARACTER / STATE），左对齐成表，不随页面宽度把字拉到两头。
func _build_seat_rows() -> void:
	_build_rows_into(_seats, _seat_rows)

func _build_guest_seat_rows() -> void:
	_build_rows_into(_lobby_seats, _guest_seat_rows)

func _build_rows_into(container: VBoxContainer, store: Array[HBoxContainer]) -> void:
	store.clear()
	if not container.has_node("SeatHeader"):
		container.add_child(_make_seat_header())
	for seat: int in range(1, GameLaunch.NET_MAX_SEATS + 1):
		var row: HBoxContainer = HBoxContainer.new()
		row.name = "Seat%d" % seat
		row.custom_minimum_size = Vector2(0, SEAT_ROW_HEIGHT)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_theme_constant_override("separation", 16)
		row.add_child(_make_seat_label("Name", &"OfferTitle", 200.0, Control.SIZE_SHRINK_BEGIN, HORIZONTAL_ALIGNMENT_LEFT))
		row.add_child(_make_seat_label("Character", &"OfferDesc", 110.0, Control.SIZE_SHRINK_BEGIN, HORIZONTAL_ALIGNMENT_LEFT))
		row.add_child(_make_seat_label("State", &"StatValue", 96.0, Control.SIZE_SHRINK_BEGIN, HORIZONTAL_ALIGNMENT_LEFT))
		container.add_child(row)
		store.append(row)

## 座位表头：列宽与座位行严格一致（PLAYER / CHARACTER / STATE），压暗当表头用，别像第 0 个玩家。
func _make_seat_header() -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	row.name = "SeatHeader"
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.modulate.a = 0.5
	row.add_theme_constant_override("separation", 16)
	row.add_child(_make_seat_label("Name", &"Caption", 200.0, Control.SIZE_SHRINK_BEGIN, HORIZONTAL_ALIGNMENT_LEFT))
	row.add_child(_make_seat_label("Character", &"Caption", 110.0, Control.SIZE_SHRINK_BEGIN, HORIZONTAL_ALIGNMENT_LEFT))
	row.add_child(_make_seat_label("State", &"Caption", 96.0, Control.SIZE_SHRINK_BEGIN, HORIZONTAL_ALIGNMENT_LEFT))
	(row.get_node("Name") as Label).text = "PLAYER"
	(row.get_node("Character") as Label).text = "CHARACTER"
	(row.get_node("State") as Label).text = "STATE"
	return row

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
	var character_label: Label = row.get_node("Character") as Label
	var state_label: Label = row.get_node("State") as Label
	if not bool(seat_data.get("occupied", false)):
		name_label.text = "EMPTY SEAT"
		character_label.text = ""
		state_label.text = ""
		## 空位压暗，别让 4 行 EMPTY SEAT 抢走 PLAYERS 的注意力。
		row.modulate.a = 0.35
		return
	row.modulate.a = 1.0
	var display_name: String = str(seat_data.get("display_name", "")).to_upper()
	name_label.text = display_name if not display_name.is_empty() else "CONNECTING"
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
	var starting: bool = int(snapshot.get("room_state", Room.RoomState.FORMING)) == int(Room.RoomState.STARTING)
	_lobby_connection.text = "STARTING  ·  ALL PLAYERS READY  ·  LAUNCHING..." if starting else "%s  ·  %s" % ["LAN" if networked else "OFFLINE", _connection_word(snapshot)]
	_sync_lobby_character_buttons()
	var local_ready: bool = bool(snapshot.get("local_ready", false))
	_lobby_ready.disabled = starting
	_lobby_boar.disabled = starting
	_lobby_chicken.disabled = starting
	_lobby_ready.text = "STARTING" if starting else ("NOT READY" if local_ready else "READY")
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
	if int(snapshot.get("room_state", Room.RoomState.FORMING)) == int(Room.RoomState.STARTING):
		return "starting · launching"
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
	_enter_multiplayer()
	UiAnim.kill_tween(_anim_tween)
	_anim_tween = UiAnim.enter_page(self, _dimmer, _sheet, false, direction)
	if _row_create != null:
		_row_create.grab_focus()

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
	if (_view == View.JOIN or _view == View.INVITE) and (_join_edit.has_focus() or _join_search.has_focus()):
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

## Back 栈：Lobby / Create room / LAN rooms / Join invite → MULTIPLAYER 首页；首页 → 关叠层。
## 已联网先离房 + 关网络（Guest 断线离房，Host 离房即关房；1.0 不做 reconnect / Host 迁移）。
## 已开战（_host_started）交给换场，这时不再动房间。
func _handle_back() -> void:
	_play_back()
	if _view == View.PICK:
		_enter_host()
		return
	if _view == View.HOME:
		close(-1)
		return
	if _view == View.LOBBY and _host_started:
		close(-1)
		return
	if _view == View.LOBBY:
		# Guest 已进 Lobby：Back = 断线离房 + 淡出，再回多人大厅。
		_leave_lobby_room()
		_clear_peer()
		_exit_lobby()
		return
	_leave_lobby_room()
	_clear_peer()
	_enter_multiplayer()

## 离开 HOST 视图 / 关页 = 离房。Host 离房即关房（1.0 不做 Host 迁移）。
## 已开战（_host_started）时不碰房间，交给换场。
func _leave_lobby_room() -> void:
	if _host_started or _lobby == null or not _lobby.has_room():
		return
	_lobby.leave_room()

func _show_home(_animate: bool) -> void:
	_picked_record_id = ""
	_reset_play_mode()
	_enter_multiplayer()

## MULTIPLAYER 首页：行式导航（Create room / Join invite / LAN rooms / Quick join）+ RECENT。
## screen spec §9：三条同级导航是**行**不是大卡，行间一条分隔线，右侧一句 caption + 箭头；
## Recent 最多 3 行，没有就整段不出现。Quick join 只基于已有 LAN discovery。
func _enter_multiplayer() -> void:
	_view = View.HOME
	_home_root.visible = true
	_pick_root.visible = false
	_host_root.visible = false
	_join_root.visible = false
	_lobby_root.visible = false
	_refresh_recent()
	_start_guest_beacon()
	_refresh_home_captions()
	if _open and _row_create != null:
		_row_create.grab_focus()

## 建首页四行导航（行内容在代码里生成：右侧 caption 要跟着 Beacon 结果变）。
func _build_home_nav() -> void:
	if _home_nav == null or _row_create != null:
		return
	_row_create = _make_home_row("CREATE ROOM", "HOST A GAME", _on_home_host_pressed)
	_row_join_invite = _make_home_row("JOIN INVITE", "IP / INVITE", _on_home_invite_pressed)
	_row_lan_rooms = _make_home_row("LAN ROOMS", "SEARCHING", _on_home_join_pressed)
	_row_quick_join = _make_home_row("QUICK JOIN", "FIRST OPEN ROOM", _on_quick_join_pressed)
	_home_rows = [_row_create, _row_join_invite, _row_lan_rooms, _row_quick_join]
	for index: int in _home_rows.size():
		if index > 0:
			_home_nav.add_child(_make_nav_divider())
		_home_nav.add_child(_home_rows[index])

## 一行导航：左标题 + 右 caption + 箭头，行间靠分隔线，不套卡片边框。
func _make_home_row(title: String, caption: String, handler: Callable) -> Button:
	var row: Button = Button.new()
	row.custom_minimum_size = Vector2(0, HOME_ROW_HEIGHT)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.theme_type_variation = &"EmptyButton"
	row.add_child(_make_row_mark())
	var text_row: HBoxContainer = HBoxContainer.new()
	text_row.name = "Text"
	text_row.set_anchors_preset(Control.PRESET_FULL_RECT)
	text_row.offset_left = 4.0
	text_row.offset_right = -4.0
	text_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_row.add_theme_constant_override("separation", 24)
	text_row.add_child(_make_row_label("Title", &"OfferTitle", title, Control.SIZE_EXPAND_FILL, HORIZONTAL_ALIGNMENT_LEFT))
	text_row.add_child(_make_row_label("Caption", &"Caption", caption, Control.SIZE_SHRINK_END, HORIZONTAL_ALIGNMENT_RIGHT))
	var arrow: Label = _make_row_label("Arrow", &"StatValue", "→", Control.SIZE_SHRINK_END, HORIZONTAL_ALIGNMENT_RIGHT)
	arrow.custom_minimum_size = Vector2(28, 0)
	text_row.add_child(arrow)
	row.add_child(text_row)
	row.pressed.connect(handler)
	_wire_hover(row)
	return row

func _make_row_label(node_name: String, variation: StringName, text: String, size_flags: int, align: int) -> Label:
	var label: Label = Label.new()
	label.name = node_name
	label.theme_type_variation = variation
	label.text = text
	label.size_flags_horizontal = size_flags
	label.horizontal_alignment = align
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

## 行间分隔线：与页面 TopLine 同一条骨白细线（结构色令牌，不写魔法颜色）。
func _make_nav_divider() -> ColorRect:
	var line: ColorRect = ColorRect.new()
	line.custom_minimum_size = Vector2(0, 1)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.color = UiType.STRUCTURE
	return line

## 首页右侧 caption：LAN 行报发现数量（发现口绑定失败时说清楚），其余是固定说明。
func _refresh_home_captions() -> void:
	if _row_lan_rooms == null:
		return
	var caption: String = "LAN ROOMS"
	if _beacon != null and _beacon.has_bind_failed():
		caption = "DISCOVER BIND FAILED"
	elif _beacon != null:
		var count: int = _beacon.get_rooms().size()
		caption = "%d ON THIS LAN" % count if count > 0 else "NONE FOUND YET"
	_row_caption(_row_lan_rooms).text = caption
	_row_caption(_row_quick_join).text = "FIRST OPEN ROOM" if _has_open_room() else "NO OPEN ROOM"

func _row_caption(row: Button) -> Label:
	return row.get_node("Text/Caption") as Label

func _has_open_room() -> bool:
	if _beacon == null:
		return false
	for room: Dictionary in _beacon.get_rooms():
		if not _is_room_full(room):
			return true
	return false

## CREATE ROOM：借档改成页内显式入口，不再挡在建房前面。
func _on_home_host_pressed() -> void:
	if not _open:
		return
	if _view != View.HOME and _view != View.JOIN and _view != View.PICK:
		return
	_play_click()
	_enter_host()

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
	_host_lan_visible.button_pressed = _privacy == Room.Privacy.LAN_VISIBLE
	_host_invite_only.button_pressed = _privacy == Room.Privacy.INVITE_ONLY
	_lobby.set_privacy(_privacy)
	_remember_room(_primary_address(), _selected_arena_id, int(_net_play), _host_loop_goal(), _occupied(), GameLaunch.NET_MAX_SEATS)
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
	_lobby_root.modulate.a = 1.0
	_refresh_lobby_view()
	# 进 Lobby 用行级错峰淡入（与 PICK 的卡片入场同一套意图）。
	var tween: Tween = UiAnim.enter_stagger_fade(self, _guest_seat_rows)
	if tween != null:
		## 淡入结束再按快照重画一次：空位行 0.5 的暗度不会被 tween 抹平成 1.0。
		tween.finished.connect(_restore_seat_row_tone)
	if not _is_lobby_frozen():
		_lobby_ready.grab_focus()

func _restore_seat_row_tone() -> void:
	if _open and _view == View.LOBBY and not _lobby_notice_playing:
		_refresh_lobby_view()

## 退 Lobby：先把 Lobby 页淡掉，再回 MULTIPLAYER 首页（与进入的错峰淡入对称）。
func _exit_lobby() -> void:
	var tween: Tween = UiAnim.fade_modulate(self, _lobby_root, 0.0, 0.15, true)
	if tween == null:
		_finish_lobby_exit()
		return
	tween.finished.connect(_finish_lobby_exit)

func _finish_lobby_exit() -> void:
	if not _open:
		return
	_lobby_root.modulate.a = 1.0
	_enter_multiplayer()

## 建房先于 bind：房间是领域状态，有没有 ENet peer 只是它的一种形态（离线 mock / 真 LAN）。
## 命令与网络执行都归 LobbyManager / LobbyNet，UI 不碰 ENet。
## LAN ROOMS：只画同网段广播出来的房间（紧凑行，JOIN / FULL）。手动表单归 JOIN INVITE。
func _enter_join() -> void:
	_view = View.JOIN
	_home_root.visible = false
	_pick_root.visible = false
	_host_root.visible = false
	_lobby_root.visible = false
	_join_root.visible = true
	_join_browse.visible = true
	_join_form.visible = false
	_reset_character()
	_join_status.text = ""
	_hide_join_session_labels()
	_connect_button.disabled = false
	if not _open:
		return
	_start_guest_beacon()
	_join_search.grab_focus()

## JOIN INVITE：手打 / 粘贴邀请文本 + 选角。Invite shell 只有复制与 QR 占位，不做真连接。
func _enter_invite() -> void:
	_view = View.INVITE
	_home_root.visible = false
	_pick_root.visible = false
	_host_root.visible = false
	_lobby_root.visible = false
	_join_root.visible = true
	_join_browse.visible = false
	_join_form.visible = true
	_reset_character()
	_join_edit.text = GameLaunch.DEFAULT_JOIN_ADDRESS
	_join_status.text = ""
	_invite_notice.text = ""
	_hide_join_session_labels()
	_connect_button.disabled = false
	if _open:
		_join_edit.grab_focus()

func _on_home_invite_pressed() -> void:
	_play_click()
	_enter_invite()

## Quick join：加入当前可用的 LAN 房间（第一个不满的）。只基于已有 LAN discovery。
func _on_quick_join_pressed() -> void:
	if not _open:
		return
	_play_click()
	_ensure_beacon()
	if _beacon != null:
		for room: Dictionary in _beacon.get_rooms():
			if _is_room_full(room):
				continue
			_connect_to_room(room)
			return
	_enter_join()
	_join_status.text = "searching"
	_play_error()

## 从 LAN 房间行 / Quick join 进房：地址与房间事实都来自发现包，顺便记进 RECENT。
func _connect_to_room(room: Dictionary) -> void:
	_join_edit.text = str(room["address"])
	_remember_room(
		str(room["address"]),
		str(room["arena_id"]),
		int(room["net_play"]),
		int(room["loop_goal"]),
		int(room["occupied"]),
		int(room["max_seats"])
	)
	_enter_join()
	_on_connect_pressed()

## 隐私只决定「要不要对外广播 LAN 信标」：INVITE ONLY 一律停掉信标（架构规则 8）。
func _on_privacy_pressed(privacy: Room.Privacy) -> void:
	_play_click()
	_privacy = privacy
	_host_lan_visible.button_pressed = privacy == Room.Privacy.LAN_VISIBLE
	_host_invite_only.button_pressed = privacy == Room.Privacy.INVITE_ONLY
	if _lobby != null:
		_lobby.set_privacy(privacy)
	_sync_host_beacon()

## Copy invite：复制本机 LAN 地址（shell，不生成 token / 不做 WAN）。
func _on_copy_invite_pressed() -> void:
	_play_click()
	DisplayServer.clipboard_set(_format_addresses())
	_invite_notice.text = "invite copied"

## Show QR：本阶段只有 shell —— JoinInvite / token 落地前不画真二维码。
func _on_show_qr_pressed() -> void:
	_play_click()
	_invite_notice.text = "QR shell · 协议 8 再接"

## 粘贴进来的邀请文本可能带前缀 / 端口：先按 IPv4 解析，解析不到再当主机名原样用。
func _resolve_join_address(raw: String) -> String:
	var parsed: String = LobbyNet.parse_address(raw)
	if not parsed.is_empty():
		return parsed
	return raw.strip_edges()

func _on_connect_pressed() -> void:
	if _view != View.JOIN and _view != View.INVITE:
		return
	_play_click()
	var address: String = _resolve_join_address(_join_edit.text)
	_join_edit.text = address
	if address.is_empty():
		_join_status.text = "no address"
		_play_error()
		return
	if _view == View.JOIN:
		_start_guest_beacon()
	_join_status.text = "connecting"
	_hide_join_session_labels()
	_connect_button.disabled = true
	# 连接执行归 LobbyNet（经 LobbyManager 命令），UI 不建 peer。
	if _lobby == null or not _lobby.join_room_address(address):
		_join_status.text = "refused"
		_connect_button.disabled = false
		_play_error()

## CREATE ROOM 页内的借档入口：放进 ROOM SETTINGS 那一竖列（与其它房间设置同一列宽），
## 排在 START 之前，不再挡在建房前面。
func _build_borrow_record_button() -> void:
	var right: VBoxContainer = $Sheet/Column/Content/HostRoot/Body/Right
	if right.has_node("BorrowRecord"):
		return
	var button: Button = Button.new()
	button.name = "BorrowRecord"
	button.custom_minimum_size = Vector2(0, 44)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.theme_type_variation = &"PillNeutral"
	button.text = "Use a record"
	button.pressed.connect(_on_borrow_record_pressed)
	right.add_child(button)
	right.move_child(button, _start_button.get_index())
	_wire_hover(button)

## 借档 = 用已有档当种子开房（Phase 3 的 DoD），仍然只种子 Room，不上网、不写档。
func _on_borrow_record_pressed() -> void:
	if _view != View.HOST:
		return
	_play_click()
	GameRecords.load_from_disk()
	if GameRecords.list_records().is_empty():
		_play_error()
		return
	_enter_pick()

# ---- RECENT（本机内存，不上服务器、不落盘）----

func _remember_room(address: String, arena_id: String, net_play: int, loop_goal: int, occupied: int, max_seats: int) -> void:
	var addr: String = address.strip_edges()
	if addr.is_empty():
		return
	var entry: Dictionary = {
		"address": addr,
		"arena_id": GameLaunch._sanitize_arena_id(arena_id),
		"net_play": net_play,
		"loop_goal": maxi(loop_goal, 0),
		"occupied": maxi(occupied, 1),
		"max_seats": maxi(max_seats, GameLaunch.NET_MAX_SEATS),
	}
	for index: int in _recent_rooms.size():
		var existing: Dictionary = _recent_rooms[index]
		if str(existing.get("address", "")) == addr and int(existing.get("net_play", 0)) == net_play:
			_recent_rooms.remove_at(index)
			break
	_recent_rooms.push_front(entry)
	while _recent_rooms.size() > RECENT_LIMIT:
		_recent_rooms.pop_back()
	_refresh_recent()

func _refresh_recent() -> void:
	if _recent_list == null or _recent_title == null:
		return
	for child: Node in _recent_list.get_children():
		_recent_list.remove_child(child)
		child.queue_free()
	var has_any: bool = not _recent_rooms.is_empty()
	_recent_title.visible = has_any
	_recent_list.visible = has_any
	if not has_any:
		return
	for entry: Dictionary in _recent_rooms:
		_recent_list.add_child(_make_recent_row(entry))

## Recent 行与导航行同一套版式：左地址（协议 5 不带房主名），右「n/5 · Mode · Arena」。
func _make_recent_row(entry: Dictionary) -> Button:
	return _make_home_row(
		str(entry["address"]),
		"%d/%d  ·  %s  ·  %s" % [
			int(entry["occupied"]),
			int(entry["max_seats"]),
			_mode_name(int(entry["net_play"])),
			RecordCard.format_arena_name(str(entry["arena_id"])),
		],
		_on_recent_pressed.bind(str(entry["address"])),
	)

func _on_recent_pressed(address: String) -> void:
	_play_click()
	_enter_invite()
	_join_edit.text = address
	_on_connect_pressed()

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
		"started":
			return "STARTING..."
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

## 本机对外地址的第一条（RECENT 里只记一个，不记整张地址表）。
func _primary_address() -> String:
	var lines: PackedStringArray = _format_addresses().split("\n", false)
	return lines[0] if not lines.is_empty() else "127.0.0.1"

## 角色卡是紧凑横排：Card(HBox) = Portrait + Text(VBox: Title / Desc)。
func _fill_character(button: Button, character_id: String) -> void:
	var def: CharacterDef = CATALOG.get_by_id(StringName(character_id))
	var portrait: TextureRect = button.get_node_or_null("Card/Portrait") as TextureRect
	var title: Label = button.get_node_or_null("Card/Text/Title") as Label
	var desc: Label = button.get_node_or_null("Card/Text/Desc") as Label
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
	if _view == View.INVITE:
		_invite_notice.text = "invite copied"

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
	if _view != View.HOST or _host_started or _privacy != Room.Privacy.LAN_VISIBLE:
		return
	_ensure_beacon()
	_beacon.start_host(_occupied(), GameLaunch.NET_MAX_SEATS, int(_net_play), _host_loop_goal(), GameLaunch._sanitize_arena_id(_selected_arena_id))

## INVITE ONLY = 不发信标（房间还在，只是同网段发现不到）。
func _sync_host_beacon() -> void:
	if _host_started or _view != View.HOST:
		return
	if _privacy != Room.Privacy.LAN_VISIBLE:
		_stop_beacon()
		return
	if _beacon == null:
		return
	_beacon.update_host(_occupied(), GameLaunch.NET_MAX_SEATS, int(_net_play), _host_loop_goal(), GameLaunch._sanitize_arena_id(_selected_arena_id))

## Guest 探针在 MULTIPLAYER 首页 / LAN ROOMS / JOIN INVITE 都跑（Quick join 要靠它）。
func _start_guest_beacon() -> void:
	if not _open or _view == View.HOST or _view == View.PICK:
		return
	_ensure_beacon()
	_beacon.start_guest()
	if _view == View.JOIN:
		_rebuild_room_cards()

func _host_loop_goal() -> int:
	return maxi(roundi(_loop_slider.value), 0)

func _on_rooms_changed() -> void:
	# 首页要更新 LAN ROOMS / QUICK JOIN 两行的 caption；LAN ROOMS 页要重画房间列表。
	if _view == View.HOME:
		_refresh_home_captions()
		return
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
		button.pressed.connect(_on_room_card_pressed.bind(room))
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
	row.add_child(_make_room_title_label(room))
	row.add_child(_make_room_address_label(str(room["address"])))
	row.add_child(_make_room_meta_label(room))
	row.add_child(_make_room_badge_label(room))
	row.add_child(_make_room_action_label(room))
	return row

## 主标题：协议 5 的发现包不带 Host 显示名，先写房间；地址放次级 caption。
func _make_room_title_label(_room: Dictionary) -> Label:
	var label: Label = Label.new()
	label.name = "Title"
	label.theme_type_variation = &"OfferTitle"
	label.text = "ROOM"
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _make_room_address_label(address: String) -> Label:
	var label: Label = Label.new()
	label.name = "Address"
	label.theme_type_variation = &"Caption"
	label.text = address
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

## 行尾动作：JOIN / FULL（满员的房间按钮本身 disabled，这里再给一次明确文案）。
func _make_room_action_label(room: Dictionary) -> Label:
	var label: Label = Label.new()
	label.name = "Action"
	label.theme_type_variation = &"StatValue"
	label.custom_minimum_size = Vector2(72, 0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.text = "FULL" if _is_room_full(room) else "JOIN"
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _make_room_meta_label(room: Dictionary) -> Label:
	var label: Label = Label.new()
	label.name = "Meta"
	label.theme_type_variation = &"OfferDesc"
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

func _on_room_card_pressed(room: Dictionary) -> void:
	if _view != View.JOIN:
		return
	_connect_to_room(room)

func _on_full_room_gui_input(event: InputEvent) -> void:
	if _view != View.JOIN:
		return
	if not (event is InputEventMouseButton):
		return
	var mouse: InputEventMouseButton = event as InputEventMouseButton
	if not mouse.pressed or mouse.button_index != MOUSE_BUTTON_LEFT:
		return
	_play_error()
