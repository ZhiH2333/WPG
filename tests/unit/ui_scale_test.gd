extends SceneTree

## UI Scale 响应式回归（200% = 逻辑视口 960x540）。
##
## 背景：winner_page / profile_overlay 把「1920 宽下版心 1200px」写死成 `offset_right = -672`，
## 又把内容列做成 FULL_RECT。UI Scale 调到 200% 时逻辑视口只剩 960x540：
##   横向 —— 同一组缩进把内容列压到 240px，而内容最少要 788px → 裁切（截图里的 "CORE 11172"）。
##   纵向 —— 内容高 754px，视口只有 540px。
##
## 现在的结构：Sheet = ScrollContainer（宽度承载者 + 可滚动），Column 交给容器排版。
## 本测试锁两轴：
##   宽度：960 下 Sheet 算出的宽度必须 >= 内容最小宽度，且 1920 下必须仍是原设计的 1200px。
##   高度：内容比 540 高时，Sheet 必须能纵向滚动（否则就是不可达的裁切）。
##
## 跑法：godot --headless --path . --script res://tests/ui_scale_test.gd
## 通过输出 UI_SCALE_OK；失败逐条 UI_SCALE_FAIL 并返回非 0。

const MARGIN: float = 48.0
const MAX_WIDTH: float = 1200.0
const LIMIT_WIDTH: float = 960.0
const LIMIT_HEIGHT: float = 540.0
## 真实目标机型：1080x2280 + UI Scale 200% → 逻辑 540x1140。
const PHONE_WIDTH: float = 540.0
const PHONE_HEIGHT: float = 1140.0

## page 场景 -> [宽度承载者(Sheet), 内容列(Column)]
const PAGES := {
	"res://ui/winner_page.tscn": ["Root/Sheet", "Root/Sheet/Column"],
	"res://ui/profile_overlay.tscn": ["Sheet", "Sheet/Column"],
	"res://ui/play_page.tscn": ["Sheet/Column", "Sheet/Column"],
}

var _failures: PackedStringArray = PackedStringArray()

func _initialize() -> void:
	_run_all.call_deferred()

func _run_all() -> void:
	PlayerProfile.load_from_disk()
	_case_width_math()
	_case_pages_responsive()
	_case_modal_panels_fit()
	_case_remaining_pages()
	await _case_settings_controls_fit()
	if _failures.is_empty():
		print("UI_SCALE_OK")
		quit(0)
		return
	for failure: String in _failures:
		printerr("UI_SCALE_FAIL: %s" % failure)
	quit(1)

## 1) 版心换算：1920 必须与旧设计完全一致，窄视口必须收窄。
func _case_width_math() -> void:
	_expect(is_equal_approx(UiFit.content_width_for(1920.0, MARGIN, MAX_WIDTH), 1200.0),
		"1920 宽下版心仍是 1200px（不改原设计）")
	_expect(is_equal_approx(UiFit.content_offset_right(1920.0, MARGIN, MAX_WIDTH), -672.0),
		"1920 宽下 offset_right 仍是旧值 -672")
	_expect(is_equal_approx(UiFit.content_width_for(960.0, MARGIN, MAX_WIDTH), 864.0),
		"960 宽（200% UI Scale）下版心收到 864px")
	_expect(is_equal_approx(UiFit.content_offset_right(960.0, MARGIN, MAX_WIDTH), -48.0),
		"960 宽下 offset_right 收到 -48")
	_expect(UiFit.content_width_for(200.0, MARGIN, MAX_WIDTH) >= 320.0,
		"极窄视口有 320px 下限，不会算出负宽度")

## 2) 真实页面：两轴都要成立。
func _case_pages_responsive() -> void:
	for page_path: String in PAGES:
		var paths: Array = PAGES[page_path]
		var packed: PackedScene = load(page_path) as PackedScene
		_expect(packed != null, "%s 能加载" % page_path)
		if packed == null:
			continue
		var page: Node = packed.instantiate()
		root.add_child(page)
		var sheet: Control = page.get_node_or_null(String(paths[0])) as Control
		var content: Control = page.get_node_or_null(String(paths[1])) as Control
		_expect(sheet != null, "%s 找到 Sheet %s" % [page_path, paths[0]])
		_expect(content != null, "%s 找到内容列 %s" % [page_path, paths[1]])
		if sheet == null or content == null:
			page.queue_free()
			continue
		var needed: Vector2 = content.get_combined_minimum_size()

		## 横向：强制 200% 那一档（逻辑视口 960），内容必须放得下。
		## 旧代码在这里算出 240 < 788，直接失败。
		page.call("sync_content_width_for", LIMIT_WIDTH)
		var width_960: float = LIMIT_WIDTH + sheet.offset_right - sheet.offset_left
		_expect(width_960 >= needed.x - 0.5,
			"%s 在 960 逻辑宽下内容列宽 %.0f 必须 >= 内容最小宽 %.0f（否则横向裁切）" % [
				page_path, width_960, needed.x,
			])
		_expect(is_equal_approx(sheet.offset_right, UiFit.content_offset_right(LIMIT_WIDTH, MARGIN, MAX_WIDTH)),
			"%s 在 960 下 offset_right 应为 %.1f，实为 %.1f" % [
				page_path, UiFit.content_offset_right(LIMIT_WIDTH, MARGIN, MAX_WIDTH), sheet.offset_right,
			])

		## 横向：回到 1920 必须与旧设计一致，不能为了窄屏把宽屏改坏。
		page.call("sync_content_width_for", 1920.0)
		var width_1920: float = 1920.0 + sheet.offset_right - sheet.offset_left
		_expect(is_equal_approx(width_1920, MAX_WIDTH),
			"%s 在 1920 下版心必须仍是 %.0f，实为 %.0f" % [page_path, MAX_WIDTH, width_1920])
		_expect(width_1920 >= needed.x - 0.5, "%s 在 1920 下当然也要放得下" % page_path)

		## 纵向：内容比视口高时，必须能滚 —— 否则那部分内容是不可达的裁切。
		if needed.y > LIMIT_HEIGHT:
			var scroll: ScrollContainer = sheet as ScrollContainer
			_expect(scroll != null,
				"%s 内容高 %.0f > %.0f，Sheet 必须是 ScrollContainer 才能滚" % [
					page_path, needed.y, LIMIT_HEIGHT,
				])
			if scroll != null:
				_expect(scroll.vertical_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED,
					"%s Sheet 必须允许纵向滚动（内容 %.0f > 视口 %.0f）" % [
						page_path, needed.y, LIMIT_HEIGHT,
					])
		page.queue_free()

## 4) 剩下三页。区别在于「怎么可达」不一样：
##    play_page   —— 内容本来就放得下（实测 min 120x331），直接断言放得下。
##    settings / pause —— 自绘滚动：Clip 是带 clip_contents 的普通 Control，纵向由
##                        settings_overlay._layout_scroll() 驱动（不是 ScrollContainer），
##                        所以判据是「有自绘滚动」+「抽屉宽度 <= 960」。
##    （pause_overlay 内嵌 SettingsOverlay 实例，随它一起成立。）
func _case_remaining_pages() -> void:
	var play_packed: PackedScene = load("res://ui/play_page.tscn") as PackedScene
	_expect(play_packed != null, "play_page.tscn 能加载")
	if play_packed != null:
		var play: Node = play_packed.instantiate()
		root.add_child(play)
		var play_column: Control = play.find_child("Column", true, false) as Control
		_expect(play_column != null, "play_page 找到内容列")
		if play_column != null:
			var minimum: Vector2 = play_column.get_combined_minimum_size()
			_expect(minimum.x <= LIMIT_WIDTH + 0.5 and minimum.y <= LIMIT_HEIGHT + 0.5,
				"play_page 内容最小尺寸 (%.0f, %.0f) 必须放得进 %.0fx%.0f" % [
					minimum.x, minimum.y, LIMIT_WIDTH, LIMIT_HEIGHT,
				])
		play.queue_free()

	var settings_packed: PackedScene = load("res://ui/settings_overlay.tscn") as PackedScene
	_expect(settings_packed != null, "settings_overlay.tscn 能加载")
	if settings_packed != null:
		var settings: Node = settings_packed.instantiate()
		root.add_child(settings)
		var drawer: Control = settings.find_child("Drawer", true, false) as Control
		_expect(drawer != null, "settings_overlay 找到 Drawer")
		if drawer != null:
			_expect(drawer.offset_right <= LIMIT_WIDTH + 0.5,
				"settings 抽屉宽 %.0f 必须 <= %.0f" % [drawer.offset_right, LIMIT_WIDTH])
		## 内容比视口高时必须真的有滚动手段（自绘滚动），否则那部分不可达。
		var clip: Control = settings.find_child("Clip", true, false) as Control
		_expect(clip != null, "settings_overlay 找到 Clip")
		if clip != null:
			var content: Control = clip.find_child("Content", true, false) as Control
			if content != null and content.get_combined_minimum_size().y > LIMIT_HEIGHT:
				_expect(clip.clip_contents or clip is ScrollContainer,
					"settings 内容比视口高，Clip 必须裁剪（配合自绘滚动）")
				_expect(settings.has_method("_layout_scroll"),
					"settings 内容比视口高时必须存在自绘滚动 _layout_scroll()")
		settings.queue_free()

	## pause_overlay 内嵌同一个 SettingsOverlay 实例：随它一起成立，这里直接断言一次。
	var pause_packed: PackedScene = load("res://ui/pause_overlay.tscn") as PackedScene
	_expect(pause_packed != null, "pause_overlay.tscn 能加载")
	if pause_packed != null:
		var pause: Node = pause_packed.instantiate()
		root.add_child(pause)
		var pause_drawer: Control = pause.find_child("Drawer", true, false) as Control
		_expect(pause_drawer != null, "pause_overlay 内嵌的 settings 抽屉存在")
		if pause_drawer != null:
			_expect(pause_drawer.offset_right <= LIMIT_WIDTH + 0.5,
				"pause 内嵌抽屉宽 %.0f 必须 <= %.0f" % [pause_drawer.offset_right, LIMIT_WIDTH])
		pause.queue_free()

## 3) 浮动 Modal 面板：credits / shop / 三选一走 UiFit.apply_floating_panel，
##    它们靠自己收敛到可用空间（不是固定的 720x560）。这里锁住 540 逻辑高下必须收敛。
##    注意：这些面板的 scene 里写的 custom_minimum_size 是「未打开时」的占位值，
##    所以不能直接拿它当溢出判据 —— 必须看收敛后的尺寸。
func _case_modal_panels_fit() -> void:
	var preferreds: Array = [
		["credits", Vector2(720.0, 560.0)],
		["shop", Vector2(1120.0, 660.0)],
		["upgrade offer", Vector2(880.0, 360.0)],
	]
	for entry: Array in preferreds:
		var name: String = entry[0]
		var preferred: Vector2 = entry[1]
		## UiFit._fit_in 的公式：宽高各自 clamp 到 [min, preferred]，min 取 PANEL_MARGIN 之外。
		var fitted: Vector2 = UiFit._fit_in(Vector2(LIMIT_WIDTH, LIMIT_HEIGHT), preferred)
		_expect(fitted.x <= LIMIT_WIDTH + 0.5,
			"%s 面板收敛后宽 %.0f 必须 <= %.0f" % [name, fitted.x, LIMIT_WIDTH])
		_expect(fitted.y <= LIMIT_HEIGHT + 0.5,
			"%s 面板收敛后高 %.0f 必须 <= %.0f（打开时会调 _fit_panel）" % [
				name, fitted.y, LIMIT_HEIGHT,
			])

func _expect(condition: bool, label: String) -> void:
	if not condition:
		_failures.append(label)
## 5) Settings 抽屉在 200% UI Scale（逻辑 540，真机 1080x2280）下必须整节都放得下。
##    之前一行绑定 = 标签 + 键盘钮 160 + 手柄钮 160（最小 ~433），Body 被撑得比面板还宽，
##    再被 Panel.clip_contents 裁掉 —— 用户看到的「凸出去」。现在：
##      · 绑定行拆成两行，按钮可收缩（下限 88），放不下就竖排；
##      · Touch/Manual Fire 行也拆两行；
##      · 长文案（Render Resolution / 提示 / Data 警告）按可用宽度手动折行；
##      · RESTORE DEFAULTS / HOLD TO DELETE ALL DATA 开 autowrap，文字换行而不是裁掉。
##    所以四个 section 的 Body 最小宽度都必须 <= 面板内宽，抽屉还必须窄于屏幕。
func _case_settings_controls_fit() -> void:
	var packed: PackedScene = load("res://ui/settings_overlay.tscn") as PackedScene
	_expect(packed != null, "settings_overlay.tscn 能加载")
	if packed == null:
		return
	var overlay: Control = packed.instantiate() as Control
	root.add_child(overlay)
	## 真实条件：1080x2280 窗口 + UI Scale 200% = 逻辑 540x1140。
	overlay.size = Vector2(PHONE_WIDTH, PHONE_HEIGHT)
	overlay.call("_apply_drawer_layout")
	await process_frame
	overlay.size = Vector2(PHONE_WIDTH, PHONE_HEIGHT)
	overlay.call("_apply_drawer_layout")
	var ratio: float = float(overlay.get("PANEL_OF_REMAINDER"))
	var panel_min: float = float(overlay.get("PANEL_MIN_W"))
	var sidebar_ratio: float = float(overlay.get("SIDEBAR_RATIO"))
	var sidebar_min: float = float(overlay.get("SIDEBAR_MIN_W"))
	var body_inset: float = float(overlay.get("BODY_INSET"))
	_expect(panel_min > 0.0, "settings 定义了 PANEL_MIN_W")

	## 540 逻辑宽下按脚本里的常量算同样的宽度，别在这里另抄一份比例（抄了就会和数据源脱钩）。
	var sidebar: float = clampf(
		PHONE_WIDTH * sidebar_ratio, minf(sidebar_min, PHONE_WIDTH), PHONE_WIDTH)
	var available: float = PHONE_WIDTH - sidebar
	var panel: float = clampf(
		available * ratio, minf(panel_min, available), available)
	var drawer: float = sidebar + panel
	var body_w: float = panel - body_inset
	_expect(drawer < PHONE_WIDTH - 0.5,
		"540 逻辑宽下抽屉 %.0f 必须严格小于屏幕 %.0f（不能铺满整屏）" % [drawer, PHONE_WIDTH])

	## 四个 section 的 Body 都不能比面板内宽还宽，否则会被 Panel.clip_contents 裁掉。
	for section_name: String in ["AudioSection", "DisplaySection", "ControlsSection", "DataSection"]:
		var section_body: Control = overlay.get_node_or_null(
			"Drawer/Panel/Clip/Content/%s/Body" % section_name) as Control
		_expect(section_body != null, "找到 %s 的 Body" % section_name)
		if section_body == null:
			continue
		var needed: float = section_body.get_combined_minimum_size().x
		_expect(needed <= body_w + 0.5,
			"540（200%%）下 %s 的 Body 最小宽 %.0f 必须 <= 面板内宽 %.0f（否则被裁切）" % [
				section_name, needed, body_w,
			])

	var body: Control = overlay.get_node_or_null(
		"Drawer/Panel/Clip/Content/ControlsSection/Body") as Control
	if body != null:
		var widest: float = 0.0
		var rows: int = 0
		for child: Node in body.get_children():
			var row: Control = child as Control
			if row == null or not row.has_meta("settings_bind_row"):
				continue
			rows += 1
			widest = maxf(widest, row.get_combined_minimum_size().x)
		_expect(rows > 0, "Controls 至少有一行绑定")
		_expect(widest > 0.0, "绑定行的最小宽度必须 > 0")
		_expect(body_w >= widest - 0.5,
			"540（200%%）下面板内宽 %.0f 必须 >= 最宽绑定行 %.0f（否则横向溢出）" % [
				body_w, widest,
			])

	## 侧栏 tab 文案（最宽 "Controls"）不能被压掉：nav 一行 = 左缩进 + 图标 + 间距 + 文案 + 右缩进。
	for nav_name: String in ["AudioButton", "DisplayButton", "ControlsButton", "DataButton"]:
		var nav: Control = overlay.find_child(nav_name, true, false) as Control
		_expect(nav != null, "找到侧栏 %s" % nav_name)
		if nav == null:
			continue
		var row: Control = nav.get_node_or_null("Row") as Control
		_expect(row != null, "侧栏 %s 有 Row" % nav_name)
		if row == null:
			continue
		var nav_need: float = row.get_combined_minimum_size().x + row.offset_left - row.offset_right
		_expect(nav_need <= sidebar + 0.5,
			"540 下侧栏 %.0f 必须放得下 %s（需要 %.0f，否则文案被压掉）" % [
				sidebar, nav_name, nav_need,
			])

	## 1920（100%）下必须仍走原设计的 0.55 比例档，不能被下限改坏。
	var wide_sidebar: float = clampf(
		1920.0 * sidebar_ratio, minf(sidebar_min, 1920.0), 1920.0)
	var wide_available: float = 1920.0 - wide_sidebar
	var wide_panel: float = clampf(
		wide_available * ratio, minf(panel_min, wide_available), wide_available)
	_expect(is_equal_approx(wide_panel, wide_available * ratio),
		"1920 下面板必须仍走 0.55 比例档（不受下限影响），实为 %.1f" % wide_panel)
	overlay.queue_free()
