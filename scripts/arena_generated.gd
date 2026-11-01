extends "res://scripts/arena.gd"
# A generated arena (README Milestone K): the Arena interface on top of a layout from arena_gen.gd. It is built
# in small steps; this file says in each section what is done. Everything here reads only the layout and the
# arena rules, so one seed gives one arena. Not used by the game yet (see docs/PROCEDURAL_ARENAS.md).

const ArenaGenScript = preload("res://scripts/arena_gen.gd")
const WorldDressScript = preload("res://scripts/world_dress.gd")

var layout: Dictionary = {}
var rules: Dictionary = {}
var _gates: Array = []
var _trees: Dictionary = {}  # the trees the world stands on the grass, by cell (Vector2i): the trunk's x and z (Vector2)


func _init(the_layout: Dictionary = {}, the_rules: Dictionary = {}) -> void:
	layout = the_layout
	rules = the_rules if not the_rules.is_empty() else ArenaGenScript.load_rules()
	_gates = _world_gates()
	_trees = _tree_table()


# The trunks of the layout's trees, found the way the world finds them to stand them (WorldDress.props_of, from the
# cells alone), so what is drawn is what is solid. At most one per cell, in the middle of it.
func _tree_table() -> Dictionary:
	var out = {}
	if not (layout.has("cells") and layout.has("cell") and layout.has("rows")):
		return out
	for tree in WorldDressScript.props_of(layout)["trees"]:
		out[tree["cell"]] = tree["pos"]
	return out


# true if p is closer than `reach` metres (along the ground) to the middle of a tree's trunk
func _near_tree(p: Vector3, reach: float) -> bool:
	if _trees.is_empty():
		return false
	var n = int(layout["cells"])
	var cell = float(layout["cell"])
	var cx = int(floor(p.x / cell + float(n) / 2.0))
	var cz = int(floor(p.z / cell + float(n) / 2.0))
	var span = int(ceil(reach / cell))  # a tree in a cell further off than this is further away than `reach`
	for dz in range(-span, span + 1):
		for dx in range(-span, span + 1):
			var key = Vector2i(cx + dx, cz + dz)
			if _trees.has(key):
				var at: Vector2 = _trees[key]
				if Vector2(p.x - at.x, p.z - at.y).length_squared() < reach * reach:
					return true
	return false


# ---------------------------------------------------------------- the ground
# what the ground is at world point p: "grass", "plaza", "sidewalk", "road", "tunnel" or "building"
func surface_at(p: Vector3) -> String:
	return ArenaGenScript.surface_at(layout, p.x, p.z)


# the share of its speed a rider keeps on the ground at p (0 where nothing can ride)
func rider_speed_at(p: Vector3) -> float:
	return ArenaGenScript.rider_speed_at(layout, rules, p.x, p.z)


# true: riders chase the player over open ground and steer round obstacles themselves
func rider_pursuit() -> bool:
	return true


func rider_avoidance() -> bool:
	return true


# false: a generated arena takes the theme of the round (day, dusk, night, ...); only the training room keeps its
# own light (Arena.fixed_lighting)
func fixed_lighting() -> bool:
	return false


# ---------------------------------------------------------------- the start and the gates
# the style the seed picked and its name on the screen (see Arena.style_name)
func style_name() -> String:
	return str(layout.get("style", ""))


func style_label() -> String:
	return str(layout.get("style_label", ""))


# the middle of the clear start area, on the ground
func start_position() -> Vector3:
	var s = layout["start"]["pos"]
	return Vector3(float(s[0]), 0.0, float(s[1]))


# where riders enter and leave, in world space (see Arena.gates)
func gates() -> Array:
	return _gates


func _world_gates() -> Array:
	var out = []
	for gate in layout.get("gates", []):
		out.append(
			{
				"pos": Vector3(float(gate["pos"][0]), 0.0, float(gate["pos"][1])),
				"outward": Vector3(float(gate["outward"][0]), 0.0, float(gate["outward"][1])),
				"half_width": float(gate["half_width"])
			}
		)
	return out


# ---------------------------------------------------------------- the cheerleaders
const CHEER_RING = 1  # cells outside the clear start square where the cheerleaders stand (the plaza is wider)
const CHEER_ROOM = 1.0  # metres of free ground kept round each one


# Up to `count` spots for the cheerleaders: the centres of plaza cells in a square ring just outside the clear start
# square, with CHEER_ROOM metres of free ground round them, spread evenly round the start by angle. The ring is the
# plaza's edge round the start, so they stand where the player can see them and never in the start area itself.
# The layout alone decides, so one seed gives the same spots. Fewer than `count` (or none) when the plaza has no room.
func cheer_spots(count: int) -> Array:
	var n = int(layout["cells"])
	var cell = float(layout["cell"])
	var sc = layout["start"]["cell"]
	var reach = int(layout["start"]["half"]) + CHEER_RING
	var home = start_position()
	var spots = []
	for dz in range(-reach, reach + 1):
		for dx in range(-reach, reach + 1):
			if maxi(absi(dx), absi(dz)) != reach:
				continue
			var cx = int(sc[0]) + dx
			var cz = int(sc[1]) + dz
			if cx < 0 or cz < 0 or cx >= n or cz >= n:
				continue
			var p = Vector3(
				(float(cx) + 0.5 - float(n) / 2.0) * cell,
				0.0,
				(float(cz) + 0.5 - float(n) / 2.0) * cell
			)
			if surface_at(p) == "plaza" and _clear(p, CHEER_ROOM):
				spots.append({"p": p, "a": atan2(p.z - home.z, p.x - home.x)})
	spots.sort_custom(func(a, b): return a["a"] < b["a"])
	var out = []
	var take = mini(count, spots.size())
	for i in range(take):
		out.append(spots[int(float(i) * float(spots.size()) / float(take))]["p"])
	return out


# ---------------------------------------------------------------- objectives (exploration)
# Where the extraction point and the supply caches go. Both read only the layout (and a seeded generator the caller
# hands in), so one seed and round give the same spots. A spot is the centre of an open cell with clearance
# GOAL_CLEAR (or CACHE_CLEAR), so it is never against a wall, and it can be reached on foot from the start through
# corridors at least 2 cells wide (the same rule the validation uses for the gates).
const GOAL_CLEAR = 3  # cells of room round the extraction point
const CACHE_CLEAR = 2  # cells of room round a supply cache
const WALK_CLEAR = 2  # corridors narrower than this do not count as a way there
const GOAL_TOP = 6  # the extraction point is one of the farthest this many spots (by walking distance)
const CACHE_MIN_WALK = 18.0  # a cache is at least this many metres of walking from the start, ...
const CACHE_APART = 22.0  # ... this far from the extraction point and from each other (straight line)

var _walk_dist: PackedInt32Array = PackedInt32Array()  # steps from the start cell, -1 where it cannot be reached


# steps on foot (4 directions, corridors with clearance >= WALK_CLEAR) from the start cell to every cell, -1 if none
func walk_distances() -> PackedInt32Array:
	if _walk_dist.size() > 0:
		return _walk_dist
	var n = int(layout["cells"])
	var sc = layout["start"]["cell"]
	var dist = PackedInt32Array()
	dist.resize(n * n)
	dist.fill(-1)
	var s = int(sc[1]) * n + int(sc[0])
	dist[s] = 0
	var queue = [s]
	var head = 0
	while head < queue.size():
		var i = int(queue[head])
		head += 1
		var x = i % n
		var z = i / n
		for step in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nx = x + step.x
			var nz = z + step.y
			if nx < 0 or nz < 0 or nx >= n or nz >= n or dist[nz * n + nx] != -1:
				continue
			if ArenaGenScript.nav_clearance(layout, nx, nz) >= WALK_CLEAR:
				dist[nz * n + nx] = dist[i] + 1
				queue.append(nz * n + nx)
	_walk_dist = dist
	return _walk_dist


# the world position of the centre of cell index i (x + z * cells)
func cell_world(i: int) -> Vector3:
	var n = int(layout["cells"])
	var cell = float(layout["cell"])
	return Vector3(
		(float(i % n) + 0.5 - float(n) / 2.0) * cell,
		0.0,
		(float(i / n) + 0.5 - float(n) / 2.0) * cell
	)


# open cells (index list) that can be walked to and have at least `clear` cells of room round them; cells that are
# on a road or on grass both count: only a building (clearance 0) and tunnel blocks are left out
func _spot_cells(clear: int) -> Array:
	var n = int(layout["cells"])
	var dist = walk_distances()
	var out = []
	for i in range(n * n):
		if dist[i] < 0:
			continue
		if ArenaGenScript.nav_clearance(layout, i % n, i / n) < clear:
			continue
		if surface_at(cell_world(i)) == "tunnel":
			continue
		if _trees.has(Vector2i(i % n, i / n)):
			continue  # a trunk stands in the middle of this cell
		out.append(i)
	return out


# The extraction point: one of the GOAL_TOP spots that are furthest to walk from the start, picked by `rng` (so each
# round of a run can end somewhere else, and one seed and round always give the same one).
func goal_spot(rng: RandomNumberGenerator) -> Vector3:
	var dist = walk_distances()
	var cells = _spot_cells(GOAL_CLEAR)
	if cells.is_empty():
		cells = _spot_cells(1)
	if cells.is_empty():
		return start_position()
	cells.sort_custom(func(a, b): return dist[a] > dist[b] or (dist[a] == dist[b] and a < b))
	return cell_world(int(cells[rng.randi() % mini(GOAL_TOP, cells.size())]))


# Up to `count` cache spots, spread over the arena: far from the start (CACHE_MIN_WALK metres of walking), the
# extraction point `goal` and each other (CACHE_APART metres), picking the spot that is furthest from everything
# chosen so far among a random handful, so they end up in different corners. Fewer than `count` if the arena has no room.
func cache_spots(count: int, goal: Vector3, rng: RandomNumberGenerator) -> Array:
	var cell = float(layout["cell"])
	var dist = walk_distances()
	var pool = []
	for i in _spot_cells(CACHE_CLEAR):
		if float(dist[i]) * cell >= CACHE_MIN_WALK:
			pool.append(i)
	var chosen = []
	var anchors = [start_position(), goal]
	while chosen.size() < count and not pool.is_empty():
		var scored = []
		for i in pool:
			var p = cell_world(i)
			var nearest = INF
			for a in anchors:
				nearest = minf(nearest, Vector2(p.x - a.x, p.z - a.z).length())
			if nearest >= CACHE_APART:
				scored.append({"i": i, "d": nearest})
		if scored.is_empty():
			break
		scored.sort_custom(
			func(a, b): return a["d"] > b["d"] or (a["d"] == b["d"] and a["i"] < b["i"])
		)
		var pick = scored[rng.randi() % mini(8, scored.size())]
		var spot = cell_world(int(pick["i"]))
		chosen.append(spot)
		anchors.append(spot)
		pool.erase(int(pick["i"]))
	return chosen


# ---------------------------------------------------------------- bounds and blocking
# Margins (metres) kept clear round a point so a body does not sink into a wall: the player, a boss (which
# may stand a little closer to the edge) and a pickup's landing spot (kept further in so it can be reached).
const MARGINS = {"player": 0.45, "boss": 0.3, "pickup": 1.0}
const SOLID_HEIGHT = 6.5  # metres: the lowest building or tunnel block; a dart above it is not stopped here
const SLIDE_STEP = 0.25  # metres between the rings searched for the nearest free point
const SLIDE_MAX = 8.0  # metres: out to here the search rings are fine (SLIDE_STEP apart)
const SLIDE_COARSE_STEP = 1.0  # metres between rings, and along them, beyond SLIDE_MAX
const TREE_RIDER_CLEAR = 0.3 + WorldDressScript.TRUNK_SOLID  # a boss's margin and the trunk: 0.55 m from the trunk's middle
const WALL_HALVINGS = 6  # a step into a wall is cut back to the wall in this many halvings (1/64 of a step)


# true if the cell under p is ground (not a building or a tunnel block): what the walls, the wall-jumps and the darts
# go by. Trees are not in it: a trunk is no wall to jump off, and the leaves are above the darts' reach.
func _ground_walkable(p: Vector3) -> bool:
	var s = surface_at(p)
	return s != "building" and s != "tunnel"


# true if p is ground a boss on foot can stand on (what obstacle_at asks): ground, and not within a boss's reach of
# a trunk. That is wider than the trunk itself (TREE_RIDER_CLEAR, not TRUNK_SOLID) so the one-metre looks that
# bosses and riders take along their way cannot slip between two samples past a trunk and walk into it.
func _walkable(p: Vector3) -> bool:
	return _ground_walkable(p) and not _near_tree(p, TREE_RIDER_CLEAR)


# true if p is walkable, the eight points `margin` metres round it are ground, and no trunk is within `margin` of
# the middle (a body is a disc of that radius: it stops that far from a wall and that far from a trunk's edge)
func _clear(p: Vector3, margin: float) -> bool:
	if not _ground_walkable(p) or _near_tree(p, margin + WorldDressScript.TRUNK_SOLID):
		return false
	for k in range(8):
		var a = TAU * float(k) / 8.0
		if not _ground_walkable(p + Vector3(cos(a), 0.0, sin(a)) * margin):
			return false
	return true


# keep a point on the walkable ground, sliding along an edge: a point that is free comes back unchanged, one
# in or against a wall comes back as the nearest free point (which is where pushing into a wall slides to)
func clamp_walk(p: Vector3, who: String = "player") -> Vector3:
	var margin: float = MARGINS.get(who, MARGINS["player"])
	if _clear(p, margin):
		return p
	# far outside the grid (a thrown pickup, a knock-back): first bring it to the edge of the grid
	var half = float(layout["cells"]) * float(layout["cell"]) / 2.0 - 0.5
	var at = Vector3(clampf(p.x, -half, half), p.y, clampf(p.z, -half, half))
	if _clear(at, margin):
		return at
	p = at
	# Search rings of growing radius for the nearest free point. Close to the point the rings are fine (a wall
	# edge is found to a quarter of a metre); a point deep inside a thick block at the edge may have to go
	# further, where the rings get coarser so the search stays cheap (it is rare, and only runs for such points).
	var reach = float(layout["cells"]) * float(layout["cell"]) * 1.5
	var home = start_position()
	var r = SLIDE_STEP
	while r <= reach:
		var step = SLIDE_STEP if r <= SLIDE_MAX else SLIDE_COARSE_STEP
		var n = maxi(8, int(ceil(TAU * r / step)))
		var best = Vector3.ZERO
		var best_d = INF
		for k in range(n):
			var a = TAU * float(k) / float(n)
			var q = Vector3(p.x + cos(a) * r, p.y, p.z + sin(a) * r)
			if _clear(q, margin):
				# on a ring every free point is as near as the next; take the one nearest the start so a
				# knock-back out of a wall ends up on the side the player can reach
				var d = Vector2(q.x - home.x, q.z - home.z).length()
				if d < best_d:
					best_d = d
					best = q
		if best_d < INF:
			return best
		r += step
	# nothing free anywhere in reach (not possible on a layout that passed validation): go to the start
	return home


# The player's step each frame. A step that stays on free ground is taken as it is. A step into a wall is
# split in x and z, the longer part first, and each part is cut back to the wall, so the player ends flush
# against the wall and keeps sliding along it at full speed. clamp_walk is not used for this: its search
# for the nearest free point pushes out in steps of a quarter of a metre and picks the point nearest the start
# of the arena, so a player hugging a wall was thrown out and pulled sideways and back every frame. The
# walls lie on the grid, so one of the two parts is always along the wall. clamp_walk stays for a body that
# starts inside a wall (a knock-back, a spawn), for bosses and for pickups.
func slide_walk(from: Vector3, to: Vector3, who: String = "player") -> Vector3:
	var margin: float = MARGINS.get(who, MARGINS["player"])
	if _clear(to, margin):
		return to
	if not _clear(from, margin):
		return clamp_walk(to, who)
	var dx = to.x - from.x
	var dz = to.z - from.z
	var p = from
	if absf(dx) >= absf(dz):
		p = _step_to_wall(p, Vector3(dx, 0.0, 0.0), margin)
		p = _step_to_wall(p, Vector3(0.0, 0.0, dz), margin)
	else:
		p = _step_to_wall(p, Vector3(0.0, 0.0, dz), margin)
		p = _step_to_wall(p, Vector3(dx, 0.0, 0.0), margin)
	p.y = to.y
	return p


# move p by `step` and stop at the wall: the whole step when it is free, otherwise the longest free part of it
func _step_to_wall(p: Vector3, step: Vector3, margin: float) -> Vector3:
	if step == Vector3.ZERO or _clear(p + step, margin):
		return p + step
	var free = 0.0
	var blocked = 1.0
	for i in range(WALL_HALVINGS):
		var mid = (free + blocked) * 0.5
		if _clear(p + step * mid, margin):
			free = mid
		else:
			blocked = mid
	return p + step * free


# true if a boss on foot at p is blocked: inside a building or a tunnel block, or outside the arena, or within
# TREE_RIDER_CLEAR of a trunk
func obstacle_at(p: Vector3) -> bool:
	return not _walkable(p)


# The nearest wall within `reach` metres of p (see Arena.wall_near): a building or tunnel block, or the edge of the grid.
# The walls lie on the grid, so looking along the four axes is enough; each hit is found to a few centimetres by halving.
func wall_near(p: Vector3, reach: float) -> Dictionary:
	if not _ground_walkable(p):
		return {}  # inside a wall (a knock-back that has not been pushed out yet): nothing to push off
	var best = {}
	var best_t = INF
	for d in [Vector3.RIGHT, Vector3.LEFT, Vector3.BACK, Vector3.FORWARD]:
		if _ground_walkable(p + d * reach):
			continue
		var free = 0.0
		var blocked = reach
		for _i in range(WALL_HALVINGS):
			var mid = (free + blocked) * 0.5
			if _ground_walkable(p + d * mid):
				free = mid
			else:
				blocked = mid
		if blocked < best_t:
			best_t = blocked
			best = {"normal": -d, "point": p + d * blocked, "dist": blocked}
	return best


# true if a dart at p is inside something solid: a building or a tunnel block, below the lowest roof
func ray_blocked(p: Vector3) -> bool:
	return p.y < SOLID_HEIGHT and not _ground_walkable(p)


# true if p is inside a gate's tunnel: on a tunnel cell, or past the outer wall in a gate's opening
func hidden_at(p: Vector3) -> bool:
	if surface_at(p) == "tunnel":
		return true
	if surface_at(p) != "building":
		return false
	for gate in _gates:
		var d: Vector3 = p - gate["pos"]
		var along = d.dot(gate["outward"])
		var across = absf(d.x * gate["outward"].z - d.z * gate["outward"].x)
		if along > 0.0 and across < gate["half_width"] and _outside(p):
			return true
	return false


# true if a rider at p cannot ride there: a building, but not through a gate (tunnel cells and the opening), or a
# trunk's neighbourhood (TREE_RIDER_CLEAR: wide enough that the riders' one-metre looks cannot slip past a trunk, and
# the same distance clamp_walk keeps a boss from it, so a rider pushed out of one is not inside it again)
func rider_blocked(p: Vector3) -> bool:
	var s = surface_at(p)
	if s == "building":
		return not hidden_at(p)
	return _near_tree(p, TREE_RIDER_CLEAR)


# true if p is outside the grid altogether
func _outside(p: Vector3) -> bool:
	var half = _half()
	return absf(p.x) >= half or absf(p.z) >= half


# ---------------------------------------------------------------- street-coordinate stubs
# Riders, bosses, pedestrians and the player still call the street-coordinate functions in places (the
# "Gameplay on open ground" items in the README move the rest to world positions). A generated arena has no
# street, so these answer as if street x and z were world x and z: the same mapping as the roundabout has at its
# middle (tangent along +x, inward along +z, no turn), always a point inside the arena, never an error. They are
# for code that has not moved yet; nothing should be built on them.
const FACADE_RHO = 0.0  # the roundabout's circle of facades (combat.gd reads it); a generated arena has none
const EDGE_LIM = 5.0  # metres in from the grid edge for lim(): clear of the 2-cell building ring and a metre more
const EDGE_PLAYER_LIM = 6.0  # ... and for player_lim(), a little further in, as on the roundabout


# street point (x, z) at height y -> the world point with the same x and z, kept inside the arena
func tw(x: float, z: float, y: float = 0.0) -> Vector3:
	var h = _half() - 0.5
	return Vector3(clampf(x, -h, h), y, clampf(z, -h, h))


# world position -> (x, z)
func to_track(p: Vector3) -> Vector2:
	return Vector2(p.x, p.z)


func tangent(_x: float) -> Vector3:
	return Vector3.RIGHT


func inward(_x: float) -> Vector3:
	return Vector3.BACK


func yaw(_x: float) -> float:
	return 0.0


# there is no tunnel along a street: nothing is hidden by street x (hidden_at looks at the real tunnels)
func hidden(_x: float) -> bool:
	return false


# a street metre is a world metre
func scale_at(_z: float) -> float:
	return 1.0


# `ahead` metres further along +x (or -x for dir -1) from p, kept on ground a boss can stand on
func lane_point(p: Vector3, dir: int, _z: float, ahead: float) -> Vector3:
	return clamp_walk(p + Vector3.RIGHT * float(dir) * ahead, "boss")


# metres to the nearest gate (0 when there are none), as the way out for a rider that gives up
func exit_distance(p: Vector3, _dir: int) -> float:
	var best = INF
	for gate in _gates:
		best = minf(best, Vector2(gate["pos"].x - p.x, gate["pos"].z - p.z).length())
	return best if best < INF else 0.0


func lim() -> float:
	return _half() - EDGE_LIM


func player_lim() -> float:
	return _half() - EDGE_PLAYER_LIM


# there is no road to be pulled back onto: keep the point on ground a boss can stand on
func clamp_road(p: Vector3, _z_near: float = 1.6, _z_far: float = -6.6) -> Vector3:
	return clamp_walk(p, "boss")


# there is no circle of facades: a ray never leaves one
func ray_exit_circle(_o: Vector3, _d: Vector3, _radius: float) -> float:
	return -1.0


# half the width of the grid, in metres
func _half() -> float:
	return float(layout["cells"]) * float(layout["cell"]) / 2.0
