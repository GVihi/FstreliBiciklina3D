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
	var retried = 0
	for n in range(count):
		var seed_value = (n * 2654435761 + 12345) & 0xFFFFFFFF
		var map = MapGen.generate(seed_value, rules)
		var again = MapGen.generate(seed_value, rules)
		if JSON.stringify(map) != JSON.stringify(again):
			_fail(seed_value, "the same seed gave two different maps")
		_check_map(seed_value, map, rules)
		if not map.is_empty():
			# the game's own validator must agree with the independent checks above
			for p in MapGen.validate(map, rules):
				_fail(seed_value, "MapGen.validate says: %s" % p)
			if int(map.get("attempt", -1)) > 0:
				retried += 1
		if problems.size() >= 20:
			break
	_check_validator(rules)
	_check_retry(rules)
	if problems.is_empty():
		print("map_check: %d seeds, all maps follow the rules and repeat exactly (%d needed a retry)" % [count, retried])
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


# ---------------------------------------------------------------- validator and retry
# Damages a good map in one way at a time and fails if MapGen.validate does not name the matching problem
# (a word that must appear in one of the problems). A map the damage leaves untouched would also fail.
func _check_validator(rules: Dictionary) -> void:
	var good = MapGen.generate(1234, rules)
	if not MapGen.validate(good, rules).is_empty():
		_fail(1234, "validate rejects a good map: %s" % [MapGen.validate(good, rules)])
		return
	var cases = {
		"a dead end": ["dead end", func(m): m["floors"][2][0]["next"] = []],
		"nodes nothing leads to": ["cannot be reached", func(m): _all_to_lane_zero(m, 1)],
		"an edge to a lane that is not there": ["does not exist", func(m): m["floors"][0][0]["next"].append(99)],
		"crossing edges": ["cross", _cross_edges],
		"a missing floor": ["expected 10 floors", func(m): m["floors"].pop_back()],
		"no mid boss": ["boss floor", func(m): m["floors"][4][0]["type"] = "normal"],
		"a boss on a free floor": ["boss nodes", func(m): m["floors"][2][0]["type"] = "boss"],
		"a prep floor without a shop": ["no 'shop'", func(m): _set_floor_types(m, 3, "rest")],
		"too many elites": ["most allowed is 3", func(m): _set_floor_types(m, 5, "elite", 6)],
		"an elite before its first floor": ["first floor", func(m): m["floors"][1][0]["type"] = "elite"],
		"two elites joined by an edge": ["both 'elite'", _repeat_along_edge],
		"edges out of the final boss": ["has edges", func(m): m["floors"][9][0]["next"] = [0]],
		"a node with no type": ["unknown type", func(m): m["floors"][5][0]["type"] = ""],
	}
	for name in cases:
		var map = good.duplicate(true)
		cases[name][1].call(map)
		var found = false
		for p in MapGen.validate(map, rules):
			if str(p).contains(cases[name][0]):
				found = true
		if not found:
			_fail(1234, "validate did not name the problem for %s: %s" % [name, MapGen.validate(map, rules)])
	# a rule damaged instead of a map: one edge per node is not enough for any branching map
	var tight = rules.duplicate(true)
	tight["max_edges_out"] = 1
	var branching = false
	for n in range(50):
		var map = MapGen.generate(n + 1, rules)
		for p in MapGen.validate(map, tight):
			if str(p).contains("most allowed is 1"):
				branching = true
	if not branching:
		_fail(0, "validate never named a node with too many edges when the limit was one")
	if MapGen.validate({}, rules).is_empty():
		_fail(0, "validate accepts an empty map")


func _all_to_lane_zero(map: Dictionary, floor_index: int) -> void:
	for node in map["floors"][floor_index]:
		node["next"] = [0]


func _set_floor_types(map: Dictionary, floor_index: int, type: String, to_floor: int = -1) -> void:
	for f in range(floor_index, maxi(floor_index + 1, to_floor)):
		for node in map["floors"][f]:
			node["type"] = type


func _cross_edges(map: Dictionary) -> void:
	map["floors"][0][0]["next"] = [1]
	map["floors"][0][1]["next"] = [0]


func _repeat_along_edge(map: Dictionary) -> void:
	var parent = map["floors"][5][0]
	parent["type"] = "elite"
	map["floors"][6][int(parent["next"][0])]["type"] = "elite"


# A map that fails validation is regenerated from a derived seed: forcing the first attempts to fail must give
# the next attempt, the same one every time, still valid; and when every attempt fails there is no map.
func _check_retry(rules: Dictionary) -> void:
	var forced = rules.duplicate(true)
	forced["test_invalid_attempts"] = 2
	var differs = 0
	for n in range(100):
		var seed_value = n * 7919 + 3
		var first = MapGen.generate(seed_value, rules)
		var map = MapGen.generate(seed_value, forced)
		var again = MapGen.generate(seed_value, forced)
		if map.is_empty():
			_fail(seed_value, "retry gave no map")
			continue
		if int(map.get("attempt", -1)) != 2:
			_fail(seed_value, "forced to skip two attempts but got attempt %s" % map.get("attempt"))
		if JSON.stringify(map) != JSON.stringify(again):
			_fail(seed_value, "a retried seed gave two different maps")
		for p in MapGen.validate(map, forced):
			_fail(seed_value, "retried map is not valid: %s" % p)
		if JSON.stringify(map["floors"]) != JSON.stringify(first["floors"]):
			differs += 1
	if differs < 90:
		_fail(0, "retrying changed the map for only %d of 100 seeds, the derived seed is not being used" % differs)
	var hopeless = rules.duplicate(true)
	hopeless["test_invalid_attempts"] = int(rules.get("max_attempts", 8))
	if not MapGen.generate(5, hopeless).is_empty():
		_fail(5, "a map was returned although every attempt was invalid")
