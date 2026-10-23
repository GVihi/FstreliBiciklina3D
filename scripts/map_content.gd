extends RefCounted
# Encounter contents of the run map (README Milestone G, "Generate arena layouts and encounter contents from
# the seed"). map_gen.gd lays out the nodes and their types; this file decides what is in each node. Rules and
# numbers: the "content" section of data/map_rules.json, what they mean: docs/MAP_GENERATION.md.
#
# One run has one arena layout (scripts/arena_gen.gd, generated from the same run seed), and every node uses
# that whole arena with its own set-up (docs/PROCEDURAL_ARENAS.md, "Map nodes"). So the content of a node is
# data about the set-up, never geometry. Every node gets a "content" dictionary:
#   all nodes:  "theme"      index into Content.THEMES (boss nodes use the fixed theme of their boss)
#   fights      "riders"     {"count": n, "mix": {"pro": a, "sprinter": b, "courier": c, "tough": d}}, the
#   (normal,                 numbers in "mix" add up to "count" and only use rider types allowed on that floor
#   elite,      "gates"      sorted indexes into the arena layout's "gates" list that riders may enter by
#   boss):      "modifiers"  0 or 1 round modifiers from the rules ("rain", "double_riders"), in an Array
#   boss nodes: "boss"       the boss kind ("mower", "wifi", "minister"), and "final": true for the last boss
#   others      "seed"       a 32-bit number for whatever shop, rest or event needs to draw later (Milestone D)
#                            (shop, rest, event)
# The map also records "gates", how many gates the arena has, so the content can be checked without the layout.
#
# Every node draws from its own generator, seeded with DailyScript.stream_seed(run_seed, floor * 100 + lane,
# "map_content") (attempt 0; later attempts use "map_retry:<attempt>:map_content"). Changing what one node
# draws therefore never changes another node, and the content never touches the streams that lay out the map,
# so adding it did not change a single floor, edge or node type.

const DailyScript = preload("res://scripts/daily.gd")

const FIGHTS = ["normal", "elite", "boss"]


# true when this node type is a fight (it has riders, gates and modifiers)
static func is_fight(type: String) -> bool:
	return FIGHTS.has(type)


# Fills floors[f][i]["content"] for every node of the map. `gate_count` is how many gates the run's arena
# layout has. Does nothing when the rules have no "content" section.
static func fill(
	map: Dictionary, run_seed: int, attempt: int, gate_count: int, rules: Dictionary
) -> void:
	var crules = rules.get("content", {})
	if crules.is_empty():
		return
	map["gates"] = gate_count
	var name = str(rules.get("streams", {}).get("content", "map_content"))
	var floors = map["floors"]
	for f in range(floors.size()):
		var spec = rules["fixed_floors"].get(str(f + 1))
		var boss_tag = "" if spec == null else str(spec.get("boss", ""))
		for i in range(floors[f].size()):
			var rng = _node_rng(run_seed, attempt, name, f, i)
			floors[f][i]["content"] = _node_content(
				str(floors[f][i]["type"]), f + 1, boss_tag, gate_count, crules, rng
			)


# the generator of one node: floor f (0-based) and lane i
static func _node_rng(
	run_seed: int, attempt: int, name: String, f: int, i: int
) -> RandomNumberGenerator:
	var rng = RandomNumberGenerator.new()
	var part = name if attempt == 0 else "map_retry:%d:%s" % [attempt, name]
	rng.seed = DailyScript.stream_seed(run_seed, f * 100 + i, part)
	return rng


# The content of one node. `floor_no` is 1-based. The draw order inside a node is fixed: theme first, then
# riders, gates and modifiers for fights, the boss kind for bosses, or the seed for the other nodes.
static func _node_content(
	type: String,
	floor_no: int,
	boss_tag: String,
	gate_count: int,
	crules: Dictionary,
	rng: RandomNumberGenerator
) -> Dictionary:
	var content = {}
	var theme = rng.randi() % maxi(1, int(crules["theme_count"]))
	if type == "boss" and crules["boss_theme"].has(boss_tag):
		theme = int(crules["boss_theme"][boss_tag])
	content["theme"] = theme
	if not is_fight(type):
		content["seed"] = rng.randi()
		return content
	content["riders"] = _riders(type, floor_no, crules["riders"], rng)
	content["gates"] = _gates(gate_count, int(crules["gates"]["min_open"]), rng)
	content["modifiers"] = _modifiers(type, floor_no, crules["modifiers"], rng)
	if type == "boss":
		var kinds = crules["boss_kinds"].get(boss_tag, [])
		if kinds.is_empty():
			kinds = crules["boss_kinds"]["mid"]
		content["boss"] = str(kinds[rng.randi() % kinds.size()])
		if boss_tag == "final":
			content["final"] = true
	return content


# How many riders and of which kinds. Types that are not allowed yet on this floor have weight 0. Every key of
# the weights table is in "mix", also when no rider of that kind was drawn.
static func _riders(
	type: String, floor_no: int, rrules: Dictionary, rng: RandomNumberGenerator
) -> Dictionary:
	var count_rule = rrules["count"][type]
	var n = rng.randi_range(int(count_rule["min"]), int(count_rule["max"]))
	var weights = rrules["weights"][type]
	var allowed = {}
	var total = 0
	var mix = {}
	for t in weights:
		mix[t] = 0
		if floor_no >= int(rrules["min_floor"].get(t, 1)):
			allowed[t] = int(weights[t])
			total += int(weights[t])
	for k in range(n):
		if total <= 0:
			mix[weights.keys()[0]] += 1
			continue
		mix[_pick(allowed, total, rng)] += 1
	return {"count": n, "mix": mix}


# Which of the arena's gates riders come in by: between `min_open` (or all of them when there are fewer) and
# every gate, chosen by shuffling, returned in order.
static func _gates(gate_count: int, min_open: int, rng: RandomNumberGenerator) -> Array:
	var all = range(gate_count)
	DailyScript.shuffle_with(all, rng)
	var open_n = rng.randi_range(mini(min_open, gate_count), gate_count)
	var open = all.slice(0, open_n)
	open.sort()
	return open


# 0 or 1 round modifier. The roll is always drawn, so the rest of the node does not depend on the answer.
static func _modifiers(
	type: String, floor_no: int, mrules: Dictionary, rng: RandomNumberGenerator
) -> Array:
	var roll = rng.randf()
	if roll >= float(mrules["chance"].get(type, 0.0)):
		return []
	var allowed = {}
	var total = 0
	for t in mrules["types"]:
		var row = mrules["types"][t]
		if floor_no >= int(row["min_floor"]):
			allowed[t] = int(row["weight"])
			total += int(row["weight"])
	if total <= 0:
		return []
	return [_pick(allowed, total, rng)]


# weighted draw from {name: weight}, in the order of the keys
static func _pick(weights: Dictionary, total: int, rng: RandomNumberGenerator) -> String:
	var roll = rng.randi() % total
	var last = ""
	for t in weights:
		last = t
		roll -= int(weights[t])
		if roll < 0:
			return t
	return last
