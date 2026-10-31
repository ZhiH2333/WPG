extends SceneTree

## Dedicated Server listen / ready-file / config 集成（Phase 2A）。
## 跑法：godot --headless --path . --script res://tests/integration/dedicated_server_test.gd

var _failures: PackedStringArray = PackedStringArray()


func _initialize() -> void:
	_run_all.call_deferred()


func _run_all() -> void:
	_case_listen_and_ready_file()
	_case_config_cli_and_env_shape()
	_case_channel_node_name_contract()
	_finish()


func _case_listen_and_ready_file() -> void:
	## 使用仓库内绝对路径，避免沙箱/CI 下 user:// 不可写造成假失败。
	var ready_path: String = ProjectSettings.globalize_path("res://").path_join("logs/wpg_ds_ready_integration")
	DirAccess.make_dir_recursive_absolute(ready_path.get_base_dir())
	if FileAccess.file_exists(ready_path):
		DirAccess.remove_absolute(ready_path)
	var cfg := ServerConfig.new()
	cfg.port = 24611
	cfg.max_players = 4
	cfg.ready_file = ready_path
	cfg.match_id = "integration_match"
	var session := DsSession.new()
	root.add_child(session)
	session.setup(cfg)
	_expect(session.start(), "DS listen ok")
	_expect(session.get_match_id() == "integration_match", "match id")
	_expect(FileAccess.file_exists(ready_path), "ready file written")
	var body: String = FileAccess.get_file_as_string(ready_path)
	_expect("ready" in body, "ready marker")
	_expect("port=24611" in body, "ready port")
	_expect("max_players=4" in body, "ready max_players")
	## OnlineChannel 必须在 /root/OnlineChannel，供跨进程 RPC。
	var channel: Node = root.get_node_or_null(OnlineProtocol.CHANNEL_NODE_NAME)
	_expect(channel != null, "OnlineChannel mounted at /root/%s" % OnlineProtocol.CHANNEL_NODE_NAME)
	session.stop()
	_expect(not FileAccess.file_exists(ready_path), "ready file cleared on stop")
	session.queue_free()


func _case_config_cli_and_env_shape() -> void:
	var cfg := ServerConfig.new()
	_expect(cfg.port == OnlineProtocol.DEFAULT_PORT, "default port")
	_expect(cfg.max_players == OnlineProtocol.MAX_PLAYERS, "default max players")
	_expect(cfg.max_players <= OnlineProtocol.MAX_PLAYERS, "never above online cap")


func _case_channel_node_name_contract() -> void:
	_expect(OnlineProtocol.CHANNEL_NODE_NAME == "OnlineChannel", "fixed channel name")
	## 清掉上一用例可能残留的通道，避免 add_child 被自动改名为 OnlineChannel2。
	var stale: Node = root.get_node_or_null(OnlineProtocol.CHANNEL_NODE_NAME)
	if stale != null:
		root.remove_child(stale)
		stale.free()
	var client: DedicatedClient = DedicatedClient.create("tester", "")
	_expect(client.name == OnlineProtocol.CHANNEL_NODE_NAME, "client configure sets fixed name")
	root.add_child(client)
	_expect(client.name == OnlineProtocol.CHANNEL_NODE_NAME, "client keeps fixed name in tree")
	root.remove_child(client)
	client.free()


func _expect(cond: bool, label: String) -> void:
	if not cond:
		_failures.append(label)


func _finish() -> void:
	if _failures.is_empty():
		print("DEDICATED_SERVER_OK")
		quit(0)
		return
	for failure: String in _failures:
		printerr("DEDICATED_SERVER_FAIL: %s" % failure)
	quit(1)
