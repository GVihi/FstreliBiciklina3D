extends RefCounted
# Procedural run map (README Milestone G). One seed gives one map: generate() uses only the run seed and the
# numbers in data/map_rules.json, and draws from generators seeded by DailyScript.stream_seed, never from the
# global random functions. Rules and what they mean: docs/MAP_GENERATION.md.
#
# A map is {"seed": int, "floors": Array}. floors[0] is floor 1 (the start) and the last entry is the final boss.
# A floor is an Array of nodes in lane order (left to right); a node is {"type": String, "next": Array},
# where "next" lists the lane numbers of the nodes it connects to on the next floor.
# Node types: normal, elite, shop, event, rest, boss.

const DailyScript = preload("res://scripts/daily.gd")

const PATH = "res://data/map_rules.json"
const LETTERS = {"normal": "N", "elite": "E", "shop": "S", "event": "?", "rest": "R", "boss": "B"}


# Reads data/map_rules.json; returns {} (and logs why) when it is missing or unusable.
static func load_rules() -> Dictionary:
	if not FileAccess.file_exists(PATH):
		push_error("map: %s is missing. Check the export include filter (data/*.json)." % PATH)
		return {}
	var data = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if typeof(data) != TYPE_DICTIONARY:
		push_error("map: %s is not valid JSON, expected an object" % PATH)
		return {}
	for key in ["floors", "width", "fixed_floors", "types"]:
		if not data.has(key):
			push_error('map: %s has no "%s"' % [PATH, key])
			return {}
	return data


# Builds the map for a run seed. Pass `rules` to test other numbers; by default the shipped file is used.
# Returns {} (and logs why) when the rules cannot produce a map.
static func generate(run_seed: int, rules: Dictionary = {}) -> Dictionary:
	if rules.is_empty():
		rules = load_rules()
	if rules.is_empty():
		return {}
	var streams = rules.get("streams", {})
	var layout_rng = _rng(run_seed, str(streams.get("layout", "map_layout")))
	var types_rng = _rng(run_seed, str(streams.get("types", "map_types")))
	var n_floors = int(rules["floors"])
	var floors = []
	for f in range(1, n_floors + 1):
		var nodes = []
		for i in range(_floor_width(rules, f, layout_rng)):
			nodes.append({"type": "", "next": []})
		floors.append(nodes)
	var max_out = int(rules.get("max_edges_out", 2))
	for f in range(n_floors - 1):
		if not _connect(floors[f], floors[f + 1], max_out, layout_rng):
			push_error(
				(
					"map: floor %d (%d nodes) cannot connect to floor %d (%d nodes) with at most %d edges per node"
					% [f + 1, floors[f].size(), f + 2, floors[f + 1].size(), max_out]
				)
			)
			return {}
	_assign_types(floors, rules, types_rng)
	return {"seed": run_seed, "floors": floors}


# One line per floor, final boss first, e.g. "F03  N(0,1) S(1) ?(2)": the letter is the node type and the
# numbers are the lanes it connects to on the next floor. For the console and the debug preview.
static func to_text(map: Dictionary) -> String:
	if map.is_empty():
		return "(no map)"
	var lines = ["MAP SEED %s" % DailyScript.seed_text(int(map["seed"]))]
	var floors = map["floors"]
	for f in range(floors.size() - 1, -1, -1):
		var parts = []
		for node in floors[f]:
			var nexts = []
			for j in node["next"]:
				nexts.append(str(j))
			parts.append("%s(%s)" % [LETTERS.get(node["type"], "-"), ",".join(nexts)])
		lines.append("F%02d  %s" % [f + 1, " ".join(parts)])
	return "\n".join(lines)


# ---------------------------------------------------------------- internals
static func _rng(run_seed: int, part: String) -> RandomNumberGenerator:
	var rng = RandomNumberGenerator.new()
	rng.seed = DailyScript.stream_seed(run_seed, 0, part)
	return rng


# number of nodes on floor f (1-based): fixed on the fixed floors, otherwise drawn from the allowed range
static func _floor_width(rules: Dictionary, f: int, rng: RandomNumberGenerator) -> int:
	var fixed = rules["fixed_floors"].get(str(f))
	if fixed != null:
		if fixed.has("width"):
			return int(fixed["width"])
		return rng.randi_range(int(fixed["width_min"]), int(fixed["width_max"]))
	return rng.randi_range(int(rules["width"]["min"]), int(rules["width"]["max"]))


# Connects one floor to the next. The edges follow a staircase from the left-most nodes to the right-most
# ones (each step moves right on the lower floor, on the upper floor, or on both), so edges never cross, every
# node gets at least one edge on each side, and a node has at most `max_out` edges up. A lone node (a boss)
# connects to every node of the next floor. Returns false when the widths cannot be connected.
static func _connect(lower: Array, upper: Array, max_out: int, rng: RandomNumberGenerator) -> bool:
	var a = lower.size()
	var b = upper.size()
	if a == 1:
		for j in range(b):
			lower[0]["next"].append(j)
		return true
	if not _can_finish(a - 1, b - 1, 0, max_out):
		return false
	var i = 0
	var j = 0
	var up_used = 0  # extra edges already given to node i
	lower[0]["next"].append(0)
	while i < a - 1 or j < b - 1:
		var ri = a - 1 - i
		var rj = b - 1 - j
		var moves = []
		if ri > 0 and rj > 0 and _can_finish(ri - 1, rj - 1, 0, max_out):
			moves.append("both")
		if ri > 0 and _can_finish(ri - 1, rj, 0, max_out):
			moves.append("lower")
		if rj > 0 and up_used < max_out - 1 and _can_finish(ri, rj - 1, up_used + 1, max_out):
			moves.append("upper")
		if moves.is_empty():
			return false
		var move = moves[rng.randi() % moves.size()]
		if move == "upper":
			j += 1
			up_used += 1
		else:
			i += 1
			up_used = 0
			if move == "both":
				j += 1
		lower[i]["next"].append(j)
	return true


# Can the staircase still reach the last pair? `ri` and `rj` are the steps left on the lower and upper floor and
# `up_used` the extra edges the current lower node already has. Every step that moves only on the upper floor
# costs one extra edge, and each lower node can take `max_out - 1` of them.
static func _can_finish(ri: int, rj: int, up_used: int, max_out: int) -> bool:
	var needed = maxi(0, rj - ri)
	var available = ri * (max_out - 1) + (max_out - 1 - up_used)
	return needed <= available


# Gives every node a type: fixed floors first (they only hold the types listed for them), then the free floors
# floor by floor, left to right, by a weighted draw that respects first floor, per-map caps and the no-repeat rule.
static func _assign_types(floors: Array, rules: Dictionary, rng: RandomNumberGenerator) -> void:
	var fixed = rules["fixed_floors"]
	var counts = {}
	for f in range(floors.size()):
		var spec = fixed.get(str(f + 1))
		if spec != null:
			_assign_fixed(floors[f], spec, rng)
			for node in floors[f]:
				counts[node["type"]] = int(counts.get(node["type"], 0)) + 1
	for f in range(floors.size()):
		if fixed.has(str(f + 1)):
			continue
		for i in range(floors[f].size()):
			var t = _draw_type(floors, f, i, rules, counts, rng)
			floors[f][i]["type"] = t
			counts[t] = int(counts.get(t, 0)) + 1


# types for a fixed floor: with "need_each" every listed type appears at least once (when there are enough
# nodes), the rest are drawn from the list, then the order is shuffled
static func _assign_fixed(nodes: Array, spec: Dictionary, rng: RandomNumberGenerator) -> void:
	var types = spec["types"]
	var list = []
	if spec.get("need_each", false) and nodes.size() >= types.size():
		list.append_array(types)
	while list.size() < nodes.size():
		list.append(types[0] if types.size() == 1 else types[rng.randi() % types.size()])
	if types.size() > 1:
		DailyScript.shuffle_with(list, rng)
	for i in range(nodes.size()):
		nodes[i]["type"] = list[i]


# weighted draw of one node type for floors[f][i]; see docs/MAP_GENERATION.md for the rules
static func _draw_type(
	floors: Array, f: int, i: int, rules: Dictionary, counts: Dictionary, rng: RandomNumberGenerator
) -> String:
	var blocked = []  # types of the nodes this one is connected to that are already known
	if f > 0:
		for parent in floors[f - 1]:
			if parent["next"].has(i) and parent["type"] != "":
				blocked.append(parent["type"])
	if f + 1 < floors.size():
		for j in floors[f][i]["next"]:
			var child_type = floors[f + 1][j]["type"]
			if child_type != "":
				blocked.append(child_type)
	var restricted = rules.get("no_repeat_along_edge", [])
	var table = rules["types"]
	var allowed = []
	var total = 0
	for t in table:
		var row = table[t]
		if f + 1 < int(row["min_floor"]):
			continue
		if row.get("max_per_map") != null and int(counts.get(t, 0)) >= int(row["max_per_map"]):
			continue
		if restricted.has(t) and blocked.has(t):
			continue
		allowed.append(t)
		total += int(row["weight"])
	if total <= 0:
		return "normal"
	var roll = rng.randi() % total
	for t in allowed:
		roll -= int(table[t]["weight"])
		if roll < 0:
			return t
	return allowed[allowed.size() - 1]
