extends Node

## Dedicated Server 入口。无 UI / Audio / 客户端菜单依赖。
## 由 server/main.tscn 挂载，或经 boot_screen 在 dedicated_server feature / CLI 下切入。

var _session: DsSession = null
var _booting: bool = false


func _ready() -> void:
	_boot.call_deferred()


func _boot() -> void:
	if _booting:
		return
	_booting = true
	var cfg: ServerConfig = ServerConfig.from_environment()
	_session = DsSession.new()
	_session.name = "DsSession"
	add_child(_session)
	_session.setup(cfg)
	if not _session.start():
		push_error("WPG_DS_FAIL: listen failed on port %d" % cfg.port)
		get_tree().quit(1)
		return
	if not await _session.bootstrap_backend():
		push_error("WPG_DS_FAIL: WildBoat bootstrap failed")
		_session.stop()
		get_tree().quit(1)
		return
	print("WPG_DS_READY")


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_shutdown()
	elif what == NOTIFICATION_EXIT_TREE:
		_shutdown()


func _shutdown() -> void:
	if _session != null:
		_session.stop()
		_session = null
