extends SceneTree
# Check for the map node's set-up in a round (README Milestone K, Gameplay on open ground: "Connect the arena to
# the run map"). Run from the project folder:
#   godot --headless --path . --script res://tools/node_setup_check.gd
# Exits with status 1 and prints the first problems.
#
# On a generated arena, with the first node of the map picked:
#   - the round's theme is the node's theme (theme_idx);
#   - the round has the node's number of riders (PER_ROUND, the HUD icons and hits array follow it) and the plan of
#     kinds adds up to the node's mix, and the riders spawned have exactly those kinds;
#   - riders only come in by the gates the node leaves open, and by any gate when the node lists none;
#   - a boss node has its boss only after every rider is down and only once, and the boss is the node's kind (the
#     last node's is the final minister); a fight node without a boss never asks for one, even where the old rule
#     would have (after 4 riders);
#   - the "double_riders" modifier makes every wave a pair of riders.
# On the roundabout (the arena the game starts with) none of it applies: node_setup() is empty, a round has 10
# riders, no plan, and the theme follows the old rule (round number and run seed).

const SEEDS = [0x9E378A43, 1, 2, 3]

var bad: Array = []
var main = null


func _init() -> void:
	await _check_generated()
	await _check_roundabout()
	if bad.is_empty():
		print(
			"node_setup_check: the node's theme, riders and gates set up the round on a generated arena only"
		)
		quit(0)
	else:
		print("node_setup_check: %d problem(s)" % bad.size())
		for p in bad.slice(0, 12):
			print("  " + p)
		quit(1)


func _boot(generated: bool) -> void:
	main = load("res://main.tscn").instantiate()
	main.generated_arena = generated
	root.add_child(main)
	for i in range(3):
		await process_frame
	seed(5)


func _kinds_of(list: Array) -> Dictionary:
	var out = {}
	for k in list:
		out[str(k)] = int(out.get(str(k), 0)) + 1
	return out


func _same_counts(a: Dictionary, b: Dictionary) -> bool:
	for k in a:
		if int(a[k]) != int(b.get(k, 0)):
			return false
	for k in b:
		if int(b[k]) != int(a.get(k, 0)):
			return false
	return true


func _check_generated() -> void:
	await _boot(true)
	for seed_value in SEEDS:
		main.start_game(false, seed_value)
		main.hits.resize(400)
		main.hits.fill(false)
		if main.run_map.is_empty():
			bad.append("seed %X: no run map" % seed_value)
			continue
		main.pick_node(0)
		var node = main.current_node()
		var content: Dictionary = node.get("content", {})
		var tag = "seed %X" % seed_value
		if content.is_empty() or main.node_setup().is_empty():
			bad.append("%s: the first node has no set-up on a generated arena" % tag)
			continue
		if main.theme_idx != int(content["theme"]) % main.THEMES.size():
			bad.append(
				"%s: theme %d, the node says %d" % [tag, main.theme_idx, int(content["theme"])]
			)
		var want_count = int(content["riders"]["count"])
		if main.PER_ROUND != want_count:
			bad.append(
				"%s: %d riders in the round, the node says %d" % [tag, main.PER_ROUND, want_count]
			)
		if main.hits.size() != main.PER_ROUND:
			bad.append(
				(
					"%s: the hits list has %d entries for %d riders"
					% [tag, main.hits.size(), main.PER_ROUND]
				)
			)
		var mix = {}
		for kind in content["riders"]["mix"]:
			if int(content["riders"]["mix"][kind]) > 0:
				mix[str(kind)] = int(content["riders"]["mix"][kind])
		if not _same_counts(_kinds_of(main.rider_plan), mix):
			bad.append(
				"%s: the plan %s is not the node's mix %s" % [tag, str(main.rider_plan), str(mix)]
			)
		var spawned = []
		main.clear_riders()
		for i in range(main.PER_ROUND):
			var r = main.rider_sys.spawn_rider(0, 1)
			spawned.append(r["type"])
		if not _same_counts(_kinds_of(spawned), mix):
			bad.append(
				(
					"%s: the riders spawned %s, the node's mix is %s"
					% [tag, str(_kinds_of(spawned)), str(mix)]
				)
			)
		main.clear_riders()
		_check_gates(tag, content)
		_check_bosses_and_modifiers(tag)
	main.queue_free()
	await process_frame


func _check_gates(tag: String, content: Dictionary) -> void:
	var gates = main.arena.gates()
	if gates.size() < 2:
		bad.append("%s: the arena has %d gates, the gate check needs 2" % [tag, gates.size()])
		return
	var saved = content["gates"]
	content["gates"] = [gates.size() - 1]
	for i in range(40):
		if main.rider_sys.pick_gate() != gates[gates.size() - 1]:
			bad.append("%s: a rider came in by a gate the node did not open" % tag)
			break
	content["gates"] = []
	var seen = {}
	for i in range(80):
		seen[main.rider_sys.pick_gate()["pos"]] = true
	if seen.size() < 2:
		bad.append(
			(
				"%s: with no gates listed the riders used %d gate(s), expected all of them"
				% [tag, seen.size()]
			)
		)
	content["gates"] = saved


func _check_roundabout() -> void:
	await _boot(false)
	main.start_game(false, 0x9E378A43)
	main.hits.resize(400)
	main.hits.fill(false)
	if main.run_map.is_empty():
		bad.append("roundabout: no run map")
	else:
		main.pick_node(0)
		if not main.node_setup().is_empty():
			bad.append("roundabout: node_setup is not empty")
		if main.PER_ROUND != main.DEFAULT_PER_ROUND:
			bad.append(
				(
					"roundabout: %d riders in the round, expected %d"
					% [main.PER_ROUND, main.DEFAULT_PER_ROUND]
				)
			)
		if not main.rider_plan.is_empty():
			bad.append("roundabout: the round has a rider plan")
		var want = (main.round_n - 1 + main.seed_shift(main.THEMES.size())) % main.THEMES.size()
		if main.theme_idx != want:
			bad.append("roundabout: theme %d, the old rule gives %d" % [main.theme_idx, want])
	main.queue_free()
	await process_frame


# puts the run on node (floor index f, lane) and starts its round
func _play_node(f: int, lane: int) -> void:
	main.map_floor = f
	main.map_lane = lane
	main.round_n = f + 1
	main.start_round()
	main.hits.fill(true)  # every rider of the round counts as hit, so only the riders still to come matter


func _check_bosses_and_modifiers(tag: String) -> void:
	var floors = main.run_map["floors"]
	var boss_nodes = 0
	var plain_nodes = 0
	for f in range(floors.size()):
		for lane in range(floors[f].size()):
			var node = floors[f][lane]
			var where = "%s floor %d lane %d" % [tag, f + 1, lane]
			if node["type"] == "boss":
				boss_nodes += 1
				_play_node(f, lane)
				var content: Dictionary = node["content"]
				main.next_idx = 4
				if main.need_boss():
					bad.append(
						(
							"%s: a boss was asked for after 4 riders, before the others are down"
							% where
						)
					)
				main.next_idx = main.PER_ROUND
				if not main.need_boss():
					bad.append("%s: no boss was asked for with every rider down" % where)
				main.clear_bosses()
				main.boss_sys.spawn_boss()
				var b = main.bosses.back()
				if b["kind"] != str(content["boss"]):
					bad.append(
						(
							"%s: the boss is a %s, the node says %s"
							% [where, b["kind"], str(content["boss"])]
						)
					)
				if bool(b["final"]) != bool(content.get("final", false)):
					bad.append(
						(
							"%s: the boss's final flag is %s, the node says %s"
							% [where, str(b["final"]), str(content.get("final", false))]
						)
					)
				if content.get("final", false) and b["kind"] != "minister":
					bad.append("%s: the final boss is a %s, not the minister" % [where, b["kind"]])
				main.clear_bosses()
				if main.need_boss():
					bad.append("%s: a second boss was asked for after the first" % where)
			elif plain_nodes < 2 and f >= 1 and ["normal", "elite"].has(node["type"]):
				plain_nodes += 1
				_play_node(f, lane)
				for n in [4, main.PER_ROUND]:
					main.next_idx = n
					if main.need_boss():
						bad.append(
							(
								"%s: a fight node without a boss asked for one with %d riders out"
								% [where, n]
							)
						)
	if boss_nodes < 2:
		bad.append(
			"%s: %d boss nodes on the map, expected the mid and the final boss" % [tag, boss_nodes]
		)
	# the double riders modifier, on the first node (round 1, where a wave is one rider unless the node says so)
	var first: Dictionary = floors[0][0]["content"]
	var saved = first["modifiers"]
	first["modifiers"] = []
	_play_node(0, 0)
	main.clear_riders()
	main.next_idx = 0
	main.rider_sys.spawn_wave()
	if main.riders.size() != 1:
		bad.append(
			(
				"%s: a wave without the modifier has %d riders in round 1, expected 1"
				% [tag, main.riders.size()]
			)
		)
	first["modifiers"] = ["double_riders"]
	_play_node(0, 0)
	main.clear_riders()
	main.next_idx = 0
	main.rider_sys.spawn_wave()
	if not main.has_modifier("double_riders") or main.riders.size() != 2:
		bad.append(
			"%s: a wave with double riders has %d riders, expected 2" % [tag, main.riders.size()]
		)
	first["modifiers"] = saved
	main.clear_riders()
