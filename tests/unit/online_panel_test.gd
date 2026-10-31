extends SceneTree

## OnlinePanel Phase 2C：场景可加载、入口控件齐全、拒绝文案可读、离开回大厅相位。
## 不连真实网络；联调走 run_wildboat_online / 玩家文档。

var _failures: PackedStringArray = PackedStringArray()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_case_reject_texts()
	await _case_panel_scene()
	await _case_channel_mounts_on_root()
	_case_credentials_slot()
	await _case_lan_online_row()
	_finish()


func _case_channel_mounts_on_root() -> void:
	## 回归：UI 客户端通道必须在 /root/OnlineChannel，与 DS 路径一致。
	var packed: PackedScene = load("res://online/ui/online_panel.tscn") as PackedScene
	_expect(packed != null, "panel for mount case")
	if packed == null:
		return
	var panel: OnlinePanel = packed.instantiate() as OnlinePanel
	root.add_child(panel)
	await process_frame
	var client: DedicatedClient = DedicatedClient.create("mount", "t", "p", "m")
	panel._mount_online_channel(client)
	await process_frame
	var mounted: Node = root.get_node_or_null(OnlineProtocol.CHANNEL_NODE_NAME)
	_expect(mounted == client, "OnlineChannel 挂在 SceneTree root")
	_expect(client.get_parent() == root, "父节点是 root")
	panel._disconnect_client("")
	await process_frame
	_expect(root.get_node_or_null(OnlineProtocol.CHANNEL_NODE_NAME) == null, "断开后 root 无残留通道")
	panel.queue_free()
	await process_frame


func _case_reject_texts() -> void:
	_expect(
		OnlineProtocol.reject_reason_text(OnlineProtocol.RejectReason.BACKEND_UNAVAILABLE).contains("NOT joined"),
		"backend down 文案不得伪装成功"
	)
	_expect(
		OnlineProtocol.reject_reason_text(OnlineProtocol.RejectReason.CONNECTION_FAILED).contains("Dedicated Server"),
		"连不上 DS 有明确文案"
	)
	_expect(
		OnlineProtocol.reject_reason_text(OnlineProtocol.RejectReason.FULL).contains("full"),
		"满员文案"
	)


func _case_panel_scene() -> void:
	var packed: PackedScene = load("res://online/ui/online_panel.tscn") as PackedScene
	_expect(packed != null, "online_panel.tscn 可加载")
	if packed == null:
		return
	var panel: OnlinePanel = packed.instantiate() as OnlinePanel
	_expect(panel != null, "根是 OnlinePanel")
	if panel == null:
		return
	root.add_child(panel)
	await process_frame
	await process_frame
	_expect(panel.get_node("%JoinMatchButton") != null, "有 Join Match")
	_expect(panel.get_node("%LeaveButton") != null, "有 Leave Match")
	_expect(panel.get_node("%MatchStatus") != null, "有 MatchStatus")
	_expect(panel.get_node("%Status") != null, "有 Status")
	_expect(panel.get_connection_phase() == OnlinePanel.PHASE_IDLE, "初始相位 idle")
	panel._on_leave()
	_expect(panel.get_connection_phase() == OnlinePanel.PHASE_IDLE, "Leave 后仍 idle")
	var status: Label = panel.get_node("%Status") as Label
	_expect(status.text.contains("Not in a match") or status.text.contains("Ready") or status.text.contains("Left") or status.text.contains("Session"), "Leave/初始有状态文案")
	panel.queue_free()
	await process_frame


func _case_credentials_slot() -> void:
	OS.set_environment("WPG_CLIENT_SLOT", "a")
	var store_a := AuthCredentialsStore.new()
	_expect(store_a.store_path().contains("wpass_session_a"), "slot a 隔离路径")
	OS.set_environment("WPG_CLIENT_SLOT", "b")
	var store_b := AuthCredentialsStore.new()
	_expect(store_b.store_path().contains("wpass_session_b"), "slot b 隔离路径")
	OS.set_environment("WPG_CLIENT_SLOT", "")
	var store := AuthCredentialsStore.new()
	_expect(store.store_path() == AuthCredentialsStore.STORE_PATH, "无 slot 用默认路径")


func _case_lan_online_row() -> void:
	var packed: PackedScene = load("res://ui/lan_overlay.tscn") as PackedScene
	_expect(packed != null, "lan_overlay 可加载")
	if packed == null:
		return
	var overlay: LanOverlay = packed.instantiate() as LanOverlay
	root.add_child(overlay)
	var manager: LobbyManager = LobbyManager.new()
	root.add_child(manager)
	var net: LobbyNet = LobbyNet.new()
	root.add_child(net)
	manager.bind_net(net)
	overlay.bind_lobby(manager)
	overlay.open()
	await process_frame
	_expect(overlay._row_online != null, "MULTIPLAYER 有 Online 行")
	if overlay._row_online != null:
		var title: Label = overlay._row_online.get_node("Text/Title") as Label
		_expect(title.text.contains("Online"), "Online 行标题")
	overlay.queue_free()
	manager.queue_free()
	net.queue_free()


func _expect(cond: bool, msg: String) -> void:
	if cond:
		print("ONLINE_PANEL_OK: ", msg)
	else:
		_failures.append(msg)
		print("ONLINE_PANEL_FAIL: ", msg)


func _finish() -> void:
	if _failures.is_empty():
		print("ONLINE_PANEL_TEST_OK")
		quit(0)
	else:
		print("ONLINE_PANEL_TEST_FAIL count=", _failures.size())
		quit(1)
