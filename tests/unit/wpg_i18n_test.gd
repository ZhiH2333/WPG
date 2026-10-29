extends SceneTree

## i18n 完整性（运行时一侧；静态扫描一侧见 tools/i18n/audit.py + tools/test/test_i18n_audit.py）。
##
## 1. locale/wpg.csv：key 唯一、各语言列无缺失 / 空值、占位符各语言一致。
## 2. 已登记的 .translation 与 CSV 逐 key 一致（防止忘记重新导入而用着旧翻译）。
## 3. 运行时切换语言后 tr() 立刻命中；缺失 key 不会被英文悄悄顶上。
## 4. 设置里的语言选项 = 翻译表里真实存在的语言列，选一项就真的切过去。
## 5. 已创建的界面切语言后，脚本生成的文案会被重写（不是重开场景才生效）。
## 6. 各界面场景在每种语言下：没有残留的翻译 key、没有残留的英文单词（带白名单）。
## 7. 随包 CJK 字体覆盖翻译表里每一个非 ASCII 字符，以及界面上实际出现的每个字符。
##
## 跑法：godot --headless --path . --script res://tests/unit/wpg_i18n_test.gd --quit
## 通过输出 WPG_I18N_OK；失败逐条 WPG_I18N_FAIL 并返回非 0。

const CJK_FONTS := [
	"res://ui/fonts/wpg_notice_cjk_regular.ttf",
	"res://ui/fonts/wpg_notice_cjk_bold.ttf",
]

## 要逐个检查的界面场景。能独立实例化的都在这里；挂了运行时依赖的（HUD 等）也会被 _ready 正常带起来。
const SCENES := [
	"res://ui/main_menu.tscn",
	"res://ui/play_page.tscn",
	"res://ui/lan_overlay.tscn",
	"res://ui/settings_overlay.tscn",
	"res://ui/pause_overlay.tscn",
	"res://ui/winner_page.tscn",
	"res://ui/record_selector.tscn",
	"res://ui/profile_overlay.tscn",
	"res://ui/record_leaderboard_overlay.tscn",
	"res://ui/credits_overlay.tscn",
	"res://ui/test_build_notice.tscn",
	"res://ui/shop_offer.tscn",
	"res://ui/upgrade_offer.tscn",
	"res://ui/room_notice.tscn",
	"res://ui/hud.tscn",
]

## 非 en 语言里允许出现的拉丁词，以及原因。其余 3 个字母以上的英文单词都算「漏翻」。
const LATIN_ALLOWED := {
	"WPG": "游戏品牌名",
	"Bug": "通用外来词，原文如此（NOTICE_*）",
	"MSAA": "技术缩写（SETTINGS_MSAA）",
	"IPv4": "协议名",
	"IPv6": "协议名",
	"RB": "手柄肩键缩写（GAMEPAD_DEBUG_STATUS）",
	"Start": "手柄 Start 键的实体键帽文字",
	"Guide": "手柄 Guide 键的实体键帽文字",
	"English": "语言自称（SETTINGS_LANGUAGE_EN）",
	"Studio": "工作室品牌名（FM Studio）",
	"IPv": "协议名 IPv4 / IPv6 的字母部分",
	"Space": "OS.get_keycode_string() 提供的键帽名称（引擎输出，不属于翻译表）",
	"Player": "玩家昵称默认值 / 用户自己起的昵称（用户数据，不属于翻译表）",
	"Godot": "引擎名称",
	"github": "仓库链接",
	"com": "仓库链接",
	"ZhiH": "作者账号",
	"Cursor": "致谢名单里的账号名",
	"Charles": "致谢名单里的账号名",
	"gmail": "邮箱地址（NOTICE_REPORT_BUG）",
	"zhih": "邮箱地址（NOTICE_REPORT_BUG）",
}

var _failures: PackedStringArray = PackedStringArray()
var _original_locale: String = "en"
## 各界面实际显示过的非 ASCII 字符 -> 来源，字体检查要覆盖它们（含制作名单里的昵称）。
var _shown_chars: Dictionary = {}

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	PlayerProfile.load_from_disk()
	GameSettings.load_from_disk()
	_original_locale = GameSettings.get_locale()
	WpgI18n.bootstrap()
	_case_table_integrity()
	_case_registered_matches_csv()
	_case_locale_switch()
	await _case_settings_language_options()
	await _case_runtime_refresh()
	await _case_scenes_have_no_leftovers()
	_case_fonts_cover_translations()
	## 还原：别把测试里切过的语言留在玩家的 settings.cfg 里。
	GameSettings.set_locale(_original_locale)
	GameSettings.apply()
	GameSettings.save_to_disk()
	if _failures.is_empty():
		print("WPG_I18N_OK")
		quit(0)
		return
	for failure: String in _failures:
		printerr("WPG_I18N_FAIL: %s" % failure)
	quit(1)

func _expect(cond: bool, msg: String) -> void:
	if not cond:
		_failures.append(msg)

func _unescape(value: String) -> String:
	return value.replace("\\n", "\n")

# ---- 1. 表本身 ----

func _case_table_integrity() -> void:
	var table: Dictionary = WpgI18n.read_csv_table()
	_expect(not table.is_empty(), "locale/wpg.csv 读得到")
	if table.is_empty():
		return
	var locales: PackedStringArray = table["locales"]
	_expect(locales.has("en") and locales.has("zh_CN"), "语言列至少有 en / zh_CN，实际 %s" % ",".join(locales))
	_expect(WpgI18n.supported_locales() == locales, "supported_locales() 与 CSV 表头一致")
	_expect((table["duplicates"] as PackedStringArray).is_empty(), "不存在重复 key：%s" % ",".join(table["duplicates"]))
	_expect((table["order"] as PackedStringArray).size() > 300, "key 数量合理（>300），实际 %d" % (table["order"] as PackedStringArray).size())
	for locale: String in locales:
		var missing: PackedStringArray = WpgI18n.missing_keys_for_locale(locale)
		_expect(missing.is_empty(), "%s 缺译 / 空值: %s" % [locale, ",".join(missing)])
	var spec: RegEx = RegEx.new()
	spec.compile("%[-+ #0]*\\d*(?:\\.\\d+)?[sdfxXcio]")
	var rows: Dictionary = table["rows"]
	var base_col: int = locales.find("en")
	for key: String in table["order"]:
		var values: PackedStringArray = rows[key]
		var base_specs: PackedStringArray = _specs(spec, values[base_col])
		for col: int in locales.size():
			var specs: PackedStringArray = _specs(spec, values[col])
			_expect(specs == base_specs, "占位符不一致 %s[%s]: %s vs %s" % [key, locales[col], ",".join(base_specs), ",".join(specs)])

func _specs(spec: RegEx, text: String) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for m: RegExMatch in spec.search_all(text.replace("%%", "")):
		out.append(m.get_string())
	return out

# ---- 2. 已登记翻译 == CSV ----

func _case_registered_matches_csv() -> void:
	var table: Dictionary = WpgI18n.read_csv_table()
	if table.is_empty():
		return
	var locales: PackedStringArray = table["locales"]
	var rows: Dictionary = table["rows"]
	var loaded: PackedStringArray = TranslationServer.get_loaded_locales()
	for locale: String in locales:
		_expect(loaded.has(locale), "TranslationServer 已加载 %s（project.godot 的 translations 要登记 .translation）" % locale)
		var trn: Translation = TranslationServer.get_translation_object(locale)
		_expect(trn != null and trn.locale == locale, "找得到 %s 的 Translation 对象" % locale)
		if trn == null or trn.locale != locale:
			continue
		var col: int = locales.find(locale)
		var stale: PackedStringArray = PackedStringArray()
		for key: String in table["order"]:
			var want: String = _unescape(String((rows[key] as PackedStringArray)[col]))
			if String(trn.get_message(key)) != want:
				stale.append(key)
		_expect(stale.is_empty(), "%s 的 .translation 与 CSV 不一致（需要重新导入）: %s" % [locale, ",".join(stale.slice(0, 8))])

# ---- 3. 切换 ----

func _case_locale_switch() -> void:
	WpgI18n.apply_locale("en")
	_expect(TranslationServer.get_locale() == "en", "apply_locale(en) 生效")
	_expect(tr("HUD_GOLD") % 5 == "gold  5", "en HUD_GOLD 带格式")
	_expect(tr("WEAPON_PISTOL") == "Pistol", "en WEAPON_PISTOL")
	WpgI18n.apply_locale("zh_CN")
	_expect(TranslationServer.get_locale() == "zh_CN", "apply_locale(zh_CN) 生效")
	_expect(tr("HUD_GOLD") % 5 == "金币  5", "zh_CN HUD_GOLD 带格式")
	_expect(tr("WEAPON_PISTOL") == "手枪", "zh_CN WEAPON_PISTOL")
	_expect(tr("WEAPON_SMG") == "冲锋枪", "zh_CN WEAPON_SMG")
	_expect(tr("HUD_ROUND") % 3 == "第 3 回合", "zh_CN HUD_ROUND")
	## 缺失 key 必须原样露出，不能被英文兜底吞掉。
	_expect(tr("NO_SUCH_KEY_FOR_TEST") == "NO_SUCH_KEY_FOR_TEST", "缺失 key 原样返回（不静默兜底）")
	WpgI18n.apply_locale("fr")
	_expect(TranslationServer.get_locale() == "en", "不支持的语言回到默认 en")
	WpgI18n.apply_locale("en")

# ---- 4. 设置里的语言选项 ----

func _case_settings_language_options() -> void:
	var packed: PackedScene = load("res://ui/settings_overlay.tscn") as PackedScene
	_expect(packed != null, "settings_overlay.tscn 能加载")
	if packed == null:
		return
	GameSettings.set_locale("en")
	GameSettings.apply()
	var overlay: SettingsOverlay = packed.instantiate() as SettingsOverlay
	root.add_child(overlay)
	await process_frame
	var locales: PackedStringArray = WpgI18n.supported_locales()
	var option: OptionButton = overlay._language_option
	_expect(option != null, "设置页有语言下拉")
	if option == null:
		overlay.queue_free()
		return
	_expect(option.item_count == locales.size(), "语言选项数 %d == 翻译表语言列数 %d" % [option.item_count, locales.size()])
	for index: int in locales.size():
		_expect(option.get_item_text(index) == tr("SETTINGS_LANGUAGE_%s" % locales[index].to_upper()), "语言项 %d 显示 %s 的自称" % [index, locales[index]])
	_expect(option.get_selected_id() == locales.find("en"), "当前语言 en 被选中")
	for index: int in locales.size():
		option.select(index)
		overlay._on_language_selected(index)
		_expect(GameSettings.get_locale() == locales[index], "选择第 %d 项后 GameSettings 语言 == %s" % [index, locales[index]])
		_expect(TranslationServer.get_locale() == locales[index], "选择第 %d 项后运行时语言 == %s" % [index, locales[index]])
		_expect(overlay._version_label.text == tr("COMMON_VERSION") % GameSettings.get_version(), "切到 %s 后版本行已重写" % locales[index])
	overlay.queue_free()
	await process_frame

# ---- 5. 已创建界面切语言后立刻更新 ----

func _case_runtime_refresh() -> void:
	GameSettings.set_locale("en")
	GameSettings.apply()
	GameSettings.save_to_disk()
	var packed: PackedScene = load("res://ui/main_menu.tscn") as PackedScene
	var menu: MainMenu = packed.instantiate() as MainMenu
	root.add_child(menu)
	for _i: int in 4:
		await process_frame
	_expect(menu._player_status.text == "Ready to play", "en 主菜单状态行")
	var overlay: SettingsOverlay = menu._overlay
	var locales: PackedStringArray = WpgI18n.supported_locales()
	var zh_index: int = locales.find("zh_CN")
	overlay._on_language_selected(zh_index)
	await process_frame
	_expect(menu._player_status.text == "准备就绪", "切到 zh_CN 后主菜单状态行立刻更新，实际 %s" % menu._player_status.text)
	## Rail EmptyButton 自身不带 text；标题在子 Label，靠 key 自动重译。
	_expect(menu._solo_button.text.is_empty(), "SOLO Rail 不写 button.text，避免与子 Label 叠字")
	var solo_title: Label = menu._solo_button.get_node("Text/Title") as Label
	_expect(solo_title != null and solo_title.atr(solo_title.text) == "单人", "切到 zh_CN 后 SOLO 标题立刻更新")
	_expect(overlay._status_label != null, "设置层仍在")
	overlay._on_language_selected(locales.find("en"))
	await process_frame
	_expect(menu._player_status.text == "Ready to play", "切回 en 后主菜单状态行恢复")
	menu.queue_free()
	await process_frame

# ---- 6. 场景里没有漏翻 ----

func _case_scenes_have_no_leftovers() -> void:
	var table: Dictionary = WpgI18n.read_csv_table()
	var keys: Dictionary = table["rows"] if not table.is_empty() else {}
	var latin: RegEx = RegEx.new()
	latin.compile("[A-Za-z]{3,}")
	for locale: String in WpgI18n.supported_locales():
		## 有的界面 _ready 会重读 settings.cfg，所以语言要像玩家真的选过一样先落盘。
		GameSettings.set_locale(locale)
		GameSettings.apply()
		GameSettings.save_to_disk()
		for path: String in SCENES:
			var packed: PackedScene = load(path) as PackedScene
			_expect(packed != null, "%s 能加载" % path)
			if packed == null:
				continue
			var node: Node = packed.instantiate()
			root.add_child(node)
			await process_frame
			for entry: Dictionary in _collect_texts(node):
				var shown: String = str(entry["shown"])
				var where: String = "%s [%s] %s" % [path, locale, entry["path"]]
				for i: int in shown.length():
					if shown.unicode_at(i) > 0x7e:
						_shown_chars[shown.unicode_at(i)] = where
				_expect(not keys.has(shown), "%s 显示出了翻译 key（缺译 / 未重译）：%s" % [where, shown])
				if locale == "en":
					continue
				for m: RegExMatch in latin.search_all(shown):
					var word: String = m.get_string()
					_expect(LATIN_ALLOWED.has(word), "%s 残留英文单词 %s（整句：%s）" % [where, word, shown])
			node.queue_free()
			await process_frame
	GameSettings.set_locale("en")
	GameSettings.apply()
	GameSettings.save_to_disk()

## 收集节点树里所有会显示出来的文本（已按当前语言翻译）。
func _collect_texts(node: Node) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var stack: Array[Node] = [node]
	while not stack.is_empty():
		var current: Node = stack.pop_back()
		for child: Node in current.get_children():
			stack.append(child)
		var path: String = str(node.get_path_to(current))
		if current is Label:
			_push_text(out, path, (current as Label).text, current)
		elif current is Button:
			_push_text(out, path, (current as Button).text, current)
			if current is OptionButton:
				var option: OptionButton = current as OptionButton
				for i: int in option.item_count:
					_push_text(out, "%s/item%d" % [path, i], option.get_item_text(i), current)
		elif current is LineEdit:
			_push_text(out, path + "/placeholder", (current as LineEdit).placeholder_text, current)
		if current is Control and (current as Control).tooltip_text != "":
			_push_text(out, path + "/tooltip", (current as Control).tooltip_text, current)
	return out

func _push_text(out: Array[Dictionary], path: String, text: String, owner_node: Node) -> void:
	if text.strip_edges().is_empty():
		return
	out.append({"path": path, "text": text, "shown": owner_node.atr(text)})

# ---- 7. 字体 ----

func _case_fonts_cover_translations() -> void:
	var table: Dictionary = WpgI18n.read_csv_table()
	if table.is_empty():
		return
	var fonts: Array[Font] = []
	for path: String in CJK_FONTS:
		var font: Font = load(path) as Font
		_expect(font != null, "%s 能加载" % path)
		if font != null:
			fonts.append(font)
	var rows: Dictionary = table["rows"]
	var locales: PackedStringArray = table["locales"]
	var chars: Dictionary = {}
	for key: String in table["order"]:
		var values: PackedStringArray = rows[key]
		for col: int in locales.size():
			for i: int in values[col].length():
				var code: int = values[col].unicode_at(i)
				if code > 0x7e:
					chars[code] = key
	for font: Font in fonts:
		var missing: PackedStringArray = PackedStringArray()
		for code: int in chars:
			if not font.has_char(code):
				missing.append("%s(U+%04X,%s)" % [String.chr(code), code, chars[code]])
		_expect(missing.is_empty(), "字体 %s 缺字（重跑 tools/fonts/subset_notice_font.py）: %s" % [font.get_font_name(), ",".join(missing.slice(0, 10))])
	## 主题里的粗体是 SystemFont：网页版没有系统字体，必须挂 CJK 子集作 fallback。
	var theme: Theme = load("res://ui/game_theme.tres") as Theme
	var themed: Font = theme.get_font("font", "Caption") if theme != null else null
	_expect(themed != null and themed.fallbacks.size() >= 1, "game_theme 的粗体挂了 CJK fallback")
	## 默认字体链：内置字体本身没有 CJK，必须靠 fallback 才显示得出来。
	WpgI18n.install_font_fallbacks()
	var base: Font = ThemeDB.fallback_font
	_expect(base.fallbacks.size() >= 1, "默认字体挂了 CJK fallback")
	for code: int in chars:
		_expect(base.has_char(code), "默认字体链缺字 U+%04X（%s）" % [code, chars[code]])
	## 界面上真正显示过的每个非 ASCII 字符（含制作名单里的昵称、箭头等符号）。
	for code: int in _shown_chars:
		_expect(base.has_char(code), "默认字体链缺界面字符 U+%04X（%s）" % [code, _shown_chars[code]])
