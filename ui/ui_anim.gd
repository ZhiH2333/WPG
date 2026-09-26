extends Object
class_name UiAnim

## 按意图区分的 UI 过渡。只改 modulate / scale / offset，逻辑 open/close 仍然瞬时。
const DIMMER_FADE_SEC: float = 0.2
const CONTENT_FADE_SEC: float = 0.25
const PANEL_MOVE_SEC: float = 0.45
const PANEL_EXIT_SEC: float = 0.3
const OVERLAY_EXIT_SEC: float = 0.15
const PAGE_MOVE_SEC: float = 0.32
const PAGE_EXIT_SEC: float = 0.2
const PAGE_RISE_PX: float = 24.0
const PAGE_SLIDE_SEC: float = 0.32
const MODAL_ENTER_SCALE: float = 0.96
const MODAL_EXIT_SEC: float = 0.15
const HOVER_SEC: float = 0.12
const HOVER_SCALE: float = 1.02
const PUNCH_PEAK: float = 1.06
const PUNCH_SEC: float = 0.12
const CONNECTION_PULSE_SEC: float = 0.6
const DRAWER_SLIDE_SEC: float = 0.6
const DRAWER_FADE_SEC: float = 0.3
const DRAWER_CONTENT_FADE_SEC: float = 0.5
const DRAWER_NAV_STAGGER_SEC: float = 0.04
const OVERLAY_RISE_PX: float = PAGE_RISE_PX
const CARD_FADE_SEC: float = 0.22
const CARD_SCALE_SEC: float = 0.4
const CARD_START_SCALE: float = 0.9
const CARD_STAGGER_SEC: float = 0.06
const MENU_ITEM_FADE_SEC: float = 0.35
const MENU_ITEM_STAGGER_SEC: float = 0.07
const ERROR_FLASH_SEC: float = 0.12
const READY_FLASH_SEC: float = 0.06

## direction: 0 = 淡入 + 上浮（旧行为）；+1 = 从右侧滑入（app 式翻页）；-1 = 从左侧滑入。
static func enter_page(host: Node, dimmer: CanvasItem, panel: CanvasItem, ignore_pause: bool = false, direction: int = 0) -> Tween:
	var tween: Tween = _make_parallel(host, ignore_pause)
	_fade_dimmer(tween, dimmer, PAGE_MOVE_SEC, Tween.EASE_OUT)
	if direction == 0:
		_rise_page_in(tween, panel)
	else:
		_slide_panel(tween, panel, direction, true)
	return tween

## direction 与 enter_page 同一含义：+1 表示新页从右侧进 → 本页向左滑出。
static func exit_page(host: Node, dimmer: CanvasItem, panel: CanvasItem, ignore_pause: bool = false, direction: int = 0) -> Tween:
	var tween: Tween = _make_parallel(host, ignore_pause)
	var rest: Vector2 = Vector2.ZERO
	if panel != null:
		rest = panel.position
		tween.tween_property(panel, "modulate:a", 0.0, PAGE_EXIT_SEC).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_IN)
		if direction == 0:
			tween.tween_property(panel, "position:y", rest.y + PAGE_RISE_PX, PAGE_EXIT_SEC).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_IN)
		else:
			tween.tween_property(panel, "position:x", rest.x - float(direction) * _page_width(panel), PAGE_SLIDE_SEC).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_IN)
	if dimmer != null:
		tween.tween_property(dimmer, "modulate:a", 0.0, PAGE_EXIT_SEC).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(_reset_page.bind(dimmer, panel, rest))
	return tween

static func enter_modal(host: Node, dimmer: CanvasItem, content: CanvasItem, ignore_pause: bool = false) -> Tween:
	var tween: Tween = _make_parallel(host, ignore_pause)
	_fade_dimmer_in(tween, dimmer)
	if content != null:
		_set_center_pivot(content)
		content.scale = Vector2(MODAL_ENTER_SCALE, MODAL_ENTER_SCALE)
		content.modulate.a = 0.0
		tween.tween_property(content, "modulate:a", 1.0, CONTENT_FADE_SEC).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
		tween.tween_property(content, "scale", Vector2.ONE, CONTENT_FADE_SEC).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	return tween

static func exit_modal(host: Node, dimmer: CanvasItem, content: CanvasItem, ignore_pause: bool = false) -> Tween:
	var tween: Tween = _make_parallel(host, ignore_pause)
	if content != null:
		tween.tween_property(content, "modulate:a", 0.0, MODAL_EXIT_SEC).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_IN)
	if dimmer != null:
		tween.tween_property(dimmer, "modulate:a", 0.0, MODAL_EXIT_SEC).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(_reset_modal.bind(dimmer, content))
	return tween

static func enter_drawer(host: Node, drawer: Control, dimmer: CanvasItem, content: CanvasItem, navs: Array, drawer_width: float) -> Tween:
	var tween: Tween = _make_parallel(host, true)
	drawer.offset_left = -drawer_width
	drawer.offset_right = 0.0
	drawer.modulate.a = 1.0
	tween.tween_property(drawer, "offset_left", 0.0, DRAWER_SLIDE_SEC).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	tween.tween_property(drawer, "offset_right", drawer_width, DRAWER_SLIDE_SEC).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	if dimmer != null:
		dimmer.modulate.a = 0.0
		tween.tween_property(dimmer, "modulate:a", 1.0, DRAWER_FADE_SEC).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	if content != null:
		content.modulate.a = 0.0
		tween.tween_property(content, "modulate:a", 1.0, DRAWER_CONTENT_FADE_SEC).set_delay(DRAWER_SLIDE_SEC / 3.0).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	_stagger_navs(tween, navs)
	return tween

static func exit_drawer(host: Node, drawer: Control, dimmer: CanvasItem, drawer_width: float) -> Tween:
	var tween: Tween = _make_parallel(host, true)
	tween.tween_property(drawer, "offset_left", -drawer_width, DRAWER_SLIDE_SEC).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	tween.tween_property(drawer, "offset_right", 0.0, DRAWER_SLIDE_SEC).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	tween.tween_property(drawer, "modulate:a", 0.0, DRAWER_FADE_SEC).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	if dimmer != null:
		tween.tween_property(dimmer, "modulate:a", 0.0, DRAWER_FADE_SEC).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_IN)
	return tween

static func enter_cards(host: Node, cards: Array, ignore_pause: bool = false) -> Tween:
	var tween: Tween = _make_parallel(host, ignore_pause)
	_append_card_entries(tween, cards)
	return tween

static func enter_overlay(host: Node, dimmer: CanvasItem, content: CanvasItem, cards: Array, ignore_pause: bool = false) -> Tween:
	var tween: Tween = _make_parallel(host, ignore_pause)
	_fade_dimmer_in(tween, dimmer)
	_rise_panel_in(tween, content)
	_append_card_entries(tween, cards)
	return tween

static func exit_overlay(host: Node, root: CanvasItem, ignore_pause: bool = false) -> Tween:
	var tween: Tween = host.create_tween()
	if ignore_pause:
		tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(root, "modulate:a", 0.0, OVERLAY_EXIT_SEC).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_IN)
	return tween

static func enter_stagger_fade(host: Node, items: Array) -> Tween:
	var tween: Tween = host.create_tween().set_parallel(true)
	var order: int = 0
	for entry: Variant in items:
		var item: CanvasItem = entry as CanvasItem
		if item == null:
			continue
		item.modulate.a = 0.0
		tween.tween_property(item, "modulate:a", 1.0, MENU_ITEM_FADE_SEC).set_delay(MENU_ITEM_STAGGER_SEC * float(order)).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
		order += 1
	return tween

static func kill_tween(tween: Tween) -> void:
	if tween != null and tween.is_valid():
		tween.kill()

## 行级反馈：1.02 缩放 + 骨白下划线 + caption 提到 Ink。只改装饰，逻辑开关仍瞬时。
static func wire_row_feedback(host: Node, button: BaseButton, ink: Color) -> void:
	if host == null or button == null:
		return
	button.mouse_entered.connect(set_row_feedback.bind(host, button, true, ink))
	button.mouse_exited.connect(set_row_feedback.bind(host, button, false, ink))
	button.focus_entered.connect(set_row_feedback.bind(host, button, true, ink))
	button.focus_exited.connect(set_row_feedback.bind(host, button, false, ink))

static func set_row_feedback(host: Node, button: Control, active: bool, ink: Color) -> void:
	if host == null or button == null:
		return
	if button.has_meta(&"row_feedback_tween"):
		var previous: Tween = button.get_meta(&"row_feedback_tween")
		if previous.is_valid():
			previous.kill()
	button.pivot_offset = button.size * 0.5
	var target: Vector2 = Vector2(HOVER_SCALE, HOVER_SCALE) if active else Vector2.ONE
	var tween: Tween = host.create_tween()
	tween.tween_property(button, "scale", target, HOVER_SEC).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	button.set_meta(&"row_feedback_tween", tween)
	var mark: CanvasItem = button.get_node_or_null("Mark") as CanvasItem
	if mark != null:
		mark.visible = active
	var caption: Label = button.get_node_or_null("Text/Caption") as Label
	if caption == null:
		return
	if active:
		caption.add_theme_color_override("font_color", ink)
	else:
		caption.remove_theme_color_override("font_color")

static func punch_scale(host: Node, control: Control, peak: float, sec: float, ignore_pause: bool) -> Tween:
	if host == null or control == null:
		return null
	var tween: Tween = host.create_tween()
	if ignore_pause:
		tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	control.pivot_offset = control.custom_minimum_size * 0.5
	var half: float = sec * 0.5
	tween.tween_property(control, "scale", Vector2(peak, peak), half).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	tween.tween_property(control, "scale", Vector2.ONE, half).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_IN)
	return tween

static func fade_modulate(host: Node, control: CanvasItem, to_alpha: float, sec: float, ignore_pause: bool) -> Tween:
	if host == null or control == null:
		return null
	var tween: Tween = host.create_tween()
	if ignore_pause:
		tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	var ease: Tween.EaseType = Tween.EASE_IN if to_alpha <= 0.0 else Tween.EASE_OUT
	tween.tween_property(control, "modulate:a", to_alpha, sec).set_trans(Tween.TRANS_QUINT).set_ease(ease)
	return tween

static func flash_error(host: Node, control: CanvasItem, ignore_pause: bool = false) -> Tween:
	if host == null or control == null:
		return null
	var tween: Tween = host.create_tween()
	if ignore_pause:
		tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	var base: Color = control.modulate
	tween.tween_property(control, "modulate", Color(1.0, 0.45, 0.55, base.a), ERROR_FLASH_SEC).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	tween.tween_property(control, "modulate", base, ERROR_FLASH_SEC).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_IN)
	return tween

static func flash_ready(host: Node, control: CanvasItem, ignore_pause: bool = false) -> Tween:
	if host == null or control == null:
		return null
	var tween: Tween = host.create_tween()
	if ignore_pause:
		tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	var base: Color = control.modulate
	tween.tween_property(control, "modulate", Color(1.15, 1.15, 1.15, base.a), READY_FLASH_SEC).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	tween.tween_property(control, "modulate", base, READY_FLASH_SEC).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_IN)
	return tween

static func pulse_connection(host: Node, control: CanvasItem, ignore_pause: bool = false) -> Tween:
	if host == null or control == null:
		return null
	var tween: Tween = host.create_tween().set_loops()
	if ignore_pause:
		tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	control.modulate.a = 1.0
	tween.tween_property(control, "modulate:a", 0.55, CONNECTION_PULSE_SEC).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(control, "modulate:a", 1.0, CONNECTION_PULSE_SEC).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_IN_OUT)
	return tween

static func _make_parallel(host: Node, ignore_pause: bool) -> Tween:
	var tween: Tween = host.create_tween().set_parallel(true)
	if ignore_pause:
		tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	return tween

static func _fade_dimmer_in(tween: Tween, dimmer: CanvasItem) -> void:
	_fade_dimmer(tween, dimmer, DIMMER_FADE_SEC, Tween.EASE_OUT)

static func _fade_dimmer(tween: Tween, dimmer: CanvasItem, sec: float, ease: Tween.EaseType) -> void:
	if dimmer == null:
		return
	dimmer.modulate.a = 0.0
	tween.tween_property(dimmer, "modulate:a", 1.0, sec).set_trans(Tween.TRANS_QUINT).set_ease(ease)

static func _rise_page_in(tween: Tween, panel: CanvasItem) -> void:
	if panel == null:
		return
	var parent_container: Container = panel.get_parent() as Container
	if parent_container != null:
		parent_container.notification(Container.NOTIFICATION_SORT_CHILDREN)
	panel.modulate.a = 0.0
	var base_y: float = panel.position.y
	panel.position.y = base_y + PAGE_RISE_PX
	tween.tween_property(panel, "modulate:a", 1.0, PAGE_MOVE_SEC).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	tween.tween_property(panel, "position:y", base_y, PAGE_MOVE_SEC).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)

static func _rise_panel_in(tween: Tween, panel: CanvasItem) -> void:
	if panel == null:
		return
	var parent_container: Container = panel.get_parent() as Container
	if parent_container != null:
		parent_container.notification(Container.NOTIFICATION_SORT_CHILDREN)
	panel.modulate.a = 0.0
	var base_y: float = panel.position.y
	panel.position.y = base_y + PAGE_RISE_PX
	tween.tween_property(panel, "modulate:a", 1.0, CONTENT_FADE_SEC).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	tween.tween_property(panel, "position:y", base_y, PAGE_MOVE_SEC).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)

## 供 MainMenu 滑 Home 舞台块：direction = 新页进入的方向（+1 右侧）。
static func slide_out(host: Node, panel: CanvasItem, direction: int, fade: bool = false) -> Tween:
	var tween: Tween = host.create_tween().set_parallel(true)
	if panel == null:
		return tween
	var base_x: float = _base_x(panel)
	panel.position.x = base_x
	tween.tween_property(panel, "position:x", base_x - float(direction) * _page_width(panel), PAGE_SLIDE_SEC).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_IN)
	if fade:
		tween.tween_property(panel, "modulate:a", 0.0, PAGE_EXIT_SEC).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_IN)
	return tween

static func slide_in(host: Node, panel: CanvasItem, direction: int, fade: bool = false) -> Tween:
	var tween: Tween = host.create_tween().set_parallel(true)
	if panel == null:
		return tween
	var rest_x: float = _base_x(panel)
	panel.position.x = rest_x + float(direction) * _page_width(panel)
	tween.tween_property(panel, "position:x", rest_x, PAGE_SLIDE_SEC).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	if fade:
		panel.modulate.a = 0.0
		tween.tween_property(panel, "modulate:a", 1.0, PAGE_SLIDE_SEC).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	else:
		panel.modulate.a = 1.0
	return tween

static func _slide_panel(tween: Tween, panel: CanvasItem, direction: int, fade: bool) -> void:
	if panel == null:
		return
	var parent_container: Container = panel.get_parent() as Container
	if parent_container != null:
		parent_container.notification(Container.NOTIFICATION_SORT_CHILDREN)
	var rest_x: float = _base_x(panel)
	panel.position.x = rest_x + float(direction) * _page_width(panel)
	if fade:
		panel.modulate.a = 0.0
		tween.tween_property(panel, "modulate:a", 1.0, PAGE_SLIDE_SEC).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	tween.tween_property(panel, "position:x", rest_x, PAGE_SLIDE_SEC).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)

static func _page_width(panel: CanvasItem) -> float:
	if panel == null:
		return 0.0
	return maxf(panel.get_viewport_rect().size.x, 1.0)

## 面板的静止 x：第一次滑动时记下当时布局值，之后一直用它（Home 的父节点是 Control，
## 不是 Container，布局不会自己把被移动过的 position 收回来）。
static func _base_x(panel: CanvasItem) -> float:
	if panel.has_meta(&"page_base_x"):
		return float(panel.get_meta(&"page_base_x"))
	var parent_container: Container = panel.get_parent() as Container
	if parent_container != null:
		parent_container.notification(Container.NOTIFICATION_SORT_CHILDREN)
	var value: float = panel.position.x
	panel.set_meta(&"page_base_x", value)
	return value

static func _reset_page(dimmer: CanvasItem, panel: CanvasItem, rest: Vector2) -> void:
	if panel != null:
		panel.position = rest
		panel.modulate.a = 1.0
	if dimmer != null:
		dimmer.modulate.a = 1.0

static func _reset_modal(dimmer: CanvasItem, content: CanvasItem) -> void:
	if content != null:
		content.scale = Vector2.ONE
		content.modulate.a = 1.0
	if dimmer != null:
		dimmer.modulate.a = 1.0

static func _set_center_pivot(content: Control) -> void:
	var pivot_size: Vector2 = content.size
	if pivot_size == Vector2.ZERO:
		pivot_size = content.get_combined_minimum_size()
	content.pivot_offset = pivot_size * 0.5

static func _stagger_navs(tween: Tween, navs: Array) -> void:
	var delay: float = 0.0
	for entry: Variant in navs:
		var nav: CanvasItem = entry as CanvasItem
		if nav == null:
			continue
		nav.modulate.a = 0.0
		tween.tween_property(nav, "modulate:a", 1.0, DRAWER_CONTENT_FADE_SEC).set_delay(delay).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
		delay += DRAWER_NAV_STAGGER_SEC

static func _append_card_entries(tween: Tween, cards: Array) -> void:
	var order: int = 0
	for entry: Variant in cards:
		var card: Control = entry as Control
		if card == null or not card.visible:
			continue
		var delay: float = CARD_STAGGER_SEC * float(order)
		card.pivot_offset = card.custom_minimum_size * 0.5
		card.modulate.a = 0.0
		card.scale = Vector2(CARD_START_SCALE, CARD_START_SCALE)
		tween.tween_property(card, "modulate:a", 1.0, CARD_FADE_SEC).set_delay(delay).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
		tween.tween_property(card, "scale", Vector2.ONE, CARD_SCALE_SEC).set_delay(delay).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		order += 1
