extends CanvasLayer
class_name LoadingScreen

## 菜单↔沙盒换场盖：不是 Autoload。挂在树根上贯穿全程，禁止中途再换成第二张加载页。Retry 不走这里。
const PATH := "res://ui/loading_screen.tscn"
const MENU_SCENE := "res://ui/main_menu.tscn"
const LAYER_INDEX: int = 80
const MIN_HOLD_SEC: float = 0.35
const BAR_CYCLE_SEC: float = 0.42
const BAR_BASE_W: float = 240.0
const BAR_TAIL_FOLLOW: float = 10.0
const BAR_STRETCH_MAX: float = 88.0
const STATUS_STEP_SEC: float = 0.06
const REVEAL_DELAY_SEC: float = 0.05

static var _active: LoadingScreen = null

var _target_path: String = ""
var _hold_left: float = 0.0
var _reveal_left: float = 0.0
var _leave_ready: bool = false
var _bar_time: float = 0.0
var _bar_stretch: float = 0.0
var _status_time: float = 0.0
var _switching: bool = false
var _revealing: bool = false
var _items: PackedStringArray = PackedStringArray()

@onready var _root: Control = $Root
@onready var _version_label: Label = $Root/Center/Column/VersionLabel
@onready var _bar_track: ColorRect = $Root/Center/Column/BarTrack
@onready var _bar_fill: ColorRect = $Root/Center/Column/BarTrack/BarFill
@onready var _status_label: Label = $Root/Center/Column/StatusLabel

static func present_on(host: Node, next_scene: String) -> void:
	GameLaunch.set_next_scene(next_scene)
	if not next_scene.is_empty():
		ResourceLoader.load_threaded_request(next_scene)
	if host == null:
		return
	var tree: SceneTree = host.get_tree()
	var cover: LoadingScreen = _ensure_cover(tree)
	if cover == null:
		return
	cover.present_cover()

static func switch_current(tree: SceneTree) -> void:
	var cover: LoadingScreen = _find_active(tree)
	if cover != null:
		cover.mark_leave_ready()
		return
	var path: String = GameLaunch.take_next_scene()
	if path.is_empty():
		path = MENU_SCENE
	if tree != null:
		tree.change_scene_to_file(path)

static func _ensure_cover(tree: SceneTree) -> LoadingScreen:
	var cover: LoadingScreen = _find_active(tree)
	if cover != null:
		return cover
	if tree == null:
		return null
	var packed: PackedScene = load(PATH) as PackedScene
	if packed == null:
		return null
	cover = packed.instantiate() as LoadingScreen
	if cover == null:
		return null
	tree.root.add_child(cover)
	_active = cover
	return cover

static func _find_active(tree: SceneTree) -> LoadingScreen:
	if _active != null and is_instance_valid(_active):
		return _active
	_active = null
	if tree == null:
		return null
	for child: Node in tree.root.get_children():
		var cover: LoadingScreen = child as LoadingScreen
		if cover != null:
			_active = cover
			return cover
	return null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = LAYER_INDEX
	visible = true
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_version_label.text = "version  %s" % GameSettings.get_version()
	_root.modulate.a = 0.0
	_bind_target()

func _exit_tree() -> void:
	if _active == self:
		_active = null

func present_cover() -> void:
	visible = true
	_leave_ready = false
	_switching = false
	_revealing = false
	_hold_left = MIN_HOLD_SEC
	_bind_target()
	if _root.modulate.a < 0.99:
		UiAnim.fade_modulate(self, _root, 1.0, UiAnim.DIMMER_FADE_SEC, true)
	else:
		_root.modulate.a = 1.0
	var parent: Node = get_parent()
	if parent != null:
		parent.move_child(self, -1)

func mark_leave_ready() -> void:
	_leave_ready = true

func _process(delta: float) -> void:
	_tick_bar(delta)
	var status: ResourceLoader.ThreadLoadStatus = _query_status()
	_tick_status(delta, status != ResourceLoader.THREAD_LOAD_IN_PROGRESS)
	if _revealing:
		_reveal_left -= delta
		if _reveal_left <= 0.0:
			_revealing = false
			_fade_out_and_free()
		return
	if not _leave_ready or _switching:
		return
	_hold_left -= delta
	if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		return
	if _hold_left > 0.0:
		return
	_switch_to_target(status)

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_pressed():
		GameAudio.unlock_driver(self)
	get_viewport().set_input_as_handled()

func _bind_target() -> void:
	_target_path = GameLaunch.peek_next_scene()
	if _target_path.is_empty():
		_target_path = MENU_SCENE
	_items = _collect_items(_target_path)
	_status_time = 0.0
	_tick_status(0.0, false)

func _query_status() -> ResourceLoader.ThreadLoadStatus:
	if _target_path.is_empty():
		return ResourceLoader.THREAD_LOAD_INVALID_RESOURCE
	return ResourceLoader.load_threaded_get_status(_target_path)

func _tick_bar(delta: float) -> void:
	_bar_time += delta
	var track_w: float = maxf(_bar_track.size.x, BAR_BASE_W)
	var travel: float = maxf(track_w - BAR_BASE_W, 0.0)
	var phase: float = _bar_time * PI / BAR_CYCLE_SEC
	var ping: float = 0.5 - 0.5 * cos(phase)
	var speed: float = absf(sin(phase))
	var target_stretch: float = BAR_STRETCH_MAX * speed * speed * (3.0 - 2.0 * speed)
	_bar_stretch = lerpf(_bar_stretch, target_stretch, 1.0 - exp(-BAR_TAIL_FOLLOW * delta))
	var going_right: bool = sin(phase) >= 0.0
	var base_left: float = ping * travel
	var left: float = base_left - _bar_stretch if going_right else base_left
	var width: float = BAR_BASE_W + _bar_stretch
	left = clampf(left, 0.0, maxf(track_w - BAR_BASE_W, 0.0))
	width = minf(width, track_w - left)
	_bar_fill.position = Vector2(left, 0.0)
	_bar_fill.size = Vector2(maxf(width, 1.0), _bar_track.size.y)

func _tick_status(delta: float, loaded: bool) -> void:
	_status_time += delta
	if _items.is_empty():
		_status_label.text = "ready" if loaded else "loading"
		return
	var last: int = _items.size() - 1
	var stepped: int = mini(int(_status_time / STATUS_STEP_SEC), last)
	if loaded and stepped >= last:
		_status_label.text = "ready"
		return
	_status_label.text = "loading  %s" % _items[stepped]

func _collect_items(path: String) -> PackedStringArray:
	var items: PackedStringArray = PackedStringArray()
	var seen: Dictionary = {}
	_add_item(items, seen, path)
	for dep: String in ResourceLoader.get_dependencies(path):
		_add_item(items, seen, dep)
	return items

func _add_item(items: PackedStringArray, seen: Dictionary, path: String) -> void:
	var label: String = _format_item(path)
	if label.is_empty() or seen.has(label):
		return
	seen[label] = true
	items.append(label)

func _format_item(path: String) -> String:
	var clean: String = path.get_slice("::", 0)
	var stem: String = clean.get_file().get_basename()
	if stem.is_empty() or stem.begins_with("loading_"):
		return ""
	return stem.replace("_", " ").replace("-", " ")

func _switch_to_target(status: ResourceLoader.ThreadLoadStatus) -> void:
	_switching = true
	GameLaunch.take_next_scene()
	var tree: SceneTree = get_tree()
	if tree == null:
		return
	if status == ResourceLoader.THREAD_LOAD_LOADED:
		var packed: PackedScene = ResourceLoader.load_threaded_get(_target_path) as PackedScene
		if packed != null:
			tree.change_scene_to_packed(packed)
			_begin_reveal()
			return
	tree.change_scene_to_file(_target_path)
	_begin_reveal()

func _begin_reveal() -> void:
	_root.modulate.a = 1.0
	_revealing = true
	_reveal_left = REVEAL_DELAY_SEC

func _fade_out_and_free() -> void:
	var tween: Tween = UiAnim.fade_modulate(self, _root, 0.0, UiAnim.DIMMER_FADE_SEC, true)
	if tween == null:
		queue_free()
		return
	tween.finished.connect(queue_free)
