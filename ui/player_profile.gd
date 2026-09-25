extends Object
class_name PlayerProfile

## 本机身份。全是 static，不是 Autoload。只写 user://profile.json。
const PATH := "user://profile.json"
const TMP_PATH := "user://profile.json.tmp"
const FILE_NAME := "profile.json"
const TMP_NAME := "profile.json.tmp"
const FILE_VERSION: int = 1
const DEFAULT_NAME := "Player"
const SPECIES_BOAR := "boar"
const SPECIES_CHICKEN := "chicken"
const MIN_NAME_LENGTH: int = 1
const MAX_NAME_LENGTH: int = 16
const PROFILE_ID_BYTES: int = 16

static var _profile_id: String = ""
static var _display_name: String = DEFAULT_NAME
static var _avatar_id: String = SPECIES_BOAR
static var _preferred_character_id: String = SPECIES_BOAR

static func load_from_disk() -> void:
	if not FileAccess.file_exists(PATH):
		_apply_defaults()
		save_to_disk()
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		_apply_defaults()
		save_to_disk()
		return
	var root: Dictionary = parsed as Dictionary
	var stored_id: String = str(root.get("profile_id", "")).strip_edges()
	if stored_id.is_empty():
		_apply_defaults()
		save_to_disk()
		return
	_profile_id = stored_id
	_display_name = _name_or_default(str(root.get("display_name", "")))
	_avatar_id = _species_or_default(str(root.get("avatar_id", "")))
	_preferred_character_id = _species_or_default(str(root.get("preferred_character_id", "")))
	if _needs_rewrite(root):
		save_to_disk()

static func save_to_disk() -> void:
	if _profile_id.is_empty():
		_profile_id = _make_profile_id()
	var payload: Dictionary = {
		"version": FILE_VERSION,
		"profile_id": _profile_id,
		"display_name": _display_name,
		"avatar_id": _avatar_id,
		"preferred_character_id": _preferred_character_id,
	}
	_write_atomic(JSON.stringify(payload))

static func get_profile_id() -> String:
	return _profile_id

static func get_display_name() -> String:
	return _display_name

static func get_avatar_id() -> String:
	return _avatar_id

static func get_preferred_character_id() -> String:
	return _preferred_character_id

static func set_display_name(requested: String) -> bool:
	var trimmed: String = requested.strip_edges()
	if not _is_visible_name(trimmed):
		return false
	_display_name = trimmed
	save_to_disk()
	return true

static func set_avatar_id(requested: String) -> bool:
	if not _is_species(requested):
		return false
	_avatar_id = requested
	save_to_disk()
	return true

static func set_preferred_character_id(requested: String) -> bool:
	if not _is_species(requested):
		return false
	_preferred_character_id = requested
	save_to_disk()
	return true

static func _apply_defaults() -> void:
	_profile_id = _make_profile_id()
	_display_name = DEFAULT_NAME
	_avatar_id = SPECIES_BOAR
	_preferred_character_id = SPECIES_BOAR

static func _needs_rewrite(root: Dictionary) -> bool:
	if int(root.get("version", -1)) != FILE_VERSION:
		return true
	if str(root.get("display_name", "")) != _display_name:
		return true
	if str(root.get("avatar_id", "")) != _avatar_id:
		return true
	if str(root.get("preferred_character_id", "")) != _preferred_character_id:
		return true
	return false

static func _name_or_default(requested: String) -> String:
	var trimmed: String = requested.strip_edges()
	if _is_visible_name(trimmed):
		return trimmed
	return DEFAULT_NAME

static func _is_visible_name(name: String) -> bool:
	if name.length() < MIN_NAME_LENGTH or name.length() > MAX_NAME_LENGTH:
		return false
	for index: int in name.length():
		var code: int = name.unicode_at(index)
		if code < 32 or code == 127:
			return false
	return true

static func _species_or_default(requested: String) -> String:
	if _is_species(requested):
		return requested
	return SPECIES_BOAR

static func _is_species(requested: String) -> bool:
	return requested == SPECIES_BOAR or requested == SPECIES_CHICKEN

static func _make_profile_id() -> String:
	var crypto: Crypto = Crypto.new()
	return crypto.generate_random_bytes(PROFILE_ID_BYTES).hex_encode()

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
