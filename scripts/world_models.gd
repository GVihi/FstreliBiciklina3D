extends RefCounted
# Real models in the generated arena (README Milestone F9, "World": buildings and props). world_dress.gd stands
# boxes on the ground; this script swaps some of them for the modelled assets and adds benches and crates, so the
# arena looks less like a toy. Like world_dress.gd it reads nothing but the layout (no scene, no random functions),
# so one layout gives one arena.
#
#   buildings   some lots (at least 2 x 2 cells, with a side that looks onto open ground) get the modelled
#               building (assets/models/low_poly_building) instead of a box with windows. The model is stretched
#               to the lot, its detailed face turned to the open side, and the lot's height sets how tall it is
#               (BUILDING_Y_MIN to BUILDING_Y_MAX times the model). The box and its windows are left out of
#               world_dress.gd's meshes (WorldDress.build(layout, skip)), so nothing is drawn twice. The cells
#               stay buildings for the arena, so riders and the player are stopped as before.
#   benches     on sidewalk cells that touch exactly one road (never a corner, never near a tunnel, never on a
#               lamp cell), turned to face the road, at most BENCH_MAX and never closer than BENCH_SPACING cells.
#   crates      test_crate against a building wall, on a sidewalk, plaza or grass cell (a road may only be on the far side
#               of the cell from the wall, and no bench within CRATE_BENCH_GAP cells), some of them
#               with a second crate on top or beside, at most CRATE_MAX places and never closer than CRATE_SPACING.
#   Nothing is placed near the start or a gate (KEEP_CLEAR metres).
# Props are decoration: no collision, same as the lamps and trees. Every model is drawn with one MultiMesh per
# mesh in the model, so the cost is a handful of draw calls however many there are. A model that is not there
# (not imported, or removed) is left out and the box building stays. "model_tris" and "model_draw_calls" in the
# result are what the models cost; "tris" and "draw_calls" of the world stay what the ground and boxes cost.

const WorldGen = preload("res://scripts/world_gen.gd")
const WorldDress = preload("res://scripts/world_dress.gd")

const BUILDING_PATH = "res://assets/models/low_poly_building/scene.gltf"
const BENCH_PATH = "res://assets/models/classic_park_bench_low_poly/scene.gltf"
const CRATE_PATH = "res://assets/models/test_crate.glb"

const BUILDING_PERCENT = 40  # of the lots that can take the model, by a hash of the lot's cells
const BUILDING_MIN_CELLS = 2
const BUILDING_FILL = 0.98  # share of the lot the model covers, so two lots side by side do not touch
const BUILDING_MAX_STRETCH = 1.45  # the most one side may be stretched compared to the other
const BUILDING_Y_MIN = 0.9
const BUILDING_Y_MAX = 1.4
const BUILDING_TINT = Color(0.66, 0.70, 0.80)  # multiplies the model's palette texture: less orange, closer to the boxes' brick

const BENCH_MAX = 10
const BENCH_SPACING = 6  # cells
const BENCH_SETBACK = 0.15  # metres from the cell centre towards the road

const CRATE_MAX = 14
const CRATE_SPACING = 5  # cells
const CRATE_BENCH_GAP = 2  # cells: no crate in a cell closer than this to a bench
const CRATE_SCALE_MIN = 1.0
const CRATE_SCALE_MAX = 1.3
const CRATE_WALL_GAP = 0.06  # metres between a crate and the wall behind it
const KEEP_CLEAR = 8.0  # metres round the start and every gate

const SIDES = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]  # north, east, south, west


# What to place, from the layout alone: {"buildings": [{"lot": index into WorldDress.lots_of, "pos": Vector3,
# "yaw", "size": Vector2 (metres along the face and into the lot), "y": height factor}], "benches": [{"pos",
# "yaw"}], "crates": [{"pos", "yaw", "scale"}]}. The model files are not needed for this, only for build().
static func plan(layout: Dictionary) -> Dictionary:
	var out = {"buildings": [], "benches": [], "crates": []}
	if layout.is_empty():
		return out
	if WorldDress.windows_wanted(layout):  # the bridge's girders and the tunnel's walls stay blank boxes
		out["buildings"] = _plan_buildings(layout)
	out["benches"] = _plan_benches(layout)
	out["crates"] = _plan_crates(layout, out["benches"])
	return out


# The lots (indices into WorldDress.lots_of(layout)) that the plan turns into models: pass them to
# WorldDress.build as the lots to leave out.
static func skipped_lots(planned: Dictionary) -> Array:
	var out = []
	for b in planned["buildings"]:
		out.append(int(b["lot"]))
	return out


# Adds the planned models to `root` and returns {"parts": [MultiMeshInstance3D], "tris", "draw_calls",
# "buildings", "benches", "crates"} (the last three are how many were really placed; a missing model gives 0).
static func build(root: Node3D, planned: Dictionary) -> Dictionary:
	var holder = Node3D.new()
	holder.name = "ArenaModels"
	root.add_child(holder)
	var out = {"parts": [], "tris": 0, "draw_calls": 0, "buildings": 0, "benches": 0, "crates": 0}
	var jobs = [
		["building", BUILDING_PATH, _building_transforms(planned), "buildings", BUILDING_TINT],
		["bench", BENCH_PATH, _bench_transforms(planned), "benches", Color.WHITE],
		["crate", CRATE_PATH, _crate_transforms(planned), "crates", Color.WHITE]
	]
	for job in jobs:
		var transforms: Array = job[2]
		if transforms.is_empty():
			continue
		var model = load_model(job[1])
		if model.is_empty():
			push_warning("world_models: %s could not be loaded, it is left out" % job[1])
			continue
		var made = _place(holder, job[0], model, transforms, job[4])
		out["parts"].append_array(made["parts"])
		out["tris"] += int(made["tris"])
		out["draw_calls"] += made["parts"].size()
		out[job[3]] = transforms.size()
	if out["parts"].is_empty():
		holder.queue_free()
	return out


# ---------------------------------------------------------------- models
# A model read from its scene: {"meshes": [{"mesh": Mesh, "xform": Transform3D (mesh to model root)}], "aabb":
# AABB (of all of them, in the model root's space)}, or {} when the file is missing or has no mesh.
static func load_model(path: String) -> Dictionary:
	if not ResourceLoader.exists(path):
		return {}
	var scene = load(path)
	if not (scene is PackedScene):
		return {}
	var inst: Node = scene.instantiate()
	var meshes = []
	_collect(inst, Transform3D.IDENTITY, meshes)
	inst.free()
	if meshes.is_empty():
		return {}
	var box: AABB = meshes[0]["xform"] * (meshes[0]["mesh"] as Mesh).get_aabb()
	for m in meshes:
		box = box.merge(m["xform"] * (m["mesh"] as Mesh).get_aabb())
	return {"meshes": meshes, "aabb": box}


static func _collect(node: Node, parent_xform: Transform3D, into: Array) -> void:
	var here = parent_xform
	if node is Node3D:
		here = parent_xform * (node as Node3D).transform
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		into.append({"mesh": (node as MeshInstance3D).mesh, "xform": here})
	for child in node.get_children():
		_collect(child, here, into)


# The transform that stands a model on the ground at the origin, centred over x and z, with its lowest point at y 0.
static func _grounded(model: Dictionary) -> Transform3D:
	var box: AABB = model["aabb"]
	var c = box.position + box.size * 0.5
	return Transform3D(Basis.IDENTITY, Vector3(-c.x, -box.position.y, -c.z))


# One MultiMeshInstance3D for each mesh of the model, every placement in `transforms` (a Transform3D that puts a
# grounded, unit-sized model where it goes) drawn by all of them.
static func _place(
	holder: Node3D, label: String, model: Dictionary, transforms: Array, tint: Color
) -> Dictionary:
	var grounded = _grounded(model)
	var parts = []
	var tris = 0
	var index = 0
	for m in model["meshes"]:
		var mm = MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = _tinted(m["mesh"], tint)
		mm.instance_count = transforms.size()
		for i in range(transforms.size()):
			mm.set_instance_transform(
				i, (transforms[i] as Transform3D) * grounded * (m["xform"] as Transform3D)
			)
		var mmi = MultiMeshInstance3D.new()
		mmi.name = "%s_%d" % [label, index]
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		holder.add_child(mmi)
		parts.append(mmi)
		tris += (m["mesh"] as Mesh).get_faces().size() / 3 * transforms.size()
		index += 1
	return {"parts": parts, "tris": tris}


# the mesh itself when the tint is white, else a copy whose materials are multiplied by the tint
static func _tinted(mesh: Mesh, tint: Color) -> Mesh:
	if tint == Color.WHITE:
		return mesh
	var copy: Mesh = mesh.duplicate()
	for i in range(copy.get_surface_count()):
		var mat = copy.surface_get_material(i)
		if mat is BaseMaterial3D:
			var tinted: BaseMaterial3D = mat.duplicate()
			tinted.albedo_color = tint
			copy.surface_set_material(i, tinted)
	return copy


# how big the grounded model is: Vector3(x, y, z) in metres
static func model_size(path: String) -> Vector3:
	var model = load_model(path)
	if model.is_empty():
		return Vector3.ZERO
	return (model["aabb"] as AABB).size


# ---------------------------------------------------------------- transforms
static func _building_transforms(planned: Dictionary) -> Array:
	var out = []
	if planned["buildings"].is_empty():
		return out
	var size = model_size(BUILDING_PATH)
	if size == Vector3.ZERO:
		return out
	for b in planned["buildings"]:
		var s = Vector3(b["size"].x / size.x, float(b["y"]), b["size"].y / size.z)
		var basis = Basis(Vector3.UP, float(b["yaw"])) * Basis.from_scale(s)
		out.append(Transform3D(basis, b["pos"]))
	return out


static func _bench_transforms(planned: Dictionary) -> Array:
	var out = []
	for b in planned["benches"]:
		out.append(Transform3D(Basis(Vector3.UP, float(b["yaw"])), b["pos"]))
	return out


static func _crate_transforms(planned: Dictionary) -> Array:
	var out = []
	for c in planned["crates"]:
		var basis = (
			Basis(Vector3.UP, float(c["yaw"])) * Basis.from_scale(Vector3.ONE * float(c["scale"]))
		)
		out.append(Transform3D(basis, c["pos"]))
	return out


# ---------------------------------------------------------------- buildings
static func _plan_buildings(layout: Dictionary) -> Array:
	var n = int(layout["cells"])
	var cell = float(layout["cell"])
	var rows: Array = layout["rows"]
	var size = model_size(BUILDING_PATH)
	var out = []
	if size == Vector3.ZERO:
		return out
	var lots = WorldDress.lots_of(layout)
	for i in range(lots.size()):
		var c: Array = lots[i]["cells"]
		var cw = int(c[2]) - int(c[0])
		var cd = int(c[3]) - int(c[1])
		if cw < BUILDING_MIN_CELLS or cd < BUILDING_MIN_CELLS:
			continue
		if _hash([c[0], c[1], c[2], c[3], 9157]) % 100 >= BUILDING_PERCENT:
			continue
		var side = _facing_side(rows, n, c, size, cell)
		if side < 0:
			continue
		var along = float(cw if side == 0 or side == 2 else cd) * cell
		var into = float(cd if side == 0 or side == 2 else cw) * cell
		var x0 = WorldGen.grid_edge(n, cell, int(c[0]))
		var z0 = WorldGen.grid_edge(n, cell, int(c[1]))
		var x1 = WorldGen.grid_edge(n, cell, int(c[2]))
		var z1 = WorldGen.grid_edge(n, cell, int(c[3]))
		var dir: Vector2i = SIDES[side]
		out.append(
			{
				"lot": i,
				"pos": Vector3((x0 + x1) * 0.5, 0.0, (z0 + z1) * 0.5),
				"yaw": atan2(float(dir.x), float(dir.y)),
				"size": Vector2(along * BUILDING_FILL, into * BUILDING_FILL),
				"y": clampf(float(lots[i]["h"]) / size.y, BUILDING_Y_MIN, BUILDING_Y_MAX)
			}
		)
	return out


# The side (0 north, 1 east, 2 south, 3 west) of a lot that the model's face should look at: of the sides that look
# onto open ground, the one that stretches the model the least, or -1 when every one stretches it more than
# BUILDING_MAX_STRETCH (or the lot has no open side).
static func _facing_side(rows: Array, n: int, c: Array, size: Vector3, cell: float) -> int:
	var cw = float(int(c[2]) - int(c[0])) * cell
	var cd = float(int(c[3]) - int(c[1])) * cell
	var best = -1
	var best_score = 1000000.0
	for side in range(4):
		var open = _open_faces(rows, n, c, side)
		if open == 0:
			continue
		var ns = side == 0 or side == 2
		var sx = (cw if ns else cd) / size.x
		var sz = (cd if ns else cw) / size.z
		var stretch = maxf(sx, sz) / minf(sx, sz)
		if stretch > BUILDING_MAX_STRETCH:
			continue
		var score = stretch - float(open) * 0.001  # a longer open face wins a tie
		if score < best_score:
			best_score = score
			best = side
	return best


# how many cells of one side of a lot have open ground (road, sidewalk, plaza or grass) in front of them
static func _open_faces(rows: Array, n: int, c: Array, side: int) -> int:
	var step: Vector2i = SIDES[side]
	var ns = side == 0 or side == 2
	var lo = int(c[0]) if ns else int(c[1])
	var hi = int(c[2]) if ns else int(c[3])
	var found = 0
	for i in range(lo, hi):
		var cx = i if ns else (int(c[2]) - 1 if side == 1 else int(c[0]))
		var cz = (int(c[3]) - 1 if side == 2 else int(c[1])) if ns else i
		var beyond = WorldGen.cell_at(rows, n, cx + step.x, cz + step.y)
		if beyond != "b" and beyond != "t":
			found += 1
	return found


# ---------------------------------------------------------------- benches
static func _plan_benches(layout: Dictionary) -> Array:
	var n = int(layout["cells"])
	var cell = float(layout["cell"])
	var rows: Array = layout["rows"]
	var found = []
	for cz in range(n):
		for cx in range(n):
			if WorldGen.cell_at(rows, n, cx, cz) != "s":
				continue
			var dir = _road_side(rows, n, cx, cz)
			if dir == Vector2i.ZERO:
				continue
			if WorldDress.lamp_side(rows, n, cx, cz) != Vector2i.ZERO:
				continue
			var centre = _centre(n, cell, cx, cz)
			if _near_start_or_gate(layout, centre):
				continue
			found.append({"cell": Vector2i(cx, cz), "dir": dir, "key": _hash([cx, cz, 5231])})
	var out = []
	for pick in _spread(found, BENCH_MAX, BENCH_SPACING):
		var d = Vector2(float(pick["dir"].x), float(pick["dir"].y))
		var at = _centre(n, cell, pick["cell"].x, pick["cell"].y) + d * BENCH_SETBACK
		out.append({"pos": Vector3(at.x, 0.0, at.y), "yaw": atan2(d.x, d.y)})  # the bench's front looks at the road
	return out


# The side a sidewalk cell's one road is on, or (0, 0) when the cell touches no road or more than one, or has a
# tunnel within a cell.
static func _road_side(rows: Array, n: int, cx: int, cz: int) -> Vector2i:
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
	return found


# ---------------------------------------------------------------- crates
static func _plan_crates(layout: Dictionary, benches: Array) -> Array:
	var n = int(layout["cells"])
	var cell = float(layout["cell"])
	var rows: Array = layout["rows"]
	var crate = model_size(CRATE_PATH)
	var out = []
	if crate == Vector3.ZERO:
		return out
	var bench_cells = []
	for b in benches:
		bench_cells.append(
			Vector2i(
				floori(b["pos"].x / cell + float(n) / 2.0),
				floori(b["pos"].z / cell + float(n) / 2.0)
			)
		)
	var found = []
	for cz in range(n):
		for cx in range(n):
			var here = WorldGen.cell_at(rows, n, cx, cz)
			if here != "s" and here != "p" and here != "g":
				continue
			if _within(bench_cells, Vector2i(cx, cz), CRATE_BENCH_GAP):
				continue
			var wall = _wall_side(rows, n, cx, cz)
			if wall == Vector2i.ZERO:
				continue
			if _near_start_or_gate(layout, _centre(n, cell, cx, cz)):
				continue
			found.append({"cell": Vector2i(cx, cz), "dir": wall, "key": _hash([cx, cz, 7919])})
	for pick in _spread(found, CRATE_MAX, CRATE_SPACING):
		var key: int = pick["key"]
		var s = lerpf(CRATE_SCALE_MIN, CRATE_SCALE_MAX, float(key % 100) / 99.0)
		var d = Vector2(float(pick["dir"].x), float(pick["dir"].y))
		var along = Vector2(-d.y, d.x)  # runs along the wall
		var depth = maxf(crate.x, crate.z) * s * 0.5  # the crate's half depth, whichever way it is turned
		var reach = cell * 0.5 - depth - CRATE_WALL_GAP
		var jitter = (float((key / 100) % 21) - 10.0) * 0.012  # up to about 7 degrees off the wall
		var base = _centre(n, cell, pick["cell"].x, pick["cell"].y) + d * reach
		var yaw = atan2(d.x, d.y) + jitter  # a crate is a box: only the small turn off the wall matters
		match (key / 2100) % 3:
			0:  # one crate with another on top
				out.append({"pos": Vector3(base.x, 0.0, base.y), "yaw": yaw, "scale": s})
				out.append(
					{"pos": Vector3(base.x, crate.y * s, base.y), "yaw": yaw + 0.3, "scale": s}
				)
			1:  # two side by side along the wall, turned so the short side runs along it: both stay in the cell
				var half = crate.z * s * 0.5 + 0.025
				var first = base - along * half
				var second = base + along * half
				out.append(
					{"pos": Vector3(first.x, 0.0, first.y), "yaw": yaw + PI * 0.5, "scale": s}
				)
				out.append(
					{"pos": Vector3(second.x, 0.0, second.y), "yaw": yaw - PI * 0.5, "scale": s}
				)
			_:
				out.append({"pos": Vector3(base.x, 0.0, base.y), "yaw": yaw, "scale": s})
	return out


# The side of a sidewalk or plaza cell that a building is on, or (0, 0) when the cell touches no building, more than
# one side of building, a road anywhere but on the side opposite the wall (the crate stands at the wall and leaves
# the other side of the cell free), or has a tunnel within two cells.
static func _wall_side(rows: Array, n: int, cx: int, cz: int) -> Vector2i:
	var found = Vector2i.ZERO
	var touching = 0
	var roads = []
	for step in SIDES:
		var beyond = WorldGen.cell_at(rows, n, cx + step.x, cz + step.y)
		if beyond == "r":
			roads.append(step)
		if beyond == "b":
			found = step
			touching += 1
	if touching != 1:
		return Vector2i.ZERO
	for r in roads:
		if r != -found:
			return Vector2i.ZERO
	for dz in range(-2, 3):
		for dx in range(-2, 3):
			if WorldGen.cell_at(rows, n, cx + dx, cz + dz) == "t":
				return Vector2i.ZERO
	return found


# ---------------------------------------------------------------- shared
# From the candidates ({"cell": Vector2i, "key": int, ...}) the ones to use: by key, never closer than `spacing`
# cells (in either direction) to one already taken, at most `limit`.
static func _spread(candidates: Array, limit: int, spacing: int) -> Array:
	var sorted = candidates.duplicate()
	sorted.sort_custom(func(a, b): return int(a["key"]) < int(b["key"]))
	var taken = []
	for c in sorted:
		if taken.size() >= limit:
			break
		var ok = true
		for t in taken:
			var d: Vector2i = c["cell"] - t["cell"]
			if maxi(absi(d.x), absi(d.y)) < spacing:
				ok = false
				break
		if ok:
			taken.append(c)
	return taken


# true when `at` is within `gap` cells (in both directions) of one of the cells
static func _within(cells: Array, at: Vector2i, gap: int) -> bool:
	for c in cells:
		var d: Vector2i = c - at
		if maxi(absi(d.x), absi(d.y)) < gap:
			return true
	return false


static func _centre(n: int, cell: float, cx: int, cz: int) -> Vector2:
	return Vector2(
		WorldGen.grid_edge(n, cell, cx) + cell * 0.5, WorldGen.grid_edge(n, cell, cz) + cell * 0.5
	)


# true when a point (world x, z) is within KEEP_CLEAR metres of the start or of a gate
static func _near_start_or_gate(layout: Dictionary, at: Vector2) -> bool:
	var spots = []
	if layout.has("start"):
		spots.append(layout["start"]["pos"])
	for g in layout.get("gates", []):
		spots.append(g["pos"])
	for p in spots:
		if at.distance_to(Vector2(float(p[0]), float(p[1]))) < KEEP_CLEAR:
			return true
	return false


# a stable number from a few ints (no random functions: the same cells always give the same pick)
static func _hash(values: Array) -> int:
	var h = 2166136261
	for v in values:
		h = ((h ^ (int(v) + 0x9E3779B9)) * 16777619) & 0x7FFFFFFF
	return h
