extends SceneTree
# Check for rider movement (README Milestone K, Foundation). Riders own a world position ("pos"), the way
# they face and ride ("yaw") and "hidden", and steer along their lane with limited turning. On the roundabout
# they have to ride exactly as the old street-coordinate code did, so this check runs that old code next to
# them: it integrates the same speeds as a street position x (wrapping at the seam, turning round and
# riding out when a rider gives up) and fails if a rider is ever more than TOL_POS metres from where the
# street code puts it, faces more than TOL_YAW radians away from the lane, is hidden when it should not
# be (away from the tunnel edge), or leaves the arena more than one step away from when the old code did.
# It also checks the model is where "pos" says, that parts fly off the way they used to, and that the
# obstacle avoidance steers a rider round the fountain.
#
# Run from the project folder:
#   godot --headless --path . --script res://tools/rider_check.gd
# Exits with status 1 and prints the first problems when something is wrong.

const SECONDS = 25.0
const TOL_POS = 0.15
const TOL_YAW = 0.12

var bad: Array = []
var fps = 60.0  # frames per second the check plays at: pass another one after "--" to try it
var dt = 1.0 / 60.0
var steps = 1500
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
	# the old street position of every rider: x, dir, whether it has entered, whether it is riding away
	var refs: Dictionary = {}
	var riders: Array = []
	for lane in range(3):
		for dir in [1, -1]:
			var r = main.rider_sys.spawn_rider(lane, dir)
			# some give up early, so the ride-away is covered on every lane and in both directions
			r["limit"] = 1.5 + 1.2 * float(lane) + (0.7 if dir > 0 else 0.0)
			riders.append(r)
			refs[r["idx"]] = {
				"x": -(hx + 2.0) if dir > 0 else hx + 2.0,
				"dir": dir,
				"entered": false,
				"away": false,
				"exit_step": -1,
				"gone_step": -1
			}
	var seen_hidden = false
	var seen_visible = false
	var left_arena = 0
	for step in range(steps):
		# keep the player out of the way so nobody gets run over mid-check
		main.player.position = Vector3(0.0, 0.0, 0.0)
		main.state = "play"
		for r in riders:
			var ref = refs[r["idx"]]
			if ref["gone_step"] >= 0:
				continue
			main.rider_sys.update_rider(r, dt)
			_step_reference(main, r, ref, step)
			if not main.riders.has(r):
				ref["gone_step"] = step
				left_arena += 1
				# gone when the street code's x has just passed 2.6 m beyond the seam (one step of the fastest ride is 39 m/s times dt)
				var over = absf(ref["x"]) - (hx + 2.6)
				if absf(over) > 39.0 * dt + 0.05:
					(
						bad
						. append(
							(
								"rider %d left the arena at step %d, %.2f m from where the street code has it"
								% [r["idx"], step, over]
							)
						)
					)
				continue
			if ref["exit_step"] >= 0 and step - ref["exit_step"] > 1:
				(
					bad
					. append(
						(
							"rider %d is still in the arena at step %d, the street code had it gone at %d"
							% [r["idx"], step, ref["exit_step"]]
						)
					)
				)
			_compare(main, r, ref, step)
			seen_hidden = seen_hidden or r["hidden"]
			seen_visible = seen_visible or not r["hidden"]
		if step == int(5.0 * fps):
			# an armoured hit uses the stored position too
			for r in riders:
				if r["mode"] == "fly" and not r["hidden"] and refs[r["idx"]]["gone_step"] < 0:
					main.rider_sys.hit_rider(r, 1)
					break
	if not seen_hidden or not seen_visible:
		bad.append("riders never both entered and left the tunnel block (check is not covering it)")
	if left_arena < riders.size() - 1:
		bad.append(
			(
				"only %d of %d riders rode away (check is not covering it)"
				% [left_arena, riders.size()]
			)
		)
	_check_parts(main)
	_check_avoidance(main)
	if bad.is_empty():
		print(
			(
				(
					"rider_check: riders ride the street code's path for %d steps, %d rode away"
					+ " (largest gap %.3f m and %.3f rad)"
				)
				% [steps, left_arena, max_pos_err, max_yaw_err]
			)
		)
		quit(0)
	else:
		for line in bad.slice(0, 10):
			printerr("rider_check: " + line)
		quit(1)


# the old movement code: x moves by dir * spd * dt, wraps once the rider has entered, and a rider that gives
# up turns towards the seam on its side and is gone 2.6 m past it
func _step_reference(main, r: Dictionary, ref: Dictionary, step: int) -> void:
	var hx = main.ARENA_HX
	if r["mode"] == "fly" or (r["mode"] == "away" and not ref["away"]):
		ref["x"] += ref["dir"] * r["spd"] * dt
		if not ref["entered"] and not main.arena.hidden(ref["x"]):
			ref["entered"] = true
		if ref["entered"]:
			if ref["x"] > hx:
				ref["x"] -= 2.0 * hx
			elif ref["x"] < -hx:
				ref["x"] += 2.0 * hx
		if r["mode"] == "away":
			ref["away"] = true
			ref["dir"] = -1 if ref["x"] < 0.0 else 1
			if absf(ref["x"]) < 0.6:
				# right in front of the player a few cm decide which seam is nearer: follow the rider
				ref["dir"] = r["dir"]
				ref["x"] = main.arena.to_track(r["pos"]).x
	elif ref["away"]:
		ref["x"] += ref["dir"] * r["spd"] * dt
		if absf(ref["x"]) > hx + 2.6 and ref["exit_step"] < 0:
			ref["exit_step"] = step


func _compare(main, r: Dictionary, ref: Dictionary, step: int) -> void:
	var lane_z = main.LANE_Z[r["ln"]]
	var tag = "step %d rider %d: " % [step, r["idx"]]
	var want_pos = main.arena.tw(ref["x"], lane_z, 0.0)
	max_pos_err = maxf(max_pos_err, r["pos"].distance_to(want_pos))
	if r["pos"].distance_to(want_pos) > TOL_POS:
		bad.append(tag + "pos %s, the street code gives %s" % [r["pos"], want_pos])
	var want_yaw = main.arena.yaw(ref["x"]) + (0.0 if ref["dir"] > 0 else PI)
	max_yaw_err = maxf(max_yaw_err, absf(wrapf(r["yaw"] - want_yaw, -PI, PI)))
	if absf(wrapf(r["yaw"] - want_yaw, -PI, PI)) > TOL_YAW:
		bad.append(tag + "yaw %f, the lane gives %f" % [r["yaw"], want_yaw])
	# hidden may differ only within a hair of the tunnel edge, where a few cm of path error decide it
	var edge = absf(absf(ref["x"]) - (hx_edge(main)))
	if r["hidden"] != main.arena.hidden(ref["x"]) and edge > 0.3:
		bad.append(
			tag + "hidden %s, the street code gives %s" % [r["hidden"], main.arena.hidden(ref["x"])]
		)
	var model: Node3D = r["model"]["root"]
	if Vector2(model.position.x - r["pos"].x, model.position.z - r["pos"].z).length() > 0.0001:
		bad.append(tag + "model is at %s, pos is %s" % [model.position, r["pos"]])
	# (the model's own yaw is read from its basis: Godot's Euler angles can come back as an equal turn)
	var facing = model.transform.basis * Vector3.RIGHT
	var heading = main.rider_sys.heading_vec(r["yaw"])
	if facing.distance_to(heading) > 0.0001:
		bad.append(tag + "model faces %s, yaw %f faces %s" % [facing, r["yaw"], heading])


func hx_edge(main) -> float:
	return main.ARENA_HX - 4.2  # Ring.HX - Ring.GATE_HALF: where the tunnel block starts


# parts thrown off a rider keep the old directions: forwards by dir * vx, up by vy, sideways by vz
func _check_parts(main) -> void:
	var r = main.rider_sys.spawn_rider(1, 1)
	var v = main.rider_sys.part_vel(r, 3.0, 2.0, 0.0)
	var ahead = main.rider_sys.heading_vec(r["yaw"]) * 3.0
	if Vector2(v.x - ahead.x, v.z - ahead.z).length() > 0.0001 or absf(v.y - 2.0) > 0.0001:
		bad.append("part_vel(vx=3, vy=2) is %s for a rider facing %s" % [v, ahead])
	var side = main.rider_sys.part_vel(r, 0.0, 0.0, 1.0)
	var fwd = main.rider_sys.heading_vec(r["yaw"])
	if absf(side.dot(fwd)) > 0.0001 or absf(side.length() - 1.0) > 0.0001:
		bad.append("part_vel sideways is %s, not a unit vector across the rider" % side)
	main.riders.erase(r)
	main.free_rider(r)


# a rider riding straight at the fountain, with avoidance on, must never end up inside it
func _check_avoidance(main) -> void:
	var pos = Vector3(0.0, 0.0, -9.0)
	var yaw = main.rider_sys.yaw_of(Vector3(0.0, 0.0, 1.0))  # towards the middle
	var speed = 8.0
	var entered_fountain = false
	var side = 1.0
	for step in range(240):
		var want = main.rider_sys.yaw_of(Vector3.ZERO - pos)  # keeps asking for the middle
		var steered = main.rider_sys.avoid_obstacles(pos, want, speed, yaw, side)
		if absf(wrapf(steered - yaw, -PI, PI)) > 0.0001:
			side = signf(wrapf(steered - yaw, -PI, PI))
		want = steered
		var turn = wrapf(want - yaw, -PI, PI)
		var max_turn = main.rider_sys.TURN_RATE * dt
		yaw += clampf(turn, -max_turn, max_turn)
		pos += main.rider_sys.heading_vec(yaw) * speed * dt
		if main.arena.obstacle_at(pos) and Vector2(pos.x, pos.z).length() < 2.3:
			entered_fountain = true
	if entered_fountain:
		bad.append("a rider with avoidance on rode into the fountain")
	# and the free case does nothing: a clear way ahead keeps the wanted yaw
	var clear = main.rider_sys.avoid_obstacles(Vector3(0.0, 0.0, -14.0), 0.5, 8.0, 0.0)
	if absf(clear - 0.5) > 0.0001:
		bad.append("avoid_obstacles changed a clear heading")
