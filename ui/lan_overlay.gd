extends Control
class_name LanOverlay

## 主菜单局域网叠层：HOME / PICK / HOST / JOIN。Host 可借已有档预填角色、loop_goal 和地图，联机仍不写档。禁止 Autoload，禁止 AcceptDialog。
signal start_lan

enum View { HOME, PICK, HOST, JOIN }

const CATALOG: CharacterCatalog = preload("res://data/character_catalog.tres")
const FALLBACK_BODY: Texture2D = preload("res://images/player.png")
const CHAR_BOAR := "boar"
const CHAR_CHICKEN := "chicken"
const DEFAULT_LOOP_GOAL: int = 20

var _open: bool = false
var _view: View = View.HOME
var _anim_tween: Tween
var _sfx_gate: Dictionary = {}
var _selected_character_id: String = CHAR_BOAR
var _guest_character_id: String = CHAR_BOAR
var _guest_id: int = 0
var _handshake_ok: bool = false
var _host_started: bool = false
var _picked_record_id: String = ""
var _selected_arena_id: String = "yard"
var _net_play: GameLaunch.NetPlay = GameLaunch.NetPlay.COOP

@onready var _dimmer: ColorRect = $Dimmer
@onready var _panel: PanelContainer = $Center/Panel
@onready var _home_root: Control = $Center/Panel/Column/Content/HomeRoot
@onready var _pick_root: Control = $Center/Panel/Column/Content/PickRoot
@onready var _host_root: Control = $Center/Panel/Column/Content/HostRoot
@onready var _join_root: Control = $Center/Panel/Column/Content/JoinRoot
@onready var _host_button: Button = $Center/Panel/Column/Content/HomeRoot/Center/Column/Host
@onready var _join_button: Button = $Center/Panel/Column/Content/HomeRoot/Center/Column/Join
@onready var _pick_scroll: ScrollContainer = $Center/Panel/Column/Content/PickRoot/Scroll
@onready var _pick_cards: GridContainer = $Center/Panel/Column/Content/PickRoot/Scroll/Cards
@onready var _custom_button: Button = $Center/Panel/Column/Content/PickRoot/Scroll/Cards/Custom
@onready var _host_address: Label = $Center/Panel/Column/Content/HostRoot/Center/Column/AddressList
@onready var _host_status: Label = $Center/Panel/Column/Content/HostRoot/Center/Column/Status
@onready var _record_hint: Label = $Center/Panel/Column/Content/HostRoot/Center/Column/RecordHint
@onready var _host_boar: Button = $Center/Panel/Column/Content/HostRoot/Center/Column/Characters/Boar
@onready var _host_chicken: Button = $Center/Panel/Column/Content/HostRoot/Center/Column/Characters/Chicken
@onready var _host_yard: Button = $Center/Panel/Column/Content/HostRoot/Center/Column/Arenas/Yard
@onready var _host_pit: Button = $Center/Panel/Column/Content/HostRoot/Center/Column/Arenas/Pit
@onready var _host_keep: Button = $Center/Panel/Column/Content/HostRoot/Center/Column/Arenas/Keep
@onready var _host_coop: Button = $Center/Panel/Column/Content/HostRoot/Center/Column/Modes/Coop
@onready var _host_battle: Button = $Center/Panel/Column/Content/HostRoot/Center/Column/Modes/Battle
@onready var _loop_slider: HSlider = $Center/Panel/Column/Content/HostRoot/Center/Column/LoopRow/Slider
@onready var _loop_label: Label = $Center/Panel/Column/Content/HostRoot/Center/Column/LoopRow/LoopLabel
@onready var _start_button: Button = $Center/Panel/Column/Content/HostRoot/Center/Column/Start
@onready var _join_edit: LineEdit = $Center/Panel/Column/Content/JoinRoot/Center/Column/Address
@onready var _connect_button: Button = $Center/Panel/Column/Content/JoinRoot/Center/Column/Connect
@onready var _join_status: Label = $Center/Panel/Column/Content/JoinRoot/Center/Column/Status
@onready var _join_boar: Button = $Center/Panel/Column/Content/JoinRoot/Center/Column/Characters/Boar
@onready var _join_chicken: Button = $Center/Panel/Column/Content/JoinRoot/Center/Column/Characters/Chicken
@onready var _join_goal: Label = $Center/Panel/Column/Content/JoinRoot/Center/Column/GoalLabel
@onready var _join_map: Label = $Center/Panel/Column/Content/JoinRoot/Center/Column/MapLabel
@onready var _join_mode: Label = $Center/Panel/Column/Content/JoinRoot/Center/Column/ModeLabel
@onready var _join_wait: Label = $Center/Panel/Column/Content/JoinRoot/Center/Column/WaitingLabel
@onready var _back_button: Button = $Center/Panel/Column/Back
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
	_loop_slider.value_changed.connect(_on_loop_changed)
	_start_button.pressed.connect(_on_start_pressed)
	_connect_button.pressed.connect(_on_connect_pressed)
	_back_button.pressed.connect(_handle_back)
	for button: Button in [_host_button, _join_button, _custom_button, _host_boar, _host_chicken, _host_yard, _host_pit, _host_keep, _host_coop, _host_battle, _start_button, _connect_button, _join_boar, _join_chicken, _back_button]:
		_wire_hover(button)
	UiFit.connect_refit(self, _on_host_resized)
	_show_home(false)

func _exit_tree() -> void:
	_unwire_multiplayer()

func is_open() -> bool:
	return _open

func open() -> void:
	_open = true
	visible = true
	modulate.a = 1.0
	mouse_filter = Control.MOUSE_FILTER_STOP
	_picked_record_id = ""
	_reset_play_mode()
	_fit_panel()
	_show_home(true)
	UiAnim.kill_tween(_anim_tween)
	_anim_tween = UiAnim.enter_overlay(self, _dimmer, _panel, [_host_button, _join_button, _back_button])
	_host_button.grab_focus()

func close() -> void:
	if not _open:
		return
	_open = false
	_picked_record_id = ""
	_clear_peer()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiAnim.kill_tween(_anim_tween)
	_anim_tween = UiAnim.exit_overlay(self, self)
	_anim_tween.finished.connect(_finish_close)
	var play: Button = get_parent().get_node_or_null("Center/Column/Buttons/Play") as Button
	if play != null:
		play.grab_focus()

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
	if _view == View.HOME or _view == View.PICK:
		return
	if _is_host_locked():
		return
	if _view == View.JOIN and _join_edit.has_focus():
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

func _handle_back() -> void:
	_play_back()
	if _view == View.HOME:
		close()
		return
	if _view == View.PICK:
		_show_home(true)
		return
	_clear_peer()
	if _view == View.HOST and not _picked_record_id.is_empty():
		_enter_pick()
		return
	_show_home(true)

func _show_home(animate: bool) -> void:
	_view = View.HOME
	_picked_record_id = ""
	_reset_play_mode()
	_pick_root.visible = false
	_host_root.visible = false
	_join_root.visible = false
	_home_root.visible = true
	if animate:
		UiAnim.kill_tween(_anim_tween)
		_anim_tween = UiAnim.enter_overlay(self, _dimmer, null, [_host_button, _join_button, _back_button])
		_host_button.grab_focus()

func _on_home_host_pressed() -> void:
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
	_view = View.PICK
	_home_root.visible = false
	_host_root.visible = false
	_join_root.visible = false
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
	_host_root.visible = true
	_host_address.text = _format_addresses()
	_host_status.text = "waiting"
	_handshake_ok = false
	_guest_id = 0
	_guest_character_id = CHAR_BOAR
	_refresh_host_start()
	if not _create_server():
		_host_status.text = "bind failed"
		_play_error()
		_refresh_host_start()
		return
	_wire_multiplayer()
	if _picked_record_id.is_empty():
		_host_boar.grab_focus()
		return
	_back_button.grab_focus()

func _enter_join() -> void:
	_view = View.JOIN
	_home_root.visible = false
	_pick_root.visible = false
	_host_root.visible = false
	_join_root.visible = true
	_reset_character()
	_join_edit.text = GameLaunch.DEFAULT_JOIN_ADDRESS
	_join_status.text = ""
	_join_goal.visible = false
	_join_map.visible = false
	_join_mode.visible = false
	_join_wait.visible = false
	_connect_button.disabled = false
	_wire_multiplayer()
	_join_edit.grab_focus()

func _create_server() -> bool:
	_clear_peer()
	var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	var err: Error = peer.create_server(GameLaunch.NET_PORT, 2)
	if err != OK:
		return false
	multiplayer.multiplayer_peer = peer
	return true

func _on_connect_pressed() -> void:
	if _view != View.JOIN:
		return
	_play_click()
	_clear_peer()
	_join_status.text = "connecting"
	_join_wait.visible = false
	_join_goal.visible = false
	_join_map.visible = false
	_join_mode.visible = false
	_connect_button.disabled = true
	var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	var err: Error = peer.create_client(_join_edit.text.strip_edges(), GameLaunch.NET_PORT)
	if err != OK:
		_join_status.text = "refused"
		_connect_button.disabled = false
		return
	multiplayer.multiplayer_peer = peer
	_wire_multiplayer()

func _wire_multiplayer() -> void:
	if not multiplayer.peer_connected.is_connected(_on_peer_connected):
		multiplayer.peer_connected.connect(_on_peer_connected)
	if not multiplayer.peer_disconnected.is_connected(_on_peer_disconnected):
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	if not multiplayer.connected_to_server.is_connected(_on_connected_to_server):
		multiplayer.connected_to_server.connect(_on_connected_to_server)
	if not multiplayer.connection_failed.is_connected(_on_connection_failed):
		multiplayer.connection_failed.connect(_on_connection_failed)
	if not multiplayer.server_disconnected.is_connected(_on_server_disconnected):
		multiplayer.server_disconnected.connect(_on_server_disconnected)

func _unwire_multiplayer() -> void:
	if multiplayer.peer_connected.is_connected(_on_peer_connected):
		multiplayer.peer_connected.disconnect(_on_peer_connected)
	if multiplayer.peer_disconnected.is_connected(_on_peer_disconnected):
		multiplayer.peer_disconnected.disconnect(_on_peer_disconnected)
	if multiplayer.connected_to_server.is_connected(_on_connected_to_server):
		multiplayer.connected_to_server.disconnect(_on_connected_to_server)
	if multiplayer.connection_failed.is_connected(_on_connection_failed):
		multiplayer.connection_failed.disconnect(_on_connection_failed)
	if multiplayer.server_disconnected.is_connected(_on_server_disconnected):
		multiplayer.server_disconnected.disconnect(_on_server_disconnected)

func _on_peer_connected(id: int) -> void:
	if not multiplayer.is_server():
		return
	if multiplayer.get_peers().size() > 1:
		multiplayer.multiplayer_peer.disconnect_peer(id)
		return
	_guest_id = id
	_handshake_ok = false
	_host_status.text = "waiting"
	_refresh_host_start()
	rpc_hello.rpc_id(id, GameLaunch.NET_PROTOCOL)

func _on_peer_disconnected(id: int) -> void:
	if not multiplayer.is_server():
		return
	if id != _guest_id:
		return
	_guest_id = 0
	_handshake_ok = false
	_guest_character_id = CHAR_BOAR
	_host_status.text = "waiting"
	_refresh_host_start()

func _on_connected_to_server() -> void:
	if _view != View.JOIN:
		return
	_join_status.text = "connected"
	rpc_guest_character.rpc_id(1, _selected_character_id)

func _on_connection_failed() -> void:
	_join_status.text = "refused"
	_connect_button.disabled = false
	_join_wait.visible = false
	_join_mode.visible = false
	_clear_peer()

func _on_server_disconnected() -> void:
	if _host_started:
		return
	if _join_status.text != "Version mismatch":
		_join_status.text = "refused"
	_connect_button.disabled = false
	_join_wait.visible = false
	_join_goal.visible = false
	_join_map.visible = false
	_join_mode.visible = false
	_clear_peer()

@rpc("authority", "call_remote", "reliable")
func rpc_hello(protocol: int) -> void:
	if protocol != GameLaunch.NET_PROTOCOL:
		_join_status.text = "Version mismatch"
		_connect_button.disabled = false
		_clear_peer()
		return
	rpc_hello_ok.rpc_id(1)
	_join_status.text = "connected"
	_join_wait.visible = true
	_join_wait.text = "waiting for host"
	rpc_guest_character.rpc_id(1, _selected_character_id)

@rpc("any_peer", "call_remote", "reliable")
func rpc_hello_ok() -> void:
	if not multiplayer.is_server():
		return
	if multiplayer.get_remote_sender_id() != _guest_id:
		return
	_handshake_ok = true
	_host_status.text = "guest connected"
	_refresh_host_start()
	_push_session_to_guest()

@rpc("any_peer", "call_remote", "reliable")
func rpc_guest_character(character_id: String) -> void:
	if not multiplayer.is_server():
		return
	if multiplayer.get_remote_sender_id() != _guest_id:
		return
	_guest_character_id = GameLaunch._sanitize_character_id(character_id)

@rpc("authority", "call_remote", "reliable")
func rpc_begin(host_character_id: String, guest_character_id: String, loop_goal: int, arena_id: String, net_play: int) -> void:
	_host_started = true
	GameLaunch.set_net_role(GameLaunch.NetRole.GUEST)
	GameLaunch.set_join_address(_join_edit.text)
	GameLaunch.set_lan_loadout(host_character_id, guest_character_id, loop_goal)
	GameLaunch.set_arena_id(arena_id)
	GameLaunch.set_net_play(_play_from_net(net_play))
	start_lan.emit()

@rpc("authority", "call_remote", "reliable")
func rpc_goal(loop_goal: int) -> void:
	_join_goal.visible = true
	if loop_goal > 0:
		_join_goal.text = "goal  %d" % loop_goal
		return
	_join_goal.text = "goal  Inf"

@rpc("authority", "call_remote", "reliable")
func rpc_arena(arena_id: String) -> void:
	var id: String = GameLaunch._sanitize_arena_id(arena_id)
	_join_map.visible = true
	_join_map.text = "map  %s" % RecordCard.format_arena_name(id)

@rpc("authority", "call_remote", "reliable")
func rpc_play_mode(net_play: int) -> void:
	_join_mode.visible = true
	if net_play == int(GameLaunch.NetPlay.BATTLE):
		_join_mode.text = "mode  Battle"
		return
	_join_mode.text = "mode  Co-op"

func _on_start_pressed() -> void:
	if not _handshake_ok or _guest_id == 0:
		return
	_play_click()
	var loop_goal: int = maxi(roundi(_loop_slider.value), 0)
	var arena_id: String = GameLaunch._sanitize_arena_id(_selected_arena_id)
	GameLaunch.set_net_role(GameLaunch.NetRole.HOST)
	GameLaunch.set_lan_loadout(_selected_character_id, _guest_character_id, loop_goal)
	GameLaunch.set_arena_id(arena_id)
	GameLaunch.set_net_play(_net_play)
	_host_started = true
	rpc_goal.rpc_id(_guest_id, loop_goal)
	rpc_play_mode.rpc_id(_guest_id, int(_net_play))
	rpc_begin.rpc_id(_guest_id, _selected_character_id, _guest_character_id, loop_goal, arena_id, int(_net_play))
	start_lan.emit()

func _on_loop_changed(_value: float) -> void:
	_refresh_loop_label()
	if _handshake_ok and _guest_id != 0:
		rpc_goal.rpc_id(_guest_id, maxi(roundi(_loop_slider.value), 0))

func _select_character(character_id: String) -> void:
	_selected_character_id = GameLaunch._sanitize_character_id(character_id)
	_host_boar.button_pressed = _selected_character_id == CHAR_BOAR
	_host_chicken.button_pressed = _selected_character_id == CHAR_CHICKEN
	_join_boar.button_pressed = _selected_character_id == CHAR_BOAR
	_join_chicken.button_pressed = _selected_character_id == CHAR_CHICKEN
	if _view == View.JOIN and multiplayer.multiplayer_peer != null:
		rpc_guest_character.rpc_id(1, _selected_character_id)

func _select_arena(arena_id: String) -> void:
	_selected_arena_id = GameLaunch._sanitize_arena_id(arena_id)
	_host_yard.button_pressed = _selected_arena_id == "yard"
	_host_pit.button_pressed = _selected_arena_id == "pit"
	_host_keep.button_pressed = _selected_arena_id == "keep"
	if _handshake_ok and _guest_id != 0:
		rpc_arena.rpc_id(_guest_id, _selected_arena_id)

func _push_session_to_guest() -> void:
	if not _handshake_ok or _guest_id == 0:
		return
	rpc_goal.rpc_id(_guest_id, maxi(roundi(_loop_slider.value), 0))
	rpc_arena.rpc_id(_guest_id, GameLaunch._sanitize_arena_id(_selected_arena_id))
	rpc_play_mode.rpc_id(_guest_id, int(_net_play))

func _reset_character() -> void:
	_select_character(CHAR_BOAR)

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
	_refresh_mode_ui()
	if _handshake_ok and _guest_id != 0:
		rpc_play_mode.rpc_id(_guest_id, int(_net_play))

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
	var can_start: bool = _handshake_ok and _guest_id != 0
	_start_button.disabled = not can_start
	_start_button.focus_mode = Control.FOCUS_ALL if can_start else Control.FOCUS_NONE

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

func _fit_card_size() -> Vector2:
	var panel_w: float = _panel.custom_minimum_size.x
	var columns: int = UiFit.card_columns(panel_w)
	_pick_cards.columns = columns
	return UiFit.card_size(panel_w, columns)

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
	_anim_tween = UiAnim.enter_overlay(self, null, null, _collect_pick_cards())

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

func _clear_peer() -> void:
	_unwire_multiplayer()
	_guest_id = 0
	_handshake_ok = false
	if _host_started:
		return
	var peer: MultiplayerPeer = multiplayer.multiplayer_peer
	if peer != null:
		peer.close()
	multiplayer.multiplayer_peer = null

func _on_host_resized() -> void:
	if not _open:
		return
	_fit_panel()

func _fit_panel() -> void:
	UiFit.apply_floating_panel(self, _panel)
	if _view != View.PICK:
		return
	var card: Vector2 = _fit_card_size()
	_custom_button.custom_minimum_size = card
	for child: Node in _pick_cards.get_children():
		var button: Button = child as Button
		if button != null:
			button.custom_minimum_size = card

func _on_home_join_pressed() -> void:
	_play_click()
	_enter_join()

func _on_character_pressed(character_id: String) -> void:
	_play_click()
	_select_character(character_id)

func _on_arena_pressed(arena_id: String) -> void:
	_play_click()
	_select_arena(arena_id)

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
