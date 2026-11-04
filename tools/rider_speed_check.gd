extends SceneTree
# Check for how fast riders get (README Milestone D "Balance pass", rider speed). Riders used to be 13% faster on every
# floor (2.2 times as fast on floor 10 as on floor 1) and a burst or a long ride could take them past 60 m/s. Now
# the growth per floor is `ROUND_SPEED_GROWTH`, the floor 1 speed is unchanged, and no rider aims faster than
# `RIDER_SPEED_CAP`, however big its burst, however old it is and whatever its type. Checks the base speed of every
# type on every floor, and a rider that is told to aim at 1000 m/s on an arena where it never gives up.
#
# Run from the project folder:
#   godot --headless --path . --script res://tools/rider_speed_check.gd
# Exits with status 1 and prints the first problems when something is wrong.

const Riders = preload("res://scripts/riders.gd")
const SEED = 0x1234ABCD
const DT = 1.0 / 60.0
const FLOOR_1_PRO = 8.25  # metres per second: 165 * RIDER_SCALE for a pro rider on floor 1 with nobody sent yet

var bad: Array = []
var main = null


func _init() -> void:
	main = load("res://main.tscn").instantiate()
	main.generated_arena = true
	root.add_child(main)
	for i in range(3):
		await process_frame
	main.start_game(false, SEED)
	main.pick_node(0)
	if main.state != "play":
		bad.append("could not start a round (state %s)" % main.state)
	else:
		_check_growth()
		_check_cap()
	if bad.is_empty():
		print(
			(
				"rider_speed_check: %.1f m/s on floor 1, %.1f m/s on floor 10 for a pro rider, nothing aims over %.0f m/s"
				% [_pro_base(1), _pro_base(10), Riders.RIDER_SPEED_CAP]
			)
		)
		quit(0)
	else:
		for line in bad.slice(0, 12):
			printerr("rider_speed_check: " + line)
		quit(1)


# the base speed a pro rider spawns with on this floor, with nobody sent yet: a rider of any type, divided by its
# type's speed factor
func _pro_base(floor_no: int) -> float:
	main.round_n = floor_no
	main.next_idx = 0
	var r = main.rider_sys.spawn_rider(0, 1)
	var base = float(r["base"]) / float(main.TYPES[r["type"]]["sp"])
	main.clear_riders()
	return base


func _check_growth() -> void:
	var last = 0.0
	for floor_no in range(1, 11):
		var want = FLOOR_1_PRO * (1.0 + float(floor_no - 1) * Riders.ROUND_SPEED_GROWTH)
		# several riders, so every type is seen: each one is the pro speed times its type's factor
		for i in range(6):
			main.round_n = floor_no
			main.next_idx = 0
			var r = main.rider_sys.spawn_rider(0, 1)
			var type_sp = float(main.TYPES[r["type"]]["sp"])
			if absf(float(r["base"]) - want * type_sp) > 0.01:
				bad.append(
					(
						"floor %d: a %s rider has base speed %.2f, expected %.2f"
						% [floor_no, r["type"], r["base"], want * type_sp]
					)
				)
			main.clear_riders()
		if want <= last:
			bad.append("floor %d is not faster than the floor before" % floor_no)
		last = want
	var growth = _pro_base(10) / _pro_base(1)
	if growth > 1.6:
		bad.append("a pro rider is %.2f times as fast on floor 10 as on floor 1, over 1.6" % growth)
	if absf(_pro_base(1) - FLOOR_1_PRO) > 0.01:
		bad.append(
			"floor 1 changed: a pro rider has %.2f m/s, expected %.2f" % [_pro_base(1), FLOOR_1_PRO]
		)
	# riders sent later in a round are a little faster still, but never past the cap's reach on their own
	main.round_n = 10
	main.next_idx = 10
	var r2 = main.rider_sys.spawn_rider(0, 1)
	if float(r2["base"]) > Riders.RIDER_SPEED_CAP * 1.4:
		bad.append("the last rider of floor 10 starts at %.1f m/s, far over the cap" % r2["base"])
	main.clear_riders()
	main.next_idx = 0


# a rider that is old, bursting and told to aim at 1000 m/s must stop at the cap
func _check_cap() -> void:
	main.round_n = 10
	main.next_idx = 0
	var r = main.rider_sys.spawn_rider(0, 1)
	if r["limit"] < 100000.0:
		bad.append(
			(
				"the rider has a time limit of %.1f s, so it could give up and ride out faster"
				% r["limit"]
			)
		)
	r["age"] = 1000.0
	r["tgt"] = 1000.0
	r["chg"] = 1000.0
	r["spd"] = 1.0
	var state_before = main.state
	main.state = "check"  # nobody gets run over, and a finished rider does not end the round
	var top = 0.0
	for i in range(600):
		main.rider_sys.update_rider(r, DT)
		r["chg"] = 1000.0  # keep the burst
		r["tgt"] = 1000.0
		top = maxf(top, float(r["spd"]))
	main.state = state_before
	if top > Riders.RIDER_SPEED_CAP + 0.05:
		bad.append(
			(
				"a rider told to aim at 1000 m/s reached %.2f m/s, over the cap %.1f"
				% [top, Riders.RIDER_SPEED_CAP]
			)
		)
	if top < Riders.RIDER_SPEED_CAP - 0.5:
		bad.append(
			(
				"a rider told to aim at 1000 m/s only reached %.2f m/s, the cap is %.1f"
				% [top, Riders.RIDER_SPEED_CAP]
			)
		)
	main.clear_riders()
