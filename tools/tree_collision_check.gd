extends SceneTree
# Checks that the trees of a generated arena are solid (the trunks are: the leaves are above head height). Before,
# the world stood trees on the grass (world_dress.gd) but the arena did not know about them, so the player, the
# riders and the bosses walked straight through the trunks. Run from the project folder:
#   godot --headless --path . --script res://tools/tree_collision_check.gd
# or: python tools/run_checks.py tree_collision
# Optional argument after "--": how many generated arenas with trees to try (default 6).
# On each arena, for trees spread over the arena, it checks that
#   - obstacle_at and rider_blocked are true up to 0.55 m from a trunk's middle (a boss's margin and the trunk) and false from there
#   - a body put inside a trunk is brought out to its own distance (player 0.70 m, boss 0.55 m, pickup 1.25 m), not further
#   - the ground next to a tree is free as before (the neighbouring cells' middles are unchanged by clamp_walk)
#   - a player walking at a trunk from every side, dead on and a little off to either side, at run speed, never gets
#     closer than 0.70 m to its middle, stops against it when dead on, and ends on free ground (the same through
#     the game's own player step, main._process)
#   - a boss walking at it keeps 0.55 m off it
#   - the extraction point and the supply caches are never on a trunk
#   - a rider riding at a player on the far side of a trunk goes round it: never closer than 0.53 m at any step
#     (the rescue puts one that gets in back out), and gets to the player
# Exits with status 1 and prints the first problems.

const ArenaGenScript = preload("res://scripts/arena_gen.gd")
const GeneratedArena = preload("res://scripts/arena_generated.gd")
const WorldDress = preload("res://scripts/world_dress.gd")
const MAIN_SCENE = "res://main.tscn"
const DT = 1.0 / 60.0
const FIRST_SEED = 5000
const SEED_TRIES = 400  # generated arenas looked at to find ones with trees
const TREES_PER_ARENA = 8
const PLAYER_KEEP = 0.45 + WorldDress.TRUNK_SOLID  # the closest the player's middle may come to a trunk's middle
const BOSS_KEEP = 0.3 + WorldDress.TRUNK_SOLID
const PICKUP_KEEP = 1.0 + WorldDress.TRUNK_SOLID
const SLACK = 0.01  # metres of float and halving slack
const RUN = 5.8  # metres per second
const APPROACH = 3.0  # metres from the trunk a walk starts
const OFFSETS = [0.0, 0.2, -0.2, 0.4, -0.4]  # metres off the line to the trunk's middle
const RIDER_FROM = 9.0  # metres either side of the trunk the rider and the player stand
const RIDER_SECONDS = 10.0
const RIDER_KEEP = 0.3 + WorldDress.TRUNK_SOLID - 0.02
const RIDER_TRIES = 2  # rider set-ups per arena

var problems = []
var main = null
var tested = {"trees": 0, "walks": 0, "boss": 0, "game": 0, "riders": 0}


func _initialize() -> void:
	var count = 6
	var args = OS.get_cmdline_user_args()
	if args.size() > 0:
		count = int(args[0])
	var rules = ArenaGenScript.load_rules()
	main = load(MAIN_SCENE).instantiate()
	root.add_child(main)
	for i in range(3):
		await process_frame
	seed(5)
	main.start_game(false, 0x1234ABCD)
	main.equip_primary("dart_gun")
	if main.state == "map":
		main.pick_node(0)
	main.force_captured = true  # headless Godot cannot capture the mouse, so the test hook plays the round
	await process_frame
	var arenas = 0
	var tries = 0
	while arenas < count and tries < SEED_TRIES:
		var layout = ArenaGenScript.generate(FIRST_SEED + tries, rules)
		tries += 1
		if layout.is_empty():
			continue
		var arena = GeneratedArena.new(layout, rules)
		var trees: Array = WorldDress.props_of(layout)["trees"]
		if trees.is_empty():
			continue
		arenas += 1
		_check_arena(
			arena, trees, "arena %d (%s)" % [FIRST_SEED + tries - 1, layout.get("style", "")]
		)
	if arenas == 0:
		_fail("no generated arena with trees was found in %d seeds" % SEED_TRIES)
	for key in tested:
		if arenas > 0 and tested[key] == 0:
			_fail("the check never tested %s (it is not covering what it says)" % key)
	if problems.is_empty():
		print(
			(
				"tree_collision_check: %d arenas, %d trees solid for the player (%d walks, %d through the game's step), the bosses (%d), the pickups, the spots and %d riders"
				% [
					arenas,
					tested["trees"],
					tested["walks"],
					tested["game"],
					tested["boss"],
					tested["riders"]
				]
			)
		)
		quit(0)
	else:
		print("tree_collision_check: %d problem(s)" % problems.size())
		for p in problems.slice(0, 12):
			print("  " + p)
		quit(1)


func _fail(text: String) -> void:
	problems.append(text)


func _flat(p: Vector3, tree: Vector2) -> float:
	return Vector2(p.x - tree.x, p.z - tree.y).length()


# trees spread over the whole list, at most TREES_PER_ARENA
func _sample(trees: Array) -> Array:
	var out = []
	var take = mini(TREES_PER_ARENA, trees.size())
	for i in range(take):
		out.append(trees[int(float(i) * float(trees.size()) / float(take))])
	return out


func _check_arena(arena, trees: Array, tag: String) -> void:
	var cell = float(arena.layout["cell"])
	var rng = RandomNumberGenerator.new()
	rng.seed = 91
	var picked = _sample(trees)
	for tree in picked:
		var at2: Vector2 = tree["pos"]
		var at = Vector3(at2.x, 0.0, at2.y)
		var label = "%s tree at %s" % [tag, at2]
		tested["trees"] += 1
		# blocked up to a boss's reach of the trunk (BOSS_KEEP, where the looks that steer a boss or a rider can see it:
		# a trunk is only half a metre across), and free from there on
		for who in ["obstacle_at", "rider_blocked"]:
			if not arena.call(who, at):
				_fail("%s: %s is false at the trunk's middle" % [label, who])
			for beside in [
				Vector3(BOSS_KEEP - 0.05, 0.0, 0.0), Vector3(0.0, 0.0, -(BOSS_KEEP - 0.05))
			]:
				if not arena.call(who, at + beside):
					_fail("%s: %s is false %.2f m from the trunk" % [label, who, beside.length()])
			for beside in [
				Vector3(BOSS_KEEP + 0.05, 0.0, 0.0), Vector3(0.0, 0.0, -(BOSS_KEEP + 0.05))
			]:
				if arena.call(who, at + beside):
					_fail("%s: %s is true %.2f m from the trunk" % [label, who, beside.length()])
		# a body inside the trunk is brought out to its own distance
		for who in [["player", PLAYER_KEEP], ["boss", BOSS_KEEP], ["pickup", PICKUP_KEEP]]:
			var out: Vector3 = arena.clamp_walk(at, who[0])
			var d = _flat(out, at2)
			if d < float(who[1]) - SLACK or d > float(who[1]) + 1.5:
				_fail(
					(
						"%s: clamp_walk put a %s at %.2f m from the trunk, expected about %.2f m"
						% [label, who[0], d, who[1]]
					)
				)
			if arena.clamp_walk(out, who[0]).distance_to(out) > 0.001:
				_fail("%s: the %s's free spot %s is not free" % [label, who[0], out])
		# the ground round it is as free as before
		for step in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var next = Vector3(at.x + float(step.x) * cell, 0.0, at.z + float(step.y) * cell)
			var neighbour = Vector2i(tree["cell"].x + step.x, tree["cell"].y + step.y)
			var has_tree = false
			for other in trees:
				if other["cell"] == neighbour:
					has_tree = true
			if not has_tree and arena.clamp_walk(next, "player").distance_to(next) > 0.001:
				_fail("%s: the cell %s beside the tree is not free" % [label, step])
		_walk_at_tree(arena, tree, label)
	_check_spots(arena, trees, tag, rng)
	_check_riders(arena, picked, tag)


# the unit steps the walks come from
const FROM_DIRS = [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]


# true if a walk of `length` metres from `from` along `dir` (every quarter metre) is on free ground for `who`
func _line_free(arena, from: Vector3, dir: Vector3, length: float, who: String) -> bool:
	var d = 0.0
	while d <= length:
		var q = from + dir * d
		if arena.clamp_walk(q, who).distance_to(q) > 0.001:
			return false
		d += 0.25
	return true


func _walk_at_tree(arena, tree: Dictionary, label: String) -> void:
	var at2: Vector2 = tree["pos"]
	var at = Vector3(at2.x, 0.0, at2.y)
	for dir2 in FROM_DIRS:
		var dir = Vector3(dir2.x, 0.0, dir2.y)  # the way the body walks, towards the trunk
		var side = Vector3(-dir.z, 0.0, dir.x)
		for off in OFFSETS:
			var start = at - dir * APPROACH + side * float(off)
			# only where the way up to the trunk's margin is open ground (no building or other tree in the way)
			if not _line_free(arena, start, dir, APPROACH - PLAYER_KEEP - 0.3, "player"):
				continue
			var tag = "%s, walking %s %.1f m off the line" % [label, dir, off]
			# the player at run speed, a step at a time as the game takes it
			var p = start
			var closest = INF
			for i in range(int((APPROACH + 2.5) / (RUN * DT))):
				p = arena.slide_walk(p, p + dir * RUN * DT)
				closest = minf(closest, _flat(p, at2))
			tested["walks"] += 1
			if closest < PLAYER_KEEP - SLACK:
				_fail(
					(
						"%s: the player got to %.2f m from the trunk's middle (keeps %.2f m)"
						% [tag, closest, PLAYER_KEEP]
					)
				)
			if arena.clamp_walk(p, "player").distance_to(p) > 0.001:
				_fail("%s: the player ended at %s, not on free ground" % [tag, p])
			if absf(off) < 0.01 and _flat(p, at2) > PLAYER_KEEP + 0.05:
				_fail(
					(
						"%s: walking dead at the trunk stopped %.2f m from it, not against it"
						% [tag, _flat(p, at2)]
					)
				)
			# a boss at its charge speed
			var b = start
			var b_closest = INF
			if not _line_free(arena, start, dir, APPROACH - BOSS_KEEP - 0.3, "boss"):
				continue
			for i in range(int((APPROACH + 2.5) / (15.0 * DT))):
				b = arena.slide_walk(b, b + dir * 15.0 * DT, "boss")
				b_closest = minf(b_closest, _flat(b, at2))
			tested["boss"] += 1
			if b_closest < BOSS_KEEP - SLACK:
				_fail(
					(
						"%s: a boss got to %.2f m from the trunk's middle (keeps %.2f m)"
						% [tag, b_closest, BOSS_KEEP]
					)
				)
	# once through the game's own player step: the player node is put in front of the trunk and `pvel` is set every frame
	var game_dir = Vector3(1.0, 0.0, 0.0)
	var game_start = at - game_dir * APPROACH
	if _line_free(arena, game_start, game_dir, APPROACH - PLAYER_KEEP - 0.3, "player"):
		var old_arena = main.arena
		main.arena = arena
		_ground()
		main.player.position = game_start
		var game_closest = INF
		for i in range(90):
			main.pvel = game_dir * RUN
			main.invuln = 1000.0
			main._process(DT)
			game_closest = minf(game_closest, _flat(main.player.position, at2))
		main.arena = old_arena
		_ground()
		tested["game"] += 1
		if game_closest < PLAYER_KEEP - SLACK:
			_fail(
				(
					"%s: in the game the player got to %.2f m from the trunk's middle (keeps %.2f m)"
					% [label, game_closest, PLAYER_KEEP]
				)
			)


# the extraction point and the caches never stand on a trunk
func _check_spots(arena, trees: Array, tag: String, rng: RandomNumberGenerator) -> void:
	for round_no in range(4):
		rng.seed = 40 + round_no
		var goal: Vector3 = arena.goal_spot(rng)
		var spots: Array = [goal]
		spots.append_array(arena.cache_spots(3, goal, rng))
		for s in spots:
			for tree in trees:
				if _flat(s, tree["pos"]) < PICKUP_KEEP:
					_fail(
						"%s: a spot at %s is %.2f m from a trunk" % [tag, s, _flat(s, tree["pos"])]
					)


# a rider on one side of a trunk, the player on the other: the rider goes round the trunk and reaches the player
func _check_riders(arena, picked: Array, tag: String) -> void:
	var old_arena = main.arena
	main.arena = arena
	main.clear_riders()
	var done = 0
	for tree in picked:
		if done >= RIDER_TRIES:
			break
		var at2: Vector2 = tree["pos"]
		var at = Vector3(at2.x, 0.0, at2.y)
		for dir2 in FROM_DIRS:
			var dir = Vector3(dir2.x, 0.0, dir2.y)
			var rider_spot = at - dir * RIDER_FROM
			var player_spot = at + dir * RIDER_FROM
			# open ground over the whole way, bar the tree itself: both ends and the two stretches before the trunk's margin
			if not (
				_line_free(arena, rider_spot, dir, RIDER_FROM - 1.5, "boss")
				and _line_free(arena, at + dir * 1.5, dir, RIDER_FROM - 1.5, "boss")
			):
				continue
			var r = main.rider_sys.spawn_rider(0, 1)
			r["can_throw"] = false
			r["limit"] = 100000.0
			r["pos"] = rider_spot
			r["yaw"] = main.rider_sys.yaw_of(dir)
			r["hidden"] = false
			r["entered"] = true
			r["pursuit"] = "chase"
			var closest_tree = INF
			var closest_player = INF
			main.state = "check"  # nobody gets run over mid-check
			for step in range(int(RIDER_SECONDS / DT)):
				main.player.position = player_spot
				main.rider_sys.move_rider(r, DT)
				if r["hidden"]:
					continue
				closest_tree = minf(closest_tree, _flat(r["pos"], at2))
				closest_player = minf(
					closest_player, _flat(r["pos"], Vector2(player_spot.x, player_spot.z))
				)
			tested["riders"] += 1
			done += 1
			var label = "%s, a rider riding %s at a tree" % [tag, dir]
			if closest_tree < RIDER_KEEP:
				_fail(
					(
						"%s: it got to %.2f m from the trunk's middle (keeps %.2f m)"
						% [label, closest_tree, RIDER_KEEP + 0.02]
					)
				)
			if closest_player > 3.0:
				_fail(
					(
						"%s: it never got round to the player (closest %.1f m of %.0f m)"
						% [label, closest_player, 2.0 * RIDER_FROM]
					)
				)
			main.clear_riders()
			break
	main.arena = old_arena


# put the player in a known place: on the ground, no slide or dash, at the arena's start
func _ground() -> void:
	main.player_sys.reset_air()
	main.pvel = Vector3.ZERO
	main.slide_t = 0.0
	main.slide_cd = 0.0
	main.dash_t = 0.0
	main.dash_cd = 0.0
	main.dash_inv = 0.0
	main.crouch_t = 0.0
	main.invuln = 1000.0
	main.state = "play"
	main.player.position = main.arena.start_position()
	main._process(DT)
