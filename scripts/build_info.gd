extends RefCounted
# Reads build_info.json (roadmap V2.2): which build this is. tools/make_build_info.py writes the file at build time,
# and the export preset includes it (V2.1). Rules:
#   - the file is optional: an editor run and a fresh clone have none, and then the version is `config/version`
#     and the commit is "dev" (`source` is "fallback"),
#   - a damaged file never crashes the game and is never half used: a missing key, a wrong type, a malformed hash,
#     an unknown channel, a bad time, an empty or oversized file all give the fallback (`source` is "damaged"),
#   - a file written for another version than `config/version` is a left-over from an older build and is not
#     believed either (`source` is "stale"), so a bumped version never shows an old hash,
#   - it only reads the file and prints nothing; the game prints `console_line()` once at start.
# The title screen shows `title_text()`: "v0.3.0 (a1b2c3d)", with a "+" after the hash for a dirty build.
# Check: `python tools/run_checks.py version`.

const VersionCompare = preload("res://scripts/version_compare.gd")
const FILE = "res://build_info.json"
const MAX_FILE = 4096
const CHANNELS = ["dev", "alpha", "release"]
const DEV_COMMIT = "dev"
const SOURCE_FILE = "file"
const SOURCE_FALLBACK = "fallback"
const SOURCE_DAMAGED = "damaged"
const SOURCE_STALE = "stale"
const COMMIT_PATTERN = "^[0-9a-f]{40}$"
const COMMIT_LENGTH = 40
const TIME_PATTERN = "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$"
const TIME_LENGTH = 20
const SHORT_LENGTH = 7


# The version written in project.godot, or "" when it is missing or not shaped like a version.
static func project_version() -> String:
	var stored = str(ProjectSettings.get_setting("application/config/version", ""))
	if VersionCompare.is_valid(stored):
		return stored
	return ""


# What a build without a (usable) file knows about itself.
static func fallback(source: String = SOURCE_FALLBACK) -> Dictionary:
	return {
		"version": project_version(),
		"commit": DEV_COMMIT,
		"short": DEV_COMMIT,
		"dirty": false,
		"built_utc": "",
		"channel": "dev",
		"source": source,
	}


# Always a complete Dictionary with the keys of fallback(), never an error.
static func load_info(path: String = FILE) -> Dictionary:
	if not FileAccess.file_exists(path):
		return fallback()
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return fallback(SOURCE_DAMAGED)
	if file.get_length() > MAX_FILE:
		return fallback(SOURCE_DAMAGED)
	var text = file.get_as_text()
	file.close()
	return parse(text)


# The text of a build_info.json turned into the Dictionary of load_info(); any problem gives a fallback.
static func parse(text: String) -> Dictionary:
	if text.length() > MAX_FILE:
		return fallback(SOURCE_DAMAGED)
	var json = JSON.new()
	if json.parse(text) != OK:
		return fallback(SOURCE_DAMAGED)
	var data = json.data
	if typeof(data) != TYPE_DICTIONARY:
		return fallback(SOURCE_DAMAGED)
	if not _is_valid(data):
		return fallback(SOURCE_DAMAGED)
	if str(data["version"]) != project_version():
		return fallback(SOURCE_STALE)
	return {
		"version": str(data["version"]),
		"commit": str(data["commit"]),
		"short": str(data["short"]),
		"dirty": data["dirty"],
		"built_utc": str(data["built_utc"]),
		"channel": str(data["channel"]),
		"source": SOURCE_FILE,
	}


# "v0.3.0 (a1b2c3d)", "v0.3.0 (a1b2c3d+)" for a dirty build, "v0.2.0 (dev)" without a file, "" without a version.
static func title_text(info: Dictionary) -> String:
	var version = str(info.get("version", ""))
	if version.is_empty():
		return ""
	return "v" + version + " (" + _hash_text(info) + ")"


# The first console line: "FB3D 0.3.0 (a1b2c3d)".
static func console_line(info: Dictionary) -> String:
	var version = str(info.get("version", ""))
	if version.is_empty():
		version = "unknown"
	return "FB3D " + version + " (" + _hash_text(info) + ")"


# The value of the X-FB3D-Build header (docs/WEBSITE_API.md): "a1b2c3d", "a1b2c3d+" for a dirty build, "dev" without a file.
static func header_text(info: Dictionary) -> String:
	return _hash_text(info)


static func _hash_text(info: Dictionary) -> String:
	var text = str(info.get("short", DEV_COMMIT))
	if text.is_empty():
		text = DEV_COMMIT
	if info.get("dirty", false) == true:
		text += "+"
	return text


# true when every key is there with the right type and shape.
static func _is_valid(data: Dictionary) -> bool:
	for key in ["version", "commit", "short", "built_utc", "channel"]:
		if not data.has(key) or typeof(data[key]) != TYPE_STRING:
			return false
	if not data.has("dirty") or typeof(data["dirty"]) != TYPE_BOOL:
		return false
	if not VersionCompare.is_valid(data["version"]):
		return false
	# the length is checked first, because `$` in a pattern also matches before a trailing line break
	if data["commit"].length() != COMMIT_LENGTH or not _matches(COMMIT_PATTERN, data["commit"]):
		return false
	if data["short"] != str(data["commit"]).substr(0, SHORT_LENGTH):
		return false
	if data["built_utc"].length() != TIME_LENGTH or not _matches(TIME_PATTERN, data["built_utc"]):
		return false
	return CHANNELS.has(data["channel"])


static func _matches(pattern: String, text: String) -> bool:
	var regex = RegEx.new()
	regex.compile(pattern)
	return regex.search(text) != null
