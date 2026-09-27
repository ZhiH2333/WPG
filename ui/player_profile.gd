extends Object
class_name PlayerProfile

## 本机身份。全是 static，不是 Autoload，不进场景树。只写 user://profile.json。
## 边界：不碰 progress.cfg / records.json / settings.cfg；profile_id 不是 network token、不是 seat、不是 peer_id。
const PATH := "user://profile.json"
const TMP_PATH := "user://profile.json.tmp"
const FILE_NAME := "profile.json"
const TMP_NAME := "profile.json.tmp"
const SAVE_VERSION: int = 1
## 可见字符上限。用 String.length()（码点）计，够覆盖 1–16 个字符的昵称。
const NAME_MAX: int = 16
const DEFAULT_NAME := "Player"
const DEFAULT_AVATAR := "boar"
const DEFAULT_CHARACTER := "boar"
const CHARACTER_IDS: PackedStringArray = ["boar", "chicken"]

static var _profile_id: String = ""
static var _display_name: String = DEFAULT_NAME
static var _avatar_id: String = DEFAULT_AVATAR
static var _preferred_character_id: String = DEFAULT_CHARACTER

## 首次启动（或无文件 / 文件损坏 / 字段缺失）会补全并落盘一次。
static func load_from_disk() -> void:
	_profile_id = ""
	_display_name = DEFAULT_NAME
	_avatar_id = DEFAULT_AVATAR
	_preferred_character_id = DEFAULT_CHARACTER
	if not FileAccess.file_exists(PATH):
		_profile_id = _generate_id()
		save_to_disk()
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		_profile_id = _generate_id()
		save_to_disk()
		return
	var root: Dictionary = parsed as Dictionary
	var raw_id: String = str(root.get("profile_id", ""))
	var raw_name: String = str(root.get("display_name", DEFAULT_NAME))
	var raw_avatar: String = str(root.get("avatar_id", DEFAULT_AVATAR))
	var raw_character: String = str(root.get("preferred_character_id", DEFAULT_CHARACTER))
	_profile_id = raw_id
	_display_name = sanitize_name(raw_name)
	_avatar_id = sanitize_character_id(raw_avatar)
	_preferred_character_id = sanitize_character_id(raw_character)
	# 只有在需要补 id / 夹昵称 / 归整未知角色时才回写，正常读档不写盘。
	var dirty: bool = (
		raw_id.is_empty()
		or raw_name != _display_name
		or raw_avatar != _avatar_id
		or raw_character != _preferred_character_id
		or int(root.get("version", 0)) != SAVE_VERSION
	)
	if _profile_id.is_empty():
		_profile_id = _generate_id()
		dirty = true
	if dirty:
		save_to_disk()

static func save_to_disk() -> void:
	if _profile_id.is_empty():
		_profile_id = _generate_id()
	var payload: Dictionary = {
		"version": SAVE_VERSION,
		"profile_id": _profile_id,
		"display_name": _display_name,
		"avatar_id": _avatar_id,
		"preferred_character_id": _preferred_character_id,
	}
	_write_atomic(JSON.stringify(payload, "  "))

# ---- getters（Profile 页与大厅只读这些，不直接读文件） ----

static func get_profile_id() -> String:
	return _profile_id

static func get_display_name() -> String:
	return _display_name

static func get_avatar_id() -> String:
	return _avatar_id

static func get_preferred_character_id() -> String:
	return _preferred_character_id

## 上网只发公开字段（PublicProfile）。selected_character_id 是 preferred 在房内的投影。
static func get_public_profile() -> Dictionary:
	return {
		"profile_id": _profile_id,
		"display_name": _display_name,
		"avatar_id": _avatar_id,
		"selected_character_id": _preferred_character_id,
	}

# ---- setters（就地生效，返回实际写入的值；失败回退到旧值/默认值） ----

static func set_display_name(value: String) -> String:
	var next: String = sanitize_name(value)
	if next == _display_name:
		return _display_name
	_display_name = next
	save_to_disk()
	return _display_name

static func set_avatar_id(value: String) -> String:
	var next: String = sanitize_character_id(value)
	if next == _avatar_id:
		return _avatar_id
	_avatar_id = next
	save_to_disk()
	return _avatar_id

static func set_preferred_character_id(value: String) -> String:
	var next: String = sanitize_character_id(value)
	if next == _preferred_character_id:
		return _preferred_character_id
	_preferred_character_id = next
	save_to_disk()
	return _preferred_character_id

## 头像槽的“换一个”：在已知角色里切到下一个。
static func cycle_avatar_id() -> String:
	var index: int = CHARACTER_IDS.find(_avatar_id)
	if index < 0:
		return set_avatar_id(DEFAULT_AVATAR)
	return set_avatar_id(CHARACTER_IDS[(index + 1) % CHARACTER_IDS.size()])

# ---- 校验 ----

## 1–16 可见字符；去首尾空白、去控制字符（JSON 可能被手改）。空 → 默认名。
static func sanitize_name(raw: String) -> String:
	var visible: String = ""
	for index: int in raw.length():
		var code: int = raw.unicode_at(index)
		if code < 32 or code == 127:
			continue
		visible += raw[index]
	visible = visible.strip_edges()
	if visible.is_empty():
		return DEFAULT_NAME
	if visible.length() > NAME_MAX:
		visible = visible.substr(0, NAME_MAX).strip_edges()
	if visible.is_empty():
		return DEFAULT_NAME
	return visible

static func sanitize_character_id(raw: String) -> String:
	if CHARACTER_IDS.has(raw):
		return raw
	return DEFAULT_AVATAR

static func is_known_character_id(raw: String) -> bool:
	return CHARACTER_IDS.has(raw)

static func _generate_id() -> String:
	return Crypto.new().generate_random_bytes(16).hex_encode()

static func _write_atomic(text: String) -> void:
	var file: FileAccess = FileAccess.open(TMP_PATH, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(text)
	file.flush()
	file.close()
	var dir: DirAccess = DirAccess.open("user://")
	if dir == null:
		return
	var err: Error = dir.rename(TMP_NAME, FILE_NAME)
	if err == OK:
		return
	dir.remove(FILE_NAME)
	dir.rename(TMP_NAME, FILE_NAME)
