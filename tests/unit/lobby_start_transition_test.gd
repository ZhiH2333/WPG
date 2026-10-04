extends SceneTree

## Lobby Start 换场回归：LobbyManager.match_started -> Guest LanOverlay -> 恰好一次 start_lan。
##
## 修的 bug：bind_lobby() 少连 match_started，Guest 收到 Host 的 begin 后
## Room.room_state 已经是 STARTING，但没有任何地方把它翻成 start_lan，
## 于是 MainMenu._enter_lan() -> _leave_to_sandbox() 永不触发，Guest 卡在 Lobby。
## LAN_E2E_OK 只能证明 LobbyManager 进了 STARTING，证明不了 UI 换场闭环，所以单独补这一刀。
##
## 本测试只测 LanOverlay 这一层的翻译动作：不发 RPC、不 bind 端口、不碰 ENet，
## 房间与角色全部复用 LobbyManager / Room 的既有真实 API（join_remote / host_room），
## 不重造第二套 Lobby fake。
## 跑法：godot --headless --path . --script res://tests/lobby_start_transition_test.gd
## 通过输出 LOBBY_START_TRANSITION_OK；失败逐条 LOBBY_START_TRANSITION_FAIL 并返回非 0。

var _failures: PackedStringArray = PackedStringArray()

func _initialize() -> void:
	# UI 节点与 LanBeacon 都需要 SceneTree 已经建好（同 multiplayer_page_test 的理由）。
	_run_all.call_deferred()

func _run_all() -> void:
	PlayerProfile.load_from_disk()
	_case_guest_match_started_fires_start_lan_once()
	_case_host_match_started_does_not_fire()
	_case_host_real_start_match_still_fires_once()
	_case_closed_overlay_does_not_fire()
	_case_non_lobby_view_does_not_fire()
	_case_guest_real_lobby_flow_needs_no_main_menu()
	_case_bind_is_idempotent()
	_finish()

# ---- 用例 ----

## CASE A：Guest / overlay open / View = LOBBY -> match_started 恰好 1 次 start_lan。
func _case_guest_match_started_fires_start_lan_once() -> void:
	var overlay: LanOverlay = _make_overlay()
	var manager: LobbyManager = _make_guest_manager(overlay)
	overlay.open()
	overlay._enter_lobby()
	var counter: StartLanCounter = _count_start_lan(overlay)

	manager.match_started.emit()

	_expect(counter.count == 1, "Guest 在 LOBBY 收到 match_started：start_lan 恰好触发 1 次（实际 %d）" % counter.count)
	_expect(overlay._host_started, "Guest 换场后置 _host_started")
	_teardown(overlay, manager)

## CASE B：Host -> match_started 不得触发 start_lan。
## Host 的换场只由 _on_start_pressed() 里那次 start_lan 负责；
## 而 start_match() 内部同步 emit match_started 时 _host_started 还没赋值，
## 所以这里同时验证「按 is_host() 判权限」而不是按 _host_started 判重。
func _case_host_match_started_does_not_fire() -> void:
	var overlay: LanOverlay = _make_overlay()
	var manager: LobbyManager = _make_host_manager(overlay)
	overlay.open()
	overlay._enter_lobby()
	var counter: StartLanCounter = _count_start_lan(overlay)

	manager.match_started.emit()

	_expect(counter.count == 0, "Host 收到 match_started：不重复 start_lan（实际 %d）" % counter.count)
	_teardown(overlay, manager)

## CASE B2：Host 真实开局路径（start_match 内部 emit）依然只切一次场。
func _case_host_real_start_match_still_fires_once() -> void:
	var overlay: LanOverlay = _make_overlay()
	var manager: LobbyManager = _make_host_manager(overlay)
	overlay.open()
	overlay._enter_lobby()
	var counter: StartLanCounter = _count_start_lan(overlay)

	overlay._on_start_pressed()

	_expect(counter.count == 1, "Host 按 Start：start_lan 恰好 1 次，不被 match_started 二次触发（实际 %d）" % counter.count)
	_teardown(overlay, manager)

## CASE C：overlay 已关 -> 不响应。
func _case_closed_overlay_does_not_fire() -> void:
	var overlay: LanOverlay = _make_overlay()
	var manager: LobbyManager = _make_guest_manager(overlay)
	overlay.open()
	overlay._enter_lobby()
	var counter: StartLanCounter = _count_start_lan(overlay)

	overlay.close()

	manager.match_started.emit()

	_expect(counter.count == 0, "overlay 已关：match_started 不触发 start_lan（实际 %d）" % counter.count)
	_teardown(overlay, manager)

## CASE D：Guest 但当前不是 LOBBY 页（例如还在邀请页）-> 不响应。
func _case_non_lobby_view_does_not_fire() -> void:
	var overlay: LanOverlay = _make_overlay()
	var manager: LobbyManager = _make_guest_manager(overlay)
	overlay.open()
	overlay._enter_invite()
	var counter: StartLanCounter = _count_start_lan(overlay)

	manager.match_started.emit()

	_expect(counter.count == 0, "View != LOBBY：match_started 不触发 start_lan（实际 %d）" % counter.count)

	## 同一个 overlay 进 LOBBY 后必须能正常响应，证明上面那次是视图门挡掉的、不是连接漏了。
	overlay._enter_lobby()
	manager.match_started.emit()
	_expect(counter.count == 1, "同一 overlay 进 LOBBY 后 match_started 恢复生效（实际 %d）" % counter.count)
	_teardown(overlay, manager)

## CASE E：走真实 Guest 进 Lobby 流程（joined_lobby -> _on_lobby_joined -> _enter_lobby），
## 收到 match_started 后 LanOverlay 自己发 start_lan，不需要任何人手动调 MainMenu。
func _case_guest_real_lobby_flow_needs_no_main_menu() -> void:
	var overlay: LanOverlay = _make_overlay()
	var manager: LobbyManager = _make_guest_manager(overlay)
	overlay.open()

	var counter: StartLanCounter = _count_start_lan(overlay)
	## 真实握手完成信号：这条路径自己会进 Lobby 页，测试不手动 _enter_lobby()。
	manager.joined_lobby.emit()
	_expect(overlay._view == LanOverlay.View.LOBBY, "joined_lobby 后 Guest 自己在 Lobby 页")

	manager.match_started.emit()

	_expect(counter.count == 1, "Guest 真实进房流程：match_started 后 LanOverlay 自发 start_lan（实际 %d）" % counter.count)
	_teardown(overlay, manager)

## bind_lobby 必须幂等：重复 bind 不能把 match_started 连成两条（否则一次开局切两次场）。
func _case_bind_is_idempotent() -> void:
	var overlay: LanOverlay = _make_overlay()
	var manager: LobbyManager = _make_guest_manager(overlay)
	overlay.open()
	overlay._enter_lobby()

	overlay.bind_lobby(manager)
	overlay.bind_lobby(manager)

	var counter: StartLanCounter = _count_start_lan(overlay)
	manager.match_started.emit()

	_expect(counter.count == 1, "重复 bind_lobby 后 match_started 仍只触发 1 次（实际 %d）" % counter.count)
	_teardown(overlay, manager)

# ---- 夹具 ----

## 与 multiplayer_page_test 同款：真实 lan_overlay.tscn + 真实 LobbyManager/LobbyNet。
func _make_overlay() -> LanOverlay:
	var packed: PackedScene = load("res://ui/lan_overlay.tscn") as PackedScene
	_expect(packed != null, "lan_overlay.tscn 能加载")
	var overlay: LanOverlay = packed.instantiate() as LanOverlay
	root.add_child(overlay)
	return overlay

## Guest 角色：离线本地投影房，不 bind 端口、不碰 ENet。
func _make_guest_manager(overlay: LanOverlay) -> LobbyManager:
	var manager: LobbyManager = LobbyManager.new()
	root.add_child(manager)
	var net: LobbyNet = LobbyNet.new()
	root.add_child(net)
	manager.bind_net(net)
	overlay.bind_lobby(manager)
	var joined: bool = manager.join_remote("LOBBY01", "HOST", "pit", GameLaunch.NetPlay.COOP, 20, 2)
	_expect(joined and manager.get_role() == LobbyManager.Role.GUEST, "Guest 投影房就位且角色是 GUEST")
	return manager

## Host 角色：离线建房（create_room 直接进 seat 1 并置 HOST）。
## 不用 host_room()：那条会真 bind 17778，本测试只测 UI 翻译动作，不占端口。
func _make_host_manager(overlay: LanOverlay) -> LobbyManager:
	var manager: LobbyManager = LobbyManager.new()
	root.add_child(manager)
	var net: LobbyNet = LobbyNet.new()
	root.add_child(net)
	manager.bind_net(net)
	overlay.bind_lobby(manager)
	manager.create_room("pit", GameLaunch.NetPlay.COOP, 20)
	_expect(manager.get_role() == LobbyManager.Role.HOST, "Host 房间就位且角色是 HOST")
	_expect(manager.can_start(), "单人离线 Host 可以开始（离线 mock 合同）")
	return manager

## start_lan 计数器。Object 是引用语义，闭包捕获后能真实回写计数。
class StartLanCounter extends RefCounted:
	var count: int = 0

## 连接并返回计数器；用 counter.count 读当前次数。
func _count_start_lan(overlay: LanOverlay) -> StartLanCounter:
	var counter := StartLanCounter.new()
	overlay.start_lan.connect(func() -> void:
		counter.count += 1
	)
	return counter

func _teardown(overlay: LanOverlay, manager: LobbyManager) -> void:
	overlay.close()
	overlay.queue_free()
	manager.queue_free()

func _expect(condition: bool, label: String) -> void:
	if not condition:
		_failures.append(label)

func _finish() -> void:
	if _failures.is_empty():
		print("LOBBY_START_TRANSITION_OK")
		quit(0)
		return
	for failure: String in _failures:
		printerr("LOBBY_START_TRANSITION_FAIL: %s" % failure)
	quit(1)
