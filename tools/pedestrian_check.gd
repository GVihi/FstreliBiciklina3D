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
# On open ground (an arena where rider_pursuit() is true) pedestrians have no street. The check puts in 12
# real generated arenas and spawns pedestrians on each: every one must start hidden in a gate's tunnel (1 m
# out from the gate, facing in) with a goal gate (a different one where there is another), come out of the
# tunnel within 10 s, never stand deep inside a building while visible, and leave the arena by being back in
# a gate's tunnel (90 % of them within 240 s of walking; the rest may be stuck behind a building, which is
# what the walls do to a pedestrian that has no path search).
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

const ArenaGenScript = preload("res://scripts/arena_gen.gd")
const GeneratedArena = preload("res://scripts/arena_generated.gd")
const OPEN_ARENAS = 12  # generated arenas the open-ground check walks pedestrians on
const OPEN_PER_ARENA = 6  # pedestrians spawned on each
const OPEN_SECONDS = 240.0  # how long they get to leave (150 on the old 96 m arena; the 144 m one is 1.5 times as far across)
const OPEN_DT = 1.0 / 20.0
const OPEN_EMERGE = 10.0  # seconds: a pedestrian is out of its start tunnel by then
const OPEN_MIN_LEFT = 0.9  # the share that must have left within OPEN_SECONDS
const WALL_DEPTH = 0.3  # metres: a pedestrian this far inside a building (all four ways) is "deep in a wall"

var bad: Array = []
var fps = 60.0
var dt = 1.0 / 60.0
var steps = 2400
var max_pos_err = 0.0
var max_yaw_err = 0.0
var open_summary = ""


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
	_check_open_ground(main)
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
		print("pedestrian_check: " + open_summary)
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


# Open ground: real generated arenas, pedestrians spawned with the arena's own rules (see the header).
func _check_open_ground(main) -> void:
	var rules = ArenaGenScript.load_rules()
	var real_arena = main.arena
	var rs = main.rider_sys
	var spawned = 0
	var left = 0
	var left_hidden = 0
	var arenas = 0
	var gates_used = {}
	var slowest = 0.0
	var deep_steps = 0
	var fled = 0
	for k in range(OPEN_ARENAS):
		var layout = ArenaGenScript.generate(5000 + k * 101, rules)
		if layout.is_empty():
			continue
		arenas += 1
		var arena = GeneratedArena.new(layout, rules)
		main.arena = arena
		_clear_civs(main)
		for n in range(OPEN_PER_ARENA):
			main.civ_sys.spawn_civ()
		var mine: Array = main.civs.duplicate()
		var tag = "open ground, seed %d: " % (5000 + k * 101)
		if mine.size() != OPEN_PER_ARENA:
			bad.append(tag + "spawned %d pedestrians, asked for %d" % [mine.size(), OPEN_PER_ARENA])
		var out_at = {}
		var gone_at = {}
		for c in mine:
			spawned += 1
			if c.has("x") or c.has("z"):
				bad.append(tag + "a pedestrian has the street keys x or z")
			var gate = _nearest_gate(arena, c["pos"])
			gates_used[str(k) + str(gate["pos"])] = true
			var d = Vector2(c["pos"].x - gate["pos"].x, c["pos"].z - gate["pos"].z).length()
			if absf(d - rs.GATE_SPAWN) > 0.01 or not c["hidden"]:
				bad.append(
					tag + "a pedestrian starts %.2f m from a gate, hidden %s" % [d, c["hidden"]]
				)
			if rs.heading_vec(c["yaw"]).dot(gate["outward"]) > -0.99:
				bad.append(tag + "a pedestrian does not start facing into the arena")
			if not arena.gates().has(c["goal"]):
				bad.append(tag + "a pedestrian has a goal that is not one of the gates")
			elif arena.gates().size() > 1 and c["goal"]["pos"] == gate["pos"]:
				bad.append(tag + "a pedestrian's goal is the gate it started at")
		# startle one that is out in the open: it must then run for the gate nearest to where it was hit
		var t = 0.0
		var startled = null
		var startled_gate = {}
		while t < OPEN_SECONDS and gone_at.size() < mine.size():
			if startled == null and t > 12.0:
				for c in mine:
					if main.civs.has(c) and not c["hidden"] and c["state"] == "walk":
						startled = c
						startled_gate = _nearest_gate(arena, c["pos"])
						main.civ_sys.hit_civ(c)
						main.hearts = 5
						main.state = "play"
						break
			main.civ_t = 99.0
			main.civ_sys.update_civs(OPEN_DT)
			t += OPEN_DT
			for c in mine:
				if gone_at.has(c):
					continue
				if not main.civs.has(c):
					gone_at[c] = t
					if c["entered"] and c["hidden"]:
						left_hidden += 1
					else:
						bad.append(tag + "a pedestrian was removed while not in a gate's tunnel")
					continue
				if not c["hidden"]:
					out_at[c] = true
				elif t > OPEN_EMERGE and not out_at.has(c) and not c["entered"]:
					bad.append(
						tag + "a pedestrian is still in its start tunnel after %d s" % int(t)
					)
					out_at[c] = true
				if not c["hidden"] and _deep_in_wall(arena, c["pos"]):
					deep_steps += 1
					if deep_steps <= 3:
						bad.append(
							tag + "a pedestrian stands deep inside a building at %s" % c["pos"]
						)
				var model: Node3D = c["model"]["root"]
				if (
					Vector2(model.position.x - c["pos"].x, model.position.z - c["pos"].z).length()
					> 0.0001
				):
					bad.append(tag + "a pedestrian's model is not at its pos")
		if startled != null:
			fled += 1
			if startled["state"] != "flee" or startled["goal"]["pos"] != startled_gate["pos"]:
				bad.append(tag + "a startled pedestrian does not run for the nearest gate")
			if not gone_at.has(startled):
				bad.append(tag + "a startled pedestrian never got away")
		for c in mine:
			if gone_at.has(c):
				left += 1
				slowest = maxf(slowest, gone_at[c])
		_clear_civs(main)
	main.arena = real_arena
	_clear_civs(main)
	if arenas < OPEN_ARENAS - 2:
		bad.append(
			(
				"open ground: only %d of %d seeds gave an arena (check is not covering it)"
				% [arenas, OPEN_ARENAS]
			)
		)
	if spawned > 0 and float(left) / float(spawned) < OPEN_MIN_LEFT:
		bad.append(
			(
				"open ground: only %d of %d pedestrians left within %d s"
				% [left, spawned, int(OPEN_SECONDS)]
			)
		)
	if gates_used.size() < arenas:
		bad.append("open ground: pedestrians used too few gates (check is not covering it)")
	if fled < arenas / 2:
		bad.append(
			"open ground: only %d pedestrians were startled (check is not covering it)" % fled
		)
	open_summary = (
		"open ground: %d pedestrians on %d generated arenas, %d left through a gate tunnel, %d startled ones ran for the nearest gate (slowest %.0f s)"
		% [spawned, arenas, left_hidden, fled, slowest]
	)


func _nearest_gate(arena, pos: Vector3) -> Dictionary:
	var best = {}
	var best_d = INF
	for gate in arena.gates():
		var d = Vector2(gate["pos"].x - pos.x, gate["pos"].z - pos.z).length()
		if d < best_d:
			best_d = d
			best = gate
	return best


# true if every point WALL_DEPTH metres off p (towards +x, -x, +z and -z) is a building a rider cannot ride through
func _deep_in_wall(arena, p: Vector3) -> bool:
	for off in [
		Vector3(WALL_DEPTH, 0, 0),
		Vector3(-WALL_DEPTH, 0, 0),
		Vector3(0, 0, WALL_DEPTH),
		Vector3(0, 0, -WALL_DEPTH)
	]:
		if not arena.rider_blocked(p + off):
			return false
	return arena.rider_blocked(p)


func _clear_civs(main) -> void:
	for c in main.civs:
		c["model"]["root"].queue_free()
	main.civs.clear()
