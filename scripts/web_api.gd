extends Node
# The one place in the game that talks to the website (roadmap V4.1). Nothing else in the game opens a connection to it.
# The contract is docs/WEBSITE_API.md; the check `python tools/run_checks.py web_api` reads that file's error table and
# fails when the mapping below and the table disagree. Add the node to the scene tree and call:
#   var result = await web_api.request_api("GET", "releases/current")
#   if result["type"] == WebApi.ResultType.OK: ... result["data"] ...
# Rules:
#   - the address and the key come from the build: api_key.bin (scripts/api_key_file.gd, written by
#     tools/build_release.py). A game started from the Godot editor binary may instead read secrets.local.cfg or the
#     environment (scripts/secrets.gd) and take `--dev-api=URL` after `--`, like `--dev-coins`; an exported game
#     ignores both. Without an address and a key nothing is sent and every call is OFFLINE ("not_configured"): the
#     game plays offline as before,
#   - HTTPS only. The one exception is `http://127.0.0.1:PORT/` or `http://localhost:PORT/` in an editor run, which is
#     how the checks talk to tools/fake_api_server.py (V4.2). Certificates are checked by Godot as usual,
#   - a call never blocks a frame: the caller awaits it while the engine moves an HTTPRequest forward a little every
#     frame. It is deliberately NOT `use_threads`: a threaded HTTPRequest does blocking reads, and then both its
#     timeout and cancel_request() wait for the server, so a server that accepts the connection and goes silent
#     froze the game for as long as it stayed silent (measured with Godot 4.7.2: cancel took 20 s). Without threads
#     the timeout fires on time and the longest frame stays at a few milliseconds. The timeout is TIMEOUT_SECONDS for
#     the whole call, redirects are not followed (the API never sends one), a response over MAX_RESPONSE_BYTES is
#     refused, and the path is checked against a short list of characters so nothing a server says can change
#     where a call goes. The big download of V6 needs its own decision (it is not a call of this file),
#   - nothing is retried, in a loop or otherwise. A 429 or 503 answer carries `retry_after`; repeating the call once
#     after that time, and only while the player is waiting for it, is the caller's decision,
#   - every call ends in one small Dictionary with a result type: OK, OFFLINE, TIMEOUT, UNAUTHORIZED, KEY_REJECTED,
#     UPDATE_REQUIRED or SERVER_ERROR (the last column of the error table in docs/WEBSITE_API.md),
#   - nothing it prints holds a key, token, password, header or body: the log line has the method, the path (made of
#     letters, digits, `_`, `-` and `/` only), the result type, the status and the error code. A token is passed to a
#     call and never kept here,
#   - `enabled = false` (the ONLINE FEATURES setting of V4.4) sends nothing at all.

const Secrets = preload("res://scripts/secrets.gd")
const BuildInfo = preload("res://scripts/build_info.gd")
const ApiKeyFile = preload("res://scripts/api_key_file.gd")

enum ResultType { OK, OFFLINE, TIMEOUT, UNAUTHORIZED, KEY_REJECTED, UPDATE_REQUIRED, SERVER_ERROR }

const RESULT_NAMES = [
	"OK", "OFFLINE", "TIMEOUT", "UNAUTHORIZED", "KEY_REJECTED", "UPDATE_REQUIRED", "SERVER_ERROR"
]
const TIMEOUT_SECONDS = 5.0
const MAX_RESPONSE_BYTES = 1048576
const MAX_REQUEST_BYTES = 262144
const MAX_RETRY_AFTER = 3600.0
const MAX_KEY_LENGTH = 128
const MAX_TOKEN_LENGTH = 512
const MAX_URL_LENGTH = 256
const MAX_PATH_LENGTH = 128
const MAX_CODE_LENGTH = 64
const ARG_DEV_API = "--dev-api="
const METHODS = ["GET", "POST", "PUT"]
const LOOPBACK_HOSTS = ["127.0.0.1", "localhost"]
const PATH_CHARACTERS = "abcdefghijklmnopqrstuvwxyz0123456789_-/"
const CODE_CHARACTERS = "abcdefghijklmnopqrstuvwxyz0123456789_"
const HOST_CHARACTERS = "abcdefghijklmnopqrstuvwxyz0123456789.-"
const SOURCE_NONE = "not set"
const SOURCE_DEV_ARG = "--dev-api"
const SOURCE_SECRETS = "secrets"
const SOURCE_BUILD = "build file"
const SOURCE_DIRECT = "set directly"

# The error code of docs/WEBSITE_API.md (the one error shape) and the result type the game makes of it. save_conflict is
# OK with "conflict" set (the 409 of the saves, V8); every other code is an error.
const CODE_TYPES = {
	"bad_request": ResultType.SERVER_ERROR,
	"invalid_json": ResultType.SERVER_ERROR,
	"key_missing": ResultType.KEY_REJECTED,
	"invalid_credentials": ResultType.UNAUTHORIZED,
	"token_missing": ResultType.UNAUTHORIZED,
	"token_expired": ResultType.UNAUTHORIZED,
	"token_invalid": ResultType.UNAUTHORIZED,
	"token_reused": ResultType.UNAUTHORIZED,
	"key_rejected": ResultType.KEY_REJECTED,
	"https_required": ResultType.SERVER_ERROR,
	"forbidden": ResultType.SERVER_ERROR,
	"not_found": ResultType.SERVER_ERROR,
	"method_not_allowed": ResultType.SERVER_ERROR,
	"save_conflict": ResultType.OK,
	"payload_too_large": ResultType.SERVER_ERROR,
	"unsupported_media_type": ResultType.SERVER_ERROR,
	"save_invalid": ResultType.SERVER_ERROR,
	"save_format_too_new": ResultType.SERVER_ERROR,
	"update_required": ResultType.UPDATE_REQUIRED,
	"throttled": ResultType.SERVER_ERROR,
	"server_error": ResultType.SERVER_ERROR,
	"maintenance": ResultType.OFFLINE,
}

# false: nothing is sent, every call is OFFLINE ("disabled"). V4.4 connects the ONLINE FEATURES setting to this.
var enabled = true
# true: print one log line per call (never a secret, see the rules above).
var log_calls = true
# true in an editor run, false in an exported game: http on this computer and `--dev-api` are only allowed then.
var allow_dev = Secrets.allowed()
var base_url = ""
var api_key = ""
var config_problems = []
var base_source = SOURCE_NONE
var key_source = SOURCE_NONE
# How many calls went out on the wire. The checks read it (a call that was refused or disabled does not count).
var requests_sent = 0

var _configured = false
var _version = ""
var _build_id = ""


func _ready() -> void:
	if not _configured:
		configure()


# Reads the address and the key (see `resolve_config`) and the identity of this build. `src` is for the check only.
func configure(src: Dictionary = {}) -> void:
	var found = resolve_config(OS.get_cmdline_user_args(), src)
	allow_dev = bool(src.get("allowed", Secrets.allowed()))
	base_url = str(found["base_url"])
	api_key = str(found["key"])
	base_source = str(found["base_source"])
	key_source = str(found["key_source"])
	config_problems = found["problems"]
	_read_identity()
	_configured = true


# Sets the address and the key directly (the checks and the fake server, V4.2). The same rules hold: a value that does
# not pass them leaves the call "not configured". Returns true when both were accepted.
func use_config(url: String, key: String) -> bool:
	_read_identity()
	_configured = true
	base_url = validate_base_url(url, allow_dev)
	api_key = key if is_valid_key(key) else ""
	base_source = SOURCE_DIRECT if not base_url.is_empty() else SOURCE_NONE
	key_source = SOURCE_DIRECT if not api_key.is_empty() else SOURCE_NONE
	return is_configured()


func is_configured() -> bool:
	return not base_url.is_empty() and not api_key.is_empty()


# One line about the setup for a log: where each value came from, never the value.
func status_line() -> String:
	return (
		"web api: base_url: %s; key: %s; online features: %s"
		% [base_source, key_source, "on" if enabled else "off"]
	)


# Makes one call and returns its result. `body` is null for a GET and a Dictionary for POST and PUT. `token` is the
# access token for the calls that need one. The Dictionary has: "type" (ResultType), "status" (0 when nothing came
# back), "code" (the API's error code, or ""), "reason" (why the game itself gave up, or ""), "retry_after" (seconds,
# 0 when none), "conflict" (true for save_conflict) and "data" (the parsed JSON object, {} when there is none).
func request_api(method: String, path: String, body = null, token: String = "") -> Dictionary:
	var refused = _refusal(method, path, body, token)
	if not refused.is_empty():
		_log(method, path, refused)
		return refused
	var text = ""
	if body != null:
		text = JSON.stringify(body)
	var headers = build_headers(_version, _build_id, api_key, token, body != null)
	var http = HTTPRequest.new()
	http.timeout = TIMEOUT_SECONDS
	http.max_redirects = 0
	http.body_size_limit = MAX_RESPONSE_BYTES
	http.use_threads = false
	add_child(http)
	var started = http.request(base_url + path, headers, _http_method(method), text)
	if started != OK:
		http.queue_free()
		var failed = make_result(ResultType.OFFLINE, 0, "", "request_not_started")
		_log(method, path, failed)
		return failed
	requests_sent += 1
	var done = await http.request_completed
	http.queue_free()
	var result = interpret(int(done[0]), int(done[1]), done[2], done[3])
	_log(method, path, result)
	return result


# ---------------------------------------------------------------- the rules, as functions the check can call


# The name of a result type: "OFFLINE".
static func type_name(type: int) -> String:
	if type < 0 or type >= RESULT_NAMES.size():
		return "UNKNOWN"
	return RESULT_NAMES[type]


# A result Dictionary with every key.
static func make_result(
	type: int, status: int = 0, code: String = "", reason: String = "", data: Dictionary = {}
) -> Dictionary:
	return {
		"type": type,
		"status": status,
		"code": code,
		"reason": reason,
		"retry_after": 0.0,
		"conflict": false,
		"data": data,
	}


# The result of one answer. `http_result` is HTTPRequest's result (RESULT_SUCCESS, RESULT_TIMEOUT, ...), `status` the
# HTTP status, `headers` its "Name: value" lines and `body` the bytes. Never an error, whatever the server sent.
static func interpret(
	http_result: int, status: int, headers: PackedStringArray, body: PackedByteArray
) -> Dictionary:
	if http_result != HTTPRequest.RESULT_SUCCESS:
		return _failed_connection(http_result)
	var parsed = _parse_object(body)
	if status >= 200 and status < 300:
		if status == 204 or body.is_empty():
			return make_result(ResultType.OK, status)
		if not parsed["ok"]:
			return make_result(ResultType.SERVER_ERROR, status, "", "bad_json")
		return make_result(ResultType.OK, status, "", "", parsed["data"])
	var error = {}
	if parsed["ok"] and typeof(parsed["data"].get("error")) == TYPE_DICTIONARY:
		error = parsed["data"]["error"]
	var code = _clean_code(error.get("code"))
	var result = make_result(_type_for(code, status), status, code)
	result["retry_after"] = _retry_after(error.get("retry_after"), headers)
	if code == "save_conflict":
		result["conflict"] = true
		result["data"] = parsed["data"]
	return result


# The headers of a call. The key, the version and the build go on every call (docs/WEBSITE_API.md), the token only when
# there is one, Content-Type only with a body.
static func build_headers(
	version: String, build_id: String, key: String, token: String, has_body: bool
) -> PackedStringArray:
	var headers = PackedStringArray()
	headers.append("Accept: application/json")
	headers.append("X-FB3D-Key: " + key)
	headers.append("X-FB3D-Version: " + version)
	headers.append("X-FB3D-Build: " + build_id)
	if has_body:
		headers.append("Content-Type: application/json")
	if not token.is_empty():
		headers.append("Authorization: Bearer " + token)
	return headers


# true for a call path like "releases/current" or "saves/versions/12": no slash at the start or the end, no empty or
# dotted part, only the characters of PATH_CHARACTERS.
static func is_valid_path(path: String) -> bool:
	if path.is_empty() or path.length() > MAX_PATH_LENGTH:
		return false
	if path.begins_with("/") or path.ends_with("/") or path.contains("//"):
		return false
	for i in range(path.length()):
		if not PATH_CHARACTERS.contains(path[i]):
			return false
	return true


# true for text that is safe to put in a header: 1 to `max_length` printable ASCII characters, no space.
static func is_header_safe(text: String, max_length: int) -> bool:
	if text.is_empty() or text.length() > max_length:
		return false
	for i in range(text.length()):
		var c = text.unicode_at(i)
		if c <= 32 or c >= 127:
			return false
	return true


static func is_valid_key(key: String) -> bool:
	return is_header_safe(key, MAX_KEY_LENGTH) and not Secrets.is_placeholder(key)


# The address with a closing slash, or "" when it is not allowed: https only (http only for this computer and only
# when `allow_dev`), a host made of letters, digits, `.` and `-` and an optional port, no user name, query, fragment,
# space or backslash, not longer than MAX_URL_LENGTH, and not a template value.
static func validate_base_url(url: String, allow_dev_http: bool) -> String:
	var text = url.strip_edges()
	if text.is_empty() or text.length() > MAX_URL_LENGTH or Secrets.is_placeholder(text):
		return ""
	for i in range(text.length()):
		var c = text.unicode_at(i)
		if c <= 32 or c >= 127 or "@?#\\".contains(text[i]):
			return ""
	var rest = ""
	var secure = false
	if text.begins_with("https://"):
		rest = text.substr(8)
		secure = true
	elif text.begins_with("http://"):
		rest = text.substr(7)
	else:
		return ""
	var host_port = rest.get_slice("/", 0)
	var host = host_port.get_slice(":", 0)
	if host.is_empty() or host.begins_with(".") or host.begins_with("-") or host.contains(".."):
		return ""
	for i in range(host.length()):
		if not HOST_CHARACTERS.contains(host[i].to_lower()):
			return ""
	if host_port.contains(":"):
		var port = host_port.get_slice(":", 1)
		if not port.is_valid_int() or int(port) < 1 or int(port) > 65535 or port.length() > 5:
			return ""
	if not secure and not (allow_dev_http and LOOPBACK_HOSTS.has(host)):
		return ""
	if not text.ends_with("/"):
		text += "/"
	return text


# The `--dev-api=URL` argument: {"url": the address or "", "problems": texts}. Without `allow_dev_http` (an exported
# game) the argument is ignored without a word.
static func parse_dev_api(args: PackedStringArray, allow_dev_http: bool) -> Dictionary:
	var out = {"url": "", "problems": []}
	if not allow_dev_http:
		return out
	for arg in args:
		if arg.begins_with(ARG_DEV_API):
			var url = validate_base_url(arg.substr(ARG_DEV_API.length()), true)
			if url.is_empty():
				out["problems"].append(
					"--dev-api: expected https://host/path/ (or http://127.0.0.1:PORT/), left out"
				)
			else:
				out["url"] = url
	return out


# Where the address and the key come from. In an editor run: `--dev-api` (address only), then secrets.local.cfg or the
# environment (scripts/secrets.gd), then the build file. In an exported game only the build file. A value that does not
# pass its rules is skipped and named in "problems" (never printed). `src` is for the check only: "allowed" (instead
# of Secrets.allowed()), "secrets" (the `src` of Secrets.lookup) and "build_path" (instead of api_key.bin).
# Returns {"base_url", "key", "base_source", "key_source", "problems"}.
static func resolve_config(args: PackedStringArray, src: Dictionary = {}) -> Dictionary:
	var dev = bool(src.get("allowed", Secrets.allowed()))
	var secrets_src = src.get("secrets", {"allowed": dev})
	var build = ApiKeyFile.load_file(str(src.get("build_path", ApiKeyFile.FILE)))
	var out = {
		"base_url": "",
		"key": "",
		"base_source": SOURCE_NONE,
		"key_source": SOURCE_NONE,
		"problems": [],
	}
	var dev_arg = parse_dev_api(args, dev)
	out["problems"].append_array(dev_arg["problems"])
	var url_candidates = [
		[SOURCE_DEV_ARG, str(dev_arg["url"])],
		[SOURCE_SECRETS, Secrets.get_value("api", "base_url", "", secrets_src)],
		[SOURCE_BUILD, str(build["base_url"])],
	]
	for c in url_candidates:
		if str(c[1]).is_empty():
			continue
		var url = validate_base_url(str(c[1]), dev)
		if url.is_empty():
			out["problems"].append("api address from %s: not allowed, left out" % c[0])
			continue
		out["base_url"] = url
		out["base_source"] = c[0]
		break
	var key_candidates = [
		[SOURCE_SECRETS, Secrets.get_value("api", "key", "", secrets_src)],
		[SOURCE_BUILD, str(build["key"])],
	]
	for c in key_candidates:
		if str(c[1]).is_empty():
			continue
		if not is_valid_key(str(c[1])):
			out["problems"].append("api key from %s: not usable, left out" % c[0])
			continue
		out["key"] = str(c[1])
		out["key_source"] = c[0]
		break
	if build["source"] == ApiKeyFile.SOURCE_DAMAGED:
		out["problems"].append("api_key.bin: damaged, not used")
	return out


# ----------------------------------------------------------------------------------------------------- inside


func _read_identity() -> void:
	var info = BuildInfo.load_info()
	_version = str(info["version"])
	_build_id = BuildInfo.header_text(info)


# {} when the call may go out, else the result to hand back without sending anything.
func _refusal(method: String, path: String, body, token: String) -> Dictionary:
	if not _configured:
		configure()
	if not enabled:
		return make_result(ResultType.OFFLINE, 0, "", "disabled")
	if not is_configured():
		return make_result(ResultType.OFFLINE, 0, "", "not_configured")
	if _version.is_empty() or not is_header_safe(_build_id, 16):
		return make_result(ResultType.SERVER_ERROR, 0, "", "no_version")
	if not METHODS.has(method):
		return make_result(ResultType.SERVER_ERROR, 0, "", "bad_method")
	if not is_valid_path(path):
		return make_result(ResultType.SERVER_ERROR, 0, "", "bad_path")
	if method == "GET" and body != null:
		return make_result(ResultType.SERVER_ERROR, 0, "", "get_with_body")
	if body != null and typeof(body) != TYPE_DICTIONARY:
		return make_result(ResultType.SERVER_ERROR, 0, "", "bad_body")
	if body != null and JSON.stringify(body).to_utf8_buffer().size() > MAX_REQUEST_BYTES:
		return make_result(ResultType.SERVER_ERROR, 0, "", "request_too_large")
	if not token.is_empty() and not is_header_safe(token, MAX_TOKEN_LENGTH):
		return make_result(ResultType.SERVER_ERROR, 0, "", "bad_token")
	if not is_inside_tree():
		return make_result(ResultType.SERVER_ERROR, 0, "", "not_in_tree")
	return {}


func _http_method(method: String) -> int:
	if method == "POST":
		return HTTPClient.METHOD_POST
	if method == "PUT":
		return HTTPClient.METHOD_PUT
	return HTTPClient.METHOD_GET


func _log(method: String, path: String, result: Dictionary) -> void:
	if not log_calls:
		return
	var line = "web api: %s %s -> %s" % [method, _safe_path(path), type_name(int(result["type"]))]
	if int(result["status"]) != 0:
		line += " " + str(result["status"])
	if not str(result["code"]).is_empty():
		line += " " + str(result["code"])
	if not str(result["reason"]).is_empty():
		line += " (" + str(result["reason"]) + ")"
	print(line)


# The path for a log line: a path that is not valid is not printed at all.
static func _safe_path(path: String) -> String:
	if is_valid_path(path):
		return path
	return "(invalid path)"


static func _failed_connection(http_result: int) -> Dictionary:
	if http_result == HTTPRequest.RESULT_TIMEOUT:
		return make_result(ResultType.TIMEOUT, 0, "", "timeout")
	var offline = [
		HTTPRequest.RESULT_CANT_CONNECT,
		HTTPRequest.RESULT_CANT_RESOLVE,
		HTTPRequest.RESULT_CONNECTION_ERROR,
		HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR,
		HTTPRequest.RESULT_NO_RESPONSE,
	]
	if offline.has(http_result):
		return make_result(ResultType.OFFLINE, 0, "", "no_connection")
	if http_result == HTTPRequest.RESULT_REDIRECT_LIMIT_REACHED:
		return make_result(ResultType.SERVER_ERROR, 0, "", "redirect")
	if http_result == HTTPRequest.RESULT_BODY_SIZE_LIMIT_EXCEEDED:
		return make_result(ResultType.SERVER_ERROR, 0, "", "response_too_large")
	return make_result(ResultType.SERVER_ERROR, 0, "", "http_result_%d" % http_result)


# The result type of an error answer: by its code, and when the code is missing or unknown by the status, where only
# 426 and 503 say something on their own (the table in docs/WEBSITE_API.md: a status it does not list is server_error).
static func _type_for(code: String, status: int) -> int:
	if CODE_TYPES.has(code):
		return CODE_TYPES[code]
	if status == 426:
		return ResultType.UPDATE_REQUIRED
	if status == 503:
		return ResultType.OFFLINE
	return ResultType.SERVER_ERROR


# {"ok": true, "data": the object} when the bytes are a JSON object, else {"ok": false}.
static func _parse_object(body: PackedByteArray) -> Dictionary:
	if body.is_empty() or body.size() > MAX_RESPONSE_BYTES:
		return {"ok": false}
	var json = JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK:
		return {"ok": false}
	if typeof(json.data) != TYPE_DICTIONARY:
		return {"ok": false}
	return {"ok": true, "data": json.data}


# The error code as the server sent it, or "" when it is not a string of lower case letters, digits and `_`.
static func _clean_code(value) -> String:
	if typeof(value) != TYPE_STRING:
		return ""
	var code: String = value
	if code.is_empty() or code.length() > MAX_CODE_LENGTH:
		return ""
	for i in range(code.length()):
		if not CODE_CHARACTERS.contains(code[i]):
			return ""
	return code


# Seconds to wait: the body's number, else the Retry-After header, else 0; never negative, never over MAX_RETRY_AFTER.
static func _retry_after(from_body, headers: PackedStringArray) -> float:
	var seconds = -1.0
	if typeof(from_body) == TYPE_INT or typeof(from_body) == TYPE_FLOAT:
		seconds = float(from_body)
	else:
		for line in headers:
			var parts = line.split(":", true, 1)
			if parts.size() == 2 and parts[0].strip_edges().to_lower() == "retry-after":
				var text = parts[1].strip_edges()
				if text.is_valid_int():
					seconds = float(int(text))
	if is_nan(seconds) or seconds < 0.0:
		return 0.0
	return minf(seconds, MAX_RETRY_AFTER)
