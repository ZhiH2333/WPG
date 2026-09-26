#!/usr/bin/env python3
"""写出 ui/game_theme.tres 和焦点用的小图标。"""

import struct
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ICON_DIR = ROOT / "ui" / "theme_icons"
THEME_PATH = ROOT / "ui" / "game_theme.tres"

BG = "Color(0.141176, 0.121569, 0.105882, 1)"
SURFACE = "Color(0.941176, 0.901961, 0.839216, 1)"
INK = "Color(0.180392, 0.141176, 0.109804, 1)"
PAPER = "Color(0.941176, 0.901961, 0.839216, 1)"
SECONDARY = "Color(0.419608, 0.368627, 0.321569, 1)"
MUTED = "Color(0.788235, 0.733333, 0.658824, 1)"
LINE = "Color(0.788235, 0.733333, 0.658824, 1)"
ACCENT = "Color(0.701961, 0.360784, 0.219608, 1)"
ACCENT_DOWN = "Color(0.603922, 0.305882, 0.188235, 1)"
SUCCESS = "Color(0.360784, 0.4, 0.258824, 1)"
WARNING = "Color(0.65098, 0.486275, 0.196078, 1)"
ERROR = "Color(0.721569, 0.239216, 0.180392, 1)"
DISABLED = "Color(0.54902, 0.505882, 0.470588, 1)"
CLEAR = "Color(0, 0, 0, 0)"

INK_RGB = (46, 36, 28, 255)
ACCENT_RGB = (179, 92, 56, 255)
PAPER_RGB = (240, 230, 214, 255)
LINE_RGB = (201, 187, 168, 255)
DISABLED_RGB = (140, 129, 120, 255)


def write_png(path: Path, width: int, height: int, pixel) -> None:
	rows = []
	for y in range(height):
		row = bytearray([0])
		for x in range(width):
			row.extend(pixel(x, y))
		rows.append(bytes(row))
	raw = b"".join(rows)

	def chunk(tag: bytes, data: bytes) -> bytes:
		return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

	ihdr = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
	path.write_bytes(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))


def solid(color):
	return lambda _x, _y: color


def box_icon(fill, border) -> None:
	def pixel(x, y):
		edge = x < 2 or y < 2 or x >= 16 or y >= 16
		return border if edge else fill
	return pixel


def write_icons() -> None:
	ICON_DIR.mkdir(parents=True, exist_ok=True)
	write_png(ICON_DIR / "grabber.png", 8, 18, solid(INK_RGB))
	write_png(ICON_DIR / "grabber_focus.png", 8, 18, solid(ACCENT_RGB))
	write_png(ICON_DIR / "grabber_disabled.png", 8, 18, solid(DISABLED_RGB))
	write_png(ICON_DIR / "check_off.png", 18, 18, box_icon((0, 0, 0, 0), INK_RGB))
	write_png(ICON_DIR / "check_on.png", 18, 18, box_icon(ACCENT_RGB, INK_RGB))
	write_png(ICON_DIR / "check_off_disabled.png", 18, 18, box_icon((0, 0, 0, 0), DISABLED_RGB))
	write_png(ICON_DIR / "check_on_disabled.png", 18, 18, box_icon(DISABLED_RGB, DISABLED_RGB))


def flat(res_id: str, bg: str, border: str, left: int = 4, bottom: int = 2, ml: float = 16, mt: float = 10, mr: float = 16, mb: float = 10) -> str:
	return (
		f'[sub_resource type="StyleBoxFlat" id="{res_id}"]\n'
		f"content_margin_left = {ml}\ncontent_margin_top = {mt}\ncontent_margin_right = {mr}\ncontent_margin_bottom = {mb}\n"
		f"bg_color = {bg}\nborder_width_left = {left}\nborder_width_bottom = {bottom}\nborder_color = {border}\n"
		"corner_radius_top_left = 0\ncorner_radius_top_right = 0\ncorner_radius_bottom_right = 0\ncorner_radius_bottom_left = 0\n"
	)


def font_var(res_id: str, ext: str, weight: int) -> str:
	return (
		f'[sub_resource type="FontVariation" id="{res_id}"]\n'
		f'base_font = ExtResource("{ext}")\n'
		'fallbacks = Array[Font]([ExtResource("3_cjk")])\n'
		"variation_opentype = {\n"
		f'"wght": {weight}\n'
		"}\n"
	)


def button_block(name: str, font: str, size: int, normal: str, hover: str, pressed: str, focus: str, disabled: str, font_color: str, hover_color: str, focus_color: str, pressed_color: str, disabled_color: str) -> str:
	return (
		f'{name}/base_type = &"Button"\n'
		f'{name}/colors/font_color = {font_color}\n'
		f'{name}/colors/font_hover_color = {hover_color}\n'
		f'{name}/colors/font_focus_color = {focus_color}\n'
		f'{name}/colors/font_pressed_color = {pressed_color}\n'
		f'{name}/colors/font_disabled_color = {disabled_color}\n'
		f'{name}/fonts/font = SubResource("{font}")\n'
		f'{name}/font_sizes/font_size = {size}\n'
		f'{name}/constants/outline_size = 0\n'
		f'{name}/styles/normal = SubResource("{normal}")\n'
		f'{name}/styles/hover = SubResource("{hover}")\n'
		f'{name}/styles/pressed = SubResource("{pressed}")\n'
		f'{name}/styles/focus = SubResource("{focus}")\n'
		f'{name}/styles/disabled = SubResource("{disabled}")\n'
	)


def label_block(name: str, font: str, size: int, color: str, line: int) -> str:
	spacing = max(line - size, 0)
	return (
		f'{name}/base_type = &"Label"\n'
		f'{name}/colors/font_color = {color}\n'
		f'{name}/fonts/font = SubResource("{font}")\n'
		f'{name}/font_sizes/font_size = {size}\n'
		f'{name}/constants/outline_size = 0\n'
		f'{name}/constants/line_spacing = {spacing}\n'
	)


def write_theme() -> None:
	subs = []
	subs.append(font_var("fv_p700", "1_playpen", 700))
	subs.append(font_var("fv_p600", "1_playpen", 600))
	subs.append(font_var("fv_p500", "1_playpen", 500))
	subs.append(font_var("fv_s600", "2_sans", 600))
	subs.append(font_var("fv_s500", "2_sans", 500))
	subs.append(font_var("fv_s400", "2_sans", 400))
	subs.append(flat("sb_text", CLEAR, CLEAR))
	subs.append(flat("sb_text_hover", CLEAR, INK))
	subs.append(flat("sb_text_focus", CLEAR, ACCENT))
	subs.append(flat("sb_text_pressed", CLEAR, INK))
	subs.append(flat("sb_text_disabled", CLEAR, CLEAR))
	subs.append(flat("sb_primary", ACCENT, CLEAR, bottom=0))
	subs.append(flat("sb_primary_hover", ACCENT_DOWN, CLEAR, bottom=0))
	subs.append(flat("sb_primary_focus", ACCENT, PAPER, bottom=0))
	subs.append(flat("sb_primary_pressed", INK, CLEAR, bottom=0))
	subs.append(flat("sb_primary_disabled", LINE, CLEAR, bottom=0))
	subs.append(flat("sb_selected", CLEAR, ACCENT))
	subs.append(flat("sb_line", CLEAR, LINE, ml=8, mt=8, mr=8, mb=8))
	subs.append(flat("sb_line_focus", CLEAR, ACCENT, ml=8, mt=8, mr=8, mb=8))
	subs.append(flat("sb_slider", LINE, CLEAR, left=0, bottom=0, ml=0, mt=8, mr=0, mb=8))
	subs.append(flat("sb_grab", INK, CLEAR, left=0, bottom=0, ml=0, mt=6, mr=0, mb=6))
	subs.append(flat("sb_grab_focus", ACCENT, CLEAR, left=0, bottom=0, ml=0, mt=6, mr=0, mb=6))
	subs.append(flat("sb_surface", SURFACE, CLEAR, left=0, bottom=0, ml=24, mt=24, mr=24, mb=24))
	subs.append(flat("sb_modal", SURFACE, CLEAR, left=0, bottom=0, ml=28, mt=24, mr=28, mb=24))
	subs.append(flat("sb_empty", CLEAR, CLEAR, left=0, bottom=0, ml=0, mt=0, mr=0, mb=0))
	subs.append(flat("sb_track", LINE, CLEAR, left=0, bottom=0, ml=0, mt=0, mr=0, mb=0))
	subs.append(flat("sb_fill_ink", INK, CLEAR, left=0, bottom=0, ml=0, mt=0, mr=0, mb=0))
	subs.append(flat("sb_fill_error", ERROR, CLEAR, left=0, bottom=0, ml=0, mt=0, mr=0, mb=0))
	subs.append(flat("sb_fill_success", SUCCESS, CLEAR, left=0, bottom=0, ml=0, mt=0, mr=0, mb=0))
	subs.append(flat("sb_check", CLEAR, CLEAR, ml=8, mt=4, mr=8, mb=4))
	subs.append(flat("sb_check_hover", CLEAR, INK, ml=8, mt=4, mr=8, mb=4))
	subs.append(flat("sb_check_focus", CLEAR, ACCENT, ml=8, mt=4, mr=8, mb=4))

	exts = [
		'[ext_resource type="FontFile" path="res://ui/fonts/PlaypenSans-Variable.ttf" id="1_playpen"]',
		'[ext_resource type="FontFile" path="res://ui/fonts/SourceSans3-Variable.ttf" id="2_sans"]',
		'[ext_resource type="FontFile" path="res://ui/fonts/NotoSansSC-Regular.otf" id="3_cjk"]',
		'[ext_resource type="Texture2D" path="res://ui/theme_icons/grabber.png" id="4_grab"]',
		'[ext_resource type="Texture2D" path="res://ui/theme_icons/grabber_focus.png" id="5_grab_focus"]',
		'[ext_resource type="Texture2D" path="res://ui/theme_icons/grabber_disabled.png" id="6_grab_off"]',
		'[ext_resource type="Texture2D" path="res://ui/theme_icons/check_off.png" id="7_off"]',
		'[ext_resource type="Texture2D" path="res://ui/theme_icons/check_on.png" id="8_on"]',
		'[ext_resource type="Texture2D" path="res://ui/theme_icons/check_off_disabled.png" id="9_off_d"]',
		'[ext_resource type="Texture2D" path="res://ui/theme_icons/check_on_disabled.png" id="10_on_d"]',
	]
	load_steps = len(exts) + len(subs) + 1
	parts = [f'[gd_resource type="Theme" load_steps={load_steps} format=3 uid="uid://b772hyjkxh87v"]', ""]
	parts.extend(exts)
	parts.append("")
	parts.extend(subs)

	stage_text = button_block("TextAction", "fv_s400", 18, "sb_text", "sb_text_hover", "sb_text_pressed", "sb_text_focus", "sb_text_disabled", PAPER, PAPER, PAPER, PAPER, MUTED)
	ink_text = button_block("InkTextAction", "fv_s400", 18, "sb_text", "sb_text_hover", "sb_text_pressed", "sb_text_focus", "sb_text_disabled", INK, INK, INK, INK, SECONDARY)
	nav = button_block("NavItem", "fv_p500", 18, "sb_text", "sb_text_hover", "sb_text_pressed", "sb_text_focus", "sb_text_disabled", PAPER, PAPER, PAPER, PAPER, MUTED)
	ink_nav = button_block("InkNav", "fv_s600", 14, "sb_text", "sb_text_hover", "sb_text_pressed", "sb_text_focus", "sb_text_disabled", INK, INK, INK, INK, SECONDARY)
	primary = button_block("PrimaryAction", "fv_p600", 22, "sb_primary", "sb_primary_hover", "sb_primary_pressed", "sb_primary_focus", "sb_primary_disabled", PAPER, PAPER, PAPER, PAPER, SECONDARY)
	secondary = button_block("SecondaryAction", "fv_p600", 22, "sb_text", "sb_text_hover", "sb_text_pressed", "sb_text_focus", "sb_text_disabled", PAPER, PAPER, PAPER, PAPER, MUTED)
	ink_secondary = button_block("InkSecondary", "fv_p600", 22, "sb_text", "sb_text_hover", "sb_text_pressed", "sb_text_focus", "sb_text_disabled", INK, INK, INK, INK, SECONDARY)
	action = button_block("ActionRow", "fv_s400", 18, "sb_text", "sb_text_hover", "sb_text_pressed", "sb_text_focus", "sb_text_disabled", PAPER, PAPER, PAPER, PAPER, MUTED)
	offer = button_block("OfferRow", "fv_s400", 18, "sb_text", "sb_text_hover", "sb_text_pressed", "sb_text_focus", "sb_text_disabled", INK, INK, INK, INK, SECONDARY)
	danger = button_block("DangerAction", "fv_s400", 18, "sb_text", "sb_text_hover", "sb_text_pressed", "sb_text_focus", "sb_text_disabled", ERROR, ERROR, ERROR, ERROR, MUTED)
	ink_danger = button_block("InkDanger", "fv_s400", 18, "sb_text", "sb_text_hover", "sb_text_pressed", "sb_text_focus", "sb_text_disabled", ERROR, ERROR, ERROR, ERROR, SECONDARY)
	selected = button_block("SelectedRow", "fv_s400", 18, "sb_selected", "sb_selected", "sb_text_pressed", "sb_text_focus", "sb_text_disabled", PAPER, PAPER, PAPER, PAPER, MUTED)
	ink_selected = button_block("InkSelected", "fv_s400", 18, "sb_selected", "sb_selected", "sb_text_pressed", "sb_text_focus", "sb_text_disabled", INK, INK, INK, INK, SECONDARY)
	record = button_block("RecordRow", "fv_s400", 18, "sb_text", "sb_text_hover", "sb_text_pressed", "sb_text_focus", "sb_text_disabled", PAPER, PAPER, PAPER, PAPER, MUTED)
	player = button_block("PlayerRow", "fv_s400", 18, "sb_text", "sb_text_hover", "sb_text_pressed", "sb_text_focus", "sb_text_disabled", PAPER, PAPER, PAPER, PAPER, MUTED)
	room = button_block("RoomRow", "fv_s400", 18, "sb_text", "sb_text_hover", "sb_text_pressed", "sb_text_focus", "sb_text_disabled", PAPER, PAPER, PAPER, PAPER, MUTED)
	choice = button_block("CharacterChoice", "fv_s400", 18, "sb_text", "sb_text_hover", "sb_text_pressed", "sb_text_focus", "sb_text_disabled", PAPER, PAPER, PAPER, PAPER, MUTED)
	icon = button_block("IconAction", "fv_p500", 18, "sb_text", "sb_text_hover", "sb_text_pressed", "sb_text_focus", "sb_text_disabled", PAPER, PAPER, PAPER, PAPER, MUTED)

	labels = [
		label_block("Display", "fv_p700", 56, PAPER, 64),
		label_block("InkDisplay", "fv_p700", 56, INK, 64),
		label_block("Page", "fv_p600", 32, PAPER, 40),
		label_block("InkPage", "fv_p600", 32, INK, 40),
		label_block("Navigation", "fv_p500", 18, PAPER, 24),
		label_block("InkNavigation", "fv_p500", 18, INK, 24),
		label_block("PlayerName", "fv_p700", 40, PAPER, 48),
		label_block("InkPlayerName", "fv_p700", 40, INK, 48),
		label_block("RailTitle", "fv_p600", 22, PAPER, 28),
		label_block("InkRailTitle", "fv_p600", 22, INK, 28),
		label_block("Section", "fv_s600", 14, MUTED, 20),
		label_block("InkSection", "fv_s600", 14, SECONDARY, 20),
		label_block("Body", "fv_s400", 18, PAPER, 28),
		label_block("InkBody", "fv_s400", 18, INK, 28),
		label_block("Caption", "fv_s400", 15, MUTED, 22),
		label_block("InkCaption", "fv_s400", 15, SECONDARY, 22),
		label_block("Numeric", "fv_s500", 20, PAPER, 24),
		label_block("InkNumeric", "fv_s500", 20, INK, 24),
		label_block("Technical", "fv_s400", 14, MUTED, 20),
		label_block("InkTechnical", "fv_s400", 14, SECONDARY, 20),
		label_block("StatusSuccess", "fv_s400", 18, SUCCESS, 28),
		label_block("InkStatusSuccess", "fv_s400", 18, SUCCESS, 28),
		label_block("StatusWarning", "fv_s400", 18, WARNING, 28),
		label_block("InkStatusWarning", "fv_s400", 18, WARNING, 28),
		label_block("StatusError", "fv_s400", 18, ERROR, 28),
		label_block("InkStatusError", "fv_s400", 18, ERROR, 28),
	]
	resource = ["[resource]"]
	resource.append('default_font = SubResource("fv_s400")')
	resource.append("default_font_size = 18")
	resource.append(f"Label/colors/font_color = {PAPER}")
	resource.append('Label/fonts/font = SubResource("fv_s400")')
	resource.append("Label/font_sizes/font_size = 18")
	resource.append("Label/constants/outline_size = 0")
	resource.append("Label/constants/line_spacing = 10")
	button_default = stage_text.replace("TextAction/", "Button/").replace("Button/base_type = &\"Button\"\n", "")
	resource.append(button_default)
	resource.append('PanelContainer/styles/panel = SubResource("sb_empty")')
	resource.append(stage_text)
	resource.append(nav)
	resource.append(primary)
	resource.append(secondary)
	resource.append(action)
	resource.append(offer)
	resource.append(danger)
	resource.append(ink_text)
	resource.append(ink_nav)
	resource.append(ink_secondary)
	resource.append(ink_danger)
	resource.append(selected)
	resource.append(ink_selected)
	resource.append(record)
	resource.append(player)
	resource.append(room)
	resource.append(choice)
	resource.append(icon)
	resource.extend(labels)
	resource.append('OpenSheet/base_type = &"PanelContainer"')
	resource.append('OpenSheet/styles/panel = SubResource("sb_empty")')
	resource.append('SurfaceGroup/base_type = &"PanelContainer"')
	resource.append('SurfaceGroup/styles/panel = SubResource("sb_surface")')
	resource.append('Modal/base_type = &"PanelContainer"')
	resource.append('Modal/styles/panel = SubResource("sb_modal")')
	resource.append('Drawer/base_type = &"PanelContainer"')
	resource.append('Drawer/styles/panel = SubResource("sb_surface")')
	resource.append(f"LineEdit/colors/font_color = {PAPER}")
	resource.append(f"LineEdit/colors/font_placeholder_color = {MUTED}")
	resource.append(f"LineEdit/colors/caret_color = {ACCENT}")
	resource.append('LineEdit/fonts/font = SubResource("fv_s400")')
	resource.append("LineEdit/font_sizes/font_size = 18")
	resource.append('LineEdit/styles/normal = SubResource("sb_line")')
	resource.append('LineEdit/styles/focus = SubResource("sb_line_focus")')
	resource.append('LineEdit/styles/read_only = SubResource("sb_line")')
	resource.append('InkLineEdit/base_type = &"LineEdit"')
	resource.append(f"InkLineEdit/colors/font_color = {INK}")
	resource.append(f"InkLineEdit/colors/font_placeholder_color = {SECONDARY}")
	resource.append(f"InkLineEdit/colors/caret_color = {ACCENT}")
	resource.append('HSlider/styles/slider = SubResource("sb_slider")')
	resource.append('HSlider/styles/grabber_area = SubResource("sb_grab")')
	resource.append('HSlider/styles/grabber_area_highlight = SubResource("sb_grab_focus")')
	resource.append('HSlider/icons/grabber = ExtResource("4_grab")')
	resource.append('HSlider/icons/grabber_highlight = ExtResource("5_grab_focus")')
	resource.append('HSlider/icons/grabber_disabled = ExtResource("6_grab_off")')
	resource.append(f"CheckBox/colors/font_color = {INK}")
	resource.append(f"CheckBox/colors/font_hover_color = {INK}")
	resource.append(f"CheckBox/colors/font_focus_color = {INK}")
	resource.append(f"CheckBox/colors/font_pressed_color = {INK}")
	resource.append(f"CheckBox/colors/font_disabled_color = {SECONDARY}")
	resource.append('CheckBox/fonts/font = SubResource("fv_s400")')
	resource.append("CheckBox/font_sizes/font_size = 18")
	resource.append('CheckBox/styles/normal = SubResource("sb_check")')
	resource.append('CheckBox/styles/hover = SubResource("sb_check_hover")')
	resource.append('CheckBox/styles/pressed = SubResource("sb_check")')
	resource.append('CheckBox/styles/focus = SubResource("sb_check_focus")')
	resource.append('CheckBox/styles/disabled = SubResource("sb_check")')
	resource.append('CheckBox/icons/checked = ExtResource("8_on")')
	resource.append('CheckBox/icons/unchecked = ExtResource("7_off")')
	resource.append('CheckBox/icons/checked_disabled = ExtResource("10_on_d")')
	resource.append('CheckBox/icons/unchecked_disabled = ExtResource("9_off_d")')
	resource.append(f"OptionButton/colors/font_color = {INK}")
	resource.append(f"OptionButton/colors/font_focus_color = {INK}")
	resource.append(f"OptionButton/colors/font_hover_color = {INK}")
	resource.append('OptionButton/fonts/font = SubResource("fv_s400")')
	resource.append("OptionButton/font_sizes/font_size = 18")
	resource.append('OptionButton/styles/normal = SubResource("sb_line")')
	resource.append('OptionButton/styles/hover = SubResource("sb_line")')
	resource.append('OptionButton/styles/pressed = SubResource("sb_line")')
	resource.append('OptionButton/styles/focus = SubResource("sb_line_focus")')
	resource.append('ProgressBar/styles/background = SubResource("sb_track")')
	resource.append('ProgressBar/styles/fill = SubResource("sb_fill_ink")')
	resource.append('ProgressBarLow/base_type = &"ProgressBar"')
	resource.append('ProgressBarLow/styles/fill = SubResource("sb_fill_error")')
	resource.append('ProgressBarXp/base_type = &"ProgressBar"')
	resource.append('ProgressBarXp/styles/fill = SubResource("sb_fill_success")')
	resource.append('RankBar/base_type = &"ProgressBar"')
	resource.append('RankBar/styles/fill = SubResource("sb_fill_ink")')
	parts.append("\n".join(resource))
	THEME_PATH.write_text("\n".join(parts) + "\n", encoding="utf-8")


def main() -> None:
	write_icons()
	write_theme()
	print(THEME_PATH)


if __name__ == "__main__":
	main()
