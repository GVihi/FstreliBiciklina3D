extends SceneTree
# Checks the HINTS ON / OFF row of the settings (README early alpha E1.4: `hints_on` in scripts/main.gd, the "hints" id in
# scripts/settings.gd and the FIRST-TIME HINTS row in scripts/hud.gd):
#   - the row is there, it is a switch, and a new game has it ON,
#   - Left, Right, Enter and a click switch it, and the choice is saved as `[game] show_hints` and loaded again; a
#     missing key or a value that is not true / false loads as ON,
#   - with it OFF none of the six triggers (map, upgrade, shop, rest, cache, extraction) shows a line, and none of them
#     uses up its "seen" flag, so switching it ON again shows the hints that were never met; a hint that was seen
#     before stays seen,
#   - switching it OFF takes a line that is on screen away at once,
#   - the settings panel with the extra row still fits the window at three window sizes, clear of its help line.
# Showing a hint saves `user://settings.cfg`, so the check keeps the real file and puts it back at the end.
# Run from the project folder:
#   godot --headless --path . --script res://tools/hint_setting_check.gd
# or with `python tools/run_checks.py hint_setting`. Exits with status 1 and prints the problems when a check fails.

const SettingsScript = preload("res://scripts/settings.gd")
const SETTINGS_PATH = "user://settings.cfg"
const SEED = 0x2468ACE9
const SIZES = [Vector2(1280.0, 720.0), Vector2(1920.0, 1080.0), Vector2(800.0, 450.0)]

var problems = []
var main
var kept = PackedByteArray()
var had_file = false


func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	main.generated_arena = true
	root.add_child(main)
	for i in range(3):
		await process_frame
	_keep_user_files()
	_check_row()
	_check_default()
	_check_save_load()
	await _check_panel_keys()
	await _check_off_triggers()
	_check_layout()
	_restore_user_files()
	_finish()


func _fail(text: String) -> void:
	if problems.size() < 40:
		problems.append(text)


func _remove_file() -> void:
	if FileAccess.file_exists(SETTINGS_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_PATH))


func _keep_user_files() -> void:
	had_file = FileAccess.file_exists(SETTINGS_PATH)
	if had_file:
		kept = FileAccess.get_file_as_bytes(SETTINGS_PATH)


func _restore_user_files() -> void:
	if had_file:
		var f = FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
		if f:
			f.store_buffer(kept)
			f.close()
	else:
		_remove_file()


func _key(code: int) -> void:
	var e = InputEventKey.new()
	e.pressed = true
	e.keycode = code
	main.input_sys.handle_input(e)


# forget the settings file, the flags and the line, as on a fresh install
func _fresh() -> void:
	_remove_file()
	main.hints_seen = {}
	main.hints_on = true
	main.settings.load_settings()
	main.hint_txt = ""
	main.hint_t0 = -100.0


# the saved [game] show_hints value, or null when the file has none
func _saved_switch():
	var cf = ConfigFile.new()
	if cf.load(SETTINGS_PATH) != OK:
		return null
	return cf.get_value("game", "show_hints", null)


func _seen_ids() -> Array:
	var out = []
	for id in SettingsScript.HINT_IDS:
		if main.settings.hint_seen(id):
			out.append(id)
	return out


func _row_of(id: String) -> int:
	var rows = main.hud.setting_rows()
	for i in range(rows.size()):
		if rows[i]["id"] == id:
			return i
	return -1


func _check_row() -> void:
	var i = _row_of("hints")
	if i < 0:
		_fail("the settings panel has no row with the id 'hints'")
		return
	var row = main.hud.setting_rows()[i]
	if not row.get("toggle", false):
		_fail("the hints row is not a switch")
	if str(row.get("label", "")).strip_edges() == "":
		_fail("the hints row has no label")
	if not main.hud.is_toggle("hints"):
		_fail("hud.is_toggle('hints') is false")
	if main.hud.is_action("hints"):
		_fail("hud.is_action('hints') is true, the row is a switch and not a button")


func _check_default() -> void:
	_fresh()
	if not main.hints_on or main.settings.get_setting("hints") != true:
		_fail("a new game does not have the hints ON")
	if _saved_switch() != null:
		_fail("a fresh game wrote show_hints before anything was changed")


func _check_save_load() -> void:
	_fresh()
	main.settings.set_setting("hints", false)
	if main.hints_on or main.settings.get_setting("hints") != false:
		_fail("set_setting('hints', false) did not switch the hints off")
	if _saved_switch() != false:
		_fail("OFF was not saved as [game] show_hints = false (got %s)" % str(_saved_switch()))
	main.hints_on = true
	main.settings.load_settings()
	if main.hints_on:
		_fail("the saved OFF did not load again")
	main.settings.set_setting("hints", true)
	if _saved_switch() != true:
		_fail("ON was not saved as [game] show_hints = true (got %s)" % str(_saved_switch()))
	main.hints_on = false
	main.settings.load_settings()
	if not main.hints_on:
		_fail("the saved ON did not load again")
	# a value that is not true / false, and a missing key, load as ON (the default)
	for bad in ["maybe", 0, 3.5, ""]:
		var cf = ConfigFile.new()
		cf.load(SETTINGS_PATH)
		cf.set_value("game", "show_hints", bad)
		cf.save(SETTINGS_PATH)
		main.hints_on = false
		main.settings.load_settings()
		if not main.hints_on:
			_fail("show_hints = %s loaded as OFF, not as the default ON" % var_to_str(bad))
	var cf2 = ConfigFile.new()
	cf2.load(SETTINGS_PATH)
	cf2.erase_section_key("game", "show_hints")
	cf2.save(SETTINGS_PATH)
	main.hints_on = false
	main.settings.load_settings()
	if not main.hints_on:
		_fail("a file without show_hints loaded as OFF, not as the default ON")
	# the switch and the seen flags are separate: OFF does not touch the flags in the file
	main.settings.set_setting("hints", true)
	main.settings.mark_hint_seen("shop")
	main.settings.set_setting("hints", false)
	var cf3 = ConfigFile.new()
	if cf3.load(SETTINGS_PATH) != OK or cf3.get_value("hints", "shop", false) != true:
		_fail("switching the hints off lost the saved shop flag")


# the panel is open: Left is off, Right is on, Enter flips, and a click flips too
func _check_panel_keys() -> void:
	_fresh()
	main.go_to_title()
	main.title_page = "settings"
	await process_frame
	main.setting_sel = _row_of("hints")
	_key(KEY_LEFT)
	if main.hints_on:
		_fail("Left on the hints row did not switch it off")
	_key(KEY_LEFT)
	if main.hints_on:
		_fail("Left on a switch that is already off switched it on")
	_key(KEY_RIGHT)
	if not main.hints_on:
		_fail("Right on the hints row did not switch it on")
	_key(KEY_ENTER)
	if main.hints_on or not main.hud.settings_visible():
		_fail("Enter on the hints row did not flip it, or closed the panel")
	_key(KEY_ENTER)
	if not main.hints_on:
		_fail("a second Enter did not switch the hints back on")
	main.settings.click_setting("hints")
	if main.hints_on:
		_fail("a click on the hints row did not flip it")
	main.settings.click_setting("hints")
	if not main.hints_on:
		_fail("a second click on the hints row did not flip it back")
	# the panel draws with the row picked, ON and OFF, at two window sizes
	for s in SIZES.slice(0, 2):
		main.hud.size = s
		for on in [true, false]:
			main.hints_on = on
			main.setting_sel = _row_of("hints")
			main.hud.queue_redraw()
			await process_frame
	main.hud.size = SIZES[0]
	main.hints_on = true
	_key(KEY_ESCAPE)


# OFF: every trigger stays quiet and keeps its flag; ON again: the ones never met show up, the met ones do not
func _check_off_triggers() -> void:
	_fresh()
	main.settings.set_setting("hints", false)
	main.start_game(false, SEED)
	for i in range(3):
		await process_frame
	if main.state != "map":
		_fail("a new run did not open the map (state %s)" % main.state)
		return
	if main.hint_txt != "":
		_fail("the map screen showed a hint with the hints OFF ('%s')" % main.hint_txt)
	main.shop_sys.show_upgrade()
	main.shop_sys.enter_shop()
	main.shop_sys.enter_rest()
	main.enter_map()
	main.pick_node(0)
	var o = main.objective_sys
	if main.state != "play" or not o.has_goal() or o.caches.is_empty():
		_fail("could not start a generated round with caches (state %s)" % main.state)
		return
	main.player.position = o.caches[0]["pos"] + Vector3(o.SENSE_RANGE - 5.0, 0.0, 0.0)
	o.update(0.05)
	o.begin_extraction()
	if main.hint_txt != "":
		_fail("a trigger showed a hint with the hints OFF ('%s')" % main.hint_txt)
	if not _seen_ids().is_empty():
		_fail("with the hints OFF the triggers used up their flags: %s" % str(_seen_ids()))
	var cf = ConfigFile.new()
	cf.load(SETTINGS_PATH)
	for id in SettingsScript.HINT_IDS:
		if cf.get_value("hints", id, false) == true:
			_fail("with the hints OFF [hints] %s = true was saved" % id)
	# a line that is up goes away the moment the switch goes OFF
	main.settings.set_setting("hints", true)
	main.settings.show_hint("A LINE")
	if main.settings.hint_alpha() <= 0.0:
		_fail("a hint with the hints ON is not visible")
	main.settings.set_setting("hints", false)
	if main.settings.hint_alpha() != 0.0:
		_fail("switching the hints OFF did not take the line on screen away")
	main.hint_txt = ""
	# ON again: a hint that was never met shows; one that was seen before the OFF stays seen
	main.settings.set_setting("hints", true)
	main.settings.mark_hint_seen("rest")
	main.settings.set_setting("hints", false)
	main.settings.set_setting("hints", true)
	main.shop_sys.enter_shop()
	if (
		main.hint_txt != str(SettingsScript.HINT_TEXTS["shop"])
		or not main.settings.hint_seen("shop")
	):
		_fail("with the hints ON again the shop hint did not show (line '%s')" % main.hint_txt)
	main.hint_txt = ""
	main.shop_sys.enter_rest()
	if main.hint_txt != "":
		_fail("the rest hint showed again after it was seen before the OFF")


# the panel with one more row: inside the window and clear of the help line under it, at three window sizes
func _check_layout() -> void:
	var hud = main.hud
	for s in SIZES:
		hud.size = s
		var k = s.y / 720.0
		var pr = hud.panel_rect()
		var label = "the settings panel at %dx%d" % [int(s.x), int(s.y)]
		if pr.position.x < 0.0 or pr.position.y < 0.0 or pr.end.x > s.x or pr.end.y > s.y:
			_fail("%s %s is not inside the window" % [label, str(pr)])
		var last = hud.row_rect(hud.setting_rows().size() - 1)
		if last.end.y > pr.end.y:
			_fail("%s: the last row sticks out of the panel" % label)
		# the help line is drawn at 89 % of the height with a 14 px (at 720p) font, so its top is about 11 k above
		if pr.end.y > s.y * 0.89 - 11.0 * k:
			_fail(
				(
					"%s ends at %.0f, which reaches the help line at %.0f"
					% [label, pr.end.y, s.y * 0.89 - 11.0 * k]
				)
			)
	hud.size = SIZES[0]


func _finish() -> void:
	if problems.is_empty():
		print(
			"hint_setting_check: the HINTS switch is saved, loaded, and silences the six hints without using them up"
		)
		quit(0)
	else:
		for line in problems.slice(0, 12):
			printerr("hint_setting_check: " + line)
		quit(1)
