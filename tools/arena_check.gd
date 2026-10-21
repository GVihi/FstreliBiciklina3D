extends SceneTree
# Regression check for the arena geometry (README Milestone K, Foundation). It samples the street <-> world
# conversions, the walkable-ground and dart-blocking rules and the boss obstacle test at fixed pseudo-random
# points and compares the numbers with tools/arena_golden.txt, which was written from the roundabout code
# before the Arena interface was added. If the interface changes any behaviour, a line differs.
#
# Run from the project folder:
#   godot --headless --path . --script res://tools/arena_check.gd           compare with the golden file
#   godot --headless --path . --script res://tools/arena_check.gd -- write  rewrite the golden file
# Exits with status 1 and prints the first differences when they do not match. The numbers come from
# sin / cos / atan2, so a different Godot version or platform can shift the last digit: this is a local aid
# for refactoring, it does not run in CI.

const Ring = preload("res://scripts/ring.gd")
const GOLDEN = "res://tools/arena_golden.txt"
const SAMPLES = 120


func _init() -> void:
	var main = load("res://main.tscn").instantiate()
	root.add_child(main)
	for i in range(3):
		await process_frame
	var lines = _sample(main)
	var queries_bad = _check_queries(main.arena)
	var args = OS.get_cmdline_user_args()
	if args.size() > 0 and args[0] == "write":
		var f = FileAccess.open(GOLDEN, FileAccess.WRITE)
		f.store_string("\n".join(lines) + "\n")
		f.close()
		print("arena_check: wrote %d lines to %s" % [lines.size(), GOLDEN])
		quit(0)
		return
	if not FileAccess.file_exists(GOLDEN):
		printerr("arena_check: %s is missing, run with -- write first" % GOLDEN)
		quit(1)
		return
	var want = FileAccess.get_file_as_string(GOLDEN).strip_edges().split("\n")
	var bad = 0
	for i in range(maxi(want.size(), lines.size())):
		var a = want[i] if i < want.size() else "(missing)"
		var b = lines[i] if i < lines.size() else "(missing)"
		if a != b:
			bad += 1
			if bad <= 8:
				printerr("line %d\n  golden: %s\n  now:    %s" % [i + 1, a, b])
	if bad == 0:
		print("arena_check: %d lines identical to the golden file" % lines.size())
	else:
		printerr("arena_check: %d of %d lines differ" % [bad, lines.size()])
	quit(1 if bad > 0 or queries_bad > 0 else 0)


# Checks of the world-space queries that are not in the golden file (they did not exist when it was
# written): the answers must agree with the ground world.gd lays down. Returns the number of failures.
func _check_queries(A) -> int:
	var bad = 0
	var tests = [
		[Vector3(0.0, 0.0, -1.0), "grass"],
		[Vector3(0.0, 0.0, -5.0), "plaza"],
		[Vector3(0.0, 0.0, -8.4), "sidewalk"],
		[Vector3(0.0, 0.0, -9.0), "road"],
		[Vector3(0.0, 0.0, -13.25), "road"],
		[Vector3(0.0, 0.0, -20.0), "sidewalk"],
		[Vector3(0.0, 0.0, -24.5), "building"],
		[Vector3(0.0, 0.0, 14.0), "tunnel"],
	]
	for t in tests:
		var got = A.surface_at(t[0])
		if got != t[1]:
			bad += 1
			printerr("surface_at %s: want %s, got %s" % [t[0], t[1], got])
	var gs = A.gates()
	if gs.size() != 1:
		bad += 1
		printerr("gates: want 1 gate, got %d" % gs.size())
	else:
		var gt = gs[0]
		if A.surface_at(gt["pos"]) != "tunnel" and A.surface_at(gt["pos"]) != "road":
			bad += 1
			printerr("gates: the gate position %s is on %s" % [gt["pos"], A.surface_at(gt["pos"])])
		if not A.hidden(A.to_track(gt["pos"]).x):
			bad += 1
			printerr("gates: the gate position %s is not inside the tunnel block" % gt["pos"])
		if absf(float(gt["outward"].length()) - 1.0) > 0.001 or gt["outward"].z < 0.99:
			bad += 1
			printerr(
				(
					"gates: outward %s should be a unit vector pointing behind the player"
					% gt["outward"]
				)
			)
	if A.start_position().distance_to(A.tw(0.0, 6.0)) > 0.0001:
		bad += 1
		printerr("start_position differs from the street point (0, 6)")
	if A.surface_at(A.start_position()) != "grass" and A.surface_at(A.start_position()) != "plaza":
		bad += 1
		printerr("start_position is not on the island: %s" % A.surface_at(A.start_position()))
	if bad == 0:
		print("arena_check: world-space queries agree with the ground")
	return bad


func _f(v: float) -> String:
	return "%.4f" % v


func _v3(v: Vector3) -> String:
	return "(%s %s %s)" % [_f(v.x), _f(v.y), _f(v.z)]


func _sample(g) -> Array:
	# the arena object once it exists, the static roundabout script before that: same function names
	var A = g.arena if g.get("arena") != null else Ring
	var rng = RandomNumberGenerator.new()
	rng.seed = 20260421
	var lines = []
	var hx = float(A.HX)
	for n in range(SAMPLES):
		var x = rng.randf_range(-hx - 3.0, hx + 3.0)
		var z = rng.randf_range(-14.0, 4.0)
		var y = rng.randf_range(0.0, 3.0)
		var w = A.tw(x, z, y)
		var back = A.to_track(w)
		lines.append(
			(
				"street %s %s %s | tw %s | back %s %s | yaw %s | tan %s | in %s | hidden %s"
				% [
					_f(x),
					_f(z),
					_f(y),
					_v3(w),
					_f(back.x),
					_f(back.y),
					_f(A.yaw(x)),
					_v3(A.tangent(x)),
					_v3(A.inward(x)),
					str(A.hidden(x))
				]
			)
		)
		lines.append(
			(
				"main tw3 %s | street_vel %s | rider_lane %s"
				% [
					_v3(g.tw3(x, y, z)),
					_v3(g.street_vel(x, 1.5, 0.5, -2.0)),
					_v3(A.tw(x, g.LANE_Z[n % 3], 1.0))
				]
			)
		)
		var p = Vector3(
			rng.randf_range(-30.0, 30.0), rng.randf_range(0.0, 8.0), rng.randf_range(-30.0, 30.0)
		)
		var walk = g.clamp_walk(p, 2.3, 22.3)
		var boss_walk = g.clamp_walk(p, 2.1, 22.6)
		(
			lines
			. append(
				(
					"world %s | clamp_walk %s | clamp_boss %s | clamp_road %s | ray_blocked %s | obstacle %s"
					% [
						_v3(p),
						_v3(walk),
						_v3(boss_walk),
						_v3(A.clamp_road(p)),
						str(g.ray_blocked(p)),
						str(g.boss_sys.obstacle_at(p))
					]
				)
			)
		)
		var d = Vector3(rng.randf_range(-1.0, 1.0), 0.0, rng.randf_range(-1.0, 1.0)).normalized()
		var o = Vector3(rng.randf_range(-5.0, 5.0), 1.5, rng.randf_range(-5.0, 5.0))
		lines.append(
			(
				"ray o %s d %s | exit_facade %s | exit_r12 %s"
				% [
					_v3(o),
					_v3(d),
					_f(A.ray_exit_circle(o, d, A.FACADE_RHO)),
					_f(A.ray_exit_circle(o, d, 12.0))
				]
			)
		)
		g.player.position = Vector3(p.x, 0.0, p.z)
		lines.append(
			"player %s | ptx %s | ptz %s" % [_v3(g.player.position), _f(g.ptx()), _f(g.ptz())]
		)
	# dart blocking is a small area (fountain, planter, tunnel), so sample it densely and near the gate
	var drng = RandomNumberGenerator.new()
	drng.seed = 77001
	for n in range(300):
		var ang = drng.randf_range(-PI, PI) if n % 2 == 0 else PI + drng.randf_range(-0.7, 0.7)
		var rad = drng.randf_range(0.0, 13.0)
		var dp = Vector3(sin(ang) * rad, drng.randf_range(0.0, 8.0), -cos(ang) * rad)
		lines.append("dart %s | blocked %s" % [_v3(dp), str(g.ray_blocked(dp))])
	lines.append(
		(
			"consts HX %s lim %s player_lim %s rho0 %s rho_m7 %s start %s"
			% [
				_f(A.HX),
				_f(A.lim()),
				_f(A.player_lim()),
				_f(A.rho(0.0)),
				_f(A.rho(-7.0)),
				_v3(A.tw(0.0, 6.0))
			]
		)
	)
	return lines
