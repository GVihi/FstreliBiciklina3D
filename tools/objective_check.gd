extends SceneTree
# Checks the exploration objectives and the rim outline. Run from the project folder:
#   godot --headless --path . --script res://tools/objective_check.gd
#
# Spots (scripts/arena_generated.gd): on 150 generated arenas the extraction point and the supply caches repeat for
# the same seed, stand on ground that can be walked to with room round it, and are spread out (the extraction point
# is far from the start, the caches far from the start, the extraction point and each other).
# Round (scripts/objective.gd): a generated round has caches and a locked extraction point, a cache pays once, taking
# them all pays the bonus, the roundabout has none of it.
# Rim (scripts/rim.gd): riders and bosses get the red rim, pedestrians and cheerleaders the green one, the hit flash
# gives the rim back when it ends and the setting takes it away and back.
# Exits with status 1 and prints the problems.

const ArenaGenScript = preload("res://scripts/arena_gen.gd")
const GeneratedArena = preload("res://scripts/arena_generated.gd")
const Rim = preload("res://scripts/rim.gd")
const Models = preload("res://scripts/models.gd")

const SEEDS = 150
const GOAL_MIN_SHARE = 0.55  # the extraction point is at least this share of the way to the farthest reachable cell
const SEED = 0x2468ACE0

var problems = []


func _initialize() -> void:
	_spots()
	await _round()
	_rim_models()
	await _rim_in_game()
	if problems.is_empty():
		print(
			(
				"objective_check: spots on %d arenas, a round with caches and an extraction point, and the rim outline hold"
				% SEEDS
			)
		)
		quit(0)
	else:
		print("objective_check: %d problem(s)" % problems.size())
		for p in problems:
			print("  " + p)
		quit(1)


func _fail(text: String) -> void:
	if problems.size() < 40:
		problems.append(text)


func _rng(seed_value: int) -> RandomNumberGenerator:
	var r = RandomNumberGenerator.new()
	r.seed = seed_value
	return r


# ------------------------------------------------------------------ spots
func _spots() -> void:
	var rules = ArenaGenScript.load_rules()
	var short_caches = 0
	for k in range(SEEDS):
		var run_seed = 0x51000000 + k * 7919
		var layout = ArenaGenScript.generate(run_seed, rules)
		var a = GeneratedArena.new(layout, rules)
		var tag = "seed %08X" % run_seed
		var goal = a.goal_spot(_rng(run_seed))
		var again = a.goal_spot(_rng(run_seed))
		if goal != again:
			_fail("%s: the extraction point is not repeatable" % tag)
		var n = int(layout["cells"])
		var cell = float(layout["cell"])
		var dist = a.walk_distances()
		var gi = _cell_index(a, goal)
		if gi < 0 or dist[gi] < 0:
			_fail("%s: the extraction point cannot be walked to" % tag)
			continue
		if ArenaGenScript.nav_clearance(layout, gi % n, gi / n) < GeneratedArena.GOAL_CLEAR:
			_fail("%s: the extraction point has no room round it" % tag)
		var far = 0
		for d in dist:
			far = maxi(far, d)
		if float(dist[gi]) < float(far) * GOAL_MIN_SHARE:
			_fail("%s: the extraction point is only %d of %d steps away" % [tag, dist[gi], far])
		var caches = a.cache_spots(4, goal, _rng(run_seed + 1))
		if caches != a.cache_spots(4, goal, _rng(run_seed + 1)):
			_fail("%s: the caches are not repeatable" % tag)
		if caches.size() < 4:
			short_caches += 1
		var seen = [a.start_position(), goal]
		for c in caches:
			var ci = _cell_index(a, c)
			if ci < 0 or dist[ci] < 0:
				_fail("%s: a cache cannot be walked to" % tag)
				continue
			if float(dist[ci]) * cell < GeneratedArena.CACHE_MIN_WALK:
				_fail(
					(
						"%s: a cache is only %.0f m of walking from the start"
						% [tag, float(dist[ci]) * cell]
					)
				)
			if ArenaGenScript.nav_clearance(layout, ci % n, ci / n) < GeneratedArena.CACHE_CLEAR:
				_fail("%s: a cache has no room round it" % tag)
			for o in seen:
				if Vector2(c.x - o.x, c.z - o.z).length() < GeneratedArena.CACHE_APART - 0.01:
					_fail(
						(
							"%s: a cache is under %d m from another spot"
							% [tag, GeneratedArena.CACHE_APART]
						)
					)
			seen.append(c)
	if short_caches > SEEDS / 20:
		_fail("%d of %d arenas have fewer than 4 cache spots" % [short_caches, SEEDS])


func _cell_index(a, p: Vector3) -> int:
	var n = int(a.layout["cells"])
	var cell = float(a.layout["cell"])
	var cx = int(floor(p.x / cell + float(n) / 2.0))
	var cz = int(floor(p.z / cell + float(n) / 2.0))
	if cx < 0 or cz < 0 or cx >= n or cz >= n:
		return -1
	return cz * n + cx


# ------------------------------------------------------------------ the round
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


func _round() -> void:
	var m = await _make_main(false)
	if (
		m.objective_sys.enabled()
		or m.objective_sys.has_goal()
		or not m.objective_sys.caches.is_empty()
	):
		_fail("roundabout: has objectives")
	_drop(m)

	m = await _make_main(true)
	m.start_game(false, SEED)
	for i in range(3):
		await process_frame
	if m.state != "map":
		_fail("a new run did not open the map (state %s)" % m.state)
	else:
		m.pick_node(0)
	var o = m.objective_sys
	if m.state != "play":
		_fail("picking a node did not start the round (state %s)" % m.state)
		_drop(m)
		return
	if not o.enabled() or not o.has_goal():
		_fail("generated round: no extraction point")
		_drop(m)
		return
	if o.extracting:
		_fail("generated round: the extraction point is open before any rider is down")
	if o.caches.size() < 3:
		_fail("generated round: only %d caches" % o.caches.size())
	var first_goal: Vector3 = o.goal["pos"]
	# a cache pays once
	var cash0 = m.cash
	var score0 = m.score
	m.player.position = o.caches[0]["pos"]
	o.update(0.05)
	if o.taken != 1 or m.score <= score0 or m.cash <= cash0:
		_fail(
			(
				"a cache paid nothing (taken %d, score %d to %d, cash %d to %d)"
				% [o.taken, score0, m.score, cash0, m.cash]
			)
		)
	var score1 = m.score
	o.update(0.05)
	if m.score != score1 or o.taken != 1:
		_fail("a cache paid twice")
	# the rest pay the bonus
	for i in range(1, o.caches.size()):
		m.player.position = o.caches[i]["pos"]
		o.update(0.05)
	if o.taken != o.caches.size():
		_fail("not every cache could be taken (%d of %d)" % [o.taken, o.caches.size()])
	if m.score - score1 < o.ALL_CACHES_SCORE:
		_fail("taking every cache did not pay the %d bonus" % o.ALL_CACHES_SCORE)
	# walking onto the locked extraction point does nothing
	m.player.position = first_goal
	o.update(0.05)
	if m.state != "play":
		_fail("the locked extraction point ended the round (state %s)" % m.state)
	# the next round gets a fresh set, the old nodes are gone
	var old_nodes = []
	for c in o.caches:
		old_nodes.append(c["node"])
	m.clear_pickups()
	if o.has_goal() or not o.caches.is_empty():
		_fail("clear_pickups left objectives behind")
	_drop(m)


# ------------------------------------------------------------------ the rim
func _rim_models() -> void:
	var kit = Models.kit_of(1)
	var pro = Models.build_rider("pro", kit)
	Rim.apply(pro["root"], Rim.FOE)
	if Rim.count(pro["root"]) < 5:
		_fail("a rider got a rim on only %d meshes" % Rim.count(pro["root"]))
	var pal = {
		"shirt": Color.html("#d65a4a"),
		"pants": Color.html("#2d3a52"),
		"hair": Color.html("#2b1d12"),
		"skin": Color.html("#f0c8a0"),
		"bag": Color.html("#c49a5a")
	}
	var civ = Models.build_civ("walker", pal)
	Rim.apply(civ["root"], Rim.FRIEND)
	var cheer = Models.build_cheer(0)
	Rim.apply(cheer["root"], Rim.FRIEND)
	if Rim.count(civ["root"]) < 3 or Rim.count(cheer["root"]) < 3:
		_fail("a pedestrian or cheerleader has too few rim meshes")
	var foe = Rim.material_for(Rim.FOE)
	var friend = Rim.material_for(Rim.FRIEND)
	if (
		foe == friend
		or foe.get_shader_parameter("rim_color") == friend.get_shader_parameter("rim_color")
	):
		_fail("foes and bystanders share a rim colour")
	var c: Color = foe.get_shader_parameter("rim_color")
	var f: Color = friend.get_shader_parameter("rim_color")
	if not (c.r > c.g and c.r > c.b):
		_fail("the foe rim is not red")
	if not (f.g > f.r and f.g > f.b):
		_fail("the bystander rim is not green")
	if _any_overlay(pro["root"], foe) == 0 or _any_overlay(civ["root"], friend) == 0:
		_fail("models have the rim in their meta but not on the overlay")
	Rim.apply(pro["root"], Rim.FOE, false)
	if Rim.count(pro["root"]) != 0 or _any_overlay(pro["root"], foe) != 0:
		_fail("taking the rim off left some behind")
	pro["root"].free()
	civ["root"].free()
	cheer["root"].free()


func _any_overlay(node: Node, mat: Material) -> int:
	var n = 0
	if node is MeshInstance3D and node.material_overlay == mat:
		n += 1
	for ch in node.get_children():
		n += _any_overlay(ch, mat)
	return n


func _rim_in_game() -> void:
	var m = await _make_main(true)
	m.start_game(false, SEED)
	for i in range(3):
		await process_frame
	m.pick_node(0)
	m.rider_sys.spawn_wave()
	for i in range(2):
		await process_frame
	if m.riders.is_empty():
		_fail("no rider was spawned to look at")
		_drop(m)
		return
	var rider_root: Node = m.riders[0]["model"]["root"]
	var foe = Rim.material_for(Rim.FOE)
	var rimmed = Rim.count(rider_root)
	if rimmed == 0 or _any_overlay(rider_root, foe) != rimmed:
		_fail(
			(
				"a spawned rider has no rim (%d meshes, %d on overlay)"
				% [rimmed, _any_overlay(rider_root, foe)]
			)
		)
	# the cheerleaders were built with the green rim
	var green = Rim.material_for(Rim.FRIEND)
	var cheer_rimmed = 0
	for c in m.cheerleaders:
		cheer_rimmed += _any_overlay(c["root"], green)
	if cheer_rimmed == 0:
		_fail("cheerleaders have no rim")
	# the hit flash covers the rim and gives it back
	m.set_flash(rider_root, true)
	if _any_overlay(rider_root, m.flash_mat) == 0 or _any_overlay(rider_root, foe) != 0:
		_fail("the hit flash did not replace the rim")
	m.set_flash(rider_root, false)
	if _any_overlay(rider_root, foe) != rimmed:
		_fail(
			(
				"the rim did not come back after the hit flash (%d of %d)"
				% [_any_overlay(rider_root, foe), rimmed]
			)
		)
	# the setting
	m.set_setting("rim", false)
	if _any_overlay(rider_root, foe) != 0 or m.rim_outline:
		_fail("the RIM GLOW setting did not take the rim off")
	m.set_setting("rim", true)
	if _any_overlay(rider_root, foe) != rimmed:
		_fail("the RIM GLOW setting did not put the rim back")
	# a new rider with the setting off gets none
	m.set_setting("rim", false)
	m.rider_sys.spawn_wave()
	var newest: Node = m.riders[m.riders.size() - 1]["model"]["root"]
	if Rim.count(newest) != 0:
		_fail("a rider spawned with the setting off has a rim")
	m.set_setting("rim", true)
	_drop(m)
