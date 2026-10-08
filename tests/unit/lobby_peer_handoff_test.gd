extends SceneTree

## Phase 10.1 契约回归：LOBBY -> BATTLE 的 multiplayer peer 交接 + 清理 + Solo 无 peer。
##
## 覆盖三件硬规则：
##   1. 换场交接不得关闭 ENet peer（LobbyNet.release_peer_for_handoff）；
##   2. 明确关房 / 离开 Lobby 必须真的断网（LobbyNet.force_close_peer）；
##   3. 离线 Solo / 打开主菜单不得创建任何网络 peer（默认 OfflineMultiplayerPeer 不算）。
## 另加一条 UI 契约：HOST OVER INTERNET 走 host_room + create_p2p_invite + start_p2p_hosting，
## 且 Host 侧只以 Host 角色参与 P2P（绝不 begin_direct_enet / 变 Guest）。
##
## 跑法：godot --headless --path . --script res://tests/unit/lobby_peer_handoff_test.gd
## 通过输出 LOBBY_PEER_HANDOFF_OK；失败逐条 LOBBY_PEER_HANDOFF_FAIL 并返回非 0。

var _failures: PackedStringArray = PackedStringArray()

func _initialize() -> void:
	_run_all.call_deferred()

func _run_all() -> void:
	PlayerProfile.load_from_disk()
	_case_net_release_preserves_peer()
	_case_manager_start_match_keeps_peer()
	_case_overlay_wan_host_starts_p2p()
	_case_overlay_create_room_stays_lan()
	_case_offline_solo_has_no_peer()
	_case_cancel_join_cleans_up()
	_case_main_menu_has_no_network_peer()
	_finish()

# ---- 用例 ----

## CASE A：LobbyNet 交接后 close() 不得关 peer；force_close_peer() 才真关。
func _case_net_release_preserves_peer() -> void:
	var net: LobbyNet = LobbyNet.new()
	root.add_child(net)
	_expect(net.host_listen(), "host_listen 起 ENet server")
	_expect(_has_live_peer(), "host_listen 后 peer 已挂到 SceneTree.multiplayer")

	net.release_peer_for_handoff()
	_expect(_has_live_peer(), "release_peer_for_handoff 后 peer 仍活着（交接不得关 peer）")
	_expect(net.get_state() == LobbyNet.NetState.STARTING, "交接后 LobbyNet 状态 = STARTING")

	## 模拟 MainMenu 换场释放：_exit_tree -> close() 必须尊重交接标记。
	net.close()
	_expect(_has_live_peer(), "交接后的 close()（换场释放语义）不得关闭 peer")

	## 战斗侧 owner 收尾 / 或明确关房：force_close_peer() 必须真的断。
	net.force_close_peer()
	_expect(not _has_live_peer(), "force_close_peer 后 multiplayer_peer 被清空")
	_expect(net.get_state() == LobbyNet.NetState.DISCONNECTED, "force_close_peer 后状态 = DISCONNECTED")
	_teardown(net)

## CASE B：LobbyManager.start_match（联网 Host）交接后 peer 仍活，Room 进 STARTING。
func _case_manager_start_match_keeps_peer() -> void:
	var net: LobbyNet = LobbyNet.new()
	root.add_child(net)
	var manager: LobbyManager = LobbyManager.new()
	root.add_child(manager)
	manager.bind_net(net)

	_expect(manager.host_room("yard", GameLaunch.NetPlay.COOP, 20), "host_room 成功")
	_expect(_has_live_peer(), "host_room 后 peer 活着")
	## 联网房 min 2 人：造一个已验证（ticket 通过）且 READY 的 Guest 才能开局。
	manager.note_peer_connecting(2)
	_expect(manager.confirm_peer(2) == 2, "confirm_peer(2) 落座 seat 2")
	_expect(manager.apply_remote_ready(2, true), "远端 Guest READY 生效")
	_expect(manager.can_start(), "联网 Host + 1 READY Guest 可以开始")
	_expect(manager.start_match(), "start_match 成功")

	_expect(_has_live_peer(), "start_match 交接后 peer 仍活着（不得掐断战斗网络）")
	_expect(net.get_state() == LobbyNet.NetState.STARTING, "start_match 后 LobbyNet 进 STARTING")
	var room: Room = manager.get_room()
	_expect(room != null and room.room_state == Room.RoomState.STARTING, "start_match 后 Room 进 STARTING")

	manager.close_network()
	_expect(not _has_live_peer(), "close_network（明确关房）后 peer 被清空")
	_teardown(net, manager)

## CASE C：HOST OVER INTERNET 真 UI 入口 = host_room + create_p2p_invite + start_p2p_hosting。
func _case_overlay_wan_host_starts_p2p() -> void:
	var overlay: LanOverlay = _make_overlay()
	var net: LobbyNet = LobbyNet.new()
	root.add_child(net)
	var manager: LobbyManager = LobbyManager.new()
	root.add_child(manager)
	manager.bind_net(net)
	overlay.bind_lobby(manager)
	manager.set_rendezvous_endpoint("127.0.0.1", 17779)

	_expect(manager.host_room("yard", GameLaunch.NetPlay.COOP, 20), "WAN host_room 成功")
	overlay.open()
	_expect(overlay._view == LanOverlay.View.HOME, "open() 后停在 MULTIPLAYER 首页")
	overlay._on_home_host_p2p_pressed()
	_expect(overlay._p2p_hosting, "HOST OVER INTERNET 进入 P2P 模式")
	_expect(overlay._view == LanOverlay.View.HOST, "HOST OVER INTERNET 进入 HOST 视图")

	var invite: JoinInvite = manager.get_host_invite()
	_expect(invite != null and invite.is_p2p(), "UI 建房产出 P2P invite（p2p=1）")
	_expect(invite != null and invite.rendezvous_host == "127.0.0.1" and invite.rendezvous_port == 17779,
		"P2P invite 带正确 rendezvous 端点")
	var uri: String = overlay.get_invite_uri()
	_expect(JoinInvite.parse(uri).is_p2p(), "get_invite_uri 返回可解析的 P2P invite URI")

	var p2p: P2PConnection = manager.get_p2p_connection()
	_expect(p2p != null, "start_p2p_hosting 已建立 P2PConnection")
	_expect(p2p != null and p2p.is_host_role(), "P2P 角色是 Host")
	_expect(p2p != null and not p2p.is_guest_role(), "Host 绝不成为 Guest（绝不 begin_direct_enet）")

	overlay.close()
	_expect(manager.get_p2p_connection() == null, "关叠层后 P2P 编排已清理（rendezvous / UDP 释放）")
	_expect(not _has_live_peer(), "关叠层后无残留 multiplayer peer")
	_teardown(net, manager, overlay)

## CASE D：CREATE ROOM 仍是 LAN（不注册 rendezvous，invite 不是 P2P）。
func _case_overlay_create_room_stays_lan() -> void:
	var overlay: LanOverlay = _make_overlay()
	var net: LobbyNet = LobbyNet.new()
	root.add_child(net)
	var manager: LobbyManager = LobbyManager.new()
	root.add_child(manager)
	manager.bind_net(net)
	overlay.bind_lobby(manager)
	manager.set_rendezvous_endpoint("127.0.0.1", 17779)

	_expect(manager.host_room("yard", GameLaunch.NetPlay.COOP, 20), "LAN host_room 成功")
	overlay.open()
	overlay._on_home_host_pressed()
	_expect(not overlay._p2p_hosting, "CREATE ROOM 不进入 P2P 模式")
	var invite: JoinInvite = JoinInvite.parse(overlay.get_invite_uri())
	_expect(invite != null and invite.is_valid() and not invite.is_p2p(), "CREATE ROOM 产出 LAN invite（非 P2P）")
	_expect(manager.get_p2p_connection() == null, "CREATE ROOM 不启动 P2P 编排")

	overlay.close()
	_expect(not _has_live_peer(), "关 LAN 房后无残留 peer")
	_teardown(net, manager, overlay)

## CASE E：离线 Solo（无 peer）start_match 走离线信封，全程不建网络 peer。
func _case_offline_solo_has_no_peer() -> void:
	var net: LobbyNet = LobbyNet.new()
	root.add_child(net)
	var manager: LobbyManager = LobbyManager.new()
	root.add_child(manager)
	manager.bind_net(net)

	var room: Room = manager.create_room("yard", GameLaunch.NetPlay.COOP, 20)
	_expect(room != null, "离线建房成功")
	_expect(not _has_live_peer(), "离线建房不建任何网络 peer")
	_expect(not manager.get_snapshot().networked, "离线快照 networked = false")
	_expect(manager.start_match(), "离线 start_match 成功")
	_expect(GameLaunch.take_net_role() == GameLaunch.NetRole.OFFLINE, "离线信封 role = OFFLINE")
	_expect(not _has_live_peer(), "离线 Solo 全程无网络 peer")
	_teardown(net, manager)

## CASE G：进行中的 join 被主动取消 -> 不留残留 attempt / peer，且不算「失败」。
func _case_cancel_join_cleans_up() -> void:
	var net: LobbyNet = LobbyNet.new()
	root.add_child(net)
	var manager: LobbyManager = LobbyManager.new()
	root.add_child(manager)
	manager.bind_net(net)

	## 指向一个静默丢弃的地址：ENet 会一直卡在连接中，正好用来验证「取消」。
	var invite: JoinInvite = JoinInvite.new()
	invite.token = "cafebabecafebabe"
	invite.lan_host = "10.255.255.1"
	invite.lan_port = GameLaunch.NET_PORT
	invite.version = JoinInvite.VERSION
	_expect(invite.is_valid(), "构造的 invite 合法")
	var parsed: JoinInvite = manager.join_invite(invite.to_uri())
	_expect(parsed != null and parsed.is_valid(), "join_invite 接受 invite 并发起尝试")

	manager.cancel_join()
	_expect(manager.get_connect_attempt() == null, "cancel_join 后无残留 connect attempt")
	_expect(not _has_live_peer(), "cancel_join 后无残留 peer")
	_expect(manager.get_terminal_failure().is_empty(), "主动取消不算失败（不得 latch 终态）")
	_teardown(net, manager)

## CASE F：打开主菜单不得自带网络 peer（默认 OfflineMultiplayerPeer 不算）。
func _case_main_menu_has_no_network_peer() -> void:
	var packed: PackedScene = load("res://ui/main_menu.tscn") as PackedScene
	_expect(packed != null, "main_menu.tscn 能加载")
	if packed == null:
		return
	var menu: Node = packed.instantiate()
	root.add_child(menu)
	current_scene = menu
	_expect(not _has_live_peer(), "主菜单打开后没有网络 peer")
	menu.queue_free()
	current_scene = null

# ---- 夹具 ----

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

func _make_overlay() -> LanOverlay:
	var packed: PackedScene = load("res://ui/lan_overlay.tscn") as PackedScene
	_expect(packed != null, "lan_overlay.tscn 能加载")
	var overlay: LanOverlay = packed.instantiate() as LanOverlay
	root.add_child(overlay)
	return overlay

func _teardown(net: LobbyNet, manager: LobbyManager = null, overlay: LanOverlay = null) -> void:
	## 保证每个用例结束后 SceneTree 里不残留 peer，避免下一个用例被上一个影响。
	if net != null:
		net.force_close_peer()
		net.queue_free()
	if manager != null:
		manager.queue_free()
	if overlay != null:
		overlay.queue_free()

func _expect(condition: bool, label: String) -> void:
	if not condition:
		_failures.append(label)

func _finish() -> void:
	if _failures.is_empty():
		print("LOBBY_PEER_HANDOFF_OK")
		quit(0)
		return
	for failure: String in _failures:
		printerr("LOBBY_PEER_HANDOFF_FAIL: %s" % failure)
	quit(1)
