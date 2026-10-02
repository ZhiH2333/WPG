extends SceneTree

## MULTIPLAYER 首页 / LAN ROOMS / JOIN INVITE / Lobby Starting / 掉线提示的 UI 契约（第四刀）。
## 直接实例化 ui/lan_overlay.tscn，按真实按钮路径驱动，只断言 UI 读到的状态，
## 不重复测 LobbyManager 的领域逻辑（那在 lobby_domain_test / lobby_ready_test / lobby_net_test）。
## 全程 headless：Guest 探针会真 bind 17778，但本测试只读视图与文案，不等发现结果。
##
## 跑法：godot --headless --path . --script res://tests/multiplayer_page_test.gd
## 通过输出 MULTIPLAYER_PAGE_OK；失败逐条 MULTIPLAYER_PAGE_FAIL 并返回非 0。

var _failures: PackedStringArray = PackedStringArray()

func _initialize() -> void:
	# UI 节点与 LanBeacon 都需要 SceneTree 已经建好（同 lobby_net_test 的理由）。
	_run_all.call_deferred()

func _run_all() -> void:
	PlayerProfile.load_from_disk()
	_case_main_menu_wiring()
	var packed: PackedScene = load("res://ui/lan_overlay.tscn") as PackedScene
	_expect(packed != null, "lan_overlay.tscn 能加载")
	if packed == null:
		_finish()
		return
	var overlay: LanOverlay = packed.instantiate() as LanOverlay
	_expect(overlay != null, "根节点是 LanOverlay")
	if overlay == null:
		_finish()
		return
	root.add_child(overlay)
	var manager: LobbyManager = LobbyManager.new()
	root.add_child(manager)
	var net: LobbyNet = LobbyNet.new()
	root.add_child(net)
	manager.bind_net(net)
	overlay.bind_lobby(manager)
	overlay.open()

	_case_multiplayer_home(overlay)
	_case_create_room_and_back(overlay, manager)
	_case_lan_rooms(overlay)
	_case_lobby_navigation(overlay, manager)
	_case_join_invite(overlay, net)
	_case_recent(overlay)
	_case_privacy(overlay, manager)
	_case_starting_and_disconnect(overlay, manager)
	_case_network_failure_feedback(overlay, manager)
	await _case_lobby_exit(overlay, manager)

	overlay.queue_free()
	manager.queue_free()
	net.queue_free()
	_finish()

# ---- 用例 ----

## 主菜单必须把 LobbyNet 绑给 LobbyManager：漏了这一步，建房页永远显示 bind failed
## （ENet 与大厅 RPC 都归 LobbyNet，没有它就没人能 listen）。
func _case_main_menu_wiring() -> void:
	var packed: PackedScene = load("res://ui/main_menu.tscn") as PackedScene
	_expect(packed != null, "main_menu.tscn 能加载")
	if packed == null:
		return
	var menu: Node = packed.instantiate()
	root.add_child(menu)
	var manager: LobbyManager = menu.get_node_or_null("LobbyManager") as LobbyManager
	_expect(manager != null, "主菜单里有 LobbyManager 节点")
	if manager != null:
		_expect(manager.has_net(), "主菜单把 LobbyNet 绑给了 LobbyManager")
		if manager.has_net():
			_expect(manager.get_net_state() == int(LobbyNet.NetState.DISCONNECTED), "绑上但还没建连")
	menu.queue_free()

func _case_multiplayer_home(overlay: LanOverlay) -> void:
	_expect(overlay._view == LanOverlay.View.HOME, "打开叠层落在 MULTIPLAYER 首页")
	_expect(overlay._home_root.visible, "首页可见")
	_expect(not overlay._host_root.visible and not overlay._join_root.visible, "首页不叠建房 / 列表页")
	_expect(overlay._row_create.visible, "Create room 行存在")
	_expect(overlay._row_quick_join.visible, "Quick join 行存在")
	_expect(overlay._row_lan_rooms.visible, "LAN rooms 行存在")
	_expect(overlay._row_join_invite.visible, "Join invite 行存在")
	_expect(overlay._row_lan_rooms.get_node("Text/Caption").text != "", "LAN rooms 行右侧有 caption")
	_expect(overlay._row_create.get_node("Text/Caption").text == "HOST A GAME", "Create room 行 caption")
	_expect(not overlay._recent_title.visible, "还没有最近房间时不显示 RECENT")
	_expect(overlay._home_nav.get_child_count() == overlay._home_rows.size() + overlay._home_rows.size() - 1, "导航行之间各一条分隔线")
	_expect(overlay._row_create.get_node_or_null("Text/Arrow") != null, "导航行右侧有箭头")

func _case_create_room_and_back(overlay: LanOverlay, manager: LobbyManager) -> void:
	overlay._row_create.pressed.emit()
	_expect(overlay._view == LanOverlay.View.HOST, "Create room -> 建房页")
	_expect(overlay._host_root.visible and not overlay._home_root.visible, "建房页可见，首页让位")
	_expect(manager.has_room() and manager.is_host(), "进建房页就真的建了房")
	_expect(overlay._host_lan_visible.button_pressed, "默认隐私是 LAN VISIBLE")
	overlay._back_button.pressed.emit()
	_expect(overlay._view == LanOverlay.View.HOME, "建房页 Back -> MULTIPLAYER 首页")
	_expect(overlay._home_root.visible, "回到首页可见")
	_expect(not manager.has_room(), "Back 时离房（Host 离房即关房）")
	_expect(not net_active(overlay), "Back 时关掉网络")

func _case_lan_rooms(overlay: LanOverlay) -> void:
	overlay._row_lan_rooms.pressed.emit()
	_expect(overlay._view == LanOverlay.View.JOIN, "LAN rooms -> 房间列表页")
	_expect(overlay._join_root.visible, "列表页可见")
	_expect(overlay._join_browse.visible and not overlay._join_form.visible, "LAN rooms 只显示发现列表列")

## Guest 握手完成必须真的把 UI 推进 Lobby 页（这条曾经断线：页面在、导航没人调）。
func _case_lobby_navigation(overlay: LanOverlay, manager: LobbyManager) -> void:
	overlay._row_lan_rooms.pressed.emit()
	_expect(overlay._view == LanOverlay.View.JOIN, "先在 LAN ROOMS 页连接")
	manager.joined_lobby.emit()
	_expect(overlay._view == LanOverlay.View.LOBBY, "joined_lobby -> 自动进 Lobby 页")
	_expect(overlay._lobby_root.visible and not overlay._join_root.visible, "Lobby 页顶掉连接页")
	overlay._enter_multiplayer()

func _case_join_invite(overlay: LanOverlay, net: LobbyNet) -> void:
	overlay._row_join_invite.pressed.emit()
	_expect(overlay._view == LanOverlay.View.INVITE, "Join invite -> 邀请页")
	_expect(overlay._join_form.visible and not overlay._join_browse.visible, "Join invite 只显示手打 / 粘贴列")
	_expect(overlay._join_edit.text == GameLaunch.DEFAULT_JOIN_ADDRESS, "邀请页地址栏回默认值")
	_expect(overlay._resolve_join_address("wpg://10.0.0.9:17777") == "10.0.0.9", "粘贴邀请文本能解析出地址")
	_expect(overlay._resolve_join_address("my-lan-host") == "my-lan-host", "解析不到 IPv4 时按主机名原样用")
	overlay._join_edit.text = ""
	overlay._on_connect_pressed()
	_expect(overlay._join_status.text == "no address", "空地址直接拒绝")
	_expect(not net.is_active(), "空地址不会建 peer")
	overlay._show_qr_button.pressed.emit()
	_expect(overlay._invite_notice.text.find("QR") >= 0, "Show QR 是 shell（只给占位文案）")
	overlay._copy_invite_button.pressed.emit()
	_expect(overlay._invite_notice.text.find("copied") >= 0, "Copy invite 给出复制反馈")

func _case_recent(overlay: LanOverlay) -> void:
	# 建房本身也会记一条（Host 的最近房间），这里先清空，只测去重与上限。
	overlay._recent_rooms.clear()
	overlay._refresh_recent()
	_expect(overlay._recent_list.get_child_count() == 0, "清空后 RECENT 没有行")
	overlay._remember_room("10.0.0.9", "pit", int(GameLaunch.NetPlay.COOP), 20, 2, 5)
	_expect(overlay._recent_list.get_child_count() == 1, "RECENT 记下一行")
	_expect(overlay._recent_title.visible, "有最近房间后显示 RECENT")
	overlay._remember_room("10.0.0.9", "pit", int(GameLaunch.NetPlay.COOP), 20, 2, 5)
	_expect(overlay._recent_list.get_child_count() == 1, "同一房间不重复记")
	overlay._remember_room("10.0.0.10", "yard", int(GameLaunch.NetPlay.BATTLE), 0, 1, 5)
	_expect(overlay._recent_list.get_child_count() == 2, "不同房间各记一行")
	for index: int in 8:
		overlay._remember_room("10.0.0.%d" % (20 + index), "yard", int(GameLaunch.NetPlay.COOP), 20, 1, 5)
	_expect(overlay._recent_list.get_child_count() <= LanOverlay.RECENT_LIMIT, "RECENT 有上限，不会无限长")

func _case_privacy(overlay: LanOverlay, manager: LobbyManager) -> void:
	overlay._enter_multiplayer()
	overlay._row_create.pressed.emit()
	_expect(overlay._view == LanOverlay.View.HOST and manager.has_room(), "再次进建房页")
	overlay._host_invite_only.pressed.emit()
	_expect(overlay._privacy == Room.Privacy.INVITE_ONLY, "UI 切到 INVITE ONLY")
	_expect(manager.get_privacy() == int(Room.Privacy.INVITE_ONLY), "隐私落到 Room")
	_expect(overlay._host_invite_only.button_pressed, "INVITE ONLY 按钮保持按下")
	overlay._host_lan_visible.pressed.emit()
	_expect(manager.get_privacy() == int(Room.Privacy.LAN_VISIBLE), "切回 LAN VISIBLE")

func _case_starting_and_disconnect(overlay: LanOverlay, manager: LobbyManager) -> void:
	manager.note_peer_connecting(7)
	manager.confirm_peer(7)
	manager.set_ready("peer:7", true)
	overlay._enter_lobby()
	_expect(overlay._view == LanOverlay.View.LOBBY, "进入 Lobby 核心页")
	_expect(overlay._lobby_root.visible, "Lobby 页可见")
	_expect(overlay._guest_seat_rows[0].modulate.a < 1.0, "进 Lobby 走行级错峰淡入")
	_expect(overlay._lobby_connection.text.find("CONNECTED") >= 0, "连接行显示已连人数")
	var seats: Array = manager.get_snapshot()["seats"]
	_expect(bool(seats[0]["is_host"]), "座位 1 是 Host")
	_expect(bool(seats[1]["ready"]), "座位 2 已 READY")
	_expect(manager.start_match(), "Host 开局")
	_expect(overlay._lobby_connection.text.find("STARTING") >= 0, "Starting 显示 STARTING / LAUNCHING 文案")
	_expect(overlay._lobby_ready.disabled, "Starting 冻结 Ready 钮")
	_expect(overlay._lobby_boar.disabled and overlay._lobby_chicken.disabled, "Starting 冻结角色钮")
	manager.drop_peer(7)
	_expect(overlay._lobby_connection.text.find("LEFT") >= 0, "掉线播放 PLAYERxx LEFT")
	_expect(overlay._lobby_notice_playing, "提示播放期间不接受整体刷新（先播完再画 EMPTY SEAT）")

## 连接失败 / 协议不符 / Host 关闭：只在当前页的状态行出文案，不弹第二个大面板。
func _case_network_failure_feedback(overlay: LanOverlay, manager: LobbyManager) -> void:
	overlay._enter_invite()
	manager.network_failed.emit("Version mismatch")
	_expect(overlay._join_status.text == "Version mismatch", "协议不符在邀请页写明原因")
	_expect(not overlay._connect_button.disabled, "失败后可以重试连接")
	overlay._enter_lobby()
	manager.network_failed.emit("host closed")
	_expect(overlay._view == LanOverlay.View.INVITE, "Host 关闭后退回邀请页（1.0 无 reconnect）")
	_expect(overlay._join_status.text == "host closed", "Host 关闭写明原因")

## 退 Lobby：淡出结束后才回 MULTIPLAYER 首页（淡出是真 tween，所以要等它跑完）。
func _case_lobby_exit(overlay: LanOverlay, manager: LobbyManager) -> void:
	overlay._enter_lobby()
	_expect(overlay._view == LanOverlay.View.LOBBY, "重新进 Lobby 才能测退场")
	overlay._back_button.pressed.emit()
	_expect(not manager.has_room(), "退 Lobby 时先离房")
	_expect(overlay._view == LanOverlay.View.LOBBY, "淡出期间还停在 Lobby 页")
	await create_timer(0.35).timeout
	_expect(overlay._view == LanOverlay.View.HOME, "淡出结束后回到 MULTIPLAYER 首页")
	_expect(overlay._home_root.visible, "回到首页可见")
	_expect(overlay._lobby_root.modulate.a == 1.0, "退场后 Lobby 页 alpha 复位")

# ---- 工具 ----

func net_active(overlay: LanOverlay) -> bool:	return overlay._lobby != null and overlay._lobby.get_net_state() != int(LobbyNet.NetState.DISCONNECTED)

func _finish() -> void:
	if _failures.is_empty():
		print("MULTIPLAYER_PAGE_OK")
		quit(0)
		return
	for failure: String in _failures:
		printerr("MULTIPLAYER_PAGE_FAIL: %s" % failure)
	quit(1)

func _expect(condition: bool, label: String) -> void:
	if not condition:
		_failures.append(label)
