extends SceneTree
# Checks the round clear rule (README Milestone K, "Gameplay on open ground"). Run from the project folder:
#   godot --headless --path . --script res://tools/round_clear_check.gd
# On the roundabout a rider that is not hit gives up and gets away, so a round needs NEED hits and is perfect only
# when all ten are hit. On a generated arena (rider pursuit) a rider never gives up, so every rider ends up hit:
# the round needs all of them, and a perfect round is one where no life was lost. Checks the rule's functions,
# that a rider on a generated arena has no time limit and does not keep speeding up, and that the round ends in
# "clear" with or without the PERFECT bonus. A seeded run (custom seed) is used, so no high score is saved.
# Exits with status 1 and prints the problems.

const SEED = 0x1234ABCD
const PERFECT_BONUS = 5000

var problems = []


func _initialize() -> void:
	await _roundabout()
	await _generated()
	if problems.is_empty():
		print("round_clear_check: the round clear rule holds on both arenas")
		quit(0)
	else:
		print("round_clear_check: %d problem(s)" % problems.size())
		for p in problems:
			print("  " + p)
		quit(1)


func _fail(text: String) -> void:
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


# riders can get away: NEED hits clear the round, only ten of ten is perfect
func _roundabout() -> void:
	var m = await _make_main(false)
	if not m.riders_can_escape():
		_fail("roundabout: riders cannot get away")
	if m.hits_needed() != m.NEED:
		_fail("roundabout: %d hits needed, not NEED (%d)" % [m.hits_needed(), m.NEED])
	if not m.is_perfect_round(m.PER_ROUND):
		_fail("roundabout: ten of ten is not a perfect round")
	if m.is_perfect_round(m.PER_ROUND - 1):
		_fail("roundabout: nine of ten is a perfect round")
	m.round_lives_lost = 3
	if not m.is_perfect_round(m.PER_ROUND):
		_fail("roundabout: losing lives spoils a perfect round, only the hits should count")
	_drop(m)


# riders cannot get away: all of them are hit, and a perfect round is one without a lost life
func _generated() -> void:
	var m = await _make_main(true)
	m.start_game(false, SEED)
	if m.state != "map":
		_fail("generated: a new run did not open the map (state %s)" % m.state)
		_drop(m)
		return
	m.pick_node(0)
	if m.state != "play":
		_fail("generated: picking a node did not start the round (state %s)" % m.state)
		_drop(m)
		return
	if m.riders_can_escape():
		_fail("generated: riders can get away")
	if m.hits_needed() != m.PER_ROUND:
		_fail("generated: %d hits needed, not %d" % [m.hits_needed(), m.PER_ROUND])
	if m.round_lives_lost != 0:
		_fail("generated: a new round starts with %d lives lost" % m.round_lives_lost)
	if not m.is_perfect_round(m.PER_ROUND):
		_fail("generated: ten of ten with no life lost is not perfect")
	m.round_lives_lost = 1
	if m.is_perfect_round(m.PER_ROUND):
		_fail("generated: a round with a lost life is perfect")
	m.round_lives_lost = 0
	_check_rider(m)
	_check_end(m, 0, true)
	m.start_round()
	_check_end(m, 1, false)
	_drop(m)


# a rider that cannot get away has no time limit and its speed stops growing with its age
func _check_rider(m) -> void:
	var r = m.rider_sys.spawn_rider(0, 1)
	if r["limit"] < 100000.0:
		_fail("generated: a rider has a time limit of %.1f s" % r["limit"])
	r["age"] = 1000.0
	r["base"] = 5.0
	r["tgt"] = 5.0
	r["chg"] = 1000.0
	r["spd"] = 5.0
	var state_before = m.state
	m.state = "check"  # nobody gets run over, and a finished rider does not end the round
	for i in range(120):
		m.rider_sys.update_rider(r, 1.0 / 60.0)
	m.state = state_before
	var cap = 5.0 * (1.0 + 6.0 * 0.08)
	if r["spd"] > cap + 0.05:
		_fail("generated: a rider aged 1000 s rides at %.2f, over the cap %.2f" % [r["spd"], cap])
	if r["mode"] != "fly":
		_fail("generated: an old rider is in mode %s, it should never give up" % r["mode"])
	m.clear_riders()


# every rider spawned and hit, nobody on the road: the round ends in "clear", with the bonus only without a lost life
func _check_end(m, lives_lost: int, want_perfect: bool) -> void:
	var tag = "generated, %d lives lost" % lives_lost
	m.clear_riders()
	m.clear_bosses()
	for i in range(m.PER_ROUND):
		m.hits[i] = true
	m.next_idx = m.PER_ROUND
	m.round_lives_lost = lives_lost
	m.state = "play"
	var score_before = m.score
	m.after_wave()
	if m.state != "clear":
		_fail("%s: all ten hit but the round ended in state %s" % [tag, m.state])
		return
	var gained = m.score - score_before
	if want_perfect and gained != PERFECT_BONUS:
		_fail(
			"%s: expected the %d perfect bonus, score went up by %d" % [tag, PERFECT_BONUS, gained]
		)
	if not want_perfect and gained != 0:
		_fail("%s: no bonus expected, score went up by %d" % [tag, gained])
