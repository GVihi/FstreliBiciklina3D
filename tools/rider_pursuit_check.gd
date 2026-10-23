extends SceneTree
# Check for rider pursuit on open ground (README Milestone K, Gameplay on open ground). On an arena that says
# rider_pursuit() a rider comes out of a gate, rides at the player on any surface, rides straight on for a
# while after it has passed, swings round in an arc no tighter than its speed allows and comes back, again and
# again, steers round obstacles, keeps a share of its speed set by the ground under it, and when it gives up it
# rides out of the nearest gate. The roundabout does none of this (its rider_pursuit() is false and
# tools/rider_check.gd covers it), so this builds a flat test arena with two gates and a post and plays riders
# on it.
#
# Run from the project folder:
#   godot --headless --path . --script res://tools/rider_pursuit_check.gd
# Exits with status 1 and prints the first problems when something is wrong.

const SECONDS = 60.0
const MIN_PASSES = 3
const POST_RADIUS = 1.2
const GRASS_X = 40.0

var bad: Array = []
var fps = 60.0  # frames per second the check plays at: pass another one after "--" to try it
var dt = 1.0 / 60.0
var main = null
var mock = null


func _init() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	for i in range(3):
		await process_frame
	seed(7)
	var args = OS.get_cmdline_user_args()
	if args.size() > 0:
		fps = float(args[0])
	dt = 1.0 / fps
	main.start_game()
	mock = _make_arena()
	if mock == null:
		bad.append("could not build the test arena")
		_finish("")
		return
	main.arena = mock
	# not "play": nobody gets run over mid-check and a finished rider does not end the round
	main.state = "check"
	main.player.position = Vector3.ZERO
	# riders spawned here get indexes past the end of the round's hit list: make room
	main.hits.resize(400)
	main.hits.fill(false)
	var summary = ""
	summary += _check_spawn()
	summary += _check_chase()
	summary += _check_avoidance()
	summary += _check_surface_speed()
	summary += _check_give_up()
	summary += _check_give_up_close()
	summary += _check_roundabout_unchanged()
	_finish(summary)


func _finish(summary: String) -> void:
	if bad.size() > 0:
		print("rider_pursuit_check: %d problem(s)" % bad.size())
		for b in bad.slice(0, 12):
			print("  " + b)
		quit(1)
		return
	print("rider_pursuit_check: " + summary.strip_edges())
	quit(0)


# a flat arena with open ground everywhere, a gate at each end (x = -30 and x = 30, tunnels outside them), a
# post standing between the west gate and the player, and grass beyond x = GRASS_X
func _make_arena():
	var src = 'extends "res://scripts/arena_roundabout.gd"\n'
	src += "var gate_list: Array = []\n"
	src += "var post := Vector3(-12.0, 0.0, 0.0)\n"
	src += "var grass_x := 40.0\n"
	src += "func rider_pursuit() -> bool:\n\treturn true\n"
	src += "func rider_avoidance() -> bool:\n\treturn true\n"
	src += "func gates() -> Array:\n\treturn gate_list\n"
	src += "func obstacle_at(p: Vector3) -> bool:\n"
	src += "\treturn Vector2(p.x - post.x, p.z - post.z).length() < 1.2\n"
	src += "func rider_speed_at(p: Vector3) -> float:\n"
	src += "\treturn 0.75 if p.x > grass_x else 1.0\n"
	src += "func hidden_at(p: Vector3) -> bool:\n"
	src += "\tfor gate in gate_list:\n"
	src += "\t\tvar d = p - gate['pos']\n"
	src += "\t\tvar along = d.dot(gate['outward'])\n"
	src += "\t\tvar across = absf(d.cross(gate['outward']).y)\n"
	src += "\t\tif along > 0.0 and across < gate['half_width']:\n\t\t\treturn true\n"
	src += "\treturn false\n"
	var script = GDScript.new()
	script.source_code = src
	if script.reload() != OK:
		return null
	var a = script.new()
	a.gate_list = [
		{"pos": Vector3(-30.0, 0.0, 0.0), "outward": Vector3(-1.0, 0.0, 0.0), "half_width": 3.0},
		{"pos": Vector3(30.0, 0.0, 0.0), "outward": Vector3(1.0, 0.0, 0.0), "half_width": 3.0}
	]
	return a


func _new_rider(lane: int) -> Dictionary:
	var r = main.rider_sys.spawn_rider(lane, 1)
	r["can_throw"] = false
	r["limit"] = 100000.0
	return r


func _planar(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


# riders start inside a gate's tunnel (hidden), facing out of it, and all start at one of the gates
func _check_spawn() -> String:
	var seen_gate = {}
	for k in range(12):
		var r = _new_rider(k % 3)
		var best = INF
		var best_i = -1
		for i in range(mock.gate_list.size()):
			var gate = mock.gate_list[i]
			var d = _planar(r["pos"], gate["pos"])
			if d < best:
				best = d
				best_i = i
		var gate = mock.gate_list[best_i]
		seen_gate[best_i] = true
		if absf(best - main.rider_sys.GATE_DEPTH) > 0.01:
			bad.append(
				"a rider started %.2f m from a gate, not %.1f m" % [best, main.rider_sys.GATE_DEPTH]
			)
		if not r["hidden"]:
			bad.append("a rider started in the open, not inside the gate's tunnel")
		var face = main.rider_sys.heading_vec(r["yaw"])
		if face.dot(-gate["outward"]) < 0.99:
			bad.append("a rider started facing out of the arena instead of into it")
		main.riders.erase(r)
		main.free_rider(r)
	if seen_gate.size() < 2:
		bad.append("12 riders all came out of the same gate (the gate is not drawn from the seed)")
	return "riders start hidden in a gate, facing in (both gates used)"


# one rider that never gives up, with the player in the middle and nothing in the way
func _check_chase() -> String:
	var rs = main.rider_sys
	mock.post = Vector3(1000.0, 0.0, 1000.0)
	var r = _new_rider(0)
	var steps = int(SECONDS * fps)
	var prev_yaw = r["yaw"]
	var max_dyaw = 0.0
	var worst_rate_ratio = 0.0
	var entered_step = -1
	var passes = 0
	var min_first = INF
	var was_far = true
	var near_now = false
	var overshoot_start = Vector3.ZERO
	var overshoot_yaw = 0.0
	var overshoots = 0
	var overshoot_short = 0.0
	var overshoot_drift = 0.0
	var prev_mode = "chase"
	var turned_back = 0
	var min_turn_radius = INF
	var max_sideways = 0.0
	for step in range(steps):
		main.player.position = Vector3.ZERO
		main.state = "check"
		rs.update_rider(r, dt)
		if r["entered"] and entered_step < 0:
			entered_step = step
		var pos: Vector3 = r["pos"]
		var d_player = _planar(pos, Vector3.ZERO)
		# the turn: never faster than the arc limit, and never a snap
		var dyaw = absf(wrapf(r["yaw"] - prev_yaw, -PI, PI))
		prev_yaw = r["yaw"]
		max_dyaw = maxf(max_dyaw, dyaw)
		var limit = r["turn_rate"] * dt
		if dyaw > limit + 0.0005:
			worst_rate_ratio = maxf(worst_rate_ratio, dyaw / maxf(limit, 0.000001))
		# the arc: the sideways acceleration (speed times turn rate) stays within PURSUIT_ACCEL
		if (
			r["turn_rate"] * r["ride_speed"] > rs.PURSUIT_ACCEL + 0.01
			and r["turn_rate"] < rs.PURSUIT_MAX_TURN - 0.001
		):
			max_sideways = maxf(max_sideways, r["turn_rate"] * r["ride_speed"])
		if dyaw > 0.0005 and not r["hidden"]:
			min_turn_radius = minf(min_turn_radius, r["ride_speed"] * dt / dyaw)
		# passes: from far away (more than 12 m) to within 3 m of the player
		if d_player > 12.0:
			was_far = true
		if d_player < 3.0 and was_far and not r["hidden"]:
			passes += 1
			was_far = false
		if passes <= 1:
			min_first = minf(min_first, d_player)
		# straight on after a pass
		if r["pursuit"] == "overshoot" and prev_mode == "chase":
			overshoot_start = pos
			overshoot_yaw = r["yaw"]
			overshoots += 1
		if r["pursuit"] == "overshoot":
			overshoot_drift = maxf(overshoot_drift, absf(wrapf(r["yaw"] - overshoot_yaw, -PI, PI)))
		if r["pursuit"] == "chase" and prev_mode == "overshoot":
			turned_back += 1
			var ridden = _planar(pos, overshoot_start)
			if ridden < rs.OVERSHOOT - 2.0:
				overshoot_short = maxf(overshoot_short, rs.OVERSHOOT - ridden)
		prev_mode = r["pursuit"]
		if not main.riders.has(r):
			bad.append("a rider that never gives up left the arena at step %d" % step)
			break
	if entered_step < 0 or float(entered_step) / fps > 3.0:
		bad.append("the rider did not come out of its gate within 3 s")
	if min_first > 2.0:
		bad.append("the rider never rode at the player (closest first approach %.2f m)" % min_first)
	if passes < MIN_PASSES:
		(
			bad
			. append(
				(
					"the rider passed the player %d times in %.0f s, wanted at least %d (it does not turn back)"
					% [passes, SECONDS, MIN_PASSES]
				)
			)
		)
	if worst_rate_ratio > 0.0:
		bad.append(
			"the rider turned %.1f times faster than its arc limit allows" % worst_rate_ratio
		)
	if max_sideways > 0.0:
		bad.append(
			(
				"a rider swung with %.1f m/s² sideways, more than the %.1f allowed"
				% [max_sideways, rs.PURSUIT_ACCEL]
			)
		)
	if max_dyaw > rs.PURSUIT_MAX_TURN * dt + 0.0005:
		bad.append("the rider turned %.3f rad in one step (a snap)" % max_dyaw)
	if overshoots < 2 or turned_back < 1:
		bad.append(
			(
				"the rider did not ride straight on after passing (%d overshoots, %d turns back)"
				% [overshoots, turned_back]
			)
		)
	if overshoot_short > 0.0:
		bad.append("a rider turned back %.1f m too soon after a pass" % overshoot_short)
	if overshoot_drift > 0.05:
		bad.append(
			"a rider drifted %.2f rad off its line while riding straight on" % overshoot_drift
		)
	main.riders.erase(r)
	main.free_rider(r)
	return (
		"\n  chase: %d passes in %.0f s, closest first approach %.2f m, tightest arc %.1f m"
		% [passes, SECONDS, min_first, min_turn_radius]
	)


# a post stands on the line from the west gate to the player: the rider must never be inside it, must
# swerve round it and must still get to the player
func _check_avoidance() -> String:
	var rs = main.rider_sys
	var r = _new_rider(0)
	# the post stands on the line from the gate this rider came out of to the player
	var side = signf(r["pos"].x)
	mock.post = Vector3(12.0 * side, 0.0, 0.0)
	var in_post = false
	var swerve = 0.0
	var reached = false
	var closest = INF
	for step in range(int(SECONDS * fps)):
		main.player.position = Vector3.ZERO
		main.state = "check"
		rs.update_rider(r, dt)
		var pos: Vector3 = r["pos"]
		if mock.obstacle_at(pos) and not r["hidden"]:
			in_post = true
		if not reached and pos.x * side > 8.0:
			swerve = maxf(swerve, absf(pos.z))
		if _planar(pos, Vector3.ZERO) < 3.0:
			reached = true
		closest = minf(closest, _planar(pos, Vector3.ZERO))
	if in_post:
		bad.append("the rider rode into the post")
	if swerve < 0.3:
		bad.append("the rider never swerved for the post (the avoidance is not covered)")
	if swerve > 8.0:
		bad.append("the rider swung %.1f m wide round a post on its first approach" % swerve)
	if closest > 4.0:
		bad.append("the rider never got to the player past the post (closest %.1f m)" % closest)
	main.riders.erase(r)
	main.free_rider(r)
	mock.post = Vector3(1000.0, 0.0, 1000.0)
	return "\n  post: swerved %.1f m, closest to the player %.1f m" % [swerve, closest]


# on grass a rider keeps 0.75 of its speed, on the road all of it
func _check_surface_speed() -> String:
	var rs = main.rider_sys
	var out = {}
	for where in [Vector3(-60.0, 0.0, 30.0), Vector3(60.0, 0.0, 30.0)]:
		var r = _new_rider(1)
		r["pos"] = where
		r["yaw"] = rs.yaw_of(Vector3(where.x, 0.0, where.z))  # riding away from the player
		r["hidden"] = false
		r["entered"] = true
		r["spd"] = 12.0
		var p0: Vector3 = r["pos"]
		rs.move_rider(r, dt)
		out[where.x] = _planar(r["pos"], p0) / (12.0 * dt)
		main.riders.erase(r)
		main.free_rider(r)
	if absf(out[-60.0] - 1.0) > 0.01:
		bad.append("on the road a rider kept %.2f of its speed, not 1.0" % out[-60.0])
	if absf(out[60.0] - 0.75) > 0.01:
		bad.append("on grass a rider kept %.2f of its speed, not 0.75" % out[60.0])
	return "\n  ground: road %.2f, grass %.2f of the speed" % [out[-60.0], out[60.0]]


# a rider that gives up rides at the nearest gate and is gone once it has ridden out through it
func _check_give_up() -> String:
	var rs = main.rider_sys
	var r = _new_rider(2)
	r["limit"] = 2.0
	var steps = int(SECONDS * fps)
	var gave_up = -1
	var chosen = {}
	var near_gate = {}
	var gone_step = -1
	for step in range(steps):
		main.player.position = Vector3.ZERO
		main.state = "check"
		var was = r["mode"]
		var before: Vector3 = r["pos"]
		rs.update_rider(r, dt)
		if was == "fly" and r["mode"] == "away":
			gave_up = step
			chosen = r["away_gate"]
			var best = INF
			for gate in mock.gate_list:
				var d = _planar(before, gate["pos"])
				if d < best:
					best = d
					near_gate = gate
		if not main.riders.has(r):
			gone_step = step
			break
	if gave_up < 0:
		bad.append("a rider past its time limit never gave up")
	elif chosen.is_empty() or _planar(chosen["pos"], near_gate["pos"]) > 0.01:
		bad.append("a rider that gave up did not ride out of the nearest gate")
	if gone_step < 0:
		bad.append("a rider that gave up never left the arena")
	elif near_gate.size() > 0 and _planar(r["pos"], near_gate["pos"]) > 5.0:
		bad.append(
			(
				"a rider that gave up was gone %.1f m from its gate"
				% _planar(r["pos"], near_gate["pos"])
			)
		)
	if gone_step >= 0:
		return "\n  give up: left after %.1f s through the nearest gate" % (float(gone_step) / fps)
	main.riders.erase(r)
	main.free_rider(r)
	return ""


# a rider that gives up close to a gate, on the wrong side of it and facing away, still gets out: it slows to
# make the turn instead of circling the gate for ever at full speed
func _check_give_up_close() -> String:
	var rs = main.rider_sys
	var r = _new_rider(1)
	r["pos"] = Vector3(20.0, 0.0, 8.0)
	r["yaw"] = PI  # riding west, away from the east gate
	r["hidden"] = false
	r["entered"] = true
	r["spd"] = 35.0
	r["base"] = 35.0
	r["tgt"] = 35.0
	r["chg"] = 100.0
	r["limit"] = 0.0
	var gone = -1
	var wide = 0.0
	for step in range(int(20.0 * fps)):
		main.player.position = Vector3.ZERO
		main.state = "check"
		rs.update_rider(r, dt)
		wide = maxf(wide, _planar(r["pos"], Vector3.ZERO))
		if not main.riders.has(r):
			gone = step
			break
	if gone < 0:
		bad.append("a rider that gave up close to a gate, facing away from it, never got out")
		main.riders.erase(r)
		main.free_rider(r)
		return ""
	if float(gone) / fps > 7.0:
		bad.append(
			(
				"a rider that gave up close to a gate took %.1f s to get out, wanted 7 s at most"
				% (float(gone) / fps)
			)
		)
	if wide > 45.0:
		(
			bad
			. append(
				(
					"a rider that gave up close to a gate swung %.0f m from the middle (the gates are at 30 m)"
					% wide
				)
			)
		)
	return (
		"\n  give up close: out after %.1f s, never more than %.0f m out"
		% [float(gone) / fps, wide]
	)


# the roundabout does not pursue and keeps its speed table
func _check_roundabout_unchanged() -> String:
	var round_arena = load("res://scripts/arena_roundabout.gd").new()
	if round_arena.rider_pursuit():
		bad.append("the roundabout says riders pursue (they must keep their lanes there)")
	if round_arena.rider_speed_at(Vector3(3.0, 0.0, 4.0)) != 1.0:
		bad.append("the roundabout changed a rider's speed on open ground")
	return "\n  roundabout: still lane steering"
