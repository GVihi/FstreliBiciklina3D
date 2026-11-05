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
#   - riders are faster by the level's `rider_speed` (README H1.5): at Heat 0 a rider starts with exactly the speed it had
#     before Heat, at every other level with that speed times the factor, and the top level still stops at `RIDER_SPEED_CAP`,
#   - rounds have more riders (README H1.6): Heat 0 plans exactly as before, a higher level adds the rounded-up share (at
#     least one, never past `riders_max`), the seed's riders keep their order, the extras copy the mix in its proportions,
#     no random stream moves, and a real round planned on the same stream at every level agrees with all of that,
#   - runs start with fewer hearts (README H1.7): `start_hearts` is 3 at Heat 0 and 2 from H3, never below the `hearts_min`
#     cap and never above 3, a run that is started (new, restarted, saved and loaded) has that many hearts and a MAXHEARTS
#     to match, a Daily Run stays at 3, and practice and the title screen are not changed,
#   - tougher enemies (README H1.8): a tough rider has `tough_hp_plus` more health and every other kind still has 1, a boss
#     has `boss_hp` times its health (before the extra of the final boss), the angry cyclist follows that factor rounded
#     up without counting the rider's bonus twice, and Heat 0 has exactly the health of the game before Heat,
#   - the level is shown (README H1.10): `Heat.label` ("HEAT 3", with the name after it from level 1, level 0 always plain),
#     the high score entry has a `heat` field (the level of the run, written to the file and read back, an old entry or a
#     bad value reads as 0, a number past the limit is cut), and the run bar, pause menu, run summary and High Scores page
#     draw at every level and two window sizes,
#   - a tighter economy (README H1.9): shop prices are `price` times as high (before HAGGLER, rounded to 5, at least 5) and
#     every cash source pays `cash` times as much (before BOUNTY, never below the `cash_min` cap), Heat 0 prices and pays
#     exactly what the game did before Heat, and no level is cheaper or richer than the one below it,
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
const Riders = preload("res://scripts/riders.gd")
const SEED = 0x1234ABCD  # the run of the rider speed case
const DT = 1.0 / 60.0
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
	_check_rider_speed()
	_check_more_riders()
	_check_hearts()
	_check_tougher()
	await _check_show_it()
	_check_economy()
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


# README H1.5: the Heat factor on the speed a rider starts a round with (riders.gd `spawn_rider`, the `diff` line)
func _check_rider_speed() -> void:
	var h = main.heat_sys
	main.generated_arena = true
	main.heat = 0
	main.start_game(false, SEED)
	main.pick_node(0)
	if main.state != "play":
		_fail("could not start a round for the rider speed case (state %s)" % main.state)
		return
	for floor_no in [1, 5, 10]:
		for idx in [0, 6]:
			var plain = 165.0 * main.RIDER_SCALE * _diff(floor_no, idx)
			var at_zero = _pro_base(0, floor_no, idx)
			if absf(at_zero - plain) > 0.000001:
				_fail(
					(
						"Heat 0, floor %d, rider %d: a pro rider starts at %.6f m/s, the game without Heat has %.6f"
						% [floor_no, idx, at_zero, plain]
					)
				)
			for level in range(1, h.top_level() + 1):
				var want = at_zero * h.value("rider_speed", level)
				var got = _pro_base(level, floor_no, idx)
				if absf(got - want) > 0.000001:
					_fail(
						(
							"Heat %d, floor %d, rider %d: a pro rider starts at %.4f m/s, expected %.4f"
							% [level, floor_no, idx, got, want]
						)
					)
	if _pro_base(h.top_level(), 1, 0) <= _pro_base(0, 1, 0):
		_fail("the top level does not make riders faster than Heat 0")
	# a rider told to aim at 1000 m/s on the top level still stops at the cap
	main.heat = h.top_level()
	main.round_n = 10
	main.next_idx = 0
	var r = main.rider_sys.spawn_rider(0, 1)
	r["age"] = 1000.0
	r["tgt"] = 1000.0
	r["chg"] = 1000.0
	r["spd"] = 1.0
	var state_before = main.state
	main.state = "check"  # nobody gets run over, and a finished rider does not end the round
	var top = 0.0
	for i in range(600):
		main.rider_sys.update_rider(r, DT)
		r["chg"] = 1000.0
		r["tgt"] = 1000.0
		top = maxf(top, float(r["spd"]))
	main.state = state_before
	if top > Riders.RIDER_SPEED_CAP + 0.05:
		_fail(
			(
				"at the top level a rider reached %.2f m/s, over the cap %.1f"
				% [top, Riders.RIDER_SPEED_CAP]
			)
		)
	main.clear_riders()
	main.heat = 0
	main.next_idx = 0
	main.go_to_title()


# README H1.6: `Heat.with_extra_riders` on made-up mixes, then on the real plan of a round
func _check_more_riders() -> void:
	var h = main.heat_sys
	var cap = int(h.caps["riders_max"])
	var mixes = [
		{"pro": 5, "sprinter": 2, "courier": 1},
		{"pro": 6, "tough": 2, "sprinter": 2, "courier": 1},
		{"pro": 1},
		{"pro": 12},
		{"pro": 15},
		{"pro": cap},
	]
	var rng_before = main.rider_rng.state
	for mix in mixes:
		var plan = []
		for kind in mix:
			for k in range(int(mix[kind])):
				plan.append(kind)
		plan.reverse()
		var kept = plan.duplicate()
		for level in range(h.top_level() + 1):
			var res = h.with_extra_riders(plan, mix, level)
			var tag = "mix %s at Heat %d" % [str(mix), level]
			if plan != kept:
				_fail("%s: the plan that was passed in was changed" % tag)
			var share = h.value("riders_more", level)
			var want = plan.size()
			if share > 0.0:
				var more = maxi(1, int(ceil(float(plan.size()) * share - 0.000001)))
				want += maxi(0, mini(more, cap - plan.size()))
			if share <= 0.0 and res != plan:
				_fail("%s: a level with no extra riders changed the plan" % tag)
			if res.size() != want:
				_fail("%s: %d riders, expected %d" % [tag, res.size(), want])
			if plan.size() <= cap and res.size() > cap:
				_fail("%s: %d riders, over the cap %d" % [tag, res.size(), cap])
			if not _is_subsequence(plan, res):
				_fail("%s: the seed's riders lost their order" % tag)
			var extra = res.size() - plan.size()
			for kind in mix:
				var have = res.count(kind) - plan.count(kind)
				var exact = float(extra) * float(int(mix[kind])) / float(plan.size())
				if have < 0 or absf(float(have) - exact) >= 1.0:
					_fail(
						(
							"%s: %d extra %s riders, the proportion asks for %.2f"
							% [tag, have, kind, exact]
						)
					)
	if main.rider_rng.state != rng_before:
		_fail("with_extra_riders moved the rider random stream")
	if h.with_extra_riders([], {}, h.top_level()) != []:
		_fail("an empty plan got riders")
	# the real plan of the first round: the same stream at every level, so only Heat differs
	main.generated_arena = true
	main.heat = 0
	main.start_game(false, SEED)
	main.pick_node(0)
	if main.state != "play":
		_fail("could not start a round for the rider count case (state %s)" % main.state)
		return
	var stream = main.DailyScript.stream_seed(main.run_seed, main.round_n, "riders")
	main.rider_rng.seed = stream
	main.plan_riders()
	var plain = main.rider_plan.duplicate()
	if plain.is_empty():
		_fail("the first round has no rider plan, so the rider count case tested nothing")
		main.go_to_title()
		return
	for level in range(1, h.top_level() + 1):
		main.heat = level
		main.rider_rng.seed = stream
		main.plan_riders()
		var share = h.value("riders_more", level)
		var want = plain.size()
		if share > 0.0:
			var more = maxi(1, int(ceil(float(plain.size()) * share - 0.000001)))
			want += maxi(0, mini(more, cap - plain.size()))
		if main.rider_plan.size() != want or main.PER_ROUND != want:
			_fail(
				(
					"Heat %d: the round has %d riders (PER_ROUND %d), expected %d"
					% [level, main.rider_plan.size(), main.PER_ROUND, want]
				)
			)
		if not _is_subsequence(plain, main.rider_plan):
			_fail("Heat %d: the seed's riders of the round lost their order" % level)
	main.heat = 0
	main.rider_rng.seed = stream
	main.plan_riders()
	if main.rider_plan != plain or main.PER_ROUND != plain.size():
		_fail("Heat 0 does not plan the round it planned before")
	main.go_to_title()


# README H1.7: `Heat.start_hearts`, then the hearts of runs that are really started
func _check_hearts() -> void:
	var h = main.heat_sys
	var top = h.top_level()
	if START_HEARTS != HeatScript.START_HEARTS:
		_fail(
			(
				"heat.gd starts a run with %d hearts, expected %d"
				% [HeatScript.START_HEARTS, START_HEARTS]
			)
		)
	# the lookup, level by level, against the table and the cap
	for level in range(top + 1):
		var want = maxi(
			int(h.caps["hearts_min"]), START_HEARTS - int(h.value("hearts_minus", level))
		)
		want = mini(want, START_HEARTS)
		if h.start_hearts(level) != want:
			_fail("Heat %d: start_hearts is %d, expected %d" % [level, h.start_hearts(level), want])
	if h.start_hearts(0) != START_HEARTS:
		_fail("Heat 0 starts with %d hearts, expected %d" % [h.start_hearts(0), START_HEARTS])
	for level in range(3, top + 1):
		if h.start_hearts(level) != 2:
			_fail(
				(
					"Heat %d starts with %d hearts, docs/HEAT.md says 2 from H3"
					% [level, h.start_hearts(level)]
				)
			)
	for level in range(0, mini(3, top + 1)):
		if h.start_hearts(level) != START_HEARTS:
			_fail(
				(
					"Heat %d starts with %d hearts, expected %d"
					% [level, h.start_hearts(level), START_HEARTS]
				)
			)
	if h.start_hearts(99) != h.start_hearts(top):
		_fail("a level past the end does not start with the hearts of the top level")
	var keep = main.heat
	main.heat = 3
	if h.start_hearts() != h.start_hearts(3):
		_fail("with no level given, start_hearts is not the one of the run's Heat (3)")
	main.heat = keep
	# the cap and the limits, on a table of its own so the real one is not touched
	var own = HeatScript.new()
	own.levels[top]["hearts_minus"] = 2
	own.caps["hearts_min"] = 2
	if own.start_hearts(top) != 2:
		_fail(
			"2 hearts taken off with a cap of 2 left %d hearts, expected 2" % own.start_hearts(top)
		)
	own.caps["hearts_min"] = 1
	if own.start_hearts(top) != 1:
		_fail(
			"2 hearts taken off with a cap of 1 left %d hearts, expected 1" % own.start_hearts(top)
		)
	own.caps["hearts_min"] = 5  # a cap above the start must not give Heat more hearts than the game had
	if own.start_hearts(0) != START_HEARTS or own.start_hearts(top) != START_HEARTS:
		_fail("a hearts_min cap above %d raised the hearts of a run" % START_HEARTS)
	# runs that are really started
	main.generated_arena = true
	for level in range(top + 1):
		main.heat = level
		main.start_game(false, SEED)
		var want = h.start_hearts(level)
		if main.MAXHEARTS != want or main.hearts != want:
			_fail(
				(
					"Heat %d: a new run has %d of %d hearts, expected %d"
					% [level, main.hearts, main.MAXHEARTS, want]
				)
			)
		if level == 0 and (main.MAXHEARTS != 3 or main.hearts != 3):
			_fail("Heat 0: a new run does not start with 3 hearts")
	# a restarted run keeps the level and so the hearts
	main.heat = 3
	main.start_game(false, SEED)
	main.hearts = 1
	main.restart_run()
	if main.heat != 3 or main.MAXHEARTS != 2 or main.hearts != 2:
		_fail(
			(
				"a restarted run at Heat 3 has %d of %d hearts (Heat %d), expected 2 of 2"
				% [main.hearts, main.MAXHEARTS, main.heat]
			)
		)
	# a saved run gives back its own maximum, and a run on the map keeps its hearts
	main.heat = 3
	main.start_game(false, SEED)
	main.hearts = 1
	var raw = RunSave.capture(main)
	if int(raw["max_hearts"]) != 2:
		_fail("a run saved at Heat 3 holds max_hearts %s, expected 2" % str(raw["max_hearts"]))
	var cleaned = RunSave.clean(raw)
	main.reset_run()
	main.meta.begin_run()
	main.challenges.begin_run()
	RunSave.apply(main, cleaned)
	if main.MAXHEARTS != 2 or main.hearts != 1 or main.heat != 3:
		_fail(
			(
				"a loaded run at Heat 3 has %d of %d hearts (Heat %d), expected 1 of 2"
				% [main.hearts, main.MAXHEARTS, main.heat]
			)
		)
	# a Daily Run is Heat 0 for everybody, so 3 hearts whatever the level chosen
	main.heat = top
	main.start_game(true)
	if main.heat != 0 or main.MAXHEARTS != START_HEARTS or main.hearts != START_HEARTS:
		_fail(
			(
				"a Daily Run has %d of %d hearts at Heat %d, expected %d at Heat 0"
				% [main.hearts, main.MAXHEARTS, main.heat, START_HEARTS]
			)
		)
	# reset_run (practice, the title screen, CONTINUE before the load) stays at 3 at every level
	main.heat = top
	main.reset_run()
	if main.MAXHEARTS != START_HEARTS:
		_fail(
			"reset_run left %d hearts at Heat %d, expected %d" % [main.MAXHEARTS, top, START_HEARTS]
		)
	main.heat = 0
	main.daily_mode = false
	main.go_to_title()


# README H1.8: tough riders have `tough_hp_plus` more health, bosses `boss_hp` times the health (the angry cyclist rounded
# up), and every other rider still falls to one hit
func _check_tougher() -> void:
	var h = main.heat_sys
	var top = h.top_level()
	# the arithmetic on its own
	for hp in [1, 2, 3, 5, 16, 22, 78, 101]:
		if h.boss_health(hp, 0) != hp or h.boss_health(hp, 0, true) != hp:
			_fail("Heat 0 changed a boss health of %d" % hp)
		for level in range(top + 1):
			var exact = float(hp) * h.value("boss_hp", level)
			var near = maxi(1, int(round(exact)))
			var up = maxi(1, int(ceil(exact - 0.000001)))
			if h.boss_health(hp, level) != near:
				_fail(
					(
						"Heat %d: a boss of %d health has %d, expected %d"
						% [level, hp, h.boss_health(hp, level), near]
					)
				)
			if h.boss_health(hp, level, true) != up:
				_fail(
					(
						"Heat %d: a runner of %d health has %d, expected %d"
						% [level, hp, h.boss_health(hp, level, true), up]
					)
				)
			if h.boss_health(hp, level) < hp:
				_fail("Heat %d: a boss of %d health got weaker" % [level, hp])
	var keep = main.heat
	main.heat = top
	if h.boss_health(22) != h.boss_health(22, top):
		_fail("with no level given, boss_health is not the one of the run's Heat")
	main.heat = keep
	main.generated_arena = true
	main.heat = 0
	main.start_game(false, SEED)
	main.pick_node(0)
	if main.state != "play":
		_fail("could not start a round for the tougher case (state %s)" % main.state)
		return
	# riders: only a tough rider gets more health
	var kinds = ["pro", "sprinter", "courier", "tough"]
	for floor_no in [1, 2, 4, 5, 10]:
		for level in range(top + 1):
			for i in range(kinds.size()):
				main.heat = level
				main.round_n = floor_no
				main.rider_plan = kinds.duplicate()
				main.next_idx = i
				var r = main.rider_sys.spawn_rider(0, 1)
				var want = 1
				if r["type"] == "tough":
					want = (3 if floor_no >= 5 else 2) + int(h.value("tough_hp_plus", level))
				if r["type"] != kinds[i]:
					_fail(
						(
							"floor %d, Heat %d: asked for a %s rider and got a %s"
							% [floor_no, level, kinds[i], r["type"]]
						)
					)
				if r["hp"] != want or r["max_hp"] != want:
					_fail(
						(
							"floor %d, Heat %d: a %s rider has %d of %d health, expected %d"
							% [floor_no, level, r["type"], r["hp"], r["max_hp"], want]
						)
					)
				main.clear_riders()
	# bosses: the kind's base health with the growth per round, the Heat factor, then the extra of the final boss
	var boss_sys = main.boss_sys
	for round_no in [2, 3, 6, 9]:
		for level in range(top + 1):
			main.heat = level
			main.round_n = round_no
			main.boss_count = 0
			main.clear_bosses()
			boss_sys.spawn_boss()
			if main.bosses.is_empty():
				_fail("round %d, Heat %d: no boss was spawned" % [round_no, level])
				continue
			var b = main.bosses[0]
			var plain = boss_sys.boss_hp(int(main.BOSS_INFO[b["kind"]]["hp"]))
			var want = h.boss_health(plain, level)
			if b["final"]:
				want = int(round(float(want) * boss_sys.FINAL_HP_MUL))
			if b["max_hp"] != want or b["hp"] != want:
				_fail(
					(
						"round %d, Heat %d: a %s has %d of %d health, expected %d"
						% [round_no, level, b["kind"], b["hp"], b["max_hp"], want]
					)
				)
			if level == 0 and not b["final"] and b["max_hp"] != plain:
				_fail(
					(
						"Heat 0: a %s has %d health, the game without Heat has %d"
						% [b["kind"], b["max_hp"], plain]
					)
				)
			main.clear_bosses()
	for level in range(top + 1):  # the final boss, the golden president
		main.heat = level
		main.round_n = main.MAX_ROUNDS
		main.boss_count = 0
		main.clear_bosses()
		boss_sys.spawn_boss()
		var b = main.bosses[0]
		var want = int(
			round(float(h.boss_health(boss_sys.boss_hp(22), level)) * boss_sys.FINAL_HP_MUL)
		)
		if level == 0:
			want = int(round(float(boss_sys.boss_hp(22)) * boss_sys.FINAL_HP_MUL))
		if b["kind"] != "president" or b["max_hp"] != want:
			_fail(
				(
					"the final boss at Heat %d is a %s with %d health, expected a president with %d"
					% [level, b["kind"], b["max_hp"], want]
				)
			)
		main.clear_bosses()
	# the angry cyclist: built from a tough rider, follows the boss factor (rounded up) and does not count the rider's
	# Heat bonus twice
	for round_no in [2, 4, 5, 8]:
		for level in range(top + 1):
			main.heat = level
			main.round_n = round_no
			main.rider_plan = ["tough"]
			main.next_idx = 0
			main.clear_bosses()
			var r = main.rider_sys.spawn_rider(0, 1)
			boss_sys.spawn_runner(r)
			var b = main.bosses[0]
			var base = (3 if round_no >= 5 else 2) + int(floor(float(maxi(0, round_no - 2)) / 2.0))
			var want = h.boss_health(base, level, true)
			if b["kind"] != "runner" or b["max_hp"] != want:
				_fail(
					(
						"round %d, Heat %d: the angry cyclist has %d health, expected %d"
						% [round_no, level, b["max_hp"], want]
					)
				)
			if level == 0 and b["max_hp"] != base:
				_fail(
					(
						"Heat 0: the angry cyclist has %d health, the game without Heat has %d"
						% [b["max_hp"], base]
					)
				)
			main.clear_bosses()
			main.clear_riders()
	main.heat = 0
	main.rider_plan = []
	main.go_to_title()


# true when every element of `sub` is in `full`, in the same order (others may lie between)
# README H1.10: the level is written where the player sees it, and the score record carries it
func _check_show_it() -> void:
	var h = main.heat_sys
	var top = h.top_level()
	var keep = main.heat
	# the label: level 0 is plain even with the name, the others say the name when asked, -1 is the level of the run
	if h.label(0) != "HEAT 0" or h.label(0, true) != "HEAT 0":
		_fail(
			(
				'the label of level 0 is "%s" / "%s", expected "HEAT 0"'
				% [h.label(0), h.label(0, true)]
			)
		)
	for level in range(1, top + 1):
		var want = "HEAT %d" % level
		if h.label(level) != want:
			_fail('the label of level %d is "%s", expected "%s"' % [level, h.label(level), want])
		var named = want + "  " + str(h.level_info(level)["name"])
		if h.label(level, true) != named:
			_fail(
				(
					'the named label of level %d is "%s", expected "%s"'
					% [level, h.label(level, true), named]
				)
			)
	main.heat = 3
	if h.label() != "HEAT 3" or h.label(-1, true) != "HEAT 3  FEWER LIVES":
		_fail('the label of the run at Heat 3 is "%s" / "%s"' % [h.label(), h.label(-1, true)])
	if h.label(top + 7) != h.label(top):
		_fail("a level past the end should be labelled as the top level")
	# the record: what heat_of makes of every kind of value
	var ScoresScript = load("res://scripts/scores.gd")
	var cases = [
		[0, 0],
		[3, 3],
		[5, 5],
		[2.9, 2],
		[-4, 0],
		[999, HeatScript.MAX_LEVEL],
		["3", 0],
		[null, 0],
		[[1], 0],
		[true, 0]
	]
	for c in cases:
		var got = ScoresScript.heat_of(c[0])
		if got != c[1]:
			_fail("heat_of(%s) is %d, expected %d" % [str(c[0]), got, c[1]])
	# the file: an old entry (no heat key), a good one, bad ones; and a run that is recorded
	var path = main.scores.PATH
	var had = FileAccess.file_exists(path)
	var kept = PackedByteArray()
	if had:
		kept = FileAccess.get_file_as_bytes(path)
	var base = {"name": "AAA", "round": 2, "kills": 5, "time": 100, "date": "2026-01-01"}
	var rows = []
	for pair in [[900, null], [800, 3], [700, "x"], [600, 999], [500, -2]]:
		var e = base.duplicate()
		e["score"] = pair[0]
		if pair[1] != null:
			e["heat"] = pair[1]
		rows.append(e)
	var f = FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify({"version": 1, "entries": rows}))
	f.close()
	main.scores.load_scores()
	var want_heat = [0, 3, 0, HeatScript.MAX_LEVEL, 0]
	if main.scores.entries.size() != 5:
		_fail("the scores file with 5 entries loaded %d" % main.scores.entries.size())
	else:
		for i in range(5):
			if int(main.scores.entries[i].get("heat", -1)) != want_heat[i]:
				_fail(
					(
						"entry %d loaded with heat %s, expected %d"
						% [i, str(main.scores.entries[i].get("heat", "<missing>")), want_heat[i]]
					)
				)
	for lvl in [0, 4]:
		main.scores.entries = []
		main.daily_mode = false
		main.custom_seed_run = false
		main.heat = lvl
		main.score = 1234
		if main.scores.submit_run() != 0:
			_fail("a ranked run at Heat %d did not reach the list" % lvl)
		main.name_entry = false
		main.scores.load_scores()
		if main.scores.entries.is_empty() or int(main.scores.entries[0].get("heat", -1)) != lvl:
			_fail("a run at Heat %d was not saved with that heat" % lvl)
	# drawn at every level and two window sizes: the run summary, the pause menu, the run bar and the High Scores page
	main.scores.entries = [
		{
			"name": "AAA",
			"score": 900,
			"round": 2,
			"kills": 5,
			"time": 100,
			"date": "2026-01-01",
			"heat": 5
		},
		{"name": "OLD", "score": 800, "round": 1, "kills": 1, "time": 0, "date": "2025-01-01"}
	]
	for level in range(top + 1):
		main.heat = level
		for s in [Vector2(1280.0, 720.0), Vector2(1920.0, 1080.0)]:
			main.hud.size = s
			main.state = "over"
			await _redraw()
			main.state = "play"
			main.paused = true
			main.pause_page = ""
			await _redraw()
			main.paused = false
			await _redraw()
			main.go_to_title()
			main.title_page = "scores"
			await _redraw()
			main.go_to_title()
	main.hud.size = Vector2(1280.0, 720.0)
	# put the real scores file back
	if had:
		var w = FileAccess.open(path, FileAccess.WRITE)
		w.store_buffer(kept)
		w.close()
	elif FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	main.scores.load_scores()
	main.heat = keep


func _redraw() -> void:
	for i in range(2):
		main.hud.queue_redraw()
		await process_frame


# README H1.9: shop prices go up by `price` and every cash source pays `cash` times as much (shop.gd `shop_price` and
# `add_cash`). Heat 0 prices and pays exactly what the game did before Heat; HAGGLER and BOUNTY still work on top.
func _check_economy() -> void:
	var h = main.heat_sys
	var top = h.top_level()
	# the factors, level by level, against the table and the cap
	for level in range(top + 1):
		if not is_equal_approx(h.price_factor(level), h.value("price", level)):
			_fail(
				(
					"Heat %d: price_factor is %s, the table says %s"
					% [level, h.price_factor(level), h.value("price", level)]
				)
			)
		var want_cash = minf(1.0, maxf(h.value("cash", level), float(h.caps["cash_min"])))
		if not is_equal_approx(h.cash_factor(level), want_cash):
			_fail(
				"Heat %d: cash_factor is %s, expected %s" % [level, h.cash_factor(level), want_cash]
			)
	if h.price_factor(0) != 1.0 or h.cash_factor(0) != 1.0:
		_fail("Heat 0 has a price or cash factor that is not exactly 1.0")
	if top >= 5:
		if (
			not is_equal_approx(h.price_factor(5), 1.2)
			or not is_equal_approx(h.cash_factor(5), 0.8)
		):
			_fail("Heat 5 should be prices x1.2 and cash x0.8 (docs/HEAT.md)")
		for level in range(0, 5):
			if h.price_factor(level) != 1.0 or h.cash_factor(level) != 1.0:
				_fail("Heat %d changes prices or cash, docs/HEAT.md says only H5 does" % level)
	if h.price_factor(99) != h.price_factor(top) or h.cash_factor(99) != h.cash_factor(top):
		_fail("a level past the end does not use the factors of the top level")
	var keep = main.heat
	main.heat = 5 if top >= 5 else top
	if h.price_factor() != h.price_factor(main.heat) or h.cash_factor() != h.cash_factor(main.heat):
		_fail("with no level given, the factors are not the ones of the run's Heat")
	main.heat = keep
	# the cap, on a table of its own so the real one is not touched
	var own = HeatScript.new()
	own.levels[top]["cash"] = 0.1
	own.caps["cash_min"] = 0.5
	if not is_equal_approx(own.cash_factor(top), 0.5):
		_fail("cash 0.1 with a cap of 0.5 gave %s, expected 0.5" % own.cash_factor(top))
	own.caps["cash_min"] = 2.0  # a cap above 1 must not make Heat pay more than the game did
	if own.cash_factor(top) != 1.0 or own.cash_factor(0) != 1.0:
		_fail("a cash_min cap above 1 made cash pay more than at Heat 0")
	# the real shop and the real cash, with the state they read kept and put back
	var kept = {
		"heat": main.heat,
		"round_n": main.round_n,
		"shop_buys": main.shop_buys,
		"shop_lvl": main.shop_lvl.duplicate(),
		"perks": main.perks.duplicate(),
		"cash": main.cash,
	}
	var item = {"id": "check", "kind": "perk", "cost": 100}
	var tier = {"id": "check_tier", "kind": "tier", "cost": 100}
	for level in range(top + 1):
		for round_no in [1, 4, 9]:
			for buys in [0, 3]:
				for haggler in [false, true]:
					main.heat = level
					main.round_n = round_no
					main.shop_buys = buys
					main.shop_lvl = {"check_tier": 2}
					main.perks = {"haggler": true} if haggler else {}
					# the price as the game had it before Heat, times the factor, rounded to 5
					for it in [item, tier]:
						var v = (
							float(it["cost"])
							* (1.0 + 0.12 * float(round_no - 1))
							* (1.0 + 0.06 * float(buys))
						)
						if it["kind"] == "tier":
							v *= 1.0 + 0.45 * 2.0
						if level == 0 and haggler:
							v *= 0.85
						var before = maxi(5, int(round(v / 5.0)) * 5)
						if level == 0:
							if main.shop_sys.shop_price(it) != before:
								_fail(
									(
										"Heat 0 changed a shop price (round %d, %d buys, haggler %s, %s): %d, was %d"
										% [
											round_no,
											buys,
											haggler,
											it["kind"],
											main.shop_sys.shop_price(it),
											before
										]
									)
								)
						else:
							var w = (
								float(it["cost"])
								* (1.0 + 0.12 * float(round_no - 1))
								* (1.0 + 0.06 * float(buys))
							)
							if it["kind"] == "tier":
								w *= 1.0 + 0.45 * 2.0
							w *= h.price_factor(level)
							if haggler:
								w *= 0.85
							var want = maxi(5, int(round(w / 5.0)) * 5)
							if main.shop_sys.shop_price(it) != want:
								_fail(
									(
										"Heat %d: a shop price is %d, expected %d (round %d, %d buys, haggler %s, %s)"
										% [
											level,
											main.shop_sys.shop_price(it),
											want,
											round_no,
											buys,
											haggler,
											it["kind"]
										]
									)
								)
							if main.shop_sys.shop_price(it) < 5:
								_fail("Heat %d: a shop price is under 5" % level)
	# a higher level never makes a price lower
	main.round_n = 4
	main.shop_buys = 1
	main.shop_lvl = {}
	main.perks = {}
	var last_price = 0
	for level in range(top + 1):
		main.heat = level
		var p = main.shop_sys.shop_price(item)
		if p < last_price:
			_fail(
				(
					"Heat %d: the shop price %d is lower than the %d of the level below"
					% [level, p, last_price]
				)
			)
		last_price = p
	# cash: every amount, round and level, with and without BOUNTY
	for level in range(top + 1):
		for round_no in [1, 3, 8]:
			for bounty in [false, true]:
				for n in [2, 5, 12, 13, 15, 18, 36, 55, 80]:
					main.heat = level
					main.round_n = round_no
					main.perks = {"bounty": true} if bounty else {}
					main.cash = 0
					main.shop_sys.add_cash(n)
					var v2 = float(n) * (1.0 + 0.08 * float(round_no - 1))
					if level != 0:
						v2 *= h.cash_factor(level)
					if bounty:
						v2 *= 1.35
					var want_cash = int(round(v2))
					if level == 0:
						want_cash = int(
							round(
								(
									float(n)
									* (1.0 + 0.08 * float(round_no - 1))
									* (1.35 if bounty else 1.0)
								)
							)
						)
					if main.cash != want_cash:
						_fail(
							(
								"Heat %d: add_cash(%d) paid %d, expected %d (round %d, bounty %s)"
								% [level, n, main.cash, want_cash, round_no, bounty]
							)
						)
	# no level pays more than the one below it
	main.round_n = 3
	main.perks = {}
	var last_pay = 1000000
	for level in range(top + 1):
		main.heat = level
		main.cash = 0
		main.shop_sys.add_cash(100)
		if main.cash > last_pay:
			_fail(
				(
					"Heat %d pays %d, more than the %d of the level below"
					% [level, main.cash, last_pay]
				)
			)
		last_pay = main.cash
	# put the state back
	main.heat = kept["heat"]
	main.round_n = kept["round_n"]
	main.shop_buys = kept["shop_buys"]
	main.shop_lvl = kept["shop_lvl"]
	main.perks = kept["perks"]
	main.cash = kept["cash"]


func _is_subsequence(sub: Array, full: Array) -> bool:
	var i = 0
	for item in full:
		if i < sub.size() and item == sub[i]:
			i += 1
	return i == sub.size()


# the `diff` of riders.gd for a floor and for the rider sent at index `idx`
func _diff(floor_no: int, idx: int) -> float:
	return 1.0 + (floor_no - 1) * Riders.ROUND_SPEED_GROWTH + idx * 0.03


# the base speed of a pro rider (a rider's own type factor taken out) at a Heat level, floor and send index
func _pro_base(level: int, floor_no: int, idx: int) -> float:
	main.heat = level
	main.round_n = floor_no
	main.next_idx = idx
	var r = main.rider_sys.spawn_rider(0, 1)
	var base = float(r["base"]) / float(main.TYPES[r["type"]]["sp"])
	main.clear_riders()
	return base


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
