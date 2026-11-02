extends SceneTree
# Checks that the benches and crates of a generated arena are solid, the way the trees (tools/tree_collision_check.gd)
# and the lamp posts (tools/lamp_collision_check.gd) are. The world stands them about with the modelled assets
# (world_models.gd); before, nothing knew about them, so the player, the riders and the bosses walked straight through
# and darts flew through. A bench or a crate is a box turned about the up axis (a crate may sit on another), so the
# arena measures from a rounded rectangle, not from a point. Run from the project folder:
#   godot --headless --path . --script res://tools/block_collision_check.gd
# or: python tools/run_checks.py block_collision
# Optional argument after "--": how many generated arenas with benches and crates to try (default 6).
# First it checks that WorldModels.BENCH_SIZE and CRATE_SIZE (the boxes made solid) are the size of the real models.
# On each arena, for benches and crates spread over it, it checks that
#   - on a grid of points round each box (0.17 m apart, out to 1.3 m from it, all heights for darts), where the ground is
#     open and no tree or lamp is near, the arena agrees with the boxes from the plan: obstacle_at is true within 0.18 m
#     of a box's footprint (what a boss's steering sees) and rider_blocked within 0.33 m, a player is held 0.48 m from
#     it and a boss 0.33 m (clamp_walk), and
#     ray_blocked is true inside a box and nowhere else (so not above a crate, nor beside or above a bench)
#   - a body put inside a box is brought out to its own distance (player, boss, pickup)
#   - a player walking at a box from every side, dead on and a little off to either side, at run speed, never gets
#     closer than 0.48 m to it and ends on free ground (a bench, whose sides lie on the axes, stops the player dead
#     against it); the same through the game's own player step (main._process); a boss walking at it keeps 0.33 m off
#   - the extraction point and the supply caches are never in a box's cell and are always somewhere a player can stand
#   - darts and phones are stopped by the boxes and fly past anything beside or above them: along whole rays
#     (tree_hit, which looks at benches and crates too, the ray's hit being where an independent box test says),
#     along sight lines, as a phone's step, and as a real dart through shoot_dart
#   - a rider riding at a player on the far side of a box goes round it (never closer than 0.31 m at any step) and gets
#     to the player
# Exits with status 1 and prints the first problems.

const ArenaGenScript = preload("res://scripts/arena_gen.gd")
const GeneratedArena = preload("res://scripts/arena_generated.gd")
const WorldDress = preload("res://scripts/world_dress.gd")
const WorldModels = preload("res://scripts/world_models.gd")
const Threats = preload("res://scripts/threats.gd")
const MAIN_SCENE = "res://main.tscn"
const DT = 1.0 / 60.0
const FIRST_SEED = 5000
const SEED_TRIES = 400  # generated arenas looked at to find ones with benches and crates
const BENCHES_PER_ARENA = 4
const CRATES_PER_ARENA = 4
const SOLID = WorldModels.BLOCK_SOLID
const PLAYER_KEEP = 0.45 + SOLID  # the closest the player's middle may come to a box's footprint
const BOSS_KEEP = 0.3 + SOLID
const BOSS_SEES = GeneratedArena.BLOCK_BOSS_CLEAR  # how far from a box obstacle_at (a boss's steering) calls the ground blocked
const PICKUP_KEEP = 1.0 + SOLID
const RIDER_KEEP = 0.3 + SOLID - 0.02
const SLACK = 0.01  # metres of float and halving slack
const EDGE = 0.012  # metres either side of a boundary where the grid does not judge (the arena rounds there)
const RUN = 5.8  # metres per second
const BOSS_RUN = 15.0
const APPROACH = 3.5  # metres from the box's middle a walk starts
const OFFSETS = [0.0, 0.1, -0.1, 0.3, -0.3]  # metres off the line to the box's middle
const GRID_STEP = 0.17
const GRID_OUT = 1.3  # metres the grid goes out from a box's footprint
const GRID_HEIGHTS = [0.02, 0.4, 0.74, 0.78, 1.0, 1.5, 1.9, 2.1]  # metres: dart heights tried at every grid point
const RIDER_FROM = 9.0  # metres either side of the box the rider and the player stand
const RIDER_SECONDS = 10.0
const RIDER_TRIES = 2  # rider set-ups per arena
const FROM_DIRS = [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]

var problems = []
var main = null
var tested = {
	"benches": 0,
	"crates": 0,
	"stacked": 0,
	"points": 0,
	"walks": 0,
	"boss": 0,
	"game": 0,
	"riders": 0,
	"rays": 0,
	"darts": 0
}


func _initialize() -> void:
	var count = 6
	var args = OS.get_cmdline_user_args()
	if args.size() > 0:
		count = int(args[0])
	_check_models()
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
		var planned: Dictionary = WorldModels.plan_props(layout)
		if planned["benches"].is_empty() or planned["crates"].is_empty():
			continue
		var arena = GeneratedArena.new(layout, rules)
		arenas += 1
		_check_arena(
			arena,
			planned,
			WorldDress.props_of(layout),
			"arena %d (%s)" % [FIRST_SEED + tries - 1, layout.get("style", "")]
		)
	if arenas == 0:
		_fail("no generated arena with benches and crates was found in %d seeds" % SEED_TRIES)
	for key in tested:
		if arenas > 0 and tested[key] == 0:
			_fail("the check never tested %s (it is not covering what it says)" % key)
	if problems.is_empty():
		print(
			(
				"block_collision_check: %d arenas, %d benches and %d crates (%d stacked) agree with the arena at %d grid points; the player (%d walks, %d through the game's step), the bosses (%d) and %d riders keep off them, and %d rays and %d real darts are stopped by them"
				% [
					arenas,
					tested["benches"],
					tested["crates"],
					tested["stacked"],
					tested["points"],
					tested["walks"],
					tested["game"],
					tested["boss"],
					tested["riders"],
					tested["rays"],
					tested["darts"]
				]
			)
		)
		quit(0)
	else:
		print("block_collision_check: %d problem(s)" % problems.size())
		for p in problems.slice(0, 12):
			print("  " + p)
		quit(1)


func _fail(text: String) -> void:
	problems.append(text)


# the sizes WorldModels makes solid are the sizes of the models it draws
func _check_models() -> void:
	for entry in [
		["BENCH_SIZE", WorldModels.BENCH_PATH, WorldModels.BENCH_SIZE],
		["CRATE_SIZE", WorldModels.CRATE_PATH, WorldModels.CRATE_SIZE]
	]:
		var real = WorldModels.model_size(entry[1])
		if real == Vector3.ZERO:
			_fail("%s could not be loaded (import the project first)" % entry[1])
		elif (real - entry[2]).length() > 0.01:
			_fail(
				(
					"WorldModels.%s is %s but the model %s is %s metres: make them the same"
					% [entry[0], entry[2], entry[1], real]
				)
			)


# ---------------------------------------------------------------- the boxes, measured here (not by the arena)
# A box is an entry of WorldModels.solid_boxes: {"at": Vector2, "yaw", "half": Vector2, "y0", "y1"}. The model is turned
# by yaw about the up axis, which takes its x axis to (cos, -sin) and its z axis to (sin, cos) in the world's (x, z).
func _ex(box: Dictionary) -> Vector2:
	return Vector2(cos(float(box["yaw"])), -sin(float(box["yaw"])))


func _ez(box: Dictionary) -> Vector2:
	return Vector2(sin(float(box["yaw"])), cos(float(box["yaw"])))


# the world point (on the ground) at local (lx, lz) of the box
func _local_point(box: Dictionary, lx: float, lz: float) -> Vector3:
	var p: Vector2 = box["at"] + _ex(box) * lx + _ez(box) * lz
	return Vector3(p.x, 0.0, p.y)


# the world point p in the box's own frame (x, z)
func _local_of(box: Dictionary, p: Vector3) -> Vector2:
	var d = Vector2(p.x, p.z) - box["at"]
	return Vector2(d.dot(_ex(box)), d.dot(_ez(box)))


# how far along the ground p is from the box's footprint (0 inside it)
func _gap(box: Dictionary, p: Vector3) -> float:
	var l = _local_of(box, p)
	var qx = maxf(absf(l.x) - box["half"].x, 0.0)
	var qz = maxf(absf(l.y) - box["half"].y, 0.0)
	return sqrt(qx * qx + qz * qz)


func _min_gap(boxes: Array, p: Vector3) -> float:
	var best = INF
	for box in boxes:
		best = minf(best, _gap(box, p))
	return best


# true if p is inside any of the boxes, height included
func _inside_any(boxes: Array, p: Vector3) -> bool:
	for box in boxes:
		var l = _local_of(box, p)
		if (
			absf(l.x) <= box["half"].x
			and absf(l.y) <= box["half"].y
			and p.y >= box["y0"]
			and p.y <= box["y1"]
		):
			return true
	return false


# where the ray from `from` along the unit vector `dir` first enters any of the boxes within `reach`, or -1.0: each box
# cut in its own frame with the slab method (a ray that starts inside a box is not stopped by it)
func _expect_hit(boxes: Array, from: Vector3, dir: Vector3, reach: float) -> float:
	var best = -1.0
	for box in boxes:
		var ex = _ex(box)
		var ez = _ez(box)
		var f = Vector2(from.x, from.z) - box["at"]
		var o = Vector3(f.dot(ex), from.y, f.dot(ez))
		var d2 = Vector2(dir.x, dir.z)
		var d = Vector3(d2.dot(ex), dir.y, d2.dot(ez))
		var lo = Vector3(-box["half"].x, box["y0"], -box["half"].y)
		var hi = Vector3(box["half"].x, box["y1"], box["half"].y)
		var near = -INF
		var far = INF
		var missed = false
		for axis in range(3):
			if absf(d[axis]) < 0.000001:
				if o[axis] < lo[axis] or o[axis] > hi[axis]:
					missed = true
				continue
			var t1 = (lo[axis] - o[axis]) / d[axis]
			var t2 = (hi[axis] - o[axis]) / d[axis]
			near = maxf(near, minf(t1, t2))
			far = minf(far, maxf(t1, t2))
		if not missed and near > 0.0 and near <= far and near <= reach:
			if best < 0.0 or near < best:
				best = near
	return best


# ---------------------------------------------------------------- the ground round a point
# true if the ground at p and a metre round it is open (no building, no tunnel), and no tree and no lamp pole is within
# `from_props` metres of it: what is left of the arena's blocking there is the benches and crates
func _open_here(arena, props: Dictionary, p: Vector3, from_props: float) -> bool:
	var s: String = arena.surface_at(p)
	if s == "building" or s == "tunnel":
		return false
	for k in range(8):
		var a = TAU * float(k) / 8.0
		var q = p + Vector3(cos(a), 0.0, sin(a))
		var sq: String = arena.surface_at(q)
		if sq == "building" or sq == "tunnel":
			return false
	var flat = Vector2(p.x, p.z)
	for tree in props["trees"]:
		if (tree["pos"] as Vector2).distance_to(flat) < from_props:
			return false
	for lamp in props["lamps"]:
		if (lamp["pole"] as Vector2).distance_to(flat) < from_props:
			return false
	return true


# true if a walk of `length` metres from `from` along `dir` (every quarter metre) is on free ground for `who`
func _line_free(arena, from: Vector3, dir: Vector3, length: float, who: String) -> bool:
	var d = 0.0
	while d <= length:
		var q = from + dir * d
		if arena.clamp_walk(q, who).distance_to(q) > 0.001:
			return false
		d += 0.25
	return true


# true if no dart is stopped by the arena (buildings, trees, lamps, boxes) anywhere on the line from `a` to `b`
func _air_clear(arena, a: Vector3, b: Vector3) -> bool:
	var length = a.distance_to(b)
	var dir = (b - a) / maxf(length, 0.0001)
	var d = 0.0
	while d <= length:
		if arena.ray_blocked(a + dir * d):
			return false
		d += 0.1
	return arena.tree_hit(a, dir, length) < 0.0


# ---------------------------------------------------------------- one arena
# the boxes to look at, spread over the benches (the first `n_benches` of the list) and over the crates
func _sample(n_total: int, n_benches: int) -> Array:
	var out = []
	var benches = mini(BENCHES_PER_ARENA, n_benches)
	for i in range(benches):
		out.append(int(float(i) * float(n_benches) / float(benches)))
	var crates = mini(CRATES_PER_ARENA, n_total - n_benches)
	for i in range(crates):
		out.append(n_benches + int(float(i) * float(n_total - n_benches) / float(crates)))
	return out


func _check_arena(arena, planned: Dictionary, props: Dictionary, tag: String) -> void:
	var boxes: Array = WorldModels.solid_boxes(planned)
	var n_benches = planned["benches"].size()
	if boxes.size() != n_benches + planned["crates"].size():
		_fail(
			(
				"%s: %d solid boxes for %d benches and %d crates"
				% [tag, boxes.size(), n_benches, planned["crates"].size()]
			)
		)
		return
	var in_table = 0
	for key in arena._blocks:
		in_table += (arena._blocks[key] as Array).size()
	if in_table != boxes.size():
		_fail("%s: the arena keeps %d boxes, the plan has %d" % [tag, in_table, boxes.size()])
	for box in boxes:
		var reach = Vector2(box["half"]).length()
		if (
			reach > GeneratedArena.BLOCK_REACH
			or box["y0"] < 0.0
			or box["y1"] > GeneratedArena.BLOCK_TOP_Y
		):
			_fail(
				(
					"%s: a box at %s reaches %.2f m, %.2f to %.2f m high: outside what the arena looks for"
					% [tag, box["at"], reach, box["y0"], box["y1"]]
				)
			)
	var rng = RandomNumberGenerator.new()
	rng.seed = 91
	var picked = _sample(boxes.size(), n_benches)
	for index in picked:
		var box: Dictionary = boxes[index]
		var is_bench = index < n_benches
		var label = "%s %s at %s" % [tag, "bench" if is_bench else "crate", box["at"]]
		tested["benches" if is_bench else "crates"] += 1
		if not is_bench and float(box["y0"]) > 0.0:
			tested["stacked"] += 1
		_check_grid(arena, props, boxes, box, label)
		_check_inside(arena, box, label)
		_walk_at_box(arena, boxes, box, is_bench, label)
		_check_rays(arena, props, boxes, box, rng, label)
	_check_spots(arena, boxes, tag, rng)
	_check_riders(arena, boxes, picked, tag)


# round one box, point by point: what the arena says is what the boxes of the plan say
func _check_grid(arena, props: Dictionary, boxes: Array, box: Dictionary, label: String) -> void:
	var out = GRID_OUT + Vector2(box["half"]).length()
	var steps = int(ceil(out / GRID_STEP))
	var wrong = 0
	for iz in range(-steps, steps + 1):
		for ix in range(-steps, steps + 1):
			var p = Vector3(
				box["at"].x + float(ix) * GRID_STEP, 0.0, box["at"].y + float(iz) * GRID_STEP
			)
			var g = _min_gap(boxes, p)
			if g > GRID_OUT:
				continue
			if not _open_here(arena, props, p, 1.6):
				continue
			tested["points"] += 1
			for who in [["obstacle_at", BOSS_SEES], ["rider_blocked", BOSS_KEEP]]:
				if (
					absf(g - float(who[1])) > EDGE
					and bool(arena.call(who[0], p)) != (g < float(who[1]))
				):
					wrong += 1
					if wrong <= 2:
						_fail(
							(
								"%s: %s is %s at %s, %.3f m from the nearest box"
								% [label, who[0], not (g < float(who[1])), p, g]
							)
						)
			for who in [["player", PLAYER_KEEP], ["boss", BOSS_KEEP]]:
				var free = arena.clamp_walk(p, who[0]).distance_to(p) < 0.001
				if absf(g - float(who[1])) > EDGE and free != (g >= float(who[1])):
					wrong += 1
					if wrong <= 2:
						_fail(
							(
								"%s: a %s at %s, %.3f m from the nearest box, is %s"
								% [
									label,
									who[0],
									p,
									g,
									"held" if free == false and g >= float(who[1]) else "free"
								]
							)
						)
			for y in GRID_HEIGHTS:
				var q = Vector3(p.x, float(y), p.z)
				var want = _inside_any(boxes, q)
				if arena.ray_blocked(q) != want and not _on_a_face(boxes, q):
					wrong += 1
					if wrong <= 2:
						_fail("%s: ray_blocked is %s at %s" % [label, not want, q])
	if wrong > 2:
		_fail("%s: %d points disagree with the boxes" % [label, wrong])


# true if q is within a hair of a face of a box: the arena and the test round differently there
func _on_a_face(boxes: Array, q: Vector3) -> bool:
	for box in boxes:
		var l = _local_of(box, q)
		var near_x = absf(absf(l.x) - float(box["half"].x)) < EDGE
		var near_z = absf(absf(l.y) - float(box["half"].y)) < EDGE
		var near_y = absf(q.y - float(box["y0"])) < EDGE or absf(q.y - float(box["y1"])) < EDGE
		var in_x = absf(l.x) <= float(box["half"].x) + EDGE
		var in_z = absf(l.y) <= float(box["half"].y) + EDGE
		var in_y = q.y >= float(box["y0"]) - EDGE and q.y <= float(box["y1"]) + EDGE
		if in_x and in_z and in_y and (near_x or near_z or near_y):
			return true
	return false


# a body put in the middle of the box is brought out to its own distance, not further than it has to be
func _check_inside(arena, box: Dictionary, label: String) -> void:
	var at = Vector3(box["at"].x, 0.0, box["at"].y)
	for who in [["player", PLAYER_KEEP], ["boss", BOSS_KEEP], ["pickup", PICKUP_KEEP]]:
		var out: Vector3 = arena.clamp_walk(at, who[0])
		var g = _gap(box, out)
		if g < float(who[1]) - SLACK or g > float(who[1]) + 3.0:
			_fail(
				(
					"%s: clamp_walk put a %s %.2f m from the box, expected about %.2f m"
					% [label, who[0], g, who[1]]
				)
			)
		if arena.clamp_walk(out, who[0]).distance_to(out) > 0.001:
			_fail("%s: the %s's free spot %s is not free" % [label, who[0], out])


# ---------------------------------------------------------------- walking at a box
func _walk_at_box(arena, boxes: Array, box: Dictionary, is_bench: bool, label: String) -> void:
	var at = Vector3(box["at"].x, 0.0, box["at"].y)
	for dir2 in FROM_DIRS:
		var dir = Vector3(dir2.x, 0.0, dir2.y)  # the way the body walks, towards the box
		var side = Vector3(-dir.z, 0.0, dir.x)
		for off in OFFSETS:
			var start = at - dir * APPROACH + side * float(off)
			if not _open_way(arena, boxes, start, dir, PLAYER_KEEP + 0.3, "player"):
				continue
			var tag = "%s, walking %s %.1f m off the line" % [label, dir, off]
			# the player at run speed, a step at a time as the game takes it
			var p = start
			var closest = INF
			for i in range(int((APPROACH + 2.5) / (RUN * DT))):
				p = arena.slide_walk(p, p + dir * RUN * DT)
				closest = minf(closest, _min_gap(boxes, p))
			tested["walks"] += 1
			if closest < PLAYER_KEEP - SLACK:
				_fail(
					(
						"%s: the player got to %.2f m from a box (keeps %.2f m)"
						% [tag, closest, PLAYER_KEEP]
					)
				)
			if arena.clamp_walk(p, "player").distance_to(p) > 0.001:
				_fail("%s: the player ended at %s, not on free ground" % [tag, p])
			if is_bench and absf(off) < 0.01 and _gap(box, p) > PLAYER_KEEP + 0.05:
				_fail(
					(
						"%s: walking dead at the bench stopped %.2f m from it, not against it"
						% [tag, _gap(box, p)]
					)
				)
			# a boss at its charge speed
			if not _open_way(arena, boxes, start, dir, BOSS_KEEP + 0.3, "boss"):
				continue
			var b = start
			var b_closest = INF
			for i in range(int((APPROACH + 2.5) / (BOSS_RUN * DT))):
				b = arena.slide_walk(b, b + dir * BOSS_RUN * DT, "boss")
				b_closest = minf(b_closest, _min_gap(boxes, b))
			tested["boss"] += 1
			if b_closest < BOSS_KEEP - SLACK:
				_fail(
					(
						"%s: a boss got to %.2f m from a box (keeps %.2f m)"
						% [tag, b_closest, BOSS_KEEP]
					)
				)
	# once through the game's own player step: the player node is put in front of the box and `pvel` is set every frame
	for candidate in FROM_DIRS:
		var cd = Vector3(candidate.x, 0.0, candidate.y)
		var game_start = at - cd * APPROACH
		if not _open_way(arena, boxes, game_start, cd, PLAYER_KEEP + 0.3, "player"):
			continue
		var old_arena = main.arena
		main.arena = arena
		_ground()
		main.player.position = game_start
		var game_closest = INF
		for i in range(90):
			main.pvel = cd * RUN
			main.invuln = 1000.0
			main._process(DT)
			game_closest = minf(game_closest, _min_gap(boxes, main.player.position))
		main.arena = old_arena
		_ground()
		tested["game"] += 1
		if game_closest < PLAYER_KEEP - SLACK:
			_fail(
				(
					"%s: in the game the player got to %.2f m from a box (keeps %.2f m)"
					% [label, game_closest, PLAYER_KEEP]
				)
			)
		break


# true if a walk from `start` along `dir` is on free ground every quarter metre until it is within `until` metres of a box
func _open_way(
	arena, boxes: Array, start: Vector3, dir: Vector3, until: float, who: String
) -> bool:
	var d = 0.0
	while d <= APPROACH + 2.5:
		var q = start + dir * d
		if _min_gap(boxes, q) <= until:
			return true
		if arena.clamp_walk(q, who).distance_to(q) > 0.001:
			return false
		d += 0.25
	return false


# ---------------------------------------------------------------- darts and phones
# darts and phones against a box: whole rays, a line of sight, a phone's step and a real dart
func _check_rays(
	arena,
	props: Dictionary,
	boxes: Array,
	box: Dictionary,
	rng: RandomNumberGenerator,
	label: String
) -> void:
	var at = Vector3(box["at"].x, 0.0, box["at"].y)
	var mid = (float(box["y0"]) + float(box["y1"])) * 0.5
	# the rays are 12 m long: no tree and no lamp within 12 m of the box, so nothing else of the arena is on them
	for tree in props["trees"]:
		if (tree["pos"] as Vector2).distance_to(box["at"]) < 14.0:
			return
	for lamp in props["lamps"]:
		if (lamp["pole"] as Vector2).distance_to(box["at"]) < 14.0:
			return
	var ex = Vector3(_ex(box).x, 0.0, _ex(box).y)
	var ez = Vector3(_ez(box).x, 0.0, _ez(box).y)
	var rays = []  # [from, unit dir]
	# along both axes of the box, through its middle, from both sides, at its middle height
	for axis in [ex, ez]:
		for sign in [1.0, -1.0]:
			var dir: Vector3 = axis * -float(sign)
			rays.append([at + axis * float(sign) * 5.0 + Vector3(0.0, mid, 0.0), dir])
	# beside the box, above it, slanting into it, and a fan of random ones from further out
	rays.append([_local_point(box, -5.0, float(box["half"].y) + 0.06) + Vector3(0.0, mid, 0.0), ex])
	rays.append(
		[_local_point(box, -5.0, -float(box["half"].y) - 0.06) + Vector3(0.0, mid, 0.0), ex]
	)
	rays.append([_local_point(box, -5.0, 0.0) + Vector3(0.0, float(box["y1"]) + 0.08, 0.0), ex])
	var slant = (
		(at + Vector3(0.0, float(box["y1"]) - 0.05, 0.0) - (at - ex * 4.0 + Vector3(0.0, 0.1, 0.0)))
		. normalized()
	)
	rays.append([at - ex * 4.0 + Vector3(0.0, 0.1, 0.0), slant])
	for i in range(16):
		var a = rng.randf() * TAU
		var from = at + Vector3(cos(a), 0.0, sin(a)) * rng.randf_range(2.0, 6.0)
		from.y = rng.randf_range(0.1, 2.2)
		var target = (
			at
			+ Vector3(
				rng.randf_range(-1.0, 1.0), rng.randf_range(0.0, 1.8), rng.randf_range(-1.0, 1.0)
			)
		)
		rays.append([from, (target - from).normalized()])
	for ray in rays:
		var from: Vector3 = ray[0]
		if arena.surface_at(from) == "building":
			continue
		var want = _expect_hit(boxes, from, ray[1], 12.0)
		var hit: float = arena.tree_hit(from, ray[1], 12.0)
		tested["rays"] += 1
		if (hit < 0.0) != (want < 0.0) or (hit >= 0.0 and absf(hit - want) > 0.02):
			_fail(
				(
					"%s: a ray from %s along %s hit at %.2f m, expected %.2f m"
					% [label, from, ray[1], hit, want]
				)
			)
	if (
		arena.tree_hit(at - ex * 5.0 + Vector3(0.0, mid, 0.0), ex, 5.0 - float(box["half"].x) - 1.0)
		>= 0.0
	):
		_fail("%s: a ray that stops 1 m short of the box hit it" % label)
	# a line of sight across the box is not clear (where nothing else is in the way before it)
	var a = at - ex * 4.0 + Vector3(0.0, mid, 0.0)
	var b = at + ex * 4.0 + Vector3(0.0, mid, 0.0)
	if _air_clear(
		arena, a, _local_point(box, -float(box["half"].x) - 0.05, 0.0) + Vector3(0.0, mid, 0.0)
	):
		if Threats.sight_clear(arena, a, b):
			_fail("%s: the line of sight across the box is clear" % label)
	var old_arena = main.arena
	main.arena = arena
	# a phone's step across the box is blocked
	var prev = _local_point(box, -float(box["half"].x) - 0.2, 0.0) + Vector3(0.0, mid, 0.0)
	var next = _local_point(box, -float(box["half"].x) + 0.2, 0.0) + Vector3(0.0, mid, 0.0)
	if not main.phone_sys.flight_blocked(prev, next):
		_fail("%s: a phone's step into the box is not blocked" % label)
	# and a real dart: aimed at the box it stops at its face, aimed past its side it flies on
	var old_spread = main.spread_deg
	main.spread_deg = 0.0
	var darts_here = 0
	var lift = Vector3(0.0, mid, 0.0)
	for aim in [ex, -ex, ez, -ez]:
		var across = Vector3(-aim.z, 0.0, aim.x)
		var on_x = absf(aim.dot(ex)) > 0.5
		var half_along = float(box["half"].x) if on_x else float(box["half"].y)
		var half_across = float(box["half"].y) if on_x else float(box["half"].x)
		# aimed at the middle, and aimed past either side (a crate stands against a wall: one of the two sides may be a wall)
		for off in [0.0, half_across + 0.3, -(half_across + 0.3)]:
			if darts_here >= 3:
				break
			var shift = across * float(off)
			var eye = at - aim * (half_along + 4.0) + shift + lift
			var line_to = at + shift + lift
			var line_end = at + aim * (half_along + 3.0) + shift + lift
			var open_line = _air_clear(arena, eye, at - aim * (half_along + 0.1) + shift + lift)
			if off != 0.0:
				open_line = _air_clear(arena, eye, line_end)
			if not open_line:
				continue
			darts_here += 1
			tested["darts"] += 1
			main.cam.global_position = eye
			main.cam.look_at(eye + aim, Vector3.UP)
			main.combat_sys.shoot_dart(1, false)
			if main.darts.is_empty():
				_fail("%s: shoot_dart sent no dart" % label)
				continue
			var end: Vector3 = main.darts.back()["b"]
			var along = (end - line_to).dot(aim)  # metres past the box's middle along the shot
			if off == 0.0 and absf(along - -half_along) > 0.1:
				_fail(
					(
						"%s: a dart at the box ended %.2f m along, not at its face %.2f"
						% [label, along, -half_along]
					)
				)
			if off != 0.0 and along < half_along + 0.5:
				_fail("%s: a dart past the box's side was stopped %.2f m along" % [label, along])
			if main.darts.size() > 70:
				main.darts.clear()
	main.spread_deg = old_spread
	main.arena = old_arena


# ---------------------------------------------------------------- spots and riders
# the extraction point and the caches never stand in a box's cell and are always somewhere a player can stand
func _check_spots(arena, boxes: Array, tag: String, rng: RandomNumberGenerator) -> void:
	for round_no in range(4):
		rng.seed = 40 + round_no
		var goal: Vector3 = arena.goal_spot(rng)
		var spots: Array = [goal]
		spots.append_array(arena.cache_spots(3, goal, rng))
		for s in spots:
			if _min_gap(boxes, s) < PLAYER_KEEP - SLACK:
				_fail(
					(
						"%s: a spot at %s is %.2f m from a bench or a crate"
						% [tag, s, _min_gap(boxes, s)]
					)
				)


# a rider on one side of a box, the player on the other: the rider goes round the box and reaches the player
func _check_riders(arena, boxes: Array, picked: Array, tag: String) -> void:
	var old_arena = main.arena
	main.arena = arena
	main.clear_riders()
	var done = 0
	for index in picked:
		if done >= RIDER_TRIES:
			break
		var box: Dictionary = boxes[index]
		var at = Vector3(box["at"].x, 0.0, box["at"].y)
		for dir2 in FROM_DIRS:
			var dir = Vector3(dir2.x, 0.0, dir2.y)
			var rider_spot = at - dir * RIDER_FROM
			var player_spot = at + dir * RIDER_FROM
			# open ground over the whole way, bar the box itself: both ends and the two stretches before its margin
			if not (
				_line_free(arena, rider_spot, dir, RIDER_FROM - 2.5, "boss")
				and _line_free(arena, at + dir * 2.5, dir, RIDER_FROM - 2.5, "boss")
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
			var closest_box = INF
			var closest_player = INF
			main.state = "check"  # nobody gets run over mid-check
			for step in range(int(RIDER_SECONDS / DT)):
				main.player.position = player_spot
				main.rider_sys.move_rider(r, DT)
				if r["hidden"]:
					continue
				closest_box = minf(closest_box, _min_gap(boxes, r["pos"]))
				closest_player = minf(
					closest_player,
					Vector2(r["pos"].x - player_spot.x, r["pos"].z - player_spot.z).length()
				)
			tested["riders"] += 1
			done += 1
			var label = "%s, a rider riding %s at a box at %s" % [tag, dir, box["at"]]
			if closest_box < RIDER_KEEP:
				_fail(
					(
						"%s: it got to %.2f m from a box (keeps %.2f m)"
						% [label, closest_box, RIDER_KEEP + 0.02]
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
