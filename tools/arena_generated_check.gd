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
