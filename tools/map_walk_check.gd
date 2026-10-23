extends SceneTree
# Checks that a run walks the generated map (README Milestone D, "Replace linear round progression").
# Run from the project folder:
#   godot --headless --path . --script res://tools/map_walk_check.gd
# Optional argument after "--": how many seeds to walk (default 30).
# For every seed it starts a run on that seed (the CUSTOM SEED way) and plays the map from floor 1 to the final
# boss, always taking a different choice (first, last, second in turn), and checks that
#   - a run starts on the map screen with every floor 1 node as a choice, and picking one starts that round
#   - the round number is the floor number, and the node played is the one picked
#   - after the shop the map screen offers exactly the nodes the current node connects to
#   - the path ends on the final boss floor, which is the final round, and that floor has no choices after it
#   - a run without a map still plays its rounds in a line
# Exits with status 1 and prints the first problems when a check fails.

var problems = []
var main


func _initialize() -> void:
	var count = 30
	var args = OS.get_cmdline_user_args()
	if args.size() > 0:
		count = int(args[0])
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	for i in range(3):
		await process_frame
	for n in range(count):
		_walk((n * 2654435761 + 99) & 0xFFFFFFFF, n)
	_check_linear()
	if problems.is_empty():
		print(
			(
				"map_walk_check: %d runs walked the map from floor 1 to the final boss, and a run without a map still goes in a line"
				% count
			)
		)
		quit(0)
	else:
		for line in problems.slice(0, 10):
			printerr("map_walk_check: " + line)
		quit(1)


func _fail(seed_value: int, text: String) -> void:
	problems.append("seed %08X: %s" % [seed_value, text])


func _walk(seed_value: int, n: int) -> void:
	main.start_game(false, seed_value)
	var floors = main.run_map["floors"]
	if main.state != "map":
		_fail(seed_value, "a new run did not open the map screen (state %s)" % main.state)
		return
	if main.map_choices.size() != floors[0].size():
		_fail(
			seed_value,
			(
				"the first map screen offers %d nodes, floor 1 has %d"
				% [main.map_choices.size(), floors[0].size()]
			)
		)
	if main.MAX_ROUNDS != floors.size():
		_fail(
			seed_value, "MAX_ROUNDS is %d, the map has %d floors" % [main.MAX_ROUNDS, floors.size()]
		)
	for f in range(floors.size()):
		var choices = main.map_choices.duplicate()
		if choices.is_empty():
			_fail(seed_value, "no choices on floor %d" % (f + 1))
			return
		var pick = 0
		if n % 3 == 1:
			pick = choices.size() - 1
		elif n % 3 == 2:
			pick = mini(1, choices.size() - 1)
		var lane = int(choices[pick])
		main.pick_node(pick)
		if main.state != "play":
			_fail(
				seed_value,
				(
					"picking a node on floor %d did not start the round (state %s)"
					% [f + 1, main.state]
				)
			)
			return
		if main.round_n != f + 1 or main.map_floor != f or main.map_lane != lane:
			_fail(
				seed_value,
				(
					"floor %d: round %d, node %d/%d"
					% [f + 1, main.round_n, main.map_floor, main.map_lane]
				)
			)
		if main.current_node() != floors[f][lane]:
			_fail(seed_value, "current_node is not the node picked on floor %d" % (f + 1))
		if f > 0 and not floors[f - 1][main.map_path[f - 1]]["next"].has(lane):
			_fail(
				seed_value,
				"floor %d lane %d is not reachable from the node before it" % [f + 1, lane]
			)
		if f == floors.size() - 1:
			if (
				main.round_n != main.MAX_ROUNDS
				or not main.is_final_round()
				or str(main.current_node()["type"]) != "boss"
			):
				_fail(seed_value, "the last floor is not the final boss round")
			if not main.next_lanes().is_empty():
				_fail(seed_value, "there are choices after the final boss")
			break
		# finish the round the way the game does: the shop, then on
		main.shop_sys.enter_shop()
		main.shop_sys.leave_shop()
		if main.state != "map":
			_fail(seed_value, "leaving the shop on floor %d did not open the map screen" % (f + 1))
			return
		var expected = []
		for j in floors[f][lane]["next"]:
			expected.append(int(j))
		if main.map_choices != expected:
			_fail(
				seed_value,
				(
					"after floor %d the map offers %s, the node connects to %s"
					% [f + 1, main.map_choices, expected]
				)
			)
	if main.map_path.size() != floors.size():
		_fail(
			seed_value,
			"the path has %d nodes for %d floors" % [main.map_path.size(), floors.size()]
		)


# with no map the rounds go 1, 2, 3 ... as before
func _check_linear() -> void:
	main.start_game(false, 5)
	main.run_map = {}
	main.map_floor = -1
	main.round_n = 1
	main.start_round()
	main.shop_sys.enter_shop()
	main.shop_sys.leave_shop()
	if main.state != "play" or main.round_n != 2:
		_fail(
			0,
			(
				"a run without a map did not go on to round 2 (state %s, round %d)"
				% [main.state, main.round_n]
			)
		)
