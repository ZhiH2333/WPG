extends Object
class_name RecordCard

## 档位主卡工厂。LIST 与 LAN PICK 共用。不含删除钮，不含 pressed 连接。全是 static，不是 Autoload，禁止 get_tree()。
const CATALOG: CharacterCatalog = preload("res://data/character_catalog.tres")
const FALLBACK_BODY: Texture2D = preload("res://images/player.png")
const CARD_SIZE := Vector2(520, 96)
const PORTRAIT_PX: float = 64.0

static func make_main_card(record: GameRecord) -> Button:
	var button: Button = Button.new()
	button.custom_minimum_size = CARD_SIZE
	button.theme_type_variation = &"OfferButton"
	var inner: HBoxContainer = HBoxContainer.new()
	inner.set_anchors_preset(Control.PRESET_FULL_RECT)
	inner.offset_left = 16.0
	inner.offset_top = 12.0
	inner.offset_right = -16.0
	inner.offset_bottom = -12.0
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_theme_constant_override("separation", 12)
	inner.add_child(_make_portrait(record.character_id))
	inner.add_child(_make_meta_box(record))
	inner.add_child(_make_score_label(record.best_score))
	button.add_child(inner)
	return button

static func format_loop_badge(loop_goal: int) -> String:
	if loop_goal > 0:
		return "%d loops" % loop_goal
	return "Inf"

static func resolve_body_texture(character_id: String) -> Texture2D:
	var def: CharacterDef = CATALOG.get_by_id(StringName(character_id))
	if def != null and def.body_texture != null:
		return def.body_texture
	return FALLBACK_BODY

static func _make_portrait(character_id: String) -> TextureRect:
	var portrait: TextureRect = TextureRect.new()
	portrait.custom_minimum_size = Vector2(PORTRAIT_PX, PORTRAIT_PX)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait.texture = resolve_body_texture(character_id)
	return portrait

static func _make_meta_box(record: GameRecord) -> VBoxContainer:
	var box: VBoxContainer = VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 4)
	var title: Label = Label.new()
	title.theme_type_variation = &"ModeTitle"
	title.text = record.name
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var meta: Label = Label.new()
	meta.theme_type_variation = &"OfferDesc"
	meta.text = "%s  %s" % [_read_display_name(record.character_id), format_loop_badge(record.loop_goal)]
	meta.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(title)
	box.add_child(meta)
	return box

static func _make_score_label(best_score: int) -> Label:
	var label: Label = Label.new()
	label.theme_type_variation = &"ModeTitle"
	label.text = str(best_score)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

static func _read_display_name(character_id: String) -> String:
	var def: CharacterDef = CATALOG.get_by_id(StringName(character_id))
	if def != null and not def.display_name.is_empty():
		return def.display_name
	return character_id
