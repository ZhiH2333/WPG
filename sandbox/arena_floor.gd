extends Sprite2D
class_name ArenaFloor

## 冷色大块石砖：和粉/橙角色拉开对比。无中频噪声，最近邻采样。亮度全场均匀，不要暗角。
const TILE_PX: int = 64
const GROUT_PX: int = 2
const BEVEL_PX: int = 1
const FLOOR_SIZE := Vector2(1600.0, 900.0)
const GROUT_COLOR := Color(0.10, 0.11, 0.13, 1)
const TILE_COLOR := Color(0.17, 0.19, 0.23, 1)

var _tile_color: Color = TILE_COLOR
var _grout_color: Color = GROUT_COLOR

func _ready() -> void:
	z_index = -10
	centered = true
	position = Vector2.ZERO
	texture_filter = TEXTURE_FILTER_NEAREST
	texture_repeat = TEXTURE_REPEAT_ENABLED
	region_enabled = true
	region_rect = Rect2(Vector2.ZERO, FLOOR_SIZE)
	texture = _make_tile_texture()

func apply_palette(tile: Color, grout: Color) -> void:
	_tile_color = tile
	_grout_color = grout
	texture = _make_tile_texture()

func _make_tile_texture() -> ImageTexture:
	var image: Image = Image.create_empty(TILE_PX, TILE_PX, false, Image.FORMAT_RGB8)
	for y: int in TILE_PX:
		for x: int in TILE_PX:
			image.set_pixel(x, y, _pixel_color(x, y))
	return ImageTexture.create_from_image(image)

func _pixel_color(x: int, y: int) -> Color:
	if x < GROUT_PX or y < GROUT_PX:
		return _grout_color
	if x < GROUT_PX + BEVEL_PX or y < GROUT_PX + BEVEL_PX:
		return _tile_color.lightened(0.07)
	if x >= TILE_PX - BEVEL_PX or y >= TILE_PX - BEVEL_PX:
		return _tile_color.darkened(0.08)
	return _tile_color
