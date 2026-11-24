extends SceneTree
# Check for the ONE GATE round modifier (README Milestone D, MD7.3). Run from the project folder:
#   godot --headless --path . --script res://tools/one_gate_modifier_check.gd
# Exits with status 1 and prints the first problems.
#
# A round whose node holds the "one_gate" modifier sends every rider of its waves out of the same one of the gates the
# node leaves open (riders.gd pick_gate). The gate comes from a stream of its own (run seed, round, "one_gate"), and
# pick_gate still makes its usual draw, so every other random number of the round is the one a round without the
# modifier gets. Checked here, in real rounds on generated arenas (no modifier is built in, the node is given it):
#   - in a ONE GATE round every pick is the same gate, one the node leaves open, and a rider spawned there starts at
#     that gate; the same round played again gives the same gate;
#   - the round's rider stream after the same picks is in exactly the same state with the modifier and without it;
#   - the gate index depends on the round, is the same twice, is in range, and moves no stream;
#   - the ambush's gate and a gate handed to spawn_rider (a cursed cache) are not the modifier's;
#   - the round after, without the modifier, is back to picking among the open gates;
#   - the name is written ONE GATE, and the row in data/map_rules.json is there and, at weight 0, moves no map.

const MapGen = preload("res://scripts/map_gen.gd")

const SEEDS = [0x9E378A43, 1, 2]
const PICKS = 40

var bad: Array = []
var main = null


func _init() -> void:
	await _check_rounds()
	_check_rules()
	if bad.is_empty():
		print(
			"one_gate_modifier_check: a ONE GATE round uses one gate, every other round as before"
		)
		quit(0)
	else:
		print("one_gate_modifier_check: %d problem(s)" % bad.size())
		for p in bad.slice(0, 12):
			print("  " + p)
		quit(1)


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


# the gates the node leaves open, the way pick_gate reads them
func _usable() -> Array:
	var gates = main.arena.gates()
	var usable = []
	for i in main.node_setup().get("gates", []):
		if int(i) >= 0 and int(i) < gates.size():
			usable.append(gates[int(i)])
	if usable.is_empty():
		usable = gates
	return usable


func _picks(n: int) -> Array:
	var out = []
	for i in range(n):
		out.append(main.rider_sys.pick_gate())
	return out


# how many different gates there are in a list of gates
func _distinct(gates: Array) -> int:
	var seen = []
	for gate in gates:
		if not seen.has(gate["pos"]):
			seen.append(gate["pos"])
	return seen.size()


# the state of the round's rider stream after PICKS gate picks from a fixed seed
func _stream_after_picks(seed_value: int) -> int:
	main.rider_rng.seed = seed_value
	_picks(PICKS)
	return main.rider_rng.state


# where a rider starts, on the ground (the height is not what the gate decides)
func _flat(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)


func _check_rounds() -> void:
	await _boot()
	if main.modifier_names(["one_gate"]) != ["ONE GATE"]:
		bad.append(
			"one_gate is written %s, expected [ONE GATE]" % str(main.modifier_names(["one_gate"]))
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
		first["modifiers"] = ["one_gate"]
		_play_first_node()
		var one = _check_one_gate_round("%s, one_gate" % tag)
		_check_gate_index("%s, one_gate" % tag)
		_check_stream("%s, one_gate" % tag)
		_check_extras("%s, one_gate" % tag, one)
		# the same round again: the same gate
		_play_first_node()
		var again = _picks(PICKS)
		if _distinct(again) != 1 or again[0]["pos"] != one["pos"]:
			bad.append("%s: the same round played again did not give the same gate" % tag)
		# the round after, without the modifier
		first["modifiers"] = []
		_play_first_node()
		if main.has_modifier("one_gate"):
			bad.append("%s: has_modifier('one_gate') is still true in the round after" % tag)
		var spread = _distinct(_picks(PICKS))
		if _usable().size() >= 2 and spread < 2:
			bad.append("%s: without the modifier %d gate(s) in %d picks" % [tag, spread, PICKS])
		first["modifiers"] = saved_mods
	main.queue_free()
	await process_frame


# every pick is the same gate, a gate the node leaves open, and a rider spawned by the wave code starts there;
# returns that gate
func _check_one_gate_round(where: String) -> Dictionary:
	if not main.has_modifier("one_gate"):
		bad.append("%s: has_modifier('one_gate') is false" % where)
	var usable = _usable()
	if usable.size() < 2:
		bad.append(
			"%s: the node leaves %d gate(s) open, the check proves nothing" % [where, usable.size()]
		)
	var picks = _picks(PICKS)
	if _distinct(picks) != 1:
		bad.append(
			"%s: %d different gates in %d picks, expected 1" % [where, _distinct(picks), PICKS]
		)
	var one: Dictionary = picks[0]
	if not usable.has(one):
		bad.append("%s: the gate is not one the node leaves open" % where)
	var want = _flat(main.rider_sys.gate_spawn_point(one))
	for k in range(4):
		var r = main.rider_sys.spawn_rider(k % 3, 1)
		if _flat(r["pos"]).distance_to(want) > 0.05:
			bad.append(
				"%s: rider %d starts at %s, not at the gate (%s)" % [where, k, r["pos"], want]
			)
			break
	return one


# the index of the gate depends on the round, is the same twice, is in range and moves no stream
func _check_gate_index(where: String) -> void:
	var before = main.rider_rng.state
	var saved_round = main.round_n
	var seen = {}
	var failed = false
	for round_no in range(1, 31):
		main.round_n = round_no
		var i = main.rider_sys.one_gate_index(4)
		seen[i] = true
		if i < 0 or i >= 4:
			bad.append("%s: round %d gave gate index %d of 4" % [where, round_no, i])
			failed = true
		elif main.rider_sys.one_gate_index(4) != i:
			bad.append("%s: round %d gave two different gate indexes" % [where, round_no])
			failed = true
		if failed:
			break
	if main.rider_sys.one_gate_index(1) != 0:
		bad.append("%s: with one gate open the index is not 0" % where)
	main.round_n = saved_round
	if not failed and seen.size() < 2:
		bad.append("%s: the same gate index in 30 rounds" % where)
	if main.rider_rng.state != before:
		bad.append("%s: one_gate_index moved the round's rider stream" % where)


# the round's rider stream ends in the same state with the modifier and without it
func _check_stream(where: String) -> void:
	var saved = main.round_modifiers
	main.round_modifiers = ["one_gate"]
	var with_it = _stream_after_picks(77)
	main.round_modifiers = []
	var without = _stream_after_picks(77)
	main.round_modifiers = saved
	if with_it != without:
		bad.append(
			(
				"%s: the rider stream is in another state with the modifier (%d, %d)"
				% [where, with_it, without]
			)
		)


# the ambush's gate and a gate handed to spawn_rider are not the modifier's
func _check_extras(where: String, one: Dictionary) -> void:
	var saved = main.round_modifiers
	main.player.position = Vector3.ZERO
	main.round_modifiers = ["one_gate"]
	main.rider_rng.seed = 123
	var ambush_with = main.rider_sys.ambush_gate()
	main.round_modifiers = []
	main.rider_rng.seed = 123
	var ambush_without = main.rider_sys.ambush_gate()
	main.round_modifiers = saved
	if ambush_with["pos"] != ambush_without["pos"]:
		bad.append("%s: the modifier changed the gate of an ambush rider" % where)
	var other = {}
	for gate in _usable():
		if gate["pos"] != one["pos"]:
			other = gate
			break
	if other.is_empty():
		return
	var r = main.rider_sys.spawn_rider(0, 1, true, RandomNumberGenerator.new(), other)
	var want = _flat(main.rider_sys.gate_spawn_point(other))
	if _flat(r["pos"]).distance_to(want) > 0.05:
		bad.append("%s: a rider sent to a given gate did not start there" % where)


# the row is in the rules, and at weight 0 it moves no map
func _check_rules() -> void:
	var rules = MapGen.load_rules()
	var row = rules["content"]["modifiers"]["types"].get("one_gate", {})
	if row.is_empty():
		bad.append("there is no one_gate row in modifiers.types of data/map_rules.json")
		return
	if not row.has("weight") or not row.has("min_floor"):
		bad.append("the one_gate row has no weight or no min_floor: %s" % str(row))
		return
	if int(row["weight"]) != 0:
		return  # turned on in MD7.6, where map_check checks how often it turns up
	var plain = rules.duplicate(true)
	plain["content"]["modifiers"]["types"].erase("one_gate")
	for n in range(40):
		var seed_value = (n * 40503 + 7) & 0xFFFFFFFF
		var gates = 2 + (seed_value % 4)
		var a = MapGen.generate(seed_value, plain, gates)
		var b = MapGen.generate(seed_value, rules, gates)
		if a.is_empty() or b.is_empty():
			bad.append("seed %08X: no map" % seed_value)
			continue
		if JSON.stringify(a, "", true) != JSON.stringify(b, "", true):
			bad.append("seed %08X: the map changed with the weight 0 row in the rules" % seed_value)
			break
