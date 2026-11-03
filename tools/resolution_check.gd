extends SceneTree
# Checks the WINDOW SIZE row of the settings panel (README Milestone E, "Choose the window size"): scripts/settings.gd
# `window_options`, `clamp_window`, `parse_window` and the row in scripts/hud.gd. Run from the project folder:
#   python tools/run_checks.py resolution
# or: godot --headless --path . --script res://tools/resolution_check.gd
#
# Sizes: only the presets that fit the screen are offered (the screen's free area minus room for the title bar), smallest
# first, the current size is in the list once when it is none of them, and an unknown screen offers every preset. Config:
# a saved size that is not two whole numbers, or is too small or too big, is ignored, and a good one is read. Clamping:
# a size is never below the minimum or bigger than the free area. Row: the settings panel has it between FULLSCREEN and
# SOUND, it is a choice row with as many names as sizes, Left / Right step through it without error, and the panel with
# its sixteen rows still fits the window and stays clear of the help line at four window sizes.
# Exits with status 1 and prints the problems when a check fails.

const Settings = preload("res://scripts/settings.gd")

const SIZES = [Vector2(1280, 720), Vector2(1920, 1080), Vector2(1024, 768), Vector2(3440, 1440)]

var problems = []
var main


func _initialize() -> void:
	_options()
	_clamp()
	_config()
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	for i in range(3):
		await process_frame
	await _row()
	_finish()


func _fail(text: String) -> void:
	if problems.size() < 40:
		problems.append(text)


func _finish() -> void:
	if problems.is_empty():
		print("resolution_check: the sizes, the saved size, the clamping and the settings row hold")
		quit(0)
	else:
		for p in problems:
			printerr("resolution_check: " + p)
		quit(1)


# ------------------------------------------------------------------ which sizes are offered
func _options() -> void:
	# a 1080p screen with a task bar: 1920x1080 does not fit as a window, 1600x900 does
	var o = Settings.window_options(Vector2i(1920, 1040), Vector2i(1280, 720))
	if o.has(Vector2i(1920, 1080)) or o.has(Vector2i(2560, 1440)):
		_fail("sizes that do not fit a 1920x1040 free area are offered: %s" % str(o))
	if not o.has(Vector2i(1280, 720)) or not o.has(Vector2i(1600, 900)):
		_fail("sizes that fit a 1920x1040 free area are missing: %s" % str(o))
	# the current size is in the list once, in its place by area
	var c = Settings.window_options(Vector2i(2560, 1400), Vector2i(720, 480))
	if c.count(Vector2i(720, 480)) != 1 or c[0] != Vector2i(720, 480):
		_fail("a current size of 720x480 should be listed once, first: %s" % str(c))
	var d = Settings.window_options(Vector2i(2560, 1400), Vector2i(1280, 720))
	if d.count(Vector2i(1280, 720)) != 1:
		_fail("a current size that is a preset was listed %d times" % d.count(Vector2i(1280, 720)))
	# sorted by area
	for i in range(1, c.size()):
		if c[i - 1].x * c[i - 1].y > c[i].x * c[i].y:
			_fail("the sizes are not sorted by area: %s" % str(c))
			break
	# an unknown screen (a headless run) offers everything
	var u = Settings.window_options(Vector2i.ZERO, Vector2i(1280, 720))
	if u.size() != Settings.WINDOW_PRESETS.size():
		_fail(
			(
				"an unknown screen offered %d of %d presets"
				% [u.size(), Settings.WINDOW_PRESETS.size()]
			)
		)
	# a screen smaller than every preset still offers the current size, so the row is never empty
	var tiny = Settings.window_options(Vector2i(800, 600), Vector2i(720, 480))
	if tiny != [Vector2i(720, 480)]:
		_fail("a small screen should offer only the current size, not %s" % str(tiny))
	if Settings.window_label(Vector2i(1920, 1080)) != "1920 x 1080":
		_fail("the label of 1920x1080 reads %s" % Settings.window_label(Vector2i(1920, 1080)))


# ------------------------------------------------------------------ clamping
func _clamp() -> void:
	var usable = Vector2i(1920, 1040)
	if Settings.clamp_window(Vector2i(100, 100), usable) != Settings.WINDOW_MIN:
		_fail("a tiny size was not raised to the minimum")
	var big = Settings.clamp_window(Vector2i(5000, 5000), usable)
	if big.x > usable.x or big.y > usable.y - Settings.WINDOW_DECOR:
		_fail("a huge size was not cut to the free area: %s" % str(big))
	if Settings.clamp_window(Vector2i(1280, 720), usable) != Vector2i(1280, 720):
		_fail("a size that fits was changed")
	if Settings.clamp_window(Vector2i(5000, 5000), Vector2i.ZERO) != Vector2i(5000, 5000):
		_fail("an unknown screen should leave a big size alone")
	var squeezed = Settings.clamp_window(Vector2i(900, 900), Vector2i(1000, 380))
	if squeezed.y < Settings.WINDOW_MIN.y:
		_fail("a very short screen pushed the height under the minimum: %s" % str(squeezed))


# ------------------------------------------------------------------ settings.cfg
func _cfg(w, h) -> ConfigFile:
	var cf = ConfigFile.new()
	if w != null:
		cf.set_value("game", "window_w", w)
	if h != null:
		cf.set_value("game", "window_h", h)
	return cf


func _config() -> void:
	if Settings.parse_window(_cfg(1600, 900)) != Vector2i(1600, 900):
		_fail("a good saved size was not read")
	if Settings.parse_window(ConfigFile.new()) != Vector2i.ZERO:
		_fail("a file with no size should give none")
	var bad = [
		[null, 900],
		[1600, null],
		["wide", 900],
		[1600.5, 900],
		[true, true],
		[100, 100],
		[1600, 100],
		[100, 900],
		[99999, 900],
		[1600, 99999],
		[-1280, 720],
	]
	for pair in bad:
		var got = Settings.parse_window(_cfg(pair[0], pair[1]))
		if got != Vector2i.ZERO:
			_fail("the saved size %s was accepted as %s" % [str(pair), str(got)])


# ------------------------------------------------------------------ the row
func _row() -> void:
	var hud = main.hud
	var rows = hud.setting_rows()
	var at = -1
	for i in range(rows.size()):
		if rows[i]["id"] == "resolution":
			at = i
	if at < 0:
		_fail("the settings panel has no row with the id 'resolution'")
		return
	if rows[at - 1]["id"] != "fullscreen" or rows[at + 1]["id"] != "sound":
		_fail("the window size row is not between FULLSCREEN and SOUND")
	if not hud.is_toggle("resolution") or not rows[at].has("choices"):
		_fail("the window size row is not a choice row")
	var names = main.settings.choice_labels(rows[at])
	var count = main.settings.window_choices().size()
	if names.is_empty() or names.size() != count:
		_fail("the window size row has %d names for %d sizes" % [names.size(), count])
	var idx = int(main.get_setting("resolution"))
	if idx < 0 or idx >= names.size():
		_fail("the window size row points at %d of %d names" % [idx, names.size()])
	# a fixed row still reads its own choices
	for row in rows:
		if row["id"] == "quality" and main.settings.choice_labels(row) != ["HIGH", "MEDIUM", "LOW"]:
			_fail("the GRAPHICS row lost its choices")
	# stepping through the row, in the title menu, does not fail and wraps
	main.go_to_title()
	main.title_page = "settings"
	main.setting_sel = at
	await process_frame
	var before = main.settings.window_size_now()
	for d in [1, 1, -1, -1, -1]:
		main.input_sys.settings_adjust(d)
	var next = main.settings.next_value("resolution")
	if int(next) < 0 or int(next) >= maxi(1, count):
		_fail("next_value gave %s for %d sizes" % [str(next), count])
	main.settings.set_setting("resolution", 9999)  # past the end: the last size, no crash
	main.settings.set_setting("resolution", -5)  # before the start: the first size, no crash
	if before == Vector2i.ZERO:
		_fail("the window reported no size")
	# the panel with its rows fits, and clears the help line
	for s in SIZES:
		hud.size = s
		var k = s.y / 720.0
		var pr = hud.panel_rect()
		var label = "the settings panel at %dx%d" % [int(s.x), int(s.y)]
		if pr.position.y < 0.0 or pr.end.y > s.y * 0.89 - 11.0 * k:
			_fail("%s %s does not fit above the help line" % [label, str(pr)])
		var last = hud.row_rect(rows.size() - 1)
		if last.end.y > pr.end.y:
			_fail("%s: the last row sticks out of the panel" % label)
		for i in range(1, rows.size()):
			if hud.row_rect(i).position.y < hud.row_rect(i - 1).end.y:
				_fail("%s: rows %d and %d overlap" % [label, i - 1, i])
	hud.size = Vector2(1280.0, 720.0)
	main.title_page = ""
