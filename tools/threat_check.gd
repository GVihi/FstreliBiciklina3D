extends SceneTree
# Check for the threat list the edge arrows and the radar read (README Milestone K, Gameplay on open ground:
# "Threat arrows, radar and aim assist for attacks from every direction and distance"). Run from the project folder:
#   godot --headless --path . --script res://tools/threat_check.gd
# Exits with status 1 and prints the first problems.
#
# Step 2, the ranking (scripts/threats.gd): on the roundabout the strength of an arrow is the threat's own urgency,
# as it always was; on open ground a near threat beats a far one, one coming at the player beats one riding away,
# no arrow is weaker than MIN_STRENGTH or stronger than 1, twelve riders at different distances get the eight
# nearest approaching ones, and a tie keeps the list's order.
#
# Step 2 in the HUD: with twelve riders behind the player on open ground the HUD draws eight arrows, the eight
# nearest, strongest first; on the roundabout they are drawn by urgency alone (nothing changes there).
#
# Step 1, the list: every entry has pos, kind, urg, dist and closing, `dist` is the metres over the ground to the
# player and `closing` the speed towards the player over the ground (+ towards, - away, 0 for a boss or a phone).

const MAIN_SCENE = "res://main.tscn"
const Threats = preload("res://scripts/threats.gd")

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
	_check_ranking()
	await _check_hud()
	if problems.is_empty():
		print(
			"threat_check: the threat list gives distance and closing speed, and the arrows rank by them on open ground"
		)
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


func _t(urg: float, dist: float, closing: float) -> Dictionary:
	return {"pos": Vector3.ZERO, "kind": "rider", "urg": urg, "dist": dist, "closing": closing}


func _check_ranking() -> void:
	# the roundabout: the old rule, urgency alone, whatever the distance or the speed
	for t in [_t(0.3, 5.0, 12.0), _t(0.45, 70.0, -9.0), _t(1.0, 30.0, 0.0)]:
		if Threats.strength(t, false) != t["urg"]:
			_fail(
				(
					"on the roundabout the strength is %.3f, not the urgency %.3f"
					% [Threats.strength(t, false), t["urg"]]
				)
			)
	# open ground: near beats far, coming beats going
	if Threats.strength(_t(0.3, 10.0, 0.0), true) <= Threats.strength(_t(0.3, 50.0, 0.0), true):
		_fail("a near threat is not stronger than a far one")
	if Threats.strength(_t(0.3, 20.0, 10.0), true) <= Threats.strength(_t(0.3, 20.0, -10.0), true):
		_fail("a threat coming at the player is not stronger than one riding away")
	if Threats.strength(_t(0.3, 20.0, 10.0), true) <= Threats.strength(_t(0.3, 20.0, 0.0), true):
		_fail("a threat coming at the player is not stronger than one standing still")
	# a far rider coming fast against a near one riding away at the same urgency: the near one wins only if the
	# distance counts for more, which it does (the factors are 1.0 against 0.3 at most)
	if Threats.strength(_t(0.45, 6.0, -8.0), true) <= Threats.strength(_t(0.45, 60.0, 12.0), true):
		_fail("a near rider (riding away) is not stronger than a rider 60 m off")
	# bounds
	for dist in [0.0, 8.0, 30.0, 60.0, 500.0]:
		for closing in [-40.0, -12.0, 0.0, 12.0, 40.0]:
			for urg in [0.3, 0.6, 1.0]:
				var v = Threats.strength(_t(urg, dist, closing), true)
				if v < Threats.MIN_STRENGTH - 0.0001 or v > 1.0001:
					_fail(
						(
							"strength %.3f out of range (urg %.2f, dist %.0f, closing %.0f)"
							% [v, urg, dist, closing]
						)
					)
	# a threat on top of the player and a far one at the same urgency are both drawn: nothing falls below the floor
	if Threats.strength(_t(0.3, 500.0, -40.0), true) < Threats.MIN_STRENGTH - 0.0001:
		_fail("a far rider riding away has no arrow strength left")
	# twelve riders: the eight nearest (all approaching) are the ones drawn
	var list = []
	for i in range(12):
		list.append(_t(0.3, 10.0 + 4.0 * float(i), 8.0))
	list.reverse()  # the farthest first, so the order of the list does not give the answer away
	var ranked = Threats.ranked(list, true)
	if ranked.size() != 12:
		_fail("ranked gave %d threats for 12" % ranked.size())
	for i in range(Threats.MAX_ARROWS):
		if ranked[i]["dist"] > 10.0 + 4.0 * float(Threats.MAX_ARROWS - 1) + 0.01:
			_fail(
				(
					"arrow %d is a rider %.0f m off: the eight nearest should be drawn"
					% [i, ranked[i]["dist"]]
				)
			)
	for i in range(1, ranked.size()):
		if ranked[i]["strength"] > ranked[i - 1]["strength"] + 0.0001:
			_fail("ranked is not strongest first at %d" % i)
	# a tie keeps the list's order, and the input is not changed
	var tie = [_t(0.5, 20.0, 0.0), _t(0.5, 20.0, 0.0)]
	tie[0]["kind"] = "boss"
	var r2 = Threats.ranked(tie, true)
	if r2[0]["kind"] != "boss" or tie[0].has("strength"):
		_fail("a tie does not keep the list's order, or ranked changed its input")


# the real HUD draws the edge arrows: twelve riders all behind the player (off screen), at 12 to 56 m, all riding at
# the player, on a generated arena; then the same on the roundabout
func _check_hud() -> void:
	var hud = main.hud
	main.clear_riders()
	main.clear_bosses()
	main.state = "play"
	main.force_captured = true
	main.player.position = main.arena.start_position()
	main.yaw = 0.0
	main.pitch = 0.0
	var rs = main.rider_sys
	var behind = Vector3(0.0, 0.0, 1.0)  # the camera looks along -z at yaw 0, so +z is behind it
	for i in range(12):
		var p: Vector3 = main.player.position + behind * (12.0 + 4.0 * float(11 - i))  # the farthest first
		var r = _rider(p, rs.yaw_of(-behind), 8.0)
		r["mode"] = "fly"
	for f in range(4):
		await process_frame
	var open_arrows: Array = hud.arrows.duplicate()
	if open_arrows.size() != Threats.MAX_ARROWS:
		_fail(
			(
				"the HUD drew %d arrows for 12 riders behind the player, expected %d"
				% [open_arrows.size(), Threats.MAX_ARROWS]
			)
		)
	for i in range(open_arrows.size()):
		if open_arrows[i]["dist"] > 12.0 + 4.0 * float(Threats.MAX_ARROWS - 1) + 0.01:
			_fail(
				(
					"the HUD drew an arrow for a rider %.0f m off: the eight nearest should be drawn"
					% open_arrows[i]["dist"]
				)
			)
		if i > 0 and open_arrows[i]["strength"] > open_arrows[i - 1]["strength"] + 0.0001:
			_fail("the HUD's arrows are not strongest first")
	if (
		open_arrows.size() > 1
		and open_arrows[0]["strength"] <= open_arrows[open_arrows.size() - 1]["strength"]
	):
		_fail("the nearest rider's arrow is not stronger than the farthest drawn one")
	main.clear_riders()
