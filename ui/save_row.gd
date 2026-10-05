extends Object
class_name SaveRow

## 一排 = 一个 SaveSlot 的完整摘要（Save Management UX / §2）。
##
## 不是「角色选择卡」：横向四段——序号+状态徽章 / 存档名+角色·场地 / 当前进度 / 更新时间。
## FlatBold：纯色块、粗体、无渐变，徽章是**实心色块 + 文字**（色觉安全，不能只靠颜色，§3）。
## 宽度不足时先砍时间、再砍次要进度行、最后砍序号——
## status / name / current progress 这三样**永不消失**（§11）。
##
## 进度不是「四句灰字」：投影给出 key/value 结构（SaveUiProjection.progress_facts()），
## 这里把它排成**两列数值表**——左列小号大写 key、右列数值，
## 同一档的每一行共用一条 key 列宽，所以数字是**竖着对齐**的，扫一眼就能比。
## 只有第 0 行（主进度）放大加粗，其余退到次级色；数值按 kind 上色，
## 但颜色只是辅助——每一行自己带 key + value 文字，色觉不敏感也读得出来（§3）。

const PINK := Color(1, 0.4, 0.67, 1)
const RED := Color(0.72, 0.24, 0.32, 1)
const GOLD := Color(1, 0.85, 0.3, 1)
const NEUTRAL := Color(0.34, 0.32, 0.37, 1)
const DARK_INK := Color(0.13, 0.11, 0.1, 1)
const LIGHT_INK := Color(0.96, 0.93, 0.88, 1)
## 次级数值：比 Caption 的 0.62 亮一点，别在深紫底上糊成一片灰。
const VALUE_INK := Color(0.82, 0.79, 0.74, 1)
## key 列：小、粗、灰，只做索引，不抢数值。
const KEY_INK := Color(0.62, 0.58, 0.52, 1)
const KEY_SIZE: int = 13
const HERO_SIZE: int = 20
const VALUE_SIZE: int = 15
## key 列与数值列之间的固定间隔（两列都靠左，数字才竖着对齐）。
const COL_GAP: int = 12
const ROW_GAP: int = 4
## 分隔「身份」与「进度」的竖细线：只在高档位出现，窄屏先让位。
const DIVIDER_INK := Color(0.96, 0.93, 0.88, 0.12)

## 行宽分档（内容宽度，不含 sheet 边距）。
const TIER_FULL: float = 900.0
const TIER_WIDE: float = 640.0
const TIER_MID: float = 500.0

## 进度最多 4 条（IN_PROGRESS），行高按「4 条竖排 + 上下内边距」留够，
## 不再像以前那样把 4 行塞进 84px 里顶到卡片边缘。
const ROW_H_FULL: float = 116.0
const ROW_H_WIDE: float = 108.0
const ROW_H_MID: float = 92.0
const ROW_H_TINY: float = 76.0

## 各档位最多露几条进度（第 0 条永不隐藏，§11）。
const FACTS_FULL: int = 4
const FACTS_WIDE: int = 4
const FACTS_MID: int = 2
const FACTS_TINY: int = 1

## 窄档没有两列的余地（key 列会把数值列压到 20px，短语被迫换行把整排撑穿）。
## 到 WIDE 以下就退回**单列短语**：key 空掉、列间距归零、字号收一档，
## 但露出来的还是同一批文字，只是不再分栏。
const HERO_SIZE_NARROW: int = 18
const VALUE_SIZE_NARROW: int = 14
## 窄档存档名也收一档：OfferTitle 的 22px 会把「Fresh Save」折成两行。
const NAME_SIZE_NARROW: int = 18
## 窄档把富余宽度多分给进度列，别让存档名把数值挤成两行。
const STRETCH_WIDE: float = 1.0
const STRETCH_NARROW_IDENTITY: float = 1.0
const STRETCH_NARROW_PROGRESS: float = 1.4

const PAD_X: float = 16.0
const PAD_Y: float = 10.0
const GAP: float = 12.0
const INDEX_W: float = 44.0
const BADGE_W: float = 132.0
const TIME_W: float = 152.0
const ACCENT_W: float = 6.0
const DIVIDER_W: float = 1.0


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
	content.add_child(_make_divider())
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
	var facts: int = FACTS_TINY
	var show_time: bool = false
	var show_index: bool = false
	var show_divider: bool = false
	var badge_min: float = 0.0
	var height: float = ROW_H_TINY
	if width >= TIER_FULL:
		facts = FACTS_FULL
		show_time = true
		show_index = true
		show_divider = true
		badge_min = BADGE_W
		height = ROW_H_FULL
	elif width >= TIER_WIDE:
		facts = FACTS_WIDE
		show_index = true
		show_divider = true
		badge_min = BADGE_W
		height = ROW_H_WIDE
	elif width >= TIER_MID:
		facts = FACTS_MID
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
	var divider: Control = button.get_node_or_null("Content/Divider") as Control
	if divider != null:
		divider.visible = show_divider
		divider.custom_minimum_size.x = DIVIDER_W if show_divider else 0.0
	## 进度表按「条」成对隐藏：第 i 条 = key 与 value 两个 Label 一起走，
	## 表列宽由仍在场的最宽 key 决定，所以砍条数不会把数字对齐弄乱。
	var show_keys: bool = width >= TIER_WIDE
	var progress: GridContainer = button.get_node_or_null("Content/Progress") as GridContainer
	if progress != null:
		## 单列时 key 列必须留空但**不能隐藏** —— GridContainer 会跳过不可见子节点，
		## 那会把后面的数值挤到错误的列上（P0/K1/P1 全错位）。
		progress.add_theme_constant_override("h_separation", COL_GAP if show_keys else 0)
		progress.size_flags_stretch_ratio = STRETCH_WIDE if show_keys else STRETCH_NARROW_PROGRESS
		for child: Node in progress.get_children():
			var label: Label = child as Label
			if label == null or not label.has_meta(&"fact"):
				continue
			label.visible = int(label.get_meta(&"fact")) < facts
			if label.has_meta(&"fact_key"):
				label.text = str(label.get_meta(&"fact_key")) if show_keys else ""
				continue
			label.text = str(label.get_meta(&"fact_value")) if show_keys else str(label.get_meta(&"fact_phrase"))
			var size: int = HERO_SIZE if int(label.get_meta(&"fact")) == 0 else VALUE_SIZE
			if not show_keys:
				size = HERO_SIZE_NARROW if int(label.get_meta(&"fact")) == 0 else VALUE_SIZE_NARROW
			label.add_theme_font_size_override("font_size", size)
	var identity: VBoxContainer = button.get_node_or_null("Content/Identity") as VBoxContainer
	if identity != null:
		identity.size_flags_stretch_ratio = STRETCH_WIDE if show_keys else STRETCH_NARROW_IDENTITY
		var name_label: Label = identity.get_node_or_null("Name") as Label
		if name_label != null:
			if show_keys:
				name_label.remove_theme_font_size_override("font_size")
			else:
				name_label.add_theme_font_size_override("font_size", NAME_SIZE_NARROW)
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


## 进度表：2 列（key / value）。同一档的每一行共用同一条 key 列宽，
## 所以数字是竖着对齐的；第 0 条放大加粗当主进度，其余退到次级色。
## P0 永远是数值那一格（§11 主进度永不消失，测试也钉着 Content/Progress/P0）。
static func _make_progress(proj: SaveUiProjection) -> GridContainer:
	var grid: GridContainer = GridContainer.new()
	grid.name = "Progress"
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	grid.add_theme_constant_override("h_separation", COL_GAP)
	grid.add_theme_constant_override("v_separation", ROW_GAP)
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var facts: Array[Dictionary] = proj.progress_facts()
	## 短语和 key/value 是同一条事实的两种写法（都来自投影，界面不自己拼）。
	## 两套文字都挂在节点上，apply_width 按档位挑一套，不用重建节点。
	var phrases: PackedStringArray = proj.progress_lines()
	for i: int in facts.size():
		var fact: Dictionary = facts[i]
		var value: String = str(fact.get("value", ""))
		var phrase: String = phrases[i] if i < phrases.size() else value
		grid.add_child(_make_fact_key(i, str(fact.get("key", ""))))
		grid.add_child(_make_fact_value(i, value, phrase, str(fact.get("kind", ""))))
	return grid


## 身份与进度之间的竖细线：把「这是哪个档」和「这个档到哪了」分开。
static func _make_divider() -> ColorRect:
	var divider: ColorRect = ColorRect.new()
	divider.name = "Divider"
	divider.color = DIVIDER_INK
	divider.custom_minimum_size = Vector2(DIVIDER_W, 0.0)
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return divider


static func _make_fact_key(index: int, text: String) -> Label:
	var label: Label = Label.new()
	label.name = "K%d" % index
	label.set_meta(&"fact", index)
	label.set_meta(&"fact_key", text.to_upper())
	label.theme_type_variation = &"SectionLabel"
	label.text = text.to_upper()
	label.add_theme_font_size_override("font_size", KEY_SIZE)
	label.add_theme_color_override("font_color", KEY_INK)
	label.add_theme_constant_override("outline_size", 2)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


static func _make_fact_value(index: int, value: String, phrase: String, kind: String) -> Label:
	var label: Label = Label.new()
	label.name = "P%d" % index
	label.set_meta(&"fact", index)
	label.set_meta(&"fact_value", value)
	label.set_meta(&"fact_phrase", phrase)
	label.text = value
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if index == 0:
		## 主进度：整排唯一一个「大字号 + 骨白」，别的都退到它后面。
		label.theme_type_variation = &"OfferTitle"
		label.add_theme_font_size_override("font_size", HERO_SIZE)
		label.add_theme_color_override("font_color", LIGHT_INK)
	else:
		label.theme_type_variation = &"OfferDesc"
		label.add_theme_font_size_override("font_size", VALUE_SIZE)
		label.add_theme_color_override("font_color", value_color(kind))
	return label


## 数值配色只是「扫读加速」，语义永远由同一行的 key + value 文字承担（§3）。
static func value_color(kind: String) -> Color:
	match kind:
		"gold":
			return GOLD
		"best", "score":
			return LIGHT_INK
		_:
			return VALUE_INK


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
