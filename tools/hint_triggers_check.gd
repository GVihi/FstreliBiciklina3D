extends SceneTree
# Checks the six first-run hint triggers (README early alpha E1.3: `HINT_TEXTS` and `trigger_hint` in scripts/settings.gd,
# the calls in scripts/main.gd, scripts/shop.gd and scripts/objective.gd):
#   - every one of the six ids has a text, each text fits on one line (HINT_MAX_CHARS) and none is shared, and the
#     real texts stay inside the window at three window sizes,
#   - the map screen, the upgrade screen, the shop, the rest screen, the extraction point opening and the first cache
#     within sense range each put their own line up the first time, mark only their own flag, and save it,
#   - a trigger that comes up a second time (also after the flags were loaded again, as on the next start of the game)
#     shows nothing, and does not replace a line that is on screen,
#   - a cache outside the sense range shows nothing, and the roundabout (no caches, no extraction point) never shows
#     the cache or the extraction hint.
# Showing a hint saves `user://settings.cfg`, so the check keeps the real file and puts it back at the end.
# Run from the project folder:
#   godot --headless --path . --script res://tools/hint_triggers_check.gd
# or with `python tools/run_checks.py hint_triggers`. Exits with status 1 and prints the problems when a check fails.

const SettingsScript = preload("res://scripts/settings.gd")
const SETTINGS_PATH = "user://settings.cfg"
const SEED = 0x2468ACE7
const SIZES = [Vector2(1280.0, 720.0), Vector2(1920.0, 1080.0), Vector2(800.0, 450.0)]

var problems = []
var kept = PackedByteArray()
var had_file = false


func _initialize() -> void:
	_keep_user_files()
	_check_texts()
	var main = await _make_main(true)
	_check_texts_fit(main)
	await _check_triggers(main)
	_check_second_start(main)
	_drop(main)
	await _check_roundabout()
	_restore_user_files()
	_finish()


func _fail(text: String) -> void:
	if problems.size() < 40:
		problems.append(text)


func _make_main(generated: bool):
	var m = load("res://main.tscn").instantiate()
	m.generated_arena = generated
	root.add_child(m)
	for i in range(3):
		await process_frame
	return m


func _drop(m) -> void:
	root.remove_child(m)
	m.free()


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
func _fresh(m) -> void:
	_remove_file()
	m.hints_seen = {}
	m.settings.load_settings()
	m.hint_txt = ""
	m.hint_t0 = -100.0


# the ids whose flag is set
func _seen_ids(m) -> Array:
	var out = []
	for id in SettingsScript.HINT_IDS:
		if m.settings.hint_seen(id):
			out.append(id)
	return out


# the trigger `id` just came up: its line is on screen and its flag is the only one that changed
func _expect_shown(m, id: String, before: Array, what: String) -> void:
	var want = str(SettingsScript.HINT_TEXTS.get(id, ""))
	if m.hint_txt != want:
		_fail("%s: the hint line is '%s', not the '%s' text" % [what, m.hint_txt, id])
	if m.settings.hint_alpha() <= 0.0:
		_fail("%s: the hint is not visible (alpha 0)" % what)
	var after = _seen_ids(m)
	var expected = before.duplicate()
	expected.append(id)
	expected.sort()
	after.sort()
	if after != expected:
		_fail("%s: the seen flags are %s, expected %s" % [what, str(after), str(expected)])
	var cf = ConfigFile.new()
	if cf.load(SETTINGS_PATH) != OK or cf.get_value("hints", id, false) != true:
		_fail("%s: [hints] %s = true was not saved" % [what, id])


func _check_texts() -> void:
	var ids = SettingsScript.HINT_IDS
	var texts = SettingsScript.HINT_TEXTS
	if ids.size() != 6:
		_fail("HINT_IDS has %d ids, E1.3 needs six" % ids.size())
	var used = {}
	for id in ids:
		if not texts.has(id):
			_fail("no HINT_TEXTS line for '%s'" % id)
			continue
		var text = str(texts[id])
		if text.strip_edges() == "":
			_fail("the '%s' hint text is empty" % id)
		if text.length() > SettingsScript.HINT_MAX_CHARS:
			_fail(
				(
					"the '%s' hint is %d characters, the limit is %d"
					% [id, text.length(), SettingsScript.HINT_MAX_CHARS]
				)
			)
		if text.contains("\n"):
			_fail("the '%s' hint has a line break, a hint is one line" % id)
		if used.has(text):
			_fail("the '%s' and '%s' hints have the same text" % [id, used[text]])
		used[text] = id
	for id in texts.keys():
		if not ids.has(id):
			_fail("HINT_TEXTS has a line for '%s', which is not one of the six ids" % id)


# the real lines stay inside the window and the font stays readable, at three window sizes
func _check_texts_fit(m) -> void:
	for id in SettingsScript.HINT_IDS:
		m.hint_txt = str(SettingsScript.HINT_TEXTS.get(id, ""))
		for s in SIZES:
			m.hud.size = s
			var k = s.y / 720.0
			var r = m.hud.hint_rect(k)
			var label = "the '%s' hint at %dx%d" % [id, int(s.x), int(s.y)]
			if r.size.x <= 0.0:
				_fail("%s: the strip is empty" % label)
				continue
			if r.position.x < 0.0 or r.end.x > s.x or r.end.y > s.y:
				_fail("%s: the strip %s is not inside the window" % [label, str(r)])
			if m.hud.hint_fs(k) < 9:
				_fail("%s: the font shrank to %d px" % [label, m.hud.hint_fs(k)])
	m.hud.size = SIZES[0]
	m.hint_txt = ""


func _check_triggers(m) -> void:
	_fresh(m)
	if not _seen_ids(m).is_empty():
		_fail("a fresh game starts with seen flags: %s" % str(_seen_ids(m)))

	# map screen: a new run opens it
	m.start_game(false, SEED)
	for i in range(3):
		await process_frame
	if m.state != "map":
		_fail("a new run did not open the map (state %s)" % m.state)
		return
	_expect_shown(m, "map", [], "map screen")
	# the same screen again shows nothing new and keeps the line that is up
	m.hint_txt = "OTHER LINE"
	m.enter_map()
	if m.hint_txt != "OTHER LINE":
		_fail("map screen, second time: the line on screen was replaced (got '%s')" % m.hint_txt)

	# upgrade screen with nothing to pick (every upgrade bought out): the game goes on, so no hint and no flag
	m.hint_txt = ""
	var all_upgrades = m.UPGRADES
	m.UPGRADES = []
	m.shop_sys.show_upgrade()
	m.UPGRADES = all_upgrades
	if m.settings.hint_seen("upgrade") or m.hint_txt != "":
		_fail(
			(
				"an upgrade screen with no offers showed or used up the upgrade hint (line '%s')"
				% m.hint_txt
			)
		)
	m.enter_map()

	# upgrade screen
	m.hint_txt = ""
	m.shop_sys.show_upgrade()
	if m.state != "upgrade" or m.offers.is_empty():
		_fail("the upgrade screen did not open with offers (state %s)" % m.state)
	else:
		_expect_shown(m, "upgrade", ["map"], "upgrade screen")
		m.hint_txt = "OTHER LINE"
		m.shop_sys.show_upgrade()
		if m.hint_txt != "OTHER LINE":
			_fail("upgrade screen, second time: the line on screen was replaced")

	# shop
	m.hint_txt = ""
	m.shop_sys.enter_shop()
	if m.state != "shop":
		_fail("the shop did not open (state %s)" % m.state)
	else:
		_expect_shown(m, "shop", ["map", "upgrade"], "shop")
		m.hint_txt = "OTHER LINE"
		m.shop_sys.enter_shop()
		if m.hint_txt != "OTHER LINE":
			_fail("shop, second time: the line on screen was replaced")

	# rest screen
	m.hint_txt = ""
	m.shop_sys.enter_rest()
	if m.state != "rest":
		_fail("the rest screen did not open (state %s)" % m.state)
	else:
		_expect_shown(m, "rest", ["map", "upgrade", "shop"], "rest screen")
		m.hint_txt = "OTHER LINE"
		m.shop_sys.enter_rest()
		if m.hint_txt != "OTHER LINE":
			_fail("rest screen, second time: the line on screen was replaced")

	# a round on the generated arena: the cache and the extraction point
	m.enter_map()
	m.pick_node(0)
	var o = m.objective_sys
	if m.state != "play" or not o.has_goal() or o.caches.is_empty():
		_fail("could not start a generated round with caches (state %s)" % m.state)
		return
	m.hint_txt = ""
	# far from every cache: nothing
	m.player.position = Vector3(o.SENSE_RANGE * 40.0, 0.0, o.SENSE_RANGE * 40.0)
	o.update(0.05)
	if m.settings.hint_seen("cache") or m.hint_txt != "":
		_fail("a cache out of sense range showed the cache hint (line '%s')" % m.hint_txt)
	# just outside the sense range of the first cache, and still far from the others
	var c0: Vector3 = o.caches[0]["pos"]
	m.player.position = c0 + Vector3(o.SENSE_RANGE + 2.0, 0.0, 0.0)
	var near_other = false
	for i in range(1, o.caches.size()):
		if o.dist_to(o.caches[i]["pos"]) < o.SENSE_RANGE:
			near_other = true
	if not near_other:
		o.update(0.05)
		if m.settings.hint_seen("cache"):
			_fail(
				(
					"a cache %.0f m away (sense range %.0f) showed the cache hint"
					% [o.SENSE_RANGE + 2.0, o.SENSE_RANGE]
				)
			)
	# inside the sense range, not yet on the cache
	m.hint_txt = ""
	m.player.position = c0 + Vector3(o.SENSE_RANGE - 5.0, 0.0, 0.0)
	o.update(0.05)
	if o.taken != 0:
		_fail("the player was 40 m from a cache and it was taken")
	_expect_shown(m, "cache", ["map", "upgrade", "shop", "rest"], "cache in sense range")
	# a second cache, or the same one again: nothing
	m.hint_txt = "OTHER LINE"
	m.player.position = c0 + Vector3(o.SENSE_RANGE - 10.0, 0.0, 0.0)
	o.update(0.05)
	if m.hint_txt != "OTHER LINE":
		_fail("cache, second time: the line on screen was replaced (got '%s')" % m.hint_txt)

	# the extraction point opens
	if o.extracting:
		_fail("the extraction point was open before any rider was down")
	m.hint_txt = ""
	o.begin_extraction()
	if not o.extracting:
		_fail("begin_extraction did not open the extraction point")
	_expect_shown(
		m, "extract", ["map", "upgrade", "shop", "rest", "cache"], "extraction point opening"
	)
	# opening it again (a second round) shows nothing new
	o.extracting = false
	m.hint_txt = "OTHER LINE"
	o.begin_extraction()
	if m.hint_txt != "OTHER LINE":
		_fail("extraction, second time: the line on screen was replaced (got '%s')" % m.hint_txt)
	if _seen_ids(m).size() != 6:
		_fail("after all six triggers %d flags are set, not 6" % _seen_ids(m).size())


# the next start of the game: the flags come back from the file and no trigger shows a line again
func _check_second_start(m) -> void:
	m.hints_seen = {}
	m.hint_txt = ""
	m.settings.load_settings()
	if _seen_ids(m).size() != 6:
		_fail("the saved flags did not load again (%s)" % str(_seen_ids(m)))
	m.enter_map()
	m.shop_sys.show_upgrade()
	m.shop_sys.enter_shop()
	m.shop_sys.enter_rest()
	if m.hint_txt != "":
		_fail("after loading the flags a trigger still showed a line ('%s')" % m.hint_txt)


# the roundabout has no caches and no extraction point, so those two hints never come up there
func _check_roundabout() -> void:
	var m = await _make_main(false)
	_fresh(m)
	m.start_game(false, SEED)
	for i in range(3):
		await process_frame
	if m.state == "map":
		m.pick_node(0)
	var o = m.objective_sys
	if o.enabled():
		_fail("the roundabout has objectives (the check cannot test what it means to)")
	if m.state == "play":
		o.update(0.05)
		o.begin_extraction()
	if m.settings.hint_seen("cache") or m.settings.hint_seen("extract"):
		_fail("the roundabout showed the cache or extraction hint")
	_drop(m)


func _finish() -> void:
	if problems.is_empty():
		print(
			"hint_triggers_check: the six hints each show once, on their own trigger, and are saved"
		)
		quit(0)
	else:
		for line in problems.slice(0, 12):
			printerr("hint_triggers_check: " + line)
		quit(1)
