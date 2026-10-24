extends SceneTree
# Check for the threat list the edge arrows and the radar read (README Milestone K, Gameplay on open ground:
# "Threat arrows, radar and aim assist for attacks from every direction and distance"). Run from the project folder:
#   godot --headless --path . --script res://tools/threat_check.gd
# Exits with status 1 and prints the first problems.
#
# Step 1, the list: every entry has pos, kind, urg, dist and closing, `dist` is the metres over the ground to the
# player and `closing` the speed towards the player over the ground (+ towards, - away, 0 for a boss or a phone).

const MAIN_SCENE = "res://main.tscn"

var problems = []
var main = null


func _initialize() -> void:
	main = load(MAIN_SCENE).instantiate()
	main.generated_arena = true
	root.add_child(main)
	for i in range(3):
		await process_frame
	seed(3)
	main.start_game(false, 0x9E378A43)
	main.state = "check"
	main.hits.resize(400)
	main.hits.fill(false)
	_check_list()
	if problems.is_empty():
		print("threat_check: the threat list gives distance and closing speed")
		quit(0)
	else:
		print("threat_check: %d problem(s)" % problems.size())
		for p in problems.slice(0, 12):
			print("  " + p)
		quit(1)


func _fail(text: String) -> void:
	problems.append(text)


func _rider(pos: Vector3, yaw: float, speed: float) -> Dictionary:
	var r = main.rider_sys.spawn_rider(0, 1)
	r["can_throw"] = false
	r["pos"] = pos
	r["yaw"] = yaw
	r["hidden"] = false
	r["entered"] = true
	r["ride_speed"] = speed
	return r


func _check_list() -> void:
	main.clear_riders()
	main.clear_bosses()
	main.player.position = Vector3(10.0, 0.0, 10.0)
	var rs = main.rider_sys
	# one rider 20 m to the west riding east at 8 m/s (towards the player), one 5 m north riding north at 6 m/s (away)
	_rider(Vector3(-10.0, 0.0, 10.0), rs.yaw_of(Vector3.RIGHT), 8.0)
	_rider(Vector3(10.0, 0.0, 5.0), rs.yaw_of(Vector3(0.0, 0.0, -1.0)), 6.0)
	var list = main.threat_list()
	if list.size() != 2:
		_fail("expected 2 threats, got %d" % list.size())
		return
	for t in list:
		for key in ["pos", "kind", "urg", "dist", "closing"]:
			if not t.has(key):
				_fail("a threat has no %s" % key)
				return
	var near = list[0] if list[0]["dist"] < list[1]["dist"] else list[1]
	var far = list[1] if near == list[0] else list[0]
	if absf(far["dist"] - 20.0) > 0.01 or absf(near["dist"] - 5.0) > 0.01:
		_fail("distances %.2f and %.2f, expected 20 and 5" % [far["dist"], near["dist"]])
	if absf(far["closing"] - 8.0) > 0.01:
		_fail("the rider coming at the player closes at %.2f m/s, expected 8" % far["closing"])
	if absf(near["closing"] + 6.0) > 0.01:
		_fail("the rider riding away closes at %.2f m/s, expected -6" % near["closing"])
	# a boss and a phone have no velocity: closing 0, and the distance counts over the ground only
	main.player.position = Vector3(10.0, 3.0, 10.0)
	var e = main.threat_entry(Vector3(10.0, 9.0, 14.0), "boss", 0.6)
	if absf(e["dist"] - 4.0) > 0.01 or e["closing"] != 0.0:
		_fail(
			"a boss entry has dist %.2f closing %.2f, expected 4 and 0" % [e["dist"], e["closing"]]
		)
	main.clear_riders()
