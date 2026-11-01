extends SceneTree
# Checks that the player slides along a building wall without rubber banding (the bug: "hugging" a wall threw the
# player out and pulled him back every frame). On a generated arena of every style it finds a straight stretch of
# building wall and walks into it, in both directions, at walk, run and dash speed, straight along, at 20 degrees
# and at 45 degrees into the wall:
#   - the player never ends inside a building,
#   - no frame steps backwards along the wall, and the speed along the wall is the wanted one (no drag),
#   - once at the wall the distance to it stays the same (a wobble of more than 2 cm fails),
#   - the same walk through the game's own player step (main._process) holds the same rules,
#   - a body that starts inside a wall (a knock-back) is still brought back onto free ground.
# The old clamp_walk walk is measured too and printed as a note, to show what the fix changed.
# Run from the project folder:
#   godot --headless --path . --script res://tools/wall_slide_check.gd
# or: python tools/run_checks.py wall_slide
# Exits with status 1 and prints the problems when a check fails.

const ArenaGenScript = preload("res://scripts/arena_gen.gd")
const GeneratedArena = preload("res://scripts/arena_generated.gd")

const DT = 1.0 / 60.0
const STYLES = ["plaza", "canyon", "market", "park", "bridge", "tunnel"]
const INTO_DIRS = [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]
const WALL_CELLS = 8  # a wall stretch must be this many cells long
const END_GAP = 1.0  # metres kept clear at each end of the stretch, away from its corners
const START_GAP = 0.6  # metres from the wall's face where a walk starts (the player stops 0.45 m from it)
const WALK_MAX = 16.0  # metres walked along a wall at most (the border walls are 134 m, which would only slow the check)
const SETTLE_FRAMES = 30  # frames to reach the wall before the wobble is measured
const WOBBLE_MAX = 0.02  # metres the distance to the wall may change once the player is at it
const SPEED_MIN = 0.95  # share of the wanted speed along the wall that must be kept
const SPEEDS = {"walk": 3.2, "run": 5.8, "dash": 15.0}
const ANGLES = [0.0, 20.0, 45.0]  # degrees into the wall; 0 is straight along it (the wall is only touched by 20 and 45)

var problems = []
var notes = []
var main


func _initialize() -> void:
	var rules = ArenaGenScript.load_rules()
	if rules.is_empty():
		_fail("data/arena_rules.json could not be read")
		_finish()
		return
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	for i in range(3):
		await process_frame
	main.start_game(false, 0x1234ABCD)
	main.equip_primary("dart_gun")
	if main.state == "map":
		main.pick_node(0)
	main.force_captured = true  # headless Godot cannot capture the mouse, so the test hook plays the round
	await process_frame

	var walls_tested = 0
	var old_note_done = false
	for style in STYLES:
		var arena = _arena_for_style(rules, style)
		if arena == null:
			continue
		var found = _find_walls(arena)
		if found.is_empty():
			_fail("%s: no straight wall of %d cells was found to walk along" % [style, WALL_CELLS])
		for wall in found:
			walls_tested += 1
			_check_wall(arena, style, wall)
			if not old_note_done:
				_note_old_walk(arena, wall)
				old_note_done = true
		_check_in_game(arena, style, found)
	if walls_tested == 0:
		_fail("no generated arena with a straight wall was found")
	_check_inside_wall()
	_finish()


# the first generated arena of this style among a few hundred seeds, or null
func _arena_for_style(rules: Dictionary, style: String):
	for sd in range(5000, 5400):
		var layout = ArenaGenScript.generate(sd, rules)
		if not layout.is_empty() and str(layout.get("style", "")) == style:
			return GeneratedArena.new(layout, rules)
	return null


# true if the grid cell is ground to stand on (inside the grid, and not a building or a tunnel block)
func _free_cell(layout: Dictionary, cx: int, cz: int) -> bool:
	var n = int(layout["cells"])
	if cx < 0 or cz < 0 or cx >= n or cz >= n:
		return false
	var kind = str(layout["rows"][cz])[cx]
	return kind != "b" and kind != "t"


# One straight wall for each of the four directions the wall can be in (if the layout has one): a run of
# WALL_CELLS free cells whose neighbour on the wall side is solid all along. Each is a dictionary:
#   "start": the first point of the run, START_GAP from the wall's face and END_GAP from the run's end
#   "along": the unit vector along the wall, "into": the unit vector from the player into the wall
#   "length": the metres that are walked along the wall (the run's length less its ends, at most WALK_MAX)
func _find_walls(arena) -> Array:
	var layout = arena.layout
	var n = int(layout["cells"])
	var cell = float(layout["cell"])
	var found = []
	for into in INTO_DIRS:
		var along = Vector2i(1, 0) if into.x == 0 else Vector2i(0, 1)
		var wall = {}
		for cz in range(n):
			for cx in range(n):
				var count = 0
				while (
					_free_cell(layout, cx + along.x * count, cz + along.y * count)
					and not _free_cell(
						layout, cx + along.x * count + into.x, cz + along.y * count + into.y
					)
				):
					count += 1
				if count >= WALL_CELLS:
					var centre = Vector3(
						(float(cx) - float(n) / 2.0 + 0.5) * cell,
						0.0,
						(float(cz) - float(n) / 2.0 + 0.5) * cell
					)
					var along3 = Vector3(float(along.x), 0.0, float(along.y))
					var into3 = Vector3(float(into.x), 0.0, float(into.y))
					# the wall's face at the start of the run, then back from it and in along the run
					var face = centre - along3 * (cell / 2.0) + into3 * (cell / 2.0)
					wall = {
						"start": face - into3 * START_GAP + along3 * END_GAP,
						"along": along3,
						"into": into3,
						"length": minf(float(count) * cell - 2.0 * END_GAP, WALK_MAX),
					}
					break
			if not wall.is_empty():
				break
		if not wall.is_empty():
			found.append(wall)
	return found


# walk into one wall with every speed and angle, both ways along it, and judge each walk
func _check_wall(arena, style: String, wall: Dictionary) -> void:
	for speed_name in SPEEDS:
		for angle in ANGLES:
			for sign_along in [1.0, -1.0]:
				var along: Vector3 = wall["along"] * sign_along
				var start: Vector3 = wall["start"]
				if sign_along < 0.0:
					start = wall["start"] + wall["along"] * float(wall["length"])
				var speed = float(SPEEDS[speed_name])
				var vel = (
					along * speed * cos(deg_to_rad(angle))
					+ wall["into"] * speed * sin(deg_to_rad(angle))
				)
				var frames = int(float(wall["length"]) / (speed * cos(deg_to_rad(angle)) * DT)) - 2
				var points = [start]
				var p = start
				for i in range(frames):
					p = arena.slide_walk(p, p + vel * DT)
					points.append(p)
				var label = (
					"%s wall %s, %s at %d deg, along %s"
					% [style, wall["into"], speed_name, int(angle), along]
				)
				_judge(
					arena,
					points,
					along,
					wall["into"],
					speed * cos(deg_to_rad(angle)),
					angle > 0.0,
					label,
					1.0
				)


# the rules every walk must keep; `expect` is the share of the wanted speed along the wall that is wanted (below 1 for the
# game's own step, which slows the velocity a little before it is used)
func _judge(
	arena,
	points: Array,
	along: Vector3,
	into: Vector3,
	along_speed: float,
	touches: bool,
	label: String,
	expect: float
) -> void:
	var inside = 0
	var backwards = 0
	var slow = 0
	var perp_min = INF
	var perp_max = -INF
	for i in range(points.size()):
		var p: Vector3 = points[i]
		if arena.obstacle_at(p) or arena.clamp_walk(p).distance_to(p) > 0.01:
			inside += 1
		if i == 0:
			continue
		var step = (p - points[i - 1]).dot(along)
		if step < -0.001:
			backwards += 1
		if i >= SETTLE_FRAMES:
			if step < along_speed * DT * expect * SPEED_MIN:
				slow += 1
			var perp = p.dot(into)
			perp_min = minf(perp_min, perp)
			perp_max = maxf(perp_max, perp)
	if inside > 0:
		_fail("%s: %d frames ended inside a wall" % [label, inside])
	if backwards > 0:
		_fail("%s: %d frames stepped backwards along the wall" % [label, backwards])
	if slow > 0:
		_fail(
			(
				"%s: %d frames were slower than %d%% of the wanted speed along the wall"
				% [label, slow, int(SPEED_MIN * 100.0)]
			)
		)
	if touches and perp_max - perp_min > WOBBLE_MAX:
		_fail(
			(
				"%s: the distance to the wall changed by %.1f cm"
				% [label, (perp_max - perp_min) * 100.0]
			)
		)


# The same walk through the game's own player step: the player node is put at the wall of the arena and `pvel` is set
# every frame (update_player slows it a little, towards no input, before it is used).
func _check_in_game(arena, style: String, found: Array) -> void:
	var old_arena = main.arena
	for wall in found:
		for angle in [20.0, 45.0]:
			_ground()
			main.arena = arena
			var along: Vector3 = wall["along"]
			var speed = SPEEDS["run"]
			var vel = (
				along * speed * cos(deg_to_rad(angle))
				+ wall["into"] * speed * sin(deg_to_rad(angle))
			)
			main.player.position = wall["start"]
			var points = [main.player.position]
			# update_player keeps about 0.83 of the speed that is set, so the walk is long enough for 0.9 of it
			var frames = (
				int(float(wall["length"]) / (speed * 0.9 * cos(deg_to_rad(angle)) * DT)) - 2
			)
			for i in range(frames):
				main.pvel = vel
				main.invuln = 1000.0
				main._process(DT)
				points.append(main.player.position)
			var label = "in game, %s wall %s, run at %d deg" % [style, wall["into"], int(angle)]
			_judge(
				arena, points, along, wall["into"], speed * cos(deg_to_rad(angle)), true, label, 0.5
			)
	main.arena = old_arena
	_ground()


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


# a note with what the old walk (clamp_walk on the new point, every frame) did on the same wall, for the record
func _note_old_walk(arena, wall: Dictionary) -> void:
	var speed = SPEEDS["run"]
	var vel = wall["along"] * speed * 0.7071 + wall["into"] * speed * 0.7071
	var p: Vector3 = wall["start"]
	var backwards = 0
	var perp_min = INF
	var perp_max = -INF
	var total = 0.0
	var frames = int(float(wall["length"]) / (speed * 0.7071 * DT)) - 2
	for i in range(frames):
		var q = arena.clamp_walk(p + vel * DT)
		var step = (q - p).dot(wall["along"])
		if step < -0.001:
			backwards += 1
		if i >= SETTLE_FRAMES:
			var perp = q.dot(wall["into"])
			perp_min = minf(perp_min, perp)
			perp_max = maxf(perp_max, perp)
			total += step
		p = q
	var seconds = float(frames - SETTLE_FRAMES) * DT
	(
		notes
		. append(
			(
				"the old clamp_walk walk, running at 45 degrees into a wall: %.1f cm of wobble, %d frames backwards, %.1f of %.1f m/s along the wall"
				% [(perp_max - perp_min) * 100.0, backwards, total / seconds, speed * 0.7071]
			)
		)
	)


# a body that starts inside a wall (a knock-back, a spawn) is still brought back onto free ground by slide_walk
func _check_inside_wall() -> void:
	var rules = ArenaGenScript.load_rules()
	var arena = _arena_for_style(rules, "plaza")
	if arena == null:
		arena = _arena_for_style(rules, STYLES[1])
	if arena == null:
		return
	var layout = arena.layout
	var n = int(layout["cells"])
	var cell = float(layout["cell"])
	var cz = n >> 1
	for cx in range(n):
		if str(layout["rows"][cz])[cx] != "b":
			continue
		var inside = Vector3(
			(float(cx) - float(n) / 2.0 + 0.5) * cell,
			0.0,
			(float(cz) - float(n) / 2.0 + 0.5) * cell
		)
		var out = arena.slide_walk(inside, inside + Vector3(0.1, 0.0, 0.0))
		if arena.obstacle_at(out) or arena.clamp_walk(out).distance_to(out) > 0.01:
			_fail(
				(
					"a step that starts inside a building at %s was not brought back onto free ground"
					% inside
				)
			)
		return


func _finish() -> void:
	for n in notes:
		print("wall_slide_check: note: " + n)
	if problems.is_empty():
		print(
			"wall_slide_check: walking along a wall is smooth at every speed and angle, in both directions, and through the player step"
		)
		quit(0)
	else:
		for line in problems.slice(0, 10):
			printerr("wall_slide_check: " + line)
		quit(1)


func _fail(text: String) -> void:
	problems.append(text)
