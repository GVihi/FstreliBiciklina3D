extends SceneTree
# Check for the generated arena class (README Milestone K, "Generated arena class"). It reads layouts from
# ArenaGen and checks that the Arena queries agree with them, for many seeds. Each step of the class adds its
# checks here, and each is also broken on purpose to see that it fails.
#
# Run from the project folder:
#   godot --headless --path . --script res://tools/arena_generated_check.gd
# Optionally pass how many seeds to check after "--" (default 30; tools/run_checks.py --full passes 200, which takes
# about 20 minutes because an arena takes about 6 s to check). Prints its progress every 5 arenas. Exits with status 1
# and prints the first problems.

const ArenaGenScript = preload("res://scripts/arena_gen.gd")
const GeneratedArena = preload("res://scripts/arena_generated.gd")

var bad: Array = []
var seeds = 30
var full_cheer = 0  # arenas with a spot for all six cheerleaders


func _init() -> void:
	var args = OS.get_cmdline_user_args()
	if args.size() > 0:
		seeds = int(args[0])
	var rules = ArenaGenScript.load_rules()
	_check_interface_covered()
	var checked = 0
	for i in range(seeds):
		var layout = ArenaGenScript.generate(1000 + i * 7919, rules)
		if layout.is_empty():
			bad.append("seed %d gave no layout" % (1000 + i * 7919))
			continue
		var arena = GeneratedArena.new(layout, rules)
		_check_ground(arena, layout, rules, i)
		_check_start_and_gates(arena, layout, i)
		_check_blocking(arena, layout, i)
		_check_clamp(arena, layout, i)
		_check_stubs(arena, layout, i)
		_check_cheer_spots(arena, layout, i)
		checked += 1
		if checked % 5 == 0 or checked == seeds:
			print("arena_generated_check: %d of %d arenas checked" % [checked, seeds])
	if bad.size() > 0:
		print("arena_generated_check: %d problem(s)" % bad.size())
		for b in bad.slice(0, 12):
			print("  " + b)
		quit(1)
		return
	print(
		(
			"arena_generated_check: %d arenas agree with their layouts (%d of them have all six cheerleader spots)"
			% [checked, full_cheer]
		)
	)
	quit(0)


# surface_at and rider_speed_at match the layout at every cell centre
func _check_ground(arena, layout: Dictionary, rules: Dictionary, tag: int) -> void:
	var n = int(layout["cells"])
	var cell = float(layout["cell"])
	for cz in range(n):
		for cx in range(n):
			var p = Vector3(
				(float(cx) + 0.5 - float(n) / 2.0) * cell,
				0.0,
				(float(cz) + 0.5 - float(n) / 2.0) * cell
			)
			var want = ArenaGenScript.LEGEND[str(layout["rows"][cz])[cx]]
			if arena.surface_at(p) != want:
				bad.append(
					(
						"arena %d: surface at cell (%d, %d) is %s, the layout says %s"
						% [tag, cx, cz, arena.surface_at(p), want]
					)
				)
				return
			var share = float(rules["rider_speed"].get(want, 0.0))
			if absf(arena.rider_speed_at(p) - share) > 0.0001:
				bad.append(
					(
						"arena %d: rider speed at cell (%d, %d) is %.2f, the table says %.2f"
						% [tag, cx, cz, arena.rider_speed_at(p), share]
					)
				)
				return
	if not arena.rider_pursuit() or not arena.rider_avoidance():
		bad.append("arena %d: a generated arena must say riders pursue and avoid" % tag)


# the start is where the layout puts it, on plaza, and the gates are the layout's gates in world space
func _check_start_and_gates(arena, layout: Dictionary, tag: int) -> void:
	var s = arena.start_position()
	var want = layout["start"]["pos"]
	if absf(s.x - float(want[0])) > 0.0001 or absf(s.z - float(want[1])) > 0.0001 or s.y != 0.0:
		bad.append("arena %d: the start is at %s, the layout says %s" % [tag, s, want])
	if arena.surface_at(s) != "plaza":
		bad.append("arena %d: the start is on %s, not plaza" % [tag, arena.surface_at(s)])
	var gates = arena.gates()
	if gates.size() != layout["gates"].size() or gates.size() < 2:
		bad.append(
			"arena %d: %d gates, the layout has %d" % [tag, gates.size(), layout["gates"].size()]
		)
		return
	for i in range(gates.size()):
		var lg = layout["gates"][i]
		var g = gates[i]
		if (
			absf(g["pos"].x - float(lg["pos"][0])) > 0.0001
			or absf(g["pos"].z - float(lg["pos"][1])) > 0.0001
		):
			bad.append("arena %d: gate %d is not where the layout puts it" % [tag, i])
		if absf(g["outward"].length() - 1.0) > 0.001 or absf(g["outward"].y) > 0.0001:
			bad.append("arena %d: gate %d outward is not a flat unit vector" % [tag, i])
		if arena.surface_at(g["pos"]) != "tunnel":
			bad.append("arena %d: gate %d is not on a tunnel cell" % [tag, i])
		# the opening faces away from the middle: outward points the way from the centre to the gate
		if g["pos"].dot(g["outward"]) <= 0.0:
			bad.append("arena %d: gate %d points into the arena" % [tag, i])


# obstacle_at, ray_blocked, hidden_at and rider_blocked agree with the layout cell by cell and at the gates
func _check_blocking(arena, layout: Dictionary, tag: int) -> void:
	var n = int(layout["cells"])
	var cell = float(layout["cell"])
	var half = float(n) * cell / 2.0
	var open_cells = 0
	for cz in range(n):
		for cx in range(n):
			var p = Vector3(
				(float(cx) + 0.5 - float(n) / 2.0) * cell,
				1.0,
				(float(cz) + 0.5 - float(n) / 2.0) * cell
			)
			var c = str(layout["rows"][cz])[cx]
			var solid = c == "b" or c == "t"
			if arena.obstacle_at(p) != solid:
				bad.append(
					"arena %d: obstacle_at is wrong in cell (%d, %d) which is %s" % [tag, cx, cz, c]
				)
				return
			if arena.ray_blocked(p) != solid:
				bad.append(
					"arena %d: ray_blocked is wrong in cell (%d, %d) which is %s" % [tag, cx, cz, c]
				)
				return
			if arena.ray_blocked(p + Vector3(0.0, 10.0, 0.0)):
				bad.append(
					"arena %d: a dart over the roofs was stopped in cell (%d, %d)" % [tag, cx, cz]
				)
				return
			if arena.hidden_at(p) != (c == "t"):
				bad.append(
					"arena %d: hidden_at is wrong in cell (%d, %d) which is %s" % [tag, cx, cz, c]
				)
				return
			if arena.rider_blocked(p) != (c == "b"):
				bad.append(
					(
						"arena %d: rider_blocked is wrong in cell (%d, %d) which is %s"
						% [tag, cx, cz, c]
					)
				)
				return
			if not solid:
				open_cells += 1
	if arena.obstacle_at(Vector3(half + 5.0, 0.0, 0.0)) == false:
		bad.append("arena %d: outside the arena is not an obstacle" % tag)
	# the way through a gate: a rider can ride in from outside to the inner mouth, and is hidden until it is out
	for gate in arena.gates():
		for d in [-1.0, 0.5, 2.0, 3.5, 6.0]:
			var p = gate["pos"] + gate["outward"] * d
			if arena.rider_blocked(p) and (d < 0.0 or _outside(arena, p)):
				bad.append(
					(
						"arena %d: a rider is blocked %.1f m along a gate (the way is not open)"
						% [tag, d]
					)
				)
				return
		var mouth = gate["pos"] - gate["outward"] * 4.0
		if arena.hidden_at(mouth):
			bad.append("arena %d: a gate's inner mouth is still hidden" % tag)
		if not arena.hidden_at(gate["pos"] + gate["outward"] * 5.0):
			bad.append("arena %d: outside a gate's opening is not hidden" % tag)
		# beside the opening is wall: blocked and not hidden
		var side = Vector3(-gate["outward"].z, 0.0, gate["outward"].x)
		var wall = gate["pos"] + gate["outward"] * 5.0 + side * (gate["half_width"] + 2.0)
		if not arena.rider_blocked(wall) or arena.hidden_at(wall):
			bad.append("arena %d: beside a gate's opening is not blocked wall" % tag)


func _outside(arena, p: Vector3) -> bool:
	var half = float(arena.layout["cells"]) * float(arena.layout["cell"]) / 2.0
	return absf(p.x) >= half or absf(p.z) >= half


# clamp_walk leaves free points alone and brings points in walls back to free ground close by
func _check_clamp(arena, layout: Dictionary, tag: int) -> void:
	var cell = float(layout["cell"])
	var half = float(layout["cells"]) * cell / 2.0
	var rng = RandomNumberGenerator.new()
	rng.seed = 4242 + tag
	var moved_free = 0
	var fixed = 0
	var far_cases = []  # [point, answer, who] where the answer is over 25 m from the point
	for k in range(300):
		var p = Vector3(
			rng.randf_range(-half - 2.0, half + 2.0), 0.0, rng.randf_range(-half - 2.0, half + 2.0)
		)
		for who in ["player", "boss", "pickup"]:
			var q = arena.clamp_walk(p, who)
			var margin = float(arena.MARGINS[who])
			if not arena._clear(q, margin):
				bad.append(
					(
						"arena %d: clamp_walk (%s) left a point in or against a wall at %s"
						% [tag, who, q]
					)
				)
				return
			if arena._clear(p, margin):
				if q != p:
					moved_free += 1
			else:
				fixed += 1
				if Vector2(q.x - p.x, q.z - p.z).length() > 25.0:
					far_cases.append([p, q, who])
	if moved_free > 0:
		bad.append("arena %d: clamp_walk moved %d free points" % [tag, moved_free])
	# A point deep inside walls (the bridge and the tunnel have walls dozens of metres thick) may really be far
	# from free ground, so a long throw is held to the nearest free cell centre (found by brute force) plus one
	# search step and one cell, not to a fixed distance.
	for c in far_cases.slice(0, 12):
		var margin = float(arena.MARGINS[c[2]])
		var nearest = INF
		for cz in range(int(layout["cells"])):
			for cx in range(int(layout["cells"])):
				var centre = Vector3(
					(float(cx) + 0.5 - float(layout["cells"]) / 2.0) * cell,
					0.0,
					(float(cz) + 0.5 - float(layout["cells"]) / 2.0) * cell
				)
				if arena._clear(centre, margin):
					nearest = minf(nearest, Vector2(centre.x - c[0].x, centre.z - c[0].z).length())
		var thrown = Vector2(c[1].x - c[0].x, c[1].z - c[0].z).length()
		if thrown > nearest + float(arena.SLIDE_COARSE_STEP) + cell:
			bad.append(
				(
					"arena %d: clamp_walk threw a point %.1f m away, free ground is %.1f m away"
					% [tag, thrown, nearest]
				)
			)
	# the start and a pickup spot are free for every kind
	for who in ["player", "boss", "pickup"]:
		if arena.clamp_walk(arena.start_position(), who) != arena.start_position():
			bad.append("arena %d: the start moved for %s" % [tag, who])
	# the player's ground is never smaller than a pickup's: what a pickup can land on, the player can reach
	if arena.MARGINS["pickup"] < arena.MARGINS["player"]:
		bad.append("arena %d: pickups are kept less far from walls than the player" % tag)


# the function names declared in a script file, read from its source
func _declared_functions(path: String) -> Array:
	var names = []
	var f = FileAccess.open(path, FileAccess.READ)
	if f == null:
		bad.append("cannot read %s" % path)
		return names
	var re = RegEx.new()
	re.compile("(?m)^func\\s+([A-Za-z_][A-Za-z0-9_]*)")
	for m in re.search_all(f.get_as_text()):
		names.append(m.get_string(1))
	return names


# once, not per arena: the class answers every Arena function itself (the base class only complains), and has
# every name the game scripts read from `arena`, so code that has not moved to world positions cannot fail on it
func _check_interface_covered() -> void:
	var own = _declared_functions("res://scripts/arena_generated.gd")
	for name in _declared_functions("res://scripts/arena.gd"):
		if not name.begins_with("_") and not own.has(name):
			bad.append(
				(
					"GeneratedArena does not override Arena.%s (the base class only logs an error)"
					% name
				)
			)
	var probe = GeneratedArena.new(ArenaGenScript.generate(1000, ArenaGenScript.load_rules()))
	var consts = probe.get_script().get_script_constant_map()
	var re = RegEx.new()
	re.compile("\\barena\\.([A-Za-z_][A-Za-z0-9_]*)")
	var dir = DirAccess.open("res://scripts")
	var used = {}
	for file in dir.get_files():
		# the roundabout's own builder (world.gd) and the roundabout itself are not what runs on a generated arena
		if not file.ends_with(".gd") or file in ["world.gd", "arena_roundabout.gd"]:
			continue
		var f = FileAccess.open("res://scripts/" + file, FileAccess.READ)
		for line in f.get_as_text().split("\n"):
			if line.strip_edges().begins_with("#"):
				continue
			for m in re.search_all(line):
				used[m.get_string(1)] = file
	for name in used:
		if name == "gd":  # "arena.gd" in a path or a comment
			continue
		if not probe.has_method(name) and not consts.has(name) and not _has_variable(probe, name):
			bad.append("%s reads arena.%s, which GeneratedArena does not have" % [used[name], name])


# true if the object has a member variable of this name (the check above looks for methods and constants too)
func _has_variable(obj: Object, name: String) -> bool:
	for prop in obj.get_property_list():
		if prop["name"] == name:
			return true
	return false


# the street-coordinate stubs give safe values: inside the arena, on ground a boss can stand on, never an error
func _check_stubs(arena, layout: Dictionary, tag: int) -> void:
	var half = float(layout["cells"]) * float(layout["cell"]) / 2.0
	var rng = RandomNumberGenerator.new()
	rng.seed = 777 + tag
	if not (
		arena.lim() > 0.0
		and arena.player_lim() > 0.0
		and arena.player_lim() < arena.lim()
		and arena.lim() < half
	):
		bad.append(
			(
				"arena %d: limits are wrong (lim %.1f, player_lim %.1f, half %.1f)"
				% [tag, arena.lim(), arena.player_lim(), half]
			)
		)
	for k in range(100):
		var x = rng.randf_range(-half * 1.5, half * 1.5)
		var z = rng.randf_range(-half * 1.5, half * 1.5)
		var y = rng.randf_range(0.0, 3.0)
		var w = arena.tw(x, z, y)
		if _outside(arena, w) or absf(w.y - y) > 0.0001:
			bad.append(
				(
					"arena %d: tw(%.1f, %.1f, %.1f) is %s, outside the arena or at the wrong height"
					% [tag, x, z, y, w]
				)
			)
			return
		var inside = absf(x) < half - 0.5 and absf(z) < half - 0.5
		var t = arena.to_track(w)
		if inside and (absf(t.x - x) > 0.0001 or absf(t.y - z) > 0.0001):
			bad.append("arena %d: to_track does not undo tw at (%.1f, %.1f): %s" % [tag, x, z, t])
			return
		# the frame: tangent and inward are flat, unit, square to each other, and inward x tangent points up
		var tan: Vector3 = arena.tangent(x)
		var inw: Vector3 = arena.inward(x)
		if (
			absf(tan.length() - 1.0) > 0.001
			or absf(inw.length() - 1.0) > 0.001
			or absf(tan.y) > 0.0001
			or absf(inw.y) > 0.0001
			or absf(tan.dot(inw)) > 0.001
		):
			bad.append(
				"arena %d: tangent %s and inward %s are not a flat unit frame" % [tag, tan, inw]
			)
			return
		# a model turned by yaw(x) faces along the tangent, as it does on the roundabout (yaw 0 faces +x there too)
		var facing = Vector3.RIGHT.rotated(Vector3.UP, arena.yaw(x))
		if (facing - tan).length() > 0.001:
			bad.append(
				(
					"arena %d: a model turned by yaw(%.1f) faces %s, not along the tangent %s"
					% [tag, x, facing, tan]
				)
			)
			return
		if arena.hidden(x) or absf(arena.scale_at(z) - 1.0) > 0.0001:
			bad.append(
				(
					"arena %d: hidden or scale_at is not the neutral value at (%.1f, %.1f)"
					% [tag, x, z]
				)
			)
			return
		# a point to steer at, and a point pulled back onto the road, are on ground a boss can stand on
		var p = Vector3(rng.randf_range(-half, half), 0.0, rng.randf_range(-half, half))
		for dir in [-1, 1]:
			var lp = arena.lane_point(p, dir, z, rng.randf_range(0.0, 8.0))
			if not arena._clear(lp, arena.MARGINS["boss"]):
				bad.append(
					"arena %d: lane_point gave %s, which is in or against a wall" % [tag, lp]
				)
				return
		var rp = arena.clamp_road(p)
		if not arena._clear(rp, arena.MARGINS["boss"]):
			bad.append("arena %d: clamp_road gave %s, which is in or against a wall" % [tag, rp])
			return
		# no facade circle: a ray from the start never leaves one, and the constant combat reads is there
		var d = Vector3(rng.randf_range(-1.0, 1.0), 0.0, rng.randf_range(-1.0, 1.0)).normalized()
		if arena.ray_exit_circle(arena.start_position(), d, arena.FACADE_RHO) > 0.0:
			bad.append("arena %d: ray_exit_circle reports a facade circle" % tag)
			return
		# the way out for a rider that gives up is the distance to the nearest gate
		var want = INF
		for g in arena.gates():
			want = minf(want, Vector2(g["pos"].x - p.x, g["pos"].z - p.z).length())
		var got = arena.exit_distance(p, 1)
		if got < 0.0 or absf(got - want) > 0.0001:
			bad.append(
				"arena %d: exit_distance is %.2f, the nearest gate is %.2f away" % [tag, got, want]
			)
			return


# the cheerleaders' spots: up to the number asked for, all different, each on a plaza cell with a metre of free ground
# round it, outside the clear start square and not far from the start, the same for the same layout, and the
# roundabout (the base class) leaves the choice to main.gd by giving none
func _check_cheer_spots(arena, layout: Dictionary, tag: int) -> void:
	var spots = arena.cheer_spots(6)
	if spots.size() > 6:
		bad.append("arena %d: %d cheerleader spots for 6 cheerleaders" % [tag, spots.size()])
	if spots.size() == 6:
		full_cheer += 1
	if spots.size() < 3:
		bad.append(
			(
				"arena %d: only %d cheerleader spots (the start plaza has room for more)"
				% [tag, spots.size()]
			)
		)
	if arena.cheer_spots(0).size() != 0:
		bad.append("arena %d: spots given for no cheerleaders" % tag)
	var again = GeneratedArena.new(layout, arena.rules).cheer_spots(6)
	if again != spots:
		bad.append("arena %d: the same layout gave different cheerleader spots" % tag)
	var start = arena.start_position()
	var clear_m = (float(layout["start"]["half"]) + 0.5) * float(layout["cell"])
	var seen = {}
	for p in spots:
		if seen.has(p):
			bad.append("arena %d: two cheerleaders on one spot %s" % [tag, p])
		seen[p] = true
		if arena.surface_at(p) != "plaza":
			bad.append(
				(
					"arena %d: a cheerleader spot %s is on %s, not plaza"
					% [tag, p, arena.surface_at(p)]
				)
			)
		if not arena._clear(p, arena.CHEER_ROOM):
			bad.append("arena %d: a cheerleader spot %s has no free ground round it" % [tag, p])
		var off = Vector2(absf(p.x - start.x), absf(p.z - start.z))
		if maxf(off.x, off.y) < clear_m:
			bad.append(
				"arena %d: a cheerleader spot %s is inside the clear start square" % [tag, p]
			)
		if maxf(off.x, off.y) > clear_m + 2.0 * float(layout["cell"]) + 0.01:
			bad.append("arena %d: a cheerleader spot %s is far from the start" % [tag, p])
