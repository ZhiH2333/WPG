extends SceneTree

## 主菜单 UI Scale 响应式回归（200% → 逻辑视口 960x540）。
##
## 背景：`Home` 是 FULL_RECT 的 MarginContainer，场景里写死 `margin_right = 672`。
## 那 672 编码的是「1920 下版心 1200px」：UI Scale 200% 把逻辑视口压到 960 后，
## 容器最小宽度变成 48+内容+672 = 1228 > 960，装不下就按 grow_horizontal 居中溢出，
## 整列被推到 x = -134（截图里 "CONTINUE" 只剩 "NUE"）。顶栏同理：最小 1084 > 960，
## 居中后左边 HOME 被切、右边时钟被切。
##
## 现在：Home 的 margin_right 按视口算（1920 -> 672 一字不变，960 -> 48），
## 顶栏放不下整排时先摘掉右端时钟（只报时，不是导航）。
##
## 断言只用「与实时视口无关」的量（margin 覆盖值 / 容器最小宽度 / 时钟可见性规则），
## 这样在 CI 默认窗口下也不会飘。
##
## 跑法：godot --headless --path . --script res://tests/main_menu_fit_test.gd --quit
## 通过输出 MAIN_MENU_FIT_OK；失败逐条 MAIN_MENU_FIT_FAIL 并返回非 0。

const DESIGN_WIDTH: float = 1920.0
const NARROW_WIDTH: float = 960.0
const CONTENT_MARGIN: float = 48.0
const CONTENT_MAX_WIDTH: float = 1200.0

var _failures: PackedStringArray = PackedStringArray()

func _initialize() -> void:
	_run_all.call_deferred()

func _run_all() -> void:
	await process_frame
	PlayerProfile.load_from_disk()
	GameSettings.load_from_disk()
	var scene: PackedScene = load("res://ui/main_menu.tscn")
	_expect(scene != null, "main_menu.tscn 可加载")
	if scene == null:
		_finish()
		return
	var menu: MainMenu = scene.instantiate() as MainMenu
	root.add_child(menu)
	for _i: int in 6:
		await process_frame

	await _case_design_width_unchanged(menu)
	await _case_narrow_width_no_overflow(menu)
	await _case_top_bar_drops_clock_only_when_needed(menu)
	await _case_long_name_remeasures(menu)

	menu.queue_free()
	await process_frame
	_finish()

## 1920：版心必须仍是 1200px、margin_right 仍是旧值 672（不能改原设计）。
func _case_design_width_unchanged(menu: MainMenu) -> void:
	menu.sync_content_width_for(DESIGN_WIDTH)
	await process_frame
	var margin_right: int = menu._home.get_theme_constant("margin_right")
	_expect(margin_right == 672, "1920 宽下 margin_right 仍是 672（实际 %d）" % margin_right)
	var content_w: float = DESIGN_WIDTH - CONTENT_MARGIN - float(margin_right)
	_expect(is_equal_approx(content_w, CONTENT_MAX_WIDTH),
		"1920 宽下版心仍是 %.0fpx（实际 %.0f）" % [CONTENT_MAX_WIDTH, content_w])
	_expect(menu._time_box.visible, "1920 宽下顶栏时钟可见")

## 960（UI Scale 200%）：容器最小宽度必须收进视口，不能再居中溢出。
func _case_narrow_width_no_overflow(menu: MainMenu) -> void:
	menu.sync_content_width_for(NARROW_WIDTH)
	await process_frame
	var margin_right: int = menu._home.get_theme_constant("margin_right")
	_expect(margin_right == 48, "960 宽下 margin_right 收到 48（实际 %d）" % margin_right)
	var home_min: float = menu._home.get_combined_minimum_size().x
	_expect(home_min <= NARROW_WIDTH + 0.5,
		"960 宽下 Home 最小宽度 %.0f <= %.0f（否则整列居中溢出）" % [home_min, NARROW_WIDTH])
	## 版心本身也得装得下内容列的最小宽度，否则内容被裁。
	var inner_min: float = menu._home.get_node("Body").get_combined_minimum_size().x
	var content_w: float = NARROW_WIDTH - CONTENT_MARGIN - float(margin_right)
	_expect(content_w >= inner_min,
		"960 宽下版心 %.0f >= Body 最小宽度 %.0f" % [content_w, inner_min])
	## Quit 贴右下角，任何宽度下都必须在视口内。
	var quit_rect: Rect2 = menu._quit_button.get_global_rect()
	_expect(quit_rect.end.x <= root.get_visible_rect().size.x + 0.5,
		"Quit 右端 %.0f 不超出视口" % quit_rect.end.x)

## 顶栏：放不下整排才摘时钟；放得下必须留着，导航永远不能被裁。
func _case_top_bar_drops_clock_only_when_needed(menu: MainMenu) -> void:
	var full_min: float = menu.get_top_bar_full_min_width()
	var nav_min: float = menu.get_top_bar_nav_min_width()
	_expect(nav_min > 0.0 and full_min > 0.0, "顶栏两档最小宽度都量到了")
	_expect(full_min > nav_min, "带时钟的整排比只留导航宽（否则这条测试没意义）")

	menu.sync_top_bar_for(NARROW_WIDTH)
	await process_frame
	_expect(menu._time_box.visible == (full_min <= NARROW_WIDTH + 0.5),
		"时钟可见性 = 整排放得下（full_min=%.0f, 视口=%.0f）" % [full_min, NARROW_WIDTH])
	_expect(menu._top_bar.get_combined_minimum_size().x <= NARROW_WIDTH + 0.5,
		"960 宽下顶栏最小宽度 %.0f <= %.0f（导航不被裁）" % [menu._top_bar.get_combined_minimum_size().x, NARROW_WIDTH])

	menu.sync_top_bar_for(DESIGN_WIDTH)
	await process_frame
	_expect(menu._time_box.visible, "1920 宽下时钟回来")
	_expect(menu._top_bar.get_combined_minimum_size().x <= DESIGN_WIDTH + 0.5,
		"1920 宽下顶栏放得下")

## 玩家名会改 PROFILE 按钮宽度 -> 顶栏最小宽度，所以 refresh_profile_label 必须重新量。
##
## 基准量 nav 档（`get_top_bar_nav_min_width()`，量时把时钟藏掉），不能量 full 档：
## `_ready()` 里 `refresh_profile_label()`(ui/main_menu.gd:96) 早于 `_refresh_clock(true)`(:134)，
## 所以 full 档那次缓存是时钟还写着场景默认 "00:00:00" 时量出来的；而之后每次量用的都是真时钟。
## 主题字体数字是比例字宽，时钟里 '1' 够多就窄 1px（"00:00:00" 162px -> "11:17:53" 161px），
## full 档因此会随墙上时钟抖 1px，这条断言就成了看当前几点。nav 档完全不含时钟，是稳定的量。
func _case_long_name_remeasures(menu: MainMenu) -> void:
	var original: String = PlayerProfile.get_display_name()
	menu._measure_top_bar()
	var before: float = menu.get_top_bar_nav_min_width()
	PlayerProfile.set_display_name("AVeryLongPlayerName")
	menu.refresh_profile_label()
	await process_frame
	var after: float = menu.get_top_bar_nav_min_width()
	_expect(after > before + 1.0, "名字变长后顶栏最小宽度被重新量到（%.0f -> %.0f）" % [before, after])
	PlayerProfile.set_display_name(original)
	menu.refresh_profile_label()
	await process_frame
	_expect(is_equal_approx(menu.get_top_bar_nav_min_width(), before),
		"名字改回去后最小宽度回到原值")

func _finish() -> void:
	if _failures.is_empty():
		print("MAIN_MENU_FIT_OK")
		quit(0)
		return
	for failure: String in _failures:
		printerr("MAIN_MENU_FIT_FAIL: %s" % failure)
	quit(1)

func _expect(condition: bool, label: String) -> void:
	if not condition:
		_failures.append(label)
