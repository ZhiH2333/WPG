extends SceneTree

## 协议 6 ticket 握手回归（Phase 8）。锁定：
## - protocol 5 -> 6：v5 客户端必须被 VERSION_MISMATCH 拒掉
## - ticket 有效 -> accepted（peer_confirmed + 座位）
## - ticket 无效 -> rejected，且不进 Room.players、不占正式座位
## - token 与 profile_id / seat / peer_id / room_id 严格分离
##
## 本测试与 lobby_net_test 同款：单进程直接打校验函数与状态机，
## 不跑两个 peer（Godot RPC 按节点路径路由，单进程两个 LobbyNet 无法互为对端）。
## 真正的跨进程 ticket 握手由 tools/ci/lan_start_ui_* + tests/lan_e2e_test 覆盖。
##
## 跑法：godot --headless --path . --script res://tests/lobby_ticket_test.gd
## 通过输出 LOBBY_TICKET_OK；失败逐条 LOBBY_TICKET_FAIL 并返回非 0。

const GOOD_TICKET := "0f1e2d3c4b5a69788796a5b4c3d2e1f0"

var _failures: PackedStringArray = PackedStringArray()

func _initialize() -> void:
	# LobbyNet 要碰 SceneTree.multiplayer；_initialize 期间 MultiplayerAPI 还没建好。
	_run_all.call_deferred()

func _run_all() -> void:
	PlayerProfile.load_from_disk()
	_case_protocol_bumped_to_six()
	_case_ticket_valid_accepted()
	_case_ticket_wrong_rejected()
	_case_ticket_empty_rejected()
	_case_no_room_ticket_rejects_all()
	_case_rejected_peer_gets_no_seat()
	_case_rejected_peer_not_in_room_players()
	_case_ticket_is_not_identity()
	_case_room_ticket_is_reused_across_invites()
	_case_guest_ticket_is_separate_from_room_ticket()
	_case_close_clears_peer_ticket_state()
	_case_version_mismatch_rejects_before_ticket()
	_finish()

# ---- 用例 ----

func _case_protocol_bumped_to_six() -> void:
	_expect(GameLaunch.NET_PROTOCOL == 6, "NET_PROTOCOL == 6")
	_expect(JoinInvite.VERSION == 6, "JoinInvite.VERSION == 6")
	_expect(GameLaunch.NET_MAX_SEATS == 5, "NET_MAX_SEATS 仍是 5（本阶段不改）")

## ticket 有效 -> 校验返回 NONE。
func _case_ticket_valid_accepted() -> void:
	var net: LobbyNet = LobbyNet.new()
	root.add_child(net)
	_make_host(net, GOOD_TICKET)
	net.set_seat_peer(2, 42)
	_expect(net.check_ticket(42, GOOD_TICKET) == LobbyNet.TicketReject.NONE, "正确 ticket -> accepted")
	net.close()
	net.queue_free()

## ticket 错误 -> BAD_TOKEN。定长比较：长度不同也必须拒。
func _case_ticket_wrong_rejected() -> void:
	var net: LobbyNet = LobbyNet.new()
	root.add_child(net)
	_make_host(net, GOOD_TICKET)
	net.set_seat_peer(2, 42)
	_expect(net.check_ticket(42, "ffffffffffffffffffffffffffffffff") == LobbyNet.TicketReject.BAD_TOKEN, "错误 ticket -> BAD_TOKEN")
	_expect(net.check_ticket(42, "0f1e2d3c4b5a69788796a5b4c3d2e1f1") == LobbyNet.TicketReject.BAD_TOKEN, "只差一位 -> BAD_TOKEN")
	_expect(net.check_ticket(42, GOOD_TICKET.substr(0, 8)) == LobbyNet.TicketReject.BAD_TOKEN, "短 ticket -> BAD_TOKEN")
	_expect(net.check_ticket(42, "") == LobbyNet.TicketReject.BAD_TOKEN, "空 ticket -> BAD_TOKEN")
	net.close()
	net.queue_free()

func _case_ticket_empty_rejected() -> void:
	_expect(JoinInvite.parse("wpg://join?v=6&t=&lan=192.168.1.20").error == JoinInvite.InvalidReason.MISSING_TOKEN, "空 token 的 invite 无效")
	_expect(JoinInvite.parse("wpg://join?v=6&lan=192.168.1.20").error == JoinInvite.InvalidReason.MISSING_TOKEN, "缺 token 的 invite 无效")

## 没设 ticket 的房间不接客：避免「空 ticket 放行」。
func _case_no_room_ticket_rejects_all() -> void:
	var net: LobbyNet = LobbyNet.new()
	root.add_child(net)
	net.host_listen()
	net.set_seat_peer(2, 42)
	_expect(net.check_ticket(42, "") == LobbyNet.TicketReject.NO_ROOM, "无 ticket 房间：空 ticket 被拒")
	_expect(net.check_ticket(42, GOOD_TICKET) == LobbyNet.TicketReject.NO_ROOM, "无 ticket 房间：任意 ticket 被拒")
	net.close()
	net.queue_free()

## 关键：ticket 不过的 peer 拿不到座位。
func _case_rejected_peer_gets_no_seat() -> void:
	var net: LobbyNet = LobbyNet.new()
	root.add_child(net)
	_make_host(net, GOOD_TICKET)
	net.set_seat_peer(2, 42)
	net.set_ticket(GOOD_TICKET)
	## 没有 pending 占座时，即使 ticket 对了也拿不到座位（NO_SEAT）。
	_expect(net.check_ticket(999, GOOD_TICKET) == LobbyNet.TicketReject.NO_SEAT, "没占座的 peer -> NO_SEAT")
	_expect(net.accept_hello_ok(999) == 0, "没占座的 peer 不给确认")
	_expect(net.is_peer_ticket_ok(999) == false, "被拒 peer 未标记 ticket_ok")
	net.close()
	net.queue_free()

## 关键：ticket 不过的 peer 不得进入 Room.players。
## 走真实链路：pending 占座 -> ticket 校验 -> peer_confirmed -> confirm_peer 才进 players。
func _case_rejected_peer_not_in_room_players() -> void:
	var net: LobbyNet = LobbyNet.new()
	root.add_child(net)
	var manager: LobbyManager = LobbyManager.new()
	root.add_child(manager)
	manager.bind_net(net)
	_make_host(net, GOOD_TICKET, manager)
	## 两个 peer 都先按真实流程占 pending 座（连上即占，与握手解耦）。
	var seat42: int = manager.note_peer_connecting(42)
	var seat43: int = manager.note_peer_connecting(43)
	_expect(seat42 > 1 and seat43 > 1, "两个 peer 都拿到 pending 座")
	net.set_seat_peer(seat42, 42)
	net.set_seat_peer(seat43, 43)
	var room: Room = manager.get_room()
	_expect(room.get_player_by_peer(42) == null, "握手前不在 players（只在 pending）")

	## peer 42 出示正确 ticket -> 确认 -> 进 players。
	_expect(net.check_ticket(42, GOOD_TICKET) == LobbyNet.TicketReject.NONE, "peer 42 ticket 有效")
	net.accept_hello_ok(42)
	_expect(room.get_player_by_peer(42) != null, "ticket 有效的 peer 进 Room.players")

	## peer 43 出示错误 ticket -> 拒绝 -> 永不进 players，且 pending 仍可被释放。
	_expect(net.check_ticket(43, "ffffffffffffffffffffffffffffffff") == LobbyNet.TicketReject.BAD_TOKEN, "peer 43 ticket 无效")
	_expect(room.get_player_by_peer(43) == null, "ticket 无效的 peer 不进 Room.players")
	_expect(net.is_peer_ticket_ok(43) == false, "ticket 无效的 peer 未标记通过")
	## 被拒 peer 的 pending 由 drop_peer 释放（真实链路里紧跟 disconnect_peer）。
	manager.drop_peer(43)
	_expect(room.get_player_by_peer(43) == null, "释放 pending 后 43 依然不在 players")
	_expect(not room.is_closed(), "房间仍在")
	net.close()
	net.queue_free()
	manager.queue_free()

## token 只证明「持有门票」：与 profile_id / seat / peer_id / room_id 都不是一回事。
func _case_ticket_is_not_identity() -> void:
	PlayerProfile.load_from_disk()
	var invite: JoinInvite = JoinInvite.create("192.168.1.20", 17777, "", "roomid01", "NightFox")
	_expect(invite.token != "roomid01", "token != room_id")
	_expect(invite.token != "1", "token != seat")
	_expect(invite.token != "42", "token != peer_id")
	var profile_id: String = PlayerProfile.get_profile_id()
	if not profile_id.is_empty():
		_expect(invite.token != profile_id, "token != profile_id")
	## 同一房间反复取 invite：每次 ticket 都重新随机（不是 room 的固定指纹）。
	## 注意：这是 JoinInvite.create() 的**静态工厂**语义 —— 它不认识「房间」，
	## 每次调用都产出一张新门票。房间级复用由 LobbyManager.create_invite() 负责
	## （见 _case_room_ticket_is_reused_across_invites）。
	var again: JoinInvite = JoinInvite.create("192.168.1.20", 17777, "", "roomid01", "NightFox")
	_expect(again.token != invite.token, "重新生成的 ticket 不同")

## ticket lifecycle（方案 A = 复用）：room ticket 属于房间，
## 再次 create_invite() **复用**当前 room ticket，只有显式 rotate 才换新票。
func _case_room_ticket_is_reused_across_invites() -> void:
	var manager: LobbyManager = LobbyManager.new()
	root.add_child(manager)
	manager.create_room("pit", GameLaunch.NetPlay.COOP, 20)
	_expect(manager.get_room_ticket().is_empty(), "建房后尚未生成 ticket")
	var first: JoinInvite = manager.create_invite("192.168.1.20", 17777)
	_expect(first != null and first.is_valid(), "第一张 invite 有效")
	var room_ticket: String = manager.get_room_ticket()
	_expect(not room_ticket.is_empty(), "建房后 room ticket 已生成")
	_expect(first.token == room_ticket, "invite.token 就是 room ticket")
	## 再取一次：必须复用，绝不换票（否则复制 invite 会让上一张失效）。
	var second: JoinInvite = manager.create_invite("192.168.1.20", 17777)
	_expect(second.token == room_ticket, "再次 create_invite 复用同一 room ticket")
	_expect(second.token == first.token, "两张 invite 的门票一致")
	_expect(manager.get_room_ticket() == room_ticket, "room ticket 未被改写")
	## 显式 rotate 才换票，且旧票立刻失效。
	var rotated: String = manager.rotate_room_ticket()
	_expect(rotated != room_ticket, "rotate 生成新 ticket")
	_expect(manager.get_room_ticket() == rotated, "room ticket 已更新")
	var third: JoinInvite = manager.create_invite("192.168.1.20", 17777)
	_expect(third.token == rotated, "rotate 后 create_invite 用新 ticket")
	_expect(third.token != room_ticket, "旧 invite 的 ticket 已失效")
	## ticket 与四种标识严格分离。
	_expect(rotated != manager.get_room().room_id, "ticket != room_id")
	_expect(rotated != PlayerProfile.get_profile_id(), "ticket != profile_id")
	manager.queue_free()

## guest ticket 与 room ticket 是两个独立概念，API 命名不混。
func _case_guest_ticket_is_separate_from_room_ticket() -> void:
	var manager: LobbyManager = LobbyManager.new()
	root.add_child(manager)
	manager.create_room("pit", GameLaunch.NetPlay.COOP, 20)
	var invite: JoinInvite = manager.create_invite("192.168.1.20", 17777)
	_expect(manager.get_room_ticket() == invite.token, "Host 持 room ticket")
	## Host 侧不该有 guest ticket。
	_expect(manager.get_guest_ticket().is_empty(), "Host 侧 guest ticket 为空")
	## Host 改房间规则 / 复制 invite 都不影响 guest ticket 语义。
	_expect(manager.get_room_ticket() != manager.get_guest_ticket(), "room ticket 与 guest ticket 分离")
	manager.queue_free()

## close() 必须清掉 peer 级 ticket 状态，避免旧连接放行新 peer。
func _case_close_clears_peer_ticket_state() -> void:
	var net: LobbyNet = LobbyNet.new()
	root.add_child(net)
	_make_host(net, GOOD_TICKET)
	net.set_seat_peer(2, 42)
	net._peer_ticket_ok[42] = 1
	_expect(net.is_peer_ticket_ok(42), "关闭前 42 已通过")
	net.close()
	_expect(not net.is_peer_ticket_ok(42), "close() 清空 peer ticket 状态")
	## 房间级 ticket 保留：否则 Host 一关连重开就拒绝所有 Guest。
	_expect(net.get_ticket() == GOOD_TICKET, "close() 不丢房间级 ticket")
	net.queue_free()

## 协议门先于 ticket 门：v5 客户端连 ticket 都不该被检查。
func _case_version_mismatch_rejects_before_ticket() -> void:
	var net: LobbyNet = LobbyNet.new()
	root.add_child(net)
	_make_host(net, GOOD_TICKET)
	var mismatches: Array = [0]
	net.version_mismatch.connect(func() -> void: mismatches[0] += 1)
	net.rpc_hello(5, GOOD_TICKET)
	_expect(net.get_state() == LobbyNet.NetState.VERSION_MISMATCH, "v5 hello -> VERSION_MISMATCH")
	_expect(int(mismatches[0]) == 1, "version_mismatch 派发一次")
	_expect(net.get_state() != LobbyNet.NetState.CONNECTED, "v5 不得进入 CONNECTED")
	net.close()
	net.queue_free()

# ---- 夹具 ----

## 建一个真监听的 Host（ticket 注入 + 可选绑 Manager）。
func _make_host(net: LobbyNet, ticket: String, manager: LobbyManager = null) -> void:
	net.host_listen()
	net.set_ticket(ticket)
	if manager != null:
		manager.create_room("pit", GameLaunch.NetPlay.COOP, 20)
		manager.mark_networked()

func _expect(condition: bool, label: String) -> void:
	if not condition:
		_failures.append(label)

func _finish() -> void:
	if _failures.is_empty():
		print("LOBBY_TICKET_OK")
		quit(0)
		return
	for failure: String in _failures:
		printerr("LOBBY_TICKET_FAIL: %s" % failure)
	quit(1)
