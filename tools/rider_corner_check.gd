extends SceneTree
# Check that a rider never ends up inside a wall on a generated arena (README Milestone K, Gameplay on open
# ground: a rider in a narrow corridor used to ride at the slowest braking speed while it turned on the spot,
# crept into a building corner and could never ride out, or be shot, again). Run from the project folder:
#   godot --headless --path . --script res://tools/rider_corner_check.gd
# Optional argument after "--": how many generated arenas to try (default 8).
# On each arena it puts RIDERS riders (all four rider kinds) in the narrowest open ground (cells with a clearance
# of one or two), facing every which way, with the player somewhere they can only reach by a way round a wall,
# lets each ride for SECONDS and checks that
#   - a rider is never inside a wall while it is visible (not in a gate's tunnel), at any step
#   - a rider that is put inside a wall is back on free ground after one step (the rescue)
#   - the corner that caught a real run: on the arena of seed 9E378A43 a rider circles at the braking floor speed
#     in a one-cell corridor next to the building corner at (6, -6) while the player walks its circle round the
#     start; it must stay on free ground and ride on (replayed from a captured state)
#   - the riders do ride (a share of them travel a few metres), so a rider that simply stops cannot pass
# Exits with status 1 and prints the first problems.

const ArenaGenScript = preload("res://scripts/arena_gen.gd")
const GeneratedArenaScript = preload("res://scripts/arena_generated.gd")
const MAIN_SCENE = "res://main.tscn"
const RIDERS = 16  # per arena
const SECONDS = 12.0
const DT = 1.0 / 60.0
const NARROW = 2  # nav clearance (cells) at most: corridors one or two cells wide
const MIN_MOVING = 0.6  # the share of riders that must travel at least MOVE_M metres in SECONDS
const MOVE_M = 4.0

var problems = []
var main = null


func _initialize() -> void:
	var count = 8
	var args = OS.get_cmdline_user_args()
	if args.size() > 0:
		count = int(args[0])
	main = load(MAIN_SCENE).instantiate()
	root.add_child(main)
	for i in range(3):
		await process_frame
	seed(5)
	main.start_game()
	main.state = "check"  # nobody gets run over mid-check and a finished rider does not end the round
	main.hits.resize(2000)
	main.hits.fill(false)
	var riders = 0
	var inside = 0
	var moving = 0
	var arenas = 0
	for k in range(count):
		var layout = ArenaGenScript.generate((k * 2654435761 + 77) & 0xFFFFFFFF)
		if layout.is_empty():
			continue
		arenas += 1
		var r = _run_arena(layout, k)
		riders += r[0]
		inside += r[1]
		moving += r[2]
	_check_rescue()
	_check_corridor_corner()
	if arenas > 0 and riders > 0 and float(moving) / float(riders) < MIN_MOVING:
		_fail(
			(
				"only %d of %d riders travelled %.0f m in %.0f s (the check is not covering the riding)"
				% [moving, riders, MOVE_M, SECONDS]
			)
		)
	if problems.is_empty():
		print(
			(
				"rider_corner_check: %d arenas, %d riders in narrow ground, none inside a wall at any step (%d steps in a wall), %d travelled %.0f m or more"
				% [arenas, riders, inside, moving, MOVE_M]
			)
		)
		quit(0)
	else:
		print("rider_corner_check: %d problem(s)" % problems.size())
		for p in problems.slice(0, 12):
			print("  " + p)
		quit(1)


func _fail(text: String) -> void:
	problems.append(text)


# returns [riders, steps spent inside a wall, riders that travelled MOVE_M]
func _run_arena(layout: Dictionary, k: int) -> Array:
	var arena = GeneratedArenaScript.new(layout)
	main.arena = arena
	main.clear_riders()
	var rng = RandomNumberGenerator.new()
	rng.seed = 300 + k
	var n = int(layout["cells"])
	var cell = float(layout["cell"])
	var narrow = []
	for cz in range(n):
		for cx in range(n):
			var c = ArenaGenScript.nav_clearance(layout, cx, cz)
			if (
				c >= 1
				and c <= NARROW
				and (
					ArenaGenScript.surface_at(layout, _cx(cx, n, cell), _cx(cz, n, cell))
					!= "tunnel"
				)
			):
				narrow.append(Vector3(_cx(cx, n, cell), 0.0, _cx(cz, n, cell)))
	if narrow.size() < RIDERS:
		_fail("arena %d: only %d narrow cells" % [k, narrow.size()])
		return [0, 0, 0]
	var riders = []
	var starts = []
	for i in range(RIDERS):
		var r = main.rider_sys.spawn_rider(i % 3, 1)
		r["can_throw"] = false
		r["limit"] = 100000.0
		var p: Vector3 = narrow[rng.randi() % narrow.size()]
		r["pos"] = p
		r["yaw"] = rng.randf_range(-PI, PI)
		r["hidden"] = false
		r["entered"] = true
		r["pursuit"] = "chase"
		riders.append(r)
		starts.append(p)
	var inside = 0
	var tag = "arena %d: " % k
	for step in range(int(SECONDS / DT)):
		# the player stands on the far side of the arena from the riders' middle, so they have to find their way
		main.player.position = _player_spot(arena, step, rng)
		for r in riders:
			main.rider_sys.move_rider(r, DT)
			if not r["hidden"] and arena.rider_blocked(r["pos"]):
				inside += 1
				if inside <= 3:
					_fail(tag + "a rider is inside a wall at %s (step %d)" % [r["pos"], step])
	var moving = 0
	for i in range(riders.size()):
		var r = riders[i]
		if Vector2(r["pos"].x - starts[i].x, r["pos"].z - starts[i].z).length() >= MOVE_M:
			moving += 1
		r["model"]["root"].queue_free()
	main.riders.clear()
	return [riders.size(), inside, moving]


func _cx(c: int, n: int, cell: float) -> float:
	return (float(c) + 0.5 - float(n) / 2.0) * cell


# a walkable point for the player: it walks from spot to spot every few seconds, so the riders keep having to turn
func _player_spot(arena, step: int, rng: RandomNumberGenerator) -> Vector3:
	var half = float(arena.layout["cells"]) * float(arena.layout["cell"]) / 2.0
	var a = float(step / 240) * 2.4
	return arena.clamp_walk(Vector3(cos(a), 0.0, sin(a)) * half * 0.6, "player")


# a rider put inside a building is on free ground after one step
func _check_rescue() -> void:
	var layout = ArenaGenScript.generate(0x9E378A43)
	var arena = GeneratedArenaScript.new(layout)
	main.arena = arena
	main.clear_riders()
	# a point in the middle of a building (a building cell with a building cell on all four sides), found in
	# the layout so a change of the generator's styles does not move it out of the building
	var inside = Vector3.ZERO
	var rows: Array = layout["rows"]
	var cells = int(layout["cells"])
	var cell_m = float(layout["cell"])
	for cz in range(2, cells - 2):
		for cx in range(2, cells - 2):
			if (
				str(rows[cz])[cx] == "b"
				and str(rows[cz - 1])[cx] == "b"
				and str(rows[cz + 1])[cx] == "b"
				and str(rows[cz])[cx - 1] == "b"
				and str(rows[cz])[cx + 1] == "b"
			):
				inside = Vector3(_cx(cx, cells, cell_m), 0.0, _cx(cz, cells, cell_m))
				break
		if inside != Vector3.ZERO:
			break
	if arena.surface_at(inside) != "building":
		_fail("rescue: the test point is not in a building (the layout changed, move it)")
		return
	var r = main.rider_sys.spawn_rider(0, 1)
	r["can_throw"] = false
	r["limit"] = 100000.0
	r["pos"] = inside
	r["hidden"] = false
	r["entered"] = true
	r["pursuit"] = "chase"
	main.player.position = arena.start_position()
	main.rider_sys.move_rider(r, DT)
	if arena.rider_blocked(r["pos"]):
		_fail(
			(
				"rescue: a rider put inside a building is still in a wall after a step, at %s"
				% r["pos"]
			)
		)
	r["model"]["root"].queue_free()
	main.riders.clear()


# The state captured from a generated_run_check run that failed (seed 9E378A43, 30 s of play, frame 1011): a rider
# at (6.23, -6.51) heading yaw -2.75 in the one-cell grass corridor just north of the building block whose corner
# is at (6, -6), with the player on its 8 m circle round the start. The old rider rode on at 3 m/s while turning at
# 6 rad/s, which is a circle of half a metre, and crept into the corner within 15 frames.
func _check_corridor_corner() -> void:
	var layout = ArenaGenScript.generate(0x9E378A43)
	var arena = GeneratedArenaScript.new(layout)
	main.arena = arena
	main.clear_riders()
	var start = arena.start_position()
	var worst = 0
	for variant in range(9):
		var r = main.rider_sys.spawn_rider(0, 1)
		r["can_throw"] = false
		r["limit"] = 100000.0
		r["pos"] = Vector3(6.227, 0.0, -6.510) + Vector3(0.0, 0.0, 0.04 * float(variant - 4))
		r["yaw"] = -2.753 + 0.02 * float(variant - 4)
		r["hidden"] = false
		r["entered"] = true
		r["pursuit"] = "chase"
		r["avoid_side"] = 1.0
		var steps_inside = 0
		var travelled = 0.0
		var last: Vector3 = r["pos"]
		for step in range(360):
			var ang = float(1011 + step) * 0.012
			main.player.position = arena.clamp_walk(start + Vector3(cos(ang), 0.0, sin(ang)) * 8.0)
			main.rider_sys.move_rider(r, DT)
			travelled += Vector2(r["pos"].x - last.x, r["pos"].z - last.z).length()
			last = r["pos"]
			if arena.rider_blocked(r["pos"]):
				steps_inside += 1
		worst = maxi(worst, steps_inside)
		if steps_inside > 0:
			_fail(
				(
					"corner replay %d: the rider was inside a wall for %d of 360 steps (at %s)"
					% [variant, steps_inside, r["pos"]]
				)
			)
		if travelled < 3.0:
			_fail(
				(
					"corner replay %d: the rider only travelled %.1f m in 6 s (stuck)"
					% [variant, travelled]
				)
			)
		r["model"]["root"].queue_free()
	main.riders.clear()
