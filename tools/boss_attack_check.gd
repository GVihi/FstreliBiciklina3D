extends SceneTree
# Check for boss attacks on open ground (README Milestone K, Gameplay on open ground). On an arena that says
# rider_avoidance() a boss walks round buildings instead of pushing against them, only starts a lunge when
# nothing solid is between it and the player (otherwise it would run itself into a wall again and again, and
# the player could hide behind a building and farm the crash reward), and a slam does not reach through a
# wall. The roundabout keeps all of its old behaviour, including a lunge that ends in the fountain, so it is
# checked too. This builds a flat test arena with one long wall and plays bosses on it.
#
# Run from the project folder:
#   godot --headless --path . --script res://tools/boss_attack_check.gd
# Exits with status 1 and prints the first problems when something is wrong.

const ArenaGenScript = preload("res://scripts/arena_gen.gd")
const GeneratedArena = preload("res://scripts/arena_generated.gd")
const DT = 1.0 / 60.0
const WALL_HALF_X = 1.4
const WALL_HALF_Z = 14.0
const CHASE_SECONDS = 45.0
const GEN_SEEDS = 30
const GEN_SECONDS = 40.0

var bad: Array = []
var main = null
var mock = null


func _init() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	for i in range(3):
		await process_frame
	seed(7)
	main.start_game()
	main.state = "play"
	var summary = ""
	# the roundabout first: it is the arena the game starts with
	summary += _check_roundabout_unchanged()
	mock = _make_arena()
	if mock == null:
		bad.append("could not build the test arena")
		_finish("")
		return
	main.arena = mock
	main.state = "play"
	summary += _check_slam_wall()
	summary += _check_chase_round_wall() + "\n"
	summary += _check_generated_arenas()
	_finish(summary)


func _finish(summary: String) -> void:
	if bad.size() > 0:
		print("boss_attack_check: %d problem(s)" % bad.size())
		for b in bad.slice(0, 12):
			print("  " + b)
		quit(1)
		return
	print("boss_attack_check: " + summary.strip_edges())
	quit(0)


# a flat arena with open ground everywhere, a gate at each end (x = -30 and x = 30) and one long wall along the
# z axis in the middle (a building 2.8 m thick and 28 m long) that a boss cannot walk through or lunge through
func _make_arena():
	var src = 'extends "res://scripts/arena_roundabout.gd"\n'
	src += "var gate_list: Array = []\n"
	src += "var wall_on := true\n"
	src += "func rider_pursuit() -> bool:\n\treturn true\n"
	src += "func rider_avoidance() -> bool:\n\treturn true\n"
	src += "func gates() -> Array:\n\treturn gate_list\n"
	src += "func obstacle_at(p: Vector3) -> bool:\n"
	src += "\treturn wall_on and absf(p.x) < %f and absf(p.z) < %f\n" % [WALL_HALF_X, WALL_HALF_Z]
	src += "func clamp_walk(p: Vector3, _who: String = 'player') -> Vector3:\n"
	src += "\tvar q = Vector3(p.x, 0.0, p.z)\n"
	src += (
		"\tif wall_on and absf(q.x) < %f and absf(q.z) < %f:\n"
		% [WALL_HALF_X + 0.3, WALL_HALF_Z + 0.3]
	)
	src += "\t\tq.x = %f * (1.0 if q.x >= 0.0 else -1.0)\n" % (WALL_HALF_X + 0.3)
	src += "\treturn q\n"
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


func _new_boss(round_n: int = 4) -> Dictionary:
	main.round_n = round_n
	main.boss_sys.spawn_boss()
	var b = main.bosses.back()
	b["intro"] = 0.0
	return b


func _clear_bosses() -> void:
	for b in main.bosses.duplicate():
		main.free_boss(b)
	main.bosses.clear()


func _planar(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


# true if something solid (as the arena says) lies on the straight line from a to b, looked at every 0.25 m
func _blocked_between(a: Vector3, b: Vector3) -> bool:
	var d = Vector3(b.x - a.x, 0.0, b.z - a.z)
	var n = int(ceil(d.length() / 0.25))
	for i in range(1, n + 1):
		if main.arena.obstacle_at(a + d * (float(i) / float(maxi(n, 1)))):
			return true
	return false


# the boss is ready to attack with the player on the other side of the fountain: the old behaviour (it lines up a
# lunge anyway and crashes into the fountain, which is how a boss is stunned on the roundabout) must stay
func _check_roundabout_unchanged() -> String:
	var b = _new_boss(4)
	b["wp"] = Vector3(-6.0, 0.0, 0.0)
	b["chase_t"] = 100.0
	var player = Vector3(6.0, 0.0, 0.0)
	main.player.position = player
	if not _blocked_between(b["wp"], player):
		bad.append("roundabout: the test line does not cross the fountain (the test does not bite)")
	main.hearts = 99
	main.invuln = 0.0
	main.boss_sys.update_bosses(DT)
	if b["mode"] != "tele":
		(
			bad
			. append(
				"roundabout: a boss ready to attack held back because the fountain is in the way (old behaviour lost)"
			)
		)
	var crashed = false
	for step in range(int(3.0 / DT)):
		main.hearts = 99
		main.invuln = 0.0
		main.player.position = player
		main.boss_sys.update_bosses(DT)
		if b["mode"] == "lunge" and b["lcrash"]:
			crashed = true
			break
	if not crashed:
		bad.append("roundabout: the lunge across the fountain no longer ends in a crash")
	_clear_bosses()
	return "roundabout bosses attack as before (a lunge across the fountain still crashes)\n"


# a slam reaches the player only if nothing solid is between the boss and the player
func _slam_hits(wall: bool) -> bool:
	mock.wall_on = wall
	var b = _new_boss(4)
	b["wp"] = Vector3(-2.0, 0.0, 0.0)
	main.player.position = Vector3(2.0, 0.0, 0.0)
	b["mode"] = "tele"
	b["pat"] = "slam"
	b["slam_r"] = main.boss_sys.slam_radius(b)
	b["tele_t"] = 0.01
	b["tele_total"] = 1.0
	main.hearts = 99
	main.invuln = 0.0
	main.dash_inv = 0.0
	main.boss_sys.update_bosses(DT)
	var hit = main.hearts < 99
	var radius = float(b["slam_r"])
	_clear_bosses()
	if radius < 4.2:
		bad.append("slam radius %.2f m is too small for the test to mean anything" % radius)
	return hit


func _check_slam_wall() -> String:
	if not _slam_hits(false):
		(
			bad
			. append(
				"slam: with nothing in the way a slam 4 m from the player did not hurt (the test does not bite)"
			)
		)
	if _slam_hits(true):
		bad.append("slam: a slam hurt the player through a wall")
	mock.wall_on = true
	return "a slam stops at a wall\n"


# the player stands still behind the wall. The boss has to walk round the end of it, must not start a lunge
# while the wall is between them, and so never crashes into the wall
func _check_chase_round_wall() -> String:
	mock.wall_on = true
	var b = _new_boss(4)
	b["wp"] = Vector3(-6.0, 0.0, 0.0)
	var player = Vector3(6.0, 0.0, 0.0)
	main.player.position = player
	var crossed_at = -1.0
	var min_dist = INF
	var attacks_blocked = 0
	var attacks = 0
	var crashes = 0
	var prev_mode = b["mode"]
	var inside_wall = 0
	for step in range(int(CHASE_SECONDS / DT)):
		main.hearts = 99
		main.invuln = 0.0
		main.player.position = player
		main.boss_sys.update_bosses(DT)
		if main.bosses.is_empty():
			break
		var wp: Vector3 = b["wp"]
		min_dist = minf(min_dist, _planar(wp, player))
		if wp.x > WALL_HALF_X and crossed_at < 0.0:
			crossed_at = float(step) * DT
		if mock.obstacle_at(wp):
			inside_wall += 1
		if b["mode"] == "tele" and prev_mode != "tele":
			attacks += 1
			if _blocked_between(wp, player):
				attacks_blocked += 1
		if b["mode"] == "lunge" and prev_mode != "lunge" and b["lcrash"]:
			crashes += 1
		prev_mode = b["mode"]
	_clear_bosses()
	if crossed_at < 0.0:
		(
			bad
			. append(
				(
					"chase: the boss never got round the wall in %d s (min distance to the player %.1f m)"
					% [CHASE_SECONDS, min_dist]
				)
			)
		)
	if attacks == 0:
		bad.append("chase: the boss never attacked once it was round the wall")
	if attacks_blocked > 0:
		bad.append(
			(
				"chase: the boss lined up %d attack(s) with the wall between it and the player"
				% attacks_blocked
			)
		)
	if crashes > 0:
		bad.append("chase: %d lunge(s) were aimed into the wall" % crashes)
	if inside_wall > 0:
		bad.append("chase: the boss stood inside the wall for %d frames" % inside_wall)
	return (
		"the boss walks round a wall (round it after %.1f s) and attacks only with a clear line"
		% crossed_at
	)


# real generated arenas: a boss comes in at a gate with the player standing on the start. It must reach the
# player (start an attack) in time on nearly every layout, never stand inside a building, and never line up an
# attack with a building in the way
func _check_generated_arenas() -> String:
	var rules = ArenaGenScript.load_rules()
	var attacked = 0
	var slowest = 0.0
	var seeds = 0
	var blocked_total = 0
	var inside_total = 0
	for k in range(GEN_SEEDS):
		var layout = ArenaGenScript.generate(1000 + k * 37, rules)
		if layout.is_empty():
			continue
		seeds += 1
		var arena = GeneratedArena.new(layout, rules)
		main.arena = arena
		var player: Vector3 = arena.start_position()
		main.player.position = player
		var b = _new_boss(4)
		var first_attack = -1.0
		var prev_mode = b["mode"]
		for step in range(int(GEN_SECONDS / DT)):
			main.hearts = 99
			main.invuln = 0.0
			main.player.position = player
			main.boss_sys.update_bosses(DT)
			if main.bosses.is_empty():
				break
			var wp: Vector3 = b["wp"]
			if arena.obstacle_at(wp):
				inside_total += 1
			if b["mode"] == "tele" and prev_mode != "tele":
				if first_attack < 0.0:
					first_attack = float(step) * DT
				if _blocked_between(wp, player):
					blocked_total += 1
			prev_mode = b["mode"]
		_clear_bosses()
		if first_attack >= 0.0:
			attacked += 1
			slowest = maxf(slowest, first_attack)
		else:
			print("  seed %d: the boss never got to attack in %d s" % [1000 + k * 37, GEN_SECONDS])
	if seeds < GEN_SEEDS / 2:
		bad.append("generated: only %d of %d seeds made a layout" % [seeds, GEN_SEEDS])
	if attacked < int(ceil(0.9 * float(seeds))):
		bad.append(
			"generated: the boss reached the player on only %d of %d arenas" % [attacked, seeds]
		)
	if blocked_total > 0:
		bad.append(
			"generated: %d attack(s) were lined up with a building in the way" % blocked_total
		)
	if inside_total > 0:
		bad.append("generated: the boss stood inside a building for %d frames" % inside_total)
	return (
		"on %d generated arenas the boss reached the player on %d (slowest %.1f s)"
		% [seeds, attacked, slowest]
	)
