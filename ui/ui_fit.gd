extends Object
class_name UiFit

## 按可见逻辑尺寸收缩大面板和两列卡片。content_scale_factor 已经放大整棵树，禁止再乘 ui_scale。
const DESIGN := Vector2(1920, 1080)
const PREFERRED_PANEL := Vector2(1680, 920)
const PREFERRED_CARD := Vector2(780, 140)
const PREFERRED_PORTRAIT: float = 96.0
const SHOP_PANEL_MAX := Vector2(1480, 820)
const PANEL_MARGIN: float = 48.0
const CARD_H_SEP: float = 16.0
const CARD_INSET: float = 104.0
const MIN_CARD_WIDTH: float = 360.0
const MIN_CARD_HEIGHT: float = 96.0
const MAX_CARD_HEIGHT: float = 160.0
const MIN_PANEL_WIDTH: float = 640.0
const MIN_PANEL_HEIGHT: float = 480.0
const MIN_PORTRAIT: float = 64.0

static func visible_size(from: CanvasItem) -> Vector2:
	var vp: Viewport = from.get_viewport()
	if vp == null:
		return DESIGN
	var vis: Vector2 = vp.get_visible_rect().size
	if vis.x < 1.0 or vis.y < 1.0:
		return DESIGN
	return vis

static func panel_size(from: CanvasItem) -> Vector2:
	var vis: Vector2 = visible_size(from)
	return Vector2(minf(PREFERRED_PANEL.x, maxf(MIN_PANEL_WIDTH, vis.x - PANEL_MARGIN)), minf(PREFERRED_PANEL.y, maxf(MIN_PANEL_HEIGHT, vis.y - PANEL_MARGIN)))

static func shop_panel_size(from: CanvasItem) -> Vector2:
	var fitted: Vector2 = panel_size(from)
	return Vector2(minf(fitted.x, SHOP_PANEL_MAX.x), minf(fitted.y, SHOP_PANEL_MAX.y))

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
