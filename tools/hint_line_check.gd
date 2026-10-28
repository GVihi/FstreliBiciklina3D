extends SceneTree
# Checks the first-run hint line (README early alpha E1.2, `hint_*` in scripts/settings.gd, `_draw_hint` in scripts/hud.gd):
#   - nothing is showing on a fresh game (alpha 0, empty text, an empty strip),
#   - show_hint puts a line up for HINT_SECONDS: fully shown, then fading over the last HINT_FADE seconds, then gone,
#     and a second hint replaces the first and starts again,
#   - show_hint does not touch the "seen" flags, hint_once shows a hint the first time only and saves the flag,
#     and an id that is not one of the six shows nothing,
#   - the line never blocks input: with it up on the map screen a node can still be picked, and a round that is up and
#     running keeps running (the line is only drawn, it takes no click or key and does not pause),
#   - the strip stays inside the window at three window sizes, even for a very long line (the font shrinks to fit),
#     sits clear of the dash bar and the FREE DARTS line in a round and of the bottom prompt on the other screens,
#   - the screens draw with the line showing, at two window sizes, in a round and on the map screen.
# Showing a hint saves `user://settings.cfg`, so the check keeps the real file and puts it back at the end.
# Run from the project folder:
#   godot --headless --path . --script res://tools/hint_line_check.gd
# or with `python tools/run_checks.py hint_line`. Exits with status 1 and prints the problems when a check fails.

const SettingsScript = preload("res://scripts/settings.gd")
const SETTINGS_PATH = "user://settings.cfg"
const SEED = 0x2468ACE1
const SIZES = [Vector2(1280.0, 720.0), Vector2(1920.0, 1080.0), Vector2(800.0, 450.0)]

var problems = []
var main
var kept = PackedByteArray()
var had_file = false


func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	for i in range(3):
		await process_frame
	_keep_user_files()
	_check_idle()
	_check_timing()
	_check_replace()
	_check_once()
	await _check_input_and_drawing()
	_restore_user_files()
	_finish()


func _fail(text: String) -> void:
	problems.append(text)


func _near(a: float, b: float) -> bool:
	return absf(a - b) < 0.001


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


# forget the flags and the line, as on a fresh install
func _fresh() -> void:
	_remove_file()
	main.hints_seen = {}
	main.settings.load_settings()
	main.hint_txt = ""
	main.hint_t0 = -100.0


# pretend the line has been up for `age` seconds (g.time moves on its own between frames, so set it right after showing)
func _age(age: float) -> void:
	main.hint_t0 = main.time - age


func _alpha_at(age: float) -> float:
	_age(age)
	return main.settings.hint_alpha()


func _check_idle() -> void:
	_fresh()
	if main.settings.hint_alpha() != 0.0:
		_fail("a fresh game has a hint showing (alpha %f)" % main.settings.hint_alpha())
	main.hud.size = SIZES[0]
	if main.hud.hint_rect(1.0) != Rect2():
		_fail("hint_rect is not empty while no hint is showing")
	# an empty text never shows, whatever the clock says
	main.hint_t0 = main.time
	if main.settings.hint_alpha() != 0.0:
		_fail("an empty hint text has an alpha")


func _check_timing() -> void:
	_fresh()
	main.settings.show_hint("TEST HINT")
	if main.hint_txt != "TEST HINT":
		_fail("show_hint did not set the text (got '%s')" % main.hint_txt)
	var full = SettingsScript.HINT_SECONDS
	var fade = SettingsScript.HINT_FADE
	if full < 3.0 or full > 8.0:
		_fail("HINT_SECONDS is %.1f, 'a few seconds' is 3 to 8" % full)
	if not _near(_alpha_at(0.0), 1.0):
		_fail("a hint that was just shown is not fully visible (alpha %f)" % _alpha_at(0.0))
	if not _near(_alpha_at(full - fade - 0.05), 1.0):
		_fail("the hint starts fading before the last %.1f s" % fade)
	var mid = _alpha_at(full - fade * 0.5)
	if mid < 0.3 or mid > 0.7:
		_fail("halfway through the fade the alpha is %f, not about 0.5" % mid)
	var late = _alpha_at(full - 0.02)
	if late <= 0.0 or late > 0.1:
		_fail("just before the end the alpha is %f, not a small positive value" % late)
	if _alpha_at(full) != 0.0:
		_fail("the hint is still drawn after HINT_SECONDS")
	if _alpha_at(full + 30.0) != 0.0:
		_fail("the hint comes back after it ended")
	if _alpha_at(-5.0) != 0.0:
		_fail("a hint stamped in the future is drawn")
	var seen = []
	for id in SettingsScript.HINT_IDS:
		if main.settings.hint_seen(id):
			seen.append(id)
	if not seen.is_empty():
		_fail("show_hint marked hints as seen: %s" % str(seen))


func _check_replace() -> void:
	_fresh()
	main.settings.show_hint("FIRST")
	_age(4.0)
	main.settings.show_hint("SECOND")
	if main.hint_txt != "SECOND":
		_fail("a second hint did not replace the first (got '%s')" % main.hint_txt)
	if not _near(main.settings.hint_alpha(), 1.0):
		_fail("a second hint did not start again at full alpha")


func _check_once() -> void:
	_fresh()
	if not main.settings.hint_once("shop", "SHOP HINT"):
		_fail("hint_once('shop') returned false the first time")
	if main.hint_txt != "SHOP HINT" or main.settings.hint_alpha() <= 0.0:
		_fail("hint_once('shop') did not put the hint up")
	if not main.settings.hint_seen("shop"):
		_fail("hint_once('shop') did not mark it seen")
	var cf = ConfigFile.new()
	if cf.load(SETTINGS_PATH) != OK or cf.get_value("hints", "shop", false) != true:
		_fail("hint_once('shop') did not save [hints] shop = true")
	main.hint_txt = "OTHER"
	if main.settings.hint_once("shop", "SHOP HINT AGAIN"):
		_fail("hint_once('shop') returned true the second time")
	if main.hint_txt != "OTHER":
		_fail("hint_once('shop') changed the line on the second call (got '%s')" % main.hint_txt)
	if main.settings.hint_once("nope", "NOPE"):
		_fail("hint_once('nope') returned true for an id that is not one of the six")
	if main.hint_txt != "OTHER":
		_fail("hint_once('nope') changed the line")


# the strip must be inside the window and clear of what the screen already draws there
func _check_rect(where: String, in_round: bool) -> void:
	var hud = main.hud
	for s in SIZES:
		hud.size = s
		var k = s.y / 720.0
		for text in ["PRESS TAB TO OPEN THE MAP", "W".repeat(SettingsScript.HINT_MAX_CHARS)]:
			main.hint_txt = text
			var r = hud.hint_rect(k)
			var label = "%s at %dx%d, %d characters" % [where, int(s.x), int(s.y), text.length()]
			if r.size.x <= 0.0 or r.size.y <= 0.0:
				_fail("%s: the strip is empty" % label)
				continue
			if r.position.x < 0.0 or r.end.x > s.x or r.position.y < 0.0 or r.end.y > s.y:
				_fail("%s: the strip %s is not inside the window" % [label, str(r)])
			if absf((r.position.x + r.end.x) * 0.5 - s.x * 0.5) > 1.0:
				_fail("%s: the strip is not centred" % label)
			if r.end.y < s.y * 0.6:
				_fail("%s: the strip is not at the bottom (ends at %.0f)" % [label, r.end.y])
			if in_round and r.end.y > s.y - 96.0 * k:
				_fail("%s: the strip reaches the FREE DARTS line (ends at %.0f)" % [label, r.end.y])
			if not in_round and r.end.y > s.y * 0.93 - 16.0 * k:
				_fail("%s: the strip reaches the bottom prompt (ends at %.0f)" % [label, r.end.y])
			if hud.hint_fs(k) < 8:
				_fail("%s: the font shrank below 8 px" % label)


func _check_input_and_drawing() -> void:
	_fresh()
	main.start_game(false, SEED)
	await process_frame
	if main.state != "map":
		_fail("could not reach the map screen (state %s)" % main.state)
		return
	# on the map screen
	main.settings.show_hint("TEST HINT")
	_check_rect("map screen", false)
	main.hint_txt = "TEST HINT"
	for s in SIZES.slice(0, 2):
		main.hud.size = s
		main.hud.queue_redraw()
		await process_frame
	main.hud.size = SIZES[0]
	main.settings.show_hint("TEST HINT")
	main.pick_node(0)
	await process_frame
	if main.state == "map":
		_fail("with a hint showing, picking a node did nothing (state still 'map')")
	# in a round (headless Godot cannot capture the mouse, so the test hook plays the round)
	main.force_captured = true
	await process_frame
	await process_frame
	if main.state != "play":
		_fail("could not start a round (state %s)" % main.state)
		main.force_captured = false
		return
	main.settings.show_hint("TEST HINT")
	_check_rect("round", true)
	main.hint_txt = "TEST HINT"
	var t0 = main.play_time
	for s in SIZES.slice(0, 2):
		main.hud.size = s
		main.hud.queue_redraw()
		for i in range(3):
			await process_frame
	main.hud.size = SIZES[0]
	if main.paused or main.state != "play":
		_fail("the hint paused or ended the round (state %s)" % main.state)
	if main.play_time <= t0:
		_fail("the round did not keep running while the hint was showing")
	main.force_captured = false


func _finish() -> void:
	if problems.is_empty():
		print("hint_line_check: the hint line shows, fades, is shown once and never blocks input")
		quit(0)
	else:
		for line in problems.slice(0, 12):
			printerr("hint_line_check: " + line)
		quit(1)
