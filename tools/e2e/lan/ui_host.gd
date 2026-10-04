extends SceneTree

## LAN UI 换场 E2E —— Host 端真进程（由 tools/e2e/lan/ui_run.py 拉起，不单独跑）。
##
## 与 tools/e2e/lan/host.gd 的区别：那个 peer 只驱动 LobbyManager，证明不了
## 「UI 换场闭环」——它从不实例化 MainMenu / LanOverlay，也不等 CombatSandbox。
## 本 peer 起真实 ui/main_menu.tscn，按真实按钮路径 Create Room -> Guest READY -> START，
## 最后断言 current_scene 真的变成 CombatSandbox。
##
## 用法：godot --headless --path . --script res://tools/e2e/lan/ui_host.gd -- <result_file>

const TIMEOUT_MS: int = 40000
const SANDBOX_MARKER: String = "CombatSandbox"

var _result_path: String = ""
var _menu: Node = null
var _overlay: LanOverlay = null
var _manager: LobbyManager = null
var _done: bool = false
var _deadline: int = 0
var _started: bool = false

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
	## UI 侧走的就是真按钮路径（Copy Invite -> get_invite_uri），这里把结果交接给 Guest 进程。
	var uri: String = _overlay.get_invite_uri()
	if uri.is_empty():
		_fail("LanOverlay 没生成 invite URI")
		return
	var parsed: JoinInvite = JoinInvite.parse(uri)
	if not parsed.is_valid():
		_fail("LanOverlay 产出的 invite 无法解析")
		return
	_write_marker(_result_path + ".invite", uri)
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
			_write_result("OK")
			print("UI_HOST_OK")
			quit(0)
		return
	if Time.get_ticks_msec() > _deadline:
		_fail("超时（started=%s scene=%s）" % [_started, _scene_name()])
		return
	create_timer(0.05).timeout.connect(_wait)

func _tick() -> bool:
	## 换场一旦真的发生，current_scene 会被 LoadingScreen 换成 CombatSandbox。
	if _scene_name() == SANDBOX_MARKER:
		return true
	if _started:
		return false
	var room: Room = _manager.get_room()
	if room == null or room.player_count() != 2:
		return false
	var guest: LobbyPlayer = room.get_player_in_seat(2)
	if guest == null or not guest.ready:
		return false
	if not _manager.can_start():
		return false
	## 走真实按钮：和玩家点 START 完全同一条路径。
	_started = true
	_overlay._on_start_pressed()
	return false

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
