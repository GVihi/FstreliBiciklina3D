extends SceneTree
# Checks the first-run hint flags in settings.cfg (README early alpha E1.1, docs/SAVE_FILES.md "First-run hints"):
#   - a fresh save (no settings.cfg) has no hint seen, and every one of the six ids is known,
#   - mark_hint_seen returns true the first time and false after that, and saves the flag under [hints],
#   - an id that is not one of the six is never stored and never counts as seen,
#   - the flags survive a save and a load, next to the other settings, and the file version stays 1,
#   - an old file without a [hints] section loads with nothing seen and keeps its other settings,
#   - a hand-edited file (text, numbers, null, a list, an unknown id) only ever makes a hint show again,
#   - a file that cannot be read loads with nothing seen and does not crash.
# Changing settings saves `user://settings.cfg`, so the check keeps the real file and puts it back at the end.
# Run from the project folder:
#   godot --headless --path . --script res://tools/hint_flags_check.gd
# or with `python tools/run_checks.py hint_flags`. Exits with status 1 and prints the problems when a check fails.

const SettingsScript = preload("res://scripts/settings.gd")
const SETTINGS_PATH = "user://settings.cfg"
const BAD_COPY_PATH = "user://settings.cfg.bad.bak"
const IDS = ["map", "upgrade", "shop", "rest", "extract", "cache"]

var problems = []
var main
var kept = PackedByteArray()
var had_file = false
var had_bad_copy = false


func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	for i in range(3):
		await process_frame
	_keep_user_files()
	_check_ids()
	_check_fresh()
	_check_mark()
	_check_unknown_id()
	_check_round_trip()
	_check_old_file()
	_check_hand_edited()
	_check_unreadable()
	_restore_user_files()
	_finish()


func _fail(text: String) -> void:
	problems.append(text)


func _write(text: String) -> void:
	var f = FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if f:
		f.store_string(text)
		f.close()


func _remove_file() -> void:
	if FileAccess.file_exists(SETTINGS_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_PATH))


# forget what the game holds in memory, then read settings.cfg the way the game does at start
func _reload() -> void:
	main.hints_seen = {}
	main.settings.load_settings()


func _seen_ids() -> Array:
	var out = []
	for id in IDS:
		if main.settings.hint_seen(id):
			out.append(id)
	return out


func _file_value(section: String, key: String, fallback):
	var cf = ConfigFile.new()
	if cf.load(SETTINGS_PATH) != OK:
		return fallback
	return cf.get_value(section, key, fallback)


func _check_ids() -> void:
	var ids = SettingsScript.HINT_IDS
	if ids.size() != IDS.size():
		_fail("HINT_IDS has %d ids, the six triggers of E1.3 are expected" % ids.size())
	for id in IDS:
		if not ids.has(id):
			_fail("HINT_IDS has no '%s' hint" % id)


func _check_fresh() -> void:
	_remove_file()
	_reload()
	var seen = _seen_ids()
	if not seen.is_empty():
		_fail("a fresh save has hints seen: %s" % str(seen))


func _check_mark() -> void:
	_remove_file()
	_reload()
	if not main.settings.mark_hint_seen("shop"):
		_fail("mark_hint_seen('shop') did not return true the first time")
	if main.settings.mark_hint_seen("shop"):
		_fail("mark_hint_seen('shop') returned true the second time")
	if not main.settings.hint_seen("shop"):
		_fail("'shop' is not seen after it was marked")
	if _file_value("hints", "shop", false) != true:
		_fail("settings.cfg has no [hints] shop = true after marking it")
	for id in ["map", "upgrade", "rest", "extract", "cache"]:
		if _file_value("hints", id, null) != false:
			_fail("settings.cfg should hold [hints] %s = false while it was not shown" % id)
		if main.settings.hint_seen(id):
			_fail("marking 'shop' also marked '%s'" % id)


func _check_unknown_id() -> void:
	_remove_file()
	_reload()
	if main.settings.mark_hint_seen("nope"):
		_fail("mark_hint_seen('nope') returned true for an id that is not one of the six")
	if main.settings.hint_seen("nope"):
		_fail("an unknown id counts as seen")
	if main.hints_seen.has("nope"):
		_fail("an unknown id was stored in memory")
	main.settings.save_settings()
	if _file_value("hints", "nope", null) != null:
		_fail("an unknown id was written to settings.cfg")


func _check_round_trip() -> void:
	_remove_file()
	_reload()
	main.settings.set_setting("sens", 1.7)
	main.settings.mark_hint_seen("map")
	main.settings.mark_hint_seen("cache")
	main.sens_mul = 1.0
	_reload()
	var seen = _seen_ids()
	if seen != ["map", "cache"] and seen != ["cache", "map"]:
		_fail("after a save and a load the seen hints are %s, expected map and cache" % str(seen))
	if absf(main.sens_mul - 1.7) > 0.0001:
		_fail("marking a hint lost another setting (sens is %s, expected 1.7)" % str(main.sens_mul))
	if int(_file_value("meta", "version", 0)) != 1:
		_fail("the settings.cfg version is not 1 (a new field with a default needs no bump)")


func _check_old_file() -> void:
	_write("[meta]\nversion=1\n\n[game]\nsens=1.2\n")
	main.sens_mul = 1.0
	_reload()
	if not _seen_ids().is_empty():
		_fail("an old file without [hints] loaded with hints seen: %s" % str(_seen_ids()))
	if absf(main.sens_mul - 1.2) > 0.0001:
		_fail(
			(
				"an old file without [hints] lost its other settings (sens %s, expected 1.2)"
				% str(main.sens_mul)
			)
		)


func _check_hand_edited() -> void:
	_write(
		(
			"[meta]\nversion=1\n\n[game]\nsens=1.2\n\n[hints]\n"
			+ 'map=true\nupgrade="yes"\nshop=1\nrest=false\nextract=null\ncache=[1, 2]\nfoo=true\n'
		)
	)
	main.sens_mul = 1.0
	_reload()
	if _seen_ids() != ["map"]:
		_fail("a hand-edited file should leave only 'map' seen, got %s" % str(_seen_ids()))
	if main.hints_seen.has("foo"):
		_fail("an unknown id in the file was loaded")
	if absf(main.sens_mul - 1.2) > 0.0001:
		_fail("a hand-edited [hints] section broke the other settings")
	main.settings.save_settings()
	if _file_value("hints", "foo", null) != null:
		_fail("an unknown id in the file survived the next save")
	if _file_value("hints", "map", false) != true:
		_fail("the next save lost the 'map' flag")


func _check_unreadable() -> void:
	_write("this is not a settings file [[[\n")
	_reload()
	if not _seen_ids().is_empty():
		_fail("an unreadable file loaded with hints seen: %s" % str(_seen_ids()))


func _keep_user_files() -> void:
	had_file = FileAccess.file_exists(SETTINGS_PATH)
	if had_file:
		kept = FileAccess.get_file_as_bytes(SETTINGS_PATH)
	had_bad_copy = FileAccess.file_exists(BAD_COPY_PATH)


func _restore_user_files() -> void:
	if had_file:
		var f = FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
		if f:
			f.store_buffer(kept)
			f.close()
	else:
		_remove_file()
	# the unreadable-file case makes a .bad.bak copy; it was not there before, so take it away again
	if not had_bad_copy and FileAccess.file_exists(BAD_COPY_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(BAD_COPY_PATH))


func _finish() -> void:
	if problems.is_empty():
		print(
			"hint_flags_check: the first-run hint flags save, load and survive a bad settings file"
		)
		quit(0)
	else:
		for line in problems.slice(0, 12):
			printerr("hint_flags_check: " + line)
		quit(1)
