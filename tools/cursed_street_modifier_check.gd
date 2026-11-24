extends SceneTree
# Check for the CURSED STREET round modifier (README Milestone D, MD7.5). Run from the project folder:
#   godot --headless --path . --script res://tools/cursed_street_modifier_check.gd
# Exits with status 1 and prints the first problems.
#
# A round whose node holds the "cursed_street" modifier gives a catch (vanishing, cursed or locked) to every cache but
# one: objective.gd setup_round reads variant_chance(street) and variant_cap(count, street), and pick_variants still
# draws the same two numbers per cache, so no other stream moves and the same seed gives the same answer. The cache
# that is left plain can hold the key of a locked one; assign_keys turns a locked cache that finds no holder plain.
# Checked here, first on the functions and the rolls and then in real rounds on generated arenas (no modifier is built
# in, the node is given it):
#   - variant_chance and variant_cap are the old numbers without the modifier, a certain chance and all but one with
#     it, and the cap is never below 0;
#   - over many seeds a street roll leaves exactly one cache plain (the last), draws the same stream as a plain roll,
#     gives every other cache that rolled a catch in the plain round the same catch, gives more catches than a plain
#     round does, and repeats for the same seed;
#   - after assign_keys every locked cache has its own key holder, a cache that is still plain is a key holder or a
#     locked cache that found no holder, and some cache is always plain;
#   - in real rounds the caches of a CURSED STREET round are what the round's own stream gives with the street
#     numbers, their spots and meta coins are the plain round's, and the round before and after, without the
#     modifier, has the plain variants (at most VARIANT_MAX of them);
#   - the name is written CURSED STREET, and the row in data/map_rules.json is there and, at weight 0, moves no map.

const MapGen = preload("res://scripts/map_gen.gd")
const Objective = preload("res://scripts/objective.gd")
const DailyScript = preload("res://scripts/daily.gd")

const SEEDS = [0x9E378A43, 1, 2]
const ROLLS = 300
const SEED = 0x51C0DE77

var bad: Array = []
var main = null


func _initialize() -> void:
	_check_functions()
	_check_rolls()
	await _check_rounds()
	_check_rules()
	if bad.is_empty():
		print(
			"cursed_street_modifier_check: a CURSED STREET round gives all but one cache a catch, every other round as before"
		)
		quit(0)
	else:
		print("cursed_street_modifier_check: %d problem(s)" % bad.size())
		for p in bad.slice(0, 12):
			print("  " + p)
		quit(1)


func _rng(seed_value: int) -> RandomNumberGenerator:
	var r = RandomNumberGenerator.new()
	r.seed = seed_value
	return r


func _boot() -> void:
	main = load("res://main.tscn").instantiate()
	main.generated_arena = true
	root.add_child(main)
	for i in range(3):
		await process_frame
	seed(5)


# starts the round of the first node of the map (a normal fight)
func _play_first_node() -> void:
	main.map_floor = 0
	main.map_lane = 0
	main.round_n = 1
	main.start_round()
	main.hits.fill(true)


# the two functions that decide the chance and the cap
func _check_functions() -> void:
	var n = Objective.CACHE_COUNT
	if Objective.variant_chance(false) != Objective.VARIANT_CHANCE:
		bad.append(
			"a round without the modifier has the chance %f" % Objective.variant_chance(false)
		)
	if Objective.variant_chance(true) < 1.0:
		bad.append(
			(
				"a CURSED STREET round has the chance %f, expected a certain one"
				% Objective.variant_chance(true)
			)
		)
	if Objective.variant_cap(n, false) != Objective.VARIANT_MAX:
		bad.append("a round without the modifier has the cap %d" % Objective.variant_cap(n, false))
	if Objective.variant_cap(n, true) != n - 1:
		bad.append(
			(
				"a CURSED STREET round of %d caches has the cap %d, expected %d"
				% [n, Objective.variant_cap(n, true), n - 1]
			)
		)
	if Objective.variant_cap(1, true) != 0 or Objective.variant_cap(0, true) != 0:
		bad.append("the cap of a round with 1 or 0 caches is not 0")


# the rolls themselves, on many seeds
func _check_rolls() -> void:
	var n = Objective.CACHE_COUNT
	var chance = Objective.variant_chance(true)
	var cap = Objective.variant_cap(n, true)
	var total_plain_round = 0
	var total_street = 0
	for s in range(ROLLS):
		var plain_rng = _rng(SEED + s)
		var street_rng = _rng(SEED + s)
		var plain = Objective.pick_variants(n, plain_rng)
		var street = Objective.pick_variants(n, street_rng, chance, cap)
		if plain_rng.state != street_rng.state:
			bad.append("seed %d: a street roll draws another stream than a plain roll" % s)
			break
		if street != Objective.pick_variants(n, _rng(SEED + s), chance, cap):
			bad.append("seed %d: the same seed gave two different street rolls" % s)
			break
		if street.count(Objective.VARIANT_PLAIN) != n - cap:
			bad.append(
				(
					"seed %d: %d caches are plain before the keys, expected %d"
					% [s, street.count(Objective.VARIANT_PLAIN), n - cap]
				)
			)
			break
		# the caches the cap reaches (all but the last) get the catch the plain roll drew for them, when it drew one
		var kept = true
		for i in range(mini(cap, n)):
			if plain[i] != Objective.VARIANT_PLAIN and plain[i] != street[i]:
				kept = false
		if not kept:
			bad.append(
				(
					"seed %d: a cache that rolled %s in a plain round got another catch"
					% [s, str(plain)]
				)
			)
			break
		total_plain_round += n - plain.count(Objective.VARIANT_PLAIN)
		var before = street.duplicate()
		var holds = Objective.assign_keys(street)
		var holders = holds.count(true)
		if holders != street.count(Objective.VARIANT_LOCKED):
			bad.append(
				(
					"seed %d: %d key holders for %d locked caches (%s)"
					% [s, holders, street.count(Objective.VARIANT_LOCKED), str(street)]
				)
			)
			break
		if street.count(Objective.VARIANT_PLAIN) < 1:
			bad.append("seed %d: no plain cache is left (%s)" % [s, str(street)])
			break
		var stray = false
		for i in range(n):
			if (
				street[i] == Objective.VARIANT_PLAIN
				and not holds[i]
				and before[i] != Objective.VARIANT_LOCKED
			):
				stray = true
		if stray:
			bad.append(
				(
					"seed %d: a cache is plain that neither holds a key nor was a locked one (%s)"
					% [s, str(before)]
				)
			)
			break
		total_street += n - street.count(Objective.VARIANT_PLAIN)
	if total_street <= total_plain_round:
		bad.append(
			(
				"over %d rolls a street round gave %d catches and a plain one %d"
				% [ROLLS, total_street, total_plain_round]
			)
		)


# what the round's own variant stream gives for n caches, with the street numbers or the old ones; returns the
# variants and the key holders
func _expected(n: int, street: bool) -> Dictionary:
	var vrng = RandomNumberGenerator.new()
	vrng.seed = DailyScript.stream_seed(main.run_seed, main.round_n, "cache_variant")
	var variants = Objective.pick_variants(
		n, vrng, Objective.variant_chance(street), Objective.variant_cap(n, street)
	)
	var holds = Objective.assign_keys(variants)
	return {"variants": variants, "holds": holds}


# the caches the round just built: where, which catch, which one holds a key, which one holds a meta coin
func _caches() -> Array:
	var out = []
	for c in main.objective_sys.caches:
		out.append({"pos": c["pos"], "variant": c["variant"], "key": c["key"], "coin": c["coin"]})
	return out


func _variants_of(list: Array) -> Array:
	var out = []
	for c in list:
		out.append(c["variant"])
	return out


func _holds_of(list: Array) -> Array:
	var out = []
	for c in list:
		out.append(c["key"])
	return out


func _check_rounds() -> void:
	await _boot()
	if main.modifier_names(["cursed_street"]) != ["CURSED STREET"]:
		bad.append(
			(
				"cursed_street is written %s, expected [CURSED STREET]"
				% str(main.modifier_names(["cursed_street"]))
			)
		)
	for seed_value in SEEDS:
		var tag = "seed %X" % seed_value
		main.heat = 0
		main.start_game(false, seed_value)
		main.hits.resize(400)
		main.hits.fill(false)
		if main.run_map.is_empty():
			bad.append("%s: no run map" % tag)
			continue
		var first: Dictionary = main.run_map["floors"][0][0]["content"]
		var saved_mods = first["modifiers"]
		# a round without the modifier
		first["modifiers"] = []
		_play_first_node()
		if main.has_modifier("cursed_street"):
			bad.append("%s: has_modifier('cursed_street') is true in a round without it" % tag)
		var plain = _caches()
		_check_plain("%s, plain" % tag, plain)
		# a CURSED STREET round
		first["modifiers"] = ["cursed_street"]
		_play_first_node()
		if not main.has_modifier("cursed_street"):
			bad.append("%s: has_modifier('cursed_street') is false" % tag)
		var street = _caches()
		_check_street("%s, cursed_street" % tag, plain, street)
		# the round after, without the modifier
		first["modifiers"] = []
		_play_first_node()
		if main.has_modifier("cursed_street"):
			bad.append("%s: has_modifier('cursed_street') is still true in the round after" % tag)
		var after = _caches()
		if str(after) != str(plain):
			bad.append("%s: the round after is not the plain round" % tag)
		first["modifiers"] = saved_mods
	main.queue_free()
	await process_frame


# a round without the modifier: the variants its stream gives with the old numbers, at most VARIANT_MAX of them
func _check_plain(where: String, list: Array) -> void:
	if list.is_empty():
		bad.append("%s: the round has no caches, the check proves nothing" % where)
		return
	var want = _expected(list.size(), false)
	if _variants_of(list) != want["variants"] or _holds_of(list) != want["holds"]:
		bad.append(
			(
				"%s: the variants %s are not what the stream gives (%s)"
				% [where, str(_variants_of(list)), str(want["variants"])]
			)
		)
	var carried = 0
	for v in _variants_of(list):
		if v != Objective.VARIANT_PLAIN:
			carried += 1
	if carried > Objective.VARIANT_MAX:
		bad.append("%s: %d caches carry a catch, more than VARIANT_MAX" % [where, carried])


# the CURSED STREET round: the variants of the street numbers, the same spots and coins as the plain round, every
# locked cache with its own key holder, and some cache left plain
func _check_street(where: String, plain: Array, street: Array) -> void:
	if street.size() != plain.size():
		bad.append(
			"%s: %d caches against %d in the plain round" % [where, street.size(), plain.size()]
		)
		return
	var want = _expected(street.size(), true)
	if _variants_of(street) != want["variants"] or _holds_of(street) != want["holds"]:
		bad.append(
			(
				"%s: the variants %s are not what the stream gives with the street numbers (%s)"
				% [where, str(_variants_of(street)), str(want["variants"])]
			)
		)
	for i in range(street.size()):
		if street[i]["pos"] != plain[i]["pos"] or street[i]["coin"] != plain[i]["coin"]:
			bad.append(
				"%s: cache %d has another spot or meta coin than in the plain round" % [where, i]
			)
			break
	var variants = _variants_of(street)
	if variants.count(Objective.VARIANT_PLAIN) < 1:
		bad.append("%s: no plain cache is left (%s)" % [where, str(variants)])
	if _holds_of(street).count(true) != variants.count(Objective.VARIANT_LOCKED):
		bad.append(
			"%s: the locked caches and the key holders do not match (%s)" % [where, str(variants)]
		)


# the row is in the rules, and at weight 0 it moves no map
func _check_rules() -> void:
	var rules = MapGen.load_rules()
	var row = rules["content"]["modifiers"]["types"].get("cursed_street", {})
	if row.is_empty():
		bad.append("there is no cursed_street row in modifiers.types of data/map_rules.json")
		return
	if not row.has("weight") or not row.has("min_floor"):
		bad.append("the cursed_street row has no weight or no min_floor: %s" % str(row))
		return
	if row.has("forces_theme"):
		bad.append("the cursed_street row forces a theme: %s" % str(row))
	if int(row["weight"]) != 0:
		return  # turned on in MD7.6, where map_check checks how often it turns up
	var plain = rules.duplicate(true)
	plain["content"]["modifiers"]["types"].erase("cursed_street")
	for n in range(40):
		var seed_value = (n * 40503 + 7) & 0xFFFFFFFF
		var gates = 2 + (seed_value % 4)
		var m = MapGen.generate(seed_value, plain, gates)
		var w = MapGen.generate(seed_value, rules, gates)
		if m.is_empty() or w.is_empty():
			bad.append("seed %08X: no map" % seed_value)
			continue
		if JSON.stringify(m, "", true) != JSON.stringify(w, "", true):
			bad.append("seed %08X: the map changed with the weight 0 row in the rules" % seed_value)
			break
