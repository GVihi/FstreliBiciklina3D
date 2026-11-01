extends SceneTree
# Checks that the lamp posts of a generated arena are solid (the poles are for everyone on foot and every rider; the arm and the
# head hang over the road above head height and stop darts and phones, not people). Before, the world stood lamps on the
# sidewalks (world_dress.gd) but the arena did not know about them, so the player, the riders and the bosses walked
# straight through the poles and darts flew through them. It is tools/tree_collision_check.gd for lamps. Run from the
# project folder:
#   godot --headless --path . --script res://tools/lamp_collision_check.gd
# or: python tools/run_checks.py lamp_collision
# Optional argument after "--": how many generated arenas with lamps to try (default 6).
# On each arena, for lamps spread over the arena, it checks that
#   - obstacle_at and rider_blocked are true up to 0.40 m from a pole's middle (a boss's margin and the pole) and false from 0.50 m
#   - a body put inside a pole is brought out to its own distance (player 0.60 m, boss 0.45 m, pickup 1.15 m), not further
#   - the ground next to a lamp (the road in front of it, the sidewalk along it) is free as before, and so is the ground
#     under the head, which hangs over the road
#   - a player walking at a pole from every side, dead on and a little off to either side, at run speed, never gets
#     closer than 0.60 m to its middle, stops against it when dead on, and ends on free ground (the same through
#     the game's own player step, main._process)
#   - a boss walking at it keeps 0.45 m off it
#   - the extraction point and the supply caches are never on a pole
#   - darts and phones are stopped by the pole, the arm and the head (the three boxes the world draws) and fly past anything
#     beside, under or above them: point by point (ray_blocked), along whole rays (tree_hit, which looks at lamps too),
#     along sight lines, as a phone's step, and as a real dart through shoot_dart
#   - a rider riding at a player on the far side of a pole goes round it: never closer than 0.43 m at any step
#     (the rescue puts one that gets in back out), and gets to the player
# Exits with status 1 and prints the first problems.

const ArenaGenScript = preload("res://scripts/arena_gen.gd")
const GeneratedArena = preload("res://scripts/arena_generated.gd")
const WorldDress = preload("res://scripts/world_dress.gd")
const Threats = preload("res://scripts/threats.gd")
const MAIN_SCENE = "res://main.tscn"
const DT = 1.0 / 60.0
const FIRST_SEED = 5000
const SEED_TRIES = 400  # generated arenas looked at to find ones with lamps
const LAMPS_PER_ARENA = 8
const PLAYER_KEEP = 0.45 + WorldDress.LAMP_SOLID  # the closest the player's middle may come to a pole's middle
const BOSS_KEEP = 0.3 + WorldDress.LAMP_SOLID
const PICKUP_KEEP = 1.0 + WorldDress.LAMP_SOLID
const SLACK = 0.01  # metres of float and halving slack
const RUN = 5.8  # metres per second
const APPROACH = 3.0  # metres from the pole a walk starts
const OFFSETS = [0.0, 0.1, -0.1, 0.3, -0.3]  # metres off the line to the pole's middle
const RIDER_FROM = 9.0  # metres either side of the pole the rider and the player stand
const RIDER_SECONDS = 10.0
const RIDER_KEEP = 0.3 + WorldDress.LAMP_SOLID - 0.02
const RIDER_TRIES = 2  # rider set-ups per arena
const HALF = WorldDress.LAMP_POLE_HALF

var problems = []
var main = null
var tested = {
	"lamps": 0, "walks": 0, "boss": 0, "game": 0, "riders": 0, "shots": 0, "darts": 0, "overhead": 0
}


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
		var props: Dictionary = WorldDress.props_of(layout)
		if props["lamps"].is_empty():
			continue
		arenas += 1
		_check_arena(
			arena, props, "arena %d (%s)" % [FIRST_SEED + tries - 1, layout.get("style", "")]
		)
	if arenas == 0:
		_fail("no generated arena with lamps was found in %d seeds" % SEED_TRIES)
	for key in tested:
		if arenas > 0 and tested[key] == 0:
			_fail("the check never tested %s (it is not covering what it says)" % key)
	if problems.is_empty():
		print(
			(
				"lamp_collision_check: %d arenas, %d lamps solid for the player (%d walks, %d through the game's step), the bosses (%d), the pickups, the spots and %d riders; %d lamps stop darts and phones (%d real darts), and the heads over the road stop nobody on foot (%d)"
				% [
					arenas,
					tested["lamps"],
					tested["walks"],
					tested["game"],
					tested["boss"],
					tested["riders"],
					tested["shots"],
					tested["darts"],
					tested["overhead"]
				]
			)
		)
		quit(0)
	else:
		print("lamp_collision_check: %d problem(s)" % problems.size())
		for p in problems.slice(0, 12):
			print("  " + p)
		quit(1)


func _fail(text: String) -> void:
	problems.append(text)


func _flat(p: Vector3, pole: Vector2) -> float:
	return Vector2(p.x - pole.x, p.z - pole.y).length()


# lamps spread over the whole list, at most LAMPS_PER_ARENA
func _sample(lamps: Array) -> Array:
	var out = []
	var take = mini(LAMPS_PER_ARENA, lamps.size())
	for i in range(take):
		out.append(lamps[int(float(i) * float(lamps.size()) / float(take))])
	return out


# the unit step from a lamp's pole towards its road, as a Vector3
func _towards_road(lamp: Dictionary) -> Vector3:
	return Vector3(float(lamp["dir"].x), 0.0, float(lamp["dir"].y))


func _check_arena(arena, props: Dictionary, tag: String) -> void:
	var lamps: Array = props["lamps"]
	var cell = float(arena.layout["cell"])
	var rng = RandomNumberGenerator.new()
	rng.seed = 91
	var picked = _sample(lamps)
	for lamp in picked:
		var pole2: Vector2 = lamp["pole"]
		var at = Vector3(pole2.x, 0.0, pole2.y)
		var label = "%s lamp at %s" % [tag, pole2]
		tested["lamps"] += 1
		# blocked up to a boss's reach of the pole (BOSS_KEEP, where the looks that steer a boss or a rider can see it:
		# a pole is only 12 cm across), and free from there on
		for who in ["obstacle_at", "rider_blocked"]:
			if not arena.call(who, at):
				_fail("%s: %s is false at the pole's middle" % [label, who])
			for beside in [
				Vector3(BOSS_KEEP - 0.05, 0.0, 0.0), Vector3(0.0, 0.0, -(BOSS_KEEP - 0.05))
			]:
				if not arena.call(who, at + beside):
					_fail("%s: %s is false %.2f m from the pole" % [label, who, beside.length()])
			for beside in [
				Vector3(BOSS_KEEP + 0.05, 0.0, 0.0), Vector3(0.0, 0.0, -(BOSS_KEEP + 0.05))
			]:
				if arena.call(who, at + beside):
					_fail("%s: %s is true %.2f m from the pole" % [label, who, beside.length()])
		# a body inside the pole is brought out to its own distance
		for who in [["player", PLAYER_KEEP], ["boss", BOSS_KEEP], ["pickup", PICKUP_KEEP]]:
			var out: Vector3 = arena.clamp_walk(at, who[0])
			var d = _flat(out, pole2)
			if d < float(who[1]) - SLACK or d > float(who[1]) + 1.5:
				_fail(
					(
						"%s: clamp_walk put a %s at %.2f m from the pole, expected about %.2f m"
						% [label, who[0], d, who[1]]
					)
				)
			if arena.clamp_walk(out, who[0]).distance_to(out) > 0.001:
				_fail("%s: the %s's free spot %s is not free" % [label, who[0], out])
		# the ground round it is as free as before: the cell in front of it (the road) and the two along the road
		var to_road = _towards_road(lamp)
		var along = Vector3(-to_road.z, 0.0, to_road.x)
		var centre = Vector3(
			float(lamp["cell"].x) * cell - float(arena.layout["cells"]) * cell * 0.5 + cell * 0.5,
			0.0,
			float(lamp["cell"].y) * cell - float(arena.layout["cells"]) * cell * 0.5 + cell * 0.5
		)
		for step in [to_road, along, -along]:
			var next: Vector3 = centre + step * cell
			if _cell_is_plain_ground(arena, props, next, lamp["cell"]):
				if arena.clamp_walk(next, "player").distance_to(next) > 0.001:
					_fail("%s: the cell %s beside the lamp is not free" % [label, step])
		# the head and the arm hang over the road above head height: the ground under them is free
		var under_head = at + to_road * WorldDress.LAMP_ARM_REACH
		if _cell_is_plain_ground(arena, props, under_head, lamp["cell"]):
			tested["overhead"] += 1
			if arena.obstacle_at(under_head) or arena.rider_blocked(under_head):
				_fail("%s: the ground under the lamp's head is blocked" % label)
			if arena.clamp_walk(under_head, "player").distance_to(under_head) > 0.001:
				_fail("%s: a player cannot stand under the lamp's head" % label)
		_walk_at_lamp(arena, lamp, label)
		_check_shots(arena, lamp, props, label)
	_check_spots(arena, lamps, tag, rng)
	_check_riders(arena, picked, tag)


# true if the ground at p is open (not a building or a tunnel), no tree stands next to it and no lamp but the one in
# cell `own` has its pole within 1.3 m of it
func _cell_is_plain_ground(arena, props: Dictionary, p: Vector3, own: Vector2i) -> bool:
	var s: String = arena.surface_at(p)
	if s == "building" or s == "tunnel":
		return false
	var n = int(arena.layout["cells"])
	var cell = float(arena.layout["cell"])
	var cx = int(floor(p.x / cell + float(n) / 2.0))
	var cz = int(floor(p.z / cell + float(n) / 2.0))
	for tree in props["trees"]:
		if absi(tree["cell"].x - cx) <= 1 and absi(tree["cell"].y - cz) <= 1:
			return false
	for other in props["lamps"]:
		if other["cell"] != own and other["pole"].distance_to(Vector2(p.x, p.z)) < 1.3:
			return false
	return true


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


# true if no dart is stopped by the arena (buildings, trees, lamps) anywhere on the line from `a` to `b`, point by point
func _air_clear(arena, a: Vector3, b: Vector3) -> bool:
	var length = a.distance_to(b)
	var dir = (b - a) / maxf(length, 0.0001)
	var d = 0.0
	while d <= length:
		if arena.ray_blocked(a + dir * d):
			return false
		d += 0.1
	return arena.tree_hit(a, dir, length) < 0.0


func _walk_at_lamp(arena, lamp: Dictionary, label: String) -> void:
	var at2: Vector2 = lamp["pole"]
	var at = Vector3(at2.x, 0.0, at2.y)
	for dir2 in FROM_DIRS:
		var dir = Vector3(dir2.x, 0.0, dir2.y)  # the way the body walks, towards the pole
		var side = Vector3(-dir.z, 0.0, dir.x)
		for off in OFFSETS:
			var start = at - dir * APPROACH + side * float(off)
			# only where the way up to the pole's margin is open ground (no building or other prop in the way)
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
						"%s: the player got to %.2f m from the pole's middle (keeps %.2f m)"
						% [tag, closest, PLAYER_KEEP]
					)
				)
			if arena.clamp_walk(p, "player").distance_to(p) > 0.001:
				_fail("%s: the player ended at %s, not on free ground" % [tag, p])
			if absf(off) < 0.01 and _flat(p, at2) > PLAYER_KEEP + 0.05:
				_fail(
					(
						"%s: walking dead at the pole stopped %.2f m from it, not against it"
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
						"%s: a boss got to %.2f m from the pole's middle (keeps %.2f m)"
						% [tag, b_closest, BOSS_KEEP]
					)
				)
	# once through the game's own player step: the player node is put in front of the pole and `pvel` is set every frame
	var game_dir = Vector3(1.0, 0.0, 0.0)
	for candidate in FROM_DIRS:
		var cd = Vector3(candidate.x, 0.0, candidate.y)
		if _line_free(arena, at - cd * APPROACH, cd, APPROACH - PLAYER_KEEP - 0.3, "player"):
			game_dir = cd
			break
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
					"%s: in the game the player got to %.2f m from the pole's middle (keeps %.2f m)"
					% [label, game_closest, PLAYER_KEEP]
				)
			)


# darts and phones against the three boxes of a lamp: the pole (to 5.2 m), the arm (5.1 to 5.2 m, from the pole over the
# road) and the head (5.07 to 5.17 m, 0.45 m long along the road and 0.28 m across it)
func _check_shots(arena, lamp: Dictionary, props: Dictionary, label: String) -> void:
	var at2: Vector2 = lamp["pole"]
	var at = Vector3(at2.x, 0.0, at2.y)
	var to_road = _towards_road(lamp)  # across the road's edge, from the pole towards the road
	var along = Vector3(-to_road.z, 0.0, to_road.x)  # along the road
	var reach = WorldDress.LAMP_ARM_REACH
	var head = at + to_road * reach
	var arm = at + to_road * (reach * 0.5)
	var up = func(v: Vector3, y: float) -> Vector3: return Vector3(v.x, y, v.z)
	var probes = [
		[up.call(at, 1.0), true, "the pole"],
		[up.call(at + Vector3(HALF - 0.005, 0.0, -(HALF - 0.005)), 1.0), true, "the pole's corner"],
		[up.call(at + Vector3(HALF + 0.04, 0.0, 0.0), 1.0), false, "beside the pole"],
		[up.call(at, 5.15), true, "the top of the pole"],
		[up.call(at, 5.4), false, "above the pole"],
		[up.call(arm, 5.15), true, "the arm"],
		[up.call(arm, 5.0), false, "under the arm"],
		[up.call(arm, 5.35), false, "above the arm"],
		[up.call(arm + along * (WorldDress.LAMP_ARM_HALF + 0.05), 5.15), false, "beside the arm"],
		[up.call(head, 5.12), true, "the head"],
		[
			up.call(head + along * (WorldDress.LAMP_HEAD_ALONG * 0.5 - 0.03), 5.12),
			true,
			"the head's end along the road"
		],
		[
			up.call(head + along * (WorldDress.LAMP_HEAD_ALONG * 0.5 + 0.05), 5.12),
			false,
			"beyond the head's end"
		],
		[
			up.call(head + to_road * (WorldDress.LAMP_HEAD_ACROSS * 0.5 - 0.03), 5.12),
			true,
			"the head's far side"
		],
		[
			up.call(head + to_road * (WorldDress.LAMP_HEAD_ACROSS * 0.5 + 0.05), 5.12),
			false,
			"beyond the head's far side"
		],
		[up.call(head, 5.0), false, "under the head"],
		[up.call(head, 5.35), false, "above the head"],
	]
	for probe in probes:
		if arena.ray_blocked(probe[0]) != probe[1]:
			_fail("%s: ray_blocked is %s at %s" % [label, not probe[1], probe[2]])
	# whole rays need a lamp with no other lamp or tree within 8 m (the rays are 10 m long)
	for other in props["lamps"]:
		var o: Vector2 = other["pole"]
		if o != at2 and o.distance_to(at2) < 8.0:
			return
	for tree in props["trees"]:
		var t: Vector2 = tree["pos"]
		if t.distance_to(at2) < 8.0:
			return
	tested["shots"] += 1
	var from = at - along * 5.0
	# [height, metres towards the road, where along the ray it should hit (-1 = a miss)]
	var rays = [
		[1.0, 0.0, 5.0 - HALF],
		[1.0, HALF - 0.005, 5.0 - HALF],
		[1.0, HALF + 0.04, -1.0],
		[5.15, 0.0, 5.0 - HALF],
		[5.4, 0.0, -1.0],
		[5.15, reach * 0.5, 5.0 - WorldDress.LAMP_ARM_HALF],
		[5.0, reach * 0.5, -1.0],
		[5.12, reach, 5.0 - WorldDress.LAMP_HEAD_ALONG * 0.5],
		[5.12, reach + WorldDress.LAMP_HEAD_ACROSS * 0.5 + 0.05, -1.0],
		[5.0, reach, -1.0],
		[5.35, reach, -1.0],
	]
	for ray in rays:
		var org = Vector3(from.x, float(ray[0]), from.z) + to_road * float(ray[1])
		var hit: float = arena.tree_hit(org, along, 10.0)
		if (
			(hit < 0.0) != (float(ray[2]) < 0.0)
			or (hit >= 0.0 and absf(hit - float(ray[2])) > 0.02)
		):
			_fail(
				(
					"%s: a ray at %.2f m high, %.2f m towards the road, hit at %.2f m, expected %.2f m"
					% [label, ray[0], ray[1], hit, ray[2]]
				)
			)
	var slanted = (
		(at + Vector3(0.0, 1.0, 0.0) - (at - along * 3.0 + Vector3(0.0, 0.5, 0.0))).normalized()
	)
	if arena.tree_hit(at - along * 3.0 + Vector3(0.0, 0.5, 0.0), slanted, 10.0) < 0.0:
		_fail("%s: a slanting ray at the pole's middle missed it" % label)
	if arena.tree_hit(from + Vector3(0.0, 1.0, 0.0), along, 3.0) >= 0.0:
		_fail("%s: a ray that stops 2 m short of the pole hit it" % label)
	# a line of sight across the pole is not clear (and one beside it is, where nothing else is in the way)
	var a = from + Vector3(0.0, 1.0, 0.0)
	var b = at + along * 5.0 + Vector3(0.0, 1.0, 0.0)
	if Threats.sight_clear(arena, a, b):
		_fail("%s: the line of sight across the pole is clear" % label)
	var aside = to_road * 0.3
	if (
		_air_clear(arena, a + aside, b + aside)
		and not Threats.sight_clear(arena, a + aside, b + aside)
	):
		_fail("%s: a line of sight 0.3 m beside the pole is not clear" % label)
	var old_arena = main.arena
	main.arena = arena
	# a phone's step across the pole, across the arm and across the head is blocked; one beside them is not
	for step in [[1.0, 0.0, 0.2], [5.15, reach * 0.5, 0.2], [5.12, reach, 0.4]]:
		var mid = Vector3(at.x, float(step[0]), at.z) + to_road * float(step[1])
		var prev = mid - along * float(step[2])
		var next = mid + along * float(step[2])
		if not main.phone_sys.flight_blocked(prev, next):
			_fail(
				(
					"%s: a phone's step across the lamp at %.2f m high is not blocked"
					% [label, step[0]]
				)
			)
	# and a real dart: aimed at the pole it stops at it, aimed 0.3 m to the side it flies on
	var old_spread = main.spread_deg
	main.spread_deg = 0.0
	for off in [0.0, 0.3]:
		var eye = from + Vector3(0.0, 1.0, 0.0) + to_road * float(off)
		var line_to = at + Vector3(0.0, 1.0, 0.0) + to_road * float(off)
		var line_end = line_to + along * 5.0
		var open_line = _air_clear(arena, eye, line_to - along * 0.3)
		if off == 0.0:
			open_line = open_line and _air_clear(arena, line_to + along * 0.3, line_end)
		else:
			open_line = _air_clear(arena, eye, line_end)
		if not open_line:
			continue
		tested["darts"] += 1
		main.cam.global_position = eye
		main.cam.look_at(eye + along, Vector3.UP)
		main.combat_sys.shoot_dart(1, false)
		if main.darts.is_empty():
			_fail("%s: shoot_dart sent no dart" % label)
			continue
		var end: Vector3 = main.darts.back()["b"]
		var past = (end - at).dot(along)  # metres past the pole's middle along the road
		if off == 0.0 and absf(past - -HALF) > 0.05:
			_fail(
				(
					"%s: a dart at the pole ended %.2f m along, not at its face %.2f"
					% [label, past, -HALF]
				)
			)
		if off != 0.0 and past < 0.5:
			_fail("%s: a dart 0.3 m beside the pole was stopped %.2f m along" % [label, past])
		if main.darts.size() > 70:
			main.darts.clear()
	main.spread_deg = old_spread
	main.arena = old_arena


# the extraction point and the caches never stand on a pole
func _check_spots(arena, lamps: Array, tag: String, rng: RandomNumberGenerator) -> void:
	for round_no in range(4):
		rng.seed = 40 + round_no
		var goal: Vector3 = arena.goal_spot(rng)
		var spots: Array = [goal]
		spots.append_array(arena.cache_spots(3, goal, rng))
		for s in spots:
			for lamp in lamps:
				if _flat(s, lamp["pole"]) < PICKUP_KEEP:
					_fail(
						"%s: a spot at %s is %.2f m from a pole" % [tag, s, _flat(s, lamp["pole"])]
					)


# a rider on one side of a pole, the player on the other: the rider goes round the pole and reaches the player
func _check_riders(arena, picked: Array, tag: String) -> void:
	var old_arena = main.arena
	main.arena = arena
	main.clear_riders()
	var done = 0
	for lamp in picked:
		if done >= RIDER_TRIES:
			break
		var at2: Vector2 = lamp["pole"]
		var at = Vector3(at2.x, 0.0, at2.y)
		for dir2 in FROM_DIRS:
			var dir = Vector3(dir2.x, 0.0, dir2.y)
			var rider_spot = at - dir * RIDER_FROM
			var player_spot = at + dir * RIDER_FROM
			# open ground over the whole way, bar the pole itself: both ends and the two stretches before the pole's margin
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
			var closest_pole = INF
			var closest_player = INF
			main.state = "check"  # nobody gets run over mid-check
			for step in range(int(RIDER_SECONDS / DT)):
				main.player.position = player_spot
				main.rider_sys.move_rider(r, DT)
				if r["hidden"]:
					continue
				closest_pole = minf(closest_pole, _flat(r["pos"], at2))
				closest_player = minf(
					closest_player, _flat(r["pos"], Vector2(player_spot.x, player_spot.z))
				)
			tested["riders"] += 1
			done += 1
			var label = "%s, a rider riding %s at a lamp" % [tag, dir]
			if closest_pole < RIDER_KEEP:
				_fail(
					(
						"%s: it got to %.2f m from the pole's middle (keeps %.2f m)"
						% [label, closest_pole, RIDER_KEEP + 0.02]
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
