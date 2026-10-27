extends SceneTree
# Checks the run map generator (scripts/map_gen.gd) against the rules in data/map_rules.json.
# Run from the project folder:
#   godot --headless --path . --script res://tools/map_check.gd
# Optional arguments after "--": a seed to print as text, and how many seeds to check (default 2000), e.g.
#   godot --headless --path . --script res://tools/map_check.gd -- 3735928559 500
# Exits with status 1 and lists the first problems when a check fails.

const MapGen = preload("res://scripts/map_gen.gd")
const ArenaGen = preload("res://scripts/arena_gen.gd")
const Content = preload("res://scripts/content.gd")

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
		print(MapGen.to_text(MapGen.generate(show_seed, rules, _gates_for(show_seed))))
	var retried = 0
	for n in range(count):
		var seed_value = (n * 2654435761 + 12345) & 0xFFFFFFFF
		var map = MapGen.generate(seed_value, rules, _gates_for(seed_value))
		var again = MapGen.generate(seed_value, rules, _gates_for(seed_value))
		if JSON.stringify(map) != JSON.stringify(again):
			_fail(seed_value, "the same seed gave two different maps")
		_check_map(seed_value, map, rules)
		_check_content(seed_value, map, rules, _gates_for(seed_value))
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
	_check_content_streams(rules)
	_check_content_text(rules)
	if problems.is_empty():
		print(
			(
				"map_check: %d seeds, all maps follow the rules and repeat exactly (%d needed a retry)"
				% [count, retried]
			)
		)
		quit(0)
	else:
		for p in problems:
			printerr(p)
		quit(1)


# a gate count from 2 to 5 (what data/arena_rules.json allows), so the check does not build 2,000 arenas
func _gates_for(seed_value: int) -> int:
	return 2 + (seed_value % 4)


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
		# a type with weight 0 that no fixed floor names (the alpha map has no event nodes) is never drawn
		if int(rules["types"][t]["weight"]) <= 0 and int(counts.get(t, 0)) > 0:
			var on_fixed_floor = false
			for key in rules["fixed_floors"]:
				if rules["fixed_floors"][key]["types"].has(t):
					on_fixed_floor = true
			if not on_fixed_floor:
				_fail(seed_value, "%d '%s' nodes although its weight is 0" % [counts[t], t])
	if int(counts.get("boss", 0)) != 2:
		_fail(seed_value, "expected exactly 2 boss nodes")


# The encounter content of every node (scripts/map_content.gd), checked from the rules alone: the right keys for
# the node type, rider counts and mixes inside the rules and allowed on that floor, gates that exist, modifiers
# allowed on that floor, boss kinds and themes.
func _check_content(seed_value: int, map: Dictionary, rules: Dictionary, gates: int) -> void:
	var crules = rules.get("content", {})
	if map.is_empty() or crules.is_empty():
		return
	if int(map.get("gates", -1)) != gates:
		_fail(seed_value, "the map says %s gates, expected %d" % [map.get("gates"), gates])
	var floors = map["floors"]
	var fights = ["normal", "elite", "boss"]
	for f in range(floors.size()):
		for i in range(floors[f].size()):
			var node = floors[f][i]
			var where = "floor %d lane %d (%s)" % [f + 1, i, node["type"]]
			if not node.has("content"):
				_fail(seed_value, "%s has no content" % where)
				continue
			var c = node["content"]
			var t = node["type"]
			if int(c.get("theme", -1)) < 0 or int(c["theme"]) >= Content.THEMES.size():
				_fail(seed_value, "%s has theme %s" % [where, c.get("theme")])
			if not fights.has(t):
				if not c.has("seed") or c.has("riders") or c.has("gates") or c.has("boss"):
					_fail(seed_value, "%s should hold only a theme and a seed" % where)
				continue
			if c.has("seed"):
				_fail(seed_value, "%s is a fight but has a seed" % where)
			_check_riders(seed_value, where, f + 1, t, c.get("riders", {}), crules)
			_check_gates(seed_value, where, c.get("gates", []), gates, crules)
			_check_modifiers(seed_value, where, f + 1, t, c.get("modifiers", []), crules)
			_check_boss(seed_value, where, f + 1, t, c, crules)


func _check_riders(
	seed_value: int, where: String, floor_no: int, t: String, riders: Dictionary, crules: Dictionary
) -> void:
	var rr = crules["riders"]
	if not riders.has("count") or not riders.has("mix"):
		_fail(seed_value, "%s has no rider count or mix" % where)
		return
	var n = int(riders["count"])
	if n < int(rr["count"][t]["min"]) or n > int(rr["count"][t]["max"]):
		_fail(seed_value, "%s has %d riders" % [where, n])
	var sum = 0
	for kind in riders["mix"]:
		var amount = int(riders["mix"][kind])
		sum += amount
		if not Content.TYPES.has(kind):
			_fail(seed_value, "%s has rider type '%s'" % [where, kind])
		elif amount > 0 and floor_no < int(rr["min_floor"].get(kind, 1)):
			_fail(
				seed_value,
				"%s has %s riders before floor %s" % [where, kind, rr["min_floor"].get(kind)]
			)
		elif amount > 0 and int(rr["weights"][t].get(kind, 0)) <= 0:
			_fail(seed_value, "%s has %s riders with weight 0" % [where, kind])
	if sum != n:
		_fail(seed_value, "%s mix adds up to %d, not %d" % [where, sum, n])


func _check_gates(
	seed_value: int, where: String, open: Array, gates: int, crules: Dictionary
) -> void:
	var want_min = mini(int(crules["gates"]["min_open"]), gates)
	if open.size() < want_min or open.size() > gates:
		_fail(seed_value, "%s opens %d of %d gates" % [where, open.size(), gates])
	var last = -1
	for g in open:
		if int(g) <= last or int(g) >= gates:
			_fail(
				seed_value,
				"%s gate list %s is not sorted, unique and inside the layout" % [where, open]
			)
			return
		last = int(g)


func _check_modifiers(
	seed_value: int, where: String, floor_no: int, t: String, mods: Array, crules: Dictionary
) -> void:
	var mrules = crules["modifiers"]
	if mods.size() > 1:
		_fail(seed_value, "%s has %d modifiers" % [where, mods.size()])
	if mods.size() > 0 and float(mrules["chance"].get(t, 0.0)) <= 0.0:
		_fail(seed_value, "%s has a modifier but its type never gets one" % where)
	for m in mods:
		if not mrules["types"].has(m):
			_fail(seed_value, "%s has unknown modifier '%s'" % [where, m])
		elif int(mrules["types"][m]["weight"]) <= 0:
			_fail(seed_value, "%s has '%s' although its weight is 0" % [where, m])
		elif floor_no < int(mrules["types"][m]["min_floor"]):
			_fail(
				seed_value,
				"%s has '%s' before floor %s" % [where, m, mrules["types"][m]["min_floor"]]
			)


func _check_boss(
	seed_value: int, where: String, floor_no: int, t: String, c: Dictionary, crules: Dictionary
) -> void:
	if t != "boss":
		if c.has("boss") or c.has("final"):
			_fail(seed_value, "%s is not a boss but has boss content" % where)
		return
	var tag = "final" if floor_no == 10 else "mid"
	if (
		not crules["boss_kinds"][tag].has(c.get("boss", ""))
		or not Content.BOSS_KINDS.has(c.get("boss", ""))
	):
		_fail(seed_value, "%s has boss kind '%s'" % [where, c.get("boss")])
	if c.has("final") != (tag == "final"):
		_fail(seed_value, "%s final flag is wrong" % where)
	if int(c["theme"]) != int(crules["boss_theme"][tag]):
		_fail(seed_value, "%s has theme %s, expected the boss theme" % [where, c["theme"]])


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
	var good = MapGen.generate(1234, rules, _gates_for(1234))
	if not MapGen.validate(good, rules).is_empty():
		_fail(1234, "validate rejects a good map: %s" % [MapGen.validate(good, rules)])
		return
	var cases = {
		"a dead end": ["dead end", func(m): m["floors"][2][0]["next"] = []],
		"nodes nothing leads to": ["cannot be reached", func(m): _all_to_lane_zero(m, 1)],
		"an edge to a lane that is not there":
		["does not exist", func(m): m["floors"][0][0]["next"].append(99)],
		"crossing edges": ["cross", _cross_edges],
		"a missing floor": ["expected 10 floors", func(m): m["floors"].pop_back()],
		"no mid boss": ["boss floor", func(m): m["floors"][4][0]["type"] = "normal"],
		"a boss on a free floor": ["boss nodes", func(m): m["floors"][2][0]["type"] = "boss"],
		"a prep floor without a shop": ["no 'shop'", func(m): _set_floor_types(m, 3, "rest")],
		"too many elites": ["most allowed is 3", func(m): _set_floor_types(m, 5, "elite", 6)],
		"an elite before its first floor":
		["first floor", func(m): m["floors"][1][0]["type"] = "elite"],
		"two elites joined by an edge": ["both 'elite'", _repeat_along_edge],
		"edges out of the final boss": ["has edges", func(m): m["floors"][9][0]["next"] = [0]],
		"a node with no type": ["unknown type", func(m): m["floors"][5][0]["type"] = ""],
		"a fight with no open gate":
		["no open gate", func(m): m["floors"][0][0]["content"]["gates"] = []],
		"a gate the arena does not have":
		["opens gate", func(m): m["floors"][0][0]["content"]["gates"] = [99]],
		"a fight with no riders":
		["no riders", func(m): m["floors"][0][0]["content"]["riders"]["count"] = 0],
		"a rider mix that does not add up":
		["does not add up", func(m): m["floors"][0][0]["content"]["riders"]["count"] += 1],
		"a boss with no kind": ["no boss kind", func(m): m["floors"][4][0]["content"]["boss"] = ""],
		"a shop with no seed": ["no seed", func(m): _drop_seed(m)],
		"a node with no content": ["has no content", func(m): m["floors"][2][0].erase("content")],
	}
	for name in cases:
		var map = good.duplicate(true)
		cases[name][1].call(map)
		var found = false
		for p in MapGen.validate(map, rules):
			if str(p).contains(cases[name][0]):
				found = true
		if not found:
			_fail(
				1234,
				"validate did not name the problem for %s: %s" % [name, MapGen.validate(map, rules)]
			)
	# a rule damaged instead of a map: one edge per node is not enough for any branching map
	var tight = rules.duplicate(true)
	tight["max_edges_out"] = 1
	var branching = false
	for n in range(50):
		var map = MapGen.generate(n + 1, rules, _gates_for(n + 1))
		for p in MapGen.validate(map, tight):
			if str(p).contains("most allowed is 1"):
				branching = true
	if not branching:
		_fail(0, "validate never named a node with too many edges when the limit was one")
	if MapGen.validate({}, rules).is_empty():
		_fail(0, "validate accepts an empty map")


# removes the seed of the first node that has one (a shop, rest or event)
func _drop_seed(map: Dictionary) -> void:
	for floor_nodes in map["floors"]:
		for node in floor_nodes:
			if node["content"].has("seed"):
				node["content"].erase("seed")
				return


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
		var first = MapGen.generate(seed_value, rules, _gates_for(seed_value))
		var map = MapGen.generate(seed_value, forced, _gates_for(seed_value))
		var again = MapGen.generate(seed_value, forced, _gates_for(seed_value))
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
		_fail(
			0,
			(
				"retrying changed the map for only %d of 100 seeds, the derived seed is not being used"
				% differs
			)
		)
	var hopeless = rules.duplicate(true)
	hopeless["test_invalid_attempts"] = int(rules.get("max_attempts", 8))
	if not MapGen.generate(5, hopeless, _gates_for(5)).is_empty():
		_fail(5, "a map was returned although every attempt was invalid")


# The content must not change the map: the floors, edges and types are the same with and without the "content"
# rules. And with no gate count given, the map uses the gate count of the real arena layout of the same seed.
func _check_content_streams(rules: Dictionary) -> void:
	var plain = rules.duplicate(true)
	plain.erase("content")
	for n in range(40):
		var seed_value = n * 104729 + 17
		var with_content = MapGen.generate(seed_value, rules, _gates_for(seed_value))
		var without = MapGen.generate(seed_value, plain)
		if JSON.stringify(_shape(with_content)) != JSON.stringify(_shape(without)):
			_fail(seed_value, "adding the content changed the floors, edges or types")
		var layout = ArenaGen.generate(seed_value)
		var real = MapGen.generate(seed_value, rules)
		if layout.is_empty() or int(real.get("gates", -1)) != layout["gates"].size():
			_fail(seed_value, "the map's gate count is not the arena layout's gate count")


# the map without its "content" entries: types and edges only
func _shape(map: Dictionary) -> Array:
	var out = []
	for floor_nodes in map["floors"]:
		var row = []
		for node in floor_nodes:
			row.append([node["type"], node["next"]])
		out.append(row)
	return out


# content_text prints one line per node
func _check_content_text(rules: Dictionary) -> void:
	var map = MapGen.generate(99, rules, _gates_for(99))
	var nodes = 0
	for floor_nodes in map["floors"]:
		nodes += floor_nodes.size()
	var lines = MapGen.content_text(map).split("\n")
	if lines.size() != nodes:
		_fail(99, "content_text printed %d lines for %d nodes" % [lines.size(), nodes])
	if not lines[lines.size() - 1].contains("minister FINAL"):
		_fail(99, "content_text does not end with the final boss")
