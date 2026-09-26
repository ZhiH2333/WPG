extends Object
class_name UiFit

## 按可见逻辑尺寸收缩大面板和两列卡片。content_scale_factor 已经放大整棵树，禁止再乘 ui_scale。
## 商店 CanvasLayer：Root/Center 刚显示时可能是 (0, 0)，按视口逻辑尺寸钉住再居中。
## 主菜单叠层：FULL_RECT + offset_top=60。打开时 host.size 往往还是整屏，CenterContainer 会按整屏居中，进场动画再把这个偏下的 y 锁住；改窗口才会重新 sort。只钉 Center 到「视口减去顶栏」的剩余矩形，不改叠层自己的 FULL_RECT。
## 宽高各自钳，不锁死设计稿宽高比。句读三选一走 offer_panel_size，禁止走 _fit_in（MIN_PANEL_HEIGHT 会把小面板撑成商店高）。
## 尺寸阶梯（2026-09-26 统一）：页面不再用大面板（走 48 margin 的 Page 布局），本文件只剩 Modal：商店 1120x660、三选一 880x360、通用 Modal 960x640。
const DESIGN := Vector2(1920, 1080)
const PREFERRED_PANEL := Vector2(960, 640)
const PREFERRED_CARD := Vector2(560, 120)
const PREFERRED_PORTRAIT: float = 96.0
const SHOP_PANEL_MAX := Vector2(1120, 660)
const OFFER_PANEL_MAX := Vector2(880, 360)
const OFFER_PANEL_MIN := Vector2(720, 280)
const PANEL_MARGIN: float = 48.0
const CARD_H_SEP: float = 16.0
const CARD_INSET: float = 104.0
const MIN_CARD_WIDTH: float = 360.0
const MIN_CARD_HEIGHT: float = 96.0
const MAX_CARD_HEIGHT: float = 144.0
const MIN_PANEL_WIDTH: float = 640.0
const MIN_PANEL_HEIGHT: float = 320.0
const MIN_PORTRAIT: float = 64.0

static func visible_size(from: CanvasItem) -> Vector2:
	if from != null:
		var logical: Vector2 = from.get_viewport_rect().size
		if logical.x > 1.0 and logical.y > 1.0:
			return logical
		var vp: Viewport = from.get_viewport()
		if vp != null:
			var vis: Vector2 = vp.get_visible_rect().size
			if vis.x > 1.0 and vis.y > 1.0:
				var stretch: Vector2 = vp.get_stretch_transform().get_scale()
				if stretch.x > 0.001 and stretch.y > 0.001:
					return Vector2(vis.x / stretch.x, vis.y / stretch.y)
				return vis
	return DESIGN

static func leftover_size(from: CanvasItem) -> Vector2:
	var vis: Vector2 = visible_size(from)
	var control: Control = from as Control
	if control != null:
		vis.y = maxf(vis.y - maxf(control.offset_top, 0.0), 1.0)
	return vis

static func pin_to_visible(ctrl: Control, vis: Vector2) -> void:
	if ctrl == null or vis.x < 1.0 or vis.y < 1.0:
		return
	ctrl.anchor_left = 0.0
	ctrl.anchor_top = 0.0
	ctrl.anchor_right = 0.0
	ctrl.anchor_bottom = 0.0
	ctrl.offset_left = 0.0
	ctrl.offset_top = 0.0
	ctrl.offset_right = vis.x
	ctrl.offset_bottom = vis.y

static func panel_size(from: CanvasItem) -> Vector2:
	return _fit_in(leftover_size(from), PREFERRED_PANEL)

static func shop_panel_size(from: CanvasItem) -> Vector2:
	return _fit_in(leftover_size(from), SHOP_PANEL_MAX)

static func offer_panel_size(from: CanvasItem) -> Vector2:
	var leftover: Vector2 = leftover_size(from)
	return Vector2(
		clampf(leftover.x - PANEL_MARGIN, OFFER_PANEL_MIN.x, OFFER_PANEL_MAX.x),
		clampf(leftover.y - PANEL_MARGIN, OFFER_PANEL_MIN.y, OFFER_PANEL_MAX.y)
	)

static func _fit_in(avail: Vector2, preferred: Vector2, min_size: Vector2 = Vector2(MIN_PANEL_WIDTH, MIN_PANEL_HEIGHT)) -> Vector2:
	return Vector2(
		minf(preferred.x, maxf(min_size.x, avail.x - PANEL_MARGIN)),
		minf(preferred.y, maxf(min_size.y, avail.y - PANEL_MARGIN))
	)

static func apply_floating_panel(host: Control, panel: Control, preferred: Vector2 = PREFERRED_PANEL, min_size: Vector2 = Vector2(MIN_PANEL_WIDTH, MIN_PANEL_HEIGHT)) -> Vector2:
	var vis: Vector2 = visible_size(host)
	var inset: float = 0.0
	if host != null:
		inset = maxf(host.offset_top, 0.0)
		if inset <= 0.0:
			pin_to_visible(host, vis)
	var leftover: Vector2 = Vector2(vis.x, maxf(vis.y - inset, 1.0))
	var fitted: Vector2 = _fit_in(leftover, preferred, min_size)
	panel.custom_minimum_size = fitted
	var center: Control = panel.get_parent() as Control
	if center != null and center != host:
		pin_to_visible(center, leftover)
		center.notification(Container.NOTIFICATION_SORT_CHILDREN)
	return fitted

static func card_size(panel_w: float, columns: int = 2) -> Vector2:
	var cols: int = maxi(columns, 1)
	var inner: float = panel_w - CARD_INSET - CARD_H_SEP * float(cols - 1)
	var width: float = inner / float(cols)
	var height: float = clampf(width * PREFERRED_CARD.y / PREFERRED_CARD.x, MIN_CARD_HEIGHT, MAX_CARD_HEIGHT)
	return Vector2(width, height)

static func portrait_px(card: Vector2) -> float:
	return clampf(PREFERRED_PORTRAIT * (card.x / PREFERRED_CARD.x), MIN_PORTRAIT, PREFERRED_PORTRAIT)

static func card_columns(panel_w: float) -> int:
	if card_size(panel_w, 2).x < MIN_CARD_WIDTH:
		return 1
	return 2

static func connect_refit(host: Control, on_refit: Callable) -> void:
	if not host.resized.is_connected(on_refit):
		host.resized.connect(on_refit)
	var vp: Viewport = host.get_viewport()
	if vp != null and not vp.size_changed.is_connected(on_refit):
		vp.size_changed.connect(on_refit)
