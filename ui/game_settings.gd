extends Object
class_name GameSettings

## 音量、显示与按键。全是 static，不是 Autoload，不进场景树。唯一读写 user://settings.cfg。
const VERSION: String = "1.0.0"
const PATH := "user://settings.cfg"
const DEFAULT_VOLUME: float = 1.0
const MUTE_THRESHOLD: float = 0.001
const REBINDABLE_ACTIONS: PackedStringArray = [
	"move_up",
	"move_down",
	"move_left",
	"move_right",
	"dash",
	"weapon_pistol",
	"weapon_shotgun",
	"weapon_rifle",
]
const DEFAULT_KEYS: Dictionary = {
	"move_up": KEY_W,
	"move_down": KEY_S,
	"move_left": KEY_A,
	"move_right": KEY_D,
	"dash": KEY_SPACE,
	"weapon_pistol": KEY_1,
	"weapon_shotgun": KEY_2,
	"weapon_rifle": KEY_3,
}
const ARROW_FALLBACK: Dictionary = {
	"move_up": KEY_UP,
	"move_down": KEY_DOWN,
	"move_left": KEY_LEFT,
	"move_right": KEY_RIGHT,
}

static var _volume: float = DEFAULT_VOLUME
static var _fullscreen: bool = false
static var _render_scale: float = 1.0
static var _ui_scale: float = 1.0
static var _vsync_enabled: bool = true
static var _msaa_index: int = 0
static var _key_overrides: Dictionary = {}

static func load_from_disk() -> void:
	_volume = DEFAULT_VOLUME
	_fullscreen = false
	_render_scale = 1.0
	_ui_scale = 1.0
	_vsync_enabled = true
	_msaa_index = 0
	_key_overrides.clear()
	if not FileAccess.file_exists(PATH):
		return
	var cfg: ConfigFile = ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	_volume = clampf(float(cfg.get_value("audio", "volume", DEFAULT_VOLUME)), 0.0, 1.0)
	_fullscreen = bool(cfg.get_value("display", "fullscreen", false))
	_render_scale = clampf(float(cfg.get_value("display", "render_scale", 1.0)), 0.1, 1.0)
	_ui_scale = clampf(float(cfg.get_value("display", "ui_scale", 1.0)), 0.8, 1.3)
	_vsync_enabled = bool(cfg.get_value("display", "vsync", true))
	_msaa_index = clampi(int(cfg.get_value("display", "msaa", 0)), 0, 3)
	for action: String in REBINDABLE_ACTIONS:
		var default_key: int = int(DEFAULT_KEYS[action])
		var stored: int = int(cfg.get_value("controls", action, default_key))
		if stored != default_key:
			_key_overrides[action] = stored

static func save_to_disk() -> void:
	var cfg: ConfigFile = ConfigFile.new()
	cfg.set_value("audio", "volume", _volume)
	cfg.set_value("display", "fullscreen", _fullscreen)
	cfg.set_value("display", "render_scale", _render_scale)
	cfg.set_value("display", "ui_scale", _ui_scale)
	cfg.set_value("display", "vsync", _vsync_enabled)
	cfg.set_value("display", "msaa", _msaa_index)
	for action: String in REBINDABLE_ACTIONS:
		cfg.set_value("controls", action, get_key_for_action(action))
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
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if _vsync_enabled else DisplayServer.VSYNC_DISABLED)
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree != null and tree.root != null:
		var root: Window = tree.root
		root.msaa_2d = [
			Viewport.MSAA_DISABLED,
			Viewport.MSAA_2X,
			Viewport.MSAA_4X,
			Viewport.MSAA_8X,
		][_msaa_index]
		root.content_scale_factor = _ui_scale
	_apply_key_bindings()

static func get_version() -> String:
	return VERSION

static func get_volume() -> float:
	return _volume

static func set_volume(value: float) -> void:
	_volume = clampf(value, 0.0, 1.0)

static func is_fullscreen() -> bool:
	return _fullscreen

static func set_fullscreen(enabled: bool) -> void:
	_fullscreen = enabled

static func get_render_scale() -> float:
	return _render_scale

static func set_render_scale(value: float) -> void:
	_render_scale = clampf(value, 0.1, 1.0)

static func get_ui_scale() -> float:
	return _ui_scale

static func set_ui_scale(value: float) -> void:
	_ui_scale = clampf(value, 0.8, 1.3)

static func is_vsync_enabled() -> bool:
	return _vsync_enabled

static func set_vsync_enabled(enabled: bool) -> void:
	_vsync_enabled = enabled

static func get_msaa_index() -> int:
	return _msaa_index

static func set_msaa_index(index: int) -> void:
	_msaa_index = clampi(index, 0, 3)

static func get_key_for_action(action: String) -> int:
	return int(_key_overrides.get(action, DEFAULT_KEYS.get(action, -1)))

static func set_key_for_action(action: String, physical_keycode: int) -> bool:
	if not REBINDABLE_ACTIONS.has(action):
		return false
	for other: String in REBINDABLE_ACTIONS:
		if other == action:
			continue
		if get_key_for_action(other) == physical_keycode:
			return false
	if physical_keycode == int(DEFAULT_KEYS[action]):
		_key_overrides.erase(action)
	else:
		_key_overrides[action] = physical_keycode
	return true

static func key_label_for_action(action: String) -> String:
	return OS.get_keycode_string(get_key_for_action(action) as Key)

static func action_display_name(action: String) -> String:
	match action:
		"move_up":
			return "Move Up"
		"move_down":
			return "Move Down"
		"move_left":
			return "Move Left"
		"move_right":
			return "Move Right"
		"dash":
			return "Dash"
		"weapon_pistol":
			return "Pistol"
		"weapon_shotgun":
			return "Shotgun"
		"weapon_rifle":
			return "Rifle"
		_:
			return action

static func _apply_key_bindings() -> void:
	for action: String in REBINDABLE_ACTIONS:
		if not InputMap.has_action(action):
			continue
		InputMap.action_erase_events(action)
		var primary: InputEventKey = InputEventKey.new()
		primary.device = -1
		primary.physical_keycode = get_key_for_action(action) as Key
		InputMap.action_add_event(action, primary)
		if not ARROW_FALLBACK.has(action):
			continue
		var arrow: InputEventKey = InputEventKey.new()
		arrow.device = -1
		arrow.physical_keycode = int(ARROW_FALLBACK[action]) as Key
		InputMap.action_add_event(action, arrow)
