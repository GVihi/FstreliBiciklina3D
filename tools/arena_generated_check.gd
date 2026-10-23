extends SceneTree
# Check for the generated arena class (README Milestone K, "Generated arena class"). It reads layouts from
# ArenaGen and checks that the Arena queries agree with them, for many seeds. Each step of the class adds its
# checks here, and each is also broken on purpose to see that it fails.
#
# Run from the project folder:
#   godot --headless --path . --script res://tools/arena_generated_check.gd
# Optionally pass how many seeds to check after "--". Exits with status 1 and prints the first problems.

const ArenaGenScript = preload("res://scripts/arena_gen.gd")
const GeneratedArena = preload("res://scripts/arena_generated.gd")

var bad: Array = []
var seeds = 200


func _init() -> void:
	var args = OS.get_cmdline_user_args()
	if args.size() > 0:
		seeds = int(args[0])
	var rules = ArenaGenScript.load_rules()
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
		checked += 1
	if bad.size() > 0:
		print("arena_generated_check: %d problem(s)" % bad.size())
		for b in bad.slice(0, 12):
			print("  " + b)
		quit(1)
		return
	print("arena_generated_check: %d arenas agree with their layouts" % checked)
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
	var far = 0.0
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
				far = maxf(far, Vector2(q.x - p.x, q.z - p.z).length())
	if moved_free > 0:
		bad.append("arena %d: clamp_walk moved %d free points" % [tag, moved_free])
	if far > 25.0:
		bad.append("arena %d: clamp_walk threw a point %.1f m away" % [tag, far])
	# the start and a pickup spot are free for every kind
	for who in ["player", "boss", "pickup"]:
		if arena.clamp_walk(arena.start_position(), who) != arena.start_position():
			bad.append("arena %d: the start moved for %s" % [tag, who])
	# the player's ground is never smaller than a pickup's: what a pickup can land on, the player can reach
	if arena.MARGINS["pickup"] < arena.MARGINS["player"]:
		bad.append("arena %d: pickups are kept less far from walls than the player" % tag)
