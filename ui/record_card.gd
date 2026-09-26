extends Object
class_name RecordCard

## 档位主卡工厂。LIST / LAN PICK 共用大卡；Profile 概览行与排行行不带头像。不含删除钮，不含 pressed 连接。全是 static，不是 Autoload，禁止 get_tree() / get_viewport()。尺寸由调用方传入，禁止再乘 ui_scale。
const CATALOG: CharacterCatalog = preload("res://data/character_catalog.tres")
const ARENA_CATALOG: ArenaCatalog = preload("res://data/arena_catalog.tres")
const FALLBACK_BODY: Texture2D = preload("res://images/player.png")
const RANK_WIDTH: float = 56.0
const RANK_BAR_HEIGHT: float = 28.0
const MARK_HEIGHT: float = 2.0
const RANK_GOLD := Color(1, 0.85, 0.3, 1)
const RANK_SILVER := Color(0.85, 0.85, 0.9, 1)
const RANK_BRONZE := Color(0.85, 0.55, 0.35, 1)

static func make_main_card(record: GameRecord, card_size: Vector2, portrait_px: float, right_reserve: float = 0.0) -> Button:
	var button: Button = Button.new()
	button.custom_minimum_size = card_size
	button.theme_type_variation = &"OfferButton"
	button.add_child(make_mark())
	var inner: HBoxContainer = HBoxContainer.new()
	inner.name = "Content"
	inner.set_anchors_preset(Control.PRESET_FULL_RECT)
	inner.offset_left = 20.0
	inner.offset_top = 16.0
	inner.offset_right = -(20.0 + right_reserve)
	inner.offset_bottom = -16.0
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_theme_constant_override("separation", 16)
	inner.add_child(_make_portrait(record.character_id, portrait_px))
	inner.add_child(_make_meta_box(record))
	inner.add_child(_make_score_label(record.best_score))
	button.add_child(inner)
	return button

static func make_overview_row(record: GameRecord) -> Control:
	var row: HBoxContainer = HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 16)
	var name_label: Label = _make_overview_name_label(record)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)
	row.add_child(_make_overview_meta_label(record))
	row.add_child(_make_score_label(record.best_score))
	return row

static func make_rank_row(rank: int, record: GameRecord, max_score: int) -> Control:
	var row: HBoxContainer = HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 16)
	row.add_child(_make_rank_label(rank))
	row.add_child(_make_rank_bar(record.best_score, max_score))
	row.add_child(_make_overview_name_label(record))
	row.add_child(_make_score_label(record.best_score))
	return row

static func format_loop_badge(loop_goal: int) -> String:
	if loop_goal > 0:
		return "%d loops" % loop_goal
	return "Inf"

static func format_arena_name(arena_id: String) -> String:
	var def: ArenaDef = ARENA_CATALOG.get_by_id(StringName(arena_id))
	if def != null and not def.display_name.is_empty():
		return def.display_name
	return arena_id

static func resolve_body_texture(character_id: String) -> Texture2D:
	var def: CharacterDef = CATALOG.get_by_id(StringName(character_id))
	if def != null and def.body_texture != null:
		return def.body_texture
	return FALLBACK_BODY

static func _make_overview_name_label(record: GameRecord) -> Label:
	var label: Label = Label.new()
	label.name = "Name"
	label.theme_type_variation = &"OfferTitle"
	label.text = record.name
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

static func _make_overview_meta_label(record: GameRecord) -> Label:
	var label: Label = Label.new()
	label.name = "Meta"
	label.theme_type_variation = &"Caption"
	label.text = "%s  %s  ·  %s" % [_read_display_name(record.character_id), format_loop_badge(record.loop_goal), format_arena_name(record.arena_id)]
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

static func _make_rank_label(rank: int) -> Label:
	var label: Label = Label.new()
	label.name = "Rank"
	label.custom_minimum_size = Vector2(RANK_WIDTH, 0.0)
	label.theme_type_variation = &"ModeTitle"
	label.text = "#%d" % rank
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if rank == 1:
		label.add_theme_color_override("font_color", RANK_GOLD)
	elif rank == 2:
		label.add_theme_color_override("font_color", RANK_SILVER)
	elif rank == 3:
		label.add_theme_color_override("font_color", RANK_BRONZE)
	return label

static func _make_rank_bar(score: int, max_score: int) -> ProgressBar:
	var bar: ProgressBar = ProgressBar.new()
	bar.name = "Bar"
	var ceiling: int = max_score if max_score > 0 else 1
	bar.theme_type_variation = &"RankBar"
	bar.show_percentage = false
	bar.min_value = 0.0
	bar.max_value = float(ceiling)
	bar.value = float(score)
	bar.custom_minimum_size = Vector2(0.0, RANK_BAR_HEIGHT)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return bar

static func _make_portrait(character_id: String, portrait_px: float) -> TextureRect:
	var portrait: TextureRect = TextureRect.new()
	portrait.name = "Portrait"
	portrait.custom_minimum_size = Vector2(portrait_px, portrait_px)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait.texture = resolve_body_texture(character_id)
	return portrait

static func _make_meta_box(record: GameRecord) -> VBoxContainer:
	var box: VBoxContainer = VBoxContainer.new()
	box.name = "Info"
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 4)
	var title: Label = Label.new()
	title.name = "Title"
	title.theme_type_variation = &"OfferTitle"
	title.text = record.name
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var meta: Label = Label.new()
	meta.name = "Meta"
	meta.theme_type_variation = &"OfferDesc"
	meta.text = "%s  %s  ·  %s" % [_read_display_name(record.character_id), format_loop_badge(record.loop_goal), format_arena_name(record.arena_id)]
	meta.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(title)
	box.add_child(meta)
	return box

static func _make_score_label(best_score: int) -> Label:
	var label: Label = Label.new()
	label.name = "Score"
	label.theme_type_variation = &"ModeTitle"
	label.text = str(best_score)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

## 行级反馈的骨白下划线。UiAnim.set_row_feedback 按名字 "Mark" 找它，名字不能改。
static func make_mark() -> ColorRect:
	var mark: ColorRect = ColorRect.new()
	mark.name = "Mark"
	mark.color = UiType.INK
	mark.visible = false
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mark.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	mark.offset_top = -MARK_HEIGHT
	return mark

static func _read_display_name(character_id: String) -> String:
	var def: CharacterDef = CATALOG.get_by_id(StringName(character_id))
	if def != null and not def.display_name.is_empty():
		return def.display_name
	return character_id
