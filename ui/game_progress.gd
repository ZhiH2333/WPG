extends Object
class_name GameProgress

## 跨局**全局统计**（总局数 / 历史最好 / 上一局的收尾数字）。全是 static，不是 Autoload，
## 不进场景树。不是中途续打。
##
## 数据边界（V2 Save Architecture 硬规定）：
## - 「当前 run progress」只有一个 authoritative source = SaveSlot.active_run（RunCheckpoint）。
## - GameProgress **绝不**保存 active_run / xp / level / gold 当前值 / 升级清单 / 任何 run state。
## - 更新入口**只有一个**：record_result(RunResult)。没产生 RunResult 的退出（例如中途 quit）
##   不得计入 runs_played —— 否则它就变成第二套 run-state source of truth。
## - 档位与局末账本归 GameSaveStore（records.json）；本文件只写 progress.cfg。
const PATH := "user://progress.cfg"

static var _best_loop: int = 0
static var _best_kills: int = 0
static var _best_score: int = 0
static var _runs_played: int = 0
static var _last_loop: int = 0
static var _last_kills: int = 0
static var _last_gold: int = 0
static var _last_time_sec: float = 0.0

static func load_from_disk() -> void:
	_best_loop = 0
	_best_kills = 0
	_best_score = 0
	_runs_played = 0
	_last_loop = 0
	_last_kills = 0
	_last_gold = 0
	_last_time_sec = 0.0
	if not FileAccess.file_exists(PATH):
		return
	var cfg: ConfigFile = ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	_best_loop = int(cfg.get_value("stats", "best_loop", 0))
	_best_kills = int(cfg.get_value("stats", "best_kills", 0))
	_best_score = int(cfg.get_value("stats", "best_score", 0))
	_runs_played = int(cfg.get_value("stats", "runs_played", 0))
	_last_loop = int(cfg.get_value("last", "loop", 0))
	_last_kills = int(cfg.get_value("last", "kills", 0))
	_last_gold = int(cfg.get_value("last", "gold", 0))
	_last_time_sec = float(cfg.get_value("last", "time_sec", 0.0))

static func save_to_disk() -> void:
	var cfg: ConfigFile = ConfigFile.new()
	cfg.set_value("stats", "best_loop", _best_loop)
	cfg.set_value("stats", "best_kills", _best_kills)
	cfg.set_value("stats", "best_score", _best_score)
	cfg.set_value("stats", "runs_played", _runs_played)
	cfg.set_value("last", "loop", _last_loop)
	cfg.set_value("last", "kills", _last_kills)
	cfg.set_value("last", "gold", _last_gold)
	cfg.set_value("last", "time_sec", _last_time_sec)
	cfg.save(PATH)

## 唯一更新入口：由一局的 RunResult 驱动。中途退出（没有 RunResult）不会走到这里。
static func record_result(result: RunResult) -> void:
	if result == null:
		return
	load_from_disk()
	_best_loop = maxi(_best_loop, result.loop_index)
	_best_kills = maxi(_best_kills, result.kill_count)
	_best_score = maxi(_best_score, result.score)
	_runs_played += 1
	_last_loop = result.loop_index
	_last_kills = result.kill_count
	_last_gold = result.gold
	_last_time_sec = result.elapsed_sec
	## 故意不记录本局获得的升级 / 物品清单：任何界面都不显示它（硬规定）。
	save_to_disk()

static func get_best_loop() -> int:
	return _best_loop

static func get_best_kills() -> int:
	return _best_kills

static func get_best_score() -> int:
	return _best_score

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
