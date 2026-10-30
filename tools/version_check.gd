extends SceneTree
# Checks the game version shown on the title screen (README Milestone E, Release Readiness) and the build identity
# (roadmap V2.2, scripts/build_info.gd):
#   - `config/version` in project.godot holds a version like 0.1.0 (the one place it is written),
#   - `Main.game_version` reads it, and the title screen draws with it,
#   - build_info.json: no file = the project version and the commit "dev"; a good file shows "v0.3.0 (a1b2c3d)", a
#     dirty one "(a1b2c3d+)"; a damaged, empty, oversized, wrong-typed or left-over (other version) file gives the
#     fallback and never crashes; the console line is "FB3D 0.3.0 (a1b2c3d)".
# Run from the project folder:
#   godot --headless --path . --script res://tools/version_check.gd
# or with tools\run_version_check.bat on Windows.
# Exits with status 1 and prints the problems when a check fails.

const BuildInfo = preload("res://scripts/build_info.gd")
const TMP_DIR = "user://version_check"
const COMMIT = "a1b2c3d4e5f60718293a4b5c6d7e8f9012345678"

var problems = []
var main


func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	for i in range(3):
		await process_frame
	var stored = str(ProjectSettings.get_setting("application/config/version", ""))
	var shape = RegEx.new()
	shape.compile("^[0-9]+\\.[0-9]+\\.[0-9]+$")
	if shape.search(stored) == null:
		_fail("config/version in project.godot is '%s', expected a version like 0.1.0" % stored)
	if main.game_version != stored:
		_fail("Main.game_version is '%s', project.godot says '%s'" % [main.game_version, stored])
	# draw the title screen at two window shapes (a script error in the drawing code shows up here)
	main.go_to_title()
	for s in [Vector2(1280.0, 720.0), Vector2(1920.0, 1080.0)]:
		main.hud.size = s
		for f in range(2):
			main.hud.queue_redraw()
			await process_frame
	# the label the title screen draws is the build identity, and no version means nothing drawn
	if main.version_label() != BuildInfo.title_text(main.build_info):
		_fail(
			(
				"Main.version_label() is '%s', build info says '%s'"
				% [main.version_label(), BuildInfo.title_text(main.build_info)]
			)
		)
	main.game_version = ""
	if main.version_label() != "":
		_fail(
			(
				"Main.version_label() is '%s' without a game version, expected nothing"
				% main.version_label()
			)
		)
	main.hud.queue_redraw()
	await process_frame
	_check_build_info(stored)
	_finish()


# A build_info.json as tools/make_build_info.py writes it, with one change when given.
func _good_text(version: String, changes: Dictionary = {}) -> String:
	var data = {
		"version": version,
		"commit": COMMIT,
		"short": COMMIT.substr(0, 7),
		"dirty": false,
		"built_utc": "2026-10-30T10:02:02Z",
		"channel": "alpha",
	}
	for key in changes:
		if changes[key] == null:
			data.erase(key)
		else:
			data[key] = changes[key]
	return JSON.stringify(data)


func _check_build_info(stored: String) -> void:
	DirAccess.make_dir_recursive_absolute(TMP_DIR)
	# no file: the project version and the commit "dev"
	var none = BuildInfo.load_info(TMP_DIR + "/missing.json")
	_expect(
		none["source"] == "fallback", "no file: source is '%s', expected fallback" % none["source"]
	)
	_expect(
		none["version"] == stored,
		"no file: version is '%s', expected '%s'" % [none["version"], stored]
	)
	_expect(none["commit"] == "dev", "no file: commit is '%s', expected dev" % none["commit"])
	_expect(
		BuildInfo.title_text(none) == "v%s (dev)" % stored,
		"no file: title is '%s'" % BuildInfo.title_text(none)
	)
	_expect(
		BuildInfo.console_line(none) == "FB3D %s (dev)" % stored,
		"no file: console line is '%s'" % BuildInfo.console_line(none)
	)
	# a good file
	var good = BuildInfo.parse(_good_text(stored))
	_expect(good["source"] == "file", "good file: source is '%s', expected file" % good["source"])
	_expect(
		good["commit"] == COMMIT and good["channel"] == "alpha",
		"good file: commit or channel not read"
	)
	_expect(
		BuildInfo.title_text(good) == "v%s (a1b2c3d)" % stored,
		"good file: title is '%s'" % BuildInfo.title_text(good)
	)
	_expect(
		BuildInfo.console_line(good) == "FB3D %s (a1b2c3d)" % stored,
		"good file: console line is '%s'" % BuildInfo.console_line(good)
	)
	# a dirty build shows a plus
	var dirty = BuildInfo.parse(_good_text(stored, {"dirty": true}))
	_expect(dirty["dirty"] == true, "dirty file: dirty flag not read")
	_expect(
		BuildInfo.title_text(dirty) == "v%s (a1b2c3d+)" % stored,
		"dirty file: title is '%s'" % BuildInfo.title_text(dirty)
	)
	_expect(
		BuildInfo.console_line(dirty) == "FB3D %s (a1b2c3d+)" % stored,
		"dirty file: console line is '%s'" % BuildInfo.console_line(dirty)
	)
	# damaged files: all give the fallback with source "damaged", none crashes
	var damaged = {
		"empty": "",
		"not json": "{not json",
		"an array": "[1, 2, 3]",
		"a number": "42",
		"missing commit": _good_text(stored, {"commit": null}),
		"missing dirty": _good_text(stored, {"dirty": null}),
		"dirty as text": _good_text(stored, {"dirty": "yes"}),
		"commit as number": _good_text(stored, {"commit": 12345}),
		"short commit": _good_text(stored, {"commit": "a1b2c3d", "short": "a1b2c3d"}),
		"capital letters in the hash":
		_good_text(stored, {"commit": COMMIT.to_upper(), "short": COMMIT.to_upper().substr(0, 7)}),
		"short does not match": _good_text(stored, {"short": "1234567"}),
		"unknown channel": _good_text(stored, {"channel": "nightly"}),
		"bad time": _good_text(stored, {"built_utc": "yesterday"}),
		"bad version": _good_text("three"),
		"oversized": _good_text(stored, {"channel": "x".repeat(BuildInfo.MAX_FILE)}),
	}
	for name in damaged:
		var info = BuildInfo.parse(damaged[name])
		_expect(
			info["source"] == "damaged",
			"%s: source is '%s', expected damaged" % [name, info["source"]]
		)
		_expect(
			info["commit"] == "dev" and info["version"] == stored, "%s: not the fallback" % name
		)
		_expect(
			not BuildInfo.title_text(info).contains("a1b2c3d"),
			"%s: title still shows the file's hash" % name
		)
	# a file written for another version is a left-over
	var stale = BuildInfo.parse(_good_text("9.9.9"))
	_expect(
		stale["source"] == "stale",
		"other version: source is '%s', expected stale" % stale["source"]
	)
	_expect(stale["commit"] == "dev", "other version: the old hash is still used")
	# reading from disk: a good file, an empty file, an oversized file
	_write(TMP_DIR + "/good.json", _good_text(stored))
	_expect(
		BuildInfo.load_info(TMP_DIR + "/good.json")["source"] == "file",
		"good file on disk was not read"
	)
	_write(TMP_DIR + "/empty.json", "")
	_expect(
		BuildInfo.load_info(TMP_DIR + "/empty.json")["source"] == "damaged",
		"empty file on disk is not 'damaged'"
	)
	_write(TMP_DIR + "/big.json", "x".repeat(BuildInfo.MAX_FILE + 10))
	_expect(
		BuildInfo.load_info(TMP_DIR + "/big.json")["source"] == "damaged",
		"oversized file on disk is not 'damaged'"
	)
	# no project version: nothing to show, no error
	_expect(BuildInfo.title_text({}) == "", "empty info: the title is not empty")
	_expect(
		BuildInfo.console_line({}) == "FB3D unknown (dev)",
		"empty info: console line is '%s'" % BuildInfo.console_line({})
	)


func _write(path: String, text: String) -> void:
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_fail("cannot write " + path)
		return
	file.store_string(text)
	file.close()


func _expect(condition: bool, text: String) -> void:
	if not condition:
		_fail(text)


func _finish() -> void:
	if problems.is_empty():
		print(
			"version_check: the version is in project.godot, read by the game and drawn on the title screen with the build hash"
		)
		quit(0)
	else:
		for line in problems.slice(0, 10):
			printerr("version_check: " + line)
		quit(1)


func _fail(text: String) -> void:
	problems.append(text)
