extends RefCounted
class_name ServerConfig

## Dedicated Server 运行时配置。优先读环境变量，其次读 CLI user args。
## 不持有密钥日志；dev_token 只用于本地开发准入，生产由 WildBoat Game Ticket 替换。
## S2S 凭证：DEDICATED_SERVER_CREDENTIAL（与 WildBoat 对齐）；兼容旧名 WPG_WILDBOAT_SERVER_TOKEN。

var port: int = OnlineProtocol.DEFAULT_PORT
var max_players: int = OnlineProtocol.MAX_PLAYERS
var tick_hz: float = OnlineProtocol.SNAPSHOT_HZ
var ready_file: String = OnlineProtocol.READY_FILE_DEFAULT
var bind_address: String = "*"
## 开发身份共享口令。空字符串 = 本地开放（仅 admission_mode=dev）。
var dev_token: String = ""
var match_id: String = "dev_match"
var game_instance_id: String = "dev_instance"
var server_id: String = ""
var admission_mode: int = OnlineProtocol.AdmissionMode.DEV
var wildboat_base_url: String = "http://127.0.0.1:8080"
var wildboat_server_token: String = ""
var server_build: String = "wpg-ds-local"
var settle_on_stop: bool = false
## 注册到 WildBoat 时对外宣告的 host（客户端将连此地址）。
var advertise_host: String = "127.0.0.1"
var heartbeat_interval_sec: float = 10.0
var register_with_wildboat: bool = true


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
	var iid: String = OS.get_environment("WPG_GAME_INSTANCE_ID").strip_edges()
	if not iid.is_empty():
		cfg.game_instance_id = iid
	var mode_raw: String = OS.get_environment("WPG_ADMISSION_MODE").strip_edges().to_lower()
	cfg.admission_mode = _parse_admission_mode(mode_raw)
	var wb: String = OS.get_environment("WPG_WILDBOAT_BASE_URL").strip_edges()
	if not wb.is_empty():
		cfg.wildboat_base_url = wb
	## 优先 WildBoat 契约名；兼容旧 WPG_* 别名。
	var st: String = OS.get_environment("DEDICATED_SERVER_CREDENTIAL")
	if st.is_empty():
		st = OS.get_environment("WPG_WILDBOAT_SERVER_TOKEN")
	if not st.is_empty():
		cfg.wildboat_server_token = st
	var build: String = OS.get_environment("WPG_SERVER_BUILD").strip_edges()
	if not build.is_empty():
		cfg.server_build = build
	var adv: String = OS.get_environment("WPG_ADVERTISE_HOST").strip_edges()
	if not adv.is_empty():
		cfg.advertise_host = adv
	cfg.heartbeat_interval_sec = maxf(2.0, _env_float("WPG_HEARTBEAT_INTERVAL_SEC", cfg.heartbeat_interval_sec))
	cfg.settle_on_stop = OS.get_environment("WPG_SETTLE_ON_STOP").strip_edges() == "1"
	if OS.get_environment("WPG_SKIP_WILDBOAT_REGISTER").strip_edges() == "1":
		cfg.register_with_wildboat = false
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
		if arg == "--admission-mode" and i + 1 < args.size():
			admission_mode = _parse_admission_mode(args[i + 1])
			i += 2
			continue
		if arg.begins_with("--admission-mode="):
			admission_mode = _parse_admission_mode(arg.get_slice("=", 1))
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


static func _parse_admission_mode(raw: String) -> int:
	match raw.strip_edges().to_lower():
		"stub":
			return OnlineProtocol.AdmissionMode.STUB
		"wildboat", "ticket", "online":
			return OnlineProtocol.AdmissionMode.WILDBOAT
		_:
			return OnlineProtocol.AdmissionMode.DEV


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
