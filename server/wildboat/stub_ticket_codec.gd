extends Object
class_name StubTicketCodec

## 本地联调 / 自动化测试专用 stub ticket。
## **不是** WildBoat 生产 game_ticket；生产路径必须走 WildBoat 签发 + validate。
##
## 格式：`wpgstub1.<player_id>.<match_id>.<instance_id>.<exp_unix>.<nonce>`

const PREFIX := "wpgstub1"


static func issue(
	player_id: String,
	_display_name: String,
	match_id: String,
	instance_id: String,
	exp_unix: int,
	nonce: String
) -> String:
	var pid: String = player_id.replace(".", "_")
	var mid: String = match_id.replace(".", "_")
	var iid: String = instance_id.replace(".", "_")
	var n: String = nonce.replace(".", "_")
	return "%s.%s.%s.%s.%d.%s" % [PREFIX, pid, mid, iid, exp_unix, n]


static func parse(ticket: String) -> Dictionary:
	var out: Dictionary = {"ok": false}
	var parts: PackedStringArray = ticket.split(".")
	if parts.size() != 6:
		return out
	if parts[0] != PREFIX:
		return out
	out["ok"] = true
	out["player_id"] = parts[1]
	out["display_name"] = ""
	out["match_id"] = parts[2]
	out["game_instance_id"] = parts[3]
	out["expires_at_unix"] = int(parts[4])
	out["nonce"] = parts[5]
	return out
