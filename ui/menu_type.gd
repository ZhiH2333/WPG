extends Object
class_name MenuType

## 主菜单字级。只服务这一页，不改 game_theme.tres，也不套到其他界面。
const FONT_PATH := "res://ui/fonts/PlaypenSans-Variable.ttf"
const SANS_PATH := "res://ui/fonts/SourceSans3-Variable.ttf"
const PAPER := Color(0.94, 0.9, 0.84, 1)
const PAPER_SOFT := Color(0.94, 0.9, 0.84, 0.78)
const MUTED_PAPER := Color(0.94, 0.9, 0.84, 0.55)
const INK := Color(0.18, 0.14, 0.11, 1)
const MUTED_INK := Color(0.42, 0.37, 0.32, 1)
const STRUCTURE := Color(0.94, 0.9, 0.84, 0.9)
const ACCENT := Color(0.7, 0.36, 0.22, 1)
const OLIVE := Color(0.36, 0.4, 0.26, 1)
const SURFACE := Color(0.94, 0.9, 0.84, 1)
const BASE := Color(0.94, 0.9, 0.84, 1)
const LINE := Color(0.18, 0.14, 0.11, 0.22)
const ERROR := Color(0.72, 0.24, 0.18, 1)

const SPACE_XS: int = 4
const SPACE_SM: int = 8
const SPACE_MD: int = 12
const SPACE_LG: int = 16
const SPACE_XL: int = 24
const SPACE_XXL: int = 48
const TOP_BAR_HEIGHT: float = 60.0
const CONTENT_MARGIN: float = 48.0
const CONTENT_MAX_WIDTH: float = 1200.0
const BUTTON_HEIGHT: float = 44.0
const ROW_GAP: int = 12
const SECTION_GAP: int = 24

## Playpen Sans 只用于品牌、标题、主导航、主动作和玩家名。
## Body / Caption / Section / Numeric / Technical 用 Source Sans 3。
## 海报上的字是 Paper。纸面上的字是 Ink。Accent 只给焦点。

static var _playpen: FontFile
static var _sans: FontFile
static var _cache: Dictionary = {}

static func apply_label(label: Label, role: StringName, on_paper: bool = false) -> void:
	if label == null:
		return
	label.add_theme_font_override("font", font(role))
	label.add_theme_font_size_override("font_size", size(role))
	label.add_theme_color_override("font_color", color_for(role, on_paper))
	label.add_theme_constant_override("outline_size", 0)
	var extra: int = line_height(role) - size(role)
	if extra > 0:
		label.add_theme_constant_override("line_spacing", extra)

static func apply_button(button: Button, role: StringName, on_paper: bool = false) -> void:
	if button == null:
		return
	button.add_theme_font_override("font", font(role))
	button.add_theme_font_size_override("font_size", size(role))
	button.add_theme_color_override("font_color", color_for(role, on_paper))

static func font(role: StringName) -> FontVariation:
	if _cache.has(role):
		return _cache[role] as FontVariation
	var variation: FontVariation = FontVariation.new()
	variation.base_font = _sans_file() if _uses_sans(role) else _playpen_file()
	variation.variation_opentype = {"wght": weight(role)}
	variation.spacing_glyph = tracking(role)
	_cache[role] = variation
	return variation

static func line_height(role: StringName) -> int:
	match role:
		&"display", &"page":
			return 48
		&"navigation", &"numeric":
			return 24
		&"section", &"technical":
			return 20
		&"button":
			return 28
		&"caption":
			return 22
		_:
			return 28

static func size(role: StringName) -> int:
	match role:
		&"display":
			return 40
		&"page":
			return 32
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
		&"control":
			return 16
		_:
			return 14

static func weight(role: StringName) -> int:
	match role:
		&"display":
			return 740
		&"page":
			return 680
		&"navigation":
			return 640
		&"button", &"section":
			return 600
		&"numeric", &"control":
			return 560
		&"technical":
			return 500
		_:
			return 460

static func _uses_sans(role: StringName) -> bool:
	return role == &"section" or role == &"body" or role == &"caption" or role == &"technical" or role == &"numeric" or role == &"control"

static func tracking(role: StringName) -> int:
	if role == &"navigation" or role == &"section":
		return 1
	return 0

static func color_for(role: StringName, on_paper: bool) -> Color:
	if on_paper:
		if role == &"caption" or role == &"technical":
			return MUTED_INK
		return INK
	if role == &"caption" or role == &"technical" or role == &"section":
		return MUTED_PAPER
	return PAPER

static func color(role: StringName) -> Color:
	return color_for(role, false)

static func paint_title_mark(button: Button, title: Label, hovered: bool) -> void:
	var mark: ColorRect = button.get_node_or_null("FocusMark") as ColorRect
	if title == null or mark == null:
		return
	var hot: bool = hovered or button.is_hovered() or button.has_focus()
	title.add_theme_color_override("font_color", PAPER if hot else PAPER_SOFT)
	var text_width: float = title.get_theme_font("font").get_string_size(title.text, HORIZONTAL_ALIGNMENT_LEFT, -1, title.get_theme_font_size("font_size")).x
	mark.set_anchors_preset(Control.PRESET_TOP_LEFT)
	mark.offset_left = 0.0
	mark.offset_top = 34.0
	mark.offset_right = maxf(text_width, 24.0)
	mark.offset_bottom = 37.0
	mark.visible = hot
	mark.color = ACCENT if button.has_focus() else PAPER

static func migrate_settings(root: Node) -> void:
	_paint_rect(root, "Sidebar", BASE)
	_paint_rect(root, "Fill", SURFACE)
	_paint_rect(root, "HeaderBg", BASE)
	var dimmer: ColorRect = root.find_child("Dimmer", true, false) as ColorRect
	if dimmer != null:
		dimmer.color = Color(BASE.r, BASE.g, BASE.b, 0.0)
	var content: VBoxContainer = root.find_child("Content", true, false) as VBoxContainer
	if content != null:
		content.add_theme_constant_override("separation", SECTION_GAP)
	for node: Node in root.find_children("*", "", true, false):
		if _inside_credits(node):
			continue
		_migrate_node(node)

static func style_slider(slider: HSlider) -> void:
	var track: StyleBoxFlat = _flat(Color(INK.r, INK.g, INK.b, 0.12), 0)
	track.content_margin_top = 11.0
	track.content_margin_bottom = 11.0
	var grab: StyleBoxFlat = _flat(INK, 0)
	slider.add_theme_stylebox_override("slider", track)
	slider.add_theme_stylebox_override("grabber_area", grab)
	slider.add_theme_stylebox_override("grabber_area_highlight", grab)

static func _migrate_node(node: Node) -> void:
	var separator: ColorRect = node as ColorRect
	if separator != null and separator.name == "Separator":
		separator.color = LINE
		return
	var section_dim: ColorRect = node as ColorRect
	if section_dim != null and section_dim.name == "Dim":
		section_dim.color = Color(INK.r, INK.g, INK.b, section_dim.color.a)
		return
	var edit: LineEdit = node as LineEdit
	if edit != null:
		_dress_line_edit(edit)
		return
	var slider: HSlider = node as HSlider
	if slider != null:
		style_slider(slider)
		return
	if node is CheckBox:
		apply_button(node as Button, &"body", true)
		return
	if node is HoldConfirmButton:
		_empty_button(node as Button)
		apply_button(node as Button, &"button", true)
		return
	if node is SettingsNavButton:
		return
	var button: Button = node as Button
	if button != null:
		_dress_action(button)
		return
	var label: Label = node as Label
	if label != null:
		_dress_label(label)

static func _dress_label(label: Label) -> void:
	var role: StringName = &"body"
	if label.name == "Header" or label.name == "Title":
		role = &"page"
	elif label.theme_type_variation == &"SettingsHeader":
		role = &"section"
	elif label.theme_type_variation == &"RunSummaryHint" or label.name == "VersionLabel":
		role = &"caption"
	elif label.name != "Caption":
		role = &"body"
	else:
		return
	apply_label(label, role, true)
	if role == &"section" or role == &"page":
		label.text = label.text.to_upper()

static func _dress_action(button: Button) -> void:
	var role: StringName = &"control"
	if button.name == "RestoreButton" or button.name == "CreditsButton":
		role = &"button"
	_empty_button(button)
	apply_button(button, role, true)
	button.set_meta("wpg_on_paper", true)
	if button.get_node_or_null("FocusMark") != null:
		return
	var mark: ColorRect = ColorRect.new()
	mark.name = "FocusMark"
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mark.visible = false
	mark.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	mark.offset_top = -2.0
	mark.offset_bottom = 0.0
	button.add_child(mark)
	button.mouse_entered.connect(_paint_action.bind(button, true))
	button.mouse_exited.connect(_paint_action.bind(button, false))
	button.focus_entered.connect(_paint_action.bind(button, true))
	button.focus_exited.connect(_paint_action.bind(button, false))
	_paint_action(button, false)

static func _paint_action(button: Button, hovered: bool) -> void:
	var mark: ColorRect = button.get_node_or_null("FocusMark") as ColorRect
	if mark == null:
		return
	var on_paper: bool = bool(button.get_meta("wpg_on_paper", false))
	var hot: bool = hovered or button.is_hovered() or button.has_focus()
	var resting: Color = MUTED_INK if on_paper else PAPER_SOFT
	var active: Color = INK if on_paper else PAPER
	var line: Color = INK if on_paper else PAPER
	button.add_theme_color_override("font_color", active if hot else resting)
	mark.visible = hot
	mark.color = ACCENT if button.has_focus() else line

static func _dress_line_edit(edit: LineEdit) -> void:
	edit.add_theme_font_override("font", font(&"body"))
	edit.add_theme_font_size_override("font_size", size(&"body"))
	edit.add_theme_stylebox_override("normal", _line_box(false))
	edit.add_theme_stylebox_override("focus", _line_box(true))
	edit.add_theme_color_override("font_color", INK)
	edit.add_theme_color_override("font_placeholder_color", MUTED_INK)
	edit.add_theme_color_override("caret_color", ACCENT)

static func _line_box(focused: bool) -> StyleBoxFlat:
	var box: StyleBoxFlat = _flat(Color(0, 0, 0, 0), 0)
	box.border_color = ACCENT if focused else LINE
	box.border_width_bottom = 2
	box.content_margin_top = 8.0
	box.content_margin_bottom = 8.0
	return box

static func _empty_button(button: Button) -> void:
	var empty: StyleBoxEmpty = StyleBoxEmpty.new()
	button.add_theme_stylebox_override("normal", empty)
	button.add_theme_stylebox_override("hover", empty)
	button.add_theme_stylebox_override("pressed", empty)
	button.add_theme_stylebox_override("focus", empty)
	button.add_theme_stylebox_override("disabled", empty)

static func _flat(fill: Color, radius: int) -> StyleBoxFlat:
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = fill
	box.set_corner_radius_all(radius)
	return box

static func _paint_rect(root: Node, node_name: String, fill: Color) -> void:
	var rect: ColorRect = root.find_child(node_name, true, false) as ColorRect
	if rect != null:
		rect.color = fill

static func _inside_credits(node: Node) -> bool:
	var current: Node = node
	while current != null:
		if current is CreditsOverlay:
			return true
		current = current.get_parent()
	return false

static func _playpen_file() -> FontFile:
	if _playpen == null:
		_playpen = load(FONT_PATH) as FontFile
	return _playpen

static func _sans_file() -> FontFile:
	if _sans == null:
		_sans = load(SANS_PATH) as FontFile
	return _sans
