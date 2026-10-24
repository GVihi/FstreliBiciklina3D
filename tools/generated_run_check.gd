extends SceneTree
# A short scripted run on a generated arena (README Milestone K, "Generated arena class": switch main.gd to a
# generated arena behind a flag). Run from the project folder:
#   godot --headless --path . --script res://tools/generated_run_check.gd
# Optional argument after "--": how many seeds to play (default 4).
# First it checks that the flag is off by default (the game is the roundabout, with its pedestrians and
# cheerleaders), then it starts the game with the flag on and checks that
#   - the title screen already shows the generated arena of today's daily seed, with one world in the scene
#   - starting a run (the CUSTOM SEED way) makes the arena of that seed (the same one every time, the layout
#     ArenaGen gives), swaps the world for its world (one environment and one sun under the game, never two),
#     and puts the player on the arena's start
#   - picking the first node of the map starts a round, and for 30 seconds of play (the game stepped at 60 frames
#     a second, the player walking a circle round the start, aiming at the nearest rider and firing) nothing
#     breaks: the player stays on ground it can stand on, riders and bosses stay finite and near the arena, a
#     rider that is not in a gate's tunnel is never inside a wall, riders come out of the gates, pedestrians come
#     out of the gates too and never stand deep inside a wall, and the cheerleaders stand on the start plaza,
#     facing the start, each on its own spot
# Exits with status 1 and prints the first problems.

const ArenaGenScript = preload("res://scripts/arena_gen.gd")
const MAIN_SCENE = "res://main.tscn"
const GENERATED = "res://scripts/arena_generated.gd"
const ROUNDABOUT = "res://scripts/arena_roundabout.gd"
const SECONDS = 30.0
const DT = 1.0 / 60.0
const GATE_SEEDS = 200  # layouts whose gate starts are checked
const STUCK_AFTER = 6.0  # seconds: a rider that is still inside its tunnel this long after it started is stuck
const GATE_SLACK = 9.0  # metres: a new rider is this near a gate at most (it starts in the tunnel, a few metres in)

var problems = []
var main = null


func _initialize() -> void:
	var count = 4
	var args = OS.get_cmdline_user_args()
	if args.size() > 0:
		count = int(args[0])
	await _check_flag_off()
	main = load(MAIN_SCENE).instantiate()
	main.generated_arena = true
	root.add_child(main)
	for i in range(3):
		await process_frame
	_check_title()
	_check_gate_spawns()
	var summary = []
	for k in range(count):
		summary.append(_play((k * 2654435761 + 4242) & 0xFFFFFFFF))
	if problems.is_empty():
		print("generated_run_check: %d runs on generated arenas played clean" % count)
		for line in summary:
			print("  " + line)
		quit(0)
	else:
		print("generated_run_check: %d problem(s)" % problems.size())
		for p in problems.slice(0, 12):
			print("  " + p)
		quit(1)


func _fail(text: String) -> void:
	problems.append(text)


# the flag is off unless asked for: the roundabout is the arena, with its pedestrians and cheerleaders
func _check_flag_off() -> void:
	var m = load(MAIN_SCENE).instantiate()
	root.add_child(m)
	for i in range(3):
		await process_frame
	if m.generated_arena:
		_fail("the generated arena flag is on by default")
	if m.arena.get_script().resource_path != ROUNDABOUT:
		_fail(
			(
				"without the flag the arena is %s, not the roundabout"
				% m.arena.get_script().resource_path
			)
		)
	if m.world_root != null:
		_fail("without the flag a generated world was built")
	if m.cheerleaders.is_empty() or m.cheerleaders.any(func(c): return not c["root"].visible):
		_fail("without the flag the cheerleaders are not all standing there")
	if m.civs.is_empty():
		_fail("without the flag no pedestrians were spawned")
	root.remove_child(m)
	m.free()


func _check_title() -> void:
	if main.arena.get_script().resource_path != GENERATED:
		_fail(
			"with the flag the title screen's arena is %s" % main.arena.get_script().resource_path
		)
		return
	var want = ArenaGenScript.generate(main.daily_seed)
	if want.is_empty() or main.arena.layout["rows"] != want["rows"]:
		_fail("the title screen's arena is not the daily seed's arena")
	_check_one_world("on the title screen")
	if main.player.position != main.arena.start_position():
		_fail("on the title screen the player is not on the start")
	_check_cheerleaders("on the title screen")
	if main.civs.size() != 2:
		_fail(
			(
				"the title screen has %d pedestrians on a generated arena, expected 2"
				% main.civs.size()
			)
		)
	for c in main.civs:
		var near = INF
		for gate in main.arena.gates():
			near = minf(
				near, Vector2(gate["pos"].x - c["pos"].x, gate["pos"].z - c["pos"].z).length()
			)
		if near > GATE_SLACK or not c["hidden"]:
			_fail(
				(
					"a pedestrian on the title screen is not in a gate's tunnel (%.1f m from a gate)"
					% near
				)
			)
	for key in ["env", "sky_mat", "sun", "win_mat", "lamp_mat", "lamps"]:
		if not main.world.has(key):
			_fail("the world has no %s" % key)


# A rider starts at rider_sys.gate_spawn_point(gate) and rides straight out of the tunnel. On every gate of many
# layouts that point must be hidden ground a rider can ride on (a start outside the grid has speed 0, so the rider
# sat there for ever: east and south gates were exactly on the edge), and the straight ride out must never meet
# a wall or ground a rider cannot ride on before it is out in the open.
func _check_gate_spawns() -> void:
	var seen_gates = 0
	for k in range(GATE_SEEDS):
		var seed_value = (k * 2654435761 + 99) & 0xFFFFFFFF
		var layout = ArenaGenScript.generate(seed_value)
		if layout.is_empty():
			continue
		var arena = load(GENERATED).new(layout)
		for gate in arena.gates():
			seen_gates += 1
			var tag = "seed %08X, gate at %s" % [seed_value, gate["pos"]]
			var at: Vector3 = main.rider_sys.gate_spawn_point(gate)
			if not arena.hidden_at(at):
				_fail("%s: riders start in the open at %s" % [tag, at])
			if arena.rider_speed_at(at) <= 0.0 or arena.rider_blocked(at):
				_fail("%s: riders start where nothing can be ridden, at %s" % [tag, at])
				continue
			var out = false
			var step = 0.25
			for i in range(1, int(14.0 / step)):
				var p: Vector3 = at - gate["outward"] * step * float(i)
				if arena.rider_blocked(p) or arena.rider_speed_at(p) <= 0.0:
					_fail("%s: the ride out of the tunnel is blocked at %s" % [tag, p])
					break
				if not arena.hidden_at(p):
					out = true
					break
			if not out:
				_fail("%s: a rider does not come out of the tunnel within 14 m" % tag)
	if seen_gates == 0:
		_fail("no gates were checked")


func _check_one_world(where: String) -> void:
	var envs = _count(main, "WorldEnvironment")
	var suns = _count(main, "DirectionalLight3D")
	if envs != 1 or suns != 1:
		_fail(
			(
				"%s: %d environments and %d suns in the scene, expected one of each"
				% [where, envs, suns]
			)
		)


func _count(node: Node, kind: String) -> int:
	var n = 1 if node.is_class(kind) else 0
	for c in node.get_children():
		n += _count(c, kind)
	return n


func _play(seed_value: int) -> String:
	var tag = "seed %08X" % seed_value
	main.start_game(false, seed_value)
	var want = ArenaGenScript.generate(seed_value)
	if main.arena.get_script().resource_path != GENERATED:
		_fail("%s: the run's arena is %s" % [tag, main.arena.get_script().resource_path])
		return tag + ": not a generated arena"
	if want.is_empty() or main.arena.layout["rows"] != want["rows"]:
		_fail("%s: the run's arena is not the one ArenaGen makes for the seed" % tag)
	_check_one_world(tag)
	var arena = main.arena
	if not main.civs.is_empty():
		_fail("%s: a pedestrian from the arena before is still there" % tag)
	if main.player.position != arena.start_position():
		_fail("%s: the player did not start on the arena's start" % tag)
	if main.state != "map":
		_fail("%s: a new run did not open the map screen (state %s)" % [tag, main.state])
		return tag + ": no map"
	main.pick_node(0)
	if main.state != "play":
		_fail("%s: picking a node did not start the round (state %s)" % [tag, main.state])
		return tag + ": no round"
	main.force_captured = true  # headless cannot capture the mouse; without this the game counts as paused
	var half = float(arena.layout["cells"]) * float(arena.layout["cell"]) / 2.0
	var start = arena.start_position()
	var frames = int(SECONDS / DT)
	var played = 0
	var seen = {}
	var shots = 0
	var bad_samples = 0
	for f in range(frames):
		if main.state != "play":
			break
		var ang = float(f) * 0.012
		main.player.position = main.clamp_walk(start + Vector3(cos(ang), 0.0, sin(ang)) * 8.0)
		var target = _nearest_rider(main.player.position)
		if target != null:
			var to: Vector3 = target["pos"] + Vector3(0.0, 1.0, 0.0) - main.cam.global_position
			main.yaw = atan2(-to.x, -to.z)
			main.pitch = atan2(to.y, Vector2(to.x, to.z).length())
			if f % 24 == 0:
				var before = main.shells
				main.combat_sys.fire()
				if main.shells < before:
					shots += 1
		main._process(DT)
		played += 1
		if f % 5 == 0:
			bad_samples += _sample(tag, f, half, arena, seen)
			if problems.size() > 12:
				break
	if played < int(10.0 / DT) and main.state == "play":
		_fail("%s: only %d frames were played" % [tag, played])
	if seen.is_empty():
		_fail("%s: no rider came out in %.0f seconds" % [tag, float(played) * DT])
	var civs_seen = seen.keys().filter(func(k): return k is String and k.begins_with("civ")).size()
	if civs_seen == 0:
		_fail("%s: no pedestrian came out in %.0f seconds" % [tag, float(played) * DT])
	_check_cheerleaders(tag)
	return (
		"%s: %d gates, %.1f s played, %d riders and %d pedestrians seen, %d shots, state %s"
		% [
			tag,
			arena.gates().size(),
			float(played) * DT,
			seen.size() - civs_seen,
			civs_seen,
			shots,
			main.state
		]
	)


func _nearest_rider(from: Vector3):
	var best = null
	var best_d = INF
	for r in main.riders:
		if r.get("hidden", false) or r.get("gone", false):
			continue
		var d = Vector2(r["pos"].x - from.x, r["pos"].z - from.z).length()
		if d < best_d:
			best_d = d
			best = r
	return best


# one look at the state of the run: returns 1 if something was wrong
func _sample(tag: String, f: int, half: float, arena, seen: Dictionary) -> int:
	var wrong = 0
	var pp: Vector3 = main.player.position
	if not _finite(pp) or arena.obstacle_at(pp) or absf(pp.x) > half or absf(pp.z) > half:
		_fail("%s, frame %d: the player is at %s, not on ground it can stand on" % [tag, f, pp])
		wrong += 1
	for r in main.riders:
		var p: Vector3 = r["pos"]
		if not _finite(p) or absf(p.x) > half + 15.0 or absf(p.z) > half + 15.0:
			_fail("%s, frame %d: a rider is at %s, off the arena" % [tag, f, p])
			wrong += 1
			continue
		if not seen.has(r["idx"]):
			seen[r["idx"]] = true
			var near = INF
			for g in arena.gates():
				near = minf(near, Vector2(g["pos"].x - p.x, g["pos"].z - p.z).length())
			if near > GATE_SLACK:
				_fail("%s, frame %d: a new rider is %.1f m from the nearest gate" % [tag, f, near])
				wrong += 1
		if not r["entered"] and r["age"] > STUCK_AFTER:
			_fail(
				"%s, frame %d: a rider has been stuck in its tunnel for %.1f s" % [tag, f, r["age"]]
			)
			wrong += 1
		if not r["hidden"] and arena.rider_blocked(p):
			_fail("%s, frame %d: a rider is inside a wall at %s" % [tag, f, p])
			wrong += 1
	for c in main.civs:
		var cp: Vector3 = c["pos"]
		if not _finite(cp) or absf(cp.x) > half + 15.0 or absf(cp.z) > half + 15.0:
			_fail("%s, frame %d: a pedestrian is at %s, off the arena" % [tag, f, cp])
			wrong += 1
			continue
		seen["civ%d" % c["model"]["root"].get_instance_id()] = true
		if not c["hidden"] and _deep_in_wall(arena, cp):
			_fail("%s, frame %d: a pedestrian stands deep inside a wall at %s" % [tag, f, cp])
			wrong += 1
	for b in main.bosses:
		var bp: Vector3 = b["wp"]
		if not _finite(bp) or absf(bp.x) > half + 15.0 or absf(bp.z) > half + 15.0:
			_fail("%s, frame %d: a boss is at %s, off the arena" % [tag, f, bp])
			wrong += 1
	return wrong


# true if p and the four points 0.3 m off it are all buildings (a graze of a corner is not deep)
func _deep_in_wall(arena, p: Vector3) -> bool:
	for off in [Vector3(0.3, 0, 0), Vector3(-0.3, 0, 0), Vector3(0, 0, 0.3), Vector3(0, 0, -0.3)]:
		if not arena.rider_blocked(p + off):
			return false
	return arena.rider_blocked(p)


# the cheerleaders on a generated arena are where cheer_spots says (the ones it has a spot for, visible, the rest
# hidden), on plaza near the start, facing it, and each model is where its "pos" says
func _check_cheerleaders(tag: String) -> void:
	var arena = main.arena
	var spots = arena.cheer_spots(main.cheerleaders.size())
	if spots.size() < 3:
		_fail("%s: the arena has only %d cheerleader spots" % [tag, spots.size()])
	for i in range(main.cheerleaders.size()):
		var m = main.cheerleaders[i]
		var cr: Node3D = m["root"]
		if cr.visible != (i < spots.size()):
			_fail(
				(
					"%s: cheerleader %d is %s but the arena has %d spots"
					% [tag, i, "visible" if cr.visible else "hidden", spots.size()]
				)
			)
			continue
		if not cr.visible:
			continue
		if m["pos"] != spots[i]:
			_fail("%s: cheerleader %d is not on its spot" % [tag, i])
		if Vector2(cr.position.x - m["pos"].x, cr.position.z - m["pos"].z).length() > 0.0001:
			_fail("%s: cheerleader %d's model is not at its pos" % [tag, i])
		var want = main.rider_sys.heading_vec(
			main.rider_sys.yaw_of(arena.start_position() - m["pos"])
		)
		var facing = (cr.transform.basis * Vector3.RIGHT).normalized()
		if facing.distance_to(want) > 0.001:
			_fail("%s: cheerleader %d does not face the start" % [tag, i])
		if arena.surface_at(m["pos"]) != "plaza":
			_fail("%s: cheerleader %d is on %s" % [tag, i, arena.surface_at(m["pos"])])


func _finite(v: Vector3) -> bool:
	return is_finite(v.x) and is_finite(v.y) and is_finite(v.z)
