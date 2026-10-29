extends Object
class_name WpgI18n

## 翻译入口。
##
## 正式路径：project.godot 的 internationalization/locale/translations 登记
## locale/wpg.<locale>.translation（由 locale/wpg.csv 导入生成，导出包会带上）。
## 兜底路径：翻译资源尚未导入时（刚 clone、还没跑 --import），直接读 CSV 注册到 TranslationServer。
## 注意：导出包不含 wpg.csv 源文件，所以兜底只服务于开发期，不能当正式路径。
##
## 默认语言：en。首次启动（settings.cfg 里没有 locale）时由 GameSettings 按系统语言选 zh_CN / en。
## 缺译诊断：missing_keys_for_locale() 逐列检查；缺译或空值不会被英文兜底吞掉（见 wpg_i18n_test）。
const CSV_PATH := "res://locale/wpg.csv"
const DEFAULT_LOCALE := "en"

static var _bootstrapped: bool = false
static var _locales: PackedStringArray = PackedStringArray()

static func supported_default() -> PackedStringArray:
	return PackedStringArray(["en", "zh_CN"])

## CSV 表头里的语言列（不含 keys）。读不到时退回 supported_default()。
static func supported_locales() -> PackedStringArray:
	bootstrap()
	if _locales.is_empty():
		return supported_default()
	return _locales.duplicate()

static func bootstrap() -> void:
	if _bootstrapped:
		return
	_bootstrapped = true
	_locales.clear()
	var table: Dictionary = read_csv_table()
	if table.is_empty():
		## 导出包里没有 CSV，语言列表只能靠已登记的翻译资源推断。
		var loaded: PackedStringArray = TranslationServer.get_loaded_locales()
		for locale: String in supported_default():
			if loaded.has(locale):
				_locales.append(locale)
		return
	_locales = table["locales"]
	## 开发期诊断：缺译 / 空值会被引擎的 locale/fallback 悄悄顶成英文，所以在这里大声报出来。
	if OS.is_debug_build():
		for locale: String in _locales:
			var missing: PackedStringArray = missing_keys_for_locale(locale)
			if not missing.is_empty():
				push_error("WpgI18n: %s 缺译 %d 项：%s" % [locale, missing.size(), ", ".join(missing.slice(0, 8))])
	var loaded_locales: PackedStringArray = TranslationServer.get_loaded_locales()
	var fallback_needed: bool = false
	for locale: String in _locales:
		if not loaded_locales.has(locale):
			fallback_needed = true
	if fallback_needed:
		_register_from_table(table)

## 读 locale/wpg.csv。返回 {"locales": PackedStringArray, "rows": {key: PackedStringArray(各语言值)}, "order": [key...], "duplicates": [key...]}。
## 文件不存在返回 {}。使用 Godot 自带的 CSV 解析，引号 / 逗号 / 换行与导入器一致。
static func read_csv_table() -> Dictionary:
	if not FileAccess.file_exists(CSV_PATH):
		return {}
	var file: FileAccess = FileAccess.open(CSV_PATH, FileAccess.READ)
	if file == null:
		push_warning("WpgI18n: cannot open %s" % CSV_PATH)
		return {}
	var header: PackedStringArray = file.get_csv_line()
	if header.size() < 2 or header[0] != "keys":
		push_warning("WpgI18n: bad CSV header")
		return {}
	var locales: PackedStringArray = PackedStringArray()
	for col: int in range(1, header.size()):
		locales.append(header[col].strip_edges())
	var rows: Dictionary = {}
	var order: PackedStringArray = PackedStringArray()
	var duplicates: PackedStringArray = PackedStringArray()
	while not file.eof_reached():
		var cols: PackedStringArray = file.get_csv_line()
		if cols.is_empty() or cols[0].strip_edges().is_empty():
			continue
		var key: String = cols[0]
		var values: PackedStringArray = PackedStringArray()
		for col: int in locales.size():
			values.append(cols[col + 1] if col + 1 < cols.size() else "")
		if rows.has(key):
			duplicates.append(key)
		rows[key] = values
		order.append(key)
	return {"locales": locales, "rows": rows, "order": order, "duplicates": duplicates}

static func _register_from_table(table: Dictionary) -> void:
	var locales: PackedStringArray = table["locales"]
	var rows: Dictionary = table["rows"]
	for col: int in locales.size():
		var trn: Translation = Translation.new()
		trn.locale = locales[col]
		for key: String in rows:
			var value: String = String((rows[key] as PackedStringArray)[col])
			if value.is_empty():
				continue
			## 与 CSV 导入器 unescape_translations=true 保持一致。
			trn.add_message(key, value.replace("\\n", "\n"))
		TranslationServer.add_translation(trn)

## static 函数里不能用 tr()，用这个等价入口。key 缺失时返回 key 本身（不会悄悄回落成英文）。
static func t(key: String) -> String:
	return TranslationServer.translate(key)

## 网页版不会回退到系统字体（godotengine/godot#78921），内置字体里又没有 CJK 字形：
## 把仓库自带的 CJK 子集字体挂成默认字体的 fallback，所有没写 theme 字体的控件都能显示中文。
## 主题里的粗体 SystemFont 在 ui/game_theme.tres 里单独挂了 bold 子集。
const CJK_FONT_PATH := "res://ui/fonts/wpg_notice_cjk_regular.ttf"
static var _fonts_installed: bool = false

static func install_font_fallbacks() -> void:
	if _fonts_installed:
		return
	_fonts_installed = true
	var base: Font = ThemeDB.fallback_font
	var cjk: Font = load(CJK_FONT_PATH) as Font
	if base == null or cjk == null:
		push_warning("WpgI18n: CJK fallback font unavailable")
		return
	var chain: Array[Font] = []
	chain.assign(base.fallbacks)
	if not chain.has(cjk):
		chain.append(cjk)
		base.fallbacks = chain

static func apply_locale(locale: String) -> void:
	bootstrap()
	install_font_fallbacks()
	var chosen: String = locale.strip_edges()
	if chosen.is_empty() or not supported_locales().has(chosen):
		chosen = DEFAULT_LOCALE
	TranslationServer.set_locale(chosen)

## 某语言列里缺失 / 为空的 key。CSV 不可读时返回带诊断码的单元素数组，不会悄悄当作「没有缺译」。
static func missing_keys_for_locale(locale: String) -> PackedStringArray:
	var missing: PackedStringArray = PackedStringArray()
	var table: Dictionary = read_csv_table()
	if table.is_empty():
		missing.append("CSV_MISSING")
		return missing
	var locales: PackedStringArray = table["locales"]
	var col: int = locales.find(locale)
	if col < 0:
		missing.append("LOCALE_COLUMN_MISSING")
		return missing
	var rows: Dictionary = table["rows"]
	for key: String in table["order"]:
		if String((rows[key] as PackedStringArray)[col]).strip_edges().is_empty():
			missing.append(key)
	return missing
