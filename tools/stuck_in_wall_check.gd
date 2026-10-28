extends SceneTree
# Check for riders and pedestrians that end up in, or stuck behind, a wall on generated arenas (open ground).
# Two bugs found on 2026-10-28 are covered:
#   1. pedestrian_check failed now and then with "a pedestrian stands deep inside a building": pedestrians use the
#      global random numbers, so which arena and random stream trips it is luck, and the old walking code stepped into
#      a building when the steering had no clear heading. A pedestrian must never end a step in a building, and one
#      that is in a building anyway must be put on free ground.
#   2. A rider disappeared on a tunnel arena and the round never ended: a rider that gets past the outer edge of the
#      grid in front of a gate counts as hidden (the tunnel), has no speed there (nothing can be ridden outside the
#      grid) and cannot be hit. It must be put back in its gate and ride out again.
#
# Run from the project folder:
#   godot --headless --path . --script res://tools/stuck_in_wall_check.gd
# Exits with status 1 and prints the first problems when something is wrong.

const ArenaGenScript = preload("res://scripts/arena_gen.gd")
const GeneratedArena = preload("res://scripts/arena_generated.gd")

const DT = 1.0 / 20.0
const WALK_SECONDS = 120.0
# arena seed and random stream pairs that put a pedestrian deep in a building before the fix (found with a sweep of
# 11 arenas of pedestrian_check times 25 random streams each: 5 pairs failed)
const OLD_FAILURES = [[5303, 111], [5404, 110], [5505, 112], [5505, 113], [5505, 119]]

var bad: Array = []
var main = null
var rules = {}


func _init() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	for i in range(3):
		await process_frame
	seed(7)
	main.start_game()
	main.state = "check"  # nobody gets run over and a finished rider does not end the round
	main.hits.resize(400)
	main.hits.fill(false)
	rules = ArenaGenScript.load_rules()
	var summary = ""
	summary += _check_rider_outside_grid()
	summary += _check_rider_in_wall()
	summary += _check_pedestrian_in_wall()
	summary += _check_pedestrians_walk()
	if bad.size() > 0:
		print("stuck_in_wall_check: %d problem(s)" % bad.size())
		for b in bad.slice(0, 12):
			print("  " + b)
		quit(1)
		return
	print("stuck_in_wall_check: " + summary.strip_edges())
	quit(0)


func _arena_of_style(style: String, first_seed: int):
	for s in range(first_seed, first_seed + 400):
		var layout = ArenaGenScript.generate(s, rules)
		if not layout.is_empty() and (style == "" or str(layout.get("style", "")) == style):
			return GeneratedArena.new(layout, rules)
	return null


func _clear_actors() -> void:
	for r in main.riders:
		main.free_rider(r)
	main.riders.clear()
	for c in main.civs:
		c["model"]["root"].queue_free()
	main.civs.clear()
	main.next_idx = 0


# the centre of a building cell with buildings all round it and well inside the grid (not a gate's opening)
func _deep_wall_point(arena) -> Vector3:
	var layout = arena.layout
	var n = int(layout["cells"])
	var cell = float(layout["cell"])
	for cz in range(4, n - 4):
		for cx in range(4, n - 4):
			var all_walls = true
			for dz in range(-1, 2):
				for dx in range(-1, 2):
					if str(layout["rows"][cz + dz])[cx + dx] != "b":
						all_walls = false
			if all_walls:
				return Vector3(
					(float(cx) + 0.5 - float(n) / 2.0) * cell,
					0.0,
					(float(cz) + 0.5 - float(n) / 2.0) * cell
				)
	return Vector3(INF, 0.0, INF)


func _spawn_rider(arena) -> Dictionary:
	main.arena = arena
	main.player.position = arena.start_position()
	var r = main.rider_sys.spawn_rider(0, 1)
	r["can_throw"] = false
	return r


# a rider hidden past the outer edge of the grid in front of a gate has to be put back in the gate and come out again
func _check_rider_outside_grid() -> String:
	var arena = _arena_of_style("tunnel", 1000)
	if arena == null:
		bad.append("rider outside the grid: no tunnel arena found to try")
		return ""
	var tried = 0
	for gate in arena.gates():
		_clear_actors()
		var r = _spawn_rider(arena)
		r["pos"] = gate["pos"] + gate["outward"] * 4.0  # 2 m past the outer edge of the grid
		r["yaw"] = main.rider_sys.yaw_of(gate["outward"])
		r["entered"] = true
		r["hidden"] = main.rider_sys.is_hidden(r["pos"])
		tried += 1
		var tag = "rider outside the grid at gate %d: " % tried
		if not r["hidden"] or arena.rider_speed_at(r["pos"]) > 0.0:
			bad.append(
				tag + "the test point is not hidden ground with no speed (the test is wrong)"
			)
			continue
		var t = 0.0
		var came_out = false
		while t < 20.0:
			main.rider_sys.update_rider(r, DT)
			t += DT
			if arena.rider_speed_at(r["pos"]) <= 0.0:
				if t < DT * 1.5:
					bad.append(tag + "still on ground with no speed after one step")
					break
			if r["entered"] and not r["hidden"]:
				came_out = true
				break
		if not came_out:
			bad.append(tag + "never came out of its gate in 20 s (pos %s)" % str(r["pos"]))
		elif arena.rider_blocked(r["pos"]):
			bad.append(tag + "came out inside a wall")
	_clear_actors()
	return "%d gate openings, " % tried


# a visible rider inside a building is put on free ground (this was already so; the check keeps it so)
func _check_rider_in_wall() -> String:
	var arena = _arena_of_style("", 1000)
	var p = _deep_wall_point(arena)
	if p.x == INF:
		bad.append("rider in a wall: no building with walls all round found to try")
		return ""
	_clear_actors()
	var r = _spawn_rider(arena)
	r["pos"] = p
	r["entered"] = true
	r["hidden"] = main.rider_sys.is_hidden(p)
	if r["hidden"] or not arena.rider_blocked(p):
		bad.append("rider in a wall: the test point is not a visible building (the test is wrong)")
		return ""
	main.rider_sys.update_rider(r, DT)
	if arena.rider_blocked(r["pos"]):
		bad.append("a rider inside a building was not put on free ground (pos %s)" % str(r["pos"]))
	_clear_actors()
	return "rider rescue, "


# a pedestrian inside a building is put on free ground, and one walking at a wall does not go in
func _check_pedestrian_in_wall() -> String:
	var arena = _arena_of_style("", 1000)
	var p = _deep_wall_point(arena)
	if p.x == INF:
		bad.append("pedestrian in a wall: no building with walls all round found to try")
		return ""
	main.arena = arena
	main.state = "play"
	_clear_actors()
	main.civ_sys.spawn_civ()
	var c = main.civs[0]
	c["pos"] = p
	c["hidden"] = false
	c["entered"] = true
	main.civ_t = 99.0
	main.civ_sys.update_civs(DT)
	if main.civs.has(c) and arena.rider_blocked(c["pos"]):
		bad.append(
			"a pedestrian inside a building was not put on free ground (pos %s)" % str(c["pos"])
		)
	# next to a wall and facing it: whatever the steering does, the step into the wall is not taken
	_clear_actors()
	main.civ_sys.spawn_civ()
	c = main.civs[0]
	var face = _wall_face(arena)
	if face.is_empty():
		bad.append("pedestrian at a wall: no free cell next to a building found to try")
	else:
		c["pos"] = face["free"]
		c["hidden"] = false
		c["entered"] = true
		c["yaw"] = main.rider_sys.yaw_of(face["into"])
		for k in range(60):
			# aim straight into the wall every step, so only the guard in move_civ can keep it out
			c["yaw"] = main.rider_sys.yaw_of(face["into"])
			main.civ_sys.move_civ(c, 40.0, DT)
			if arena.rider_blocked(c["pos"]):
				bad.append("a pedestrian walked into a building (pos %s)" % str(c["pos"]))
				break
	_clear_actors()
	main.state = "check"
	return "pedestrian rescue and wall, "


# a free ground point 0.3 m west of a building's west face, and the direction into the building
func _wall_face(arena) -> Dictionary:
	var layout = arena.layout
	var n = int(layout["cells"])
	var cell = float(layout["cell"])
	for cz in range(4, n - 4):
		for cx in range(4, n - 4):
			if str(layout["rows"][cz])[cx] != "b" or not str(layout["rows"][cz])[cx - 1] in "gprs":
				continue
			var x = (float(cx) - float(n) / 2.0) * cell - 0.3
			var z = (float(cz) + 0.5 - float(n) / 2.0) * cell
			var free = Vector3(x, 0.0, z)
			if not arena.rider_blocked(free) and arena.rider_blocked(free + Vector3(0.6, 0.0, 0.0)):
				return {"free": free, "into": Vector3(1.0, 0.0, 0.0)}
	return {}


# the walks that put a pedestrian deep in a building before the fix, played the way pedestrian_check plays them
func _check_pedestrians_walk() -> String:
	var checked = 0
	for pair in OLD_FAILURES:
		var layout = ArenaGenScript.generate(pair[0], rules)
		if layout.is_empty():
			bad.append("pedestrians: no arena for seed %d" % pair[0])
			continue
		var arena = GeneratedArena.new(layout, rules)
		main.arena = arena
		main.state = "play"
		_clear_actors()
		seed(pair[1])
		for n in range(6):
			main.civ_sys.spawn_civ()
		var mine: Array = main.civs.duplicate()
		var t = 0.0
		var startled = null
		var deep = 0
		var tag = "pedestrians, arena %d, random stream %d: " % [pair[0], pair[1]]
		while t < WALK_SECONDS and not main.civs.is_empty():
			if startled == null and t > 12.0:
				for c in mine:
					if main.civs.has(c) and not c["hidden"] and c["state"] == "walk":
						startled = c
						main.civ_sys.hit_civ(c)
						main.hearts = 5
						main.state = "play"
						break
			main.civ_t = 99.0
			main.civ_sys.update_civs(DT)
			t += DT
			for c in mine:
				if main.civs.has(c) and not c["hidden"] and arena.rider_blocked(c["pos"]):
					deep += 1
					if deep <= 2:
						bad.append(tag + "a pedestrian stands in a building at %s" % str(c["pos"]))
		checked += 1
	_clear_actors()
	main.state = "check"
	return "%d old pedestrian walks" % checked
