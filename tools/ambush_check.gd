extends SceneTree
# Checks the ambush when the extraction point opens (README Milestone K, "Exploration and extraction"). Run from the
# project folder:
#   godot --headless --path . --script res://tools/ambush_check.gd
# or with tools\run_ambush_check.bat on Windows.
#
# Size (scripts/ambush.gd): 2 riders early in a run, more later, at most 4.
# Round: when the last rider of a generated round falls the way out opens and the ambush is lined up but nobody is
# on the road yet; the riders come out one after another after the delay; they are not among the round's riders
# (hits and next_idx stay as they were, no armoured rider, they start at gates far from the player); the last one
# going down does not end the round; reaching the extraction point does, and takes the riders still on the road with
# it. The roundabout has no ambush. The same seed gives the same kinds of riders in the same order.
# Exits with status 1 and prints the problems.

const AmbushScript = preload("res://scripts/ambush.gd")
const SEED = 0x2468ACE0

var problems = []


func _initialize() -> void:
	_sizes()
	await _roundabout()
	await _round()
	await _tough()
	await _same_seed()
	if problems.is_empty():
		print("ambush_check: size, timing, rules and the way out of the ambush hold")
		quit(0)
	else:
		print("ambush_check: %d problem(s)" % problems.size())
		for p in problems:
			print("  " + p)
		quit(1)


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


# a generated round in play, with every rider hit and nobody on the road: the way out opens and the ambush is lined up
func _open_way(m, round_n: int = -1) -> bool:
	m.start_game(false, SEED)
	if m.state == "map":
		m.pick_node(0)
	if m.state != "play":
		_fail("could not start a round (state %s)" % m.state)
		return false
	if round_n > 0:
		m.round_n = round_n
	m.clear_riders()
	m.clear_bosses()
	for i in range(m.PER_ROUND):
		m.hits[i] = true
	m.next_idx = m.PER_ROUND
	m.state = "play"
	m.after_wave()
	if m.state != "play" or not m.objective_sys.extracting:
		_fail("the way out did not open (state %s)" % m.state)
		return false
	return true


func _sizes() -> void:
	var a = AmbushScript.new(null)
	var want = {1: 2, 4: 2, 5: 3, 7: 3, 8: 4, 10: 4, 20: 4}
	for n in want:
		if a.count_for_round(n) != want[n]:
			_fail("round %d: %d ambush riders, expected %d" % [n, a.count_for_round(n), want[n]])
	for n in range(1, 21):
		if a.count_for_round(n) < a.MIN_RIDERS or a.count_for_round(n) > a.MAX_RIDERS:
			_fail(
				(
					"round %d: %d ambush riders is outside %d to %d"
					% [n, a.count_for_round(n), a.MIN_RIDERS, a.MAX_RIDERS]
				)
			)


func _roundabout() -> void:
	var m = await _make_main(false)
	m.ambush_sys.start()
	if m.ambush_sys.pending():
		_fail("roundabout: an ambush was lined up")
	_drop(m)


func _round() -> void:
	var m = await _make_main(true)
	if not await _open_way(m):
		_drop(m)
		return
	var a = m.ambush_sys
	var per_round = m.PER_ROUND
	var want = a.count_for_round(m.round_n)
	if a.left != want or not a.pending():
		_fail("the ambush has %d riders lined up, expected %d" % [a.left, want])
	if not m.riders.is_empty():
		_fail("%d riders are on the road the moment the way opens" % m.riders.size())
	# nobody comes before the delay
	a.update(a.DELAY * 0.5)
	if not m.riders.is_empty():
		_fail("a rider came out before the delay")
	# the first comes after it, with a warning
	var notes_before = m.notes.size()
	a.update(a.DELAY)
	if m.riders.size() != 1:
		_fail("%d riders after the delay, expected the first" % m.riders.size())
	if (
		m.notes.size() <= notes_before
		or not str(m.notes[m.notes.size() - 1]["txt"]).begins_with("AMBUSH")
	):
		_fail("no AMBUSH note when the first rider came out")
	# the rest follow, one per gap
	a.update(a.GAP * 0.5)
	if m.riders.size() != 1:
		_fail("a second rider came out before the gap")
	for i in range(want - 1):
		a.update(a.GAP)
	if m.riders.size() != want or a.left != 0 or a.sent != want:
		_fail(
			(
				"%d riders on the road, %d left, %d sent, expected %d, 0 and %d"
				% [m.riders.size(), a.left, a.sent, want, want]
			)
		)
	a.update(a.GAP * 3.0)
	if m.riders.size() != want:
		_fail("more riders than the ambush's %d came out (%d)" % [want, m.riders.size()])
	# they are not the round's riders
	if m.next_idx != per_round or m.PER_ROUND != per_round or m.hits.size() != per_round:
		_fail(
			(
				"the ambush changed the round's riders (next_idx %d, PER_ROUND %d, hits %d)"
				% [m.next_idx, m.PER_ROUND, m.hits.size()]
			)
		)
	var far_exists = false
	for gate in m.arena.gates():
		if (
			(
				Vector2(gate["pos"].x - m.player.position.x, gate["pos"].z - m.player.position.z)
				. length()
			)
			>= m.rider_sys.AMBUSH_MIN_DIST
		):
			far_exists = true
	for r in m.riders:
		if not r["ambush"] or r["idx"] != -1:
			_fail("an ambush rider is marked ambush %s, idx %d" % [str(r["ambush"]), r["idx"]])
		if r["type"] == "tough":
			_fail("an ambush rider is an armoured one")
		var d = Vector2(r["pos"].x - m.player.position.x, r["pos"].z - m.player.position.z).length()
		if far_exists and d < m.rider_sys.AMBUSH_MIN_DIST - 2.0:
			_fail("an ambush rider started %.1f m from the player, a far gate exists" % d)
	# the last one going down does not end the round
	var snapshot = m.riders.duplicate()
	for r in snapshot:
		m.rider_sys.resolve(r, true)
	if m.state != "play" or not m.objective_sys.extracting:
		_fail(
			(
				"the ambush riders going down ended the round (state %s, extracting %s)"
				% [m.state, str(m.objective_sys.extracting)]
			)
		)
	if m.count_hits() != per_round or m.hits.size() != per_round:
		_fail("an ambush rider changed the hits (%d of %d)" % [m.count_hits(), per_round])
	# reaching the point ends it, and takes riders still on the road with it
	a.start()
	a.update(a.DELAY + 0.1)
	a.update(a.GAP + 0.1)
	if m.riders.size() < 2:
		_fail("could not put riders on the road for the exit test (%d)" % m.riders.size())
	m.player.position = m.objective_sys.goal["pos"] + Vector3(0.5, 0.0, 0.0)
	m.objective_sys.update(0.1)
	if m.state != "clear":
		_fail("stood on the extraction point with the ambush on the road: state %s" % m.state)
	if not m.riders.is_empty() or a.pending() or a.sent != 0:
		_fail(
			(
				"the ambush is still there after the round ended (%d riders, %d left)"
				% [m.riders.size(), a.left]
			)
		)
	_drop(m)


# a later round (where the armoured rider is common) never sends one in the ambush
func _tough() -> void:
	var m = await _make_main(true)
	for k in range(5):
		if not await _open_way(m, 8):
			break
		var a = m.ambush_sys
		a.update(a.DELAY + 0.1)
		for i in range(a.left):
			a.update(a.GAP + 0.1)
		for r in m.riders:
			if r["type"] == "tough":
				_fail("round 8, try %d: an ambush rider is armoured" % k)
		if m.riders.size() != 4:
			_fail("round 8, try %d: %d ambush riders, expected 4" % [k, m.riders.size()])
	_drop(m)


# the kinds of the ambush riders, in order, for a seed
func _kinds() -> Array:
	var m = await _make_main(true)
	var out = []
	if await _open_way(m, 8):
		var a = m.ambush_sys
		a.update(a.DELAY + 0.1)
		for i in range(a.left):
			a.update(a.GAP + 0.1)
		for r in m.riders:
			out.append(r["type"])
	_drop(m)
	return out


func _same_seed() -> void:
	var first = await _kinds()
	var second = await _kinds()
	if first.is_empty() or first != second:
		_fail("the same seed gave different ambush riders: %s then %s" % [str(first), str(second)])
