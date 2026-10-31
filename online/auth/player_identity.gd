extends RefCounted
class_name PlayerIdentity

## 客户端侧玩家身份快照（来自 WildBoat /me 或 login 响应）。

var account_id: String = ""
var player_id: String = ""
var email: String = ""
var status: String = ""
var email_verified: bool = false
var display_name: String = ""
var avatar_id: String = "default"
var bio: String = ""


func is_logged_in_identity() -> bool:
	return not account_id.is_empty() and not player_id.is_empty()


static func from_me_payload(payload: Dictionary) -> PlayerIdentity:
	var out := PlayerIdentity.new()
	out.account_id = str(payload.get("account_id", ""))
	out.email = str(payload.get("email", ""))
	out.status = str(payload.get("status", ""))
	out.email_verified = bool(payload.get("email_verified", false))
	var player: Variant = payload.get("player", {})
	if typeof(player) == TYPE_DICTIONARY:
		var p: Dictionary = player
		out.player_id = str(p.get("player_id", ""))
		out.display_name = str(p.get("display_name", ""))
		out.avatar_id = str(p.get("avatar_id", "default"))
		out.bio = str(p.get("bio", ""))
	return out


func to_public_dict() -> Dictionary:
	## 不含 email 以外可展示字段；绝不含 token。
	return {
		"account_id": account_id,
		"player_id": player_id,
		"display_name": display_name,
		"avatar_id": avatar_id,
		"status": status,
		"email_verified": email_verified,
	}
