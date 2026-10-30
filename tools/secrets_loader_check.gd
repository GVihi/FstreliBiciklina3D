extends SceneTree
# Checks the secrets loader (roadmap V1.2): scripts/secrets.gd and the template secrets.example.cfg.
#   - with no file and no variable every value is the default (a fresh clone plays offline),
#   - the environment wins over the file, the file is read, and a value that is still the template's is ignored,
#   - a damaged, empty or wrong-typed file, a wrong type and a too long value are "not set" and never crash,
#   - nothing is read when `allowed` is false (an exported game),
#   - status_line() never holds a value,
#   - the template holds every value the loader knows, with fake values only, and secrets.local.* is git-ignored.
# Run from the project folder:
#   godot --headless --path . --script res://tools/secrets_loader_check.gd
# or: python tools/run_checks.py secrets_loader
# Exits with status 1 and prints the problems when a check fails.

const Secrets = preload("res://scripts/secrets.gd")
const TEMPLATE = "res://secrets.example.cfg"
const TMP_DIR = "user://secrets_loader_check"
const MARKER = "REALVALUE-9f3a71c2"

var problems = []


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(TMP_DIR)
	_check_fresh_clone()
	_check_sources()
	_check_file_format()
	_check_bad_files()
	_check_gate()
	_check_status_line()
	_check_real_environment()
	_check_template()
	_check_gitignore()
	_finish()


# Neither a file nor a variable: the normal state of a fresh clone.
func _check_fresh_clone() -> void:
	var src = {"path": TMP_DIR + "/missing.cfg", "env": {}, "allowed": true}
	for k in Secrets.KNOWN:
		var s = str(k["section"])
		var key = str(k["key"])
		if Secrets.get_value(s, key, "", src) != "":
			_fail("%s/%s: not empty with no file and no variable" % [s, key])
		if Secrets.get_value(s, key, "fallback", src) != "fallback":
			_fail("%s/%s: the default was not returned" % [s, key])
		if Secrets.is_set(s, key, src):
			_fail("%s/%s: is_set is true with nothing set" % [s, key])
		if Secrets.lookup(s, key, src)["source"] != Secrets.SOURCE_NONE:
			_fail("%s/%s: source is not 'not set'" % [s, key])


# The environment, the file, and which one wins.
func _check_sources() -> void:
	var good = TMP_DIR + "/good.cfg"
	_write(
		good, '[api]\nbase_url="https://api.test-site.org/fb3d/api/v1/"\nkey="%s-file"\n' % MARKER
	)
	var from_file = {"path": good, "env": {}, "allowed": true}
	if Secrets.get_value("api", "key", "", from_file) != MARKER + "-file":
		_fail("the value in the file was not read")
	if Secrets.lookup("api", "key", from_file)["source"] != Secrets.SOURCE_FILE:
		_fail("a value from the file is not reported as coming from the file")
	if (
		Secrets.get_value("api", "base_url", "", from_file)
		!= "https://api.test-site.org/fb3d/api/v1/"
	):
		_fail("the base_url in the file was not read")
	if Secrets.env_name("api", "key") != "FB3D_API_KEY":
		_fail("env_name(api, key) is '%s', expected FB3D_API_KEY" % Secrets.env_name("api", "key"))
	if Secrets.env_name("api", "base_url") != "FB3D_API_BASE_URL":
		_fail("env_name(api, base_url) is '%s'" % Secrets.env_name("api", "base_url"))
	var both = {"path": good, "env": {"FB3D_API_KEY": "  " + MARKER + "-env  "}, "allowed": true}
	if Secrets.get_value("api", "key", "", both) != MARKER + "-env":
		_fail("the environment variable does not win over the file, or it was not trimmed")
	if Secrets.lookup("api", "key", both)["source"] != Secrets.SOURCE_ENV:
		_fail("a value from the environment is not reported as such")
	if Secrets.get_value("api", "base_url", "", both) != "https://api.test-site.org/fb3d/api/v1/":
		_fail("a value missing in the environment did not fall back to the file")
	# a template value in the environment does not hide a real one in the file
	var fake_env = {
		"path": good, "env": {"FB3D_API_KEY": "fake-key-replace-me-0000"}, "allowed": true
	}
	if Secrets.get_value("api", "key", "", fake_env) != MARKER + "-file":
		_fail("a template value in the environment hid the real value in the file")
	# a template value alone is not a value
	var only_fake = {
		"path": TMP_DIR + "/missing.cfg",
		"env": {"FB3D_API_KEY": "fake-key-replace-me-0000"},
		"allowed": true
	}
	if Secrets.is_set("api", "key", only_fake):
		_fail("a template value counts as set")
	if Secrets.lookup("api", "key", only_fake)["source"] != Secrets.SOURCE_PLACEHOLDER:
		_fail("a template value is not reported as ignored")
	for text in ["", "  ", "fake", "Fake-Key", "https://fb3d.invalid/x", "please-replace-me"]:
		if not Secrets.is_placeholder(text):
			_fail("is_placeholder('%s') is false" % text)
	for text in [MARKER, "https://api.test-site.org/", "k3y-fakeness-inside"]:
		if Secrets.is_placeholder(text):
			_fail("is_placeholder('%s') is true" % text)


# Files that are not what they should be: nothing crashes and the value is not set.
func _check_bad_files() -> void:
	var cases = {
		"empty": "",
		"garbage": "this is not a config file {{{ [[[ \u0001 =\n",
		"half_section": '[api\nkey="%s"\n' % MARKER,
		"wrong_section": '[other]\nkey="%s"\n' % MARKER,
		"number": "[api]\nkey=12345\nbase_url=true\n",
		"array": '[api]\nkey=["%s"]\n' % MARKER,
		"blank": '[api]\nkey="   "\n',
		"too_long": '[api]\nkey="%s"\n' % "x".repeat(Secrets.MAX_LEN + 1),
		"unquoted": "[api]\nkey=%s\n" % MARKER,
		"no_section": 'key="%s"\n' % MARKER,
		"file_too_big": '[api]\nkey="%s"\n%s' % [MARKER, " ".repeat(Secrets.MAX_FILE)],
	}
	for name in cases:
		var path = "%s/bad_%s.cfg" % [TMP_DIR, name]
		_write(path, str(cases[name]))
		var src = {"path": path, "env": {}, "allowed": true}
		if Secrets.is_set("api", "key", src):
			_fail("bad file '%s': the key counts as set" % name)
		if Secrets.get_value("api", "key", "fallback", src) != "fallback":
			_fail("bad file '%s': the default was not returned" % name)
	# a too long value in the environment is not set either
	var long_env = {
		"path": TMP_DIR + "/missing.cfg",
		"env": {"FB3D_API_KEY": "x".repeat(Secrets.MAX_LEN + 1)},
		"allowed": true
	}
	if Secrets.is_set("api", "key", long_env):
		_fail("a too long environment value counts as set")
	# a folder where the file should be
	var dir_src = {"path": TMP_DIR, "env": {}, "allowed": true}
	if Secrets.is_set("api", "key", dir_src):
		_fail("a folder in place of the file counts as set")


# What the file reader accepts: comments, spaces, Windows line ends, a byte order mark, escapes, a second section.
func _check_file_format() -> void:
	var ok_text = (
		char(0xFEFF)
		+ '[ api ]\r\n  key = "ab\\"c\\\\d"  \r\nbase_url="https://api.test-site.org/"\r\n'
		+ '; a comment\r\n# another\r\n\r\n[other]\r\nkey="not-this-one"\r\n'
	)
	var path = TMP_DIR + "/format.cfg"
	_write(path, ok_text)
	var src = {"path": path, "env": {}, "allowed": true}
	if Secrets.get_value("api", "key", "", src) != 'ab"c\\d':
		_fail("the file reader did not handle spaces, escapes, a BOM or Windows line ends")
	if Secrets.get_value("api", "base_url", "", src) != "https://api.test-site.org/":
		_fail("the second value after a Windows line end was not read")
	var table = Secrets.parse_text(ok_text)
	if not table.has("other") or not table.has("api"):
		_fail("parse_text did not return both sections")
	elif str(table["api"].get("key", "")) != 'ab"c\\d':
		_fail("parse_text skipped the first section after a byte order mark")


# `allowed` false is an exported game: nothing is read, whatever is there.
func _check_gate() -> void:
	var good = TMP_DIR + "/good.cfg"
	var src = {"path": good, "env": {"FB3D_API_KEY": MARKER}, "allowed": false}
	if Secrets.is_set("api", "key", src):
		_fail("a value was read although the game is not allowed to read secrets")
	if Secrets.get_value("api", "key", "fallback", src) != "fallback":
		_fail("the default was not returned although reading is not allowed")
	# this check runs from the editor binary, so the real gate must be open here
	if not Secrets.allowed():
		_fail("allowed() is false when run from the Godot editor binary")


# The log line names the source and never the value.
func _check_status_line() -> void:
	var good = TMP_DIR + "/good.cfg"
	var src = {
		"path": good,
		"env": {"FB3D_API_BASE_URL": "https://" + MARKER + ".test-site.org/"},
		"allowed": true
	}
	var line = Secrets.status_line(src)
	if line.contains(MARKER) or line.contains("test-site.org"):
		_fail("status_line holds a value: " + line.replace(MARKER, "<value>"))
	if not line.contains(Secrets.SOURCE_ENV) or not line.contains(Secrets.SOURCE_FILE):
		_fail("status_line does not name the sources: " + line.replace(MARKER, "<value>"))
	for k in Secrets.KNOWN:
		if not line.contains("%s/%s" % [k["section"], k["key"]]):
			_fail("status_line does not name %s/%s" % [k["section"], k["key"]])
	var none_line = Secrets.status_line(
		{"path": TMP_DIR + "/missing.cfg", "env": {}, "allowed": true}
	)
	if not none_line.contains(Secrets.SOURCE_NONE):
		_fail("status_line with nothing set does not say so: " + none_line)


# The real process environment (no "env" in `src`).
func _check_real_environment() -> void:
	var src = {"path": TMP_DIR + "/missing.cfg", "allowed": true}
	var name = Secrets.env_name("api", "key")
	var before = OS.get_environment(name)
	OS.set_environment(name, MARKER + "-real")
	if Secrets.get_value("api", "key", "", src) != MARKER + "-real":
		_fail("a real environment variable was not read")
	OS.unset_environment(name)
	if Secrets.is_set("api", "key", src):
		_fail("the value is still set after the environment variable was removed")
	if before != "":
		OS.set_environment(name, before)


# The tracked template: every known value, fake values only, and the way to use it written down.
func _check_template() -> void:
	if not FileAccess.file_exists(TEMPLATE):
		_fail("secrets.example.cfg is missing")
		return
	var text = FileAccess.get_file_as_string(TEMPLATE)
	var cf = ConfigFile.new()
	if cf.load(TEMPLATE) != OK:
		_fail("secrets.example.cfg cannot be parsed")
		return
	for k in Secrets.KNOWN:
		var s = str(k["section"])
		var key = str(k["key"])
		if not cf.has_section_key(s, key):
			_fail("secrets.example.cfg has no %s/%s" % [s, key])
			continue
		var value = str(cf.get_value(s, key, ""))
		if not Secrets.is_placeholder(value):
			_fail("secrets.example.cfg: %s/%s is not an obvious fake value" % [s, key])
		# the loader's own reader and Godot's ConfigFile agree on the template
		var own = Secrets.parse_text(text)
		if not own.has(s) or str(own[s].get(key, "<none>")) != value:
			_fail(
				"secrets.example.cfg: the loader reads %s/%s differently from ConfigFile" % [s, key]
			)
		if not text.contains(Secrets.env_name(s, key)):
			_fail("secrets.example.cfg does not name the variable %s" % Secrets.env_name(s, key))
	for s in cf.get_sections():
		for key in cf.get_section_keys(s):
			var known = false
			for k in Secrets.KNOWN:
				if k["section"] == s and k["key"] == key:
					known = true
			if not known:
				_fail("secrets.example.cfg has %s/%s, which the loader does not know" % [s, key])
			if not Secrets.is_placeholder(str(cf.get_value(s, key, ""))):
				_fail("secrets.example.cfg: %s/%s is not an obvious fake value" % [s, key])
	# the template read through the loader gives nothing
	var src = {"path": TEMPLATE, "env": {}, "allowed": true}
	for k in Secrets.KNOWN:
		if Secrets.is_set(str(k["section"]), str(k["key"]), src):
			_fail("the unedited template counts as set for %s/%s" % [k["section"], k["key"]])
		if (
			Secrets.lookup(str(k["section"]), str(k["key"]), src)["source"]
			!= Secrets.SOURCE_PLACEHOLDER
		):
			_fail(
				(
					"the unedited template is not reported as ignored for %s/%s"
					% [k["section"], k["key"]]
				)
			)


# The untracked file must stay untracked (V1.1), and the template must not be hidden by the same rule.
func _check_gitignore() -> void:
	var path = "res://.gitignore"
	if not FileAccess.file_exists(path):
		_fail(".gitignore is missing")
		return
	var lines = FileAccess.get_file_as_string(path).split("\n")
	var has_local = false
	for line in lines:
		var t = line.strip_edges()
		if t == "secrets.local.*" or t == "secrets.local.cfg":
			has_local = true
		if t == "*.cfg" or t == "secrets.*" or t == "secrets*":
			_fail(".gitignore line '%s' would hide secrets.example.cfg" % t)
	if not has_local:
		_fail(".gitignore does not ignore secrets.local.cfg")


func _write(path: String, text: String) -> void:
	var f = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		_fail("cannot write " + path)
		return
	f.store_string(text)
	f.close()


func _finish() -> void:
	if problems.is_empty():
		print(
			"secrets_loader_check: fresh clone reads nothing, environment beats file, template values and bad files are ignored, nothing is read when not allowed, status line holds no value"
		)
		quit(0)
	else:
		for line in problems.slice(0, 10):
			printerr("secrets_loader_check: " + line)
		quit(1)


func _fail(text: String) -> void:
	problems.append(text)
