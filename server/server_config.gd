extends RefCounted
class_name ServerConfig

## Dedicated Server 运行时配置。优先读环境变量，其次读 CLI user args。
## 不持有密钥日志；dev_token 只用于本地开发准入，生产由 WildBoat Game Ticket 替换。

var port: int = OnlineProtocol.DEFAULT_PORT
var max_players: int = OnlineProtocol.MAX_PLAYERS
var tick_hz: float = OnlineProtocol.SNAPSHOT_HZ
var ready_file: String = OnlineProtocol.READY_FILE_DEFAULT
var bind_address: String = "*"
## 开发身份共享口令。空字符串 = 本地开放（仅 Phase 2A / 本机测试）。
var dev_token: String = ""
var match_id: String = "dev_match"


static func from_environment() -> ServerConfig:
	var cfg := ServerConfig.new()
	cfg.port = _env_int("WPG_GAME_PORT", cfg.port)
	cfg.max_players = clampi(_env_int("WPG_MAX_PLAYERS", cfg.max_players), 1, OnlineProtocol.MAX_PLAYERS)
	cfg.tick_hz = maxf(1.0, _env_float("WPG_TICK_HZ", cfg.tick_hz))
	var ready: String = OS.get_environment("WPG_READY_FILE").strip_edges()
	if not ready.is_empty():
		cfg.ready_file = ready
	var bind_addr: String = OS.get_environment("WPG_BIND_ADDRESS").strip_edges()
	if not bind_addr.is_empty():
		cfg.bind_address = bind_addr
	var token: String = OS.get_environment("WPG_DEV_TOKEN")
	if not token.is_empty():
		cfg.dev_token = token.substr(0, OnlineProtocol.MAX_DEV_TOKEN_LEN)
	var mid: String = OS.get_environment("WPG_MATCH_ID").strip_edges()
	if not mid.is_empty():
		cfg.match_id = mid
	cfg._apply_cli_overrides()
	return cfg


func snapshot_interval() -> float:
	return 1.0 / maxf(1.0, tick_hz)


func _apply_cli_overrides() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var i: int = 0
	while i < args.size():
		var arg: String = args[i]
		if arg == "--port" and i + 1 < args.size():
			port = clampi(int(args[i + 1]), 1, 65535)
			i += 2
			continue
		if arg.begins_with("--port="):
			port = clampi(int(arg.get_slice("=", 1)), 1, 65535)
			i += 1
			continue
		if arg == "--max-players" and i + 1 < args.size():
			max_players = clampi(int(args[i + 1]), 1, OnlineProtocol.MAX_PLAYERS)
			i += 2
			continue
		if arg.begins_with("--max-players="):
			max_players = clampi(int(arg.get_slice("=", 1)), 1, OnlineProtocol.MAX_PLAYERS)
			i += 1
			continue
		if arg == "--dev-token" and i + 1 < args.size():
			dev_token = args[i + 1].substr(0, OnlineProtocol.MAX_DEV_TOKEN_LEN)
			i += 2
			continue
		if arg.begins_with("--dev-token="):
			dev_token = arg.get_slice("=", 1).substr(0, OnlineProtocol.MAX_DEV_TOKEN_LEN)
			i += 1
			continue
		if arg == "--ready-file" and i + 1 < args.size():
			ready_file = args[i + 1]
			i += 2
			continue
		if arg.begins_with("--ready-file="):
			ready_file = arg.get_slice("=", 1)
			i += 1
			continue
		i += 1


static func _env_int(key: String, fallback: int) -> int:
	var raw: String = OS.get_environment(key).strip_edges()
	if raw.is_empty():
		return fallback
	return int(raw)


static func _env_float(key: String, fallback: float) -> float:
	var raw: String = OS.get_environment(key).strip_edges()
	if raw.is_empty():
		return fallback
	return float(raw)
