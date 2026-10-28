extends SceneTree
# Checks how the six real first-run hints are DRAWN on the screen they belong to (README early alpha E1.5, `hint_rect`
# and `hint_y` in scripts/hud.gd), at two window sizes (1280x720 and 1920x1080) and a small one (800x450):
#   - the hint is triggered the real way (a new run for the map, then the upgrade screen, the shop, the rest screen, a cache
#     in range and the extraction point opening), so the line is the real text of that trigger,
#   - its strip is inside the window, centred, and does not touch anything the screen draws: the cards, the CONTINUE and
#     REROLL buttons, the perks lines, the map nodes and the info panel, the titles and the bottom prompts, and in a round
#     the dash bar and the FREE DARTS line,
#   - the screen draws with the line showing, at every size.
# Headless Godot cannot draw, so the places of the things on a screen come from the same functions the HUD draws with
# (`card_rect`, `continue_rect`, `map_node_pos`, ...) and from the fractions of the window height written in
# `_draw_*` (listed below as bands). The flags and the HINTS switch have their own checks (hint_flags, hint_setting,
# hint_triggers), and the line itself (timing, fade, replacing) has hint_line.
# Showing a hint saves `user://settings.cfg`, so the check keeps the real file and puts it back at the end.
# Run from the project folder:
#   godot --headless --path . --script res://tools/hint_screens_check.gd
# or with `python tools/run_checks.py hint_screens`. Exits with status 1 and prints the problems when a check fails.

const SettingsScript = preload("res://scripts/settings.gd")
const SETTINGS_PATH = "user://settings.cfg"
const SEED = 0x2468ACEB
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
	await _run()
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


# a full-width horizontal band round a line of text drawn at `y` (a baseline, in window pixels): `up` above, `down` below
func _band(s: Vector2, y: float, up: float, down: float) -> Rect2:
	return Rect2(0.0, y - up, s.x, up + down)


# everything the screen draws near the bottom or the middle that the strip must stay off, as [name, Rect2]
func _occupied(screen: String, s: Vector2) -> Array:
	var hud = main.hud
	var k = s.y / 720.0
	var h = s.y
	var out = []
	if screen == "map":
		var floors = main.run_map["floors"]
		for f in range(floors.size()):
			for i in range(floors[f].size()):
				var p = hud.map_node_pos(f, i)
				# a node is a circle of 20 k, with a ring of up to 9 k round it when it is the picked choice
				out.append(
					[
						"map node %d.%d" % [f, i],
						Rect2(p - Vector2(29.0, 29.0) * k, Vector2(58.0, 58.0) * k)
					]
				)
		var px = hud.map_info_x()
		out.append(["map info panel", Rect2(px - 4.0 * k, h * 0.28 - 20.0 * k, s.x - px, h * 0.42)])
		out.append(["map title", _band(s, h * 0.09, 36.0 * k, 8.0 * k)])
		out.append(["map arena line", _band(s, h * 0.135, 16.0 * k, 5.0 * k)])
		out.append(["map bottom prompt", _band(s, hud.map_prompt_y(k), 12.0 * k, 4.0 * k)])
	elif screen == "upgrade" or screen == "rest" or screen == "shop":
		var n = main.offers.size()
		if screen == "rest":
			n = main.rest_opts.size()
		elif screen == "shop":
			n = main.shop_items.size()
		for i in range(n):
			out.append(["card %d" % i, hud.card_rect(i, n)])
		if screen == "upgrade":
			out.append(["upgrade title", _band(s, h * 0.13, 32.0 * k, 8.0 * k)])
			out.append(["upgrade prompt", _band(s, h * 0.8, 16.0 * k, 5.0 * k)])
		elif screen == "rest":
			out.append(["rest title", _band(s, h * 0.13, 32.0 * k, 8.0 * k)])
			out.append(["rest hearts line", _band(s, h * 0.19, 18.0 * k, 6.0 * k)])
			out.append(["rest prompt", _band(s, h * 0.8, 16.0 * k, 5.0 * k)])
		else:
			out.append(["shop title", _band(s, h * 0.11, 32.0 * k, 8.0 * k)])
			out.append(["shop cash line", _band(s, h * 0.17, 18.0 * k, 6.0 * k)])
			out.append(["shop perks line", _band(s, h * 0.72, 12.0 * k, 4.0 * k)])
			out.append(["shop duos line", _band(s, h * 0.76, 12.0 * k, 4.0 * k)])
			out.append(["shop CONTINUE button", hud.continue_rect()])
			out.append(["shop REROLL button", hud.reroll_rect()])
			out.append(["shop bottom prompt", _band(s, h * 0.93, 12.0 * k, 4.0 * k)])
	else:
		# in a round: the dash bar and the FREE DARTS line along the bottom edge (see hint_line_check)
		out.append(["bottom HUD", Rect2(0.0, s.y - 96.0 * k, s.x, 96.0 * k)])
	return out


func _check_strip(screen: String, id: String, s: Vector2) -> void:
	var hud = main.hud
	hud.size = s
	var k = s.y / 720.0
	main.hint_t0 = main.time  # the line is as fresh as it can be
	var label = "%s hint on the %s screen at %dx%d" % [id, screen, int(s.x), int(s.y)]
	if main.hint_txt != str(SettingsScript.HINT_TEXTS[id]):
		_fail("%s: the line on screen is '%s'" % [label, main.hint_txt])
		return
	if main.settings.hint_alpha() <= 0.0:
		_fail("%s: the line is not visible" % label)
	var r = hud.hint_rect(k)
	if r.size.x <= 0.0 or r.size.y <= 0.0:
		_fail("%s: the strip is empty" % label)
		return
	if r.position.x < 0.0 or r.position.y < 0.0 or r.end.x > s.x or r.end.y > s.y:
		_fail("%s: the strip %s is not inside the window" % [label, str(r)])
	if absf((r.position.x + r.end.x) * 0.5 - s.x * 0.5) > 1.0:
		_fail("%s: the strip is not centred" % label)
	for item in _occupied(screen, s):
		if r.intersects(item[1]):
			_fail("%s: the strip %s covers the %s %s" % [label, str(r), item[0], str(item[1])])
	# draw the screen with the line up
	hud.queue_redraw()


func _check_all_sizes(screen: String, id: String) -> void:
	for s in SIZES:
		_check_strip(screen, id, s)
		await process_frame
	main.hud.size = SIZES[0]


func _run() -> void:
	_remove_file()
	main.hints_seen = {}
	main.hints_on = true
	main.settings.load_settings()
	main.hint_txt = ""
	main.start_game(false, SEED)
	for i in range(3):
		await process_frame
	if main.state != "map":
		_fail("a new run did not open the map (state %s)" % main.state)
		return
	await _check_all_sizes("map", "map")

	main.shop_sys.show_upgrade()
	if main.state != "upgrade":
		_fail("the upgrade screen did not open (state %s)" % main.state)
	else:
		await _check_all_sizes("upgrade", "upgrade")

	main.shop_sys.enter_shop()
	if main.state != "shop":
		_fail("the shop did not open (state %s)" % main.state)
	else:
		await _check_all_sizes("shop", "shop")

	main.shop_sys.enter_rest()
	if main.state != "rest":
		_fail("the rest screen did not open (state %s)" % main.state)
	else:
		await _check_all_sizes("rest", "rest")

	# a round (headless Godot cannot capture the mouse, so the test hook plays the round)
	main.enter_map()
	main.pick_node(0)
	main.force_captured = true
	await process_frame
	var o = main.objective_sys
	if main.state != "play" or not o.has_goal() or o.caches.is_empty():
		_fail("could not start a generated round with caches (state %s)" % main.state)
		main.force_captured = false
		return
	main.player.position = o.caches[0]["pos"] + Vector3(o.SENSE_RANGE - 5.0, 0.0, 0.0)
	o.update(0.05)
	await _check_all_sizes("round", "cache")
	o.begin_extraction()
	await _check_all_sizes("round", "extract")
	main.force_captured = false


func _finish() -> void:
	if problems.is_empty():
		print(
			"hint_screens_check: the six hints are drawn clear of what their screens show, at three window sizes"
		)
		quit(0)
	else:
		for line in problems.slice(0, 12):
			printerr("hint_screens_check: " + line)
		quit(1)
