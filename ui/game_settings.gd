extends Object
class_name GameSettings

## 音量与全屏。全是 static，不是 Autoload，不进场景树。
const PATH := "user://settings.cfg"
const DEFAULT_VOLUME: float = 1.0
const MUTE_THRESHOLD: float = 0.001

static var _volume: float = DEFAULT_VOLUME
static var _fullscreen: bool = false

static func load_from_disk() -> void:
	_volume = DEFAULT_VOLUME
	_fullscreen = false
	if not FileAccess.file_exists(PATH):
		return
	var cfg: ConfigFile = ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	_volume = clampf(float(cfg.get_value("audio", "volume", DEFAULT_VOLUME)), 0.0, 1.0)
	_fullscreen = bool(cfg.get_value("display", "fullscreen", false))

static func save_to_disk() -> void:
	var cfg: ConfigFile = ConfigFile.new()
	cfg.set_value("audio", "volume", _volume)
	cfg.set_value("display", "fullscreen", _fullscreen)
	cfg.save(PATH)

static func apply() -> void:
	var bus: int = AudioServer.get_bus_index("Master")
	if _volume <= MUTE_THRESHOLD:
		AudioServer.set_bus_mute(bus, true)
	else:
		AudioServer.set_bus_mute(bus, false)
		AudioServer.set_bus_volume_db(bus, linear_to_db(clampf(_volume, MUTE_THRESHOLD, 1.0)))
	if _fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)

static func get_volume() -> float:
	return _volume

static func set_volume(value: float) -> void:
	_volume = clampf(value, 0.0, 1.0)

static func is_fullscreen() -> bool:
	return _fullscreen

static func set_fullscreen(enabled: bool) -> void:
	_fullscreen = enabled
