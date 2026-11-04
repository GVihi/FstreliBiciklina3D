extends SceneTree
# Checks the Heat table (README Milestone B, "Difficulty Scaling", chunk H1.2; design in docs/HEAT.md):
#   - data/heat.json loads: levels 0 to 5 in order, each with a name and a text, level 0 changes nothing,
#   - every level keeps what the level below it does (speed, riders, hearts lost, health, boss health and prices never
#     go down, cash never goes up), and the top level stays inside the caps of the file (riders against the rider counts
#     of data/map_rules.json, hearts, cash),
#   - the lookup: -1 is the level of the run, a level past the end is the top level,
#   - a run starts at Heat 0 (`Main.heat`), and Heat 0 is neutral for every effect,
#   - the level is saved: `heat` in the saved run (an old run without it loads as 0, a bad or too big number is kept to the
#     levels there are, a Daily Run is always 0) and in settings.cfg (a bad value leaves the level as it is), each with a
#     round trip through a real file,
#   - bad data is refused the way data/README.md says: a table that is not valid, a missing level 0, a level 0 that
#     changes something, a gap in the levels, a duplicate, a bad number, a number out of its range.
# The "heat: ..." errors printed while it runs come from the bad data it feeds in on purpose.
# Run from the project folder:
#   godot --headless --path . --script res://tools/heat_check.gd
# or: python tools/run_checks.py heat
# Exits with status 1 and prints the problems when a check fails.

const HeatScript = preload("res://scripts/heat.gd")
const START_HEARTS = 3  # the hearts a run starts with (Main.MAXHEARTS), which hearts_minus is taken from
const EXPECTED_TOP = 5  # the ladder of docs/HEAT.md: H0 to H5
const RunSave = preload("res://scripts/run_save.gd")
const TEST_RUN_PATH = "user://heat_check_run.json"  # the saved run of this check, never the player's run.json
const SETTINGS_PATH = "user://settings.cfg"

var problems = []
var main
var kept_settings = PackedByteArray()
var had_settings = false


func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	for i in range(3):
		await process_frame
	_check_table()
	_check_neutral()
	_check_ladder()
	_check_caps()
	_check_lookup()
	_check_bad_data()
	_keep_settings()
	_check_run_save()
	_check_settings()
	_restore_settings()
	_finish()


func _check_table() -> void:
	var h = main.heat_sys
	if h.top_level() != EXPECTED_TOP:
		_fail("the table has levels 0 to %d, expected 0 to %d" % [h.top_level(), EXPECTED_TOP])
	var names = {}
	for i in range(h.levels.size()):
		var e = h.levels[i]
		if int(e["level"]) != i:
			_fail("entry %d is level %d" % [i, int(e["level"])])
		if str(e["name"]) == "" or str(e["desc"]) == "":
			_fail("level %d has no name or no text" % i)
		if names.has(e["name"]):
			_fail("the name %s is used twice" % e["name"])
		names[e["name"]] = true
		for key in HeatScript.NEUTRAL:
			if not e.has(key):
				_fail("level %d has no %s" % [i, key])


func _check_neutral() -> void:
	var h = main.heat_sys
	if main.heat != 0:
		_fail("a run starts at Heat %d, expected 0" % main.heat)
	if not h.is_neutral(0):
		_fail("level 0 changes something")
	for key in HeatScript.NEUTRAL:
		if not is_equal_approx(h.value(key, 0), float(HeatScript.NEUTRAL[key])):
			_fail(
				"level 0: %s is %s, expected %s" % [key, h.value(key, 0), HeatScript.NEUTRAL[key]]
			)
		if not is_equal_approx(h.value(key), h.value(key, 0)):
			_fail(
				(
					"with no level given %s is not the Heat 0 value (the run is at Heat %d)"
					% [key, main.heat]
				)
			)
	if h.is_neutral(h.top_level()):
		_fail("the top level changes nothing")


# every level keeps what the one below it does
func _check_ladder() -> void:
	var h = main.heat_sys
	var rising = ["rider_speed", "riders_more", "hearts_minus", "tough_hp_plus", "boss_hp", "price"]
	for i in range(1, h.levels.size()):
		for key in HeatScript.NEUTRAL:
			var now = h.value(key, i)
			var before = h.value(key, i - 1)
			if rising.has(key) and now < before - 0.0001:
				_fail("level %d lowers %s (%s after %s)" % [i, key, now, before])
			if key == "cash" and now > before + 0.0001:
				_fail("level %d raises cash (%s after %s)" % [i, now, before])
		if h.is_neutral(i):
			_fail("level %d changes nothing" % i)


# the top level against the caps in the file (docs/HEAT.md, "Caps that keep a late floor playable")
func _check_caps() -> void:
	var h = main.heat_sys
	var top = h.top_level()
	var hearts = START_HEARTS - int(h.value("hearts_minus", top))
	if hearts < int(h.caps["hearts_min"]):
		_fail("the top level leaves %d hearts, the cap is %d" % [hearts, int(h.caps["hearts_min"])])
	if h.value("cash", top) < float(h.caps["cash_min"]) - 0.0001:
		_fail(
			(
				"the top level pays %s of the cash, the cap is %s"
				% [h.value("cash", top), h.caps["cash_min"]]
			)
		)
	# the biggest round of the map rules, with the extra riders of the top level, rounded up
	var rules = JSON.parse_string(FileAccess.get_file_as_string("res://data/map_rules.json"))
	var counts = rules["content"]["riders"]["count"]
	var biggest = 0
	for kind in counts:
		biggest = maxi(biggest, int(counts[kind]["max"]))
	var with_heat = int(ceil(float(biggest) * (1.0 + h.value("riders_more", top))))
	if with_heat > int(h.caps["riders_max"]):
		_fail(
			(
				"the biggest round has %d riders at the top level, the cap is %d"
				% [with_heat, int(h.caps["riders_max"])]
			)
		)
	if with_heat <= biggest:
		_fail("the top level adds no riders to a round of %d" % biggest)


func _check_lookup() -> void:
	var h = main.heat_sys
	var top = h.top_level()
	if h.clamp_level(99) != top or h.clamp_level(-3) != 0:
		_fail("clamp_level does not keep a level between 0 and %d" % top)
	if not is_equal_approx(h.value("rider_speed", 99), h.value("rider_speed", top)):
		_fail("a level past the end is not the top level")
	var keep = main.heat
	main.heat = 2
	if not is_equal_approx(h.value("riders_more"), h.value("riders_more", 2)):
		_fail("with no level given, the value is not the one of the run's Heat (2)")
	main.heat = keep
	var info = h.level_info(1)
	info["name"] = "CHANGED"
	if h.levels[1]["name"] == "CHANGED":
		_fail("level_info gave out the table itself, not a copy")


# the Heat level in the saved run: written, read back, cleaned and put into the game
func _check_run_save() -> void:
	var h = main.heat_sys
	var top = h.top_level()
	RunSave.test_path = TEST_RUN_PATH
	var keep = main.heat
	# a round trip through a real file, at the top level
	main.heat = top
	main.daily_mode = false
	if not RunSave.save(main):
		_fail("the saved run could not be written")
	var loaded = RunSave.load_file()
	if int(loaded.get("heat", -1)) != top:
		_fail(
			"the saved run holds Heat %s, expected %d" % [str(loaded.get("heat", "<missing>")), top]
		)
	main.reset_run()
	main.meta.begin_run()
	main.challenges.begin_run()
	main.heat = 0
	RunSave.apply(main, loaded)
	if main.heat != top:
		_fail("after loading the saved run the game is at Heat %d, expected %d" % [main.heat, top])
	# a run saved before Heat has no key and was played at 0
	var raw = RunSave.capture(main)
	raw.erase("heat")
	if int(RunSave.clean(raw)["heat"]) != 0:
		_fail("a saved run without a heat key should load as Heat 0")
	# bad values: too big is kept to the levels there are, below 0 and not a number fall back
	raw = RunSave.capture(main)
	raw["heat"] = 999
	var cleaned = RunSave.clean(raw)
	main.heat = 0
	RunSave.apply(main, cleaned)
	if main.heat != top:
		_fail("Heat 999 in a saved run should load as the top level %d, got %d" % [top, main.heat])
	for bad in [-4, "x", null, [1], 2.9]:
		raw["heat"] = bad
		var want = 2 if typeof(bad) == TYPE_FLOAT else 0
		var got = int(RunSave.clean(raw)["heat"])
		if got != want:
			_fail("a saved run with heat %s should load as Heat %d, got %d" % [str(bad), want, got])
	# a Daily Run is always Heat 0
	raw["heat"] = 3
	raw["daily"] = true
	if int(RunSave.clean(raw)["heat"]) != 0:
		_fail("a saved Daily Run should load as Heat 0")
	for path in [TEST_RUN_PATH, TEST_RUN_PATH + ".bak", TEST_RUN_PATH + ".tmp"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	RunSave.test_path = ""
	main.heat = keep


# the level in settings.cfg: kept to the levels there are, and a value that is not a number leaves it alone
func _check_settings() -> void:
	var top = main.heat_sys.top_level()
	var keep = main.heat
	if FileAccess.file_exists(SETTINGS_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_PATH))
	main.heat = 3
	main.settings.save_settings()
	main.heat = 0
	main.settings.load_settings()
	if main.heat != 3:
		_fail("settings.cfg did not give Heat 3 back (got %d)" % main.heat)
	# a file from before Heat has no key: the level stays what it is
	var cf = ConfigFile.new()
	cf.load(SETTINGS_PATH)
	cf.erase_section_key("game", "heat")
	cf.save(SETTINGS_PATH)
	main.heat = 2
	main.settings.load_settings()
	if main.heat != 2:
		_fail("a settings.cfg without heat changed the level (got %d)" % main.heat)
	# hand-edited values
	for case in [[999, top], [-3, 0], [1.0, 1]]:
		cf.set_value("game", "heat", case[0])
		cf.save(SETTINGS_PATH)
		main.heat = 4
		main.settings.load_settings()
		if main.heat != case[1]:
			_fail(
				(
					"heat %s in settings.cfg loaded as %d, expected %d"
					% [str(case[0]), main.heat, case[1]]
				)
			)
	for bad in ["x", true, [1, 2]]:
		cf.set_value("game", "heat", bad)
		cf.save(SETTINGS_PATH)
		main.heat = 4
		main.settings.load_settings()
		if main.heat != 4:
			_fail("heat %s in settings.cfg changed the level to %d" % [str(bad), main.heat])
	main.heat = keep


# the real settings.cfg is kept in memory and written back at the end
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


func _check_bad_data() -> void:
	var good0 = {"level": 0, "name": "A", "desc": "B"}
	var good1 = {"level": 1, "name": "C", "desc": "D", "rider_speed": 1.2}
	# not a table at all, or no levels: level 0 only
	for bad in [null, [], {}, {"levels": "x"}]:
		var t = HeatScript.parse(bad)
		if (
			t["levels"].size() != 1
			or not is_equal_approx(float(t["levels"][0]["rider_speed"]), 1.0)
		):
			_fail("a table that is not valid should give level 0 only (%s)" % str(bad))
	# a good table
	var t = HeatScript.parse({"levels": [good0, good1]})
	if t["levels"].size() != 2 or not is_equal_approx(float(t["levels"][1]["rider_speed"]), 1.2):
		_fail("a good table did not load")
	if not is_equal_approx(float(t["levels"][1]["cash"]), 1.0):
		_fail("a key that is left out should keep its neutral value")
	# level 0 missing: the game runs without Heat
	t = HeatScript.parse({"levels": [good1]})
	if t["levels"].size() != 1:
		_fail(
			"a table without level 0 should give level 0 only, got %d levels" % t["levels"].size()
		)
	# level 0 that changes something is set back
	t = HeatScript.parse(
		{"levels": [{"level": 0, "name": "A", "desc": "B", "rider_speed": 1.5}, good1]}
	)
	if not is_equal_approx(float(t["levels"][0]["rider_speed"]), 1.0):
		_fail("level 0 that changed rider_speed was not set back to 1.0")
	# a gap: the level after it is dropped
	var good3 = {"level": 3, "name": "E", "desc": "F"}
	t = HeatScript.parse({"levels": [good0, good1, good3]})
	if t["levels"].size() != 2:
		_fail("a level after a gap should be dropped, got %d levels" % t["levels"].size())
	# a duplicate, a bad type, a number out of its range, a fraction where a whole number is needed, a missing text
	var bad_entries = [
		{"level": 1, "name": "X", "desc": "Y"},
		{"level": 2, "name": "X", "desc": "Y", "rider_speed": "fast"},
		{"level": 2, "name": "X", "desc": "Y", "rider_speed": 0.5},
		{"level": 2, "name": "X", "desc": "Y", "cash": 1.5},
		{"level": 2, "name": "X", "desc": "Y", "hearts_minus": 3},
		{"level": 2, "name": "X", "desc": "Y", "hearts_minus": 0.5},
		{"level": 2, "name": "X", "desc": "Y", "tough_hp_plus": 1.5},
		{"level": 2, "name": "", "desc": "Y"},
		{"level": 2, "name": "X"},
		{"level": 1.5, "name": "X", "desc": "Y"},
		{"name": "X", "desc": "Y"},
		{"level": 99, "name": "X", "desc": "Y"},
		"not an object",
	]
	for i in range(bad_entries.size()):
		t = HeatScript.parse({"levels": [good0, good1, bad_entries[i]]})
		if t["levels"].size() != 2:
			_fail("bad entry %d was not refused (%s)" % [i, str(bad_entries[i])])
	# caps: a bad number falls back to the default, a good one is taken
	t = HeatScript.parse({"levels": [good0], "caps": {"riders_max": -1, "hearts_min": 1}})
	if int(t["caps"]["riders_max"]) != int(HeatScript.CAP_DEFAULTS["riders_max"]):
		_fail("a bad riders_max cap was not replaced by the default")
	if int(t["caps"]["hearts_min"]) != 1:
		_fail("a good hearts_min cap was not taken")
	# a missing file gives level 0 only
	t = HeatScript.load_table("res://data/no_such_heat_table.json")
	if t["levels"].size() != 1:
		_fail("a missing file should give level 0 only")


func _finish() -> void:
	if problems.is_empty():
		print("heat_check: the Heat table loads, level 0 is neutral, the ladder and its caps hold")
		quit(0)
	else:
		for line in problems.slice(0, 10):
			printerr("heat_check: " + line)
		quit(1)


func _fail(text: String) -> void:
	problems.append(text)
