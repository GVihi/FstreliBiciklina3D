extends SceneTree
# Checks that the kinds of cache can be told apart without colour (README Milestone K, "Caches with a catch", the item
# "Mark the variants on the HUD and the radar"). Run from the project folder:
#   godot --headless --path . --script res://tools/cache_markers_check.gd
# or with `python tools/run_checks.py cache_markers`.
#
# Shapes (scripts/hud.gd `CACHE_SHAPES`, `cache_shape`): every variant the round can roll, and the plain cache, has a
# shape of its own and a colour of its own (`Objective.variant_color`), so a new variant added to `VARIANTS` without a
# shape is caught here. The map legend (`MAP_LEGEND`) lists each of them.
# Drawing: a generated round with one cache of each variant (and one taken) draws the radar, the world markers and the
# held map at three window sizes (a script error in the drawing code shows up here and the runner reports it).
# Exits with status 1 and prints the problems.

const Hud = preload("res://scripts/hud.gd")
const Objective = preload("res://scripts/objective.gd")

const SEED = 0x2468ACE0
const SIZES = [Vector2(1280.0, 720.0), Vector2(1920.0, 1080.0), Vector2(800.0, 450.0)]

var problems = []


func _initialize() -> void:
	_shapes()
	await _drawing()
	if problems.is_empty():
		print(
			"cache_markers_check: every cache variant has its own shape and colour, and they draw"
		)
		quit(0)
	else:
		print("cache_markers_check: %d problem(s)" % problems.size())
		for p in problems:
			print("  " + p)
		quit(1)


func _fail(text: String) -> void:
	if problems.size() < 40:
		problems.append(text)


func _shapes() -> void:
	var kinds = [Objective.VARIANT_PLAIN]
	kinds.append_array(Objective.VARIANTS)
	var shapes = {}
	var colours = {}
	for v in kinds:
		var s = Hud.cache_shape(v)
		var c = Objective.variant_color(v)
		if not Hud.CACHE_SHAPES.has(v):
			_fail("variant %s has no entry in CACHE_SHAPES" % v)
		if shapes.has(s):
			_fail("variants %s and %s share the shape %s" % [shapes[s], v, s])
		if colours.has(c):
			_fail("variants %s and %s share a colour" % [colours[c], v])
		shapes[s] = v
		colours[c] = v
		if v != Objective.VARIANT_PLAIN:
			var found = false
			for row in Hud.MAP_LEGEND:
				if row[0] == "cache_" + v:
					found = true
			if not found:
				_fail("the map legend has no entry for the %s cache" % v)
	if Hud.cache_shape("no_such_variant") != Hud.cache_shape(Objective.VARIANT_PLAIN):
		_fail("an unknown variant does not look like a plain cache")


func _drawing() -> void:
	var m = load("res://main.tscn").instantiate()
	m.generated_arena = true
	root.add_child(m)
	for i in range(3):
		await process_frame
	m.start_game(false, SEED)
	for i in range(3):
		await process_frame
	if m.state == "map":
		m.pick_node(0)
	if m.state != "play":
		_fail("could not start a round (state %s)" % m.state)
		return
	var o = m.objective_sys
	var ex = m.explore_sys
	var kinds = [Objective.VARIANT_PLAIN]
	kinds.append_array(Objective.VARIANTS)
	for i in range(mini(kinds.size(), o.caches.size())):
		o.caches[i]["variant"] = kinds[i]
		if i < ex.cache_found.size():
			ex.cache_found[i] = true
	if o.caches.size() > kinds.size():
		o.caches[kinds.size()]["taken"] = true
	m.player.position = o.caches[0]["pos"] + Vector3(3.0, 0.0, 0.0)
	for s in SIZES:
		m.hud.size = s
		m.map_key_forced = false
		m.hud.queue_redraw()
		for i in range(2):
			await process_frame
		m.map_key_forced = true
		m.hud.queue_redraw()
		for i in range(2):
			await process_frame
	m.map_key_forced = false
	root.remove_child(m)
	m.free()
