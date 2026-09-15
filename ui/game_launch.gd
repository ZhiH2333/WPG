extends Object
class_name GameLaunch

## 一次性把模式和档位 id 带进沙盒。不是 Autoload，不是 Node，禁止 get_tree()。默认 Infinite，take 后打回 Infinite。只传 id，不塞 Record 对象。
enum Mode { SOLO, INFINITE }

const SOLO_LOOP_GOAL: int = 20 ## 硬锁 20，不要 2，不要 export

static var _mode: Mode = Mode.INFINITE
static var _active_record_id: String = ""

static func set_mode(mode: Mode) -> void:
	_mode = mode

static func take_mode() -> Mode:
	var current: Mode = _mode
	_mode = Mode.INFINITE
	return current

static func set_active_record_id(id: String) -> void:
	_active_record_id = id

static func take_active_record_id() -> String:
	var current: String = _active_record_id
	_active_record_id = ""
	return current
