extends SceneTree
# Checks that the player can hop onto the benches and crates of a generated arena, stand on them, hop on them again and
# walk off them, and that nothing else got easier to pass (README "Jump onto crates and benches"; the boxes are still
# solid walls for a player on the ground, tools/block_collision_check.gd). The arena says what the floor under the feet is
# (`Arena.stand_height`) and the player's step (`player.gd`) stands on it. Run from the project folder:
#   godot --headless --path . --script res://tools/stand_on_props_check.gd
# or: python tools/run_checks.py stand_on_props
# Optional argument after "--": how many generated arenas with benches and crates to try (default 4).
# On each arena, for a few benches and crates that stand alone (no other box and no tree or lamp pole near), it checks that
#   - the base Arena has nothing to stand on (stand_height is 0), and `stand_height` is the top of the box for feet over its
#     footprint that are at the top or less than STAND_TOL below it, and 0 for feet lower than that and for a point just
#     outside the footprint; a boss is held out of the box at every height, a player on the ground is brought out of it
#   - a bench has a spot on its top where a player may stand (a crate against a wall has one too, unless the wall's 0.45 m
#     margin leaves none: that is noted, not a failure)
#   - walking at the box on the ground never gets the player on it or closer than the usual 0.48 m
#   - a hop at run speed or at walking pace, from a little under 2 m away, through the game's own player step
#     (main._process), ends on the top: the player stands there (not airborne, `jump_h` and `floor_h` are the box's top,
#     not "hurdling" so a rider still reaches the player) and was never inside the footprint below the top on the way
#   - standing on the box, a hop goes up from the top and comes down on it, and walking off at walking pace ends on the
#     ground, on free ground
#   - a crate stacked on another is still a wall from the lower crate's top (feet at the lower top cannot enter it)
# Exits with status 1 and prints the first problems.

const ArenaGenScript = preload("res://scripts/arena_gen.gd")
const GeneratedArena = preload("res://scripts/arena_generated.gd")
const BaseArena = preload("res://scripts/arena.gd")
const WorldModels = preload("res://scripts/world_models.gd")
const WorldDress = preload("res://scripts/world_dress.gd")
const MAIN_SCENE = "res://main.tscn"
const DT = 1.0 / 60.0
const FIRST_SEED = 5000
const SEED_TRIES = 400  # generated arenas looked at to find ones with benches and crates
const BENCHES_PER_ARENA = 2
const CRATES_PER_ARENA = 2
const ALONE = 2.6  # metres: a box with another box, a trunk or a lamp pole this close to its middle is not looked at
const KEEP = 0.45 + WorldModels.BLOCK_SOLID  # the closest a player on the ground gets to a box
const SLACK = 0.01
const RUN = 5.8  # metres per second
const WALK = 3.2
const APPROACH = 3.0  # metres from the box a walk on the ground starts
const HOP_SPEEDS = [RUN, WALK]
const HOP_GAPS = [1.2, 1.5, 1.8, 2.1]  # metres from the footprint a hop starts; the first that gets on counts
const FROM_DIRS = [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]

var problems = []
var notes = []
var main = null
var tested = {"floors": 0, "walks": 0, "hops": 0, "standing": 0, "stacks": 0}


func _initialize() -> void:
	var count = 4
	var args = OS.get_cmdline_user_args()
	if args.size() > 0:
		count = int(args[0])
	var base = BaseArena.new()
	if base.stand_height(Vector3(1.0, 2.0, 3.0)) != 0.0:
		_fail("the base Arena has something to stand on")
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
	# a stack of crates is rare: keep looking (up to a few more arenas) until one has been tested
	while tries < SEED_TRIES and (arenas < count or (tested["stacks"] == 0 and arenas < count + 6)):
		var layout = ArenaGenScript.generate(FIRST_SEED + tries, rules)
		tries += 1
		if layout.is_empty():
			continue
		var planned: Dictionary = WorldModels.plan_props(layout)
		if planned["benches"].is_empty() or planned["crates"].is_empty():
			continue
		arenas += 1
		_check_arena(
			GeneratedArena.new(layout, rules),
			planned,
			WorldDress.props_of(layout),
			"arena %d (%s)" % [FIRST_SEED + tries - 1, layout.get("style", "")]
		)
	if arenas == 0:
		_fail("no generated arena with benches and crates was found in %d seeds" % SEED_TRIES)
	for key in tested:
		if arenas > 0 and key != "stacks" and tested[key] == 0:
			_fail("the check never tested %s (it is not covering what it says)" % key)
	if arenas > 0 and tested["stacks"] == 0:
		notes.append("no stacked crates were found in %d arenas" % arenas)
	for n in notes.slice(0, 6):
		print("stand_on_props_check: note: " + n)
	if problems.is_empty():
		print(
			(
				"stand_on_props_check: %d arenas; %d floors measured, %d walks held at the side, %d hops got on top, %d boxes stood on, hopped on and walked off, %d stacks stay walls"
				% [
					arenas,
					tested["floors"],
					tested["walks"],
					tested["hops"],
					tested["standing"],
					tested["stacks"]
				]
			)
		)
		quit(0)
	else:
		print("stand_on_props_check: %d problem(s)" % problems.size())
		for p in problems.slice(0, 12):
			print("  " + p)
		quit(1)


func _fail(text: String) -> void:
	problems.append(text)


# ---------------------------------------------------------------- the boxes, measured here (not by the arena)
# A box is an entry of WorldModels.solid_boxes: {"at": Vector2, "yaw", "half": Vector2, "y0", "y1"}. The model is turned
# by yaw about the up axis, which takes its x axis to (cos, -sin) and its z axis to (sin, cos) in the world's (x, z).
func _ex(box: Dictionary) -> Vector2:
	return Vector2(cos(float(box["yaw"])), -sin(float(box["yaw"])))


func _ez(box: Dictionary) -> Vector2:
	return Vector2(sin(float(box["yaw"])), cos(float(box["yaw"])))


# the world point (at height y) at local (lx, lz) of the box
func _local_point(box: Dictionary, lx: float, lz: float, y: float) -> Vector3:
	var p: Vector2 = box["at"] + _ex(box) * lx + _ez(box) * lz
	return Vector3(p.x, y, p.y)


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


# the point at ground level `gap` metres (a little more) from the box's footprint, on the line back from `target` along
# the unit vector `dir`
func _start_toward(box: Dictionary, target: Vector3, dir: Vector3, gap: float) -> Vector3:
	var flat = Vector3(target.x, 0.0, target.z)
	var d = 0.0
	while d < 12.0 and _gap(box, flat - dir * d) < gap:
		d += 0.05
	return flat - dir * d


# true if a walk from `start` along `dir` for `length` metres is on free ground for a player on the ground at every
# quarter metre, except close to a box (the walk is meant to meet it, or to cross its top)
func _way_ok(arena, boxes: Array, start: Vector3, dir: Vector3, length: float) -> bool:
	var d = 0.0
	while d <= length:
		var q = start + dir * d
		if _min_gap(boxes, q) > 0.6 and arena.clamp_walk(q, "player").distance_to(q) > 0.001:
			return false
		d += 0.25
	return true


# one of the four axes to walk at `target` along, free from `gap` metres before the box up to the target, or Vector3.ZERO
func _approach_dir(arena, boxes: Array, box: Dictionary, target: Vector3, gap: float) -> Vector3:
	for candidate in FROM_DIRS:
		var cd = Vector3(candidate.x, 0.0, candidate.y)
		var start = _start_toward(box, target, cd, gap)
		var flat = Vector3(target.x, 0.0, target.z)
		if _way_ok(arena, boxes, start, cd, start.distance_to(flat)):
			return cd
	return Vector3.ZERO


# one of the four axes to walk away from `from` along, free (at ground level, out of the box's neighbourhood) for 4 m, or
# Vector3.ZERO
func _exit_dir(arena, boxes: Array, from: Vector3) -> Vector3:
	for candidate in FROM_DIRS:
		var cd = Vector3(candidate.x, 0.0, candidate.y)
		if _way_ok(arena, boxes, Vector3(from.x, 0.0, from.z), cd, 4.0):
			return cd
	return Vector3.ZERO


# the spot on the top of the box nearest its middle where a player may stand (the arena keeps the feet on free ground
# there), as a point at the height of the top; Vector3.INF when there is none
func _stand_point(arena, box: Dictionary) -> Vector3:
	var top = float(box["y1"])
	var best = Vector3.INF
	var best_d = INF
	var hx = float(box["half"].x)
	var hz = float(box["half"].y)
	var steps_x = int(floor(hx / 0.1))
	var steps_z = int(floor(hz / 0.1))
	for ix in range(-steps_x, steps_x + 1):
		for iz in range(-steps_z, steps_z + 1):
			var p = _local_point(box, float(ix) * 0.1, float(iz) * 0.1, top)
			if absf(arena.stand_height(p) - top) > 0.002:
				continue
			if arena.clamp_walk(p, "player").distance_to(p) > 0.001:
				continue
			var d = float(ix * ix + iz * iz)
			if d < best_d:
				best_d = d
				best = p
	return best


# true if no tree and no lamp pole is within `reach` metres of the box's middle
func _props_clear(props: Dictionary, box: Dictionary, reach: float) -> bool:
	for tree in props["trees"]:
		if (tree["pos"] as Vector2).distance_to(box["at"]) < reach:
			return false
	for lamp in props["lamps"]:
		if (lamp["pole"] as Vector2).distance_to(box["at"]) < reach:
			return false
	return true


# true if no other box has its middle within ALONE metres of this one's
func _alone(boxes: Array, index: int) -> bool:
	for i in range(boxes.size()):
		if i != index and (boxes[i]["at"] as Vector2).distance_to(boxes[index]["at"]) < ALONE:
			return false
	return true


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


# ---------------------------------------------------------------- one arena
func _check_arena(arena, planned: Dictionary, props: Dictionary, tag: String) -> void:
	var boxes: Array = WorldModels.solid_boxes(planned)
	var n_benches = planned["benches"].size()
	var benches = 0
	var crates = 0
	var stacks = 0
	for index in range(boxes.size()):
		var box: Dictionary = boxes[index]
		var is_bench = index < n_benches
		var label = "%s %s at %s" % [tag, "bench" if is_bench else "crate", box["at"]]
		if float(box["y0"]) > 0.0:  # a crate on top of another
			if stacks < 1 and _props_clear(props, box, ALONE):
				stacks += 1
				_check_stack(arena, boxes, box, label)
			continue
		if not _alone(boxes, index) or not _props_clear(props, box, ALONE):
			continue
		if is_bench:
			if benches >= BENCHES_PER_ARENA:
				continue
			benches += 1
		else:
			if crates >= CRATES_PER_ARENA:
				continue
			crates += 1
		_check_floor(arena, box, label)
		_check_walk(arena, boxes, box, label)
		var spot = _stand_point(arena, box)
		if spot == Vector3.INF:
			if is_bench:
				_fail("%s: no spot on the top where a player may stand" % label)
			else:
				notes.append("%s: no spot on the top where the player's 0.45 m margin fits" % label)
			continue
		_check_hop(arena, boxes, box, spot, label)
		_check_standing(arena, boxes, box, spot, label)


# what the arena says the floor is, point by point
func _check_floor(arena, box: Dictionary, label: String) -> void:
	tested["floors"] += 1
	var top = float(box["y1"])
	var tol = GeneratedArena.STAND_TOL
	var hx = float(box["half"].x)
	var cases = [
		["feet at the top over the middle", _local_point(box, 0.0, 0.0, top), top],
		["feet a little under the top limit", _local_point(box, 0.0, 0.0, top - tol + 0.02), top],
		["feet below the top limit", _local_point(box, 0.0, 0.0, top - tol - 0.02), 0.0],
		["feet on the ground over the middle", _local_point(box, 0.0, 0.0, 0.0), 0.0],
		["feet above the top, over the middle", _local_point(box, 0.0, 0.0, top + 0.5), top],
		["feet at the top just inside the end", _local_point(box, hx - 0.05, 0.0, top), top],
		["feet at the top just outside the end", _local_point(box, hx + 0.15, 0.0, top), 0.0],
	]
	for c in cases:
		var got: float = arena.stand_height(c[1])
		if absf(got - float(c[2])) > 0.002:
			_fail("%s: stand_height with %s is %.3f, expected %.3f" % [label, c[0], got, c[2]])
	var on_top: Vector3 = _local_point(box, 0.0, 0.0, top)
	var inside: Vector3 = _local_point(box, 0.0, 0.0, 0.0)
	if arena.clamp_walk(inside, "player").distance_to(inside) < 0.1:
		_fail("%s: a player on the ground inside the box is not brought out" % label)
	if arena.clamp_walk(on_top, "boss").distance_to(on_top) < 0.1:
		_fail("%s: a boss is let into the box when it is asked at the height of the top" % label)


# walking at the box on the ground (no jump): it is still a wall
func _check_walk(arena, boxes: Array, box: Dictionary, label: String) -> void:
	var mid = Vector3(box["at"].x, 0.0, box["at"].y)
	var cd = _approach_dir(arena, boxes, box, mid, APPROACH)
	if cd == Vector3.ZERO:
		return
	var old_arena = main.arena
	main.arena = arena
	_ground()
	main.player.position = _start_toward(box, mid, cd, APPROACH)
	var closest = INF
	var highest = 0.0
	for i in range(75):
		main.pvel = cd * RUN
		main.invuln = 1000.0
		main._process(DT)
		closest = minf(closest, _gap(box, main.player.position))
		highest = maxf(highest, main.jump_h)
	main.arena = old_arena
	_ground()
	tested["walks"] += 1
	if closest < KEEP - SLACK:
		_fail(
			(
				"%s: walking at it on the ground got to %.2f m from it (keeps %.2f m)"
				% [label, closest, KEEP]
			)
		)
	if highest > 0.001:
		_fail("%s: walking at it on the ground lifted the player %.2f m" % [label, highest])


# one hop at the spot on the box from `gap` metres away, through the game's own step; stops when the player stands on it
func _hop_attempt(
	arena, box: Dictionary, spot: Vector3, cd: Vector3, gap: float, speed: float
) -> Dictionary:
	var top = float(box["y1"])
	var old_arena = main.arena
	main.arena = arena
	_ground()
	main.player.position = _start_toward(box, spot, cd, gap)
	var out = {"stood": false, "low": false, "bad_floor": false, "hurdling": false}
	for i in range(80):
		main.pvel = cd * speed
		main.invuln = 1000.0
		if i == 0:
			main.player_sys.request_jump()
		main._process(DT)
		var over = _gap(box, main.player.position) <= 0.0
		if over and main.jump_h < top - GeneratedArena.STAND_TOL - 0.002:
			out["low"] = true
		if over and not main.player_sys.is_airborne() and absf(main.jump_h - top) < 0.002:
			out["stood"] = true
			out["bad_floor"] = absf(main.floor_h - top) > 0.002
			out["hurdling"] = main.player_sys.is_hurdling()
			break
	main.arena = old_arena
	_ground()
	return out


# a hop onto the top
func _check_hop(arena, boxes: Array, box: Dictionary, spot: Vector3, label: String) -> void:
	var cd = _approach_dir(arena, boxes, box, spot, HOP_GAPS.max())
	if cd == Vector3.ZERO:
		return
	tested["hops"] += 1
	var got_on = false
	for speed in HOP_SPEEDS:
		for gap in HOP_GAPS:
			var r = _hop_attempt(arena, box, spot, cd, float(gap), float(speed))
			if bool(r["low"]):
				_fail(
					(
						"%s: a hop (%.1f m at %.1f m/s) was inside the box, lower than its top"
						% [label, gap, speed]
					)
				)
			if bool(r["stood"]):
				got_on = true
				if bool(r["bad_floor"]):
					_fail(
						(
							"%s: standing on the top, the floor is not the top (floor_h %.3f)"
							% [label, main.floor_h]
						)
					)
				if bool(r["hurdling"]):
					_fail(
						(
							"%s: standing on the top counts as hurdling: a rider would pass under the player"
							% label
						)
					)
				break
		if got_on:
			break
	if not got_on:
		_fail(
			(
				"%s: a hop at %s m/s from %s m away never got the player on top of it"
				% [label, HOP_SPEEDS, HOP_GAPS]
			)
		)


# standing on the box: still, a hop from the top, and walking off
func _check_standing(arena, boxes: Array, box: Dictionary, spot: Vector3, label: String) -> void:
	var cd = _exit_dir(arena, boxes, spot)
	if cd == Vector3.ZERO:
		return
	var top = float(box["y1"])
	var old_arena = main.arena
	main.arena = arena
	_ground()
	main.player.position = spot
	main.jump_h = top
	main.floor_h = top
	for i in range(6):
		main.invuln = 1000.0
		main._process(DT)
	if main.player_sys.is_airborne() or absf(main.jump_h - top) > 0.002:
		_fail(
			(
				"%s: standing still on the top the player is airborne or at %.3f m (top %.3f)"
				% [label, main.jump_h, top]
			)
		)
	if absf(main.player.position.y - top) > 0.002:
		_fail(
			(
				"%s: the player node is at %.3f m on the top, not at %.3f"
				% [label, main.player.position.y, top]
			)
		)
	if main.player_sys.is_hurdling():
		_fail(
			(
				"%s: standing on the top counts as hurdling: a rider would pass under the player"
				% label
			)
		)
	# a hop from the top comes down on the top
	main.player_sys.request_jump()
	var apex = top
	var landed_on_top = false
	for i in range(90):
		main.invuln = 1000.0
		main._process(DT)
		apex = maxf(apex, main.jump_h)
		if i > 3 and not main.player_sys.is_airborne():
			landed_on_top = absf(main.jump_h - top) < 0.002 and absf(main.floor_h - top) < 0.002
			break
	if apex - top < 0.6 or apex - top > 1.1:
		_fail("%s: a hop from the top rose %.2f m, expected about 0.84 m" % [label, apex - top])
	if not landed_on_top:
		_fail(
			"%s: a hop from the top did not come down on the top (at %.3f m)" % [label, main.jump_h]
		)
	# walking off at walking pace ends on the ground, on free ground
	var off = false
	for i in range(120):
		main.pvel = cd * WALK
		main.invuln = 1000.0
		main._process(DT)
		if _gap(box, main.player.position) > 1.2 and not main.player_sys.is_airborne():
			off = true
			break
	var p: Vector3 = main.player.position
	if not off:
		_fail(
			(
				"%s: walking off the top never ended on the ground (at %s, %.3f m up)"
				% [label, p, main.jump_h]
			)
		)
	elif absf(main.jump_h) > 0.002 or main.floor_h != 0.0:
		_fail(
			(
				"%s: after walking off the top the player is at %.3f m, not on the ground"
				% [label, main.jump_h]
			)
		)
	elif main.clamp_walk(p).distance_to(p) > 0.01:
		_fail("%s: after walking off the top the player is not on free ground" % label)
	main.arena = old_arena
	_ground()
	tested["standing"] += 1


# a crate on top of another: from the lower crate's top (the feet at the stack's y0) the upper crate is still a wall
func _check_stack(arena, boxes: Array, box: Dictionary, label: String) -> void:
	var mid = Vector3(box["at"].x, 0.0, box["at"].y)
	var cd = _approach_dir(arena, boxes, box, mid, 2.0)
	if cd == Vector3.ZERO:
		return
	var y = float(box["y0"])
	var start = _start_toward(box, mid, cd, 2.0)
	start.y = y
	var end: Vector3 = arena.slide_walk(start, Vector3(mid.x, y, mid.z), "player")
	tested["stacks"] += 1
	if _gap(box, end) < KEEP - SLACK:
		_fail(
			(
				"%s: the feet at the lower crate's top got %.2f m from the crate on it (keeps %.2f m)"
				% [label, _gap(box, end), KEEP]
			)
		)
