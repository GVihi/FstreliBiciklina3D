extends SceneTree
# Checks the run map generator (scripts/map_gen.gd) against the rules in data/map_rules.json.
# Run from the project folder:
#   godot --headless --path . --script res://tools/map_check.gd
# Optional arguments after "--": a seed to print as text, and how many seeds to check (default 2000), e.g.
#   godot --headless --path . --script res://tools/map_check.gd -- 3735928559 500
# Exits with status 1 and lists the first problems when a check fails.

const MapGen = preload("res://scripts/map_gen.gd")

var problems = []


func _init() -> void:
	var show_seed = -1
	var count = 2000
	var args = OS.get_cmdline_user_args()
	if args.size() > 0:
		show_seed = int(args[0])
	if args.size() > 1:
		count = int(args[1])
	var rules = MapGen.load_rules()
	if rules.is_empty():
		quit(1)
		return
	if show_seed >= 0:
		print(MapGen.to_text(MapGen.generate(show_seed, rules)))
	for n in range(count):
		var seed_value = (n * 2654435761 + 12345) & 0xFFFFFFFF
		var map = MapGen.generate(seed_value, rules)
		var again = MapGen.generate(seed_value, rules)
		if JSON.stringify(map) != JSON.stringify(again):
			_fail(seed_value, "the same seed gave two different maps")
		_check_map(seed_value, map, rules)
		if problems.size() >= 20:
			break
	if problems.is_empty():
		print("map_check: %d seeds, all maps follow the rules and repeat exactly" % count)
		quit(0)
	else:
		for p in problems:
			printerr(p)
		quit(1)


func _fail(seed_value: int, text: String) -> void:
	problems.append("seed %08X: %s" % [seed_value, text])


func _check_map(seed_value: int, map: Dictionary, rules: Dictionary) -> void:
	if map.is_empty():
		_fail(seed_value, "no map was generated")
		return
	var floors = map["floors"]
	var n = int(rules["floors"])
	var fixed = rules["fixed_floors"]
	var max_out = int(rules["max_edges_out"])
	var restricted = rules["no_repeat_along_edge"]
	if floors.size() != n:
		_fail(seed_value, "expected %d floors, got %d" % [n, floors.size()])
		return
	var counts = {}
	for f in range(n):
		var nodes = floors[f]
		var spec = fixed.get(str(f + 1))
		var wmin = int(rules["width"]["min"])
		var wmax = int(rules["width"]["max"])
		if spec != null:
			wmin = int(spec.get("width", spec.get("width_min", wmin)))
			wmax = int(spec.get("width", spec.get("width_max", wmax)))
		if nodes.size() < wmin or nodes.size() > wmax:
			_fail(seed_value, "floor %d has %d nodes" % [f + 1, nodes.size()])
		var seen_types = {}
		var incoming = []
		incoming.resize(nodes.size() if f == 0 else floors[f].size())
		for i in range(nodes.size()):
			var node = nodes[i]
			var t = node["type"]
			counts[t] = int(counts.get(t, 0)) + 1
			seen_types[t] = true
			if not rules["types"].has(t) and t != "boss":
				_fail(seed_value, "floor %d lane %d has unknown type '%s'" % [f + 1, i, t])
			if spec != null and not spec["types"].has(t):
				_fail(seed_value, "floor %d lane %d is '%s', not allowed there" % [f + 1, i, t])
			if spec == null and f + 1 < int(rules["types"][t]["min_floor"]):
				_fail(seed_value, "floor %d has '%s' before its first floor" % [f + 1, t])
			var nexts = node["next"]
			if f == n - 1:
				if nexts.size() != 0:
					_fail(seed_value, "the final boss has edges")
				continue
			var next_floor = floors[f + 1]
			if nexts.size() < 1:
				_fail(seed_value, "floor %d lane %d is a dead end" % [f + 1, i])
			if nodes.size() > 1 and nexts.size() > max_out:
				_fail(seed_value, "floor %d lane %d has %d edges" % [f + 1, i, nexts.size()])
			for k in range(nexts.size()):
				var j = int(nexts[k])
				if j < 0 or j >= next_floor.size():
					_fail(
						seed_value, "floor %d lane %d points outside floor %d" % [f + 1, i, f + 2]
					)
					continue
				if k > 0 and j <= int(nexts[k - 1]):
					_fail(seed_value, "floor %d lane %d edges are not in order" % [f + 1, i])
				if restricted.has(t) and next_floor[j]["type"] == t:
					_fail(
						seed_value, "floor %d lane %d and its child are both '%s'" % [f + 1, i, t]
					)
		if spec != null and spec.get("need_each", false) and nodes.size() >= spec["types"].size():
			for t in spec["types"]:
				if not seen_types.has(t):
					_fail(seed_value, "prep floor %d has no '%s'" % [f + 1, t])
		if f < n - 1:
			_check_links(seed_value, f, floors)
	for t in rules["types"]:
		var cap = rules["types"][t].get("max_per_map")
		if cap != null and int(counts.get(t, 0)) > int(cap):
			_fail(seed_value, "%d '%s' nodes, the most allowed is %d" % [counts[t], t, int(cap)])
	if int(counts.get("boss", 0)) != 2:
		_fail(seed_value, "expected exactly 2 boss nodes")


# every node on the next floor has a parent, and no two edges cross
func _check_links(seed_value: int, f: int, floors: Array) -> void:
	var has_parent = []
	has_parent.resize(floors[f + 1].size())
	has_parent.fill(false)
	var last_j = -1
	for i in range(floors[f].size()):
		for j in floors[f][i]["next"]:
			has_parent[j] = true
			if j < last_j:
				_fail(seed_value, "edges cross between floor %d and %d" % [f + 1, f + 2])
			last_j = j
	for j in range(has_parent.size()):
		if not has_parent[j]:
			_fail(seed_value, "floor %d lane %d has no way in" % [f + 2, j])
