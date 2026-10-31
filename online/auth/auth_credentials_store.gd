extends RefCounted
class_name AuthCredentialsStore

## 会话凭证持久化。
##
## 限制（未完成安全存储）：
## - 当前写入 Godot `user://` 普通文件（平台依赖，非 OS Keychain / Keystore）。
## - Desktop / 导出物上该文件可被同用户进程读取；**不得宣称已完成安全凭证存储**。
## - 不持久化 access_token（短命，内存持有）；只持久化 refresh_token + session 元数据。
## - 永不写入 password。

const STORE_PATH := "user://wpass_session.json"
const STORE_VERSION: int = 1


func save_session(
	refresh_token: String,
	session_id: String,
	refresh_expires_at: String,
	account_id: String,
	player_id: String,
	display_name: String,
	base_url: String
) -> bool:
	if refresh_token.is_empty() or session_id.is_empty():
		return false
	var payload: Dictionary = {
		"v": STORE_VERSION,
		"refresh_token": refresh_token,
		"session_id": session_id,
		"refresh_expires_at": refresh_expires_at,
		"account_id": account_id,
		"player_id": player_id,
		"display_name": display_name,
		"base_url": base_url,
		"saved_at": Time.get_datetime_string_from_system(true),
		"storage": "user_file_unencrypted",
		"security_note": "NOT OS secure storage; local-dev / interim only",
	}
	var file: FileAccess = FileAccess.open(STORE_PATH, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(payload))
	return true


func load_session() -> Dictionary:
	if not FileAccess.file_exists(STORE_PATH):
		return {}
	var file: FileAccess = FileAccess.open(STORE_PATH, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	var data: Dictionary = parsed
	if int(data.get("v", 0)) != STORE_VERSION:
		return {}
	if str(data.get("refresh_token", "")).is_empty():
		return {}
	return data


func clear() -> void:
	var absolute: String = ProjectSettings.globalize_path(STORE_PATH)
	if FileAccess.file_exists(STORE_PATH) or FileAccess.file_exists(absolute):
		DirAccess.remove_absolute(absolute)


func storage_is_secure() -> bool:
	## 明确对外声明：当前实现不是安全凭证存储。
	return false
