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
#   - the ladder unlocks (README H1.11): `heat_open` in meta.json (a missing key, a bad value, a negative number read as
#     0, a number past the limit is cut, a round trip through the real file), a win at the highest open level opens the
#     next one and nothing else does (a win at a lower level, a lost run, the top level, practice), a run starts at the
#     highest open level at most, the picker stops there, RESET ALL PROGRESS closes the ladder again, and the PLAY page
#     and the run summary draw with locked levels,
#   - the modifiers (README H2.2): the five of docs/HEAT.md with strictly rising points and no effect set twice, the
#     presets built from them give exactly the ladder of H1 (every effect at every level), the total of every preset is
#     the Heat it names, no preset has a clash or fewer than 2 hearts, the arithmetic on sets (`total_points`, `is_legal`,
#     `clean_set`, `effects_of`), and all 432 combinations of ranks: 330 without a clash, the top total 12 (two sets), and
#     `clean_set` makes every one of them legal without making it worth more,
#   - stacking (README H2.3): a set of ranks can be played and cleared, every clash of the table is refused (the second
#     named goes down, the first keeps its rank), all 432 sets played are legal and within the top total with every cap
#     holding (hearts 1 to 3, cash at least the cap, riders in a round at most the cap), the set with every rank maxed and the
#     best sets start a real round, riders on floor 10 never aim past RIDER_SPEED_CAP and never speed up past their spawn
#     speed, a hearts cap that reads as 0 still leaves 1 heart, and a Daily Run puts a played set away,
#   - the rewards (README H3.2; docs/HEAT.md, "Rewards"): `reward_bonus` is 10 % of the base per point in whole numbers
#     (the worked examples of the note, at least +1 from Heat 1 up, 0 at Heat 0 and for a base of 0, a set of ranks pays by
#     its total, a bad number of points is kept inside the table), the table's `rewards` entry loads and a bad one keeps the
#     default, and a real run paid through `Meta.award_run` gets the bonus on the coins of rounds, bosses and caches and on
#     the XP of rounds, kills, a win and bosses but not on the score, its coins and XP, Heat 0 pays what it did before Heat,
#     a higher Heat pays more, a run that earned nothing is paid nothing, and a run is paid once,
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
var open_before = 0


func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	for i in range(3):
		await process_frame
	_check_table()
	_check_neutral()
	_check_ladder()
	_check_modifiers()
	_check_caps()
	_check_lookup()
	_check_bad_data()
	_keep_settings()
	open_before = int(main.meta.heat_open)
	main.meta.heat_open = main.heat_sys.top_level()  # the cases above play at every level: all of them open
	_check_run_save()
	_check_settings()
	_check_rider_speed()
	_check_more_riders()
	_check_hearts()
	_check_tougher()
	await _check_show_it()
	await _check_unlock()
	_check_economy()
	_check_stacking()
	_check_rewards()
	main.meta.heat_open = open_before
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
# README H1.11: the ladder opens one level at a time
func _check_unlock() -> void:
	var h = main.heat_sys
	var top = h.top_level()
	var keep_open = main.meta.heat_open
	var keep_heat = main.heat
	var path = main.meta.PATH
	var had = FileAccess.file_exists(path)
	var kept = PackedByteArray()
	if had:
		kept = FileAccess.get_file_as_bytes(path)
	# the file: a missing key, good values and bad ones, then a real round trip
	var cases = [
		["<missing>", 0],
		[3, 3],
		[2.9, 2],
		[0, 0],
		[-2, 0],
		["x", 0],
		[null, 0],
		[[1], 0],
		[999, main.meta.MAX_HEAT_OPEN],
	]
	for c in cases:
		var data = {"version": 1, "balance": 5, "xp": 7}
		if not (typeof(c[0]) == TYPE_STRING and c[0] == "<missing>"):
			data["heat_open"] = c[0]
		var f = FileAccess.open(path, FileAccess.WRITE)
		f.store_string(JSON.stringify(data))
		f.close()
		main.meta.load_meta()
		if main.meta.heat_open != c[1]:
			_fail(
				(
					"meta.json with heat_open %s loaded as %d, expected %d"
					% [str(c[0]), main.meta.heat_open, c[1]]
				)
			)
		if main.meta.balance != 5 or main.meta.xp != 7:
			_fail("meta.json with heat_open %s lost its other fields" % str(c[0]))
	main.meta.heat_open = top + 3  # past the table: the level in use is still the top level
	if h.open_level() != top:
		_fail("open_level with heat_open past the top is %d, expected %d" % [h.open_level(), top])
	main.meta.heat_open = 3
	main.meta.save_meta()
	main.meta.heat_open = 0
	main.meta.load_meta()
	if main.meta.heat_open != 3:
		_fail("heat_open 3 came back as %d after a save and a load" % main.meta.heat_open)
	# the rule, at every open level
	main.practice = false
	for open in range(top + 1):
		main.meta.heat_open = open
		for level in range(top + 1):
			main.heat = level
			main.run_won = true
			var opened = main.meta.unlock_heat_after_win()
			var want_open = open + 1 if level == open and open < top else open
			if main.meta.heat_open != want_open or opened != (want_open != open):
				_fail(
					(
						"a win at Heat %d with %d open left %d open (opened %s), expected %d"
						% [level, open, main.meta.heat_open, str(opened), want_open]
					)
				)
			if opened and main.meta.heat_unlocked != want_open:
				_fail(
					(
						"a win that opened Heat %d says it opened %d"
						% [want_open, main.meta.heat_unlocked]
					)
				)
			if not opened and main.meta.heat_unlocked != -1:
				_fail("a win that opened nothing says it opened %d" % main.meta.heat_unlocked)
			main.meta.heat_open = open
		main.heat = open
		main.run_won = false  # a lost or quit run opens nothing
		if main.meta.unlock_heat_after_win() or main.meta.heat_open != open:
			_fail(
				(
					"a run that was not won opened a level (%d open, was %d)"
					% [main.meta.heat_open, open]
				)
			)
	main.heat = 0
	main.meta.heat_open = 0
	main.run_won = true
	main.practice = true  # the training room is no run
	if main.meta.unlock_heat_after_win() or main.meta.heat_open != 0:
		_fail("a win in the training room opened a level")
	main.practice = false
	# the real flow: a run starts at the highest open level at most, the picker stops there, and a win pays it out once
	main.meta.heat_open = 2
	main.heat = top
	main.start_game(false, SEED)
	if main.heat != 2:
		_fail(
			"a run chosen at Heat %d with 2 open started at Heat %d, expected 2" % [top, main.heat]
		)
	if main.MAXHEARTS != 3:
		_fail("a run at Heat 2 has %d hearts, expected 3" % main.MAXHEARTS)
	main.win_run()
	if main.meta.heat_open != 3 or main.meta.heat_unlocked != 3:
		_fail(
			(
				"winning at Heat 2 with 2 open left %d open (unlocked %d), expected 3"
				% [main.meta.heat_open, main.meta.heat_unlocked]
			)
		)
	main.meta.load_meta()
	if main.meta.heat_open != 3:
		_fail("the level opened by a win was not saved (the file says %d)" % main.meta.heat_open)
	main.start_game(false, SEED)  # a new run clears the note on the summary
	if main.meta.heat_unlocked != -1:
		_fail("a new run still carries the level the last one opened")
	main.heat = 3
	main.go_to_title()
	main.title_page = "play"
	main.input_sys.heat_adjust(1)
	if main.heat != 3:
		_fail("the picker went to Heat %d with 3 open" % main.heat)
	main.input_sys.heat_adjust(-1)
	if main.heat != 2:
		_fail("the picker did not step down from Heat 3 (it is %d)" % main.heat)
	main.meta.heat_open = 0
	main.heat = 4  # a choice remembered from before the ladder was locked
	main.start_game(false, SEED)
	if main.heat != 0:
		_fail("a run chosen at Heat 4 with only Heat 0 open started at Heat %d" % main.heat)
	# RESET ALL PROGRESS closes the ladder again
	main.meta.heat_open = top
	main.reset_all_progress()
	if main.meta.heat_open != 0 or main.heat_sys.open_level() != 0:
		_fail("RESET ALL PROGRESS left %d levels open" % main.meta.heat_open)
	# the PLAY page and the run summary draw with locked levels, at two window sizes
	for open in [0, 2, top]:
		main.meta.heat_open = open
		for s in [Vector2(1280.0, 720.0), Vector2(1920.0, 1080.0)]:
			main.hud.size = s
			main.heat = open
			main.go_to_title()
			main.title_page = "play"
			await _redraw()
			main.start_game(false, SEED)
			main.heat = open
			main.run_won = true
			main.meta.unlock_heat_after_win()
			main.state = "over"
			await _redraw()
			main.go_to_title()
	main.hud.size = Vector2(1280.0, 720.0)
	# put the real meta.json back
	if had:
		var w = FileAccess.open(path, FileAccess.WRITE)
		w.store_buffer(kept)
		w.close()
	elif FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	main.meta.load_meta()
	main.meta.heat_open = keep_open
	main.heat = keep_heat
	main.run_won = false


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


# README H2.3: stacking rules. A set of ranks can be played (`play_set`, `clear_set`), a clash is refused, and every cap of
# the table holds for every legal set, for the set with every rank maxed, and for a set that skipped the clash rule (a
# hand-edited save). The sets that are worth the top total, and the maxed one, start a real round with riders that never
# aim past `RIDER_SPEED_CAP`.
func _check_stacking() -> void:
	var h = main.heat_sys
	var cap = int(h.caps["riders_max"])
	if h.has_set() or h.set_points() != 0 or not h.set_ranks.is_empty():
		_fail("a set is played before any was chosen")
	# play_set, clear_set and what a lookup reads
	var asked = {"swift": 2, "crowd": 1}
	var kept = asked.duplicate()
	var got = h.play_set(asked)
	if asked != kept:
		_fail("play_set changed the set that was passed in")
	if got != kept or not h.has_set() or h.set_points() != h.total_points(kept):
		_fail("play_set(%s) played %s worth %d" % [str(kept), str(got), h.set_points()])
	var want = h.effects_of(kept)
	for key in HeatScript.NEUTRAL:
		if not is_equal_approx(h.value(key), float(want[key])):
			_fail("a played set: %s is %s, expected %s" % [key, h.value(key), want[key]])
		if not is_equal_approx(h.value(key, 0), float(HeatScript.NEUTRAL[key])):
			_fail(
				"a played set: a level given on purpose did not read the table (%s at Heat 0)" % key
			)
	got.erase("swift")
	if h.set_ranks != kept:
		_fail("play_set gave out the played set itself, not a copy")
	h.clear_set()
	if h.has_set() or h.set_points() != 0 or not h.set_ranks.is_empty():
		_fail("clear_set left a set played")
	for key in HeatScript.NEUTRAL:
		if not is_equal_approx(h.value(key), h.value(key, main.heat)):
			_fail("after clear_set %s does not read the level of the run again" % key)
	h.play_set({})
	if not h.has_set() or h.set_points() != 0:
		_fail("an empty set is not played as a set worth 0")
	for key in HeatScript.NEUTRAL:
		if not is_equal_approx(h.value(key), float(HeatScript.NEUTRAL[key])):
			_fail("an empty set: %s is %s, Heat 0 changes nothing" % [key, h.value(key)])
	h.clear_set()
	# every clash is refused, and the one that is kept is the first named
	for c in h.clashes:
		var a = str(c["a_id"])
		var b = str(c["b_id"])
		var pair = {a: int(c["a_rank"]), b: int(c["b_rank"])}
		var tag = "%s %d with %s %d" % [a, int(c["a_rank"]), b, int(c["b_rank"])]
		if h.is_legal(pair):
			_fail("%s is in the table as a clash but is a legal set" % tag)
		if str(c["why"]) == "":
			_fail("%s is refused with no reason to show" % tag)
		var played = h.play_set(pair)
		if not h.is_legal(played) or played != h.clean_set(pair):
			_fail(
				(
					"%s: play_set played %s, which clashes or is not what clean_set says"
					% [tag, str(played)]
				)
			)
		if int(played.get(a, 0)) != int(c["a_rank"]):
			_fail("%s: the first named lost a rank (%s)" % [tag, str(played)])
		if int(played.get(b, 0)) >= int(c["b_rank"]):
			_fail("%s: the second named kept its rank (%s)" % [tag, str(played)])
		if h.set_points() >= h.total_points(pair):
			_fail("%s: the refused set is not worth less than the one asked for" % tag)
	h.clear_set()
	# all 432 sets of ranks: what is played is legal, within the top total, and every cap holds
	var sets = []
	_all_sets(h.modifier_ids(), 0, {}, sets)
	var seen_top = 0
	for raw in sets:
		var tag = "set %s" % str(raw)
		var played = h.play_set(raw)
		if not h.is_legal(played):
			_fail("%s: played %s, which has a clash" % [tag, str(played)])
		if h.is_legal(raw) and played != raw:
			_fail("%s: a legal set was changed to %s" % [tag, str(played)])
		var points = h.set_points()
		if points > h.top_total:
			_fail("%s: worth %d, over the top total %d" % [tag, points, h.top_total])
		seen_top = maxi(seen_top, points)
		_stack_caps(tag)
	if seen_top != h.top_total:
		_fail(
			(
				"the best set that can be played is worth %d, the top total is %d"
				% [seen_top, h.top_total]
			)
		)
	h.clear_set()
	# the set with every rank maxed is refused down to a legal one; the best sets are played as they are
	var all_max = {}
	for id in h.modifier_ids():
		all_max[id] = h.max_rank(id)
	var best = []
	for raw in sets:
		if h.is_legal(raw) and h.total_points(raw) == h.top_total:
			best.append(raw)
	if best.is_empty():
		_fail("no legal set is worth the top total %d" % h.top_total)
	var runs = [["every rank maxed", all_max]]
	for i in range(best.size()):
		runs.append(["top total set %d of %d" % [i + 1, best.size()], best[i]])
	# a set that skipped play_set (a hand-edited save that went round clean_set): the caps are in the code that plays
	# each effect, so they must hold without the clash rule
	h.set_ranks = all_max.duplicate()
	h.set_effects = h.effects_of(all_max)
	_stack_caps("every rank maxed with the clash rule skipped")
	_play_round("every rank maxed with the clash rule skipped", cap)
	h.clear_set()
	for run in runs:
		var played = h.play_set(run[1])
		_stack_caps(str(run[0]))
		_play_round("%s (%s)" % [run[0], str(played)], cap)
		h.clear_set()
	# hearts never below one: the table cannot take more than 2 hearts off 3 (the range of hearts_minus), and a table and a
	# set that both went round their checks (a hearts_min cap under 1, which the loader reads as 0, and 5 hearts taken off)
	# still leave 1
	if int(HeatScript.RANGES["hearts_minus"][1]) >= START_HEARTS:
		_fail(
			(
				"hearts_minus may take %d hearts off the %d of a run"
				% [HeatScript.RANGES["hearts_minus"][1], START_HEARTS]
			)
		)
	for silly in [0.4, 0.0]:
		var own = HeatScript.new()
		own.caps["hearts_min"] = silly
		own.set_effects = own.effects_of({})
		own.set_effects["hearts_minus"] = 5
		if own.start_hearts() != 1:
			_fail(
				(
					"a hearts_min cap of %s with 5 hearts taken off left %d hearts, expected 1"
					% [silly, own.start_hearts()]
				)
			)
	# a Daily Run is Heat 0 for everybody, so it puts a played set away
	h.play_set(all_max)
	main.heat = h.top_level()
	main.start_game(true)
	if h.has_set() or main.heat != 0 or main.MAXHEARTS != START_HEARTS:
		_fail(
			(
				"a Daily Run after a set was played has set %s, Heat %d and %d hearts, expected none, 0 and %d"
				% [h.has_set(), main.heat, main.MAXHEARTS, START_HEARTS]
			)
		)
	for key in HeatScript.NEUTRAL:
		if not is_equal_approx(h.value(key), float(HeatScript.NEUTRAL[key])):
			_fail(
				(
					"a Daily Run after a set was played: %s is %s, Heat 0 changes nothing"
					% [key, h.value(key)]
				)
			)
	h.clear_set()
	main.heat = 0
	main.daily_mode = false
	main.go_to_title()


# every set of ranks of `ids` from index `i` on, added to `out` (rank 0 is left out of the dictionary)
func _all_sets(ids: Array, i: int, cur: Dictionary, out: Array) -> void:
	if i >= ids.size():
		out.append(cur.duplicate())
		return
	var id = str(ids[i])
	for rank in range(main.heat_sys.max_rank(id) + 1):
		if rank > 0:
			cur[id] = rank
		_all_sets(ids, i + 1, cur, out)
		cur.erase(id)


# the caps of the table, read through the set that is played now
func _stack_caps(tag: String) -> void:
	var h = main.heat_sys
	var cap = int(h.caps["riders_max"])
	var hearts = h.start_hearts()
	if hearts < 1 or hearts > START_HEARTS or hearts < int(h.caps["hearts_min"]):
		_fail(
			(
				"%s: a run starts with %d hearts (at least %d, at most %d)"
				% [tag, hearts, maxi(1, int(h.caps["hearts_min"])), START_HEARTS]
			)
		)
	var cash = h.cash_factor()
	if cash < float(h.caps["cash_min"]) - 0.0001 or cash > 1.0:
		_fail("%s: cash is x%s, the cap is x%s to x1" % [tag, cash, h.caps["cash_min"]])
	if h.price_factor() < 1.0 - 0.0001:
		_fail("%s: prices are x%s, Heat never makes them lower" % [tag, h.price_factor()])
	if h.boss_health(100) < 100:
		_fail("%s: a boss of 100 health has %d" % [tag, h.boss_health(100)])
	for mix in [
		{"pro": 5, "sprinter": 2, "courier": 1},
		{"pro": 6, "tough": 2, "sprinter": 2, "courier": 1},
		{"pro": 12},
		{"pro": cap - 1},
		{"pro": cap},
	]:
		var plan = []
		for kind in mix:
			for k in range(int(mix[kind])):
				plan.append(kind)
		var res = h.with_extra_riders(plan, mix)
		if res.size() < plan.size() or (plan.size() <= cap and res.size() > cap):
			_fail("%s: %d riders became %d, the cap is %d" % [tag, plan.size(), res.size(), cap])
		if not _is_subsequence(plan, res):
			_fail("%s: the seed's riders lost their order" % tag)


# a real run with the set that is played now: it starts with the right hearts, picks a round and begins it, and its
# riders on late floors never aim past RIDER_SPEED_CAP (a rider that spawns faster than the cap, as late sprinters do at
# every Heat including 0, only slows down to it)
func _play_round(tag: String, cap: int) -> void:
	var h = main.heat_sys
	main.generated_arena = true
	main.heat = 0
	main.start_game(false, SEED)
	var hearts = h.start_hearts()
	if main.MAXHEARTS != hearts or main.hearts != hearts:
		_fail(
			(
				"%s: a new run has %d of %d hearts, expected %d"
				% [tag, main.hearts, main.MAXHEARTS, hearts]
			)
		)
	main.pick_node(0)
	if main.state != "play":
		_fail("%s: could not start a round (state %s)" % [tag, main.state])
		main.go_to_title()
		return
	if main.rider_plan.size() > cap or main.PER_ROUND > cap or main.rider_plan.is_empty():
		_fail(
			(
				"%s: the round has %d riders (PER_ROUND %d), expected 1 to %d"
				% [tag, main.rider_plan.size(), main.PER_ROUND, cap]
			)
		)
	var state_before = main.state
	main.round_n = 10
	for idx in [0, 6]:
		main.next_idx = idx
		for k in range(8):
			var r = main.rider_sys.spawn_rider(k % 3, 1)
			var peak_allowed = maxf(float(r["spd"]), Riders.RIDER_SPEED_CAP) + 0.05
			r["age"] = 1000.0
			main.state = "check"  # nobody gets run over, and a finished rider does not end the round
			var late = 0.0
			var peak = 0.0
			for i in range(240):
				r["tgt"] = 1000.0
				r["chg"] = 1000.0
				main.rider_sys.update_rider(r, DT)
				peak = maxf(peak, float(r["spd"]))
				if i >= 180:
					late = maxf(late, float(r["spd"]))
			main.state = state_before
			if late > Riders.RIDER_SPEED_CAP + 0.05:
				_fail(
					(
						"%s: a %s rider on floor 10 still rides %.2f m/s after 3 s, the cap is %.1f"
						% [tag, str(r.get("type", "?")), late, Riders.RIDER_SPEED_CAP]
					)
				)
			if peak > peak_allowed:
				_fail(
					(
						"%s: a %s rider sped up to %.2f m/s, from %.2f and under the cap %.1f"
						% [
							tag,
							str(r.get("type", "?")),
							peak,
							peak_allowed - 0.05,
							Riders.RIDER_SPEED_CAP
						]
					)
				)
			main.clear_riders()
	main.next_idx = 0
	main.heat = 0
	main.go_to_title()


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


# the table of data/heat.json as the H1 chunks left it: every effect at every level of the ladder (README H1.5 to H1.9).
# The modifiers of H2.2 build the levels, and this is what proves they build the same ones.
const LADDER = [
	{},
	{"rider_speed": 1.1},
	{"rider_speed": 1.1, "riders_more": 0.2},
	{"rider_speed": 1.1, "riders_more": 0.2, "hearts_minus": 1},
	{
		"rider_speed": 1.1,
		"riders_more": 0.2,
		"hearts_minus": 1,
		"tough_hp_plus": 1,
		"boss_hp": 1.15
	},
	{
		"rider_speed": 1.1,
		"riders_more": 0.2,
		"hearts_minus": 1,
		"tough_hp_plus": 1,
		"boss_hp": 1.15,
		"price": 1.2,
		"cash": 0.8
	},
]


# README H2.2: the modifiers, their ranks and points, the clashing pairs and the presets that name sets of ranks
func _check_modifiers() -> void:
	var h = main.heat_sys
	var top = h.top_level()
	var ids = h.modifier_ids()
	if ids != ["swift", "crowd", "lives", "tough", "stingy"]:
		_fail("the modifiers are %s, expected the five of docs/HEAT.md" % str(ids))
	# every rank is worth more than the one before it, sets effects of its own, and stays inside the allowed range
	var owner = {}
	for m in h.modifiers:
		var last = 0
		for r in range(m["ranks"].size()):
			var rank = m["ranks"][r]
			if int(rank["points"]) <= last:
				_fail(
					(
						"%s rank %d is worth %d, not more than the rank before it"
						% [m["id"], r + 1, int(rank["points"])]
					)
				)
			last = int(rank["points"])
			for key in rank["effects"]:
				if not HeatScript.NEUTRAL.has(key):
					_fail("%s rank %d sets %s, which is not an effect" % [m["id"], r + 1, key])
				if r > 0:
					var before = float(m["ranks"][r - 1]["effects"][key])
					var now = float(rank["effects"][key])
					var harder = now <= before + 0.0001 if key == "cash" else now >= before - 0.0001
					if not harder:
						_fail(
							(
								"%s rank %d makes %s easier than the rank before (%s after %s)"
								% [m["id"], r + 1, key, now, before]
							)
						)
				if owner.has(key) and owner[key] != m["id"]:
					_fail("%s is set by both %s and %s" % [key, owner[key], m["id"]])
				owner[key] = m["id"]
	# the presets: the ladder is built from them, and the total of every preset is the Heat it names
	if h.levels.size() != LADDER.size():
		_fail("the table has %d levels, expected %d" % [h.levels.size(), LADDER.size()])
	var before_ranks = {}
	for level in range(mini(h.levels.size(), LADDER.size())):
		if h.preset_points(level) != level:
			_fail(
				(
					"preset %d is worth %d points, it has to be worth %d"
					% [level, h.preset_points(level), level]
				)
			)
		var ranks = h.preset_ranks(level)
		if h.total_points(ranks) != level:
			_fail(
				"the total of preset %d is %d, expected %d" % [level, h.total_points(ranks), level]
			)
		if not h.is_legal(ranks):
			_fail("preset %d is not a legal set (a clash, or a rank out of range)" % level)
		for id in before_ranks:
			if int(ranks.get(id, 0)) < int(before_ranks[id]):
				_fail("preset %d has less of %s than preset %d" % [level, id, level - 1])
		before_ranks = ranks
		var fx = h.effects_of(ranks)
		for key in HeatScript.NEUTRAL:
			var want = float(LADDER[level].get(key, HeatScript.NEUTRAL[key]))
			if not is_equal_approx(h.value(key, level), want):
				_fail(
					(
						"level %d has %s %s, the ladder of H1 had %s"
						% [level, key, h.value(key, level), want]
					)
				)
			if not is_equal_approx(float(fx[key]), want):
				_fail(
					"the effects of preset %d have %s %s, expected %s" % [level, key, fx[key], want]
				)
		if level > 0 and h.preset_ranks(level).size() != level:
			_fail(
				(
					"preset %d names %d modifiers, expected %d (each level adds one at rank 1)"
					% [level, h.preset_ranks(level).size(), level]
				)
			)
		if h.start_hearts(level) < 2:
			_fail(
				(
					"preset %d leaves %d hearts, the ladder never goes below 2"
					% [level, h.start_hearts(level)]
				)
			)
	# the arithmetic on sets
	if h.total_points({}) != 0 or h.total_points({"swift": 0}) != 0:
		_fail("an empty set is not worth 0 points")
	if h.total_points({"swift": 3, "lives": 2}) != 8:
		_fail(
			(
				"swift 3 and lives 2 are worth %d points, expected 8"
				% h.total_points({"swift": 3, "lives": 2})
			)
		)
	if h.total_points({"nothing": 2, "swift": -1, "crowd": 9}) != 2:
		_fail(
			(
				"an unknown id and a negative rank should count 0 and a rank past the end the top rank (expected 2, got %d)"
				% h.total_points({"nothing": 2, "swift": -1, "crowd": 9})
			)
		)
	if h.points_of("swift", 2) != 2 or h.points_of("swift", 3) != 4 or h.points_of("lives", 2) != 4:
		_fail("the points of swift 2, swift 3 or lives 2 are not 2, 4 and 4")
	if h.max_rank("swift") != 3 or h.max_rank("crowd") != 2 or h.max_rank("nothing") != 0:
		_fail("max_rank is not 3 for swift, 2 for crowd and 0 for an id that does not exist")
	# clashes: found, refused, and a set made legal by holding the second modifier of the clash back one rank at a time
	var bad = {"lives": 2, "swift": 3}
	if h.is_legal(bad) or h.clashes_in(bad).size() != 1 or h.clashes_in(bad)[0]["why"] == "":
		_fail("lives 2 with swift 3 should be one clash with a reason")
	if (
		not h.is_legal({"lives": 2, "swift": 2, "crowd": 1})
		or not h.is_legal({"lives": 1, "swift": 3, "crowd": 2})
	):
		_fail(
			"lives 2 with swift 2 and crowd 1, or lives 1 with swift 3 and crowd 2, should be legal"
		)
	if (
		h.is_legal({"swift": 4})
		or h.is_legal({"swift": -1})
		or h.is_legal({"nothing": 1})
		or h.is_legal({"swift": 1.0})
	):
		_fail(
			"a rank past the end, a negative rank, an unknown id and a rank that is not a whole number should not be legal"
		)
	var messy = {"lives": 2, "swift": 3, "crowd": 2, "tough": 2, "stingy": 3}
	var fixed = h.clean_set(messy)
	if fixed != {"lives": 2, "swift": 2, "crowd": 1, "tough": 2, "stingy": 2}:
		_fail("clean_set of every clash at once gave %s" % str(fixed))
	if messy != {"lives": 2, "swift": 3, "crowd": 2, "tough": 2, "stingy": 3}:
		_fail("clean_set changed the set it was given")
	var cast = h.clean_set(
		{
			"swift": 2.9,
			"crowd": 9,
			"lives": -1,
			"tough": "x",
			"stingy": null,
			"nothing": 1,
			"extra": 0
		}
	)
	if cast != {"swift": 2, "crowd": 2}:
		_fail("clean_set of bad values gave %s, expected swift 2 and crowd 2" % str(cast))
	# every combination of ranks: 432 of them, 330 without a clash, none worth more than the top total, and clean_set
	# makes every one of them legal without going over
	var counts = [
		h.max_rank("swift"),
		h.max_rank("crowd"),
		h.max_rank("lives"),
		h.max_rank("tough"),
		h.max_rank("stingy")
	]
	var every = 0
	var legal = 0
	var best = 0
	var at_best = 0
	var worst_cash = 1.0
	for a in range(counts[0] + 1):
		for b in range(counts[1] + 1):
			for c in range(counts[2] + 1):
				for d in range(counts[3] + 1):
					for e in range(counts[4] + 1):
						var combo = {"swift": a, "crowd": b, "lives": c, "tough": d, "stingy": e}
						every += 1
						var cleaned = h.clean_set(combo)
						if not h.is_legal(cleaned):
							_fail("clean_set of %s is not legal: %s" % [str(combo), str(cleaned)])
						if h.total_points(cleaned) > h.total_points(combo):
							_fail("clean_set of %s is worth more than the set" % str(combo))
						if h.is_legal(combo):
							legal += 1
							var total = h.total_points(combo)
							if cleaned != h.clean_set(cleaned) or h.total_points(cleaned) != total:
								_fail("clean_set changed the legal set %s" % str(combo))
							if total > best:
								best = total
								at_best = 0
							if total == best:
								at_best += 1
							var fx = h.effects_of(combo)
							var hearts = START_HEARTS - int(fx["hearts_minus"])
							if hearts < int(h.caps["hearts_min"]):
								_fail(
									(
										"%s leaves %d hearts, the cap is %d"
										% [str(combo), hearts, int(h.caps["hearts_min"])]
									)
								)
							if float(fx["cash"]) < float(h.caps["cash_min"]) - 0.0001:
								_fail(
									(
										"%s pays %s of the cash, the cap is %s"
										% [str(combo), fx["cash"], h.caps["cash_min"]]
									)
								)
							worst_cash = minf(worst_cash, float(fx["cash"]))
	if every != 432 or legal != 330:
		_fail(
			(
				"there are %d sets of ranks of which %d have no clash, expected 432 and 330"
				% [every, legal]
			)
		)
	if best != h.top_total or best != 12 or at_best != 2:
		_fail(
			(
				"the top total is %d (table says %d) with %d sets, expected 12 with 2"
				% [best, h.top_total, at_best]
			)
		)
	if h.top_total < top:
		_fail("the top total %d is below the top level %d" % [h.top_total, top])


func _check_bad_data() -> void:
	var rank_a1 = {"points": 1, "desc": "X", "rider_speed": 1.2}
	var rank_a2 = {"points": 3, "desc": "Y", "rider_speed": 1.4}
	var mod_a = {"id": "a", "name": "A", "ranks": [rank_a1, rank_a2]}
	var mod_b = {"id": "b", "name": "B", "ranks": [{"points": 1, "desc": "X", "cash": 0.8}]}
	var clash_ab = {"a": ["a", 2], "b": ["b", 1], "why": "BECAUSE"}
	var p0 = {"level": 0, "name": "A", "desc": "B", "ranks": {}}
	var p1 = {"level": 1, "name": "C", "desc": "D", "ranks": {"a": 1}}
	var good = {"modifiers": [mod_a, mod_b], "clashes": [clash_ab], "presets": [p0, p1]}
	# not a table at all, or no modifiers or presets: level 0 only
	for bad in [null, [], {}, {"modifiers": "x", "presets": []}, {"modifiers": [], "presets": "x"}]:
		var t = HeatScript.parse(bad)
		if (
			t["levels"].size() != 1
			or not t["modifiers"].is_empty()
			or not is_equal_approx(float(t["levels"][0]["rider_speed"]), 1.0)
		):
			_fail("a table that is not valid should give level 0 only (%s)" % str(bad))
	# a good table
	var t = HeatScript.parse(good)
	if t["levels"].size() != 2 or not is_equal_approx(float(t["levels"][1]["rider_speed"]), 1.2):
		_fail("a good table did not load")
	elif not is_equal_approx(float(t["levels"][1]["cash"]), 1.0):
		_fail("an effect that no rank of the preset sets should keep its neutral value")
	elif int(t["levels"][1]["points"]) != 1 or t["levels"][1]["ranks"] != {"a": 1}:
		_fail("the level made from a preset has the wrong points or ranks")
	if t["modifiers"].size() != 2 or t["clashes"].size() != 1 or int(t["top_total"]) != 3:
		_fail(
			(
				"a good table has %d modifiers, %d clashes and top total %s, expected 2, 1 and 3"
				% [t["modifiers"].size(), t["clashes"].size(), str(t["top_total"])]
			)
		)
	# level 0 missing: the game runs without Heat
	t = HeatScript.parse({"modifiers": [mod_a], "presets": [p1]})
	if t["levels"].size() != 1:
		_fail(
			"a table without level 0 should give level 0 only, got %d levels" % t["levels"].size()
		)
	# level 0 that names ranks is set back to nothing
	t = HeatScript.parse(
		{
			"modifiers": [mod_a],
			"presets": [{"level": 0, "name": "A", "desc": "B", "ranks": {"a": 2}}, p1]
		}
	)
	if (
		not is_equal_approx(float(t["levels"][0]["rider_speed"]), 1.0)
		or not t["levels"][0]["ranks"].is_empty()
	):
		_fail("level 0 that named a rank was not set back to nothing")
	# a gap: the level after it is dropped
	var p3 = {"level": 3, "name": "E", "desc": "F", "ranks": {}}
	t = HeatScript.parse({"modifiers": [mod_a], "presets": [p0, p1, p3]})
	if t["levels"].size() != 2:
		_fail("a level after a gap should be dropped, got %d levels" % t["levels"].size())
	# a preset that is refused: a duplicate, an unknown modifier, a rank out of range or not whole, a missing text
	var bad_presets = [
		{"level": 1, "name": "X", "desc": "Y", "ranks": {}},
		{"level": 2, "name": "X", "desc": "Y", "ranks": {"nothing": 1}},
		{"level": 2, "name": "X", "desc": "Y", "ranks": {"a": 3}},
		{"level": 2, "name": "X", "desc": "Y", "ranks": {"a": -1}},
		{"level": 2, "name": "X", "desc": "Y", "ranks": {"a": 1.5}},
		{"level": 2, "name": "X", "desc": "Y", "ranks": {"a": "1"}},
		{"level": 2, "name": "X", "desc": "Y", "ranks": [1]},
		{"level": 2, "name": "", "desc": "Y", "ranks": {}},
		{"level": 2, "name": "X", "ranks": {}},
		{"level": 1.5, "name": "X", "desc": "Y", "ranks": {}},
		{"name": "X", "desc": "Y", "ranks": {}},
		{"level": 99, "name": "X", "desc": "Y", "ranks": {}},
		"not an object",
	]
	for i in range(bad_presets.size()):
		t = HeatScript.parse({"modifiers": [mod_a], "presets": [p0, p1, bad_presets[i]]})
		if t["levels"].size() != 2:
			_fail("bad preset %d was not refused (%s)" % [i, str(bad_presets[i])])
	# a rank of 0 is the same as leaving the modifier out
	t = HeatScript.parse(
		{
			"modifiers": [mod_a],
			"presets": [p0, {"level": 1, "name": "X", "desc": "Y", "ranks": {"a": 0}}]
		}
	)
	if t["levels"].size() != 2 or not t["levels"][1]["ranks"].is_empty():
		_fail("a rank of 0 should be the same as leaving the modifier out")
	# a modifier that is refused (it must not stop the good one next to it from loading)
	var bad_mods = [
		{"id": "a", "name": "AGAIN", "ranks": [rank_a1]},
		{"id": "Big", "name": "X", "ranks": [rank_a1]},
		{"id": "has space", "name": "X", "ranks": [rank_a1]},
		{"name": "X", "ranks": [rank_a1]},
		{"id": "c", "ranks": [{"points": 1, "desc": "X", "price": 1.2}]},
		{"id": "c", "name": "", "ranks": [{"points": 1, "desc": "X", "price": 1.2}]},
		{"id": "c", "name": "C"},
		{"id": "c", "name": "C", "ranks": []},
		{
			"id": "c",
			"name": "C",
			"ranks":
			[
				{"points": 1, "desc": "X", "price": 1.2},
				{"points": 2, "desc": "X", "price": 1.3},
				{"points": 3, "desc": "X", "price": 1.4},
				{"points": 4, "desc": "X", "price": 1.5},
				{"points": 5, "desc": "X", "price": 1.6},
				{"points": 6, "desc": "X", "price": 1.7}
			]
		},
		{
			"id": "c",
			"name": "C",
			"ranks":
			[{"points": 2, "desc": "X", "price": 1.2}, {"points": 2, "desc": "X", "price": 1.3}]
		},
		{"id": "c", "name": "C", "ranks": [{"points": 0, "desc": "X", "price": 1.2}]},
		{"id": "c", "name": "C", "ranks": [{"points": 1.5, "desc": "X", "price": 1.2}]},
		{"id": "c", "name": "C", "ranks": [{"points": 101, "desc": "X", "price": 1.2}]},
		{"id": "c", "name": "C", "ranks": [{"points": 1, "price": 1.2}]},
		{"id": "c", "name": "C", "ranks": [{"points": 1, "desc": "X", "speed": 1.2}]},
		{"id": "c", "name": "C", "ranks": [{"points": 1, "desc": "X"}]},
		{"id": "c", "name": "C", "ranks": [{"points": 1, "desc": "X", "price": "high"}]},
		{"id": "c", "name": "C", "ranks": [{"points": 1, "desc": "X", "price": 0.5}]},
		{"id": "c", "name": "C", "ranks": [{"points": 1, "desc": "X", "cash": 1.5}]},
		{"id": "c", "name": "C", "ranks": [{"points": 1, "desc": "X", "tough_hp_plus": 1.5}]},
		{
			"id": "c",
			"name": "C",
			"ranks":
			[{"points": 1, "desc": "X", "price": 1.2}, {"points": 2, "desc": "X", "cash": 0.9}]
		},
		{"id": "c", "name": "C", "ranks": [{"points": 1, "desc": "X", "rider_speed": 1.2}]},
		{"id": "c", "name": "C", "ranks": ["not an object"]},
		"not an object",
	]
	for i in range(bad_mods.size()):
		t = HeatScript.parse({"modifiers": [mod_a, bad_mods[i], mod_b], "presets": [p0]})
		if t["modifiers"].size() != 2:
			_fail("bad modifier %d was not refused (%s)" % [i, str(bad_mods[i])])
	# a clash that is refused: an unknown modifier, a rank out of range, one modifier twice, no reason, not an object
	var bad_clashes = [
		{"a": ["nothing", 1], "b": ["b", 1], "why": "X"},
		{"a": ["a", 3], "b": ["b", 1], "why": "X"},
		{"a": ["a", 0], "b": ["b", 1], "why": "X"},
		{"a": ["a", 1.5], "b": ["b", 1], "why": "X"},
		{"a": ["a", 1], "b": ["a", 2], "why": "X"},
		{"a": ["a", 1], "b": ["b", 1]},
		{"a": ["a", 1], "b": ["b", 1], "why": ""},
		{"a": ["a", 1], "why": "X"},
		{"a": "a", "b": ["b", 1], "why": "X"},
		{"a": [1, 1], "b": ["b", 1], "why": "X"},
		"not an object",
	]
	for i in range(bad_clashes.size()):
		t = HeatScript.parse(
			{"modifiers": [mod_a, mod_b], "clashes": [clash_ab, bad_clashes[i]], "presets": [p0]}
		)
		if t["clashes"].size() != 1:
			_fail("bad clash %d was not refused (%s)" % [i, str(bad_clashes[i])])
	t = HeatScript.parse({"modifiers": [mod_a, mod_b], "clashes": "x", "presets": [p0]})
	if t["modifiers"].size() != 2 or not t["clashes"].is_empty():
		_fail(
			"clashes that are not an array should load as no clashes and leave the modifiers alone"
		)
	# the top total follows the clashes: a and b together are 3 + 1, a clash between rank 2 of a and b makes it 3
	t = HeatScript.parse({"modifiers": [mod_a, mod_b], "clashes": [], "presets": [p0]})
	if int(t["top_total"]) != 4:
		_fail("with no clash the top total is %s, expected 4" % str(t["top_total"]))
	t = HeatScript.parse({"modifiers": [mod_a, mod_b], "clashes": [clash_ab], "presets": [p0]})
	if int(t["top_total"]) != 3:
		_fail("with the clash the top total is %s, expected 3" % str(t["top_total"]))
	# caps: a bad number falls back to the default, a good one is taken
	t = HeatScript.parse(
		{"modifiers": [], "presets": [p0], "caps": {"riders_max": -1, "hearts_min": 1}}
	)
	if int(t["caps"]["riders_max"]) != int(HeatScript.CAP_DEFAULTS["riders_max"]):
		_fail("a bad riders_max cap was not replaced by the default")
	if int(t["caps"]["hearts_min"]) != 1:
		_fail("a good hearts_min cap was not taken")
	# a missing file gives level 0 only
	t = HeatScript.load_table("res://data/no_such_heat_table.json")
	if t["levels"].size() != 1:
		_fail("a missing file should give level 0 only")


# README H3.2: what Heat pays (docs/HEAT.md, "Rewards"). The arithmetic of `reward_bonus` against the worked examples of the
# note, the table entry, and runs paid through the real `Meta.award_run`. The real meta.json is kept and put back.
func _check_rewards() -> void:
	var h = main.heat_sys
	var top = h.top_level()
	var XpScript = load("res://scripts/xp.gd")
	var keep_heat = main.heat
	var keep_state = [main.score, main.kills, main.round_n, main.run_won]
	var path = main.meta.PATH
	var had = FileAccess.file_exists(path)
	var kept = PackedByteArray()
	if had:
		kept = FileAccess.get_file_as_bytes(path)
	# the table entry and its defaults
	if int(h.rewards["pct_per_point"]) != 10 or int(h.rewards["min"]) != 1:
		_fail(
			(
				"the rewards entry is %s, expected 10 percent per point and a minimum of 1"
				% str(h.rewards)
			)
		)
	var raw = JSON.parse_string(FileAccess.get_file_as_string(HeatScript.PATH))
	var kept_rewards = raw["rewards"]
	for bad in [
		{"pct_per_point": -5},
		{"pct_per_point": 250},
		{"pct_per_point": "x"},
		{"min": 2.5},
		{"min": -1}
	]:
		raw["rewards"] = bad
		var t = HeatScript.parse(raw)
		if t["rewards"] != HeatScript.REWARD_DEFAULTS:
			_fail(
				(
					"a bad rewards entry %s was not replaced by the defaults, got %s"
					% [str(bad), str(t["rewards"])]
				)
			)
	raw["rewards"] = "text"
	if HeatScript.parse(raw)["rewards"] != HeatScript.REWARD_DEFAULTS:
		_fail("a rewards entry that is not an object was not replaced by the defaults")
	raw.erase("rewards")
	if HeatScript.parse(raw)["rewards"] != HeatScript.REWARD_DEFAULTS:
		_fail("a table with no rewards entry did not get the defaults")
	raw["rewards"] = {"pct_per_point": 20, "min": 2}
	var custom = HeatScript.parse(raw)["rewards"]
	if int(custom["pct_per_point"]) != 20 or int(custom["min"]) != 2:
		_fail("a good rewards entry was not taken, got %s" % str(custom))
	raw["rewards"] = kept_rewards
	# the arithmetic against the worked examples of the note
	var examples = [
		[33, {0: 0, 1: 3, 2: 7, 3: 10, 4: 13, 5: 17, 12: 40}],
		[4, {0: 0, 1: 1, 2: 1, 3: 1, 4: 2, 5: 2, 12: 5}],
		[2, {0: 0, 1: 1, 3: 1, 5: 1, 7: 1, 12: 2}],
		[485, {0: 0, 1: 49, 3: 146, 5: 243, 12: 582}],
		[0, {0: 0, 1: 0, 5: 0, 12: 0}],
		[-7, {0: 0, 5: 0}],
	]
	for e in examples:
		for pts in e[1]:
			var got = h.reward_bonus(int(e[0]), int(pts))
			if got != e[1][pts]:
				_fail("reward_bonus(%d, %d) is %d, the note says %d" % [e[0], pts, got, e[1][pts]])
	# never negative, never less than +1 from Heat 1 up on a base above 0, and more points never pay less
	for base in range(0, 61):
		var last = 0
		for pts in range(0, 13):
			var b = h.reward_bonus(base, pts)
			if b < last:
				_fail(
					(
						"base %d: %d points pay %d, less than the %d of the point below"
						% [base, pts, b, last]
					)
				)
			if pts >= 1 and base >= 1 and b < 1:
				_fail("base %d at %d points pays less than 1" % [base, pts])
			if (pts == 0 or base == 0) and b != 0:
				_fail("base %d at %d points pays %d, expected 0" % [base, pts, b])
			last = b
	# points past the table are kept to what the table can ask for
	if h.reward_bonus(33, 999) != h.reward_bonus(33, h.total_cap()):
		_fail("999 points do not pay the same as the top total")
	# -1 is the run being played: the level of the run, or the set of ranks played, which wins
	main.heat = 3
	if h.reward_bonus(33) != 10:
		_fail("reward_bonus(33) at Heat 3 is %d, expected 10" % h.reward_bonus(33))
	main.heat = 0
	if h.reward_bonus(33) != 0:
		_fail("reward_bonus(33) at Heat 0 is %d, expected 0" % h.reward_bonus(33))
	h.play_set({"swift": 2, "crowd": 1, "lives": 1})  # 2 + 1 + 1 = 4 points
	main.heat = 4
	if h.reward_bonus(33) != 13 or h.reward_bonus(33) != h.reward_bonus(33, 4):
		_fail("a set worth 4 points pays %d on 33, expected 13" % h.reward_bonus(33))
	h.clear_set()
	# runs paid through the real award_run
	# every round cleared, a boss, the final boss and 2 cache coins: 33 with the 10 rounds of the note
	var base_coins = (
		main.MAX_ROUNDS * main.meta.COINS_PER_ROUND
		+ main.meta.COINS_PER_BOSS
		+ main.meta.COINS_FINAL_BOSS
		+ 2
	)
	var won_run = {
		"round": main.MAX_ROUNDS,
		"won": true,
		"kills": 120,
		"bosses": [["boss", false], ["any", true]],
		"caches": 2
	}
	var xp_table = XpScript.table
	var bonusable = (
		120 * int(xp_table["per_kill"])
		+ main.MAX_ROUNDS * int(xp_table["per_round"])
		+ int(xp_table["run_won"])
		+ int(xp_table["boss"]["boss"])
		+ int(xp_table["boss"]["final"])
	)
	var last_coins = -1
	var last_xp = -1
	for level in range(top + 1):
		var r = _reward_run(level, won_run)
		var want_bonus = h.reward_bonus(base_coins, level)
		var want_xp_bonus = h.reward_bonus(bonusable, level)
		if base_coins == 33 and level <= 5:
			var doc = {0: 0, 1: 3, 2: 7, 3: 10, 4: 13, 5: 17}
			if r["coins"] != doc[level]:
				_fail(
					(
						"a won run at Heat %d paid %d bonus coins, the note says %d"
						% [level, r["coins"], doc[level]]
					)
				)
		if (
			r["coins"] != want_bonus
			or r["n"] != base_coins + want_bonus
			or main.meta_earned != r["n"]
		):
			_fail(
				(
					"Heat %d: the won run paid %d coins (bonus %d), expected %d (bonus %d)"
					% [level, r["n"], r["coins"], base_coins + want_bonus, want_bonus]
				)
			)
		if r["xp_heat"] != want_xp_bonus or r["xp"] != bonusable + want_xp_bonus:
			_fail(
				(
					"Heat %d: the won run paid %d XP (bonus %d), expected %d (bonus %d)"
					% [level, r["xp"], r["xp_heat"], bonusable + want_xp_bonus, want_xp_bonus]
				)
			)
		if (
			level == 0
			and (
				r["coins"] != 0 or r["xp_heat"] != 0 or r["n"] != base_coins or r["xp"] != bonusable
			)
		):
			_fail(
				(
					"Heat 0 pays %d coins and %d XP, expected %d and %d as before Heat"
					% [r["n"], r["xp"], base_coins, bonusable]
				)
			)
		if r["n"] <= last_coins or r["xp"] <= last_xp:
			_fail(
				(
					"Heat %d pays %d coins and %d XP, not more than the level below"
					% [level, r["n"], r["xp"]]
				)
			)
		last_coins = r["n"]
		last_xp = r["xp"]
	# the score and its coins and XP are not multiplied: the cap of 5 coins stays 5, and the score XP is added once
	var scored = won_run.duplicate()
	scored["score"] = main.meta.SCORE_PER_COIN * 40
	var r5 = _reward_run(5, scored)
	var bonus5 = h.reward_bonus(base_coins, 5)
	if r5["n"] != main.meta.SCORE_COINS_MAX + base_coins + bonus5:
		_fail(
			(
				"a Heat 5 run with a huge score paid %d coins, expected %d"
				% [r5["n"], main.meta.SCORE_COINS_MAX + base_coins + bonus5]
			)
		)
	var score_xp = floori(float(scored["score"]) / float(xp_table["score_per_xp"]))
	if (
		r5["xp_heat"] != h.reward_bonus(bonusable, 5)
		or r5["xp"] != score_xp + bonusable + r5["xp_heat"]
	):
		_fail(
			(
				"a Heat 5 run with a big score paid %d XP with a bonus of %d, the score XP must not be in the bonus"
				% [r5["xp"], r5["xp_heat"]]
			)
		)
	# a lost run is paid in proportion; a run that earned nothing is paid nothing at any Heat
	var lost = _reward_run(4, {"round": 3})  # two rounds cleared: 4 coins
	if lost["n"] != 4 + h.reward_bonus(4, 4) or lost["coins"] != 2:
		_fail(
			(
				"a run lost in round 3 at Heat 4 paid %d coins (bonus %d), expected 6 (bonus 2)"
				% [lost["n"], lost["coins"]]
			)
		)
	for level in range(top + 1):
		var nothing = _reward_run(level, {"round": 1})
		if (
			nothing["n"] != 0
			or nothing["coins"] != 0
			or nothing["xp"] != 0
			or nothing["xp_heat"] != 0
		):
			_fail("a run that earned nothing paid %s at Heat %d" % [str(nothing), level])
	# a run pays once, and a quit run (award_run is never called for it) pays nothing
	var once = _reward_run(5, won_run)
	var again = main.meta.award_run()
	if again != 0 or main.meta.heat_coins != once["coins"]:
		_fail(
			(
				"paying the run a second time paid %d coins or changed the Heat coins to %d"
				% [again, main.meta.heat_coins]
			)
		)
	main.heat = 5
	main.meta.begin_run()
	main.score = 999999
	main.round_n = 6
	if main.meta_earned != 0 or main.meta.heat_coins != 0 or main.meta.heat_xp != 0:
		_fail("a new run did not start with no Heat pay")
	# a set of the player's own pays by its total
	h.play_set({"swift": 2, "crowd": 1, "lives": 1})
	var own = _reward_run(4, won_run)
	h.clear_set()
	if own["coins"] != h.reward_bonus(base_coins, 4):
		_fail(
			(
				"a set worth 4 points paid %d bonus coins, expected %d"
				% [own["coins"], h.reward_bonus(base_coins, 4)]
			)
		)
	# put everything back, and the real meta.json
	if had:
		var w = FileAccess.open(path, FileAccess.WRITE)
		w.store_buffer(kept)
		w.close()
	elif FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	main.meta.load_meta()
	main.meta.heat_open = top
	main.heat = keep_heat
	main.score = keep_state[0]
	main.kills = keep_state[1]
	main.round_n = keep_state[2]
	main.run_won = keep_state[3]
	main.meta.begin_run()


# pays one run through the real `Meta.award_run` at Heat `level` and says what it paid. `o` may hold round, won, kills,
# score, bosses ([[kind, final], ...]) and caches. Returns {"n": coins, "coins": the Heat coins, "xp", "xp_heat"}.
func _reward_run(level: int, o: Dictionary) -> Dictionary:
	main.heat = level
	main.meta.xp = 0
	main.meta.begin_run()
	main.challenges.begin_run()
	main.score = int(o.get("score", 0))
	main.kills = int(o.get("kills", 0))
	main.round_n = int(o.get("round", 1))
	main.run_won = bool(o.get("won", false))
	main.round_lives_lost = 0
	for b in o.get("bosses", []):
		main.meta.add_boss_kill(str(b[0]), bool(b[1]))
	for i in range(int(o.get("caches", 0))):
		main.meta.add_cache_coin()
	var n = main.meta.award_run()
	return {
		"n": n,
		"coins": main.meta.heat_coins,
		"xp": main.meta.xp_earned,
		"xp_heat": main.meta.heat_xp
	}


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
