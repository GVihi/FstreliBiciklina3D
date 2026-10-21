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
		quit(0)
	else:
		printerr("arena_check: %d of %d lines differ" % [bad, lines.size()])
		quit(1)


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
