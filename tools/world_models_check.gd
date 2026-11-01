extends SceneTree
# Checks the modelled buildings, benches and crates that scripts/world_models.gd puts on an arena (README Milestone
# F9, "World"). Run from the project folder:
#   godot --headless --path . --script res://tools/world_models_check.gd
# Optional argument after "--": how many seeds to build (default 40).
# For every seed it checks that
#   - the plan is the same when it is made twice, and an empty layout gives an empty plan
#   - every planned building is a lot of at least 2 x 2 cells with a side onto open ground, stands exactly on the
#     lot's middle, is turned to an open side, stays inside the lot and is stretched less than the most allowed
#   - every bench is on a sidewalk cell that touches exactly one road and no tunnel, not on a lamp cell, faces the
#     road, and there are at most BENCH_MAX of them, never closer than BENCH_SPACING cells
#   - every crate is on the ground or on another crate, against one building on a sidewalk, plaza or grass cell, there
#     are at most two crates to a place and never more than CRATE_MAX places
#   - nothing is within KEEP_CLEAR metres of the start or of a gate
#   - WorldDress.build with the skipped lots draws no wall for them and still lists every lot, and without them it
#     draws what it always did
#   - build() makes one MultiMesh per mesh of each model with one instance per placement, the triangle count it
#     reports is right, and a path that does not exist is left out without an error
# It also damages a plan three ways (a bench on a road cell, a crate in the start, a building outside its lot) and
# fails if the checks do not name each one. Exits with status 1 and lists the first problems when a check fails.

const ArenaGen = preload("res://scripts/arena_gen.gd")
const WorldGen = preload("res://scripts/world_gen.gd")
const WorldDress = preload("res://scripts/world_dress.gd")
const WorldModels = preload("res://scripts/world_models.gd")

const EPS = 0.01
const SIDES = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]

var problems = []
var buildings_total = 0
var benches_total = 0
var crates_total = 0
var arenas_with_models = 0
var model_tris_max = 0
var model_calls_max = 0


func _initialize() -> void:
	var count = 40
	var args = OS.get_cmdline_user_args()
	if args.size() > 0:
		count = int(args[0])
	var rules = ArenaGen.load_rules()
	if rules.is_empty():
		quit(1)
		return
	var first_layout = {}
	for k in range(count):
		var seed_value = (k * 2654435761 + 4242) & 0xFFFFFFFF
		var layout = ArenaGen.generate(seed_value, rules)
		if layout.is_empty():
			problems.append("seed %08X: no layout was generated" % seed_value)
			continue
		var found = _check_layout(layout)
		for p in found:
			problems.append("seed %08X: %s" % [seed_value, p])
		if first_layout.is_empty() and not WorldModels.plan(layout)["benches"].is_empty():
			if not WorldModels.plan(layout)["crates"].is_empty():
				first_layout = layout
	if not WorldModels.plan({})["benches"].is_empty():
		problems.append("an empty layout did not give an empty plan")
	problems.append_array(_check_missing_model())
	if first_layout.is_empty():
		problems.append("no arena had both benches and crates, the damage tests cannot run")
	else:
		problems.append_array(_check_damage(first_layout))
	if arenas_with_models == 0:
		problems.append("no arena got any model: the check says nothing")
	if problems.is_empty():
		print(
			(
				"world_models_check: %d arenas, %d modelled buildings, %d benches, %d crates, up to %d model triangles and %d model draw calls; placement rules, spacing, clear zones, skipped lots and the MultiMeshes are right"
				% [
					count,
					buildings_total,
					benches_total,
					crates_total,
					model_tris_max,
					model_calls_max
				]
			)
		)
		quit(0)
		return
	for i in range(mini(problems.size(), 25)):
		print("world_models_check: ", problems[i])
	print("world_models_check: %d problems" % problems.size())
	quit(1)


func _check_layout(layout: Dictionary) -> Array:
	var bad = []
	var n = int(layout["cells"])
	var cell = float(layout["cell"])
	var rows: Array = layout["rows"]
	var planned = WorldModels.plan(layout)
	if str(planned) != str(WorldModels.plan(layout)):
		bad.append("the plan is not the same when made twice")
	var lots = WorldDress.lots_of(layout)
	for b in planned["buildings"]:
		bad.append_array(_check_building(layout, lots, b))
	bad.append_array(_check_benches(planned["benches"], rows, n, cell))
	bad.append_array(_check_crates(planned["crates"], planned["benches"], rows, n, cell))
	for key in ["benches", "crates"]:
		for item in planned[key]:
			var at = Vector2i(
				floori(item["pos"].x / cell + float(n) / 2.0),
				floori(item["pos"].z / cell + float(n) / 2.0)
			)
			var centre = Vector2(
				WorldGen.grid_edge(n, cell, at.x) + cell * 0.5,
				WorldGen.grid_edge(n, cell, at.y) + cell * 0.5
			)
			if _near_start_or_gate(layout, centre):
				bad.append("a %s is within the clear zone of the start or a gate" % key[0])
	bad.append_array(_check_skip(layout, planned, lots))
	# build it for real
	var root = Node3D.new()
	var made = WorldModels.build(root, planned)
	bad.append_array(_check_build(planned, made, root))
	root.free()
	buildings_total += planned["buildings"].size()
	benches_total += planned["benches"].size()
	crates_total += planned["crates"].size()
	if not planned["benches"].is_empty() or not planned["crates"].is_empty():
		arenas_with_models += 1
	model_tris_max = maxi(model_tris_max, int(made["tris"]))
	model_calls_max = maxi(model_calls_max, int(made["draw_calls"]))
	return bad


func _check_building(layout: Dictionary, lots: Array, b: Dictionary) -> Array:
	var bad = []
	var n = int(layout["cells"])
	var cell = float(layout["cell"])
	var rows: Array = layout["rows"]
	var i = int(b["lot"])
	if i < 0 or i >= lots.size():
		return ["a building is on lot %d, there are %d lots" % [i, lots.size()]]
	var c: Array = lots[i]["cells"]
	if int(c[2]) - int(c[0]) < 2 or int(c[3]) - int(c[1]) < 2:
		bad.append(
			(
				"lot %d is %d x %d cells, a model needs 2 x 2"
				% [i, int(c[2]) - int(c[0]), int(c[3]) - int(c[1])]
			)
		)
	var x0 = WorldGen.grid_edge(n, cell, int(c[0]))
	var z0 = WorldGen.grid_edge(n, cell, int(c[1]))
	var x1 = WorldGen.grid_edge(n, cell, int(c[2]))
	var z1 = WorldGen.grid_edge(n, cell, int(c[3]))
	var pos: Vector3 = b["pos"]
	if (
		absf(pos.x - (x0 + x1) * 0.5) > EPS
		or absf(pos.z - (z0 + z1) * 0.5) > EPS
		or absf(pos.y) > EPS
	):
		bad.append("lot %d: the model is not in the middle of the lot" % i)
	# the face looks at an open side
	var yaw = float(b["yaw"])
	var face = Vector2i(roundi(sin(yaw)), roundi(cos(yaw)))
	var side = SIDES.find(face)
	if side < 0:
		bad.append("lot %d: the model is turned to no side (yaw %.2f)" % [i, yaw])
	elif _open_cells(rows, n, c, side) == 0:
		bad.append("lot %d: the model looks at a side with nothing open in front of it" % i)
	# inside the lot
	var along: float = b["size"].x
	var into: float = b["size"].y
	var ns = face.y != 0
	var w = along if ns else into
	var d = into if ns else along
	if w > (x1 - x0) + EPS or d > (z1 - z0) + EPS:
		bad.append("lot %d: the model (%.2f x %.2f) is bigger than the lot" % [i, w, d])
	var mw = WorldModels.model_size(WorldModels.BUILDING_PATH)
	if mw != Vector3.ZERO:
		var sx = along / mw.x
		var sz = into / mw.z
		if maxf(sx, sz) / minf(sx, sz) > WorldModels.BUILDING_MAX_STRETCH + 0.001:
			bad.append(
				"lot %d: the model is stretched %.2f times" % [i, maxf(sx, sz) / minf(sx, sz)]
			)
	var y = float(b["y"])
	if y < WorldModels.BUILDING_Y_MIN - 0.001 or y > WorldModels.BUILDING_Y_MAX + 0.001:
		bad.append("lot %d: the height factor %.2f is out of range" % [i, y])
	return bad


func _check_benches(benches: Array, rows: Array, n: int, cell: float) -> Array:
	var bad = []
	if benches.size() > WorldModels.BENCH_MAX:
		bad.append("%d benches, at most %d" % [benches.size(), WorldModels.BENCH_MAX])
	var cells = []
	for b in benches:
		var pos: Vector3 = b["pos"]
		var cx = floori(pos.x / cell + float(n) / 2.0)
		var cz = floori(pos.z / cell + float(n) / 2.0)
		cells.append(Vector2i(cx, cz))
		if WorldGen.cell_at(rows, n, cx, cz) != "s":
			bad.append(
				"a bench is on a %s cell, not a sidewalk" % WorldGen.cell_at(rows, n, cx, cz)
			)
			continue
		var roads = []
		for step in SIDES:
			if WorldGen.cell_at(rows, n, cx + step.x, cz + step.y) == "r":
				roads.append(step)
		if roads.size() != 1:
			bad.append("a bench is on a sidewalk cell that touches %d roads" % roads.size())
			continue
		var face = Vector2i(roundi(sin(float(b["yaw"]))), roundi(cos(float(b["yaw"]))))
		if face != roads[0]:
			bad.append("a bench at cell %d, %d does not face its road" % [cx, cz])
		if WorldDress.lamp_side(rows, n, cx, cz) != Vector2i.ZERO:
			bad.append("a bench is on a lamp cell")
		for dz in range(-1, 2):
			for dx in range(-1, 2):
				if WorldGen.cell_at(rows, n, cx + dx, cz + dz) == "t":
					bad.append("a bench is within a cell of a tunnel")
		if absf(pos.y) > EPS:
			bad.append("a bench is not on the ground")
	bad.append_array(_check_spacing(cells, WorldModels.BENCH_SPACING, "benches"))
	return bad


func _check_crates(crates: Array, benches: Array, rows: Array, n: int, cell: float) -> Array:
	var bad = []
	var places = {}
	for c in crates:
		var pos: Vector3 = c["pos"]
		var cx = floori(pos.x / cell + float(n) / 2.0)
		var cz = floori(pos.z / cell + float(n) / 2.0)
		var here = WorldGen.cell_at(rows, n, cx, cz)
		if here != "s" and here != "p" and here != "g":
			bad.append("a crate is on a %s cell" % here)
			continue
		var walls = []
		var roads = []
		for step in SIDES:
			var beyond = WorldGen.cell_at(rows, n, cx + step.x, cz + step.y)
			if beyond == "r":
				roads.append(step)
			if beyond == "b":
				walls.append(step)
		if walls.size() != 1:
			bad.append(
				"a crate at cell %d, %d has %d buildings next to it" % [cx, cz, walls.size()]
			)
		else:
			for r in roads:
				if r != -walls[0]:
					bad.append("a crate is on a cell with a road beside it, not behind it")
			var face = Vector2(float(walls[0].x), float(walls[0].y))
			var centre = Vector2(
				WorldGen.grid_edge(n, cell, cx) + cell * 0.5,
				WorldGen.grid_edge(n, cell, cz) + cell * 0.5
			)
			var from_centre = Vector2(pos.x, pos.z) - centre
			if from_centre.dot(face) < 0.0:
				bad.append(
					"a crate at cell %d, %d is on the far side of its cell from the wall" % [cx, cz]
				)
		if pos.y > 0.0 + EPS:
			var below = false
			for o in crates:
				if (
					absf(o["pos"].x - pos.x) < EPS
					and absf(o["pos"].z - pos.z) < EPS
					and absf(o["pos"].y) < EPS
				):
					below = true
			if not below:
				bad.append("a crate floats above nothing")
		for b in benches:
			if absf(b["pos"].x - pos.x) < cell * 1.5 and absf(b["pos"].z - pos.z) < cell * 1.5:
				bad.append("a crate is within a cell and a half of a bench")
		var key = Vector2i(cx, cz)
		places[key] = int(places.get(key, 0)) + 1
	if places.size() > WorldModels.CRATE_MAX:
		bad.append("%d crate places, at most %d" % [places.size(), WorldModels.CRATE_MAX])
	for key in places:
		if int(places[key]) > 2:
			bad.append("%d crates in cell %d, %d" % [places[key], key.x, key.y])
	return bad


func _check_spacing(cells: Array, spacing: int, what: String) -> Array:
	var bad = []
	for i in range(cells.size()):
		for j in range(i + 1, cells.size()):
			var d: Vector2i = cells[i] - cells[j]
			if maxi(absi(d.x), absi(d.y)) < spacing:
				bad.append(
					(
						"two %s are %d cells apart, at least %d"
						% [what, maxi(absi(d.x), absi(d.y)), spacing]
					)
				)
	return bad


func _check_skip(layout: Dictionary, planned: Dictionary, lots: Array) -> Array:
	var bad = []
	var skip = WorldModels.skipped_lots(planned)
	var plain = WorldDress.build(layout)
	var skipped = WorldDress.build(layout, skip)
	if skipped["buildings"].size() != lots.size():
		bad.append(
			(
				'with skipped lots "buildings" lists %d lots, not %d'
				% [skipped["buildings"].size(), lots.size()]
			)
		)
	var plain_tris = int(plain["tris"])
	var skipped_tris = int(skipped["tris"])
	if skip.is_empty() and plain_tris != skipped_tris:
		bad.append("nothing was skipped but the triangles changed")
	if not skip.is_empty() and skipped_tris >= plain_tris:
		bad.append("%d lots were skipped but the box meshes did not get smaller" % skip.size())
	# no wall of a skipped lot is drawn: its middle on the roof height is not inside any wall mesh
	var n = int(layout["cells"])
	var cell = float(layout["cell"])
	for i in skip:
		var lot = lots[i]
		var c: Array = lot["cells"]
		var mid = Vector3(
			(WorldGen.grid_edge(n, cell, int(c[0])) + WorldGen.grid_edge(n, cell, int(c[2]))) * 0.5,
			float(lot["h"]),
			(WorldGen.grid_edge(n, cell, int(c[1])) + WorldGen.grid_edge(n, cell, int(c[3]))) * 0.5
		)
		for part_name in ["walls_brick", "walls_dark"]:
			if (
				skipped["parts"].has(part_name)
				and _mesh_has_top_at(skipped["parts"][part_name], mid)
			):
				bad.append("lot %d was skipped but its roof is still drawn" % i)
	plain["root"].free()
	skipped["root"].free()
	return bad


# true when the mesh has an upward-facing triangle at height mid.y whose box contains mid (x, z)
func _mesh_has_top_at(part: MeshInstance3D, mid: Vector3) -> bool:
	var faces = part.mesh.get_faces()
	for t in range(0, faces.size(), 3):
		var a = faces[t]
		var b = faces[t + 1]
		var c = faces[t + 2]
		if absf(a.y - mid.y) > EPS or absf(b.y - mid.y) > EPS or absf(c.y - mid.y) > EPS:
			continue
		var lo_x = minf(a.x, minf(b.x, c.x))
		var hi_x = maxf(a.x, maxf(b.x, c.x))
		var lo_z = minf(a.z, minf(b.z, c.z))
		var hi_z = maxf(a.z, maxf(b.z, c.z))
		if (
			mid.x >= lo_x - EPS
			and mid.x <= hi_x + EPS
			and mid.z >= lo_z - EPS
			and mid.z <= hi_z + EPS
		):
			return true
	return false


func _check_build(planned: Dictionary, made: Dictionary, root: Node3D) -> Array:
	var bad = []
	var want = {
		"building": planned["buildings"].size(),
		"bench": planned["benches"].size(),
		"crate": planned["crates"].size()
	}
	var tris = 0
	var parts = 0
	for mmi in root.find_children("*", "MultiMeshInstance3D", true, false):
		var label = str(mmi.name).split("_")[0]
		var mm: MultiMesh = mmi.multimesh
		parts += 1
		if not want.has(label):
			bad.append("a MultiMesh named %s" % mmi.name)
			continue
		if mm.instance_count != int(want[label]):
			bad.append(
				"%s has %d instances, the plan has %d" % [mmi.name, mm.instance_count, want[label]]
			)
		tris += mm.mesh.get_faces().size() / 3 * mm.instance_count
	if parts != int(made["draw_calls"]):
		bad.append("draw_calls says %d, there are %d MultiMeshes" % [made["draw_calls"], parts])
	if tris != int(made["tris"]):
		bad.append("tris says %d, the MultiMeshes have %d" % [made["tris"], tris])
	if made["parts"].size() != parts:
		bad.append('"parts" lists %d, there are %d' % [made["parts"].size(), parts])
	return bad


# a model that is not there is left out, with no parts and no error
func _check_missing_model() -> Array:
	var bad = []
	if not WorldModels.load_model("res://assets/models/no_such_model.glb").is_empty():
		bad.append("a path that does not exist gave a model")
	if WorldModels.model_size("res://assets/models/no_such_model.glb") != Vector3.ZERO:
		bad.append("a path that does not exist has a size")
	return bad


func _check_damage(layout: Dictionary) -> Array:
	var bad = []
	var n = int(layout["cells"])
	var cell = float(layout["cell"])
	var rows: Array = layout["rows"]
	var good = WorldModels.plan(layout)
	# a bench on a road cell
	var broken = good.duplicate(true)
	for cz in range(n):
		var found = false
		for cx in range(n):
			if WorldGen.cell_at(rows, n, cx, cz) == "r":
				var at = WorldGen.grid_edge(n, cell, cx) + cell * 0.5
				broken["benches"][0]["pos"] = Vector3(
					at, 0.0, WorldGen.grid_edge(n, cell, cz) + cell * 0.5
				)
				found = true
				break
		if found:
			break
	if _check_benches(broken["benches"], rows, n, cell).is_empty():
		bad.append("damage test: a bench on a road was not noticed")
	# a crate in the start
	broken = good.duplicate(true)
	var start = layout["start"]["pos"]
	broken["crates"][0]["pos"] = Vector3(float(start[0]), 0.0, float(start[1]))
	if not _near_start_or_gate(layout, Vector2(float(start[0]), float(start[1]))):
		bad.append("damage test: the start is not in its own clear zone")
	if _check_crates(broken["crates"], broken["benches"], rows, n, cell).is_empty():
		bad.append("damage test: a crate in the start was not noticed")
	# a building outside its lot
	var lots = WorldDress.lots_of(layout)
	if not good["buildings"].is_empty():
		broken = good.duplicate(true)
		broken["buildings"][0]["size"] = Vector2(100.0, 100.0)
		if _check_building(layout, lots, broken["buildings"][0]).is_empty():
			bad.append("damage test: a building bigger than its lot was not noticed")
	return bad


func _open_cells(rows: Array, n: int, c: Array, side: int) -> int:
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


func _near_start_or_gate(layout: Dictionary, at: Vector2) -> bool:
	var spots = [layout["start"]["pos"]]
	for g in layout.get("gates", []):
		spots.append(g["pos"])
	for p in spots:
		if at.distance_to(Vector2(float(p[0]), float(p[1]))) < WorldModels.KEEP_CLEAR - EPS:
			return true
	return false
