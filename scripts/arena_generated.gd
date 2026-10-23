extends "res://scripts/arena.gd"
# A generated arena (README Milestone K): the Arena interface on top of a layout from arena_gen.gd. It is built
# in small steps; this file says in each section what is done. Everything here reads only the layout and the
# arena rules, so one seed gives one arena. Not used by the game yet (see docs/PROCEDURAL_ARENAS.md).

const ArenaGenScript = preload("res://scripts/arena_gen.gd")

var layout: Dictionary = {}
var rules: Dictionary = {}
var _gates: Array = []


func _init(the_layout: Dictionary = {}, the_rules: Dictionary = {}) -> void:
	layout = the_layout
	rules = the_rules if not the_rules.is_empty() else ArenaGenScript.load_rules()
	_gates = _world_gates()


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


# ---------------------------------------------------------------- the start and the gates
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


# ---------------------------------------------------------------- bounds and blocking
# Margins (metres) kept clear round a point so a body does not sink into a wall: the player, a boss (which
# may stand a little closer to the edge) and a pickup's landing spot (kept further in so it can be reached).
const MARGINS = {"player": 0.45, "boss": 0.3, "pickup": 1.0}
const SOLID_HEIGHT = 6.5  # metres: the lowest building or tunnel block; a dart above it is not stopped here
const SLIDE_STEP = 0.25  # metres between the rings searched for the nearest free point
const SLIDE_MAX = 8.0  # metres: out to here the search rings are fine (SLIDE_STEP apart)
const SLIDE_COARSE_STEP = 1.0  # metres between rings, and along them, beyond SLIDE_MAX


# true if the cell under p is ground someone on foot can stand on (not a building or a tunnel block)
func _walkable(p: Vector3) -> bool:
	var s = surface_at(p)
	return s != "building" and s != "tunnel"


# true if p is walkable and so are the eight points `margin` metres round it
func _clear(p: Vector3, margin: float) -> bool:
	if not _walkable(p):
		return false
	for k in range(8):
		var a = TAU * float(k) / 8.0
		if not _walkable(p + Vector3(cos(a), 0.0, sin(a)) * margin):
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


# true if a boss on foot at p is blocked: inside a building or a tunnel block, or outside the arena
func obstacle_at(p: Vector3) -> bool:
	return not _walkable(p)


# true if a dart at p is inside something solid: a building or a tunnel block, below the lowest roof
func ray_blocked(p: Vector3) -> bool:
	return p.y < SOLID_HEIGHT and not _walkable(p)


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


# true if a rider at p cannot ride there: a building, but not through a gate (tunnel cells and the opening)
func rider_blocked(p: Vector3) -> bool:
	var s = surface_at(p)
	if s == "building":
		return not hidden_at(p)
	return false


# true if p is outside the grid altogether
func _outside(p: Vector3) -> bool:
	var half = float(layout["cells"]) * float(layout["cell"]) / 2.0
	return absf(p.x) >= half or absf(p.z) >= half
