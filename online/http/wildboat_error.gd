extends RefCounted
class_name WildboatError

## WildBoat HTTPS 错误信封。按稳定 `code` 分支，不依赖本地化 message。

var http_status: int = 0
var code: String = ""
var message: String = ""
var request_id: String = ""
var details: Dictionary = {}
var transport_error: String = ""
var cancelled: bool = false


func is_transport() -> bool:
	return not transport_error.is_empty() or cancelled


func is_auth_failure() -> bool:
	return code in [
		"AUTH_INVALID_CREDENTIALS",
		"AUTH_SESSION_EXPIRED",
		"AUTH_REQUIRED",
		"ACCOUNT_NOT_VERIFIED",
		"ACCOUNT_LOCKED",
		"ACCOUNT_CLOSED",
	]


static func from_transport(err: String, cancelled_flag: bool = false) -> WildboatError:
	var out := WildboatError.new()
	out.transport_error = err
	out.cancelled = cancelled_flag
	out.code = "TRANSPORT_ERROR" if not cancelled_flag else "CANCELLED"
	out.message = err if not cancelled_flag else "request cancelled"
	return out


static func from_http(status: int, body: Variant, request_id_header: String = "") -> WildboatError:
	var out := WildboatError.new()
	out.http_status = status
	out.request_id = request_id_header
	if typeof(body) == TYPE_DICTIONARY:
		var err_obj: Variant = body.get("error", {})
		if typeof(err_obj) == TYPE_DICTIONARY:
			var err_dict: Dictionary = err_obj
			out.code = str(err_dict.get("code", ""))
			out.message = str(err_dict.get("message", ""))
			out.request_id = str(err_dict.get("request_id", out.request_id))
			var det: Variant = err_dict.get("details", {})
			if typeof(det) == TYPE_DICTIONARY:
				out.details = det
	if out.code.is_empty():
		out.code = "HTTP_%d" % status
	if out.message.is_empty():
		out.message = "HTTP %d" % status
	return out


func to_dict() -> Dictionary:
	return {
		"http_status": http_status,
		"code": code,
		"message": message,
		"request_id": request_id,
		"details": details,
		"transport_error": transport_error,
		"cancelled": cancelled,
	}
