extends RefCounted
# Builds the ground of a generated arena from its layout (README Milestone K, "Building the world": ground
# surfaces, curbs and markings). Props, buildings, lamps and lighting are the next items; this is only what
# you walk and ride on. Nothing here reads the scene or the random functions: one layout gives one set of
# meshes, so the same seed builds the same ground. The layout is described at the top of arena_gen.gd.
#
# What it makes, all in world metres (x east, z south, y up) with the ground surface at y = 0:
#   one flat mesh per ground type (grass, plaza, sidewalk, road, building lot, tunnel floor), neighbouring
#     cells of one type merged into rectangles, so a whole arena is a few hundred triangles
#   curbs: a raised strip (CURB_H high, CURB_W wide) on every cell edge where road meets sidewalk, plaza or
#     grass (not where it meets a building or a tunnel mouth)
#   paint: a white edge line just inside the road along every curb, and a dashed white centre line along
#     each road, stopping short of crossings and of the road's ends
#   a hazard-yellow frame round the clear start area
# Meshes are flat quads built straight from the layout with one shared material each (Util.mat), so the
# whole ground is about a dozen draw calls. The materials are the roundabout's, until Milestone F replaces
# them.

const Util = preload("res://scripts/util.gd")

const CURB_H = 0.12
const CURB_W = 0.22
const PAINT_W = 0.12
const PAINT_Y = 0.013  # paint just above the road, as on the roundabout
const EDGE_INSET = 0.3  # the edge line's middle is this far inside the road from the curb line
const DASH_LEN = 1.6
const DASH_GAP = 1.6
const DASH_MARGIN = 0.8  # no dash closer than this to a crossing or the end of a road
const START_W = 0.3
const START_Y = 0.014
const CURB_NEIGHBOURS = "spg"  # what a road edge needs on the other side to get a curb and an edge line

# ground type -> [colour, roughness]; the first three colours are the ones world.gd uses for the same things
const SURFACE_STYLE = {
	"g": [Color(0.3, 0.46, 0.27), 1.0],
	"p": [Color(0.62, 0.6, 0.55), 0.95],
	"s": [Color(0.56, 0.55, 0.51), 0.95],
	"r": [Color(0.17, 0.17, 0.19), 0.95],
	"b": [Color(0.3, 0.3, 0.33), 0.95],
	"t": [Color(0.04, 0.04, 0.05), 1.0],
}
const SURFACE_NAMES = {
	"g": "grass", "p": "plaza", "s": "sidewalk", "r": "road", "b": "building", "t": "tunnel"
}
const CURB_COLOR = Color(0.74, 0.73, 0.69)
const PAINT_COLOR = Color(0.93, 0.93, 0.9)
const HAZARD_COLOR = Color(0.95, 0.75, 0.15)


# Builds the ground for a layout. Returns {"root": Node3D (not in the tree: the caller adds it),
# "parts": {name: MeshInstance3D} (ground_<surface> for each ground type that occurs, plus "curbs", "paint"
# and "start_frame"), "tris": triangles in all of them, "draw_calls": mesh instances} or {} for an empty layout.
static func build_ground(layout: Dictionary) -> Dictionary:
	if layout.is_empty():
		return {}
	var n = int(layout["cells"])
	var cell = float(layout["cell"])
	var rows: Array = layout["rows"]
	var root = Node3D.new()
	root.name = "ArenaGround"
	var parts = {}
	var tris = 0
	var calls = 0
	# a big dark plane under everything, so no gap ever shows the sky (same as the roundabout's)
	Util.box(
		root,
		Vector3(300.0, 0.1, 300.0),
		Vector3(0.0, -0.12, 0.0),
		Util.mat(SURFACE_STYLE["g"][0], 1.0)
	)
	tris += 12
	calls += 1
	for ch in ["g", "p", "s", "r", "b", "t"]:
		var rects = []
		for r in _merge_cells(rows, n, ch):
			rects.append(
				[
					_edge(n, cell, r[0]),
					_edge(n, cell, r[1]),
					_edge(n, cell, r[2]),
					_edge(n, cell, r[3])
				]
			)
		if rects.is_empty():
			continue
		var style = SURFACE_STYLE[ch]
		var mat = Util.unshaded(style[0]) if ch == "t" else Util.mat(style[0], style[1])
		var mi = _part(root, "ground_" + SURFACE_NAMES[ch], _flat_mesh(rects, 0.0), mat)
		parts["ground_" + SURFACE_NAMES[ch]] = mi
		tris += rects.size() * 2
		calls += 1
	var edges = _road_edges(rows, n, cell)
	var curbs = []
	var edge_lines = []
	for e in edges:
		var half_curb = CURB_W * 0.5
		var half_line = PAINT_W * 0.5
		if e["axis"] == "h":
			curbs.append([e["a0"], e["pos"] - half_curb, e["a1"], e["pos"] + half_curb])
			var zc = float(e["pos"]) + float(e["side"]) * EDGE_INSET
			edge_lines.append([e["a0"], zc - half_line, e["a1"], zc + half_line])
		else:
			curbs.append([e["pos"] - half_curb, e["a0"], e["pos"] + half_curb, e["a1"]])
			var xc = float(e["pos"]) + float(e["side"]) * EDGE_INSET
			edge_lines.append([xc - half_line, e["a0"], xc + half_line, e["a1"]])
	if not curbs.is_empty():
		parts["curbs"] = _part(
			root, "curbs", _box_mesh(curbs, 0.0, CURB_H), Util.mat(CURB_COLOR, 0.9)
		)
		tris += curbs.size() * 10
		calls += 1
	var paint = edge_lines
	for rd in layout["roads"]:
		paint = paint + _dashes(rows, n, cell, rd)
	if not paint.is_empty():
		parts["paint"] = _part(
			root, "paint", _flat_mesh(paint, PAINT_Y), Util.mat(PAINT_COLOR, 0.8)
		)
		tris += paint.size() * 2
		calls += 1
	var frame = _start_frame(layout)
	parts["start_frame"] = _part(
		root, "start_frame", _flat_mesh(frame, START_Y), Util.mat(HAZARD_COLOR, 0.7)
	)
	tris += frame.size() * 2
	calls += 1
	return {"root": root, "parts": parts, "tris": tris, "draw_calls": calls}


# ---------------------------------------------------------------- layout to rectangles
# world metres of grid line i (0 is the west / north edge of the arena)
static func _edge(n: int, cell: float, i: int) -> float:
	return (float(i) - float(n) / 2.0) * cell


# The cells of one ground type as few rectangles as it is easy to get: each row's runs, and a run with the
# same span as the one above it grows that rectangle down. Returns [[cx0, cz0, cx1, cz1]] in cells, the end
# exclusive.
static func _merge_cells(rows: Array, n: int, ch: String) -> Array:
	var done = []
	var open = {}
	for cz in range(n):
		var row = str(rows[cz])
		var runs = []
		var cx = 0
		while cx < n:
			if row[cx] == ch:
				var start = cx
				while cx < n and row[cx] == ch:
					cx += 1
				runs.append([start, cx])
			else:
				cx += 1
		var next_open = {}
		for run in runs:
			var key = "%d:%d" % [run[0], run[1]]
			if open.has(key):
				var grown = open[key]
				grown[3] = cz + 1
				next_open[key] = grown
			else:
				var fresh = [run[0], cz, run[1], cz + 1]
				next_open[key] = fresh
				done.append(fresh)
		open = next_open
	return done


static func _at(rows: Array, n: int, cx: int, cz: int) -> String:
	if cx < 0 or cz < 0 or cx >= n or cz >= n:
		return "b"
	return str(rows[cz])[cx]


# Every stretch of cell edge with road on one side and a CURB_NEIGHBOURS cell on the other, joined along the
# edge: [{"axis": "h" (runs east-west) or "v" (runs north-south), "pos": the edge's z (h) or x (v) in metres,
# "a0", "a1": its ends along the edge in metres, "side": +1 if the road is on the higher-coordinate side,
# else -1}].
static func _road_edges(rows: Array, n: int, cell: float) -> Array:
	var out = []
	for axis in ["h", "v"]:
		for line in range(1, n):
			var run_start = -1
			var run_side = 0
			for along in range(n + 1):
				var side = 0
				if along < n:
					var before = (
						_at(rows, n, along, line - 1)
						if axis == "h"
						else _at(rows, n, line - 1, along)
					)
					var after = (
						_at(rows, n, along, line) if axis == "h" else _at(rows, n, line, along)
					)
					if before == "r" and CURB_NEIGHBOURS.contains(after):
						side = -1
					elif after == "r" and CURB_NEIGHBOURS.contains(before):
						side = 1
				if run_start >= 0 and side != run_side:
					out.append(
						{
							"axis": axis,
							"pos": _edge(n, cell, line),
							"a0": _edge(n, cell, run_start),
							"a1": _edge(n, cell, along),
							"side": run_side
						}
					)
					run_start = -1
				if side != 0 and run_start < 0:
					run_start = along
					run_side = side
	return out


# The dashed centre line of one road ({"dir", "centre"} from the layout): dashes along the middle of the
# road through every stretch that is plain road (no crossing road: the cells two out from the middle are
# not road), centred in the stretch, DASH_MARGIN short of each end. Returns [[x0, z0, x1, z1]].
static func _dashes(rows: Array, n: int, cell: float, rd: Dictionary) -> Array:
	var out = []
	var c = int(rd["centre"])
	var ns = str(rd["dir"]) == "ns"
	var mid = _edge(n, cell, c) + cell * 0.5  # the middle of the road across it, in metres
	var start = -1
	for a in range(n + 1):
		var plain = false
		if a < n:
			var x = c if ns else a
			var z = a if ns else c
			var dx = 2 if ns else 0
			var dz = 0 if ns else 2
			plain = (
				_at(rows, n, x, z) == "r"
				and _at(rows, n, x - dx, z - dz) != "r"
				and _at(rows, n, x + dx, z + dz) != "r"
			)
		if plain and start < 0:
			start = a
		elif not plain and start >= 0:
			var lo = _edge(n, cell, start) + DASH_MARGIN
			var hi = _edge(n, cell, a) - DASH_MARGIN
			var count = int(floor((hi - lo + DASH_GAP) / (DASH_LEN + DASH_GAP)))
			if count > 0:
				var total = float(count) * DASH_LEN + float(count - 1) * DASH_GAP
				var at = (lo + hi) * 0.5 - total * 0.5
				for _k in range(count):
					if ns:
						out.append([mid - PAINT_W * 0.5, at, mid + PAINT_W * 0.5, at + DASH_LEN])
					else:
						out.append([at, mid - PAINT_W * 0.5, at + DASH_LEN, mid + PAINT_W * 0.5])
					at += DASH_LEN + DASH_GAP
			start = -1
	return out


# the four strips of the frame round the clear start square, just inside its edge
static func _start_frame(layout: Dictionary) -> Array:
	var cell = float(layout["cell"])
	var r = (float(layout["start"]["half"]) + 0.5) * cell
	var cx = float(layout["start"]["pos"][0])
	var cz = float(layout["start"]["pos"][1])
	var w = START_W
	return [
		[cx - r, cz - r, cx + r, cz - r + w],
		[cx - r, cz + r - w, cx + r, cz + r],
		[cx - r, cz - r + w, cx - r + w, cz + r - w],
		[cx + r - w, cz - r + w, cx + r, cz + r - w],
	]


# ---------------------------------------------------------------- meshes
static func _part(
	root: Node3D, part_name: String, mesh: ArrayMesh, mat: Material
) -> MeshInstance3D:
	var mi = MeshInstance3D.new()
	mi.name = part_name
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	return mi


# flat rectangles ([x0, z0, x1, z1] in metres) at height y, facing up: four vertices each, in that order
static func _flat_mesh(rects: Array, y: float) -> ArrayMesh:
	var verts = PackedVector3Array()
	var norms = PackedVector3Array()
	var idx = PackedInt32Array()
	for r in rects:
		_top(verts, norms, idx, r, y)
	return _finish(verts, norms, idx)


# boxes ([x0, z0, x1, z1] in metres) from y0 to y1: the top and the four sides, twenty vertices each
static func _box_mesh(rects: Array, y0: float, y1: float) -> ArrayMesh:
	var verts = PackedVector3Array()
	var norms = PackedVector3Array()
	var idx = PackedInt32Array()
	for r in rects:
		_top(verts, norms, idx, r, y1)
		var a = Vector3(r[0], y0, r[1])
		var b = Vector3(r[2], y0, r[1])
		var c = Vector3(r[2], y0, r[3])
		var d = Vector3(r[0], y0, r[3])
		var up = Vector3(0.0, y1 - y0, 0.0)
		_face(verts, norms, idx, [a, b, b + up, a + up], Vector3(0.0, 0.0, -1.0))
		_face(verts, norms, idx, [b, c, c + up, b + up], Vector3(1.0, 0.0, 0.0))
		_face(verts, norms, idx, [c, d, d + up, c + up], Vector3(0.0, 0.0, 1.0))
		_face(verts, norms, idx, [d, a, a + up, d + up], Vector3(-1.0, 0.0, 0.0))
	return _finish(verts, norms, idx)


static func _top(
	verts: PackedVector3Array, norms: PackedVector3Array, idx: PackedInt32Array, r: Array, y: float
) -> void:
	_face(
		verts,
		norms,
		idx,
		[
			Vector3(r[0], y, r[1]),
			Vector3(r[2], y, r[1]),
			Vector3(r[2], y, r[3]),
			Vector3(r[0], y, r[3])
		],
		Vector3.UP
	)


# one square face with the outward normal n: its corners are put in the order Godot draws as front-facing
# (clockwise seen from outside), whichever way round they were given
static func _face(
	verts: PackedVector3Array,
	norms: PackedVector3Array,
	idx: PackedInt32Array,
	corners: Array,
	n: Vector3
) -> void:
	var c = corners
	if (c[1] - c[0]).cross(c[2] - c[1]).dot(n) > 0.0:
		c = [corners[3], corners[2], corners[1], corners[0]]
	var base = len(verts)
	for v in c:
		verts.append(v)
		norms.append(n)
	idx.append_array(PackedInt32Array([base, base + 1, base + 2, base, base + 2, base + 3]))


static func _finish(
	verts: PackedVector3Array, norms: PackedVector3Array, idx: PackedInt32Array
) -> ArrayMesh:
	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
