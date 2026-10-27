extends SceneTree
# Checks that a run walks the generated map (README Milestone D, "Replace linear round progression").
# Run from the project folder:
#   godot --headless --path . --script res://tools/map_walk_check.gd
# Optional argument after "--": how many seeds to walk (default 30).
# For every seed it starts a run on that seed (the CUSTOM SEED way) and plays the map from floor 1 to the final
# boss, always taking a different choice (first, last, second in turn), and checks that
#   - a run starts on the map screen with every floor 1 node as a choice, and picking one starts that round
#   - the round number is the floor number, and the node played is the one picked
#   - a shop node opens the shop screen and no round: no riders, no round time, the map comes back after it
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
	_check_empty_upgrade_pool()
	await _check_map_cash()
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
		var is_shop = str(floors[f][lane]["type"]) == "shop"
		var times_before = main.round_times.size()
		var shop_before = main.shop_buys
		main.pick_node(pick)
		# a fight node starts the round; a shop node (README alpha B2) opens the shop screen and no round
		var expected_state = "shop" if is_shop else "play"
		if main.state != expected_state:
			_fail(
				seed_value,
				(
					"picking a %s node on floor %d gave state %s, not %s"
					% [floors[f][lane]["type"], f + 1, main.state, expected_state]
				)
			)
			return
		if is_shop:
			_check_shop_node(seed_value, f)
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
		# finish the round the way the game does (README alpha B1): a fight node gives the upgrade screen and then
		# the map; a shop node is already in the shop and leaving it gives the map
		if is_shop:
			main.shop_sys.leave_shop()
		else:
			_check_upgrade_then_map(seed_value, f)
		if main.round_times.size() != times_before or main.shop_buys != shop_before:
			_fail(seed_value, "floor %d: a shop node changed round_times or shop_buys" % (f + 1))
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


# after a fight the upgrade pick goes straight to the map, not to the shop (README alpha B1.1)
func _check_upgrade_then_map(seed_value: int, f: int) -> void:
	main.shop_sys.enter_upgrade()
	if main.state != "upgrade" and main.state != "map":
		_fail(seed_value, "floor %d: after a fight the state is %s" % [f + 1, main.state])
		return
	if main.state == "upgrade":
		if main.offers.is_empty():
			_fail(seed_value, "floor %d: the upgrade screen has no offers" % (f + 1))
			return
		main.shop_sys.pick_upgrade(0)
	if main.state == "shop":
		_fail(seed_value, "floor %d: the upgrade pick went to the shop, not the map" % (f + 1))


# what a shop node leaves behind: no round, no riders, no round counted as cleared (README alpha B2.1 and B2.4)
func _check_shop_node(seed_value: int, f: int) -> void:
	if main.round_n != f + 1:
		_fail(seed_value, "the shop node on floor %d made round %d" % [f + 1, main.round_n])
	if not main.riders.is_empty() or not main.bosses.is_empty():
		_fail(seed_value, "the shop node on floor %d has riders or a boss" % (f + 1))
	if main.shop_items.is_empty():
		_fail(seed_value, "the shop node on floor %d offers nothing" % (f + 1))
	var heal_on_sale = false
	for it in main.shop_items:
		if it["kind"] == "heal":
			heal_on_sale = true
	# the heal is on sale exactly when the player is hurt (`shop_ok` in scripts/shop.gd), as in any other shop
	if heal_on_sale != (main.hearts < main.MAXHEARTS):
		_fail(seed_value, "the shop node on floor %d: heal on sale is %s" % [f + 1, heal_on_sale])
	if main.screens_passed() != _shops_before(f):
		_fail(seed_value, "screens_passed is %d on floor %d" % [main.screens_passed(), f + 1])


# shop nodes among the nodes walked before floor f (0-based)
func _shops_before(f: int) -> int:
	var n = 0
	for i in range(f):
		if str(main.run_map["floors"][i][main.map_path[i]]["type"]) == "shop":
			n += 1
	return n


# every upgrade bought out: the upgrade screen has nothing to pick and goes on to the map, not to the shop
func _check_empty_upgrade_pool() -> void:
	main.start_game(false, 77)
	main.pick_node(0)
	var saved = main.UPGRADES
	main.UPGRADES = []
	main.shop_sys.enter_upgrade()
	main.UPGRADES = saved
	if main.state != "map":
		_fail(77, "an empty upgrade pool led to state %s, not the map" % main.state)


# the map screen shows the cash (README alpha B1.2) and draws at two window sizes
func _check_map_cash() -> void:
	main.start_game(false, 78)
	main.cash = 123
	for s in [Vector2(1280.0, 720.0), Vector2(1920.0, 1080.0)]:
		main.hud.size = s
		for i in range(2):
			main.hud.queue_redraw()
			await process_frame
	main.hud.size = Vector2(1280.0, 720.0)
	main.cash = 0


# with no map the rounds go 1, 2, 3 ... as before
func _check_linear() -> void:
	main.start_game(false, 5)
	main.run_map = {}
	main.map_floor = -1
	main.round_n = 1
	main.start_round()
	# no map means no shop nodes, so the upgrade pick still leads to the shop (README alpha B1)
	main.shop_sys.enter_upgrade()
	main.shop_sys.pick_upgrade(0)
	if main.state != "shop":
		_fail(
			0, "a run without a map did not go from the upgrade pick to the shop (%s)" % main.state
		)
	main.shop_sys.leave_shop()
	if main.state != "play" or main.round_n != 2:
		_fail(
			0,
			(
				"a run without a map did not go on to round 2 (state %s, round %d)"
				% [main.state, main.round_n]
			)
		)
