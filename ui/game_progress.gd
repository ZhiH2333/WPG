extends Object
class_name GameProgress

## 跨局成绩。全是 static，不是 Autoload，不进场景树。不是中途续打。
const PATH := "user://progress.cfg"

static var _best_loop: int = 0
static var _best_kills: int = 0
static var _runs_played: int = 0
static var _last_loop: int = 0
static var _last_kills: int = 0
static var _last_gold: int = 0
static var _last_time_sec: float = 0.0
static var _last_owned: String = ""

static func load_from_disk() -> void:
	_best_loop = 0
	_best_kills = 0
	_runs_played = 0
	_last_loop = 0
	_last_kills = 0
	_last_gold = 0
	_last_time_sec = 0.0
	_last_owned = ""
	if not FileAccess.file_exists(PATH):
		return
	var cfg: ConfigFile = ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	_best_loop = int(cfg.get_value("stats", "best_loop", 0))
	_best_kills = int(cfg.get_value("stats", "best_kills", 0))
	_runs_played = int(cfg.get_value("stats", "runs_played", 0))
	_last_loop = int(cfg.get_value("last", "loop", 0))
	_last_kills = int(cfg.get_value("last", "kills", 0))
	_last_gold = int(cfg.get_value("last", "gold", 0))
	_last_time_sec = float(cfg.get_value("last", "time_sec", 0.0))
	_last_owned = str(cfg.get_value("last", "owned", ""))

static func save_to_disk() -> void:
	var cfg: ConfigFile = ConfigFile.new()
	cfg.set_value("stats", "best_loop", _best_loop)
	cfg.set_value("stats", "best_kills", _best_kills)
	cfg.set_value("stats", "runs_played", _runs_played)
	cfg.set_value("last", "loop", _last_loop)
	cfg.set_value("last", "kills", _last_kills)
	cfg.set_value("last", "gold", _last_gold)
	cfg.set_value("last", "time_sec", _last_time_sec)
	cfg.set_value("last", "owned", _last_owned)
	cfg.save(PATH)

static func record_run(session: RunSession) -> void:
	if session == null:
		return
	load_from_disk()
	var loop_index: int = session.get_loop_index()
	var kills: int = session.get_kill_count()
	_best_loop = maxi(_best_loop, loop_index)
	_best_kills = maxi(_best_kills, kills)
	_runs_played += 1
	_last_loop = loop_index
	_last_kills = kills
	_last_gold = session.get_gold()
	_last_time_sec = session.get_elapsed_sec()
	var ids: PackedStringArray = session.get_owned_upgrade_ids()
	if ids.is_empty():
		_last_owned = ""
	else:
		_last_owned = ",".join(ids)
	save_to_disk()

static func get_best_loop() -> int:
	return _best_loop

static func get_best_kills() -> int:
	return _best_kills

static func get_runs_played() -> int:
	return _runs_played

static func get_last_loop() -> int:
	return _last_loop

static func get_last_kills() -> int:
	return _last_kills

static func get_last_gold() -> int:
	return _last_gold

static func get_last_time_sec() -> float:
	return _last_time_sec

static func get_last_owned() -> String:
	return _last_owned
