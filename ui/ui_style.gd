extends Object
class_name UiStyle

## 把一棵玩家界面收到 UI 2.0 的 Theme variation 上，并清掉逐控件的字号和字色补丁。
const _LABELS := {
	&"MenuTitle": &"Display",
	&"PauseTitle": &"Page",
	&"FloatingHeader": &"Page",
	&"ClearedTitle": &"Page",
	&"RunSummaryTitle": &"Page",
	&"WinnerNewBest": &"StatusSuccess",
	&"ProfileHeader": &"Section",
	&"SettingsHeader": &"Section",
	&"SettingsNavCaption": &"Section",
	&"ModeTitle": &"Section",
	&"OfferTitle": &"Section",
	&"StripCaption": &"RailTitle",
	&"ProfileName": &"PlayerName",
	&"ClockLabel": &"Technical",
	&"HudHp": &"Numeric",
	&"HudPhrase": &"Body",
	&"HudWeapon": &"Caption",
	&"OfferDesc": &"Caption",
	&"RunSummaryHint": &"Caption",
	&"RunSummaryBody": &"Body",
	&"WinnerHist": &"Caption",
	&"WinnerHistHi": &"Numeric",
	&"WinnerScore": &"Numeric",
}
const _BUTTONS := {
	&"EmptyButton": &"TextAction",
	&"PillPink": &"PrimaryAction",
	&"LogoButton": &"PrimaryAction",
	&"PillNeutral": &"SecondaryAction",
	&"PillRed": &"DangerAction",
	&"MainMenuButton": &"ActionRow",
	&"OfferButton": &"ActionRow",
	&"BarButton": &"NavItem",
	&"IconBarButton": &"NavItem",
}
const _INK_LABEL := {
	&"Display": &"InkDisplay",
	&"Page": &"InkPage",
	&"Navigation": &"InkNavigation",
	&"PlayerName": &"InkPlayerName",
	&"RailTitle": &"InkRailTitle",
	&"Section": &"InkSection",
	&"Body": &"InkBody",
	&"Caption": &"InkCaption",
	&"Numeric": &"InkNumeric",
	&"Technical": &"InkTechnical",
	&"StatusSuccess": &"InkStatusSuccess",
	&"StatusWarning": &"InkStatusWarning",
	&"StatusError": &"InkStatusError",
}
const _INK_BUTTON := {
	&"TextAction": &"InkTextAction",
	&"SecondaryAction": &"InkSecondary",
	&"ActionRow": &"OfferRow",
	&"NavItem": &"InkNav",
	&"DangerAction": &"InkDanger",
}
const _STYLE_KEYS: PackedStringArray = ["normal", "hover", "pressed", "focus", "disabled", "panel"]

static func present(root: Node, on_paper: bool = false) -> void:
	if root == null:
		return
	_visit(root, on_paper)

static func scrim(rect: ColorRect) -> void:
	if rect == null:
		return
	rect.color = UiTokens.SCRIM

static func _visit(node: Node, on_paper: bool) -> void:
	if node is SettingsNavButton:
		return
	_dress(node, on_paper)
	for child: Node in node.get_children():
		_visit(child, on_paper)

static func _dress(node: Node, on_paper: bool) -> void:
	var rect: ColorRect = node as ColorRect
	if rect != null:
		_dress_rect(rect)
		return
	var label: Label = node as Label
	if label != null:
		_dress_label(label, on_paper)
		return
	if node is CheckBox:
		_clear_text(node as Control)
		(node as CheckBox).theme_type_variation = &""
		return
	if node is OptionButton:
		_clear_text(node as Control)
		(node as OptionButton).theme_type_variation = &""
		return
	var button: Button = node as Button
	if button != null:
		_dress_button(button, on_paper)
		return
	var panel: PanelContainer = node as PanelContainer
	if panel != null:
		_dress_panel(panel, on_paper)
		return
	var edit: LineEdit = node as LineEdit
	if edit != null:
		_clear_text(edit)
		edit.theme_type_variation = &"InkLineEdit" if on_paper else &""

static func _dress_rect(rect: ColorRect) -> void:
	if rect.name == &"Dimmer":
		rect.color = UiTokens.SCRIM
		return
	if rect.name == &"Vignette" or rect.name == &"Wash":
		rect.visible = false
		rect.color = UiTokens.CLEAR
		return
	if rect.name == &"Separator":
		rect.color = UiTokens.LINE
		return
	if rect.name == &"Fill":
		rect.color = UiTokens.ERROR if rect.get_parent() is HoldConfirmButton else UiTokens.SURFACE
		return
	if rect.name == &"Sidebar" or rect.name == &"HeaderBg":
		rect.color = UiTokens.SURFACE

static func _dress_label(label: Label, on_paper: bool) -> void:
	_clear_text(label)
	var role: StringName = _LABELS.get(label.theme_type_variation, label.theme_type_variation)
	if role == &"":
		role = &"Body"
	if on_paper and _INK_LABEL.has(role):
		role = _INK_LABEL[role]
	label.theme_type_variation = role
	label.add_theme_constant_override("outline_size", 0)

static func _dress_button(button: BaseButton, on_paper: bool) -> void:
	_clear_text(button)
	_clear_styles(button)
	var role: StringName = _BUTTONS.get(button.theme_type_variation, button.theme_type_variation)
	if role == &"":
		role = &"TextAction"
	if on_paper and _INK_BUTTON.has(role):
		role = _INK_BUTTON[role]
	button.theme_type_variation = role

static func _dress_panel(panel: PanelContainer, on_paper: bool) -> void:
	_clear_styles(panel)
	var role: StringName = panel.theme_type_variation
	if role == &"SurfaceGroup" or role == &"Modal" or role == &"Drawer" or role == &"OpenSheet":
		return
	panel.theme_type_variation = &"SurfaceGroup" if on_paper else &"OpenSheet"

static func _clear_text(control: Control) -> void:
	control.remove_theme_color_override("font_color")
	control.remove_theme_color_override("font_hover_color")
	control.remove_theme_color_override("font_focus_color")
	control.remove_theme_color_override("font_pressed_color")
	control.remove_theme_color_override("font_outline_color")
	control.remove_theme_font_size_override("font_size")
	control.remove_theme_font_override("font")
	control.remove_theme_constant_override("outline_size")

static func _clear_styles(control: Control) -> void:
	for key: String in _STYLE_KEYS:
		if control.has_theme_stylebox_override(key):
			control.remove_theme_stylebox_override(key)
