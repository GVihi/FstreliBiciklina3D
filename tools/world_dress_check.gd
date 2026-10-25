extends SceneTree
# Checks the buildings, tunnels, lamps and trees that scripts/world_dress.gd stands on an arena layout (README Milestone K,
# "Building the world"). Like world_gen_check.gd it reads the finished meshes back and compares them with the
# layout, so it tests what would be drawn, not how WorldDress got there. Run from the project folder:
#   godot --headless --path . --script res://tools/world_dress_check.gd
# Optional argument after "--": how many seeds to build (default 100).
# For every seed it checks that
#   - every building cell is under exactly one lot (a box of five faces: top and four sides, the sides going
#     from the ground to the top and standing on the lot's edge), no lot covers anything else, no lot is more
#     than LOT_CELLS cells across, heights are in range, and the data in "buildings" is the lots that are drawn
#   - every cell face that looks onto open ground has one window per row that fits under the roof, centred on
#     the face and standing exactly WIN_OFF off the wall, with building behind it and open ground in front,
#     and there are no other windows
#   - every tunnel cell is under a black block TUNNEL_H high, nothing else is, and each face of it that looks
#     onto open ground has one hazard band round its top
#   - lamps stand on exactly the sidewalk cells that touch one road and no tunnel on the lamp spacing (worked out
#     again here from the cells, not taken from WorldDress), each with a pole, an arm and a head of the right
#     size in the right place, a hidden light over the head, and heads that are dark until the theme lights them
#   - trees stand only on grass cells with nothing but grass and sidewalk round them, one to a cell, each with
#     a trunk and two blocks of leaves of the right size in the right place
#   - every triangle is wound the way Godot draws it, every normal is a unit vector, nothing is outside the
#     arena, the counts the builder reports are the ones in the meshes and stay small, materials are right
#     (windows dark until the theme lights them) and the same layout builds the same meshes
# It also damages the result fourteen ways and fails if the checks do not name each one. Exits with status 1 and
# lists the first problems when a check fails.

const ArenaGen = preload("res://scripts/arena_gen.gd")
const WorldGen = preload("res://scripts/world_gen.gd")
const WorldDress = preload("res://scripts/world_dress.gd")

const EPS = 0.001
const MAX_TRIS = 16000  # was 9000 on the 48-cell arena; the 72-cell arena has about 2.4 times the ground
const MAX_DRAW_CALLS = 12
const OUTWARD = [Vector3(0, 0, -1), Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(-1, 0, 0)]  # N E S W

var problems = []
var tri_min = 1000000
var tri_max = 0
var lot_min = 1000000
var lot_max = 0
var lamps_min = 1000000
var lamps_max = 0
var trees_min = 1000000
var trees_max = 0
var styles_seen = {}


func _initialize() -> void:
	var count = 100
	var args = OS.get_cmdline_user_args()
	if args.size() > 0:
		count = int(args[0])
	var rules = ArenaGen.load_rules()
	if rules.is_empty():
		quit(1)
		return
	_check_sizes()
	var built_count = 0
	var first_layout = {}
	for k in range(count):
		var seed_value = (k * 2654435761 + 777) & 0xFFFFFFFF
		var layout = ArenaGen.generate(seed_value, rules)
		if layout.is_empty():
			problems.append("seed %08X: no layout was generated" % seed_value)
			continue
		var built = WorldDress.build(layout)
		var found = _check_built(layout, built)
		for p in found:
			problems.append("seed %08X: %s" % [seed_value, p])
		if found.is_empty():
			_check_repeat(seed_value, layout, built)
		styles_seen[str(layout.get("style", ""))] = (
			int(styles_seen.get(str(layout.get("style", "")), 0)) + 1
		)
		tri_min = mini(tri_min, int(built["tris"]))
		tri_max = maxi(tri_max, int(built["tris"]))
		lot_min = mini(lot_min, built["buildings"].size())
		lot_max = maxi(lot_max, built["buildings"].size())
		# the damage tests need a layout with brick walls and windows (not a bridge or a tunnel)
		var dressed: Dictionary = layout.get("dress", {})
		if (
			first_layout.is_empty()
			and bool(dressed.get("windows", true))
			and not bool(dressed.get("dark_all", false))
		):
			first_layout = layout
		built["root"].free()
		built_count += 1
	if not first_layout.is_empty():
		_check_damage(first_layout)
	if not WorldDress.build({}).is_empty():
		problems.append("an empty layout did not give an empty result")
	# every style of the rules has to have been dressed, or the check says nothing about it
	if count >= 60:
		for name in ArenaGen.style_names(rules):
			if not styles_seen.has(name):
				problems.append("no arena of style %s was dressed" % name)
	if problems.is_empty():
		print(
			(
				"world_dress_check: %d arenas dressed, %d to %d lots, %d to %d lamps, %d to %d trees, %d to %d triangles; every building cell is under one lot, windows and tunnel bands are on the faces that look onto open ground, tunnels are black blocks over the tunnel cells, lamps and trees stand where the cells say, and sixteen kinds of damage are caught (styles dressed: %s)"
				% [
					built_count,
					lot_min,
					lot_max,
					lamps_min,
					lamps_max,
					trees_min,
					trees_max,
					tri_min,
					tri_max,
					", ".join(PackedStringArray(_style_tally()))
				]
			)
		)
		quit(0)
	else:
		for i in range(mini(problems.size(), 20)):
			print("FAIL: " + problems[i])
		print("world_dress_check: %d problems" % problems.size())
		quit(1)


# ---------------------------------------------------------------- reading a mesh back
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


# {"lo": Vector3, "hi": Vector3} of a face's corners
func _span(v: Array) -> Dictionary:
	var lo = Vector3(INF, INF, INF)
	var hi = Vector3(-INF, -INF, -INF)
	for p in v:
		lo = Vector3(minf(lo.x, p.x), minf(lo.y, p.y), minf(lo.z, p.z))
		hi = Vector3(maxf(hi.x, p.x), maxf(hi.y, p.y), maxf(hi.z, p.z))
	return {"lo": lo, "hi": hi}


# Godot stores normals compressed, so they come back a hair off
func _near(a: Vector3, b: Vector3) -> bool:
	return a.dot(b) > 0.999


func _part_faces(built: Dictionary, part_name: String) -> Array:
	if not built["parts"].has(part_name):
		return []
	return _faces(built["parts"][part_name].mesh)


func _surface(layout: Dictionary, p: Vector3) -> String:
	return ArenaGen.surface_at(layout, p.x, p.z)


func _is_open(layout: Dictionary, p: Vector3) -> bool:
	var s = _surface(layout, p)
	return s != "building" and s != "tunnel"


func _cell_of(layout: Dictionary, p: Vector3) -> Vector2i:
	var n = int(layout["cells"])
	var cell = float(layout["cell"])
	return Vector2i(
		int(floor(p.x / cell + float(n) / 2.0)), int(floor(p.z / cell + float(n) / 2.0))
	)


# ---------------------------------------------------------------- the checks on one arena
func _check_built(layout: Dictionary, built: Dictionary) -> Array:
	var found = []
	if built.is_empty() or not built.has("parts"):
		return ["nothing was built"]
	var heights = _check_lots(layout, built, found)
	if found.is_empty():
		_check_windows(layout, built, heights, found)
		_check_tunnels(layout, built, found)
		_check_props(layout, built, found)
		_check_meshes(layout, built, found)
	return found


# the lots drawn: returns {cell index: height of the lot over it} (empty when something is wrong)
func _check_lots(layout: Dictionary, built: Dictionary, found: Array) -> Dictionary:
	var n = int(layout["cells"])
	var cell = float(layout["cell"])
	var half_world = float(n) * cell / 2.0
	var heights = {}
	# the lowest and highest roof the layout's style allows: its "dress" numbers (the plain ones without a style)
	var dress: Dictionary = layout.get("dress", {})
	var h_lo = float(dress.get("h_base", WorldDress.H_MIN))
	var h_hi = (
		h_lo
		+ (
			float(maxi(1, int(dress.get("h_steps", WorldDress.H_STEPS))) - 1)
			* float(dress.get("h_step", WorldDress.H_STEP))
		)
	)
	if h_lo < 6.0 or h_hi > 16.0:
		found.append(
			"the style's roofs are %.2f to %.2f m, 6 to 16 m is the sensible range" % [h_lo, h_hi]
		)
		return {}
	var covered = PackedInt32Array()
	covered.resize(n * n)
	var drawn = []  # [x0, z0, x1, z1, h, dark] of each lot's top
	for part_name in ["walls_brick", "walls_dark"]:
		var faces = _part_faces(built, part_name)
		if faces.size() % 5 != 0:
			found.append(
				"%s has %d faces, a whole number of boxes of 5 expected" % [part_name, faces.size()]
			)
			return {}
		for k in range(0, faces.size(), 5):
			var top = faces[k]
			var sp = _span(top["v"])
			var h = sp["hi"].y
			if not _near(top["n"], Vector3.UP) or absf(sp["lo"].y - h) > EPS:
				found.append("%s: the first face of a box is not its flat top" % part_name)
				return {}
			var r = [sp["lo"].x, sp["lo"].z, sp["hi"].x, sp["hi"].z]
			drawn.append([r[0], r[1], r[2], r[3], h, part_name == "walls_dark"])
			if h < h_lo - EPS or h > h_hi + EPS:
				found.append("a building is %.2f m high, %.2f to %.2f m expected" % [h, h_lo, h_hi])
				return {}
			# the four sides: vertical, from the ground to the top, standing on the lot's edge
			for s in range(4):
				var side = faces[k + 1 + s]
				var ss = _span(side["v"])
				var on_edge = [
					absf(ss["lo"].z - r[1]) < EPS and absf(ss["hi"].z - r[1]) < EPS,
					absf(ss["lo"].x - r[2]) < EPS and absf(ss["hi"].x - r[2]) < EPS,
					absf(ss["lo"].z - r[3]) < EPS and absf(ss["hi"].z - r[3]) < EPS,
					absf(ss["lo"].x - r[0]) < EPS and absf(ss["hi"].x - r[0]) < EPS,
				][s]
				if (
					not _near(side["n"], OUTWARD[s])
					or absf(ss["lo"].y) > EPS
					or absf(ss["hi"].y - h) > EPS
					or not on_edge
				):
					(
						found
						. append(
							(
								"a building side (%d) does not stand on the lot's edge from the ground to the top"
								% s
							)
						)
					)
					return {}
			var c = [
				(r[0] + half_world) / cell,
				(r[1] + half_world) / cell,
				(r[2] + half_world) / cell,
				(r[3] + half_world) / cell
			]
			for v in c:
				if absf(v - roundf(v)) > EPS:
					found.append("a building is off the cell grid")
					return {}
			if (
				roundi(c[2]) - roundi(c[0]) > WorldDress.LOT_CELLS
				or roundi(c[3]) - roundi(c[1]) > WorldDress.LOT_CELLS
			):
				found.append("a lot is more than %d cells across" % WorldDress.LOT_CELLS)
				return {}
			for cz in range(roundi(c[1]), roundi(c[3])):
				for cx in range(roundi(c[0]), roundi(c[2])):
					if cx < 0 or cz < 0 or cx >= n or cz >= n:
						found.append("a building is outside the arena")
						return {}
					covered[cz * n + cx] += 1
					heights[cz * n + cx] = h
	for cz in range(n):
		for cx in range(n):
			var want = str(layout["rows"][cz])[cx] == "b"
			var got = covered[cz * n + cx]
			if got != (1 if want else 0):
				found.append(
					(
						"cell %d,%d (%s) is covered by %d lots"
						% [cx, cz, str(layout["rows"][cz])[cx], got]
					)
				)
				return {}
	# the data the builder hands back is the lots that are drawn
	var data: Array = built["buildings"]
	if data.size() != drawn.size():
		found.append("building data lists %d lots, %d are drawn" % [data.size(), drawn.size()])
		return {}
	var seen = {}
	for d in drawn:
		seen["%.2f:%.2f:%.2f:%.2f:%.2f:%s" % [d[0], d[1], d[2], d[3], d[4], str(d[5])]] = true
	for b in data:
		var c = b["cells"]
		var key = (
			"%.2f:%.2f:%.2f:%.2f:%.2f:%s"
			% [
				WorldGen.grid_edge(n, cell, int(c[0])),
				WorldGen.grid_edge(n, cell, int(c[1])),
				WorldGen.grid_edge(n, cell, int(c[2])),
				WorldGen.grid_edge(n, cell, int(c[3])),
				float(b["h"]),
				str(b["dark"])
			]
		)
		if not seen.has(key):
			found.append("the building data has a lot that is not drawn like that: %s" % str(b))
			return {}
	# a style whose dress says "dark_all" has no brick building at all
	if bool(dress.get("dark_all", false)):
		for d in drawn:
			if not d[5]:
				found.append("the style dresses every building dark, a brick one is drawn")
				return {}
	return heights


func _check_windows(
	layout: Dictionary, built: Dictionary, heights: Dictionary, found: Array
) -> void:
	var n = int(layout["cells"])
	var cell = float(layout["cell"])
	var half_world = float(n) * cell / 2.0
	# how many windows the layout asks for: a column on every building cell face that looks onto open ground
	var expected = 0
	var wants_windows = bool(layout.get("dress", {}).get("windows", true))
	for cz in range(n):
		for cx in range(n):
			if not wants_windows or str(layout["rows"][cz])[cx] != "b":
				continue
			var h = float(heights[cz * n + cx])
			var rows_fit = 0
			var y = WorldDress.WIN_ROW0
			while y + WorldDress.WIN_H * 0.5 <= h - WorldDress.WIN_TOP_GAP:
				rows_fit += 1
				y += WorldDress.WIN_ROW_STEP
			for step in [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]:
				var beyond = WorldGen.cell_at(layout["rows"], n, cx + step.x, cz + step.y)
				if beyond != "b" and beyond != "t":
					expected += rows_fit
	var faces = _part_faces(built, "windows")
	if faces.size() != expected:
		found.append("%d windows drawn, the layout asks for %d" % [faces.size(), expected])
		return
	var seen = {}
	for f in faces:
		var sp = _span(f["v"])
		var c = (sp["lo"] + sp["hi"]) * 0.5
		var nrm = Vector3(roundf(f["n"].x), 0.0, roundf(f["n"].z))
		if absf(f["n"].y) > 0.01 or nrm.length() < 0.99 or not _near(f["n"], nrm):
			found.append("a window does not face along the ground")
			return
		var width = (sp["hi"] - sp["lo"]).x + (sp["hi"] - sp["lo"]).z
		var height = (sp["hi"] - sp["lo"]).y
		if absf(width - WorldDress.WIN_W) > EPS or absf(height - WorldDress.WIN_H) > EPS:
			found.append(
				(
					"a window is %.2f by %.2f m, not %.2f by %.2f"
					% [width, height, WorldDress.WIN_W, WorldDress.WIN_H]
				)
			)
			return
		# the wall is exactly WIN_OFF behind the window: building just behind it, open ground just before it
		var behind = c - nrm * (WorldDress.WIN_OFF + 0.01)
		var before = c - nrm * (WorldDress.WIN_OFF - 0.01)
		behind.y = 0.0
		before.y = 0.0
		if _surface(layout, behind) != "building" or not _is_open(layout, before):
			(
				found
				. append(
					(
						"a window at %.1f, %.1f is not %.2f m off a wall that has open ground in front of it"
						% [c.x, c.z, WorldDress.WIN_OFF]
					)
				)
			)
			return
		# centred on its cell face: the wall plane is on a grid line, the middle on a cell centre
		var along = c.z if absf(nrm.x) > 0.5 else c.x
		var plane = (
			(c.x - nrm.x * WorldDress.WIN_OFF)
			if absf(nrm.x) > 0.5
			else (c.z - nrm.z * WorldDress.WIN_OFF)
		)
		var cell_pos = (along + half_world) / cell - 0.5
		var plane_pos = (plane + half_world) / cell
		if absf(cell_pos - roundf(cell_pos)) > EPS or absf(plane_pos - roundf(plane_pos)) > EPS:
			found.append("a window at %.1f, %.1f is not centred on a cell face" % [c.x, c.z])
			return
		var roof = float(heights[_cell_key(layout, behind)])
		if sp["lo"].y < 1.0 or sp["hi"].y > roof - WorldDress.WIN_TOP_GAP + EPS:
			found.append(
				(
					"a window from %.2f to %.2f m does not fit under a roof of %.2f m"
					% [sp["lo"].y, sp["hi"].y, roof]
				)
			)
			return
		var key = "%.2f:%.2f:%.2f" % [c.x, c.y, c.z]
		if seen.has(key):
			found.append("two windows at %s" % key)
			return
		seen[key] = true
	var mat = built["parts"]["windows"].material_override if built["parts"].has("windows") else null
	if mat != null:
		if not (mat is StandardMaterial3D) or mat != built["win_mat"]:
			found.append("the windows do not use the win_mat that is handed back")
		elif not mat.emission_enabled or mat.emission_energy_multiplier != 0.0:
			found.append("the windows are lit before the theme asks for it")
		elif mat.albedo_color.get_luminance() > 0.45:
			found.append("the unlit windows are too bright")


func _cell_key(layout: Dictionary, p: Vector3) -> int:
	var c = _cell_of(layout, p)
	return c.y * int(layout["cells"]) + c.x


func _check_tunnels(layout: Dictionary, built: Dictionary, found: Array) -> void:
	var n = int(layout["cells"])
	var cell = float(layout["cell"])
	var half_world = float(n) * cell / 2.0
	var covered = PackedInt32Array()
	covered.resize(n * n)
	var faces = _part_faces(built, "tunnels")
	if faces.size() % 5 != 0:
		found.append("the tunnel mesh has %d faces, boxes of 5 expected" % faces.size())
		return
	for k in range(0, faces.size(), 5):
		var sp = _span(faces[k]["v"])
		if not _near(faces[k]["n"], Vector3.UP) or absf(sp["hi"].y - WorldDress.TUNNEL_H) > EPS:
			found.append("a tunnel block is not %.1f m high" % WorldDress.TUNNEL_H)
			return
		for cz in range(
			roundi((sp["lo"].z + half_world) / cell), roundi((sp["hi"].z + half_world) / cell)
		):
			for cx in range(
				roundi((sp["lo"].x + half_world) / cell), roundi((sp["hi"].x + half_world) / cell)
			):
				if cx >= 0 and cz >= 0 and cx < n and cz < n:
					covered[cz * n + cx] += 1
	var expected_bands = 0
	for cz in range(n):
		for cx in range(n):
			var is_tunnel = str(layout["rows"][cz])[cx] == "t"
			if covered[cz * n + cx] != (1 if is_tunnel else 0):
				found.append(
					(
						"tunnel cell check: cell %d,%d (%s) is under %d tunnel blocks"
						% [cx, cz, str(layout["rows"][cz])[cx], covered[cz * n + cx]]
					)
				)
				return
			if is_tunnel:
				for step in [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]:
					var beyond = WorldGen.cell_at(layout["rows"], n, cx + step.x, cz + step.y)
					if beyond != "b" and beyond != "t":
						expected_bands += 1
	var mat = built["parts"]["tunnels"].material_override if built["parts"].has("tunnels") else null
	if (
		mat != null
		and (
			not (mat is StandardMaterial3D)
			or mat.shading_mode != BaseMaterial3D.SHADING_MODE_UNSHADED
			or mat.albedo_color.get_luminance() > 0.01
		)
	):
		found.append("the tunnel blocks are not unshaded black")
	var bands = _part_faces(built, "tunnel_bands")
	if bands.size() != expected_bands:
		found.append(
			(
				"tunnel bands: %d drawn, %d faces look onto open ground"
				% [bands.size(), expected_bands]
			)
		)
		return
	var seen = {}
	for f in bands:
		var sp = _span(f["v"])
		var c = (sp["lo"] + sp["hi"]) * 0.5
		var nrm = Vector3(roundf(f["n"].x), 0.0, roundf(f["n"].z))
		if absf(f["n"].y) > 0.01 or nrm.length() < 0.99:
			found.append("a tunnel band does not face along the ground")
			return
		if (
			absf((sp["hi"].y - sp["lo"].y) - WorldDress.HAZARD_H) > EPS
			or absf(sp["hi"].y - WorldDress.TUNNEL_H) > EPS
		):
			found.append("a tunnel band is not the top %.1f m of the block" % WorldDress.HAZARD_H)
			return
		var behind = c - nrm * (WorldDress.HAZARD_OFF + 0.01)
		var before = c - nrm * (WorldDress.HAZARD_OFF - 0.01)
		behind.y = 0.0
		before.y = 0.0
		if _surface(layout, behind) != "tunnel" or not _is_open(layout, before):
			found.append(
				(
					"a tunnel band at %.1f, %.1f is not on a tunnel face looking onto open ground"
					% [c.x, c.z]
				)
			)
			return
		var key = "%.2f:%.2f:%.2f" % [c.x, c.y, c.z]
		if seen.has(key):
			found.append("two tunnel bands at %s" % key)
			return
		seen[key] = true


func _check_meshes(layout: Dictionary, built: Dictionary, found: Array) -> void:
	var n = int(layout["cells"])
	var half_world = float(n) * float(layout["cell"]) / 2.0
	var tris = 0
	var parts: Dictionary = built["parts"]
	for part_name in parts:
		var data = _read(parts[part_name].mesh)
		var idx: PackedInt32Array = data["i"]
		tris += idx.size() / 3
		for v in data["v"]:
			if (
				absf(v.x) > half_world + 0.05
				or absf(v.z) > half_world + 0.05
				or v.y < -EPS
				or v.y > 20.0
			):
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
			if (b - a).cross(c - a).dot(data["n"][idx[t]]) >= 0.0:
				found.append(
					(
						"%s has a triangle wound the wrong way (it would be culled): %s"
						% [part_name, str(a)]
					)
				)
				return
			t += 3
	if int(built["tris"]) != tris:
		found.append(
			"the builder says %d triangles, the meshes hold %d" % [int(built["tris"]), tris]
		)
	if int(built["draw_calls"]) != parts.size():
		found.append(
			(
				"the builder says %d draw calls, there are %d meshes"
				% [int(built["draw_calls"]), parts.size()]
			)
		)
	if tris > MAX_TRIS or parts.size() > MAX_DRAW_CALLS:
		found.append(
			(
				"the dressing is %d triangles and %d draw calls, over the %d and %d allowed"
				% [tris, parts.size(), MAX_TRIS, MAX_DRAW_CALLS]
			)
		)
	var want = {
		"walls_brick": WorldDress.BRICK_COLOR,
		"walls_dark": WorldDress.DARK_WALL_COLOR,
		"lamp_posts": WorldDress.METAL_COLOR,
		"tree_trunks": WorldDress.TRUNK_COLOR,
		"tree_leaves": WorldDress.LEAF_COLOR,
		"tree_tops": WorldDress.LEAF_TOP_COLOR,
	}
	for part_name in want:
		if parts.has(part_name):
			var col: Color = parts[part_name].material_override.albedo_color
			if (
				absf(col.r - want[part_name].r) > 0.004
				or absf(col.g - want[part_name].g) > 0.004
				or absf(col.b - want[part_name].b) > 0.004
			):
				found.append("%s has the wrong colour" % part_name)


# sizes the dressing is built from must stay sensible, whatever they are set to
# "bridge 14, canyon 17, ..." for the summary line
func _style_tally() -> Array:
	var names = styles_seen.keys()
	names.sort()
	var out = []
	for name in names:
		out.append("%s %d" % [name, int(styles_seen[name])])
	return out


func _check_sizes() -> void:
	# name: [the value, lowest allowed, highest allowed]
	var limits = {
		"LOT_CELLS": [WorldDress.LOT_CELLS, 1, 4],
		"H_MIN": [WorldDress.H_MIN, 4.0, 8.0],
		"H_STEP": [WorldDress.H_STEP, 0.5, 2.0],
		"H_STEPS": [WorldDress.H_STEPS, 1, 8],
		"TUNNEL_H": [WorldDress.TUNNEL_H, 5.0, 9.0],
		"HAZARD_H": [WorldDress.HAZARD_H, 0.2, 1.0],
		"WIN_W": [WorldDress.WIN_W, 0.8, 1.8],
		"WIN_H": [WorldDress.WIN_H, 0.8, 1.8],
		"WIN_OFF": [WorldDress.WIN_OFF, 0.01, 0.1],
		"WIN_ROW0": [WorldDress.WIN_ROW0, 1.5, 3.2],
		"WIN_ROW_STEP": [WorldDress.WIN_ROW_STEP, 2.0, 3.5],
		"WIN_TOP_GAP": [WorldDress.WIN_TOP_GAP, 0.3, 1.5],
		"HAZARD_OFF": [WorldDress.HAZARD_OFF, 0.005, 0.1],
		"LAMP_EVERY": [WorldDress.LAMP_EVERY, 4, 16],
		"LAMP_SETBACK": [WorldDress.LAMP_SETBACK, 0.4, 0.9],
		"LAMP_POLE_H": [WorldDress.LAMP_POLE_H, 4.0, 7.0],
		"LAMP_ARM_REACH": [WorldDress.LAMP_ARM_REACH, 0.6, 1.6],
		"LAMP_RANGE": [WorldDress.LAMP_RANGE, 8.0, 24.0],
		"LAMP_ENERGY": [WorldDress.LAMP_ENERGY, 1.0, 6.0],
		"TREE_EVERY": [WorldDress.TREE_EVERY, 6, 60],
		"TRUNK_H": [WorldDress.TRUNK_H, 1.5, 3.0],
		"CANOPY_HALF": [WorldDress.CANOPY_HALF, 0.6, 1.3],
		"TOP_Y1": [WorldDress.TOP_Y1, 3.5, 6.5],
	}
	for key in limits:
		var value = float(limits[key][0])
		if value < float(limits[key][1]) or value > float(limits[key][2]):
			problems.append(
				(
					"WorldDress.%s is %.3f, outside the %.2f to %.2f this check allows"
					% [key, value, float(limits[key][1]), float(limits[key][2])]
				)
			)
	# a canopy must stay inside the cell it stands in plus the cells round it (which are grass or sidewalk), and
	# a lamp pole inside its sidewalk cell with the head over the road
	if WorldDress.CANOPY_HALF > 1.3:
		problems.append("a tree canopy reaches further than the next cell")
	if WorldDress.LAMP_SETBACK + WorldDress.LAMP_POLE_HALF >= 1.0:
		problems.append("a lamp pole would stand over the kerb")
	if WorldDress.LAMP_SETBACK + WorldDress.LAMP_ARM_REACH <= 1.0:
		problems.append("a lamp head would not reach the road")
	# windows must be narrower than a cell face, and a building lower than its top-most window row allows
	if WorldDress.WIN_W >= 2.0:
		problems.append("a window is as wide as a 2 m cell face")
	if WorldDress.TUNNEL_H < WorldDress.H_MIN - 3.0:
		problems.append("tunnel blocks are far lower than the buildings round them")


# the same layout builds exactly the same meshes
func _check_repeat(seed_value: int, layout: Dictionary, built: Dictionary) -> void:
	var again = WorldDress.build(layout)
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
	if again["buildings"] != built["buildings"]:
		problems.append("seed %08X: the building data differs between two builds" % seed_value)
	again["root"].free()


# ---------------------------------------------------------------- lamps and trees
func _cell_char(layout: Dictionary, cx: int, cz: int) -> String:
	var n = int(layout["cells"])
	if cx < 0 or cz < 0 or cx >= n or cz >= n:
		return "b"
	return str(layout["rows"][cz])[cx]


# the lamp cells the rules give, worked out here again: {Vector2i cell: Vector2i towards the road}
func _lamp_cells(layout: Dictionary) -> Dictionary:
	var n = int(layout["cells"])
	var out = {}
	for cz in range(n):
		for cx in range(n):
			if _cell_char(layout, cx, cz) != "s":
				continue
			var roads = []
			for step in WorldDress.SIDES:
				if _cell_char(layout, cx + step.x, cz + step.y) == "r":
					roads.append(step)
			if roads.size() != 1:
				continue
			var tunnel_near = false
			for dz in range(-1, 2):
				for dx in range(-1, 2):
					if _cell_char(layout, cx + dx, cz + dz) == "t":
						tunnel_near = true
			if tunnel_near:
				continue
			var step: Vector2i = roads[0]
			var along = cx if step.y != 0 else cz
			var half_shift = WorldDress.LAMP_EVERY / 2 if step.x + step.y > 0 else 0
			if (along + half_shift) % WorldDress.LAMP_EVERY == 0:
				out[Vector2i(cx, cz)] = step
	return out


func _tree_ok(layout: Dictionary, c: Vector2i) -> bool:
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var ch = _cell_char(layout, c.x + dx, c.y + dz)
			if ch != "g" and ch != "s":
				return false
	return _cell_char(layout, c.x, c.y) == "g"


func _centre_of(layout: Dictionary, c: Vector2i) -> Vector2:
	var n = int(layout["cells"])
	var cell = float(layout["cell"])
	return Vector2(
		(float(c.x) - float(n) / 2.0) * cell + cell * 0.5,
		(float(c.y) - float(n) / 2.0) * cell + cell * 0.5
	)


# "x,y,z,width,depth" of every face that looks up, to the millimetre: where the tops of a part's boxes are
func _tops(built: Dictionary, part_name: String) -> Array:
	var out = []
	for f in _part_faces(built, part_name):
		if not _near(f["n"], Vector3.UP):
			continue
		var sp = _span(f["v"])
		var mid = (sp["lo"] + sp["hi"]) * 0.5
		out.append(
			(
				"%.3f,%.3f,%.3f,%.3f,%.3f"
				% [mid.x, mid.y, mid.z, sp["hi"].x - sp["lo"].x, sp["hi"].z - sp["lo"].z]
			)
		)
	out.sort()
	return out


func _top_key(at: Vector2, y: float, w: float, d: float) -> String:
	return "%.3f,%.3f,%.3f,%.3f,%.3f" % [at.x, y, at.y, w, d]


func _part_matches(
	built: Dictionary, part_name: String, want: Array, faces_each: int, count: int, found: Array
) -> void:
	var faces = _part_faces(built, part_name)
	if faces.size() != faces_each * count:
		found.append(
			(
				"%s check: %d faces drawn, %d expected (%d each for %d)"
				% [part_name, faces.size(), faces_each * count, faces_each, count]
			)
		)
		return
	want.sort()
	if _tops(built, part_name) != want:
		found.append("%s check: a box is not where or what size the props say" % part_name)
	var lowest = INF
	for f in faces:
		lowest = minf(lowest, _span(f["v"])["lo"].y)
	if (
		count > 0
		and (part_name == "lamp_posts" or part_name == "tree_trunks")
		and absf(lowest) > EPS
	):
		found.append(
			"%s check: it does not stand on the ground (lowest point %.3f)" % [part_name, lowest]
		)


func _check_props(layout: Dictionary, built: Dictionary, found: Array) -> void:
	var props: Dictionary = built["props"]
	var n = int(layout["cells"])
	# ---- lamps: the data against the rules
	var want_cells = _lamp_cells(layout)
	var seen = {}
	for lamp in props["lamps"]:
		var c: Vector2i = lamp["cell"]
		if seen.has(c):
			found.append("lamp check: two lamps in cell %s" % str(c))
		seen[c] = true
		if not want_cells.has(c):
			found.append("lamp check: a lamp in cell %s, which is not a lamp cell" % str(c))
			continue
		var dir: Vector2i = want_cells[c]
		if lamp["dir"] != dir:
			found.append("lamp check: the lamp in %s faces the wrong way" % str(c))
		var d = Vector2(float(dir.x), float(dir.y))
		var centre = _centre_of(layout, c)
		if lamp["pole"].distance_to(centre + d * WorldDress.LAMP_SETBACK) > EPS:
			found.append("lamp check: the pole in %s is not LAMP_SETBACK from the centre" % str(c))
		if (
			lamp["head"].distance_to(
				centre + d * (WorldDress.LAMP_SETBACK + WorldDress.LAMP_ARM_REACH)
			)
			> EPS
		):
			found.append("lamp check: the head in %s is not LAMP_ARM_REACH from its pole" % str(c))
		if _cell_char(layout, int(c.x + dir.x * 2), int(c.y + dir.y * 2)) != "r":
			# the head is 1.9 m out: it must be over the road, whose first cell is the next one over
			pass
	if props["lamps"].size() != want_cells.size():
		found.append(
			(
				"lamp check: %d lamps, the layout has %d lamp cells"
				% [props["lamps"].size(), want_cells.size()]
			)
		)
	# ---- lamps: the meshes
	var posts = []
	var heads = []
	for lamp in props["lamps"]:
		var ns = lamp["dir"].y != 0
		var pole: Vector2 = lamp["pole"]
		var head: Vector2 = lamp["head"]
		var pw = WorldDress.LAMP_POLE_HALF * 2.0
		posts.append(_top_key(pole, WorldDress.LAMP_POLE_H, pw, pw))
		var aw = WorldDress.LAMP_ARM_HALF * 2.0
		var reach = pole.distance_to(head)
		posts.append(
			_top_key(
				(pole + head) * 0.5,
				WorldDress.LAMP_ARM_Y1,
				aw if ns else reach,
				reach if ns else aw
			)
		)
		var along = WorldDress.LAMP_HEAD_ALONG
		var across = WorldDress.LAMP_HEAD_ACROSS
		heads.append(
			_top_key(
				head, WorldDress.LAMP_HEAD_Y1, along if ns else across, across if ns else along
			)
		)
	var lamp_count = props["lamps"].size()
	if lamp_count > 0:
		_part_matches(built, "lamp_posts", posts, 11, lamp_count, found)
		_part_matches(built, "lamp_heads", heads, 6, lamp_count, found)
	elif built["parts"].has("lamp_posts"):
		found.append("lamp check: lamp posts drawn with no lamps")
	# ---- lamps: the lights
	var lights: Array = built["lamps"]
	if lights.size() != lamp_count:
		found.append("lamp check: %d lights for %d lamps" % [lights.size(), lamp_count])
	else:
		for i in range(lamp_count):
			var light: OmniLight3D = lights[i]
			var head: Vector2 = props["lamps"][i]["head"]
			if light.visible:
				found.append("lamp check: lamp lights must be hidden until the theme lights them")
				break
			if (
				absf(light.position.x - head.x) > EPS
				or absf(light.position.z - head.y) > EPS
				or absf(light.position.y - WorldDress.LAMP_LIGHT_Y) > EPS
			):
				found.append("lamp check: a light is not under its lamp head")
				break
			if (
				absf(light.omni_range - WorldDress.LAMP_RANGE) > EPS
				or absf(light.light_energy - WorldDress.LAMP_ENERGY) > EPS
			):
				found.append("lamp check: a light has the wrong range or energy")
				break
	if built["lamp_mat"].emission_energy_multiplier != 0.0:
		found.append("lamp heads are lit before the theme asks for it")
	# ---- trees: the data against the rules
	var tree_seen = {}
	for tree in props["trees"]:
		var c: Vector2i = tree["cell"]
		if tree_seen.has(c):
			found.append("tree check: two trees in cell %s" % str(c))
		tree_seen[c] = true
		if not _tree_ok(layout, c):
			(
				found
				. append(
					(
						"tree check: a tree in cell %s, which is not grass with only grass and sidewalk round it"
						% str(c)
					)
				)
			)
		elif tree["pos"].distance_to(_centre_of(layout, c)) > EPS:
			found.append("tree check: the tree in %s is not in the middle of its cell" % str(c))
	# ---- trees: the meshes
	var trunks = []
	var leaves = []
	var tops = []
	for tree in props["trees"]:
		var at: Vector2 = tree["pos"]
		var tw = WorldDress.TRUNK_HALF * 2.0
		var cw = WorldDress.CANOPY_HALF * 2.0
		var uw = WorldDress.TOP_HALF * 2.0
		trunks.append(_top_key(at, WorldDress.TRUNK_H, tw, tw))
		leaves.append(_top_key(at, WorldDress.CANOPY_Y1, cw, cw))
		tops.append(_top_key(at, WorldDress.TOP_Y1, uw, uw))
	var tree_count = props["trees"].size()
	if tree_count > 0:
		_part_matches(built, "tree_trunks", trunks, 5, tree_count, found)
		_part_matches(built, "tree_leaves", leaves, 6, tree_count, found)
		_part_matches(built, "tree_tops", tops, 5, tree_count, found)
	elif built["parts"].has("tree_trunks"):
		found.append("tree check: tree parts drawn with no trees")
	# an arena with room for trees (many grass cells with only grass and sidewalk round them) must have some; the
	# bridge and the tunnel have no such cells and no trees
	var room = 0
	for cz in range(n):
		for cx in range(n):
			if str(layout["rows"][cz])[cx] != "g":
				continue
			var open_round = true
			for dz in range(-1, 2):
				for dx in range(-1, 2):
					var around = WorldGen.cell_at(layout["rows"], n, cx + dx, cz + dz)
					if around != "g" and around != "s":
						open_round = false
			if open_round:
				room += 1
	if lamp_count == 0 or (tree_count == 0 and room >= 60):
		found.append("an arena with %d lamps and %d trees is bare" % [lamp_count, tree_count])
	lamps_min = mini(lamps_min, lamp_count)
	lamps_max = maxi(lamps_max, lamp_count)
	trees_min = mini(trees_min, tree_count)
	trees_max = maxi(trees_max, tree_count)


# ---------------------------------------------------------------- damage
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


# the mesh without its last `quads` squares
func _drop_last(mesh: Mesh, quads: int) -> ArrayMesh:
	var data = _read(mesh)
	var verts: PackedVector3Array = data["v"]
	var norms: PackedVector3Array = data["n"]
	var idx: PackedInt32Array = data["i"]
	verts.resize(verts.size() - 4 * quads)
	norms.resize(norms.size() - 4 * quads)
	idx.resize(idx.size() - 6 * quads)
	return _remade(verts, norms, idx)


# the damaged result must be reported, and one of the problems must contain `needle`
func _expect_caught(label: String, needle: String, layout: Dictionary, built: Dictionary) -> void:
	var said = _check_built(layout, built)
	if said.is_empty():
		problems.append("the checks did not notice: %s" % label)
	elif not " | ".join(said).contains(needle):
		problems.append('the checks noticed "%s" but not by "%s": %s' % [label, needle, said[0]])
	built["root"].free()


func _check_damage(layout: Dictionary) -> void:
	# mirrored: built from the layout turned east to west, judged against the real one
	var mirrored = layout.duplicate(true)
	var rows = []
	for row in layout["rows"]:
		var flipped = ""
		for i in range(str(row).length() - 1, -1, -1):
			flipped += str(row)[i]
		rows.append(flipped)
	mirrored["rows"] = rows
	_expect_caught(
		"an arena mirrored east to west", "covered by", layout, WorldDress.build(mirrored)
	)
	# a hole in the walls: the last building box of the brick walls dropped
	var hole = WorldDress.build(layout)
	var brick: MeshInstance3D = hole["parts"]["walls_brick"]
	brick.mesh = _drop_last(brick.mesh, 5)
	_expect_caught("a building missing", "covered by", layout, hole)
	# walls wound the wrong way round
	var inside_out = WorldDress.build(layout)
	var walls: MeshInstance3D = (
		inside_out["parts"]["walls_dark"]
		if inside_out["parts"].has("walls_dark")
		else inside_out["parts"]["walls_brick"]
	)
	walls.mesh = _flip(walls.mesh)
	_expect_caught("walls wound the wrong way round", "wound the wrong way", layout, inside_out)
	# windows left out, and a window left off
	var bare = WorldDress.build(layout)
	bare["parts"]["windows"].free()
	bare["parts"].erase("windows")
	_expect_caught("no windows", "0 windows drawn", layout, bare)
	var one_short = WorldDress.build(layout)
	var glass: MeshInstance3D = one_short["parts"]["windows"]
	glass.mesh = _drop_last(glass.mesh, 1)
	_expect_caught("one window missing", "windows drawn", layout, one_short)
	# the tunnel blocks and their bands
	var no_tunnel = WorldDress.build(layout)
	no_tunnel["parts"]["tunnels"].free()
	no_tunnel["parts"].erase("tunnels")
	_expect_caught("no tunnel blocks", "tunnel cell check", layout, no_tunnel)
	var no_band = WorldDress.build(layout)
	var bands: MeshInstance3D = no_band["parts"]["tunnel_bands"]
	bands.mesh = _drop_last(bands.mesh, 1)
	_expect_caught("a tunnel band missing", "tunnel bands", layout, no_band)
	# a style that says "no windows" or "all dark" is held to it: the same dressing checked against such a style
	var blank_dress: Dictionary = layout.get("dress", {}).duplicate(true)
	blank_dress["windows"] = false
	var blank: Dictionary = layout.duplicate(true)
	blank["dress"] = blank_dress
	_expect_caught(
		"windows on a style that has none", "the layout asks for 0", blank, WorldDress.build(layout)
	)
	var dark_dress: Dictionary = layout.get("dress", {}).duplicate(true)
	dark_dress["dark_all"] = true
	var all_dark: Dictionary = layout.duplicate(true)
	all_dark["dress"] = dark_dress
	_expect_caught(
		"brick walls on an all-dark style",
		"dresses every building dark",
		all_dark,
		WorldDress.build(layout)
	)
	# windows lit all the time
	var lit = WorldDress.build(layout)
	lit["win_mat"].emission_energy_multiplier = 2.0
	_expect_caught("windows lit by day", "lit before the theme", layout, lit)
	# lamps: one missing, a light left on, heads lit by day, a lamp in the wrong cell
	var no_lamp = WorldDress.build(layout)
	var lamp_posts: MeshInstance3D = no_lamp["parts"]["lamp_posts"]
	lamp_posts.mesh = _drop_last(lamp_posts.mesh, 11)
	_expect_caught("a lamp pole missing", "lamp_posts check", layout, no_lamp)
	var on = WorldDress.build(layout)
	on["lamps"][0].visible = true
	_expect_caught("a lamp light left on", "hidden until", layout, on)
	var glowing = WorldDress.build(layout)
	glowing["lamp_mat"].emission_energy_multiplier = 2.0
	_expect_caught("lamp heads lit by day", "lamp heads are lit", layout, glowing)
	var strayed = WorldDress.build(layout)
	strayed["props"]["lamps"][0]["cell"] = Vector2i(0, 0)
	_expect_caught("a lamp in a building cell", "not a lamp cell", layout, strayed)
	# trees: one missing, one standing on a road
	var no_tree = WorldDress.build(layout)
	var trunks: MeshInstance3D = no_tree["parts"]["tree_trunks"]
	trunks.mesh = _drop_last(trunks.mesh, 5)
	_expect_caught("a tree trunk missing", "tree_trunks check", layout, no_tree)
	var on_road = WorldDress.build(layout)
	for r in range(int(layout["cells"])):
		var col = str(layout["rows"][r]).find("r")
		if col >= 0:
			on_road["props"]["trees"][0]["cell"] = Vector2i(col, r)
			break
	_expect_caught("a tree on the road", "tree check", layout, on_road)
