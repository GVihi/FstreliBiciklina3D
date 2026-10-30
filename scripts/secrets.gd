extends RefCounted
# Reads the game's secrets (roadmap V1.2): the website's API address and the game's API key, and whatever V3 and V4
# add. This repository is public, so a real value is never in it. A value comes from, in this order:
#   1. an environment variable named FB3D_<SECTION>_<KEY> in capitals (FB3D_API_KEY, FB3D_API_BASE_URL),
#   2. the untracked file `secrets.local.cfg` in the project folder (a copy of the tracked template
#      `secrets.example.cfg`, which holds fake values only; `secrets.local.*` is in .gitignore).
# Rules:
#   - nothing is required: neither source existing is the normal state of a fresh clone, and then every value is the
#     default (an empty string) and the game plays offline. A missing, empty or damaged file, a wrong type and a value
#     that is too long are all "not set" and never stop the game,
#   - a value that still looks like the template ("fake...", ".invalid" or "replace-me") counts as not set, so an
#     unedited copy of the template never sends a fake key anywhere,
#   - it reads anything only when the game runs from the Godot editor binary (`allowed()`, like dev_start.gd): an
#     exported game gets its values from the build (V4.1) and does not read this file or these variables,
#   - it never prints a value. `status_line()` says where each value came from and nothing else; use it, not the value,
#     in any log or message.
# Check: `python tools/run_checks.py secrets_loader`. The template: secrets.example.cfg. Rules for secrets: README.md.

const LOCAL_FILE = "res://secrets.local.cfg"
const ENV_PREFIX = "FB3D_"
const MAX_LEN = 512
const MAX_FILE = 65536
const SOURCE_NONE = "not set"
const SOURCE_ENV = "environment variable"
const SOURCE_FILE = "secrets.local.cfg"
const SOURCE_PLACEHOLDER = "template value (ignored)"

# Every value the game reads. Add the next one here and in secrets.example.cfg (the check compares the two).
const KNOWN = [
	{"section": "api", "key": "base_url"},
	{"section": "api", "key": "key"},
]


# true when the game runs from the Godot editor binary (the editor, or `godot --path .`), false in every exported game
static func allowed() -> bool:
	return OS.has_feature("editor")


# The environment variable of a value: ("api", "key") is "FB3D_API_KEY".
static func env_name(section: String, key: String) -> String:
	return ENV_PREFIX + section.to_upper() + "_" + key.to_upper()


# true when a value is still the template's fake one (or empty).
static func is_placeholder(value: String) -> bool:
	var v = value.strip_edges().to_lower()
	return (
		v.is_empty() or v.begins_with("fake") or v.contains(".invalid") or v.contains("replace-me")
	)


# The value, or `default` when it is not set. `src` is for the check only: "path" (the file), "env" (a Dictionary
# used instead of the real environment) and "allowed" (instead of `allowed()`).
static func get_value(section: String, key: String, default = "", src: Dictionary = {}) -> String:
	var found = lookup(section, key, src)
	if found["source"] == SOURCE_ENV or found["source"] == SOURCE_FILE:
		return found["value"]
	return str(default)


# true when a real value (not empty, not the template's) is set.
static func is_set(section: String, key: String, src: Dictionary = {}) -> bool:
	var found = lookup(section, key, src)
	return found["source"] == SOURCE_ENV or found["source"] == SOURCE_FILE


# {"value": the text, "source": one of the SOURCE_ constants}. The value is "" unless the source is the environment
# or the file. Never print "value".
static func lookup(section: String, key: String, src: Dictionary = {}) -> Dictionary:
	var out = {"value": "", "source": SOURCE_NONE}
	if not bool(src.get("allowed", allowed())):
		return out
	var saw_template = false
	var candidates = [
		[SOURCE_ENV, _env_value(section, key, src)],
		[SOURCE_FILE, _file_value(section, key, str(src.get("path", LOCAL_FILE)))],
	]
	for c in candidates:
		var value = str(c[1])
		if value.is_empty():
			continue
		if is_placeholder(value):
			saw_template = true
			continue
		return {"value": value, "source": c[0]}
	if saw_template:
		out["source"] = SOURCE_PLACEHOLDER
	return out


# One line for a log: where each known value came from, never the value. For example
# "secrets: api/base_url: not set; api/key: secrets.local.cfg".
static func status_line(src: Dictionary = {}) -> String:
	var parts = []
	for k in KNOWN:
		var found = lookup(str(k["section"]), str(k["key"]), src)
		parts.append("%s/%s: %s" % [k["section"], k["key"], found["source"]])
	return "secrets: " + "; ".join(parts)


static func _env_value(section: String, key: String, src: Dictionary) -> String:
	var name = env_name(section, key)
	var text = ""
	if src.has("env"):
		text = str(src["env"].get(name, ""))
	else:
		text = OS.get_environment(name)
	return _clean(text)


static func _file_value(section: String, key: String, path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var f = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	if f.get_length() > MAX_FILE:
		return ""
	var text = f.get_as_text()
	f.close()
	var table = parse_text(text)
	if not table.has(section) or not table[section].has(key):
		return ""
	return _clean(str(table[section][key]))


# Reads the text of a secrets file into {section: {key: value}}. The format is the small part of Godot's config
# format that the template uses: `[section]` lines, `key="text"` lines (with \" and \\ inside the text), and `;` or
# `#` comment lines. A line that is anything else (a value that is not in quotes, a number, a broken line) is skipped
# without a word. Godot's own ConfigFile is not used on purpose: on a damaged file it prints an error, and that error
# can name part of the broken line, which may be a key.
static func parse_text(text: String) -> Dictionary:
	var out = {}
	var section = ""
	if text.begins_with(char(0xFEFF)):
		text = text.substr(1)
	for raw in text.split("\n"):
		var line = raw.strip_edges()
		if line.is_empty() or line.begins_with(";") or line.begins_with("#"):
			continue
		if line.begins_with("[") and line.ends_with("]"):
			section = line.substr(1, line.length() - 2).strip_edges()
			continue
		var eq = line.find("=")
		if eq <= 0 or section.is_empty():
			continue
		var key = line.substr(0, eq).strip_edges()
		var value = line.substr(eq + 1).strip_edges()
		if value.length() < 2 or not value.begins_with('"') or not value.ends_with('"'):
			continue
		if not out.has(section):
			out[section] = {}
		out[section][key] = _unescape(value.substr(1, value.length() - 2))
	return out


static func _unescape(text: String) -> String:
	var out = ""
	var i = 0
	while i < text.length():
		var c = text[i]
		if c == "\\" and i + 1 < text.length() and (text[i + 1] == '"' or text[i + 1] == "\\"):
			out += text[i + 1]
			i += 2
		else:
			out += c
			i += 1
	return out


# Trims the value; one that is too long is treated as not set.
static func _clean(text: String) -> String:
	var t = text.strip_edges()
	if t.length() > MAX_LEN:
		return ""
	return t
