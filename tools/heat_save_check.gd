extends SceneTree
# Checks saving the chosen Heat modifiers and showing them (README Milestone B, "Difficulty Scaling", chunk H2.5; design in
# docs/HEAT.md):
#   - `Heat.load_saved`, the one rule both save files read a set by: no set, or something that is not a set, reads as the preset
#     of the saved level; a set is made legal; a set that is a preset is kept as its level; one of the player's own is kept and
#     wins over the level beside it; a set worth more than the top level of the ladder is ignored. Every one of the 432 sets
#     goes through it and the Heat number always comes out as what the set is worth,
#   - `settings.cfg` keeps the set of the player's own (`heat_set` under `[game]`) and nothing for a preset, an old file with
#     only a level reads as the preset of that level, and a hand-edited file never gives a set that is not legal,
#   - `run.json` keeps it the same way (`heat_set`): CONTINUE plays the saved set (not the preset of its level), a run saved
#     before H2.5 or with a preset plays by level, a Daily Run is always Heat 0, and bad values never stop a run from loading,
#   - the modifiers are written out (`Heat.modifiers_line`: names and ranks, nothing at Heat 0), and the run bar, the pause menu
#     and the run summary draw them at three window shapes.
# It uses its own run file (user://heat_save_check.json) and puts the real settings file back.
# Run from the project folder:
#   godot --headless --path . --script res://tools/heat_save_check.gd
# or: python tools/run_checks.py heat_save
# Exits with status 1 and prints the problems when a check fails.

const RunSave = preload("res://scripts/run_save.gd")
const SETTINGS_PATH = "user://settings.cfg"
const TEST_PATH = "user://heat_save_check.json"
const SEED = 0x1234ABCD

var problems = []
var main
var kept_settings = PackedByteArray()
var had_settings = false


func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	for i in range(3):
		await process_frame
	_keep_settings()
	main.go_to_title()
	main.meta.heat_open = main.heat_sys.top_level()  # the saves are the subject here, so every level is open
	main.heat = 0
	main.heat_ranks = {}
	_check_load_saved()
	_check_every_set()
	_check_settings_file()
	_check_run_save()
	_check_words()
	await _check_drawing()
	main.go_to_title()
	main.heat = 0
	main.heat_ranks = {}
	main.heat_sys.clear_set()
	_restore_settings()
	_finish()


# ---------------------------------------------------------------- the rule both files read a set by (heat.gd)


func _check_load_saved() -> void:
	var h = main.heat_sys
	var top = h.top_level()
	# no set, or something that is not a set, reads as the preset of the saved level (kept to the levels there are)
	for raw in [null, "swift", 5, [1, 2], true, {}]:
		for level in [0, 1, 3, top, 99, -4]:
			var kept = h.load_saved(level, raw)
			if kept["heat"] != h.clamp_level(level) or not kept["ranks"].is_empty():
				_fail(
					(
						"load_saved(%d, %s) gave %s, expected the preset of level %d"
						% [level, str(raw), str(kept), h.clamp_level(level)]
					)
				)
	# a set that is a preset is kept as its level, whatever level stood beside it (preset 0 has no ranks: that is "no set" above)
	for lv in range(1, top + 1):
		var kept = h.load_saved(top - lv, h.preset_ranks(lv))
		if kept["heat"] != lv or not kept["ranks"].is_empty():
			_fail("the ranks of preset %d did not load as that level: %s" % [lv, str(kept)])
	# a set of the player's own is kept and wins over the level beside it
	var own = h.load_saved(top, {"swift": 2})
	if own["heat"] != 2 or own["ranks"] != {"swift": 2}:
		_fail(
			"{swift 2} beside level %d loaded as %s, expected Heat 2 and the set" % [top, str(own)]
		)
	# the whole numbers of a JSON file are floats when they are read back
	own = h.load_saved(0, {"swift": 2.0, "crowd": 1.0})
	if own["heat"] != 3 or own["ranks"] != {"swift": 2, "crowd": 1}:
		_fail("a set written as floats loaded as %s" % str(own))
	# unknown ids are dropped, a rank past the top rank is the top rank
	own = h.load_saved(0, {"no_such_modifier": 3, "swift": 2})
	if own["heat"] != 2 or own["ranks"] != {"swift": 2}:
		_fail("an unknown id was not dropped: %s" % str(own))
	own = h.load_saved(3, {"no_such_modifier": 3})
	if own["heat"] != 3 or not own["ranks"].is_empty():
		_fail("a set of only unknown ids should read as the saved level: %s" % str(own))
	own = h.load_saved(0, {"swift": 9})
	if own["heat"] != 4 or own["ranks"] != {"swift": 3}:
		_fail("rank 9 of swift should be the top rank, 3: %s" % str(own))
	# ranks that are not whole numbers above 0 are not ranks
	for bad in [{"swift": "2"}, {"swift": -1}, {"swift": null}, {"swift": 0}, {"swift": [2]}]:
		own = h.load_saved(2, bad)
		if own["heat"] != 2 or not own["ranks"].is_empty():
			_fail("%s should read as the saved level 2: %s" % [str(bad), str(own)])
	# a clash is resolved the way clean_set does it (the second named goes down), and what comes out is legal
	own = h.load_saved(0, {"lives": 2, "crowd": 2})
	if own["ranks"] != {"lives": 2, "crowd": 1} or own["heat"] != 5 or not h.is_legal(own["ranks"]):
		_fail("a set with a clash loaded as %s" % str(own))
	# a set worth more than the top level cannot be held (the page does not offer it): the saved level is used
	own = h.load_saved(2, {"swift": 3, "crowd": 2, "lives": 1, "tough": 1})
	if own["heat"] != 2 or not own["ranks"].is_empty():
		_fail("a set worth more than the top level should be ignored: %s" % str(own))
	# the set that comes in is not changed
	var raw = {"swift": 9, "lives": 2, "crowd": 2}
	h.load_saved(0, raw)
	if raw != {"swift": 9, "lives": 2, "crowd": 2}:
		_fail("load_saved changed the set that was passed in: %s" % str(raw))


# every set of ranks (432) as a file might hold it: the Heat comes out as what the set is worth, and the game then plays what
# the file said
func _check_every_set() -> void:
	var h = main.heat_sys
	var top = h.top_level()
	var sets = []
	_walk_sets(h.modifier_ids(), 0, {}, sets)
	if sets.size() != 432:
		_fail("expected 432 sets of ranks, found %d" % sets.size())
	var kept_own = 0
	var kept_preset = 0
	var ignored = 0
	for s in sets:
		var legal = h.clean_set(s)
		var total = h.total_points(legal)
		var kept = h.load_saved(0, s)
		if legal.is_empty() or total > top:
			ignored += 1
			if kept["heat"] != 0 or not kept["ranks"].is_empty():
				_fail(
					"%s should be ignored and read as the saved level 0: %s" % [str(s), str(kept)]
				)
			continue
		if kept["heat"] != total:
			_fail("%s is worth %d but loaded as Heat %d" % [str(s), total, kept["heat"]])
			continue
		var preset = h.preset_matching(legal)
		if preset >= 0:
			kept_preset += 1
			if not kept["ranks"].is_empty() or preset != total:
				_fail(
					(
						"%s is preset %d, which should load as a level: %s"
						% [str(s), preset, str(kept)]
					)
				)
			continue
		kept_own += 1
		if kept["ranks"] != legal or not h.is_legal(kept["ranks"]):
			_fail("%s did not load as its legal set: %s" % [str(s), str(kept)])
			continue
		# what the game holds after the load plays that set, and its Heat is what the set is worth
		main.heat = kept["heat"]
		main.heat_ranks = kept["ranks"]
		if h.custom_set() != legal or h.played_ranks() != legal:
			_fail("%s loaded but the game does not play it as its own set" % str(s))
		if h.total_points(h.played_ranks()) != main.heat:
			_fail("%s: the Heat of the run is not what its set is worth" % str(s))
	main.heat = 0
	main.heat_ranks = {}
	# a count that proves the walk looked at sets of all three kinds (the presets 1 to top; preset 0 is the empty set, which is ignored)
	if kept_own < 20 or kept_preset != top or ignored < 100:
		_fail(
			(
				"the walk over every set saw %d own sets, %d presets and %d ignored; expected many own sets, %d presets and many ignored"
				% [kept_own, kept_preset, ignored, top]
			)
		)


func _walk_sets(ids: Array, i: int, ranks: Dictionary, out: Array) -> void:
	if i == ids.size():
		out.append(ranks.duplicate())
		return
	for r in range(main.heat_sys.max_rank(ids[i]) + 1):
		ranks[ids[i]] = r
		_walk_sets(ids, i + 1, ranks, out)
	ranks.erase(ids[i])


# ---------------------------------------------------------------- settings.cfg


func _keep_settings() -> void:
	had_settings = FileAccess.file_exists(SETTINGS_PATH)
	if had_settings:
		kept_settings = FileAccess.get_file_as_bytes(SETTINGS_PATH)


func _restore_settings() -> void:
	if had_settings:
		var f = FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
		if f:
			f.store_buffer(kept_settings)
			f.close()
	elif FileAccess.file_exists(SETTINGS_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_PATH))
	main.settings.load_settings()


func _read_cfg() -> ConfigFile:
	var cf = ConfigFile.new()
	cf.load(SETTINGS_PATH)
	return cf


# a settings file with only these keys under [game]
func _write_cfg(values: Dictionary) -> void:
	var cf = ConfigFile.new()
	for key in values:
		cf.set_value("game", key, values[key])
	cf.save(SETTINGS_PATH)


# puts a set into memory that the next load has to replace, then loads the settings file
func _load_over_leftovers() -> void:
	main.heat = 2
	main.heat_ranks = {"stingy": 2}
	main.settings.load_settings()


func _check_settings_file() -> void:
	var h = main.heat_sys
	# a set of the player's own is written next to its level and read back
	main.heat = 3
	main.heat_ranks = {"swift": 2, "crowd": 1}
	main.settings.save_settings()
	var cf = _read_cfg()
	var saved = cf.get_value("game", "heat_set", null)
	if int(cf.get_value("game", "heat", -1)) != 3 or typeof(saved) != TYPE_DICTIONARY:
		_fail(
			(
				"settings.cfg does not hold the level and the set: heat %s, heat_set %s"
				% [str(cf.get_value("game", "heat", null)), str(saved)]
			)
		)
	elif saved != {"swift": 2, "crowd": 1}:
		_fail("settings.cfg holds %s, expected {swift 2, crowd 1}" % str(saved))
	main.heat = 0
	main.heat_ranks = {}
	main.settings.load_settings()
	if main.heat != 3 or main.heat_ranks != {"swift": 2, "crowd": 1}:
		_fail(
			(
				"the set did not come back from settings.cfg: heat %d, set %s"
				% [main.heat, str(main.heat_ranks)]
			)
		)
	if h.custom_set() != {"swift": 2, "crowd": 1}:
		_fail("a set read from settings.cfg is not the one the game plays")
	# a preset writes no set (and drops an older one: the file is written from scratch)
	main.heat = 3
	main.heat_ranks = {}
	main.settings.save_settings()
	cf = _read_cfg()
	if cf.has_section_key("game", "heat_set"):
		_fail("a preset was saved with a heat_set: %s" % str(cf.get_value("game", "heat_set")))
	main.heat_ranks = {"stingy": 2}
	main.heat = 0
	main.settings.load_settings()
	if main.heat != 3 or not main.heat_ranks.is_empty():
		_fail(
			(
				"a file with only a level should read as that preset: heat %d, set %s"
				% [main.heat, str(main.heat_ranks)]
			)
		)
	# a set that is in memory but is not what the game plays (its Heat does not match) is not written
	main.heat = 1
	main.heat_ranks = {"swift": 2}
	main.settings.save_settings()
	if _read_cfg().has_section_key("game", "heat_set"):
		_fail("a set that is worth more than the level of the run was written to settings.cfg")
	# an old file, written before H2.5: only a level
	_write_cfg({"heat": 4})
	_load_over_leftovers()
	if main.heat != 4 or not main.heat_ranks.is_empty() or h.played_ranks() != h.preset_ranks(4):
		_fail(
			(
				"an old settings.cfg with Heat 4 should play as the preset of Heat 4: heat %d, set %s"
				% [main.heat, str(main.heat_ranks)]
			)
		)
	if h.modifiers_line() != "SWIFT RIDERS 1, CROWD 1, FEWER LIVES 1, TOUGH 1":
		_fail('an old file with Heat 4 writes its modifiers as "%s"' % h.modifiers_line())
	# a hand-edited set that is not a set never gives one
	for bad in ["swift", 5, [1], {"swift": "x"}, {"no_such_modifier": 2}, {}]:
		_write_cfg({"heat": 2, "heat_set": bad})
		_load_over_leftovers()
		if main.heat != 2 or not main.heat_ranks.is_empty():
			_fail(
				(
					"heat_set %s should read as the preset of Heat 2: heat %d, set %s"
					% [str(bad), main.heat, str(main.heat_ranks)]
				)
			)
	# the set wins over a level that does not match it, and a set that cannot be held is ignored
	_write_cfg({"heat": 5, "heat_set": {"swift": 2}})
	_load_over_leftovers()
	if main.heat != 2 or main.heat_ranks != {"swift": 2}:
		_fail(
			(
				"{swift 2} beside Heat 5 should load as Heat 2 with the set: heat %d, set %s"
				% [main.heat, str(main.heat_ranks)]
			)
		)
	_write_cfg({"heat": 1, "heat_set": {"swift": 3, "crowd": 2, "lives": 1, "tough": 1}})
	_load_over_leftovers()
	if main.heat != 1 or not main.heat_ranks.is_empty():
		_fail(
			(
				"a set worth more than the top level should be ignored: heat %d, set %s"
				% [main.heat, str(main.heat_ranks)]
			)
		)
	main.heat = 0
	main.heat_ranks = {}


# ---------------------------------------------------------------- run.json


func _remove_test_files() -> void:
	for tag in ["", ".bad.bak", ".v2.bak", ".replaced.bak"]:
		var p = TEST_PATH + tag
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))


# the game as it is when it has just been started: no run, nothing of a set in memory
func _fresh_start() -> void:
	main.reset_run()
	main.heat_sys.clear_set()
	main.own_heat_set_played = false
	main.heat = 0
	main.heat_ranks = {}


func _continue_saved(why: String) -> bool:
	main.refresh_saved_run()
	if main.saved_run.is_empty():
		_fail("%s: the saved run was not loaded back" % why)
		return false
	main.continue_run()
	return true


func _check_run_save() -> void:
	var h = main.heat_sys
	RunSave.test_path = TEST_PATH
	_remove_test_files()
	main.run_save_enabled = true
	# a run played with a set of the player's own is saved with it and continues with it
	main.heat = 3
	main.heat_ranks = {"swift": 2, "crowd": 1}
	main.start_game(false, SEED)
	if not h.has_set():
		_fail("the run did not start with the set, so there is nothing to save")
	var data = RunSave.load_file()
	if data.is_empty():
		_fail("starting a run did not write a checkpoint")
	else:
		if data["heat"] != 3 or data["heat_set"] != {"swift": 2, "crowd": 1}:
			_fail(
				(
					"the checkpoint holds heat %s and set %s"
					% [str(data["heat"]), str(data["heat_set"])]
				)
			)
	var text = FileAccess.get_file_as_string(TEST_PATH)
	if not text.contains("heat_set"):
		_fail("run.json has no heat_set key")
	_fresh_start()
	if _continue_saved("a run with a set of its own"):
		if main.heat != 3 or main.heat_ranks != {"swift": 2, "crowd": 1}:
			_fail(
				(
					"CONTINUE did not bring back the set: heat %d, set %s"
					% [main.heat, str(main.heat_ranks)]
				)
			)
		if not h.has_set() or h.set_points() != 3:
			_fail("CONTINUE did not play the saved set")
		# the set is what plays: the preset of Heat 3 would give 1.10, SWIFT RIDERS rank 2 gives 1.20
		if not is_equal_approx(h.value("rider_speed"), 1.2):
			_fail(
				(
					"after CONTINUE riders ride x%s, expected x1.2 from the saved set"
					% str(h.value("rider_speed"))
				)
			)
		if h.modifiers_line() != "SWIFT RIDERS 2, CROWD 1":
			_fail('after CONTINUE the modifiers read "%s"' % h.modifiers_line())
	# a preset is saved without a set and continues by level
	_fresh_start()
	main.heat = 3
	main.start_game(false, SEED)
	data = RunSave.load_file()
	if data.is_empty() or data["heat"] != 3 or not data["heat_set"].is_empty():
		_fail("a run at preset Heat 3 was saved as %s" % str(data))
	_fresh_start()
	main.heat_ranks = {"stingy": 2}  # a leftover that CONTINUE has to replace
	if _continue_saved("a run at a preset"):
		if main.heat != 3 or not main.heat_ranks.is_empty() or h.has_set():
			_fail(
				(
					"a preset run continued with a set: heat %d, set %s"
					% [main.heat, str(main.heat_ranks)]
				)
			)
		if not is_equal_approx(h.value("rider_speed"), 1.1):
			_fail(
				(
					"a preset run continued with riders at x%s, expected x1.1"
					% str(h.value("rider_speed"))
				)
			)
		if h.modifiers_line() != "SWIFT RIDERS 1, CROWD 1, FEWER LIVES 1":
			_fail('a preset run continued with the modifiers "%s"' % h.modifiers_line())
	# a run saved before H2.5 has a level and no set: it plays as the preset of its level
	_fresh_start()
	main.heat = 4
	main.start_game(false, SEED)
	var raw = RunSave.capture(main)
	raw.erase("heat_set")
	RunSave.write_file(raw)
	data = RunSave.load_file()
	if data.is_empty() or data["heat"] != 4 or not data["heat_set"].is_empty():
		_fail("a run saved before H2.5 loaded as %s" % str(data))
	_fresh_start()
	main.heat_ranks = {"stingy": 2}
	if _continue_saved("a run saved before H2.5"):
		if main.heat != 4 or not main.heat_ranks.is_empty() or h.has_set():
			_fail(
				(
					"an old run did not continue as preset 4: heat %d, set %s"
					% [main.heat, str(main.heat_ranks)]
				)
			)
		if h.played_ranks() != h.preset_ranks(4):
			_fail("an old run at Heat 4 does not play the ranks of preset 4")
	# a Daily Run is Heat 0 for everybody, whatever the file says
	raw = RunSave.capture(main)
	raw["daily"] = true
	raw["heat"] = 3
	raw["heat_set"] = {"swift": 2}
	RunSave.write_file(raw)
	data = RunSave.load_file()
	if data.is_empty() or data["heat"] != 0 or not data["heat_set"].is_empty():
		_fail(
			(
				"a saved Daily Run with Heat 3 and a set loaded as heat %s, set %s"
				% [str(data.get("heat")), str(data.get("heat_set"))]
			)
		)
	# bad values never stop a run from loading, and what is kept is plain data (text ids, whole ranks 1 to 5, at most 20)
	var many = {}
	for i in range(30):
		many["modifier_%d" % i] = 1
	for bad in [
		"swift",
		5,
		[1, 2],
		null,
		{"swift": "x"},
		{"swift": -2},
		{"swift": 99},
		{"": 1},
		many,
		{"swift": 2.7}
	]:
		raw = RunSave.capture(main)
		raw["daily"] = false
		raw["heat"] = 4
		raw["heat_set"] = bad
		RunSave.write_file(raw)
		data = RunSave.load_file()
		if data.is_empty():
			_fail("a run with heat_set %s did not load" % str(bad))
			continue
		var kept_set = data["heat_set"]
		if kept_set.size() > RunSave.MAX_SAVED_SET:
			_fail("heat_set %s kept %d entries" % [str(bad).left(40), kept_set.size()])
		for id in kept_set:
			if (
				typeof(id) != TYPE_STRING
				or typeof(kept_set[id]) != TYPE_INT
				or kept_set[id] < 1
				or kept_set[id] > 5
			):
				_fail(
					(
						"heat_set %s kept the entry %s: %s"
						% [str(bad).left(40), str(id), str(kept_set[id])]
					)
				)
	# a rank that was cut at load time is cut to the top rank when the run is put into the game
	raw = RunSave.capture(main)
	raw["heat"] = 4
	raw["heat_set"] = {"swift": 99}
	RunSave.write_file(raw)
	data = RunSave.load_file()
	var played = h.load_saved(data["heat"], data["heat_set"])
	if played["ranks"] != {"swift": 3} or played["heat"] != 4:
		_fail("{swift 99} should play as SWIFT RIDERS rank 3 (Heat 4): %s" % str(played))
	main.run_save_enabled = false
	RunSave.test_path = ""
	_remove_test_files()
	_fresh_start()
	main.go_to_title()


# ---------------------------------------------------------------- showing it


func _check_words() -> void:
	var h = main.heat_sys
	var cases = [
		[0, {}, ""],
		[1, {}, "SWIFT RIDERS 1"],
		[3, {}, "SWIFT RIDERS 1, CROWD 1, FEWER LIVES 1"],
		[5, {}, "SWIFT RIDERS 1, CROWD 1, FEWER LIVES 1, TOUGH 1, STINGY 1"],
		[2, {"swift": 2}, "SWIFT RIDERS 2"],
		[3, {"swift": 2, "crowd": 1}, "SWIFT RIDERS 2, CROWD 1"],
		[5, {"swift": 2, "stingy": 3}, "SWIFT RIDERS 2, STINGY 3"],
		# a set that is not worth the Heat of the run is not the one played: the line says the preset of the level
		[2, {"swift": 2, "stingy": 3}, "SWIFT RIDERS 1, CROWD 1"],
	]
	for case in cases:
		main.heat = case[0]
		main.heat_ranks = case[1]
		if h.modifiers_line() != case[2]:
			_fail(
				(
					'Heat %d with set %s writes "%s", expected "%s"'
					% [case[0], str(case[1]), h.modifiers_line(), case[2]]
				)
			)
	# every set that can be held reads as names with ranks (a number in every part, so a player who cannot see colours loses nothing)
	var sets = []
	_walk_sets(h.modifier_ids(), 0, {}, sets)
	for s in sets:
		var kept = h.load_saved(0, s)
		if kept["heat"] == 0 and kept["ranks"].is_empty():
			continue
		main.heat = kept["heat"]
		main.heat_ranks = kept["ranks"]
		var line = h.modifiers_line()
		if line == "":
			_fail("Heat %d wrote no modifiers" % main.heat)
		for part in line.split(", "):
			if not part[part.length() - 1].is_valid_int():
				_fail('"%s" in Heat %d has no rank' % [part, main.heat])
	main.heat = 0
	main.heat_ranks = {}


func _redraw() -> void:
	for i in range(2):
		main.hud.queue_redraw()
		await process_frame


# the run bar, the pause menu and the run summary at several Heat levels and sets, at three window shapes
func _check_drawing() -> void:
	var h = main.heat_sys
	var cases = [
		[0, {}], [3, {}], [5, {}], [3, {"swift": 2, "crowd": 1}], [5, {"swift": 2, "stingy": 3}]
	]
	for case in cases:
		main.heat = case[0]
		main.heat_ranks = case[1]
		for s in [Vector2(1280.0, 720.0), Vector2(1920.0, 1080.0), Vector2(1024.0, 768.0)]:
			main.hud.size = s
			var k = s.y / 720.0
			# the line on the run bar has to leave room for the radar and the score on both sides
			var width = main.hud._text_w(h.modifiers_line(), int(11 * k))
			if width > s.x * 0.45:
				_fail(
					(
						"the modifiers on the run bar are %d px wide on a %s screen"
						% [int(width), str(s)]
					)
				)
			main.state = "play"
			main.paused = false
			await _redraw()
			main.paused = true
			main.pause_page = ""
			await _redraw()
			main.paused = false
			main.state = "over"
			await _redraw()
	main.hud.size = Vector2(1280.0, 720.0)
	main.heat = 0
	main.heat_ranks = {}
	main.go_to_title()


func _finish() -> void:
	if problems.is_empty():
		print(
			"heat_save_check: the chosen modifiers are saved in settings.cfg and run.json, an old file plays as the preset of its level, a bad one never gives a set that is not legal, and the run bar, pause menu and run summary list them"
		)
		quit(0)
	else:
		for line in problems.slice(0, 12):
			printerr("heat_save_check: " + line)
		quit(1)


func _fail(text: String) -> void:
	problems.append(text)
