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
	_check_radar_scale()
	_check_aim_assist()
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


# Step 3, the radar scale (Threats.radar_fraction): the roundabout keeps its straight 26 m scale; on open ground the
# scale reaches 60 m, never goes backwards, stays between 0 and 1, and gives a rider 10 m off more room from one 20 m
# off than the straight scale would.
func _check_radar_scale() -> void:
	for dist in [0.0, 5.0, 13.0, 26.0, 40.0, 500.0]:
		var want = minf(dist / 26.0, 1.0)
		if absf(Threats.radar_fraction(dist, false) - want) > 0.0001:
			_fail(
				(
					"on the roundabout the radar puts %.0f m at %.3f, not %.3f"
					% [dist, Threats.radar_fraction(dist, false), want]
				)
			)
	var last = -1.0
	for i in range(0, 121):
		var v = Threats.radar_fraction(float(i) * 2.0, true)
		if v < 0.0 or v > 1.0001:
			_fail("the open ground radar puts %.0f m at %.3f, outside 0 to 1" % [float(i) * 2.0, v])
		if v < last - 0.0001:
			_fail("the open ground radar goes backwards at %.0f m" % [float(i) * 2.0])
		last = v
	if Threats.radar_fraction(0.0, true) > 0.0001:
		_fail("a threat on top of the player is not at the radar's centre")
	if Threats.radar_fraction(Threats.RADAR_RANGE_OPEN, true) < 0.9999:
		_fail("a threat at the open ground range is not on the rim")
	# a far rider is on the radar, not piled on the rim: 40 m is inside the rim on open ground (it is on the rim on
	# the roundabout), and two riders 10 m and 20 m off are farther apart than on a straight 60 m scale
	if Threats.radar_fraction(40.0, true) >= 0.99:
		_fail("a rider 40 m off is on the rim of the open ground radar")
	var gap = Threats.radar_fraction(20.0, true) - Threats.radar_fraction(10.0, true)
	if gap <= (20.0 - 10.0) / Threats.RADAR_RANGE_OPEN:
		_fail("near riders have no more room on the open ground radar than on a straight scale")


# Step 4, aim assist (Threats.assist_cone, Threats.sight_clear, Player.apply_aim_assist): the roundabout keeps the
# fixed 8 degree cone and has no sight rule; on open ground the cone narrows with distance (never wider than 8
# degrees, never reaching more than ASSIST_REACH metres to the side), a target behind a building does not pull the
# crosshair and one in the open does.
func _check_aim_assist() -> void:
	for dist in [1.0, 10.0, 40.0, 90.0]:
		if absf(Threats.assist_cone(dist, false) - deg_to_rad(8.0)) > 0.0001:
			_fail("the roundabout's assist cone at %.0f m is not 8 degrees" % dist)
		var cone = Threats.assist_cone(dist, true)
		if cone > deg_to_rad(8.0) + 0.0001:
			_fail("the open ground assist cone at %.0f m is wider than 8 degrees" % dist)
		if tan(cone) * dist > Threats.ASSIST_REACH + 0.0001:
			_fail(
				(
					"the open ground assist cone at %.0f m reaches %.2f m to the side"
					% [dist, tan(cone) * dist]
				)
			)
	if Threats.assist_cone(90.0, true) >= Threats.assist_cone(40.0, true):
		_fail("the open ground assist cone does not narrow with distance")
	# the real arena: a rider in the open pulls the crosshair, the same rider behind a building does not
	main.clear_riders()
	main.clear_bosses()
	main.state = "play"
	main.aim_assist = 1.0
	var arena = main.arena
	var found = false
	for seed_value in [0x9E378A43, 1, 2, 3, 4, 5, 6, 7]:
		main.start_game(false, seed_value)
		main.state = "check"
		arena = main.arena
		var spot = _wall_spot(arena)
		if spot.is_empty():
			continue
		found = true
		var eye = spot["open"] + Vector3(0.0, 1.5, 0.0)
		var target = spot["behind"] + Vector3(0.0, 1.2, 0.0)
		var clear_target = spot["open_far"] + Vector3(0.0, 1.2, 0.0)
		if Threats.sight_clear(arena, eye, target):
			_fail("seed %X: a point behind a building is in sight" % seed_value)
		if not Threats.sight_clear(arena, eye, clear_target):
			_fail("seed %X: a point in the open is not in sight" % seed_value)
		break
	if not found:
		_fail("no generated arena in 8 seeds had a spot with a building between two open points")
	main.aim_assist = 0.6
	# back to the arena the other steps use
	main.start_game(false, 0x9E378A43)
	main.state = "check"
	main.hits.resize(400)
	main.hits.fill(false)


# a point on open ground, a point 4 m or more from it behind a building and a third point in the open the same
# distance away; empty if the arena has none (found by walking the grid, never random)
func _wall_spot(arena) -> Dictionary:
	var step = 2.0
	var start: Vector3 = arena.start_position()
	for ix in range(-20, 21):
		for iz in range(-20, 21):
			var a = start + Vector3(float(ix) * step, 0.0, float(iz) * step)
			if arena.obstacle_at(a):
				continue
			for dir in [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]:
				var wall_at = -1.0
				var behind_at = -1.0
				var l = 1.0
				while l < 20.0:
					var p = a + dir * l
					if wall_at < 0.0 and arena.ray_blocked(Vector3(p.x, 1.5, p.z)):
						wall_at = l
					elif (
						wall_at > 0.0
						and not arena.ray_blocked(Vector3(p.x, 1.2, p.z))
						and not arena.obstacle_at(p)
					):
						behind_at = l
						break
					l += 1.0
				if wall_at > 0.0 and behind_at > wall_at:
					# the open point in the opposite direction, the same distance away
					var far = a - dir * behind_at
					if (
						not arena.obstacle_at(far)
						and Threats.sight_clear(
							arena, a + Vector3(0, 1.5, 0), far + Vector3(0, 1.2, 0)
						)
					):
						return {"open": a, "behind": a + dir * behind_at, "open_far": far}
	return {}


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
