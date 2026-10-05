extends Object
class_name SaveRow

## 一排 = 一个 SaveSlot 的完整摘要（Save Management UX / §2）。
##
## 不是「角色选择卡」：横向四段——序号+状态徽章 / 存档名+角色·场地 / 当前进度 / 更新时间。
## FlatBold：纯色块、粗体、无渐变，徽章是**实心色块 + 文字**（色觉安全，不能只靠颜色，§3）。
## 宽度不足时先砍时间、再砍次要进度行、最后砍序号——
## status / name / current progress 这三样**永不消失**（§11）。

const PINK := Color(1, 0.4, 0.67, 1)
const RED := Color(0.72, 0.24, 0.32, 1)
const GOLD := Color(1, 0.85, 0.3, 1)
const NEUTRAL := Color(0.34, 0.32, 0.37, 1)
const DARK_INK := Color(0.13, 0.11, 0.1, 1)
const LIGHT_INK := Color(0.96, 0.93, 0.88, 1)

## 行宽分档（内容宽度，不含 sheet 边距）。
const TIER_FULL: float = 900.0
const TIER_WIDE: float = 640.0
const TIER_MID: float = 500.0

const ROW_H_FULL: float = 104.0
const ROW_H_WIDE: float = 96.0
const ROW_H_MID: float = 84.0
const ROW_H_TINY: float = 76.0

const PAD_X: float = 16.0
const PAD_Y: float = 10.0
const GAP: float = 12.0
const INDEX_W: float = 44.0
const BADGE_W: float = 132.0
const TIME_W: float = 152.0
const ACCENT_W: float = 6.0


static func make(proj: SaveUiProjection, width: float = 0.0) -> Button:
	var button: Button = Button.new()
	button.name = "SaveRow"
	button.theme_type_variation = &"OfferButton"
	button.focus_mode = Control.FOCUS_ALL
	button.set_meta(&"slot_id", proj.slot_id)
	button.set_meta(&"save_status", proj.status)
	button.add_child(_make_mark())
	button.add_child(_make_accent(proj.status))
	button.add_child(_make_cleared_mark(proj.status))
	var content: HBoxContainer = HBoxContainer.new()
	content.name = "Content"
	content.set_anchors_preset(Control.PRESET_FULL_RECT)
	content.offset_left = PAD_X
	content.offset_top = PAD_Y
	content.offset_right = -PAD_X
	content.offset_bottom = -PAD_Y
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_theme_constant_override("separation", int(GAP))
	content.add_child(_make_index(proj.index))
	content.add_child(_make_badge(proj))
	content.add_child(_make_identity(proj))
	content.add_child(_make_progress(proj))
	content.add_child(_make_time(proj))
	button.add_child(content)
	apply_width(button, width)
	if width > 0.0:
		button.custom_minimum_size.x = width
	return button


static func slot_id_of(button: Node) -> String:
	if button == null or not button.has_meta(&"slot_id"):
		return ""
	return String(button.get_meta(&"slot_id"))


static func status_of(button: Node) -> String:
	if button == null or not button.has_meta(&"save_status"):
		return SaveUiProjection.STATUS_NEW
	return String(button.get_meta(&"save_status"))


## 选中态：2px ink 粗边框 + 略亮底色（不靠动画表达选中）。
static func set_selected(button: Control, selected: bool) -> void:
	if button == null:
		return
	if selected:
		var style: StyleBoxFlat = StyleBoxFlat.new()
		style.bg_color = Color(0.27, 0.225, 0.31, 1)
		style.set_border_width_all(2)
		style.border_color = LIGHT_INK
		style.set_corner_radius_all(6)
		style.content_margin_left = 20.0
		style.content_margin_right = 20.0
		style.content_margin_top = 14.0
		style.content_margin_bottom = 14.0
		button.add_theme_stylebox_override("normal", style)
		button.add_theme_stylebox_override("hover", style)
		button.add_theme_stylebox_override("pressed", style)
	else:
		button.remove_theme_stylebox_override("normal")
		button.remove_theme_stylebox_override("hover")
		button.remove_theme_stylebox_override("pressed")


static func apply_width(button: Control, width: float) -> void:
	if button == null:
		return
	var lines: int = 4
	var show_time: bool = false
	var show_index: bool = false
	var badge_min: float = 0.0
	var height: float = ROW_H_TINY
	if width >= TIER_FULL:
		lines = 4
		show_time = true
		show_index = true
		badge_min = BADGE_W
		height = ROW_H_FULL
	elif width >= TIER_WIDE:
		lines = 4
		show_index = true
		badge_min = BADGE_W
		height = ROW_H_WIDE
	elif width >= TIER_MID:
		lines = 2
		show_index = true
		badge_min = BADGE_W
		height = ROW_H_MID
	var index: Control = button.get_node_or_null("Content/Index") as Control
	if index != null:
		index.visible = show_index
		index.custom_minimum_size.x = INDEX_W if show_index else 0.0
	var time: Control = button.get_node_or_null("Content/Time") as Control
	if time != null:
		time.visible = show_time
		time.custom_minimum_size.x = TIME_W if show_time else 0.0
	var badge: Control = button.get_node_or_null("Content/Badge") as Control
	if badge != null:
		badge.custom_minimum_size.x = badge_min
	var progress: VBoxContainer = button.get_node_or_null("Content/Progress") as VBoxContainer
	if progress != null:
		var shown: int = 0
		for child: Node in progress.get_children():
			var label: Label = child as Label
			if label == null:
				continue
			var wanted: bool = shown < lines
			label.visible = wanted
			if wanted:
				shown += 1
	var identity: VBoxContainer = button.get_node_or_null("Content/Identity") as VBoxContainer
	if identity != null:
		var sub: Label = identity.get_node_or_null("Sub") as Label
		if sub != null:
			sub.visible = width >= TIER_MID
	button.custom_minimum_size.y = height
	## 最窄一档把行内间距也收紧，给「状态 / 名字 / 主进度」腾出硬余量。
	var content: HBoxContainer = button.get_node_or_null("Content") as HBoxContainer
	if content != null:
		content.add_theme_constant_override("separation", 8 if height <= ROW_H_TINY else int(GAP))


static func status_color(status: String) -> Color:
	match status:
		SaveUiProjection.STATUS_IN_PROGRESS:
			return PINK
		SaveUiProjection.STATUS_CLEARED:
			return GOLD
		SaveUiProjection.STATUS_FAILED:
			return RED
		_:
			return NEUTRAL


static func status_text_color(status: String) -> Color:
	match status:
		SaveUiProjection.STATUS_NEW:
			return LIGHT_INK
		SaveUiProjection.STATUS_FAILED:
			return LIGHT_INK
		_:
			return DARK_INK


# ---- 节点 ----

static func _make_mark() -> ColorRect:
	var mark: ColorRect = ColorRect.new()
	mark.name = "Mark"
	mark.color = LIGHT_INK
	mark.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	mark.offset_top = -3.0
	mark.offset_bottom = 0.0
	mark.offset_left = 4.0
	mark.offset_right = -4.0
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mark.visible = false
	return mark


static func _make_accent(status: String) -> ColorRect:
	var accent: ColorRect = ColorRect.new()
	accent.name = "Accent"
	accent.color = status_color(status)
	accent.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	accent.offset_right = ACCENT_W
	accent.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return accent


## 只给 COMPLETED 的一行极克制的完成标记（比状态色更宽的右侧金条）。
static func _make_cleared_mark(status: String) -> ColorRect:
	var mark: ColorRect = ColorRect.new()
	mark.name = "ClearedMark"
	mark.color = GOLD
	mark.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	mark.offset_left = -10.0
	mark.offset_right = 0.0
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mark.visible = status == SaveUiProjection.STATUS_CLEARED
	return mark


static func _make_index(index: int) -> Label:
	var label: Label = Label.new()
	label.name = "Index"
	label.theme_type_variation = &"SectionLabel"
	label.text = "%02d" % index
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	label.add_theme_color_override("font_color", Color(0.62, 0.58, 0.52, 1))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


static func _make_badge(proj: SaveUiProjection) -> PanelContainer:
	var badge: PanelContainer = PanelContainer.new()
	badge.name = "Badge"
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = status_color(proj.status)
	style.set_corner_radius_all(4)
	style.content_margin_left = 10.0
	style.content_margin_right = 10.0
	style.content_margin_top = 4.0
	style.content_margin_bottom = 4.0
	badge.add_theme_stylebox_override("panel", style)
	var label: Label = Label.new()
	label.name = "Label"
	label.theme_type_variation = &"SectionLabel"
	label.text = proj.status_label_text()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", status_text_color(proj.status))
	label.add_theme_constant_override("outline_size", 0)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.add_child(label)
	return badge


static func _make_identity(proj: SaveUiProjection) -> VBoxContainer:
	var box: VBoxContainer = VBoxContainer.new()
	box.name = "Identity"
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.add_theme_constant_override("separation", 2)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var name_label: Label = Label.new()
	name_label.name = "Name"
	name_label.theme_type_variation = &"OfferTitle"
	name_label.text = proj.display_name
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sub: Label = Label.new()
	sub.name = "Sub"
	sub.theme_type_variation = &"OfferDesc"
	sub.text = proj.identity_line()
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(name_label)
	box.add_child(sub)
	return box


static func _make_progress(proj: SaveUiProjection) -> VBoxContainer:
	var box: VBoxContainer = VBoxContainer.new()
	box.name = "Progress"
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.add_theme_constant_override("separation", 2)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var lines: PackedStringArray = proj.progress_lines()
	for i: int in lines.size():
		var label: Label = Label.new()
		label.name = "P%d" % i
		label.theme_type_variation = &"SectionLabel" if i == 0 else &"OfferDesc"
		label.text = lines[i]
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if i > 0:
			label.add_theme_color_override("font_color", Color(0.62, 0.58, 0.52, 1))
		box.add_child(label)
	return box


static func _make_time(proj: SaveUiProjection) -> VBoxContainer:
	var box: VBoxContainer = VBoxContainer.new()
	box.name = "Time"
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var label: Label = Label.new()
	label.name = "TimeText"
	label.theme_type_variation = &"OfferDesc"
	label.text = proj.time_label()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(label)
	return box
