extends Control

## 开屏：开屏字标 + 加载进度条。
##
## Godot 4 没有内建启动进度条 —— RenderingServer 只在启动时用
## `set_boot_image_with_stretch()` 画一次静态图，之后到主场景就绪之间没有任何绘制代码，
## 而且那段时间里还没有 GDScript 在跑。所以这里用一张极轻的场景顶上：它自身几乎瞬时
## 加载完，再把 `ui/main_menu.tscn` 放到后台线程加载并显示进度。
##
## 字标用与 `application/boot_splash` 完全相同的规则绘制（满宽等比、垂直居中，也就是
## stretch_mode=2 Keep Width），并且用同一张 `res://icons/splash.png`，
## 因此从引擎启动图切到本场景时画面不会跳。
##
## 进度条样式与 `ui/loading_screen.tscn` 保持一致（同一组颜色与 18px 高度），
## 这样开屏和换场封面的观感是连续的。
##
## 网页版会先把 `ui/test_build_notice.tscn`（测试版提示）盖在上面：提示页出现的那一刻，
## 主菜单已经在后台线程里加载，只是没挂进树所以不显示。玩家点「开始游玩」之后才换场。
const MENU_SCENE := "res://ui/main_menu.tscn"
const NOTICE_SCENE := "res://ui/test_build_notice.tscn"
const MIN_HOLD_SEC: float = 0.6 ## 加载常快于这段时间；用地板值保证进度条一定走完
const BAR_MAX_W: float = 720.0
const BAR_W_RATIO: float = 0.42
const BAR_H: float = 18.0
const BAR_Y_RATIO: float = 0.8 ## 字标正下方偏下，横向溢出时也不至于压到字标
const BAR_MIN_TAIL: float = 48.0
const RATIO_FOLLOW: float = 7.0
const FILL_MIN_W: float = 6.0
const BAR_DONE: float = 0.995 ## 进度条走满才换场，避免在 78% 处硬切
const FADE_SEC: float = 0.35 ## 开屏 → 主菜单的交叉渐入时长

var _elapsed: float = 0.0
var _ratio: float = 0.0
var _requested: bool = false
var _leaving: bool = false
## 测试版提示页。只有网页版会开；开了之后换场要等玩家点「开始游玩」。
var _notice: TestBuildNotice = null
var _notice_started: bool = false
## 本帧的主菜单加载状态。提示页要判断「能不能换场」时直接读它，不重复问一遍。
var _status: ResourceLoader.ThreadLoadStatus = ResourceLoader.THREAD_LOAD_INVALID_RESOURCE

@onready var _logo: TextureRect = $Logo
@onready var _bar_track: ColorRect = $BarTrack
@onready var _bar_fill: ColorRect = $BarTrack/BarFill


func _ready() -> void:
	_requested = ResourceLoader.load_threaded_request(MENU_SCENE) == OK
	resized.connect(_layout)
	_layout()
	_apply_ratio()
	_open_notice()


## 网页版（且玩家没勾「不再提示」）先把提示页盖上来。主菜单的线程加载不受影响，
## 所以提示页出现时主场景已经在加载了。
func _open_notice() -> void:
	if not TestBuildNotice.should_show():
		return
	var packed: PackedScene = load(NOTICE_SCENE) as PackedScene
	if packed == null:
		push_warning("boot_screen: 测试版提示页加载失败，直接进主菜单")
		return
	var notice: TestBuildNotice = packed.instantiate() as TestBuildNotice
	if notice == null:
		push_warning("boot_screen: 测试版提示页实例化失败，直接进主菜单")
		return
	notice.started.connect(_on_notice_started)
	add_child(notice)
	# 提示页是纯黑不透明的，字标和进度条已经被盖住了；显式藏掉是防止将来改版式时露出来。
	_logo.visible = false
	_bar_track.visible = false
	_notice = notice


func _on_notice_started() -> void:
	_notice_started = true
	# 加载还没完就把按钮切成「正在加载…」：玩家已经点过，不能让他以为没反应又点一次。
	if _notice != null and _status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		_notice.lock_for_loading()


func _process(delta: float) -> void:
	if _leaving:
		return
	_elapsed += delta
	var progress: Array = []
	var status: ResourceLoader.ThreadLoadStatus = ResourceLoader.THREAD_LOAD_INVALID_RESOURCE
	if _requested:
		status = ResourceLoader.load_threaded_get_status(MENU_SCENE, progress)
	_status = status
	var in_flight: bool = status == ResourceLoader.THREAD_LOAD_IN_PROGRESS
	var real: float = 0.0
	if progress.size() > 0:
		real = clampf(float(progress[0]), 0.0, 1.0)
	if not in_flight:
		real = 1.0
	var floor_ratio: float = clampf(_elapsed / MIN_HOLD_SEC, 0.0, 1.0)
	# 只前进不后退：真实进度偶尔会回跳，地板值保证条子不会倒着走。
	_ratio = maxf(_ratio, lerpf(_ratio, maxf(real, floor_ratio), 1.0 - exp(-RATIO_FOLLOW * delta)))
	_ratio = clampf(_ratio, 0.0, 1.0)
	_apply_ratio()
	if in_flight or _elapsed < MIN_HOLD_SEC or _ratio < BAR_DONE:
		return
	# 提示页开着时换场由玩家决定。走到这里主菜单一定加载完了，没点就继续等。
	if _notice != null:
		if not _notice_started:
			return
		_notice.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_leave(status)


func _layout() -> void:
	var vp: Vector2 = get_viewport_rect().size
	if vp.x <= 0.0 or vp.y <= 0.0:
		return
	var drawn_h: float = vp.x
	var tex: Texture2D = _logo.texture
	if tex != null and tex.get_width() > 0:
		drawn_h = vp.x * float(tex.get_height()) / float(tex.get_width())
	# 与 application/boot_splash 的 stretch_mode=2（Keep Width）逐像素对齐。
	_logo.position = Vector2(0.0, (vp.y - drawn_h) * 0.5)
	_logo.size = Vector2(vp.x, drawn_h)
	var bar_w: float = minf(vp.x * BAR_W_RATIO, BAR_MAX_W)
	var bar_y: float = clampf(
		vp.y * BAR_Y_RATIO, vp.y * 0.58, maxf(vp.y - BAR_H - BAR_MIN_TAIL, 0.0)
	)
	_bar_track.position = Vector2((vp.x - bar_w) * 0.5, bar_y)
	_bar_track.size = Vector2(bar_w, BAR_H)
	_apply_ratio()


func _apply_ratio() -> void:
	if _bar_track == null:
		return
	_bar_fill.size = Vector2(maxf(_bar_track.size.x * _ratio, FILL_MIN_W), BAR_H)


func _leave(status: ResourceLoader.ThreadLoadStatus) -> void:
	_leaving = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tree: SceneTree = get_tree()
	if tree == null:
		return
	var menu: Node = null
	if status == ResourceLoader.THREAD_LOAD_LOADED:
		var packed: PackedScene = ResourceLoader.load_threaded_get(MENU_SCENE) as PackedScene
		if packed != null:
			menu = packed.instantiate()
	if menu == null:
		# 加载失败（或资源类型不对）时退回同步加载，绝不把玩家卡在开屏。
		tree.change_scene_to_file(MENU_SCENE)
		return
	_cross_fade(tree, menu)


func _cross_fade(tree: SceneTree, menu: Node) -> void:
	# 交叉渐入：新场景挂到上层、从全透明淡到实心，开屏全程保持不透明当底。
	# 两层同时对淡会在中段把整屏拉向清屏色（叠一层的 alpha 被吃两次，画面暗一下），
	# 所以这里只淡入新场景，等它盖满再丢掉开屏。主菜单是全屏不透明背景，能盖干净。
	menu.modulate.a = 0.0
	tree.root.add_child(menu)
	tree.current_scene = menu
	var tween: Tween = UiAnim.fade_modulate(menu, menu, 1.0, FADE_SEC, true)
	if tween == null:
		queue_free()
		return
	tween.finished.connect(queue_free)
