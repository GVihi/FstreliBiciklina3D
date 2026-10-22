extends SceneTree
# Checks the ground that scripts/world_gen.gd builds from an arena layout (README Milestone K, "Building the
# world": ground surfaces, curbs and markings). It reads the finished meshes back and compares them with the
# layout, so it tests what would be drawn, not how WorldGen got there. Run from the project folder:
#   godot --headless --path . --script res://tools/world_gen_check.gd
# Optional argument after "--": how many seeds to build (default 100).
# For every seed it checks that
#   - every 2 m cell is covered by exactly one ground rectangle, of the ground type the layout says, flat at
#     y 0, on the cell grid (so a mirrored or swapped axis, a gap or an overlap fails)
#   - a curb stands on every cell edge where a road meets a sidewalk, plaza or grass, and on no other edge:
#     CURB_H high and CURB_W wide, centred on the edge, its sides reaching down to the ground
#   - a white edge line lies inside the road next to every curb, all paint lies on road only, and the dashed
#     centre line of every road is on its middle, a whole number of DASH_LEN dashes, clear of crossings and
#     of the road's ends by DASH_MARGIN
#   - the start frame is four strips round the clear start area: the right size, centred on the start, with
#     the middle left bare
#   - every triangle faces up and is wound the way Godot draws it (clockwise seen from above), so nothing is
#     culled away, every normal is a unit vector, and nothing lies outside the arena
#   - each ground type has its own colour, paint and curbs are lighter than the road, and each part uses its
#     colour
#   - the triangle and draw-call counts WorldGen reports are the ones in the meshes and stay small
#   - the same layout builds exactly the same meshes
# It also damages the ground nine ways (mirrored, a surface swapped, the start moved, paint, curbs or the
# start frame left out, a hole, a flipped winding, a wrong colour) and fails if the checks do not name each.
# Exits with status 1 and lists the first problems when a check fails.

const ArenaGen = preload("res://scripts/arena_gen.gd")
const WorldGen = preload("res://scripts/world_gen.gd")
const Util = preload("res://scripts/util.gd")

const EPS = 0.001
const MAX_TRIS = 2000
const MAX_DRAW_CALLS = 16
const CURB_SURFACES = "spg"  # what a road edge must meet to get a curb: not a building, a tunnel or a road

var problems = []
var tri_min = 1000000
var tri_max = 0
var call_max = 0


func _initialize() -> void:
	var count = 100
	var args = OS.get_cmdline_user_args()
	if args.size() > 0:
		count = int(args[0])
	var rules = ArenaGen.load_rules()
	if rules.is_empty():
		quit(1)
		return
	_check_colours()
	_check_sizes()
	var built_count = 0
	var first_layout = {}
	for k in range(count):
		var seed_value = (k * 2654435761 + 777) & 0xFFFFFFFF
		var layout = ArenaGen.generate(seed_value, rules)
		if layout.is_empty():
			problems.append("seed %08X: no layout was generated" % seed_value)
			continue
		var built = WorldGen.build_ground(layout)
		var found = _check_built(layout, built)
		for p in found:
			problems.append("seed %08X: %s" % [seed_value, p])
		if found.is_empty():
			_check_repeat(seed_value, layout, built)
		tri_min = mini(tri_min, int(built["tris"]))
		tri_max = maxi(tri_max, int(built["tris"]))
		call_max = maxi(call_max, int(built["draw_calls"]))
		if first_layout.is_empty():
			first_layout = layout
		built["root"].free()
		built_count += 1
	if not first_layout.is_empty():
		_check_damage(first_layout)
	if not WorldGen.build_ground({}).is_empty():
		problems.append("an empty layout did not give an empty result")
	if problems.is_empty():
		print(
			(
				"world_gen_check: %d arenas built, %d to %d triangles and at most %d draw calls; every cell is covered once by its ground, curbs and paint are where the layout says, the start frame is round the start area, and nine kinds of damage are caught"
				% [built_count, tri_min, tri_max, call_max]
			)
		)
		quit(0)
	else:
		for i in range(mini(problems.size(), 20)):
			print("FAIL: " + problems[i])
		print("world_gen_check: %d problems" % problems.size())
		quit(1)


# ---------------------------------------------------------------- reading a mesh back
# {"v": vertices, "n": normals, "i": indices} of the first surface
func _read(mesh: Mesh) -> Dictionary:
	var arrays = mesh.surface_get_arrays(0)
	return {
		"v": arrays[Mesh.ARRAY_VERTEX],
		"n": arrays[Mesh.ARRAY_NORMAL],
		"i": arrays[Mesh.ARRAY_INDEX],
	}


# every square face of a mesh as {"v": its four corners, "n": its normal}, in the order they were made
func _faces(mesh: Mesh) -> Array:
	var data = _read(mesh)
	var out = []
	var i = 0
	while i + 5 < data["i"].size():
		var base = data["i"][i]
		(
			out
			. append(
				{
					"v":
					[
						data["v"][base],
						data["v"][base + 1],
						data["v"][base + 2],
						data["v"][base + 3]
					],
					"n": data["n"][base],
				}
			)
		)
		i += 6
	return out


# the flat rectangles of a mesh as [x0, z0, x1, z1] with their height: faces that look straight up
func _tops(mesh: Mesh) -> Array:
	var out = []
	for f in _faces(mesh):
		if _up(f["n"]):
			out.append(_rect(f["v"]))
	return out


# Godot stores normals compressed, so they come back a hair off: "up" means within a few degrees of it
func _up(n: Vector3) -> bool:
	return n.dot(Vector3.UP) > 0.999


func _rect(v: Array) -> Array:
	var x0 = minf(minf(v[0].x, v[1].x), minf(v[2].x, v[3].x))
	var x1 = maxf(maxf(v[0].x, v[1].x), maxf(v[2].x, v[3].x))
	var z0 = minf(minf(v[0].z, v[1].z), minf(v[2].z, v[3].z))
	var z1 = maxf(maxf(v[0].z, v[1].z), maxf(v[2].z, v[3].z))
	return [x0, z0, x1, z1, v[0].y]


# how many of the rectangles hold the point (x, z); the edges do not count as inside
func _holding(rects: Array, x: float, z: float) -> int:
	var found = 0
	for r in rects:
		if x > r[0] + EPS and x < r[2] - EPS and z > r[1] + EPS and z < r[3] - EPS:
			found += 1
	return found


# the rectangles sorted into the 2 m cells they touch, so a point only has to be tried against the few
# rectangles near it: {cell index: [rectangles]}
func _bucket(layout: Dictionary, rects: Array) -> Dictionary:
	var n = int(layout["cells"])
	var cell = float(layout["cell"])
	var half_world = float(n) * cell / 2.0
	var out = {}
	for r in rects:
		var cx0 = int(floor((r[0] + half_world) / cell))
		var cz0 = int(floor((r[1] + half_world) / cell))
		var cx1 = int(floor((r[2] + half_world - EPS) / cell))
		var cz1 = int(floor((r[3] + half_world - EPS) / cell))
		for cz in range(cz0, cz1 + 1):
			for cx in range(cx0, cx1 + 1):
				var key = cz * n + cx
				if not out.has(key):
					out[key] = []
				out[key].append(r)
	return out


func _holding_in(layout: Dictionary, bucket: Dictionary, x: float, z: float) -> int:
	var n = int(layout["cells"])
	var cell = float(layout["cell"])
	var half_world = float(n) * cell / 2.0
	var key = int(floor((z + half_world) / cell)) * n + int(floor((x + half_world) / cell))
	return _holding(bucket.get(key, []), x, z)


func _part_mesh(built: Dictionary, part_name: String) -> Mesh:
	if not built["parts"].has(part_name):
		return null
	return built["parts"][part_name].mesh


func _part_tops(built: Dictionary, part_name: String) -> Array:
	var mesh = _part_mesh(built, part_name)
	return [] if mesh == null else _tops(mesh)


# ---------------------------------------------------------------- the checks on one arena
# Everything wrong with `built` as the ground of `layout`, in words; an empty list when it is right.
func _check_built(layout: Dictionary, built: Dictionary) -> Array:
	var found = []
	if built.is_empty() or not built.has("parts"):
		return ["nothing was built"]
	_check_ground(layout, built, found)
	_check_curbs(layout, built, found)
	_check_paint(layout, built, found)
	_check_start(layout, built, found)
	_check_meshes(layout, built, found)
	return found


func _edge(layout: Dictionary, i: int) -> float:
	return (float(i) - float(int(layout["cells"])) / 2.0) * float(layout["cell"])


func _row_char(layout: Dictionary, cx: int, cz: int) -> String:
	return str(layout["rows"][cz])[cx]


func _check_ground(layout: Dictionary, built: Dictionary, found: Array) -> void:
	var n = int(layout["cells"])
	var cell = float(layout["cell"])
	var half_world = float(n) * cell / 2.0
	var covered = PackedInt32Array()
	covered.resize(n * n)
	var kind = PackedByteArray()
	kind.resize(n * n)
	for ch in WorldGen.SURFACE_NAMES:
		for r in _part_tops(built, "ground_" + WorldGen.SURFACE_NAMES[ch]):
			if absf(r[4]) > EPS:
				found.append(
					"%s ground is at height %.3f, not 0" % [WorldGen.SURFACE_NAMES[ch], r[4]]
				)
				return
			var cx0 = (r[0] + half_world) / cell
			var cz0 = (r[1] + half_world) / cell
			var cx1 = (r[2] + half_world) / cell
			var cz1 = (r[3] + half_world) / cell
			for c in [cx0, cz0, cx1, cz1]:
				if absf(c - roundf(c)) > EPS:
					found.append("a %s rectangle is off the cell grid" % WorldGen.SURFACE_NAMES[ch])
					return
			for cz in range(int(roundf(cz0)), int(roundf(cz1))):
				for cx in range(int(roundf(cx0)), int(roundf(cx1))):
					if cx < 0 or cz < 0 or cx >= n or cz >= n:
						found.append(
							"a %s rectangle is outside the arena" % WorldGen.SURFACE_NAMES[ch]
						)
						return
					covered[cz * n + cx] += 1
					kind[cz * n + cx] = ch.unicode_at(0)
	for cz in range(n):
		for cx in range(n):
			var got = covered[cz * n + cx]
			var want = _row_char(layout, cx, cz)
			if got != 1:
				found.append("cell %d,%d (%s) is covered %d times, not once" % [cx, cz, want, got])
				return
			if kind[cz * n + cx] != want.unicode_at(0):
				found.append(
					(
						"cell %d,%d is drawn as %s, the layout says %s"
						% [
							cx,
							cz,
							WorldGen.SURFACE_NAMES[char(kind[cz * n + cx])],
							WorldGen.SURFACE_NAMES[want]
						]
					)
				)
				return


# the cell edges between two neighbouring cells where a road meets CURB_SURFACES:
# [{"x", "z": the middle of the edge in metres, "toward": a unit step from the edge into the road}]
func _curb_edges(layout: Dictionary) -> Array:
	var n = int(layout["cells"])
	var cell = float(layout["cell"])
	var out = []
	for cz in range(n):
		for cx in range(n):
			var a = _row_char(layout, cx, cz)
			for step in [Vector2i(1, 0), Vector2i(0, 1)]:
				var nx = cx + step.x
				var nz = cz + step.y
				if nx >= n or nz >= n:
					continue
				var b = _row_char(layout, nx, nz)
				var road_is_a = a == "r" and CURB_SURFACES.contains(b)
				var road_is_b = b == "r" and CURB_SURFACES.contains(a)
				if not road_is_a and not road_is_b:
					continue
				var mid = Vector2(_edge(layout, cx) + cell * 0.5, _edge(layout, cz) + cell * 0.5)
				var toward = Vector2(step)
				if step.x == 1:
					mid.x += cell * 0.5
				else:
					mid.y += cell * 0.5
				if road_is_a:
					toward = -toward
				out.append({"x": mid.x, "z": mid.y, "toward": toward})
	return out


func _check_curbs(layout: Dictionary, built: Dictionary, found: Array) -> void:
	var n = int(layout["cells"])
	var cell = float(layout["cell"])
	var curbs = _part_tops(built, "curbs")
	for r in curbs:
		if absf(r[4] - WorldGen.CURB_H) > EPS:
			found.append("a curb top is at height %.3f, not %.3f" % [r[4], WorldGen.CURB_H])
			return
		var w = minf(r[2] - r[0], r[3] - r[1])
		if absf(w - WorldGen.CURB_W) > EPS:
			found.append("a curb is %.3f m wide, not %.3f" % [w, WorldGen.CURB_W])
			return
	# the sides: each box has a top and four sides that go down to the ground
	var mesh = _part_mesh(built, "curbs")
	if mesh != null:
		for f in _faces(mesh):
			if _up(f["n"]):
				continue
			var lo = INF
			var hi = -INF
			for v in f["v"]:
				lo = minf(lo, v.y)
				hi = maxf(hi, v.y)
			if absf(lo) > EPS or absf(hi - WorldGen.CURB_H) > EPS or absf(f["n"].y) > 0.01:
				found.append("a curb side does not reach from the ground to the top")
				return
	# expected edges have exactly one curb through the middle, with the edge in the middle of its width
	var bucket = _bucket(layout, curbs)
	var expected = {}
	for e in _curb_edges(layout):
		expected["%.2f:%.2f" % [e["x"], e["z"]]] = true
		var held = _holding_in(layout, bucket, e["x"], e["z"])
		if held != 1:
			found.append("the road edge at %.1f, %.1f has %d curbs, not 1" % [e["x"], e["z"], held])
			return
	# no curb on any other edge: every curb lies along a cell line and only over edges that are expected
	for r in curbs:
		var along_x = (r[2] - r[0]) > (r[3] - r[1])
		var line = (r[1] + r[3]) * 0.5 if along_x else (r[0] + r[2]) * 0.5
		var lo = r[0] if along_x else r[1]
		var hi = r[2] if along_x else r[3]
		var grid = (line + float(n) * cell / 2.0) / cell
		if absf(grid - roundf(grid)) > EPS:
			found.append("a curb is not centred on a cell edge")
			return
		var k = 0
		while lo + cell * (float(k) + 0.5) < hi:
			var mid = lo + cell * (float(k) + 0.5)
			var key = "%.2f:%.2f" % [mid, line] if along_x else "%.2f:%.2f" % [line, mid]
			if not expected.has(key):
				found.append(
					(
						"there is a curb on an edge that has none to give, at %s"
						% key.replace(":", ", ")
					)
				)
				return
			k += 1
		if absf(hi - lo - cell * float(k)) > EPS:
			found.append("a curb does not end on a cell line")
			return


# is every cell the rectangle touches road? The corners are pulled in a hair so an edge that lies exactly on a
# cell line does not count as touching the next cell.
func _on_road(layout: Dictionary, r: Array) -> bool:
	var xs = [r[0] + EPS * 2.0, (r[0] + r[2]) * 0.5, r[2] - EPS * 2.0]
	var zs = [r[1] + EPS * 2.0, (r[1] + r[3]) * 0.5, r[3] - EPS * 2.0]
	for x in xs:
		for z in zs:
			if ArenaGen.surface_at(layout, x, z) != "road":
				return false
	return true


func _check_paint(layout: Dictionary, built: Dictionary, found: Array) -> void:
	var cell = float(layout["cell"])
	var paint = _part_tops(built, "paint")
	for r in paint:
		if r[4] <= EPS or r[4] >= WorldGen.CURB_H - EPS:
			found.append(
				"paint is at height %.3f, between the road and the curb top expected" % r[4]
			)
			return
		if not _on_road(layout, r):
			found.append(
				(
					"paint at %.1f, %.1f is not all over road"
					% [(r[0] + r[2]) * 0.5, (r[1] + r[3]) * 0.5]
				)
			)
			return
	# an edge line inside the road next to every curb
	var bucket = _bucket(layout, paint)
	for e in _curb_edges(layout):
		var at = Vector2(e["x"], e["z"]) + Vector2(e["toward"]) * WorldGen.EDGE_INSET
		if _holding_in(layout, bucket, at.x, at.y) < 1:
			found.append("no edge line next to the curb at %.1f, %.1f" % [e["x"], e["z"]])
			return
	# the centre line of each road: dashes on the middle, whole, clear of crossings and ends
	for rd in layout["roads"]:
		var ns = str(rd["dir"]) == "ns"
		var mid = _edge(layout, int(rd["centre"])) + cell * 0.5
		var dashes = []
		for r in paint:
			var across = (r[0] + r[2]) * 0.5 if ns else (r[1] + r[3]) * 0.5
			var length = (r[3] - r[1]) if ns else (r[2] - r[0])
			if absf(across - mid) < EPS and length > WorldGen.PAINT_W * 2.0:
				dashes.append(r)
		if dashes.is_empty():
			found.append("the %s road at cell %d has no centre line" % [rd["dir"], rd["centre"]])
			return
		for r in dashes:
			var length = (r[3] - r[1]) if ns else (r[2] - r[0])
			if absf(length - WorldGen.DASH_LEN) > EPS:
				found.append("a centre dash is %.2f m long, not %.2f" % [length, WorldGen.DASH_LEN])
				return
			# a point DASH_MARGIN beyond each end must still be plain road, with no road crossing it
			for end in [0, 1]:
				var along = (r[1] if end == 0 else r[3]) if ns else (r[0] if end == 0 else r[2])
				along += (-1.0 if end == 0 else 1.0) * (WorldGen.DASH_MARGIN - EPS * 4.0)
				if not _plain_road(layout, rd, mid, along):
					(
						found
						. append(
							(
								"a centre dash of the %s road at cell %d is too close to a crossing or the end of the road"
								% [rd["dir"], rd["centre"]]
							)
						)
					)
					return


# is the point `along` the road (in metres along it) on plain road: road itself and no road two cells to
# either side?
func _plain_road(layout: Dictionary, rd: Dictionary, mid: float, along: float) -> bool:
	var ns = str(rd["dir"]) == "ns"
	var cell = float(layout["cell"])
	for side in [-2.0, 0.0, 2.0]:
		var x = mid + side * cell if ns else along
		var z = along if ns else mid + side * cell
		var is_road = ArenaGen.surface_at(layout, x, z) == "road"
		if (side == 0.0) != is_road:
			return false
	return true


func _check_start(layout: Dictionary, built: Dictionary, found: Array) -> void:
	var cell = float(layout["cell"])
	var strips = _part_tops(built, "start_frame")
	if strips.size() != 4:
		found.append("the start frame has %d strips, not 4" % strips.size())
		return
	var side = float(2 * int(layout["start"]["half"]) + 1) * cell
	var centre = Vector2(float(layout["start"]["pos"][0]), float(layout["start"]["pos"][1]))
	var lo = Vector2(INF, INF)
	var hi = Vector2(-INF, -INF)
	var area = 0.0
	for r in strips:
		if absf(r[4] - WorldGen.START_Y) > EPS:
			found.append("the start frame is at height %.3f, not %.3f" % [r[4], WorldGen.START_Y])
			return
		lo = Vector2(minf(lo.x, r[0]), minf(lo.y, r[1]))
		hi = Vector2(maxf(hi.x, r[2]), maxf(hi.y, r[3]))
		area += (r[2] - r[0]) * (r[3] - r[1])
	if absf((hi - lo).x - side) > EPS or absf((hi - lo).y - side) > EPS:
		found.append("the start frame is %s m, not %.1f m square" % [str(hi - lo), side])
		return
	if ((hi + lo) / 2.0).distance_to(centre) > EPS:
		found.append(
			(
				"the start frame is centred on %s, the start is %s"
				% [str((hi + lo) / 2.0), str(centre)]
			)
		)
		return
	# four strips that do not overlap, round a bare middle: their area is the band between two squares
	var inner = side - 2.0 * WorldGen.START_W
	var band = side * side - inner * inner
	if absf(area - band) > 0.01:
		found.append("the start frame covers %.2f m2, a plain frame covers %.2f" % [area, band])
		return
	if _holding(strips, centre.x, centre.y) != 0:
		found.append("the middle of the start area is painted")
		return
	# and the whole frame is on plaza
	for r in strips:
		for p in [
			Vector2(r[0], r[1]), Vector2(r[2], r[3]), Vector2(r[0], r[3]), Vector2(r[2], r[1])
		]:
			var q = p + (centre - p).normalized() * EPS * 4.0
			if ArenaGen.surface_at(layout, q.x, q.y) != "plaza":
				found.append("the start frame is not all on plaza")
				return


# winding, normals, bounds, colours, counts
func _check_meshes(layout: Dictionary, built: Dictionary, found: Array) -> void:
	var n = int(layout["cells"])
	var cell = float(layout["cell"])
	var half_world = float(n) * cell / 2.0
	var tris = 12  # the dark plane under everything
	var parts: Dictionary = built["parts"]
	if built["root"].get_child_count() != parts.size() + 1:
		found.append(
			(
				"%d nodes under the root, %d parts and the plane expected"
				% [built["root"].get_child_count(), parts.size()]
			)
		)
		return
	for part_name in parts:
		var data = _read(parts[part_name].mesh)
		var idx: PackedInt32Array = data["i"]
		tris += idx.size() / 3
		for v in data["v"]:
			if absf(v.x) > half_world + EPS or absf(v.z) > half_world + EPS or v.y < -EPS:
				found.append("%s has a point outside the arena: %s" % [part_name, str(v)])
				return
		for nv in data["n"]:
			if absf(nv.length() - 1.0) > 0.01:
				found.append("%s has a normal that is not a unit vector" % part_name)
				return
		var t = 0
		while t + 2 < idx.size():
			var a: Vector3 = data["v"][idx[t]]
			var b: Vector3 = data["v"][idx[t + 1]]
			var c: Vector3 = data["v"][idx[t + 2]]
			var normal: Vector3 = data["n"][idx[t]]
			if (b - a).cross(c - a).dot(normal) >= 0.0:
				found.append(
					(
						"%s has a triangle wound the wrong way (it would be culled): %s"
						% [part_name, str(a)]
					)
				)
				return
			t += 3
		if not part_name.begins_with("curbs"):
			for nv in data["n"]:
				if not _up(nv):
					found.append("%s has a face that does not look up" % part_name)
					return
	if int(built["tris"]) != tris:
		found.append("WorldGen says %d triangles, the meshes hold %d" % [int(built["tris"]), tris])
	if int(built["draw_calls"]) != parts.size() + 1:
		found.append(
			(
				"WorldGen says %d draw calls, there are %d meshes"
				% [int(built["draw_calls"]), parts.size() + 1]
			)
		)
	if tris > MAX_TRIS or int(built["draw_calls"]) > MAX_DRAW_CALLS:
		found.append(
			(
				"the ground is %d triangles and %d draw calls, over the %d and %d allowed"
				% [tris, int(built["draw_calls"]), MAX_TRIS, MAX_DRAW_CALLS]
			)
		)
	for ch in WorldGen.SURFACE_NAMES:
		var present = str("".join(layout["rows"])).contains(ch)
		if present != parts.has("ground_" + WorldGen.SURFACE_NAMES[ch]):
			found.append("the %s ground part is missing or not needed" % WorldGen.SURFACE_NAMES[ch])
	_check_part_colours(built, found)


func _albedo(built: Dictionary, part_name: String) -> Color:
	var m = built["parts"][part_name].material_override
	return m.albedo_color


func _same(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) < 0.004 and absf(a.g - b.g) < 0.004 and absf(a.b - b.b) < 0.004


func _check_part_colours(built: Dictionary, found: Array) -> void:
	for ch in WorldGen.SURFACE_NAMES:
		var part_name = "ground_" + WorldGen.SURFACE_NAMES[ch]
		if (
			built["parts"].has(part_name)
			and not _same(_albedo(built, part_name), WorldGen.SURFACE_STYLE[ch][0])
		):
			found.append("%s has the wrong colour" % part_name)
	var want = {
		"curbs": WorldGen.CURB_COLOR,
		"paint": WorldGen.PAINT_COLOR,
		"start_frame": WorldGen.HAZARD_COLOR
	}
	for part_name in want:
		if built["parts"].has(part_name) and not _same(_albedo(built, part_name), want[part_name]):
			found.append("%s has the wrong colour" % part_name)


# fixed facts about the colours: they tell the ground types apart, and the paint and curbs stand out
func _check_colours() -> void:
	var seen = []
	for ch in WorldGen.SURFACE_STYLE:
		var col: Color = WorldGen.SURFACE_STYLE[ch][0]
		for other in seen:
			if _same(col, other):
				problems.append("two ground types have the same colour %s" % col.to_html())
		seen.append(col)
	var road: Color = WorldGen.SURFACE_STYLE["r"][0]
	for light in [WorldGen.PAINT_COLOR, WorldGen.CURB_COLOR]:
		if light.get_luminance() < road.get_luminance() + 0.3:
			problems.append("%s is not clearly lighter than the road" % light.to_html())
	for ch in ["g", "p", "s"]:
		if WorldGen.SURFACE_STYLE[ch][0].get_luminance() <= road.get_luminance():
			problems.append("the road is not the darkest ground (%s is darker)" % ch)
	for ch in WorldGen.SURFACE_STYLE:
		if not WorldGen.SURFACE_NAMES.has(ch):
			problems.append("ground type %s has a colour but no name" % ch)


# the sizes WorldGen is built from must be sensible ones, whatever they are set to: a curb a rider can see
# but not a wall, paint that can be seen from above, dashes with room to stop short of a crossing
func _check_sizes() -> void:
	# name: [the value WorldGen uses, lowest allowed, highest allowed]
	var limits = {
		"CURB_H": [WorldGen.CURB_H, 0.05, 0.15],
		"CURB_W": [WorldGen.CURB_W, 0.1, 0.4],
		"PAINT_W": [WorldGen.PAINT_W, 0.08, 0.3],
		"EDGE_INSET": [WorldGen.EDGE_INSET, 0.15, 0.6],
		"DASH_LEN": [WorldGen.DASH_LEN, 1.0, 3.0],
		"DASH_GAP": [WorldGen.DASH_GAP, 1.0, 3.0],
		"DASH_MARGIN": [WorldGen.DASH_MARGIN, 0.5, 2.0],
		"START_W": [WorldGen.START_W, 0.15, 0.6],
	}
	for key in limits:
		var value = float(limits[key][0])
		if value < limits[key][1] or value > limits[key][2]:
			problems.append(
				(
					"WorldGen.%s is %.3f, outside the %.2f to %.2f this check allows"
					% [key, value, limits[key][1], limits[key][2]]
				)
			)
	# the layers must stack: ground, paint, start frame, curb top
	if not (
		0.0 < WorldGen.PAINT_Y
		and WorldGen.PAINT_Y < WorldGen.START_Y
		and WorldGen.START_Y < WorldGen.CURB_H
	):
		problems.append(
			"the paint, start frame and curb heights do not stack in that order above the ground"
		)


# the same layout builds exactly the same meshes
func _check_repeat(seed_value: int, layout: Dictionary, built: Dictionary) -> void:
	var again = WorldGen.build_ground(layout)
	if again["parts"].keys() != built["parts"].keys():
		problems.append("seed %08X: a second build has different parts" % seed_value)
	else:
		for part_name in built["parts"]:
			if (
				built["parts"][part_name].mesh.surface_get_arrays(0)
				!= again["parts"][part_name].mesh.surface_get_arrays(0)
			):
				problems.append(
					"seed %08X: %s differs between two builds" % [seed_value, part_name]
				)
	again["root"].free()


# ---------------------------------------------------------------- damage
func _damaged(layout: Dictionary) -> Dictionary:
	return layout.duplicate(true)


# the damaged ground must be reported, and one of the problems must contain `needle`
func _expect_caught(label: String, needle: String, layout: Dictionary, built: Dictionary) -> void:
	var said = _check_built(layout, built)
	if said.is_empty():
		problems.append("the checks did not notice: %s" % label)
	elif not " | ".join(said).contains(needle):
		problems.append('the checks noticed "%s" but not by "%s": %s' % [label, needle, said[0]])
	built["root"].free()


# a mesh made again from vertices, normals and indices
func _remade(
	verts: PackedVector3Array, norms: PackedVector3Array, idx: PackedInt32Array
) -> ArrayMesh:
	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_INDEX] = idx
	var out = ArrayMesh.new()
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return out


# the mesh of a part with every triangle turned the other way round
func _flip(mesh: Mesh) -> ArrayMesh:
	var data = _read(mesh)
	var idx: PackedInt32Array = data["i"]
	var t = 0
	while t + 2 < idx.size():
		var keep = idx[t + 1]
		idx[t + 1] = idx[t + 2]
		idx[t + 2] = keep
		t += 3
	return _remade(data["v"], data["n"], idx)


# the mesh of a part without its last square
func _drop_last(mesh: Mesh) -> ArrayMesh:
	var data = _read(mesh)
	var verts: PackedVector3Array = data["v"]
	var norms: PackedVector3Array = data["n"]
	var idx: PackedInt32Array = data["i"]
	verts.resize(verts.size() - 4)
	norms.resize(norms.size() - 4)
	idx.resize(idx.size() - 6)
	return _remade(verts, norms, idx)


func _check_damage(layout: Dictionary) -> void:
	# mirrored: built from the layout turned east to west, judged against the real one
	var mirrored = _damaged(layout)
	var rows = []
	for row in layout["rows"]:
		var flipped = ""
		for i in range(str(row).length() - 1, -1, -1):
			flipped += str(row)[i]
		rows.append(flipped)
	mirrored["rows"] = rows
	_expect_caught(
		"an arena mirrored east to west", "drawn as", layout, WorldGen.build_ground(mirrored)
	)
	# a surface swapped: every sidewalk built as grass
	var swapped = _damaged(layout)
	var swapped_rows = []
	for row in layout["rows"]:
		swapped_rows.append(str(row).replace("s", "g"))
	swapped["rows"] = swapped_rows
	_expect_caught("sidewalks built as grass", "drawn as", layout, WorldGen.build_ground(swapped))
	# the start frame built 4 m away from the start
	var moved = _damaged(layout)
	moved["start"]["pos"] = [
		float(layout["start"]["pos"][0]) + 4.0, float(layout["start"]["pos"][1])
	]
	_expect_caught(
		"a start frame in the wrong place",
		"start frame is centred",
		layout,
		WorldGen.build_ground(moved)
	)
	# paint, curbs and the start frame left out
	var needles = {"paint": "no edge line", "curbs": "0 curbs", "start_frame": "start frame has 0"}
	for part_name in needles:
		var built = WorldGen.build_ground(layout)
		built["parts"][part_name].free()
		built["parts"].erase(part_name)
		_expect_caught("the %s part left out" % part_name, needles[part_name], layout, built)
	# a hole in the grass
	var hole = WorldGen.build_ground(layout)
	var grass: MeshInstance3D = hole["parts"]["ground_grass"]
	grass.mesh = _drop_last(grass.mesh)
	_expect_caught("a hole in the grass", "covered 0 times", layout, hole)
	# a road wound the wrong way round
	var inside_out = WorldGen.build_ground(layout)
	var road: MeshInstance3D = inside_out["parts"]["ground_road"]
	road.mesh = _flip(road.mesh)
	_expect_caught("a road wound the wrong way round", "wound the wrong way", layout, inside_out)
	# a road in the colour of grass
	var wrong = WorldGen.build_ground(layout)
	wrong["parts"]["ground_road"].material_override = Util.mat(WorldGen.SURFACE_STYLE["g"][0], 1.0)
	_expect_caught("a road in the colour of grass", "wrong colour", layout, wrong)
