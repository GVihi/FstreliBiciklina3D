extends SceneTree
# Checks the arena viewer (tools/viewer/arena_viewer.gd): what it draws for a seed, not how it looks.
# Run from the project folder:
#   godot --headless --path . --script res://tools/arena_viewer_check.gd
# Optional argument after "--": how many seeds to draw (default 200).
# For every seed it builds the picture from the layout and checks that
#   - every cell is drawn once at the right place and in the colour of its ground (read back through
#     ArenaGen.surface_at, so a mirrored or swapped axis fails), buildings as blocks BUILDING_HEIGHT high
#   - a building wall is drawn only where it faces open ground, and every drawn point is inside the arena
#   - the start frame is as big as the clear start area and centred on the start position
#   - there is one gate arrow per gate, pointing the way "outward" says, on the gate
#   - the clearance colours differ from the ground colours and follow the navigation grid
#   - the same seed gives exactly the same picture
# It also runs the whole scene: typing a seed draws that arena, the text names the seed and says the layout
# is valid, a bad seed is refused, and a gate label is added for every gate plus one for the start. W swaps
# the flat plan for the real ground WorldGen builds from the layout (lit, with its own legend and counts),
# keeps it for the next seed, and C goes back to the plan.
# Exits with status 1 and lists the first problems when a check fails.

const ArenaGen = preload("res://scripts/arena_gen.gd")
const DailyScript = preload("res://scripts/daily.gd")
const Viewer = preload("res://tools/viewer/arena_viewer.gd")
const WorldGen = preload("res://scripts/world_gen.gd")
const WorldDress = preload("res://scripts/world_dress.gd")

var problems = []


# Mesh colours are stored with 8 bits per channel, so they come back rounded to 1/255.
func _same(a: Color, b: Color) -> bool:
	return (
		absf(a.r - b.r) < 0.01
		and absf(a.g - b.g) < 0.01
		and absf(a.b - b.b) < 0.01
		and absf(a.a - b.a) < 0.01
	)


func _initialize() -> void:
	var count = 200
	var args = OS.get_cmdline_user_args()
	if args.size() > 0:
		count = int(args[0])
	var rules = ArenaGen.load_rules()
	if rules.is_empty():
		quit(1)
		return
	_check_parse_seed()
	var drawn = 0
	for k in range(count):
		var seed_value = (k * 2654435761 + 777) & 0xFFFFFFFF
		var layout = ArenaGen.generate(seed_value, rules)
		if layout.is_empty():
			_fail(seed_value, "no layout was generated")
			continue
		_check_picture(seed_value, layout)
		drawn += 1
	await _check_scene(rules)
	if problems.is_empty():
		print(
			(
				"arena_viewer_check: %d seeds drawn, every cell, wall, start frame and gate arrow is where the layout says, the scene takes a seed and refuses a bad one, and W shows the real ground"
				% drawn
			)
		)
		quit(0)
	else:
		for i in range(mini(problems.size(), 20)):
			print("FAIL: " + problems[i])
		print("arena_viewer_check: %d problems" % problems.size())
		quit(1)


func _fail(seed_value: int, text: String) -> void:
	problems.append("seed %08X: %s" % [seed_value, text])


func _check_parse_seed() -> void:
	var cases = {
		"7F3A91C2": 0x7F3A91C2,
		"  7f3a91c2 ": 0x7F3A91C2,
		"0x7F3A91C2": 0x7F3A91C2,
		"1": 1,
		"00000000": 0,
		"FFFFFFFF": 0xFFFFFFFF,
		"today": DailyScript.today_seed(),
		"Daily": DailyScript.today_seed(),
		"": -1,
		"   ": -1,
		"123456789": -1,
		"7F3A91CG": -1,
		"-5": -1,
		"1.5": -1,
		"seed": -1,
	}
	for text in cases:
		var got = Viewer.parse_seed(text)
		if got != int(cases[text]):
			problems.append('parse_seed("%s") gave %d, expected %d' % [text, got, int(cases[text])])
	# what the game shows for a seed must be read back as the same seed
	for s in [0, 1, 0xDEADBEEF, 0xFFFFFFFF, DailyScript.today_seed()]:
		if Viewer.parse_seed(DailyScript.seed_text(s)) != s:
			problems.append("seed_text of %d is not read back as the same seed" % s)


# one flat or upright square read back from the mesh
func _quads(mesh: ArrayMesh, arrows: int) -> Array:
	var arrays = mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var cols: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var out = []
	var quad_idx = idx.size() - 3 * arrows
	var i = 0
	while i < quad_idx:
		var base = idx[i]
		(
			out
			. append(
				{
					"v": [verts[base], verts[base + 1], verts[base + 2], verts[base + 3]],
					"color": cols[base],
				}
			)
		)
		i += 6
	return out


func _check_picture(seed_value: int, layout: Dictionary) -> void:
	var n = int(layout["cells"])
	var cell = float(layout["cell"])
	var half_world = float(n) * cell / 2.0
	var mesh = Viewer.build_mesh(layout, Viewer.MODE_GROUND)
	var again = Viewer.build_mesh(layout, Viewer.MODE_GROUND)
	if mesh.surface_get_arrays(0) != again.surface_get_arrays(0):
		_fail(seed_value, "the same layout was drawn two different ways")
	var arrays = mesh.surface_get_arrays(0)
	for v in arrays[Mesh.ARRAY_VERTEX]:
		if absf(v.x) > half_world + 0.001 or absf(v.z) > half_world + 0.001 or v.y < 0.0:
			_fail(seed_value, "a point is outside the arena: %s" % str(v))
			break
	var quads = _quads(mesh, layout["gates"].size())
	# the cell tops: side `cell`, flat, at y 0 (ground) or BUILDING_HEIGHT (building), one per cell
	var tops = {}
	var walls = 0
	for q in quads:
		var v = q["v"]
		var flat = is_equal_approx(v[0].y, v[1].y) and is_equal_approx(v[1].y, v[2].y)
		var w = v[0].distance_to(v[1])
		var d = v[1].distance_to(v[2])
		if flat and is_equal_approx(w, cell) and is_equal_approx(d, cell):
			var cx = int(floor((v[0].x + half_world) / cell + 0.0001))
			var cz = int(floor((v[0].z + half_world) / cell + 0.0001))
			var key = cz * n + cx
			if tops.has(key):
				_fail(seed_value, "cell %d,%d is drawn twice" % [cx, cz])
			tops[key] = q
		elif (
			not flat
			and is_equal_approx(v[0].y, 0.0)
			and is_equal_approx(v[2].y, Viewer.BUILDING_HEIGHT)
		):
			walls += 1
	if tops.size() != n * n:
		_fail(seed_value, "%d cell squares drawn, %d cells" % [tops.size(), n * n])
		return
	var expected_walls = 0
	for cz in range(n):
		for cx in range(n):
			var q = tops[cz * n + cx]
			var centre = (q["v"][0] + q["v"][2]) / 2.0
			var name = ArenaGen.surface_at(layout, centre.x, centre.z)
			var ch = str(layout["rows"][cz])[cx]
			if name != ArenaGen.LEGEND[ch]:
				_fail(seed_value, "cell %d,%d is drawn where the layout says %s" % [cx, cz, name])
				return
			var want_y = Viewer.BUILDING_HEIGHT if ch == "b" else 0.0
			if not is_equal_approx(q["v"][0].y, want_y):
				_fail(
					seed_value,
					"cell %d,%d (%s) is drawn at height %.2f" % [cx, cz, name, q["v"][0].y]
				)
				return
			var want = Viewer.GROUND_COLORS[ch]
			var got: Color = q["color"]
			if not (_same(got, want) or _same(got, want.darkened(0.04))):
				_fail(seed_value, "cell %d,%d (%s) has the wrong colour %s" % [cx, cz, name, got])
				return
			if ch == "b":
				for step in [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]:
					var nx = cx + step.x
					var nz = cz + step.y
					if (
						nx >= 0
						and nz >= 0
						and nx < n
						and nz < n
						and str(layout["rows"][nz])[nx] != "b"
					):
						expected_walls += 1
	if walls != expected_walls:
		_fail(seed_value, "%d building walls drawn, %d face open ground" % [walls, expected_walls])
	_check_start(seed_value, layout, quads)
	_check_arrows(seed_value, layout, mesh)
	_check_clearance(seed_value, layout)


# the pink frame: four strips round the clear (2 * half + 1) cell square, centred on the start position
func _check_start(seed_value: int, layout: Dictionary, quads: Array) -> void:
	var lo = Vector2(INF, INF)
	var hi = Vector2(-INF, -INF)
	var found = 0
	for q in quads:
		if not _same(q["color"], Viewer.START_COLOR):
			continue
		for v in q["v"]:
			if v.y > 0.5:
				continue  # the pole
			lo = Vector2(minf(lo.x, v.x), minf(lo.y, v.z))
			hi = Vector2(maxf(hi.x, v.x), maxf(hi.y, v.z))
		found += 1
	var side = float(2 * int(layout["start"]["half"]) + 1) * float(layout["cell"])
	var centre = Vector2(float(layout["start"]["pos"][0]), float(layout["start"]["pos"][1]))
	if found != 9:
		_fail(seed_value, "%d start quads drawn, 9 expected (4 frame strips, pole of 5)" % found)
	elif not (hi - lo).is_equal_approx(Vector2(side, side)):
		_fail(seed_value, "start frame is %s, expected %.1f m square" % [str(hi - lo), side])
	elif not ((hi + lo) / 2.0).is_equal_approx(centre):
		_fail(
			seed_value,
			(
				"start frame is centred on %s, not on the start %s"
				% [str((hi + lo) / 2.0), str(centre)]
			)
		)


# one arrow per gate: tip a little out from the gate centre along "outward", tail inside
func _check_arrows(seed_value: int, layout: Dictionary, mesh: ArrayMesh) -> void:
	var arrays = mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var cols: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var gates: Array = layout["gates"]
	var first = verts.size() - 3 * gates.size()
	for g in range(gates.size()):
		var tip = verts[first + 3 * g]
		var tail = (verts[first + 3 * g + 1] + verts[first + 3 * g + 2]) / 2.0
		if not _same(cols[first + 3 * g], Viewer.GATE_COLOR):
			_fail(seed_value, "gate %d arrow has the wrong colour" % (g + 1))
		var at = Vector2(float(gates[g]["pos"][0]), float(gates[g]["pos"][1]))
		var out = Vector2(float(gates[g]["outward"][0]), float(gates[g]["outward"][1]))
		var way = Vector2(tip.x - tail.x, tip.z - tail.z)
		if way.normalized().dot(out) < 0.99:
			_fail(
				seed_value,
				"gate %d arrow points %s, outward is %s" % [g + 1, str(way.normalized()), str(out)]
			)
		var mid = Vector2((tip.x + tail.x) / 2.0, (tip.z + tail.z) / 2.0)
		if mid.distance_to(at) > float(layout["cell"]) * 1.5:
			_fail(
				seed_value, "gate %d arrow is %.1f m from its gate" % [g + 1, mid.distance_to(at)]
			)


func _check_clearance(seed_value: int, layout: Dictionary) -> void:
	var n = int(layout["cells"])
	var cell = float(layout["cell"])
	var half_world = float(n) * cell / 2.0
	var mesh = Viewer.build_mesh(layout, Viewer.MODE_CLEARANCE)
	var tops = {}
	for q in _quads(mesh, layout["gates"].size()):
		var v = q["v"]
		var flat = is_equal_approx(v[0].y, v[1].y) and is_equal_approx(v[1].y, v[2].y)
		if (
			flat
			and is_equal_approx(v[0].distance_to(v[1]), cell)
			and is_equal_approx(v[1].distance_to(v[2]), cell)
		):
			tops[int(floor((v[0].z + half_world) / cell + 0.0001)) * n + int(floor((v[0].x + half_world) / cell + 0.0001))] = q["color"]
	var distinct = {}
	for cz in range(n):
		for cx in range(n):
			var d = ArenaGen.nav_clearance(layout, cx, cz)
			var got: Color = tops[cz * n + cx]
			var want = Viewer.GROUND_COLORS["b"] if d == 0 else Viewer.clearance_color(d)
			if not (_same(got, want) or _same(got, want.darkened(0.04))):
				_fail(
					seed_value,
					"clearance view: cell %d,%d (clearance %d) has colour %s" % [cx, cz, d, got]
				)
				return
			distinct[d] = true
	if distinct.size() < 3:
		_fail(seed_value, "clearance view shows only %d different clearances" % distinct.size())
	if _same(Viewer.clearance_color(1), Viewer.clearance_color(2)):
		_fail(seed_value, "clearance 1 and 2 have the same colour")


# the scene as it runs: type a seed, get that arena
func _check_scene(rules: Dictionary) -> void:
	var scene = load("res://tools/viewer/arena_viewer.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	if scene.layout.is_empty() or scene.seed_value != DailyScript.today_seed():
		problems.append("the viewer does not start on today's daily seed")
	scene._on_seed_submitted("7F3A91C2")
	await process_frame
	var layout = ArenaGen.generate(0x7F3A91C2, rules)
	if scene.layout != layout:
		problems.append("typing 7F3A91C2 did not draw the layout ArenaGen makes for it")
	if scene.seed_box.text != "7F3A91C2":
		problems.append("the seed box shows %s after typing 7F3A91C2" % scene.seed_box.text)
	if (
		not scene.info.text.contains("Seed 7F3A91C2")
		or not scene.info.text.contains("validation: ok")
	):
		problems.append(
			"the text does not name the seed and say the layout is valid: " + scene.info.text
		)
	var labels = 0
	for c in scene.root.get_children():
		if c is Label3D:
			labels += 1
	if labels != layout["gates"].size() + 1:
		problems.append(
			"%d labels, %d gates and the start expected" % [labels, layout["gates"].size()]
		)
	var before = scene.layout
	scene._on_seed_submitted("not a seed")
	await process_frame
	if scene.layout != before or not scene.info.text.contains("is not a seed"):
		problems.append("a bad seed was not refused")
	scene._unhandled_input(_key(KEY_RIGHT))
	await process_frame
	if scene.seed_value != 0x7F3A91C3 or scene.layout != ArenaGen.generate(0x7F3A91C3, rules):
		problems.append("Right did not show the next seed")
	scene._unhandled_input(_key(KEY_LEFT))
	scene._unhandled_input(_key(KEY_LEFT))
	await process_frame
	if scene.seed_value != 0x7F3A91C1:
		problems.append("Left did not show the previous seed")
	scene.show_seed(0)
	scene.show_seed(scene.seed_value - 1)
	await process_frame
	if scene.seed_value != 0xFFFFFFFF:
		problems.append("the seed before 0 is %d, expected 4294967295" % scene.seed_value)
	var mode_before = scene.mode
	scene._unhandled_input(_key(KEY_C))
	await process_frame
	if scene.mode == mode_before or scene.legend.get_child_count() == 0:
		problems.append("C did not switch the colours")
	await _check_world_view(scene, rules)
	scene.queue_free()


# W: the real ground instead of the flat plan, as WorldGen builds it from the layout on show
func _check_world_view(scene: Node, rules: Dictionary) -> void:
	scene.show_seed(0x7F3A91C2)
	await process_frame
	if scene.world_view:
		problems.append("the viewer starts in the real-ground view")
	if scene.root.get_node_or_null("ArenaGround") != null:
		problems.append("the flat plan has the real ground in it")
	scene._unhandled_input(_key(KEY_W))
	await process_frame
	_check_ground_shown(scene, "W")
	# the next seed keeps the real-ground view and shows the ground of the new layout
	scene._unhandled_input(_key(KEY_RIGHT))
	await process_frame
	if scene.seed_value != 0x7F3A91C3 or scene.layout != ArenaGen.generate(0x7F3A91C3, rules):
		problems.append("Right did not show the next seed in the real-ground view")
	_check_ground_shown(scene, "Right")
	# C is for the plan: it leaves the real ground and goes to the other colours
	var mode_before = scene.mode
	scene._unhandled_input(_key(KEY_C))
	await process_frame
	if scene.world_view or scene.mode == mode_before:
		problems.append("C did not leave the real ground for the other plan colours")
	if scene.root.get_node_or_null("ArenaGround") != null:
		problems.append("the plan still has the real ground in it after C")
	if scene.info.text.contains("flat plan"):
		problems.append("the text still offers the flat plan after C: " + scene.info.text)
	# W twice is the plan again, with no light and no leftovers of the ground
	scene._unhandled_input(_key(KEY_W))
	await process_frame
	scene._unhandled_input(_key(KEY_W))
	await process_frame
	if scene.world_view or scene.root.get_node_or_null("ArenaGround") != null:
		problems.append("W twice did not go back to the flat plan")
	for c in scene.root.get_children():
		if c is DirectionalLight3D:
			problems.append("the flat plan has a light")
	if not scene.info.text.contains("W: real ground"):
		problems.append("the plan's text does not offer the real ground: " + scene.info.text)


# what the real-arena view must be showing now: the ground and the buildings and tunnels of scene.layout, a
# light, the right legend, the counts in the text and a label for every gate and the start
func _check_ground_shown(scene: Node, how: String) -> void:
	if not scene.world_view:
		problems.append("%s did not switch to the real ground" % how)
		return
	var ground = scene.root.get_node_or_null("ArenaGround")
	if ground == null:
		problems.append("%s: no ground under the viewer's root" % how)
		return
	var want = WorldGen.build_ground(scene.layout)
	if ground.get_child_count() != want["root"].get_child_count():
		problems.append(
			(
				"%s: %d ground meshes shown, WorldGen builds %d"
				% [how, ground.get_child_count(), want["root"].get_child_count()]
			)
		)
	for part_name in want["parts"]:
		var shown = ground.get_node_or_null(part_name)
		if (
			shown == null
			or (
				shown.mesh.surface_get_arrays(0)
				!= want["parts"][part_name].mesh.surface_get_arrays(0)
			)
		):
			problems.append(
				"%s: %s is not the one WorldGen builds for this layout" % [how, part_name]
			)
	if (
		int(scene.ground_stats.get("tris", -1)) != int(want["tris"])
		or int(scene.ground_stats.get("draw_calls", -1)) != int(want["draw_calls"])
	):
		problems.append(
			(
				"%s: the viewer keeps %s, WorldGen says %d triangles and %d draw calls"
				% [how, str(scene.ground_stats), int(want["tris"]), int(want["draw_calls"])]
			)
		)
	# the buildings and tunnels stand on it: the ones WorldDress builds for this layout, with their counts
	var dressing = scene.root.get_node_or_null("ArenaDressing")
	var dressed = WorldDress.build(scene.layout)
	if dressing == null:
		problems.append("%s: no buildings and tunnels under the viewer's root" % how)
	else:
		for part_name in dressed["parts"]:
			var shown = dressing.get_node_or_null(part_name)
			if (
				shown == null
				or (
					shown.mesh.surface_get_arrays(0)
					!= dressed["parts"][part_name].mesh.surface_get_arrays(0)
				)
			):
				problems.append(
					"%s: %s is not the one WorldDress builds for this layout" % [how, part_name]
				)
	if (
		int(scene.dress_stats.get("tris", -1)) != int(dressed["tris"])
		or int(scene.dress_stats.get("draw_calls", -1)) != int(dressed["draw_calls"])
	):
		(
			problems
			. append(
				(
					"%s: the viewer keeps %s for the dressing, WorldDress says %d triangles and %d draw calls"
					% [
						how,
						str(scene.dress_stats),
						int(dressed["tris"]),
						int(dressed["draw_calls"])
					]
				)
			)
		)
	var counts = "%d triangles, %d draw calls" % [int(want["tris"]), int(want["draw_calls"])]
	var dress_counts = (
		"buildings, lamps and trees: %d triangles, %d draw calls"
		% [int(dressed["tris"]), int(dressed["draw_calls"])]
	)
	dressed["root"].free()
	if (
		not scene.info.text.contains(counts)
		or not scene.info.text.contains(dress_counts)
		or not scene.info.text.contains("W: flat plan")
	):
		problems.append(
			(
				"%s: the text does not give %s and offer the flat plan: %s"
				% [how, counts, scene.info.text]
			)
		)
	var lights = 0
	var labels = 0
	for c in scene.root.get_children():
		if c is DirectionalLight3D:
			lights += 1
		elif c is Label3D:
			labels += 1
	if lights != 1:
		problems.append("%s: %d lights, the lit ground needs 1" % [how, lights])
	if labels != scene.layout["gates"].size() + 1:
		problems.append(
			(
				"%s: %d labels, %d gates and the start expected"
				% [how, labels, scene.layout["gates"].size()]
			)
		)
	# the legend names every colour on the ground and its swatches are the colours WorldGen uses
	var entries = {}
	for item in scene.legend.get_children():
		var swatch: ColorRect = item.get_child(0)
		var text: Label = item.get_child(1)
		entries[text.text.strip_edges()] = swatch.color
	var legend_want = {
		"curb": WorldGen.CURB_COLOR,
		"road paint": WorldGen.PAINT_COLOR,
		"start frame": WorldGen.HAZARD_COLOR,
		"brick building": WorldDress.BRICK_COLOR,
		"dark building": WorldDress.DARK_WALL_COLOR,
		"windows": WorldDress.WINDOW_COLOR,
		"tunnel block": Viewer.TUNNEL_BLOCK_COLOR,
		"lamp": WorldDress.METAL_COLOR,
		"tree": WorldDress.LEAF_COLOR,
	}
	for key in WorldGen.SURFACE_NAMES:
		legend_want[WorldGen.SURFACE_NAMES[key]] = WorldGen.SURFACE_STYLE[key][0]
	for name in legend_want:
		if not entries.has(name) or not _same(entries[name], legend_want[name]):
			problems.append("%s: the legend has no %s in its colour" % [how, name])
	if entries.size() != legend_want.size() + 1:
		problems.append(
			(
				"%s: the legend has %d entries, %d expected"
				% [how, entries.size(), legend_want.size() + 1]
			)
		)
	want["root"].free()


func _key(code: int) -> InputEventKey:
	var e = InputEventKey.new()
	e.keycode = code
	e.pressed = true
	return e
