extends SceneTree

## LAN UI 换场 E2E —— Guest 端真进程（由 tools/ci/lan_start_ui_run.py 拉起，不单独跑）。
##
## 这是唯一能证明本 bug 真被修好的路径：真进程 + 真 ENet + 真 ui/main_menu.tscn。
## 旧 tools/ci/lan_e2e_guest.gd 只断言 room_state == STARTING，那在 bug 存在时也为真，
## 所以它必须看到 current_scene 变成 CombatSandbox 才算数。
##
## 用法：godot --headless --path . --script res://tools/ci/lan_start_ui_guest.gd -- <result_file>

const TIMEOUT_MS: int = 40000
const SANDBOX_MARKER: String = "CombatSandbox"

var _result_path: String = ""
var _menu: Node = null
var _overlay: LanOverlay = null
var _manager: LobbyManager = null
var _done: bool = false
var _deadline: int = 0
var _phase: int = 0
var _ready_sent: bool = false
var _saw_starting: bool = false

func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < 1:
		printerr("UI_GUEST_FAIL -: 缺少 result_file")
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
	## 两条合同都必须接上：LobbyManager.match_started -> LanOverlay，以及
	## LanOverlay.start_lan -> MainMenu。缺任一条 Guest 都切不了场。
	if not _overlay.start_lan.is_connected(_menu._enter_lan):
		_fail("MainMenu 没把 start_lan 接到 _enter_lan")
		return
	if not _manager.match_started.is_connected(_overlay._on_lobby_match_started):
		_fail("LanOverlay 没把 match_started 接到 _on_lobby_match_started（本 bug）")
		return
	## 走真实 UI：开叠层 -> JOIN 页，把 Host 的 invite 文本粘进地址栏 -> CONNECT。
	## 粘贴的是完整 wpg:// URI，因此会走 JoinInvite + ticket 全链路（而不是裸地址）。
	var uri: String = _read_invite_uri()
	if uri.is_empty():
		_fail("读不到 Host invite")
		return
	_overlay.open()
	_overlay._enter_join()
	_overlay._join_edit.text = uri
	_overlay._connect_button.pressed.emit()
	_wait()

## 同目录的 host.result.invite：Host 写、Guest 读。
func _read_invite_uri() -> String:
	var path: String = _result_path.replace("guest.result", "host.result") + ".invite"
	for _attempt: int in 100:
		if FileAccess.file_exists(path):
			var file: FileAccess = FileAccess.open(path, FileAccess.READ)
			if file != null:
				var text: String = file.get_as_text().strip_edges()
				file.close()
				if not text.is_empty():
					return text
		OS.delay_msec(50)
	return ""

func _wait() -> void:
	if _done:
		return
	if _deadline == 0:
		_deadline = Time.get_ticks_msec() + TIMEOUT_MS
	if _tick():
		if not _done:
			_done = true
			_write_result("OK")
			print("UI_GUEST_OK")
			quit(0)
		return
	if Time.get_ticks_msec() > _deadline:
		_fail("超时（phase=%d scene=%s starting=%s）" % [_phase, _scene_name(), _saw_starting])
		return
	create_timer(0.05).timeout.connect(_wait)

func _tick() -> bool:
	## 真 · 换场判据：房间状态不算数，必须看到 CombatSandbox 真的成为 current_scene。
	if _scene_name() == SANDBOX_MARKER:
		return true
	## 换场会 change_scene_to_file，旧 MainMenu 连同其子节点 LobbyManager 一起被释放；
	## 此时若还有一次 timer 回调在飞，直接摸 _manager 会踩空指针崩进程，
	## 让「其实已经成功换场」表现成假崩溃。先确认对象还活着。
	if not is_instance_valid(_manager) or not is_instance_valid(_overlay):
		return false
	var room: Room = _manager.get_room()
	if room == null or _manager.get_local_seat() <= 1:
		return false
	match _phase:
		0:
			## 落座且 Guest 自己的 Lobby 页真的可见，再按 READY。
			if not _overlay.is_open() or _overlay._view != LanOverlay.View.LOBBY:
				return false
			_phase = 1
			return false
		1:
			_overlay._on_lobby_ready_pressed()
			_ready_sent = true
			_phase = 2
			return false
		2:
			## Host 开局后会广播 begin -> LobbyManager 进 STARTING -> match_started。
			## 记录「看见了 STARTING」只为区分「状态到了但没换场」这种失败形态。
			if room.room_state == Room.RoomState.STARTING:
				_saw_starting = true
			return false
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
	printerr("UI_GUEST_FAIL: %s" % reason)
	quit(1)

func _write_result(text: String) -> void:
	var file: FileAccess = FileAccess.open(_result_path, FileAccess.WRITE)
	if file == null:
		printerr("UI_GUEST_FAIL: 无法写结果文件 %s" % _result_path)
		return
	file.store_string(text)
	file.close()
