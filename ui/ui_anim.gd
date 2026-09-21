extends Object
class_name UiAnim

## osu 式非线性 UI 过渡工具：进场 OutQuint/OutBack、退场 InQuint，透明度时长约为位移的一半。
## 只做装饰（modulate / scale / offset），不改逻辑开关；逻辑上 open/close 仍然瞬时生效。
const DIMMER_FADE_SEC: float = 0.2
const CONTENT_FADE_SEC: float = 0.25
const PANEL_MOVE_SEC: float = 0.45
const PANEL_EXIT_SEC: float = 0.3
const OVERLAY_EXIT_SEC: float = 0.15
const OVERLAY_RISE_PX: float = 56.0
const CARD_FADE_SEC: float = 0.22
const CARD_SCALE_SEC: float = 0.4
const CARD_START_SCALE: float = 0.9
const CARD_STAGGER_SEC: float = 0.06
const MENU_ITEM_FADE_SEC: float = 0.35
const MENU_ITEM_STAGGER_SEC: float = 0.07

static func enter_overlay(host: Node, dimmer: CanvasItem, content: CanvasItem, cards: Array, ignore_pause: bool = false) -> Tween:
	var tween: Tween = host.create_tween().set_parallel(true)
	if ignore_pause:
		tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	if dimmer != null:
		dimmer.modulate.a = 0.0
		tween.tween_property(dimmer, "modulate:a", 1.0, DIMMER_FADE_SEC).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	if content != null:
		var parent_container: Container = content.get_parent() as Container
		if parent_container != null:
			parent_container.notification(Container.NOTIFICATION_SORT_CHILDREN)
		content.modulate.a = 0.0
		var base_y: float = content.position.y
		content.position.y = base_y + OVERLAY_RISE_PX
		tween.tween_property(content, "modulate:a", 1.0, CONTENT_FADE_SEC).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
		tween.tween_property(content, "position:y", base_y, PANEL_MOVE_SEC).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_append_card_entries(tween, cards)
	return tween

static func exit_overlay(host: Node, root: CanvasItem, ignore_pause: bool = false) -> Tween:
	var tween: Tween = host.create_tween()
	if ignore_pause:
		tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(root, "modulate:a", 0.0, OVERLAY_EXIT_SEC).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_IN)
	return tween

static func enter_stagger_fade(host: Node, items: Array) -> Tween:
	var tween: Tween = host.create_tween().set_parallel(true)
	var order: int = 0
	for entry: Variant in items:
		var item: CanvasItem = entry as CanvasItem
		if item == null:
			continue
		item.modulate.a = 0.0
		tween.tween_property(item, "modulate:a", 1.0, MENU_ITEM_FADE_SEC).set_delay(MENU_ITEM_STAGGER_SEC * float(order)).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
		order += 1
	return tween

static func kill_tween(tween: Tween) -> void:
	if tween != null and tween.is_valid():
		tween.kill()

static func punch_scale(host: Node, control: Control, peak: float, sec: float, ignore_pause: bool) -> Tween:
	if host == null or control == null:
		return null
	var tween: Tween = host.create_tween()
	if ignore_pause:
		tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	control.pivot_offset = control.custom_minimum_size * 0.5
	var half: float = sec * 0.5
	tween.tween_property(control, "scale", Vector2(peak, peak), half).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	tween.tween_property(control, "scale", Vector2.ONE, half).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_IN)
	return tween

static func fade_modulate(host: Node, control: CanvasItem, to_alpha: float, sec: float, ignore_pause: bool) -> Tween:
	if host == null or control == null:
		return null
	var tween: Tween = host.create_tween()
	if ignore_pause:
		tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	var ease: Tween.EaseType = Tween.EASE_IN if to_alpha <= 0.0 else Tween.EASE_OUT
	tween.tween_property(control, "modulate:a", to_alpha, sec).set_trans(Tween.TRANS_QUINT).set_ease(ease)
	return tween

static func _append_card_entries(tween: Tween, cards: Array) -> void:
	var order: int = 0
	for entry: Variant in cards:
		var card: Control = entry as Control
		if card == null or not card.visible:
			continue
		var delay: float = CARD_STAGGER_SEC * float(order)
		card.pivot_offset = card.custom_minimum_size * 0.5
		card.modulate.a = 0.0
		card.scale = Vector2(CARD_START_SCALE, CARD_START_SCALE)
		tween.tween_property(card, "modulate:a", 1.0, CARD_FADE_SEC).set_delay(delay).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
		tween.tween_property(card, "scale", Vector2.ONE, CARD_SCALE_SEC).set_delay(delay).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		order += 1
