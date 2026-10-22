extends SceneTree
# Check for pedestrian and cheerleader movement (README Milestone K, Foundation). A pedestrian owns a world
# position ("pos"), the way it faces and walks ("yaw") and "hidden", and steers along its lane with limited
# turning; a cheerleader carries a fixed "pos". On the roundabout pedestrians have to walk exactly as the old
# street-coordinate code did, so this check runs that old code next to them: it integrates the same speeds
# as a street position x (the walking speed, standing still while a tourist takes a photo, the flee speed
# after a hit) and fails if a pedestrian is ever more than TOL_POS metres from where the street code puts
# it, faces more than TOL_YAW radians away from the lane, is hidden when it should not be (away from the
# tunnel edge), or leaves the arena more than one step away from when the old code did. It also checks the
# model is where "pos" says, that the street keys x and z are gone (from pedestrians and cheerleaders), and
# that a pedestrian steers round an obstacle in its way and goes on past it.
#
# Run from the project folder:
#   godot --headless --path . --script res://tools/pedestrian_check.gd
# Pass a frame rate after "--" to try another one (default 60).
# Exits with status 1 and prints the first problems when something is wrong.

const SECONDS = 40.0
const TOL_POS = 0.15
const TOL_YAW = 0.12
const FLEE_SPEED = 6.6  # street metres per second after a hit (the old constant in pedestrians.gd)
const LEAVE_X = 2.4  # street metres past the seam where the old code removed a pedestrian

var bad: Array = []
var fps = 60.0
var dt = 1.0 / 60.0
var steps = 2400
var max_pos_err = 0.0
var max_yaw_err = 0.0


func _init() -> void:
	var main = load("res://main.tscn").instantiate()
	root.add_child(main)
	for i in range(3):
		await process_frame
	seed(7)
	var args = OS.get_cmdline_user_args()
	if args.size() > 0:
		fps = float(args[0])
	dt = 1.0 / fps
	steps = int(SECONDS * fps)
	main.start_game()
	main.state = "play"
	var hx = main.ARENA_HX
	# the old street position of every pedestrian we follow: x, dir, and whether it has been startled
	var tracked: Array = []
	for c in main.civs:  # the two start_game puts on the street
		tracked.append(_track(main, c, main.arena.to_track(c["pos"]).x))
	for k in range(10):
		main.civ_sys.spawn_civ()
		tracked.append(_track(main, main.civs[main.civs.size() - 1], null))
	var seen_hidden = false
	var seen_visible = false
	var left_arena = 0
	var fled = 0
	var fled_left = 0
	for step in range(steps):
		main.civ_t = 99.0  # no new random pedestrians: only the ones above
		# two pedestrians are startled part way through, so the flee is covered (only a visible one can be hit)
		if step == int(6.0 * fps) or step == int(9.0 * fps):
			for t in tracked:
				var c = t["civ"]
				if t["gone"] < 0 and c["state"] == "walk" and not c["hidden"]:
					main.civ_sys.hit_civ(c)
					t["hit"] = true
					break
		var before: Array = []
		for t in tracked:
			before.append(t["civ"]["state"] if t["gone"] < 0 else "")
		main.civ_sys.update_civs(dt)
		for i in range(tracked.size()):
			var t = tracked[i]
			if t["gone"] >= 0:
				continue
			var c = t["civ"]
			_step_reference(t, c, before[i])
			if not main.civs.has(c):
				t["gone"] = step
				left_arena += 1
				if t["fled"]:
					fled_left += 1
				# gone when the street code's x has just passed 2.4 m beyond the seam (one step of the fastest walk)
				var over = absf(t["x"]) - (hx + LEAVE_X)
				if absf(over) > FLEE_SPEED * dt + 0.05:
					(
						bad
						. append(
							(
								"pedestrian %d left the arena at step %d, %.2f m from where the street code has it"
								% [i, step, over]
							)
						)
					)
				continue
			if absf(t["x"]) > hx + LEAVE_X + FLEE_SPEED * dt + 0.05:
				(
					bad
					. append(
						(
							"pedestrian %d is still in the arena at step %d, the street code had it gone"
							% [i, step]
						)
					)
				)
			_compare(main, t, c, "step %d pedestrian %d: " % [step, i])
			if c["state"] == "flee" and not t["fled"]:
				t["fled"] = true
				fled += 1
			seen_hidden = seen_hidden or c["hidden"]
			seen_visible = seen_visible or not c["hidden"]
		main.hearts = 5  # a hit costs a life, so keep the run alive
		main.state = "play"
	if not seen_visible or not seen_hidden:
		bad.append(
			"pedestrians never both entered and left the tunnel block (check is not covering it)"
		)
	if left_arena < 3:
		bad.append(
			(
				"only %d of %d pedestrians left the arena (check is not covering it)"
				% [left_arena, tracked.size()]
			)
		)
	if fled == 0 or fled_left == 0:
		bad.append("no pedestrian was startled, fled and left (check is not covering it)")
	_check_cheerleaders(main)
	_check_avoidance(main)
	if bad.is_empty():
		print(
			(
				(
					"pedestrian_check: pedestrians walk the street code's path for %d steps, %d left, %d fled"
					+ " (largest gap %.3f m and %.3f rad)"
				)
				% [steps, left_arena, fled, max_pos_err, max_yaw_err]
			)
		)
		quit(0)
	else:
		for line in bad.slice(0, 10):
			printerr("pedestrian_check: " + line)
		quit(1)


# start following a pedestrian: its street x is the spawn point (init_x) or, by default, the one before the seam
func _track(main, c: Dictionary, init_x) -> Dictionary:
	var x0 = init_x
	if x0 == null:
		x0 = -(main.ARENA_HX + 1.8) if c["dir"] > 0 else (main.ARENA_HX + 1.8)
	if c.has("x") or c.has("z"):
		bad.append("a pedestrian has the street keys x or z again")
	return {"civ": c, "x": x0, "dir": c["dir"], "fled": false, "hit": false, "gone": -1}


# the old movement code: x moves by dir * spd * dt while it walks (not while a tourist takes a photo), a
# startled one stands still and then runs for the nearer end at the flee speed
func _step_reference(t: Dictionary, c: Dictionary, state_before: String) -> void:
	if state_before == "walk":
		var posing = c["type"] == "tourist" and c["photo"] > 0.0
		if not posing:
			t["x"] += t["dir"] * c["spd"] * dt
	elif state_before == "startled" and c["state"] == "flee":
		t["dir"] = -1 if t["x"] < 0.0 else 1
	elif state_before == "flee":
		t["x"] += t["dir"] * FLEE_SPEED * dt


func _compare(main, t: Dictionary, c: Dictionary, tag: String) -> void:
	var hx = main.ARENA_HX
	var want_pos = main.arena.tw(t["x"], c["lane_z"], 0.0)
	max_pos_err = maxf(max_pos_err, c["pos"].distance_to(want_pos))
	if c["pos"].distance_to(want_pos) > TOL_POS:
		bad.append(tag + "pos %s, the street code gives %s" % [c["pos"], want_pos])
	var want_yaw = main.arena.yaw(t["x"]) + (0.0 if t["dir"] > 0 else PI)
	var yaw_err = absf(wrapf(c["yaw"] - want_yaw, -PI, PI))
	max_yaw_err = maxf(max_yaw_err, yaw_err)
	if yaw_err > TOL_YAW:
		bad.append(tag + "yaw %f, the lane gives %f" % [c["yaw"], want_yaw])
	# hidden may differ only within a hair of the tunnel edge, where a few cm of path error decide it
	var edge = absf(absf(t["x"]) - (hx - 4.2))  # Ring.HX - Ring.GATE_HALF: where the tunnel block starts
	if c["hidden"] != main.arena.hidden(t["x"]) and edge > 0.3:
		bad.append(
			tag + "hidden %s, the street code gives %s" % [c["hidden"], main.arena.hidden(t["x"])]
		)
	var model: Node3D = c["model"]["root"]
	if Vector2(model.position.x - c["pos"].x, model.position.z - c["pos"].z).length() > 0.0001:
		bad.append(tag + "model is at %s, pos is %s" % [model.position, c["pos"]])
	# (the model's own yaw is read from its basis: Godot's Euler angles can come back as an equal turn)
	var facing = (model.transform.basis * Vector3.RIGHT).normalized()  # (a pedestrian model is scaled)
	var heading = main.rider_sys.heading_vec(c["yaw"])
	if facing.distance_to(heading) > 0.0001:
		bad.append(tag + "model faces %s, yaw %f faces %s" % [facing, c["yaw"], heading])


func _check_cheerleaders(main) -> void:
	for m in main.cheerleaders:
		if m.has("x"):
			bad.append("a cheerleader has the street key x again")
		if not m.has("pos"):
			bad.append("a cheerleader has no pos")
			continue
		var model_pos: Vector3 = m["root"].position
		if Vector2(model_pos.x - m["pos"].x, model_pos.z - m["pos"].z).length() > 0.0001:
			bad.append("cheerleader model is at %s, pos is %s" % [model_pos, m["pos"]])
		if model_pos.y < -0.0001:
			bad.append("cheerleader is below the ground: %s" % model_pos)


# On open ground the arena asks pedestrians to steer round obstacles (rider_avoidance). The roundabout never
# does, so this puts in an arena that does, with a post standing on the sidewalk in the way, and checks that
# a pedestrian walking along the sidewalk never ends up inside the post and still gets past it.
func _check_avoidance(main) -> void:
	var src = 'extends "res://scripts/arena_roundabout.gd"\n'
	src += "var post := Vector3.ZERO\n"
	src += "func rider_avoidance() -> bool:\n\treturn true\n"
	src += "func obstacle_at(p: Vector3) -> bool:\n"
	src += "\treturn Vector2(p.x - post.x, p.z - post.z).length() < 1.2\n"
	var script = GDScript.new()
	script.source_code = src
	if script.reload() != OK:
		bad.append("could not build the test arena for the avoidance check")
		return
	var real_arena = main.arena
	var mock = script.new()
	main.arena = mock
	var lane_z = main.SIDEWALK_Z
	var post_x = -2.0
	mock.post = mock.tw(post_x, lane_z, 0.0)
	main.civ_sys.spawn_civ(-6.0)
	var c = main.civs[main.civs.size() - 1]
	c["dir"] = 1
	c["lane_z"] = lane_z
	c["pos"] = mock.tw(-6.0, lane_z, 0.0)
	c["yaw"] = mock.yaw(-6.0)
	c["type"] = "walker"
	c["spd"] = 1.5
	c["avoid_side"] = 1.0
	var inside = false
	var closest = 99.0
	var swerved = false
	for step in range(int(30.0 * fps)):
		main.civ_sys.move_civ(c, c["spd"], dt)
		var d = Vector2(c["pos"].x - mock.post.x, c["pos"].z - mock.post.z).length()
		closest = minf(closest, d)
		if mock.obstacle_at(c["pos"]):
			inside = true
		if absf(wrapf(c["yaw"] - mock.yaw(mock.to_track(c["pos"]).x), -PI, PI)) > 0.2:
			swerved = true
	var x_end = mock.to_track(c["pos"]).x
	main.arena = real_arena
	main.civs.erase(c)
	c["model"]["root"].queue_free()
	if inside:
		bad.append("a pedestrian with avoidance on walked into the post (closest %.2f m)" % closest)
	if not swerved:
		bad.append("a pedestrian never swerved for the post (the avoidance is not covered)")
	if x_end < post_x + 1.5:
		(
			bad
			. append(
				(
					"a pedestrian with avoidance on did not get past the post (street x %.2f, post at %.2f)"
					% [x_end, post_x]
				)
			)
		)
