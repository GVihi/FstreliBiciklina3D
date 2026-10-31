extends SceneTree
# Checks the game's one door to the website (roadmap V4.1): scripts/web_api.gd, scripts/api_key_file.gd and the way
# tools/build_release.py hands the key to the export. It needs no server: the answers of the website are fed in as
# data, and the one real call goes to a port nobody listens on. The full test against a fake website is V4.7.
#   - the result types and the mapping of every error code: the check reads the table in docs/WEBSITE_API.md and fails
#     when a code is missing from the game or maps to another type there (the doc and the game cannot drift apart),
#   - answers: 2xx, 204, damaged and non-object JSON, an unknown code, a status the table does not list, a redirect, a
#     response over the limit, retry_after from the body and from the header, the 409 conflict,
#   - the address (https only, http only for this computer in an editor run, no user name, template values refused),
#     the path (a short list of characters), `--dev-api` (ignored in an exported game), and where the address and the
#     key come from (secrets in an editor run, the build file everywhere, a damaged file never half used),
#   - the headers (key, version and build on every call, a token only when there is one, nothing that can inject a
#     header line) and that no log line or status line holds a key,
#   - api_key.bin: the shared cases of tools/api_key_file_cases.json (the same file tools/api_key_file.py runs), and a
#     changed, cut, oversized or foreign file is "damaged" and never an error,
#   - a call that is not configured, disabled, or has a bad path, method, body or token sends nothing; a call to a dead
#     port ends in OFFLINE without a frame being blocked,
#   - the key file is git-ignored and in the export preset's include_filter, and no print in web_api.gd can show a
#     key, token, header or body.
# Run from the project folder:
#   godot --headless --path . --script res://tools/web_api_check.gd
# or: python tools/run_checks.py web_api
# Exits with status 1 and prints the problems when a check fails.

const WebApi = preload("res://scripts/web_api.gd")
const ApiKeyFile = preload("res://scripts/api_key_file.gd")
const BuildInfo = preload("res://scripts/build_info.gd")
const DOC = "res://docs/WEBSITE_API.md"
const CASES = "res://tools/api_key_file_cases.json"
const PRESET = "res://export_presets.cfg"
const GITIGNORE = "res://.gitignore"
const SOURCE = "res://scripts/web_api.gd"
const TMP_DIR = "user://web_api_check"
const MARKER_KEY = "KEYMARKER-5c1e9d27"
const MARKER_TOKEN = "TOKENMARKER-8b40f3a6"  # secrets-check: ignore (a made-up marker, not a key)
const GOOD_URL = "https://example.org/fb3d/api/v1/"
const MIN_DOC_CODES = 20

var problems = []
var checked = 0


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(TMP_DIR)
	_check_result_names()
	_check_code_table()
	_check_answers()
	_check_base_url()
	_check_path_and_header_text()
	_check_headers()
	_check_dev_api()
	_check_key_file_cases()
	_check_damaged_key_files()
	_check_resolve_config()
	_check_source_rules()
	await _check_calls()
	_finish()


func _check_result_names() -> void:
	var want = [
		"OK",
		"OFFLINE",
		"TIMEOUT",
		"UNAUTHORIZED",
		"KEY_REJECTED",
		"UPDATE_REQUIRED",
		"SERVER_ERROR"
	]
	for i in range(want.size()):
		_expect(WebApi.type_name(i) == want[i], "result type %d is '%s'" % [i, WebApi.type_name(i)])
		_expect(
			WebApi.ResultType.keys()[i] == want[i], "the enum has %s at place %d" % [want[i], i]
		)
	_expect(WebApi.type_name(99) == "UNKNOWN", "an unknown result type has no name")


# Every row of the error table in docs/WEBSITE_API.md: | 401 | `key_missing` | meaning | KEY_REJECTED |
func _check_code_table() -> void:
	var f = FileAccess.open(DOC, FileAccess.READ)
	if f == null:
		_fail("cannot read " + DOC)
		return
	var text = f.get_as_text()
	f.close()
	var rows = 0
	for line in text.split("\n"):
		if not line.begins_with("| 4") and not line.begins_with("| 5"):
			continue
		var cells = line.split("|")
		if cells.size() < 6:
			continue
		var status = cells[1].strip_edges()
		var code = cells[2].strip_edges().replace("`", "")
		var type_text = cells[cells.size() - 2].strip_edges()
		if not status.is_valid_int():
			continue
		rows += 1
		var want = type_text
		var conflict = false
		if want == "OK-with-conflict":
			want = "OK"
			conflict = true
		var body = (
			JSON
			. stringify({"error": {"code": code, "message": "x", "retry_after": null}})
			. to_utf8_buffer()
		)
		var got = WebApi.interpret(
			HTTPRequest.RESULT_SUCCESS, int(status), PackedStringArray(), body
		)
		_expect(
			WebApi.type_name(got["type"]) == want,
			(
				"code %s (%s): the doc says %s, the game says %s"
				% [code, status, want, WebApi.type_name(got["type"])]
			)
		)
		_expect(got["code"] == code, "code %s is kept in the result" % code)
		_expect(
			bool(got["conflict"]) == conflict, "code %s: conflict flag is %s" % [code, conflict]
		)
		_expect(WebApi.CODE_TYPES.has(code), "code %s of the doc is missing from CODE_TYPES" % code)
	_expect(rows >= MIN_DOC_CODES, "only %d error rows were read from the doc" % rows)
	for code in WebApi.CODE_TYPES.keys():
		_expect(
			text.contains("`%s`" % code), "CODE_TYPES has '%s', which the doc does not list" % code
		)


func _check_answers() -> void:
	var ok = WebApi.interpret(
		0, 200, PackedStringArray(), _json({"status": "ok", "update": "none"})
	)
	_expect(
		ok["type"] == WebApi.ResultType.OK and ok["data"].get("status") == "ok",
		"200 with an object"
	)
	var none = WebApi.interpret(0, 204, PackedStringArray(), PackedByteArray())
	_expect(none["type"] == WebApi.ResultType.OK and none["data"].is_empty(), "204 with no body")
	var empty200 = WebApi.interpret(0, 200, PackedStringArray(), PackedByteArray())
	_expect(empty200["type"] == WebApi.ResultType.OK, "200 with no body is OK with no data")
	for text in ["{not json", "[1,2]", '"text"', "123", "null"]:
		var bad = WebApi.interpret(0, 200, PackedStringArray(), text.to_utf8_buffer())
		_expect(
			bad["type"] == WebApi.ResultType.SERVER_ERROR and bad["reason"] == "bad_json",
			"200 with '%s' is SERVER_ERROR (bad_json)" % text
		)
	# an error answer that is not the error shape
	for text in ["", "<html>502</html>", "[]", "{}", '{"error": 5}', '{"error": {"code": 7}}']:
		var odd = WebApi.interpret(0, 502, PackedStringArray(), text.to_utf8_buffer())
		_expect(
			odd["type"] == WebApi.ResultType.SERVER_ERROR, "502 with '%s' is SERVER_ERROR" % text
		)
		_expect(odd["code"] == "", "502 with '%s' has no code" % text)
	var unknown = WebApi.interpret(0, 403, PackedStringArray(), _error("something_new", null))
	_expect(unknown["type"] == WebApi.ResultType.SERVER_ERROR, "a code the game does not know")
	_expect(unknown["code"] == "something_new", "an unknown code is kept as it is")
	var loud = WebApi.interpret(0, 403, PackedStringArray(), _error("Bad Code!\n", null))
	_expect(loud["code"] == "", "a code with other characters is dropped")
	var long_code = WebApi.interpret(0, 403, PackedStringArray(), _error("a".repeat(65), null))
	_expect(long_code["code"] == "", "a code over 64 characters is dropped")
	_expect(
		(
			WebApi.interpret(0, 426, PackedStringArray(), PackedByteArray())["type"]
			== WebApi.ResultType.UPDATE_REQUIRED
		),
		"426 with no body is UPDATE_REQUIRED"
	)
	_expect(
		(
			WebApi.interpret(0, 503, PackedStringArray(), PackedByteArray())["type"]
			== WebApi.ResultType.OFFLINE
		),
		"503 with no body is OFFLINE"
	)
	for status in [301, 302, 401, 403, 404, 418, 500, 502, 504]:
		var by_status = WebApi.interpret(0, status, PackedStringArray(), PackedByteArray())
		_expect(
			by_status["type"] == WebApi.ResultType.SERVER_ERROR,
			"%d with no body is SERVER_ERROR (the game does not guess)" % status
		)
	# nothing came back
	var timed_out = WebApi.interpret(
		HTTPRequest.RESULT_TIMEOUT, 0, PackedStringArray(), PackedByteArray()
	)
	_expect(timed_out["type"] == WebApi.ResultType.TIMEOUT, "a timeout is TIMEOUT")
	for r in [
		HTTPRequest.RESULT_CANT_CONNECT,
		HTTPRequest.RESULT_CANT_RESOLVE,
		HTTPRequest.RESULT_CONNECTION_ERROR,
		HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR,
		HTTPRequest.RESULT_NO_RESPONSE,
	]:
		var lost = WebApi.interpret(r, 0, PackedStringArray(), PackedByteArray())
		_expect(lost["type"] == WebApi.ResultType.OFFLINE, "http result %d is OFFLINE" % r)
	for r in [
		HTTPRequest.RESULT_REDIRECT_LIMIT_REACHED,
		HTTPRequest.RESULT_BODY_SIZE_LIMIT_EXCEEDED,
		HTTPRequest.RESULT_REQUEST_FAILED,
		HTTPRequest.RESULT_CHUNKED_BODY_SIZE_MISMATCH,
	]:
		var failed = WebApi.interpret(r, 200, PackedStringArray(), _json({"a": 1}))
		_expect(
			failed["type"] == WebApi.ResultType.SERVER_ERROR,
			"http result %d is SERVER_ERROR even with a status 200" % r
		)
	# a body over the limit is never parsed
	var huge = PackedByteArray()
	huge.resize(WebApi.MAX_RESPONSE_BYTES + 1)
	var big = WebApi.interpret(0, 200, PackedStringArray(), huge)
	_expect(
		big["type"] == WebApi.ResultType.SERVER_ERROR, "a 200 over the size limit is SERVER_ERROR"
	)
	# retry_after
	var throttled = WebApi.interpret(0, 429, PackedStringArray(), _error("throttled", 30))
	_expect(
		(
			throttled["type"] == WebApi.ResultType.SERVER_ERROR
			and is_equal_approx(throttled["retry_after"], 30.0)
		),
		"429: retry_after from the body"
	)
	var from_header = WebApi.interpret(
		0,
		503,
		PackedStringArray(["Content-Type: application/json", "retry-after:  45 "]),
		_error("maintenance", null)
	)
	_expect(
		(
			from_header["type"] == WebApi.ResultType.OFFLINE
			and is_equal_approx(from_header["retry_after"], 45.0)
		),
		"503: retry_after from the header, whatever its case"
	)
	_expect(
		is_equal_approx(
			(
				WebApi
				. interpret(0, 429, PackedStringArray(), _error("throttled", 99999))["retry_after"]
			),
			WebApi.MAX_RETRY_AFTER
		),
		"retry_after is capped"
	)
	_expect(
		(
			WebApi.interpret(0, 429, PackedStringArray(), _error("throttled", -5))["retry_after"]
			== 0.0
		),
		"a negative retry_after is 0"
	)
	_expect(
		(
			(
				WebApi
				. interpret(
					0, 429, PackedStringArray(["Retry-After: soon"]), _error("throttled", null)
				)["retry_after"]
			)
			== 0.0
		),
		"a retry_after that is no number is 0"
	)
	_expect(
		(
			WebApi.interpret(0, 429, PackedStringArray(), _error("throttled", "5"))["retry_after"]
			== 0.0
		),
		"a retry_after of the wrong type is 0"
	)
	# the 409 of the saves keeps the whole answer for the conflict dialog
	var conflict = WebApi.interpret(
		0,
		409,
		PackedStringArray(),
		_json({"error": {"code": "save_conflict", "conflict": {"revision": 12}}})
	)
	_expect(
		conflict["type"] == WebApi.ResultType.OK and conflict["conflict"] == true,
		"409 save_conflict is OK with the conflict flag"
	)
	_expect(
		conflict["data"]["error"]["conflict"]["revision"] == 12,
		"the conflict answer keeps its data"
	)
	# a result from outside never has a missing key
	var failed_any = WebApi.interpret(0, 500, PackedStringArray(), PackedByteArray())
	for key in ["type", "status", "code", "reason", "retry_after", "conflict", "data"]:
		_expect(ok.has(key), "a result always has '%s'" % key)
		_expect(failed_any.has(key), "a failed result always has '%s'" % key)


func _check_base_url() -> void:
	_expect(WebApi.validate_base_url(GOOD_URL, false) == GOOD_URL, "a good https address")
	_expect(
		WebApi.validate_base_url("https://example.org/fb3d/api/v1", false) == GOOD_URL,
		"the closing slash is added"
	)
	_expect(
		(
			WebApi.validate_base_url("  https://example.org:8443/v1/ ", false)
			== "https://example.org:8443/v1/"
		),
		"spaces around it and a port are fine"
	)
	_expect(
		WebApi.validate_base_url("https://Example.ORG/v1/", false) != "",
		"capital letters in the host"
	)
	var refused = {
		"empty": "",
		"plain http": "http://example.org/v1/",
		"http, other host, dev": "http://example.org/v1/",
		"no scheme": "example.org/v1/",
		"ftp": "ftp://example.org/v1/",
		"user name": "https://user@example.org/v1/",
		"password": "https://user:pw@example.org/v1/",
		"query": "https://example.org/v1/?a=1",
		"fragment": "https://example.org/v1/#a",
		"space inside": "https://exa mple.org/v1/",
		"newline": "https://example.org/v1/\nX-Evil: 1",
		"backslash": "https://example.org\\v1/",
		"no host": "https:///v1/",
		"dotted start": "https://.example.org/v1/",
		"double dot": "https://exa..mple.org/v1/",
		"underscore host": "https://exa_mple.org/v1/",
		"bad port": "https://example.org:99999/v1/",
		"port that is no number": "https://example.org:abc/v1/",
		"template value": "https://fb3d.invalid/fb3d/api/v1/",
		"template word": "https://replace-me.example.org/v1/",
		"non-ASCII": "https://exačmple.org/v1/",
		"too long": "https://example.org/" + "a".repeat(WebApi.MAX_URL_LENGTH),
		"http on a look-alike host": "http://127.0.0.1.example.org/v1/",
	}
	for name in refused.keys():
		_expect(
			WebApi.validate_base_url(str(refused[name]), false).is_empty(),
			"refused: %s (exported game)" % name
		)
		_expect(
			WebApi.validate_base_url(str(refused[name]), true).is_empty(),
			"refused: %s (editor run)" % name
		)
	_expect(
		(
			WebApi.validate_base_url("http://127.0.0.1:8765/fb3d/api/v1/", true)
			== "http://127.0.0.1:8765/fb3d/api/v1/"
		),
		"http to this computer is allowed in an editor run"
	)
	_expect(
		WebApi.validate_base_url("http://localhost:8765/v1/", true) == "http://localhost:8765/v1/",
		"http to localhost is allowed in an editor run"
	)
	_expect(
		WebApi.validate_base_url("http://127.0.0.1:8765/v1/", false).is_empty(),
		"http to this computer is NOT allowed in an exported game"
	)


func _check_path_and_header_text() -> void:
	for ok in [
		"ping", "releases/current", "auth/login", "saves/versions/12", "me", "saves/current"
	]:
		_expect(WebApi.is_valid_path(ok), "path '%s' is valid" % ok)
	var bad = [
		"",
		"/ping",
		"ping/",
		"a//b",
		"../me",
		"a/../b",
		"a/./b",
		"https://evil.example/x",
		"ping?x=1",
		"ping#x",
		"Ping",
		"a b",
		"ping\n",
		"a%2Fb",
		"a.b",
		"a".repeat(WebApi.MAX_PATH_LENGTH + 1),
		"č",
	]
	for p in bad:
		_expect(
			not WebApi.is_valid_path(p), "path '%s' is refused" % p.replace("\n", "\\n").left(20)
		)
	_expect(WebApi.is_header_safe("abc-DEF_123", 20), "plain header text")
	for p in ["", "a b", "a\nb", "a\rb", "a\tb", "ač", "a\u007f", "x".repeat(21)]:
		_expect(not WebApi.is_header_safe(p, 20), "header text '%s' is refused" % p.json_escape())
	_expect(WebApi.is_valid_key("fb3dk_" + "A".repeat(43)), "a key of the real shape is usable")
	_expect(not WebApi.is_valid_key("fake-key-replace-me-0000"), "the template key is not usable")
	_expect(
		not WebApi.is_valid_key("a".repeat(WebApi.MAX_KEY_LENGTH + 1)),
		"a too long key is not usable"
	)
	_expect(not WebApi.is_valid_key("key with space"), "a key with a space is not usable")


func _check_headers() -> void:
	var plain = WebApi.build_headers("0.3.0", "a1b2c3d", MARKER_KEY, "", false)
	_expect(plain.has("X-FB3D-Key: " + MARKER_KEY), "the key header")
	_expect(plain.has("X-FB3D-Version: 0.3.0"), "the version header")
	_expect(plain.has("X-FB3D-Build: a1b2c3d"), "the build header")
	_expect(plain.has("Accept: application/json"), "the accept header")
	for line in plain:
		_expect(
			not line.begins_with("Authorization") and not line.begins_with("Content-Type"),
			"no token and no body: no '%s' header" % line.get_slice(":", 0)
		)
	var full = WebApi.build_headers("0.3.0", "a1b2c3d+", MARKER_KEY, MARKER_TOKEN, true)
	_expect(full.has("Authorization: Bearer " + MARKER_TOKEN), "the token goes as a bearer token")
	_expect(full.has("Content-Type: application/json"), "a body is sent as JSON")
	_expect(full.has("X-FB3D-Build: a1b2c3d+"), "a dirty build is marked with a plus")
	# the build id comes from build_info.gd
	var info = BuildInfo.parse("")
	_expect(BuildInfo.header_text(info) == "dev", "no build file: the build id is 'dev'")
	var dirty = info.duplicate()
	dirty["short"] = "a1b2c3d"
	dirty["dirty"] = true
	_expect(BuildInfo.header_text(dirty) == "a1b2c3d+", "a dirty build id ends with +")
	dirty["dirty"] = false
	_expect(BuildInfo.header_text(dirty) == "a1b2c3d", "a clean build id is the short hash")


func _check_dev_api() -> void:
	var args = PackedStringArray(["--dev-coins=5", "--dev-api=http://127.0.0.1:9000/fb3d/api/v1"])
	var in_editor = WebApi.parse_dev_api(args, true)
	_expect(in_editor["url"] == "http://127.0.0.1:9000/fb3d/api/v1/", "--dev-api in an editor run")
	_expect(in_editor["problems"].is_empty(), "--dev-api: no problem for a good value")
	var exported = WebApi.parse_dev_api(args, false)
	_expect(
		exported["url"] == "" and exported["problems"].is_empty(),
		"--dev-api is ignored in an exported game"
	)
	var wrong = WebApi.parse_dev_api(PackedStringArray(["--dev-api=http://example.org/"]), true)
	_expect(
		wrong["url"] == "" and wrong["problems"].size() == 1,
		"--dev-api with another host over http is left out"
	)
	_expect(
		not str(wrong["problems"]).contains("example.org"),
		"the problem text does not repeat the value"
	)
	var last = WebApi.parse_dev_api(
		PackedStringArray(["--dev-api=https://a.example.org/", "--dev-api=https://b.example.org/"]),
		true
	)
	_expect(last["url"] == "https://b.example.org/", "the last --dev-api wins")
	_expect(WebApi.parse_dev_api(PackedStringArray(), true)["url"] == "", "no argument, no address")


func _check_key_file_cases() -> void:
	var f = FileAccess.open(CASES, FileAccess.READ)
	if f == null:
		_fail("cannot read " + CASES)
		return
	var json = JSON.new()
	if json.parse(f.get_as_text()) != OK:
		_fail("cannot parse " + CASES)
		return
	f.close()
	var cases = json.data["cases"]
	_expect(cases.size() >= 3, "the key file cases are there")
	for c in cases:
		var bytes = _hex(str(c["file_hex"]))
		var got = ApiKeyFile.decode(bytes)
		_expect(
			got.get("base_url") == c["base_url"] and got.get("key") == c["key"],
			"key file case '%s': Python's bytes read back by the game" % c["name"]
		)
		var path = TMP_DIR + "/case.bin"
		_write_bytes(path, bytes)
		var loaded = ApiKeyFile.load_file(path)
		_expect(
			loaded["source"] == ApiKeyFile.SOURCE_FILE and loaded["key"] == c["key"],
			"key file case '%s': load_file reads it" % c["name"]
		)


func _check_damaged_key_files() -> void:
	var f = FileAccess.open(CASES, FileAccess.READ)
	var json = JSON.new()
	if f == null or json.parse(f.get_as_text()) != OK:
		return
	f.close()
	var good = _hex(str(json.data["cases"][1]["file_hex"]))
	_expect(not ApiKeyFile.decode(good).is_empty(), "the file to damage is good")
	for i in [0, 3, 4, 5, 12, 21, 40, good.size() - 9, good.size() - 1]:
		var changed = good.duplicate()
		changed[i] = changed[i] ^ 1
		_expect(ApiKeyFile.decode(changed).is_empty(), "a changed byte %d is noticed" % i)
	_expect(ApiKeyFile.decode(good.slice(0, good.size() - 1)).is_empty(), "a cut file is noticed")
	_expect(ApiKeyFile.decode(good.slice(1)).is_empty(), "a file with a byte missing at the start")
	_expect(ApiKeyFile.decode(PackedByteArray()).is_empty(), "an empty file")
	_expect(ApiKeyFile.decode("FB3K".to_utf8_buffer()).is_empty(), "a file with only the magic")
	_expect(
		ApiKeyFile.decode("just some text that is not a key file".to_utf8_buffer()).is_empty(),
		"text"
	)
	var big = good.duplicate()
	big.resize(ApiKeyFile.MAX_FILE + 1)
	_expect(ApiKeyFile.decode(big).is_empty(), "an oversized file")
	var path = TMP_DIR + "/damaged.bin"
	var broken = good.duplicate()
	broken[30] = broken[30] ^ 255
	_write_bytes(path, broken)
	var loaded = ApiKeyFile.load_file(path)
	_expect(
		(
			loaded["source"] == ApiKeyFile.SOURCE_DAMAGED
			and loaded["key"] == ""
			and loaded["base_url"] == ""
		),
		"a damaged file gives no values at all"
	)
	_write_bytes(path, big)
	_expect(
		ApiKeyFile.load_file(path)["source"] == ApiKeyFile.SOURCE_DAMAGED,
		"an oversized file on disk"
	)
	var none = ApiKeyFile.load_file(TMP_DIR + "/missing.bin")
	_expect(
		none["source"] == ApiKeyFile.SOURCE_NONE and none["key"] == "",
		"no file: nothing, and no error"
	)
	var parts = ApiKeyFile.decode(_hex(str(json.data["cases"][0]["file_hex"])))
	_expect(parts.size() == 2, "a good file gives exactly the base_url and the key")


func _check_resolve_config() -> void:
	var key = "fb3dk_" + "B".repeat(43)
	var build_path = TMP_DIR + "/build_key.bin"
	_write_bytes(build_path, _make_file(GOOD_URL, key))
	var secrets_path = TMP_DIR + "/secrets.cfg"
	_write_text(
		secrets_path,
		'[api]\nbase_url="https://secrets.example.org/v1/"\nkey="%s-secrets"\n' % MARKER_KEY
	)
	var no_args = PackedStringArray()
	# an exported game: the build file only
	var exported = WebApi.resolve_config(
		PackedStringArray(["--dev-api=https://dev.example.org/"]),
		{
			"allowed": false,
			"build_path": build_path,
			"secrets": {"allowed": false, "path": secrets_path}
		}
	)
	_expect(
		exported["base_url"] == GOOD_URL and exported["base_source"] == WebApi.SOURCE_BUILD,
		"exported game: the address is the build's"
	)
	_expect(
		exported["key"] == key and exported["key_source"] == WebApi.SOURCE_BUILD,
		"exported game: the key is the build's, not secrets.local.cfg"
	)
	_expect(
		exported["problems"].is_empty(), "exported game: --dev-api is ignored without a problem"
	)
	# an editor run: --dev-api, then secrets, then the build file
	var editor_src = {
		"allowed": true,
		"build_path": build_path,
		"secrets": {"allowed": true, "path": secrets_path, "env": {}}
	}
	var dev_args = PackedStringArray(["--dev-api=http://127.0.0.1:7000/v1/"])
	var from_arg = WebApi.resolve_config(dev_args, editor_src)
	_expect(
		(
			from_arg["base_url"] == "http://127.0.0.1:7000/v1/"
			and from_arg["base_source"] == WebApi.SOURCE_DEV_ARG
		),
		"editor run: --dev-api beats secrets and the build"
	)
	_expect(
		(
			from_arg["key"] == MARKER_KEY + "-secrets"
			and from_arg["key_source"] == WebApi.SOURCE_SECRETS
		),
		"editor run: the key of secrets.local.cfg beats the build's"
	)
	var from_secrets = WebApi.resolve_config(no_args, editor_src)
	_expect(
		from_secrets["base_source"] == WebApi.SOURCE_SECRETS,
		"editor run: the address of secrets beats the build's"
	)
	var only_build = WebApi.resolve_config(
		no_args,
		{
			"allowed": true,
			"build_path": build_path,
			"secrets": {"allowed": true, "path": TMP_DIR + "/none.cfg", "env": {}}
		}
	)
	_expect(
		(
			only_build["base_source"] == WebApi.SOURCE_BUILD
			and only_build["key_source"] == WebApi.SOURCE_BUILD
		),
		"editor run with no secrets: the build's values"
	)
	# nothing at all: the normal state of a fresh clone
	var nothing = WebApi.resolve_config(
		no_args,
		{
			"allowed": true,
			"build_path": TMP_DIR + "/none.bin",
			"secrets": {"allowed": true, "path": TMP_DIR + "/none.cfg", "env": {}}
		}
	)
	_expect(
		nothing["base_url"] == "" and nothing["key"] == "" and nothing["problems"].is_empty(),
		"a fresh clone: nothing set, no problem"
	)
	# a template value is not used
	var template_path = TMP_DIR + "/template.cfg"
	_write_text(
		template_path,
		'[api]\nbase_url="https://fb3d.invalid/fb3d/api/v1/"\nkey="fake-key-replace-me-0000"\n'
	)
	var templ = WebApi.resolve_config(
		no_args,
		{
			"allowed": true,
			"build_path": TMP_DIR + "/none.bin",
			"secrets": {"allowed": true, "path": template_path, "env": {}}
		}
	)
	_expect(
		templ["base_url"] == "" and templ["key"] == "",
		"the unedited template sends nothing anywhere"
	)
	# a bad value in a higher source is skipped, the next one is used, and the problem names the source only
	var bad_path = TMP_DIR + "/bad.cfg"
	_write_text(
		bad_path, '[api]\nbase_url="http://example.org/v1/"\nkey="has a space %s"\n' % MARKER_KEY
	)
	var skipped = WebApi.resolve_config(
		no_args,
		{
			"allowed": true,
			"build_path": build_path,
			"secrets": {"allowed": true, "path": bad_path, "env": {}}
		}
	)
	_expect(
		skipped["base_url"] == GOOD_URL and skipped["key"] == key,
		"a bad value is skipped and the build's value is used"
	)
	_expect(skipped["problems"].size() == 2, "two problems named: %s" % str(skipped["problems"]))
	_expect(
		(
			not str(skipped["problems"]).contains(MARKER_KEY)
			and not str(skipped["problems"]).contains("example.org")
		),
		"the problems do not hold a value"
	)
	# a damaged build file is never half used
	var damaged_path = TMP_DIR + "/build_damaged.bin"
	var damaged = _make_file(GOOD_URL, key)
	damaged[28] = damaged[28] ^ 1
	_write_bytes(damaged_path, damaged)
	var from_damaged = WebApi.resolve_config(
		no_args, {"allowed": false, "build_path": damaged_path, "secrets": {"allowed": false}}
	)
	_expect(
		from_damaged["base_url"] == "" and from_damaged["key"] == "",
		"a damaged build file gives nothing"
	)
	_expect(from_damaged["problems"].size() == 1, "a damaged build file is named as a problem")
	# a build file with plain http is not used by an exported game, and a template key in the file is not used
	var http_build = TMP_DIR + "/build_http.bin"
	_write_bytes(http_build, _make_file("http://127.0.0.1:7000/v1/", key))
	var refused = WebApi.resolve_config(
		no_args, {"allowed": false, "build_path": http_build, "secrets": {"allowed": false}}
	)
	_expect(
		refused["base_url"] == "",
		"an exported game never takes an http address, not even from its build file"
	)
	var fake_build = TMP_DIR + "/build_fake.bin"
	_write_bytes(fake_build, _make_file(GOOD_URL, "fake-key-replace-me-0000"))
	_expect(
		(
			(
				WebApi
				. resolve_config(
					no_args,
					{"allowed": false, "build_path": fake_build, "secrets": {"allowed": false}}
				)["key"]
			)
			== ""
		),
		"a template key in the build file is not used"
	)


# The source of web_api.gd and api_key_file.gd: no print can show a secret, and the build and ignore rules are in place.
func _check_source_rules() -> void:
	for path in [SOURCE, "res://scripts/api_key_file.gd"]:
		var text = _read(path)
		_expect(not text.is_empty(), "cannot read " + path)
		for line in text.split("\n"):
			var code = line.get_slice("#", 0)
			if not (
				code.contains("print(")
				or code.contains("push_error(")
				or code.contains("push_warning(")
				or code.contains("printerr(")
				or code.contains("print_rich(")
				or code.contains("printraw(")
			):
				continue
			for word in [
				"api_key", "token", "password", "headers", "body", "text", "plain", "bytes", "data"
			]:
				_expect(
					not code.to_lower().contains(word),
					"%s: a print line mentions '%s': %s" % [path, word, line.strip_edges()]
				)
		_expect(not text.contains("OS.shell_open"), "%s opens no link" % path)
	var source = _read(SOURCE)
	_expect(source.contains("max_redirects = 0"), "redirects are switched off")
	_expect(
		source.contains("use_threads = false") and not source.contains("use_threads = true"),
		"the call is not threaded (a threaded HTTPRequest cannot be cancelled while the server is silent)"
	)
	_expect(source.contains("body_size_limit"), "the response size is limited")
	_expect(source.contains("timeout = TIMEOUT_SECONDS"), "the call has a timeout")
	_expect(
		not source.contains("tls_options") and not source.contains("set_tls_options"),
		"certificates are checked as usual"
	)
	_expect(
		WebApi.TIMEOUT_SECONDS > 0.0 and WebApi.TIMEOUT_SECONDS <= 10.0,
		"the timeout is a few seconds"
	)
	# nothing in the game outside web_api.gd talks to the website
	var users = []
	for path in _scripts():
		if path == SOURCE:
			continue
		var other = _read(path)
		if (
			other.contains("HTTPRequest.new")
			or other.contains("HTTPClient.new")
			or other.contains("X-FB3D-Key")
		):
			users.append(path)
	_expect(users.is_empty(), "these scripts talk to a server themselves: %s" % str(users))
	# the key file is never tracked and always exported
	var ignore = _read(GITIGNORE)
	var lines = []
	for line in ignore.split("\n"):
		lines.append(line.strip_edges())
	_expect(lines.has("api_key.*"), ".gitignore lists api_key.*")
	var preset = _read(PRESET)
	var in_filter = false
	for line in preset.split("\n"):
		if line.begins_with("include_filter="):
			in_filter = line.contains("api_key.bin") and line.contains("build_info.json")
	_expect(in_filter, "export_presets.cfg include_filter has api_key.bin (and build_info.json)")
	_expect(ApiKeyFile.FILE == "res://api_key.bin", "the game reads api_key.bin")


func _check_calls() -> void:
	var api = WebApi.new()
	api.log_calls = false
	api.allow_dev = true
	root.add_child(api)
	# a script run by --script gets its nodes into the tree only after the first frame
	await process_frame
	await process_frame
	# not configured: nothing is sent
	api.configure(
		{
			"allowed": true,
			"build_path": TMP_DIR + "/none.bin",
			"secrets": {"allowed": true, "path": TMP_DIR + "/none.cfg", "env": {}}
		}
	)
	_expect(not api.is_configured(), "a fresh clone is not configured")
	var r = await api.request_api("GET", "ping")
	_expect(
		r["type"] == WebApi.ResultType.OFFLINE and r["reason"] == "not_configured",
		"not configured: OFFLINE"
	)
	_expect(api.requests_sent == 0, "not configured: nothing was sent")
	_expect(
		api.status_line().contains("not set") and api.status_line().contains("on"),
		"status line: %s" % api.status_line()
	)
	# configured, but each bad call is refused before it is sent
	_expect(
		api.use_config("http://127.0.0.1:1/fb3d/api/v1/", MARKER_KEY),
		"a dev address and a key are accepted"
	)
	_expect(
		not api.status_line().contains(MARKER_KEY) and not api.status_line().contains("127.0.0.1"),
		"the status line holds no value"
	)
	var refusals = [
		["DELETE", "ping", null, "", "bad_method"],
		["get", "ping", null, "", "bad_method"],
		["GET", "../ping", null, "", "bad_path"],
		["GET", "/ping", null, "", "bad_path"],
		["GET", "https://evil.example/", null, "", "bad_path"],
		["GET", "ping", {"a": 1}, "", "get_with_body"],
		["POST", "auth/login", "not a dictionary", "", "bad_body"],
		[
			"POST",
			"auth/login",
			{"x": "y".repeat(WebApi.MAX_REQUEST_BYTES)},
			"",
			"request_too_large"
		],
		["GET", "me", null, "bad token\r\nX-Evil: 1", "bad_token"],
		["GET", "me", null, "t".repeat(WebApi.MAX_TOKEN_LENGTH + 1), "bad_token"],
	]
	for c in refusals:
		var got = await api.request_api(str(c[0]), str(c[1]), c[2], str(c[3]))
		_expect(
			got["type"] == WebApi.ResultType.SERVER_ERROR and got["reason"] == c[4],
			(
				"refused before sending: %s %s (%s, got %s)"
				% [c[0], str(c[1]).left(20), c[4], got["reason"]]
			)
		)
	_expect(api.requests_sent == 0, "no refused call was sent")
	# switched off: nothing at all
	api.enabled = false
	var off = await api.request_api("GET", "ping")
	_expect(
		off["type"] == WebApi.ResultType.OFFLINE and off["reason"] == "disabled",
		"ONLINE FEATURES off: OFFLINE"
	)
	_expect(api.requests_sent == 0, "ONLINE FEATURES off: nothing was sent")
	api.enabled = true
	# a key or an address that is not allowed is never used
	_expect(
		not api.use_config("http://example.org/v1/", MARKER_KEY),
		"plain http to a site is not accepted"
	)
	_expect(not api.use_config(GOOD_URL, "bad key"), "a key with a space is not accepted")
	var rejected = await api.request_api("GET", "ping")
	_expect(
		rejected["reason"] == "not_configured" and api.requests_sent == 0,
		"and then nothing is sent"
	)
	# the one real call: a port nobody listens on is OFFLINE, and the frames keep running meanwhile
	api.use_config("http://127.0.0.1:1/fb3d/api/v1/", MARKER_KEY)
	var frame_before = Engine.get_process_frames()
	var dead = await api.request_api("GET", "ping", null, MARKER_TOKEN)
	_expect(
		dead["type"] == WebApi.ResultType.OFFLINE,
		(
			"a dead port is OFFLINE (got %s, reason %s)"
			% [WebApi.type_name(dead["type"]), dead["reason"]]
		)
	)
	_expect(api.requests_sent == 1, "the call went out once and was not repeated")
	_expect(Engine.get_process_frames() > frame_before, "the call did not finish inside one frame")
	_expect(
		not str(dead).contains(MARKER_KEY) and not str(dead).contains(MARKER_TOKEN),
		"the result holds no key or token"
	)
	await process_frame
	_expect(api.get_child_count() == 0, "the finished call left nothing behind")
	api.queue_free()


func _scripts() -> Array:
	var out = []
	var dir = DirAccess.open("res://scripts")
	if dir == null:
		return out
	for name in dir.get_files():
		if name.ends_with(".gd"):
			out.append("res://scripts/" + name)
	return out


func _read(path: String) -> String:
	var f = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var text = f.get_as_text()
	f.close()
	return text


# What tools/api_key_file.py makes, written the same way (the nonce is fixed), for the resolve tests.
func _make_file(url: String, key: String) -> PackedByteArray:
	var salt = ApiKeyFile.SALT.to_utf8_buffer()
	var nonce = PackedByteArray()
	for i in range(ApiKeyFile.NONCE_LENGTH):
		nonce.append(i + 1)
	var plain = JSON.stringify({"base_url": url, "key": key}, "", false).to_utf8_buffer()
	var cipher = PackedByteArray()
	var stream = PackedByteArray()
	var block = 0
	for i in range(plain.size()):
		if i >= stream.size():
			var input = salt + nonce
			input.append((block >> 24) & 255)
			input.append((block >> 16) & 255)
			input.append((block >> 8) & 255)
			input.append(block & 255)
			stream.append_array(_sha256(input))
			block += 1
		cipher.append(plain[i] ^ stream[i])
	var mac = _sha256(salt + nonce + plain).slice(0, ApiKeyFile.MAC_LENGTH)
	return "FB3K".to_utf8_buffer() + PackedByteArray([1]) + nonce + cipher + mac


func _sha256(data: PackedByteArray) -> PackedByteArray:
	var context = HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(data)
	return context.finish()


func _hex(text: String) -> PackedByteArray:
	return text.hex_decode()


func _json(data: Dictionary) -> PackedByteArray:
	return JSON.stringify(data).to_utf8_buffer()


func _error(code: String, retry_after) -> PackedByteArray:
	return _json({"error": {"code": code, "message": "x", "retry_after": retry_after}})


func _write_bytes(path: String, bytes: PackedByteArray) -> void:
	var f = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		_fail("cannot write " + path)
		return
	f.store_buffer(bytes)
	f.close()


func _write_text(path: String, text: String) -> void:
	var f = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		_fail("cannot write " + path)
		return
	f.store_string(text)
	f.close()


func _expect(condition: bool, text: String) -> void:
	checked += 1
	if not condition:
		problems.append(text)


func _fail(text: String) -> void:
	problems.append(text)


func _finish() -> void:
	if problems.is_empty():
		print(
			(
				"web_api_check: %d checks: the error table of the doc matches the game, answers of every kind end in a result type, addresses, paths and headers are strict, the key file reads what Python writes and a damaged one is nothing, a call that is not allowed sends nothing, a dead port is OFFLINE"
				% checked
			)
		)
		quit(0)
	else:
		for line in problems.slice(0, 20):
			printerr("web_api_check: " + line)
		quit(1)
