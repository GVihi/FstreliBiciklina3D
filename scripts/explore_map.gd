extends RefCounted
# What the player has found of the arena, for the pause-screen map (README Milestone K, "Exploration and
# extraction").
#
#   Layout      A cell of the arena grid is "seen" once the player has been within REVEAL_RADIUS metres of its
#               centre. Nothing is shown on the map that the player has not been near.
#   Spots       A supply cache or the extraction point is "found" the first time the player comes within the
#               objectives' SENSE_RANGE of it (the same range at which it shows on the radar), so exploring is
#               rewarded and the map never gives a spot away. A taken cache is found by definition.
#   Gates       A gate is shown once the cell it stands in has been seen. The start is always shown: the round
#               begins there.
#
# One round at a time, like `objective.gd`: `setup_round()` (after the objectives are built) starts with only the
# area round the start seen, `clear()` forgets everything. The roundabout has no layout and no map
# (`enabled()` is false there). Drawing is in `hud.gd` (`_draw_pause_map`).

const REVEAL_RADIUS = 26.0  # metres of ground round the player that count as explored
const GROUND_COLORS = {
	"g": Color("#7FB069"),
	"p": Color("#E3D3A1"),
	"s": Color("#BDBDB5"),
	"r": Color("#3E4147"),
	"b": Color("#8A6F63"),
	"t": Color("#E8A21F"),
}

var g = null
var n = 0  # cells along one side of the grid
var cell = 0.0  # metres per cell
var seen: PackedByteArray = PackedByteArray()  # 1 where the cell has been seen, index x + z * n
var seen_count = 0
var goal_found = false
var cache_found: Array = []  # one bool per cache of `objective_sys.caches`, in the same order
var _last_cell = Vector2i(-1000, -1000)


func _init(game) -> void:
	g = game


# true on an arena that has a layout to draw (the generated arena)
func enabled() -> bool:
	return g != null and g.arena != null and "layout" in g.arena and not g.arena.layout.is_empty()


func layout() -> Dictionary:
	if enabled():
		return g.arena.layout
	return {}


# Start a round: only the ground round the start is seen, and nothing is found yet.
func setup_round() -> void:
	clear()
	if not enabled():
		return
	var lay = layout()
	n = int(lay["cells"])
	cell = float(lay["cell"])
	seen = PackedByteArray()
	seen.resize(n * n)
	seen.fill(0)
	cache_found.clear()
	for _c in g.objective_sys.caches:
		cache_found.append(false)
	_reveal_around(g.arena.start_position())
	_last_cell = cell_of(g.arena.start_position())


func clear() -> void:
	n = 0
	cell = 0.0
	seen = PackedByteArray()
	seen_count = 0
	goal_found = false
	cache_found.clear()
	_last_cell = Vector2i(-1000, -1000)


# the cell (x, z) that holds world point p, clamped onto the grid
func cell_of(p: Vector3) -> Vector2i:
	if n <= 0:
		return Vector2i(0, 0)
	return Vector2i(
		clampi(int(floor(p.x / cell + float(n) / 2.0)), 0, n - 1),
		clampi(int(floor(p.z / cell + float(n) / 2.0)), 0, n - 1)
	)


func cell_seen(cx: int, cz: int) -> bool:
	if n <= 0 or cx < 0 or cz < 0 or cx >= n or cz >= n:
		return false
	return seen[cz * n + cx] == 1


# the share of the grid that is seen, 0 to 1
func explored_fraction() -> float:
	if n <= 0:
		return 0.0
	return float(seen_count) / float(n * n)


func gate_seen(gate: Dictionary) -> bool:
	var c = cell_of(gate["pos"])
	return cell_seen(c.x, c.y)


func update(_dt: float) -> void:
	if n <= 0 or g.player == null:
		return
	var p: Vector3 = g.player.position
	var c = cell_of(p)
	if c != _last_cell:  # the ring of cells only changes when the player steps into another cell
		_last_cell = c
		_reveal_around(p)
	var o = g.objective_sys
	if not goal_found and o.has_goal() and o.dist_to(o.goal["pos"]) < o.SENSE_RANGE:
		goal_found = true
	for i in range(mini(cache_found.size(), o.caches.size())):
		var cache: Dictionary = o.caches[i]
		if cache_found[i]:
			continue
		if cache["taken"] or o.dist_to(cache["pos"]) < o.SENSE_RANGE:
			cache_found[i] = true


func _reveal_around(p: Vector3) -> void:
	var reach = int(ceil(REVEAL_RADIUS / cell))
	var c = cell_of(p)
	for cz in range(maxi(0, c.y - reach), mini(n, c.y + reach + 1)):
		for cx in range(maxi(0, c.x - reach), mini(n, c.x + reach + 1)):
			var wx = (float(cx) + 0.5 - float(n) / 2.0) * cell
			var wz = (float(cz) + 0.5 - float(n) / 2.0) * cell
			if Vector2(wx - p.x, wz - p.z).length() > REVEAL_RADIUS:
				continue
			var i = cz * n + cx
			if seen[i] == 0:
				seen[i] = 1
				seen_count += 1
