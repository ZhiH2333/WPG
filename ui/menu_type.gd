extends Object
class_name MenuType

## 主菜单字级。只服务这一页，不改 game_theme.tres，也不套到其他界面。
const FONT_PATH := "res://ui/fonts/PlaypenSans-Variable.ttf"
const INK := Color(0.96, 0.93, 0.88, 1)
const INK_SOFT := Color(0.82, 0.76, 0.68, 1)
const MUTED := Color(0.72, 0.66, 0.58, 1)
const STRUCTURE := Color(0.96, 0.93, 0.88, 0.85)
const ACCENT := Color(0.72, 0.38, 0.24, 1)

static var _base: FontFile
static var _cache: Dictionary = {}

static func apply_label(label: Label, role: StringName) -> void:
	if label == null:
		return
	label.add_theme_font_override("font", font(role))
	label.add_theme_font_size_override("font_size", size(role))
	label.add_theme_color_override("font_color", color(role))
	label.add_theme_constant_override("outline_size", 0)

static func apply_button(button: Button, role: StringName) -> void:
	if button == null:
		return
	button.add_theme_font_override("font", font(role))
	button.add_theme_font_size_override("font_size", size(role))
	button.add_theme_color_override("font_color", color(role))

static func font(role: StringName) -> FontVariation:
	if _cache.has(role):
		return _cache[role] as FontVariation
	var variation: FontVariation = FontVariation.new()
	variation.base_font = _font_file()
	variation.variation_opentype = {"wght": weight(role)}
	variation.spacing_glyph = tracking(role)
	_cache[role] = variation
	return variation

static func size(role: StringName) -> int:
	match role:
		&"display":
			return 40
		&"navigation":
			return 18
		&"section":
			return 14
		&"button":
			return 22
		&"body":
			return 18
		&"caption":
			return 15
		&"numeric":
			return 20
		_:
			return 14

static func weight(_role: StringName) -> int:
	return 800

static func tracking(role: StringName) -> int:
	if role == &"navigation" or role == &"section":
		return 1
	return 0

static func color(role: StringName) -> Color:
	if role == &"caption" or role == &"technical":
		return MUTED
	if role == &"section":
		return INK_SOFT
	return INK

static func _font_file() -> FontFile:
	if _base == null:
		_base = load(FONT_PATH) as FontFile
	return _base
