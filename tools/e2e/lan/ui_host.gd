extends SceneTree

## LAN UI 换场 E2E —— Host 端真进程（由 tools/e2e/lan/ui_run.py 拉起，不单独跑）。
##
## 与 tools/e2e/lan/host.gd 的区别：那个 peer 只驱动 LobbyManager，证明不了
## 「UI 换场闭环」——它从不实例化 MainMenu / LanOverlay，也不等 CombatSandbox。
## 本 peer 起真实 ui/main_menu.tscn，按真实按钮路径 Create Room -> Guest READY -> START，
## 然后断言：
##   1. current_scene 真的变成 CombatSandbox；
##   2. 换场后 multiplayer_peer 仍然活着（LOBBY -> BATTLE peer 交接没被 close 掐断）；
##   3. Host 座位 = 1、role = HOST；
##   4. 从 Battle 退回菜单后 multiplayer_peer 被清空（无残留 peer）。
##
## 用法：godot --headless --path . --script res://tools/e2e/lan/ui_host.gd -- <result_file>

const TIMEOUT_MS: int = 50000
const SANDBOX_MARKER: String = "CombatSandbox"
const MENU_MARKER: String = "MainMenu"
## CombatSandbox 刚进场的头几帧还在建 pawn / 绑 roster，等它稳定下来再断言。
const SETTLE_MS: int = 1200

var _result_path: String = ""
var _menu: Node = null
var _overlay: LanOverlay = null
var _manager: LobbyManager = null
var _done: bool = false
var _deadline: int = 0
var _phase: int = 0
var _started: bool = false
var _sandbox_at: int = -1

func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < 1:
		printerr("UI_HOST_FAIL -: 缺少 result_file")
		quit(1)
		return
	_result_path = args[0]
	_run.call_deferred()

func _run() -> void:
	PlayerProfile.load_from_disk()
	var packed: PackedScene = load("res://ui/main_menu.tscn") as PackedScene
	if packed == null:
		_fail("main_menu.tscn 加载失败")
		return
	_menu = packed.instantiate()
	root.add_child(_menu)
	current_scene = _menu
	_manager = _menu.get_node_or_null("LobbyManager") as LobbyManager
	_overlay = _menu.get_node_or_null("LanOverlay") as LanOverlay
	if _manager == null or _overlay == null:
		_fail("主菜单缺 LobbyManager / LanOverlay")
		return
	## Start 是 LanOverlay 的 signal，必须有接线，否则 Host 也切不了场。
	if not _overlay.start_lan.is_connected(_menu._enter_lan):
		_fail("MainMenu 没把 start_lan 接到 _enter_lan")
		return
	if not _manager.host_room("yard", GameLaunch.NetPlay.COOP, 20):
		_fail("host_room 失败（17777 被占？）")
		return
	_overlay.open()
	_overlay._enter_host()
	## 协议 6：Guest 必须拿到本房 invite（含 ticket）才能进房。
	## 真按钮路径（Copy Invite -> get_invite_uri）必须能产出可解析的 LAN invite。
	var ui_uri: String = _overlay.get_invite_uri()
	var parsed_ui: JoinInvite = JoinInvite.parse(ui_uri)
	if ui_uri.is_empty() or not parsed_ui.is_valid():
		_fail("LanOverlay 没生成可解析的 invite URI")
		return
	if parsed_ui.version != GameLaunch.NET_PROTOCOL:
		_fail("LanOverlay invite 协议号不是 %d（%d）" % [GameLaunch.NET_PROTOCOL, parsed_ui.version])
		return
	## 连接用的 invite 强制走 127.0.0.1：本机可能有多个网卡，_primary_address() 选中的
	## 局域网 IP 在 CI / sandbox 里不一定回环可达。地址换成回环不影响要验证的东西
	##（protocol 6 + ticket + Ready + 换场 + peer 交接），invite 依旧由 LobbyManager 生成。
	var loopback_uri: String = _manager.create_invite("127.0.0.1", GameLaunch.NET_PORT).to_uri()
	if loopback_uri.is_empty():
		_fail("LobbyManager 生成回环 invite 失败")
		return
	_write_marker(_result_path + ".invite", loopback_uri)
	## 监听已建立：编排方据此才起 Guest，避免抢跑。
	_write_marker(_result_path + ".ready")
	_wait()

func _wait() -> void:
	if _done:
		return
	if _deadline == 0:
		_deadline = Time.get_ticks_msec() + TIMEOUT_MS
	if _tick():
		if not _done:
			_done = true
			_write_result(_ok_line())
			print("UI_HOST_OK")
			quit(0)
		return
	if Time.get_ticks_msec() > _deadline:
		_fail("超时（phase=%d started=%s scene=%s）" % [_phase, _started, _scene_name()])
		return
	create_timer(0.05).timeout.connect(_wait)

func _tick() -> bool:
	match _phase:
		0:
			return _tick_lobby()
		1:
			return _tick_lan_preserved()
		2:
			return _tick_wait_guest_ready()
		3:
			return _tick_cleanup()
	return false

## phase 0：等 Guest 落座、READY，然后走真实按钮 START。
func _tick_lobby() -> bool:
	var room: Room = _manager.get_room()
	if room == null or room.player_count() != 2:
		return false
	var guest: LobbyPlayer = room.get_player_in_seat(2)
	if guest == null or not guest.ready:
		return false
	if not _manager.can_start():
		return false
	_started = true
	_overlay._on_start_pressed()
	_phase = 1
	return false

## phase 1：真 · 换场判据 —— current_scene 必须变成 CombatSandbox，且 peer 活着。
func _tick_lan_preserved() -> bool:
	if _scene_name() != SANDBOX_MARKER:
		return false
	if _sandbox_at < 0:
		_sandbox_at = Time.get_ticks_msec()
		return false
	if Time.get_ticks_msec() - _sandbox_at < SETTLE_MS:
		return false
	var sandbox: Node = current_scene
	if not _has_live_peer():
		_fail("进 CombatSandbox 后没有活的 multiplayer_peer（换场把 peer 掐断了）")
		return false
	if int(sandbox.get("_net_role")) != int(GameLaunch.NetRole.HOST):
		_fail("Host 换场后 role 不是 HOST（%s）" % str(sandbox.get("_net_role")))
		return false
	if int(sandbox.get("_local_seat")) != Room.HOST_SEAT:
		_fail("Host 换场后座位不是 1（%s）" % str(sandbox.get("_local_seat")))
		return false
	## 通知 Guest：Host 已在 Battle 里站稳（peer 活着）。Guest 据此才准许退回菜单，
	## 否则 Guest 先关连接会让 Host 的 _on_peer_lost 把 LAN 房降级成 Solo（peer 被清空）。
	_write_marker(_result_path + ".battle", "OK scene=%s peer=live seat=1" % SANDBOX_MARKER)
	## 再等 Guest 也在 Battle 里站稳（它写 guest.result.battle），然后退回菜单。
	## 否则 Host 先关 peer 会把 Guest 打成 server_disconnected，掩盖换场问题。
	_phase = 2
	return false

## phase 2：等 Guest 的 Battle 就绪标记，然后从 Battle 退回菜单（等价于暂停页 Quit）。
func _tick_wait_guest_ready() -> bool:
	if not FileAccess.file_exists(_guest_battle_marker()):
		return false
	var sandbox: Node = current_scene
	if sandbox != null and sandbox.name == SANDBOX_MARKER:
		sandbox.call("_return_to_menu")
	_phase = 3
	return false

## phase 3：退回菜单后必须没有残留 peer。
func _tick_cleanup() -> bool:
	if _scene_name() != MENU_MARKER:
		return false
	if not _has_no_network_peer():
		_fail("退回菜单后仍有活的 multiplayer_peer（残留 peer）")
		return false
	return true

## Guest 端写的 Battle 就绪标记：与 Guest 共用同一结果目录。
func _guest_battle_marker() -> String:
	return _result_path.replace("host.result", "guest.result") + ".battle"

func _ok_line() -> String:
	return "OK scene=%s peer=released seat=%d cleanup=ok" % [SANDBOX_MARKER, Room.HOST_SEAT]

## Godot 启动时 multiplayer_peer 默认是 OfflineMultiplayerPeer（非 null）。
## 「有没有真正的网络 peer」必须排除它。
func _has_live_peer() -> bool:
	var peer: MultiplayerPeer = root.multiplayer.multiplayer_peer
	if peer == null or peer is OfflineMultiplayerPeer:
		return false
	## ENet 的「对象还在」不等于「连接还活着」：Host 关服后 Guest 手里的
	## ENetMultiplayerPeer 还在，但状态已经不是 CONNECTED。必须按连接状态判定。
	if peer is ENetMultiplayerPeer:
		return peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED
	return true

func _has_no_network_peer() -> bool:
	return not _has_live_peer()

func _scene_name() -> String:
	var scene: Node = current_scene
	if scene == null:
		return ""
	return scene.name

func _fail(reason: String) -> void:
	if _done:
		return
	_done = true
	_write_result("FAIL: %s" % reason)
	printerr("UI_HOST_FAIL: %s" % reason)
	quit(1)

func _write_result(text: String) -> void:
	_write_marker(_result_path, text)

func _write_marker(path: String, text: String = "ready") -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		printerr("UI_HOST_FAIL: 无法写 %s" % path)
		return
	file.store_string(text)
	file.close()
