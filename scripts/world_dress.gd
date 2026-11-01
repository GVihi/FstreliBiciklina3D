extends RefCounted
# Dresses the ground of a generated arena (README Milestone K, "Building the world": buildings, props, lamps
# and gates). world_gen.gd lays the ground; this stands things on it. Like the ground it reads nothing but the
# layout (no scene, no random functions): every height and every prop position comes from the cells, so one
# layout gives one arena. The recipe is the roundabout's (world.gd) made from boxes: brick and dark facades
# with rows of windows on one shared glow material, black tunnel blocks where riders appear and vanish, and
# lamps with a (hidden by default) warm light each, and trees. The F9 kit proper is not built yet, so these are
# the roundabout's chunky stand-ins, in the roundabout's colours (boxes only, so every part is quads).
#
# What it makes, all in world metres (x east, z south, y up), standing on the ground at y = 0:
#   buildings   every 'b' cell is under exactly one lot, a box at most LOT_CELLS cells long on each side,
#               H_MIN to H_MIN + 4 * H_STEP high by a hash of the lot's cells (a layout's "dress" can change the
#               base, the number of steps and the step: the arena style, see arena_gen.gd); brick or dark by the same hash
#               (all dark when the "dress" says "dark_all"); windows (WIN_W by WIN_H) on every cell face that looks
#               onto open ground, in rows from WIN_ROW0 up every WIN_ROW_STEP while they fit WIN_TOP_GAP under the
#               roof (none when the "dress" says "windows": false)
#   tunnels     every 't' cell is under one black block TUNNEL_H high, with a hazard-yellow band round the top
#               of each face that looks onto open ground
#   lamps       on a sidewalk cell that touches a road (never a corner, never near a tunnel), every LAMP_EVERY
#               cells along the road, one side offset half a spacing from the other: a pole LAMP_SETBACK from the
#               cell centre towards the road, an arm over the kerb, a glowing head, and a hidden OmniLight3D
#   trees       on a grass cell whose eight neighbours are all grass or sidewalk (so none stands against a
#               building, a road, a plaza or a tunnel), one cell in TREE_EVERY (or the layout's "dress" tree_every) by
#               a hash of the cell: a trunk and two blocks of leaves, centred in the cell
#   Props are decoration and the layout does not know about them. The trunks are solid all the same: the generated
#   arena (arena_generated.gd) reads props_of() and keeps everyone on foot and every rider TRUNK_SOLID metres
#   (plus its own margin) off a trunk; the leaves are above head height and do not stop anyone on foot, but darts and thrown phones are stopped by trunk and leaves alike (Arena.tree_hit). The lamp poles
#   are solid the same way: LAMP_SOLID (plus the body's margin) off a pole for everyone on foot and every rider, and
#   darts and phones are stopped by the pole, the arm and the head alike (lamp_boxes, the boxes the world draws).
#   The arm and the head hang over the road above head height, so they stop nobody on foot.
# Meshes are merged per material, so the whole dressing is a handful of draw calls.
# build(layout, skip_lots): the indices (into lots_of) of lots that get no box and no windows because world_models.gd
# stands a model on them. "buildings" in the result still lists every lot.

const Util = preload("res://scripts/util.gd")
const WorldGen = preload("res://scripts/world_gen.gd")

const LOT_CELLS = 3
const H_MIN = 6.5
const H_STEP = 1.2
const H_STEPS = 5
const TUNNEL_H = 6.5
const HAZARD_H = 0.5
const WIN_W = 1.2
const WIN_H = 1.3
const WIN_OFF = 0.03  # a window quad stands this far off the wall
const WIN_ROW0 = 2.6
const WIN_ROW_STEP = 2.4
const WIN_TOP_GAP = 0.6
const HAZARD_OFF = 0.02

const BRICK_COLOR = Color(0.52, 0.34, 0.28)
const DARK_WALL_COLOR = Color(0.3, 0.3, 0.33)
const WINDOW_COLOR = Color(0.25, 0.32, 0.4)  # the glass; at dusk and night it glows WINDOW_LIGHT
const WINDOW_LIGHT = Color(1.0, 0.74, 0.38)  # warm orange so lit windows never burn out to white (as world.gd)

const LAMP_EVERY = 8  # cells between lamps along a road side (16 m)
const LAMP_SETBACK = 0.7  # pole centre from the cell centre, towards the road
const LAMP_POLE_H = 5.2
const LAMP_POLE_HALF = 0.06
const LAMP_ARM_REACH = 1.2  # pole centre to the head's centre
const LAMP_ARM_Y0 = 5.1
const LAMP_ARM_Y1 = 5.2
const LAMP_ARM_HALF = 0.05
const LAMP_HEAD_ALONG = 0.45  # the head's size along the road
const LAMP_HEAD_ACROSS = 0.28
const LAMP_HEAD_Y0 = 5.07
const LAMP_HEAD_Y1 = 5.17
const LAMP_LIGHT_Y = 4.9
const LAMP_RANGE = 16.0  # the same warm pool as world.gd's lamps
const LAMP_ENERGY = 3.2
const LAMP_SOLID = 0.15  # metres from the pole's middle that nobody can stand in (the pole's corner is 0.085 away)
const LAMP_LIGHT_COLOR = Color(1.0, 0.8, 0.5)
const LAMP_GLOW = Color(1.0, 0.9, 0.65)
const METAL_COLOR = Color(0.25, 0.27, 0.3)

const TREE_EVERY = 14
const TRUNK_HALF = 0.15
const TRUNK_SOLID = 0.25  # metres from the trunk's middle that nobody can stand in (the trunk's corner is 0.21 away)
const TRUNK_H = 2.4
const CANOPY_HALF = 1.05
const CANOPY_Y0 = 2.2
const CANOPY_Y1 = 3.8
const TOP_HALF = 0.7
const TOP_Y1 = 4.8
const TRUNK_COLOR = Color(0.3, 0.2, 0.12)
const LEAF_COLOR = Color(0.18, 0.38, 0.2)
const LEAF_TOP_COLOR = Color(0.24, 0.46, 0.24)

const SIDES = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]  # north, east, south, west


# Builds the dressing for a layout. Returns {"root": Node3D (not in the tree: the caller adds it),
# "parts": {name: MeshInstance3D}, "buildings": [{"cells": [cx0, cz0, cx1, cz1] (end exclusive), "h": height,
# "dark": bool}], "props": props_of(layout), "win_mat": the windows' material and "lamp_mat": the lamp heads'
# (the theme sets their emission_energy_multiplier), "lamps": [OmniLight3D] (hidden, one per lamp, children of
# root), "tris", "draw_calls"} or {} for an empty layout.
static func build(layout: Dictionary, skip_lots: Array = []) -> Dictionary:
	if layout.is_empty():
		return {}
	var n = int(layout["cells"])
	var cell = float(layout["cell"])
	var rows: Array = layout["rows"]
	var root = Node3D.new()
	root.name = "ArenaDressing"
	var parts = {}
	var tris = 0
	var lots = lots_of(layout)
	var props = props_of(layout)
	var out = {"root": root, "parts": parts, "buildings": lots, "props": props}
	# ---- buildings: walls (brick and dark in a mesh each) and the windows
	var brick = _Mesh.new()
	var dark = _Mesh.new()
	var glass = _Mesh.new()
	var windows_on = windows_wanted(layout)
	for lot_index in range(lots.size()):
		if skip_lots.has(lot_index):  # drawn as a model instead (world_models.gd)
			continue
		var lot = lots[lot_index]
		var c = lot["cells"]
		var rect = _rect(n, cell, c)
		(dark if lot["dark"] else brick).box(rect, 0.0, float(lot["h"]), false)
		if not windows_on:
			continue
		for side in range(4):
			for cell_face in _faces_onto_open_ground(rows, n, c, side):
				_window_column(glass, n, cell, cell_face, side, float(lot["h"]))
	var wall_mat_brick = Util.mat(BRICK_COLOR, 0.95)
	var wall_mat_dark = Util.mat(DARK_WALL_COLOR, 0.95)
	var win_mat = Util.glow(WINDOW_LIGHT, 0.0)
	win_mat.albedo_color = WINDOW_COLOR
	out["win_mat"] = win_mat
	for entry in [["walls_brick", brick, wall_mat_brick], ["walls_dark", dark, wall_mat_dark]]:
		if entry[1].is_empty():
			continue
		parts[entry[0]] = WorldGen.add_part(root, entry[0], entry[1].mesh(), entry[2])
		parts[entry[0]].cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		tris += entry[1].tris()
	if not glass.is_empty():
		parts["windows"] = WorldGen.add_part(root, "windows", glass.mesh(), win_mat)
		tris += glass.tris()
	# ---- tunnels: black blocks, hazard band on the mouth
	var tunnel = _Mesh.new()
	var band = _Mesh.new()
	for r in WorldGen.merge_cells(rows, n, "t"):
		tunnel.box(_rect(n, cell, r), 0.0, TUNNEL_H, false)
		for side in range(4):
			for cell_face in _faces_onto_open_ground(rows, n, r, side):
				var a = _face_ends(n, cell, cell_face, side)
				band.quad(
					[
						Vector3(a[0].x, TUNNEL_H - HAZARD_H, a[0].y),
						Vector3(a[1].x, TUNNEL_H - HAZARD_H, a[1].y),
						Vector3(a[1].x, TUNNEL_H, a[1].y),
						Vector3(a[0].x, TUNNEL_H, a[0].y)
					],
					_outward(side),
					HAZARD_OFF
				)
	if not tunnel.is_empty():
		parts["tunnels"] = WorldGen.add_part(
			root, "tunnels", tunnel.mesh(), Util.unshaded(Color(0.0, 0.0, 0.0))
		)
		tris += tunnel.tris()
	if not band.is_empty():
		parts["tunnel_bands"] = WorldGen.add_part(
			root, "tunnel_bands", band.mesh(), Util.mat(WorldGen.HAZARD_COLOR, 0.7)
		)
		tris += band.tris()
	# ---- lamps: poles and arms in metal, heads that glow, a hidden light each
	var posts = _Mesh.new()
	var heads = _Mesh.new()
	var lamp_lights = []
	var lights = Node3D.new()
	lights.name = "LampLights"
	root.add_child(lights)
	for lamp in props["lamps"]:
		var head: Vector2 = lamp["head"]
		var boxes = lamp_boxes(lamp)  # the same boxes the arena makes solid
		posts.box(boxes[0][0], boxes[0][1], boxes[0][2], false)
		posts.box(boxes[1][0], boxes[1][1], boxes[1][2], true)
		heads.box(boxes[2][0], boxes[2][1], boxes[2][2], true)
		var light = OmniLight3D.new()
		light.position = Vector3(head.x, LAMP_LIGHT_Y, head.y)
		light.omni_range = LAMP_RANGE
		light.light_energy = LAMP_ENERGY
		light.light_color = LAMP_LIGHT_COLOR
		light.visible = false
		lights.add_child(light)
		lamp_lights.append(light)
	var lamp_mat = Util.glow(LAMP_GLOW, 0.0)
	out["lamp_mat"] = lamp_mat
	out["lamps"] = lamp_lights
	if not posts.is_empty():
		parts["lamp_posts"] = WorldGen.add_part(
			root, "lamp_posts", posts.mesh(), Util.mat(METAL_COLOR, 0.5, 0.6)
		)
		parts["lamp_heads"] = WorldGen.add_part(root, "lamp_heads", heads.mesh(), lamp_mat)
		tris += posts.tris() + heads.tris()
	# ---- trees: a trunk and two blocks of leaves
	var trunks = _Mesh.new()
	var leaves = _Mesh.new()
	var tops = _Mesh.new()
	for tree in props["trees"]:
		var at: Vector2 = tree["pos"]
		trunks.box(_around(at, TRUNK_HALF, TRUNK_HALF), 0.0, TRUNK_H, false)
		leaves.box(_around(at, CANOPY_HALF, CANOPY_HALF), CANOPY_Y0, CANOPY_Y1, true)
		tops.box(_around(at, TOP_HALF, TOP_HALF), CANOPY_Y1, TOP_Y1, false)
	for entry in [
		["tree_trunks", trunks, TRUNK_COLOR],
		["tree_leaves", leaves, LEAF_COLOR],
		["tree_tops", tops, LEAF_TOP_COLOR]
	]:
		if entry[1].is_empty():
			continue
		parts[entry[0]] = WorldGen.add_part(
			root, entry[0], entry[1].mesh(), Util.mat(entry[2], 1.0)
		)
		parts[entry[0]].cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		tris += entry[1].tris()
	for part_name in ["windows", "tunnels", "tunnel_bands", "lamp_posts", "lamp_heads"]:
		if parts.has(part_name):
			parts[part_name].cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	out["tris"] = tris
	out["draw_calls"] = parts.size()
	return out


# ---------------------------------------------------------------- lots
# The lots of a layout: every 'b' cell is in exactly one. Each merged rectangle of building cells is cut into
# whether the buildings of this layout get windows: yes unless the layout's "dress" says "windows": false (the
# bridge's girders and the tunnel's walls are blank)
static func windows_wanted(layout: Dictionary) -> bool:
	return bool(layout.get("dress", {}).get("windows", true))


# pieces of at most LOT_CELLS cells across, as even as it goes. [{"cells": [cx0, cz0, cx1, cz1], "h", "dark"}]
static func lots_of(layout: Dictionary) -> Array:
	var n = int(layout["cells"])
	var dress: Dictionary = layout.get("dress", {})
	var h_base = float(dress.get("h_base", H_MIN))
	var h_steps = maxi(1, int(dress.get("h_steps", H_STEPS)))
	var h_step = float(dress.get("h_step", H_STEP))
	var all_dark = bool(dress.get("dark_all", false))
	var out = []
	for r in WorldGen.merge_cells(layout["rows"], n, "b"):
		for xs in _cut(int(r[0]), int(r[2])):
			for zs in _cut(int(r[1]), int(r[3])):
				var key = _hash([xs[0], zs[0], xs[1], zs[1]])
				(
					out
					. append(
						{
							"cells": [xs[0], zs[0], xs[1], zs[1]],
							"h": h_base + float(key % h_steps) * h_step,
							"dark": all_dark or (key / 7) % 3 == 1,
						}
					)
				)
	return out


# ---------------------------------------------------------------- props
# The lamps and trees of a layout, from its cells alone: {"lamps": [{"cell": Vector2i, "dir": Vector2i (towards
# the road), "pole": Vector2, "head": Vector2 (world x, z)}], "trees": [{"cell": Vector2i, "pos": Vector2}]}.
static func props_of(layout: Dictionary) -> Dictionary:
	var n = int(layout["cells"])
	var cell = float(layout["cell"])
	var rows: Array = layout["rows"]
	var every = maxi(1, int(layout.get("dress", {}).get("tree_every", TREE_EVERY)))
	var lamps = []
	var trees = []
	for cz in range(n):
		for cx in range(n):
			var here = WorldGen.cell_at(rows, n, cx, cz)
			var centre = Vector2(
				WorldGen.grid_edge(n, cell, cx) + cell * 0.5,
				WorldGen.grid_edge(n, cell, cz) + cell * 0.5
			)
			if here == "s":
				var dir = lamp_side(rows, n, cx, cz)
				if dir != Vector2i.ZERO:
					var d = Vector2(float(dir.x), float(dir.y))
					lamps.append(
						{
							"cell": Vector2i(cx, cz),
							"dir": dir,
							"pole": centre + d * LAMP_SETBACK,
							"head": centre + d * (LAMP_SETBACK + LAMP_ARM_REACH)
						}
					)
			elif here == "g" and _tree_cell(rows, n, cx, cz, every):
				trees.append({"cell": Vector2i(cx, cz), "pos": centre})
	return {"lamps": lamps, "trees": trees}


# The three boxes a lamp (an entry of props_of()["lamps"]) is drawn from, each as [[x0, z0, x1, z1] (world metres),
# from y, to y]: the pole, the arm that reaches over the road and the head. build() draws exactly these, and the
# generated arena stops darts and phones with exactly these, so what is drawn is what is solid.
static func lamp_boxes(lamp: Dictionary) -> Array:
	var pole: Vector2 = lamp["pole"]
	var head: Vector2 = lamp["head"]
	var dir: Vector2i = lamp["dir"]
	var ns = dir.y != 0  # the road is north or south: the head is long in x
	return [
		[_around(pole, LAMP_POLE_HALF, LAMP_POLE_HALF), 0.0, LAMP_POLE_H],
		[_between(pole, head, LAMP_ARM_HALF), LAMP_ARM_Y0, LAMP_ARM_Y1],
		[
			_around(
				head,
				LAMP_HEAD_ALONG * 0.5 if ns else LAMP_HEAD_ACROSS * 0.5,
				LAMP_HEAD_ACROSS * 0.5 if ns else LAMP_HEAD_ALONG * 0.5
			),
			LAMP_HEAD_Y0,
			LAMP_HEAD_Y1
		]
	]


# The side (a unit step) a lamp on sidewalk cell (cx, cz) faces, towards its road, or (0, 0) when the cell has
# no lamp: it must touch exactly one road (so not a corner), have no tunnel within a cell, and sit on the
# lamp spacing, with the two sides of a road half a spacing apart.
static func lamp_side(rows: Array, n: int, cx: int, cz: int) -> Vector2i:
	var found = Vector2i.ZERO
	var touching = 0
	for step in SIDES:
		if WorldGen.cell_at(rows, n, cx + step.x, cz + step.y) == "r":
			found = step
			touching += 1
	if touching != 1:
		return Vector2i.ZERO
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			if WorldGen.cell_at(rows, n, cx + dx, cz + dz) == "t":
				return Vector2i.ZERO
	var along = cx if found.y != 0 else cz
	var phase = LAMP_EVERY / 2 if (found.x + found.y) > 0 else 0
	return found if (along + phase) % LAMP_EVERY == 0 else Vector2i.ZERO


# a tree stands on a grass cell with only grass and sidewalk round it, one in `every` by a hash of the cell
static func _tree_cell(rows: Array, n: int, cx: int, cz: int, every: int) -> bool:
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var around = WorldGen.cell_at(rows, n, cx + dx, cz + dz)
			if around != "g" and around != "s":
				return false
	return _hash([cx, cz, 4141]) % every == 0


# [from, to) cut into pieces of at most LOT_CELLS, the long ones first
static func _cut(lo: int, hi: int) -> Array:
	var length = hi - lo
	var pieces = int(ceil(float(length) / float(LOT_CELLS)))
	var base = length / pieces
	var extra = length % pieces
	var out = []
	var at = lo
	for i in range(pieces):
		var size = base + (1 if i < extra else 0)
		out.append([at, at + size])
		at += size
	return out


# a stable number from a few ints (no random functions: the same cells always give the same lot)
static func _hash(values: Array) -> int:
	var h = 2166136261
	for v in values:
		h = ((h ^ (int(v) + 0x9E3779B9)) * 16777619) & 0x7FFFFFFF
	return h


# ---------------------------------------------------------------- geometry
# a cell rectangle [cx0, cz0, cx1, cz1] in world metres [x0, z0, x1, z1]
static func _rect(n: int, cell: float, c: Array) -> Array:
	return [
		WorldGen.grid_edge(n, cell, int(c[0])),
		WorldGen.grid_edge(n, cell, int(c[1])),
		WorldGen.grid_edge(n, cell, int(c[2])),
		WorldGen.grid_edge(n, cell, int(c[3]))
	]


# the square [x0, z0, x1, z1] round a point, hx and hz each side of it
static func _around(at: Vector2, hx: float, hz: float) -> Array:
	return [at.x - hx, at.y - hz, at.x + hx, at.y + hz]


# the rectangle from one point to another (they share an x or a z), `half` wide each side of the line
static func _between(a: Vector2, b: Vector2, half: float) -> Array:
	return [
		minf(a.x, b.x) - (half if absf(a.x - b.x) < 0.001 else 0.0),
		minf(a.y, b.y) - (half if absf(a.y - b.y) < 0.001 else 0.0),
		maxf(a.x, b.x) + (half if absf(a.x - b.x) < 0.001 else 0.0),
		maxf(a.y, b.y) + (half if absf(a.y - b.y) < 0.001 else 0.0)
	]


# the outward unit vector of side 0 north, 1 east, 2 south, 3 west
static func _outward(side: int) -> Vector3:
	return Vector3(float(SIDES[side].x), 0.0, float(SIDES[side].y))


# The cell faces along one side of a cell rectangle that look onto open ground (a cell that is not a building
# or a tunnel; outside the grid counts as building). Returns [Vector2i(cx, cz)] of the cells of the rectangle
# that own those faces.
static func _faces_onto_open_ground(rows: Array, n: int, c: Array, side: int) -> Array:
	var out = []
	var step: Vector2i = SIDES[side]
	var ns = side == 0 or side == 2
	var lo = int(c[0]) if ns else int(c[1])
	var hi = int(c[2]) if ns else int(c[3])
	for i in range(lo, hi):
		var cx = i if ns else (int(c[2]) - 1 if side == 1 else int(c[0]))
		var cz = (int(c[3]) - 1 if side == 2 else int(c[1])) if ns else i
		var beyond = WorldGen.cell_at(rows, n, cx + step.x, cz + step.y)
		if beyond != "b" and beyond != "t":
			out.append(Vector2i(cx, cz))
	return out


# the two ends of one cell face, as world (x, z), in the order that runs left to right seen from outside
static func _face_ends(n: int, cell: float, cell_xz: Vector2i, side: int) -> Array:
	var x0 = WorldGen.grid_edge(n, cell, cell_xz.x)
	var z0 = WorldGen.grid_edge(n, cell, cell_xz.y)
	var x1 = x0 + cell
	var z1 = z0 + cell
	match side:
		0:
			return [Vector2(x0, z0), Vector2(x1, z0)]
		1:
			return [Vector2(x1, z0), Vector2(x1, z1)]
		2:
			return [Vector2(x1, z1), Vector2(x0, z1)]
	return [Vector2(x0, z1), Vector2(x0, z0)]


# the windows of one cell face, centred on it, one per row that fits under a roof of height h
static func _window_column(
	glass, n: int, cell: float, cell_xz: Vector2i, side: int, h: float
) -> void:
	var ends = _face_ends(n, cell, cell_xz, side)
	var mid = (ends[0] + ends[1]) * 0.5
	var along = (ends[1] - ends[0]).normalized()
	var y = WIN_ROW0
	while y + WIN_H * 0.5 <= h - WIN_TOP_GAP:
		var a = mid - along * WIN_W * 0.5
		var b = mid + along * WIN_W * 0.5
		glass.quad(
			[
				Vector3(a.x, y - WIN_H * 0.5, a.y),
				Vector3(b.x, y - WIN_H * 0.5, b.y),
				Vector3(b.x, y + WIN_H * 0.5, b.y),
				Vector3(a.x, y + WIN_H * 0.5, a.y)
			],
			_outward(side),
			WIN_OFF
		)
		y += WIN_ROW_STEP


# ---------------------------------------------------------------- mesh accumulation
# Quads and boxes collected into one mesh. Faces are put in the order Godot draws as front-facing
# (WorldGen.add_face does that), so nothing is culled away.
class _Mesh:
	extends RefCounted
	var verts = PackedVector3Array()
	var norms = PackedVector3Array()
	var idx = PackedInt32Array()

	func is_empty() -> bool:
		return idx.is_empty()

	func tris() -> int:
		return idx.size() / 3

	func mesh() -> ArrayMesh:
		return WorldGen.finish_mesh(verts, norms, idx)

	# one quad with outward normal n, pushed `off` metres out along it
	func quad(corners: Array, n: Vector3, off: float = 0.0) -> void:
		var moved = []
		for v in corners:
			moved.append(v + n * off)
		WorldGen.add_face(verts, norms, idx, moved, n)

	# a box over the rectangle [x0, z0, x1, z1] from y0 to y1: the top and the four sides, and the bottom when
	# `bottom` is set
	func box(r: Array, y0: float, y1: float, bottom: bool) -> void:
		var a = Vector3(r[0], y0, r[1])
		var b = Vector3(r[2], y0, r[1])
		var c = Vector3(r[2], y0, r[3])
		var d = Vector3(r[0], y0, r[3])
		var up = Vector3(0.0, y1 - y0, 0.0)
		quad([a + up, b + up, c + up, d + up], Vector3.UP)
		quad([a, b, b + up, a + up], Vector3(0.0, 0.0, -1.0))
		quad([b, c, c + up, b + up], Vector3(1.0, 0.0, 0.0))
		quad([c, d, d + up, c + up], Vector3(0.0, 0.0, 1.0))
		quad([d, a, a + up, d + up], Vector3(-1.0, 0.0, 0.0))
		if bottom:
			quad([a, b, c, d], Vector3.DOWN)
