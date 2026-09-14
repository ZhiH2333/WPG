extends Sprite2D
class_name ArenaFloor

## 铺满现有 Floor 范围的可平铺地砖。运行时生成一次 256×256 贴图，禁止 NoiseTexture2D 每帧重算。
const TILE_PX: int = 256
const FLOOR_SIZE := Vector2(1600.0, 900.0)
const GRID_PX: int = 32
const BASE_COLOR := Color(0.20, 0.18, 0.24, 1)
const NOISE_STRENGTH: float = 0.045
const GRID_DARKEN: float = 0.06

func _ready() -> void:
	z_index = -10
	centered = true
	position = Vector2.ZERO
	texture_repeat = TEXTURE_REPEAT_ENABLED
	region_enabled = true
	region_rect = Rect2(Vector2.ZERO, FLOOR_SIZE)
	texture = _make_tile_texture()

func _make_tile_texture() -> ImageTexture:
	var image: Image = Image.create_empty(TILE_PX, TILE_PX, false, Image.FORMAT_RGB8)
	for y: int in TILE_PX:
		for x: int in TILE_PX:
			image.set_pixel(x, y, _pixel_color(x, y))
	return ImageTexture.create_from_image(image)

func _pixel_color(x: int, y: int) -> Color:
	var noise: float = _wrap_noise(x, y)
	var shade: float = (noise - 0.5) * 2.0 * NOISE_STRENGTH
	var color: Color = Color(
		clampf(BASE_COLOR.r + shade, 0.0, 1.0),
		clampf(BASE_COLOR.g + shade * 0.9, 0.0, 1.0),
		clampf(BASE_COLOR.b + shade * 1.1, 0.0, 1.0),
		1.0
	)
	if x % GRID_PX == 0 or y % GRID_PX == 0:
		color.r = maxf(0.0, color.r - GRID_DARKEN)
		color.g = maxf(0.0, color.g - GRID_DARKEN)
		color.b = maxf(0.0, color.b - GRID_DARKEN * 0.8)
	return color

func _wrap_noise(x: int, y: int) -> float:
	var n0: float = _value_noise(float(x) / 32.0, float(y) / 32.0, 8)
	var n1: float = _value_noise(float(x) / 16.0, float(y) / 16.0, 16)
	return n0 * 0.65 + n1 * 0.35

func _value_noise(nx: float, ny: float, period: int) -> float:
	var x0: int = int(floor(nx))
	var y0: int = int(floor(ny))
	var fx: float = _fade(nx - float(x0))
	var fy: float = _fade(ny - float(y0))
	var v00: float = _hash2(x0, y0, period)
	var v10: float = _hash2(x0 + 1, y0, period)
	var v01: float = _hash2(x0, y0 + 1, period)
	var v11: float = _hash2(x0 + 1, y0 + 1, period)
	var a: float = lerpf(v00, v10, fx)
	var b: float = lerpf(v01, v11, fx)
	return lerpf(a, b, fy)

func _hash2(x: int, y: int, period: int) -> float:
	var wx: int = posmod(x, period)
	var wy: int = posmod(y, period)
	var n: int = wx * 374761393 + wy * 668265263
	n = (n ^ (n >> 13)) * 1274126177
	return float(n & 0x7fffffff) / 2147483647.0

func _fade(t: float) -> float:
	return t * t * (3.0 - 2.0 * t)
