extends RefCounted
# Procedural arena layout (README Milestone K, "Generation"). One seed gives one layout: generate() uses only
# the run seed and the numbers in data/arena_rules.json, and draws from generators seeded by
# DailyScript.stream_seed, never from the global random functions. What the numbers mean and how a layout is
# built: docs/PROCEDURAL_ARENAS.md.
#
# A layout is a square grid of cells (cell metres wide), centred on the world origin, x to the east and z to
# the south. It is plain data (strings, numbers, arrays), so it can be compared, saved and printed:
#   "rows":      Array of `cells` Strings, one per z, each `cells` characters, one per x. The characters are
#                the keys of LEGEND: g grass, p plaza, s sidewalk, r road, b building, t tunnel.
#   "nav":       Array of `cells` Strings like "rows", the navigation grid: '#' where nothing can go (building),
#                otherwise a digit 1 to 9, the clearance: how many cells away the nearest building is, counting
#                diagonals (1 = touching one, so a rider there has no room to swing), capped at nav.max_clearance
#   "roads":     [{"dir": "ns" or "ew", "centre": cell index across the road}] (ns roads run north to south)
#   "plazas":    [{"x", "z", "w", "h", "start": bool}] in cells; the first one holds the start area
#   "buildings": [{"x", "z", "w", "h"}] block rectangles in cells (the border ring is not listed)
#   "gates":     [{"side": "n", "s", "w" or "e", "lo", "hi" (cells along that side), "pos": [x, z] (metres,
#                centre of the tunnel block), "outward": [x, z] (unit vector), "half_width": metres}]
#   "start":     {"cell": [cx, cz], "pos": [x, z], "half": cells} a clear (2 * half + 1) square of plaza
#   "walkable_m2": ground a player or rider can stand on (everything but buildings and tunnels)
#   "style":     the arena style the seed picked ("plaza", "canyon", "market", "park"; "" when the rules have no
#                styles), see "styles" in data/arena_rules.json
#   "dress":     how world_dress.gd dresses this style: {"h_base", "h_steps", "h_step" (building heights) and
#                "tree_every"}; empty when the style gives none
# Nothing in a layout reads the scene or the global random state.

const DailyScript = preload("res://scripts/daily.gd")

const PATH = "res://data/arena_rules.json"
const LEGEND = {
	"g": "grass", "p": "plaza", "s": "sidewalk", "r": "road", "b": "building", "t": "tunnel"
}
const G = 103  # "g"
const P = 112  # "p"
const S = 115  # "s"
const R = 114  # "r"
const B = 98  # "b"
const T = 116  # "t"
const SIDES = {
	"n": Vector2(0.0, -1.0), "s": Vector2(0.0, 1.0), "w": Vector2(-1.0, 0.0), "e": Vector2(1.0, 0.0)
}


# Reads data/arena_rules.json; returns {} (and logs why) when it is missing or unusable.
static func load_rules() -> Dictionary:
	if not FileAccess.file_exists(PATH):
		push_error("arena: %s is missing. Check the export include filter (data/*.json)." % PATH)
		return {}
	var data = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if typeof(data) != TYPE_DICTIONARY:
		push_error("arena: %s is not valid JSON, expected an object" % PATH)
		return {}
	for key in ["cell", "cells", "border", "road", "gates", "start", "plazas", "buildings"]:
		if not data.has(key):
			push_error('arena: %s has no "%s"' % [PATH, key])
			return {}
	return data


# Builds the layout for a run seed. Pass `rules` to test other numbers; by default the shipped file is used.
# An attempt that cannot place the start plaza or ends up with too little or too much ground is thrown away
# and the next one draws from streams seeded with the attempt number (DailyScript.stream_seed(seed, attempt,
# name)), so the seed still gives exactly one layout. Returns {} (and logs why) if every attempt fails.
static func generate(run_seed: int, rules: Dictionary = {}) -> Dictionary:
	if rules.is_empty():
		rules = load_rules()
	if rules.is_empty():
		return {}
	var tries = int(rules.get("max_attempts", 8))
	# the style belongs to the seed, not to the attempt: a retry changes the layout, never the style
	var style = pick_style(run_seed, rules)
	var style_rules = rules_for_style(rules, style)
	var dress = {}
	if style != "":
		dress = rules["styles"][style].get("dress", {}).duplicate(true)
	for attempt in range(tries):
		var layout = _attempt(run_seed, attempt, style_rules)
		if not layout.is_empty():
			layout["style"] = style
			layout["dress"] = dress
			return layout
	push_error("arena: seed %08X gave no usable layout in %d attempts" % [run_seed, tries])
	return {}


# The names of the styles in the rules, in a fixed (sorted) order; empty when the rules have none.
static func style_names(rules: Dictionary) -> Array:
	var names = rules.get("styles", {}).keys()
	names.sort()
	return names


# The style a run seed gets: drawn from its own stream (attempt 0), by the "weight" of each style. "" when the
# rules have no styles, which gives the plain numbers of the rules.
static func pick_style(run_seed: int, rules: Dictionary) -> String:
	var names = style_names(rules)
	if names.is_empty():
		return ""
	var styles = rules["styles"]
	var total = 0.0
	for name in names:
		total += maxf(0.0, float(styles[name].get("weight", 1.0)))
	var rng = _rng(run_seed, 0, str(rules.get("streams", {}).get("style", "arena_style")))
	var roll = rng.randf() * total
	for name in names:
		roll -= maxf(0.0, float(styles[name].get("weight", 1.0)))
		if roll < 0.0:
			return str(name)
	return str(names[names.size() - 1])


# The rules with the numbers of a style laid over them: every key a style names replaces the key in the
# rules, dictionaries are merged key by key (so a style can change only road["vertical"]). The "styles" table
# itself is left out of the result. A style that is not in the rules ("" too) gives the rules as they are.
static func rules_for_style(rules: Dictionary, style: String) -> Dictionary:
	var styles = rules.get("styles", {})
	if style == "" or not styles.has(style):
		return rules
	var out = _merged(rules, styles[style].get("rules", {}))
	out.erase("styles")
	return out


static func _merged(base: Dictionary, over: Dictionary) -> Dictionary:
	var out = base.duplicate(true)
	for key in over:
		if (
			out.has(key)
			and typeof(out[key]) == TYPE_DICTIONARY
			and typeof(over[key]) == TYPE_DICTIONARY
		):
			out[key] = _merged(out[key], over[key])
		else:
			out[key] = over[key]
	return out


static func _rng(run_seed: int, attempt: int, part: String) -> RandomNumberGenerator:
	var rng = RandomNumberGenerator.new()
	rng.seed = DailyScript.stream_seed(run_seed, attempt, part)
	return rng


static func _attempt(run_seed: int, attempt: int, rules: Dictionary) -> Dictionary:
	var streams = rules.get("streams", {})
	var road_rng = _rng(run_seed, attempt, str(streams.get("roads", "arena_roads")))
	var plaza_rng = _rng(run_seed, attempt, str(streams.get("plazas", "arena_plazas")))
	var block_rng = _rng(run_seed, attempt, str(streams.get("blocks", "arena_blocks")))
	var n = int(rules["cells"])
	var border = int(rules["border"])
	var grid = PackedByteArray()
	grid.resize(n * n)
	grid.fill(G)
	var roads = _place_roads(grid, n, rules, road_rng)
	var gates = _place_gates(grid, n, roads, rules, road_rng)
	var plazas = []
	var start_plaza = _place_plaza(
		grid, n, border, rules["start"], plaza_rng, "plaza_min", "plaza_max"
	)
	if start_plaza.is_empty():
		return {}
	start_plaza["start"] = true
	plazas.append(start_plaza)
	var more = rules["plazas"]
	var extra = plaza_rng.randi_range(int(more["extra_min"]), int(more["extra_max"]))
	for _i in range(extra):
		var plaza = _place_plaza(grid, n, border, more, plaza_rng, "size_min", "size_max")
		if not plaza.is_empty():
			plaza["start"] = false
			plazas.append(plaza)
	var buildings = _place_buildings(grid, n, border, rules["buildings"], block_rng)
	var cell = float(rules["cell"])
	var walkable = 0
	for c in grid:
		if c == G or c == P or c == S or c == R:
			walkable += 1
	var area = float(walkable) * cell * cell
	var limits = rules.get("walkable_m2", {})
	if area < float(limits.get("min", 0.0)) or area > float(limits.get("max", 1.0e12)):
		return {}
	var rows = []
	for z in range(n):
		rows.append(grid.slice(z * n, (z + 1) * n).get_string_from_ascii())
	var half = int(rules["start"]["half"])
	var sc = Vector2i(
		int(start_plaza["x"]) + int(start_plaza["w"]) / 2,
		int(start_plaza["z"]) + int(start_plaza["h"]) / 2
	)
	var sp = _world(n, cell, sc.x + 0.5, sc.y + 0.5)
	var layout = {
		"version": int(rules.get("version", 1)),
		"seed": run_seed,
		"attempt": attempt,
		"cell": cell,
		"cells": n,
		"border": border,
		"rows": rows,
		"nav": _nav_rows(grid, n, int(rules.get("nav", {}).get("max_clearance", 9))),
		"roads": roads,
		"plazas": plazas,
		"buildings": buildings,
		"gates": gates,
		"start": {"cell": [sc.x, sc.y], "pos": [sp.x, sp.y], "half": half},
		"walkable_m2": int(round(area)),
	}
	# a layout that breaks the validation rules is thrown away like one with the wrong amount of ground
	if rules.has("validate") and not validate(layout, rules).is_empty():
		return {}
	return layout


# world metres (x, z) of a point given in cell units (a cell centre is index + 0.5)
static func _world(n: int, cell: float, cx: float, cz: float) -> Vector2:
	return Vector2((cx - float(n) / 2.0) * cell, (cz - float(n) / 2.0) * cell)


static func _place_roads(
	grid: PackedByteArray, n: int, rules: Dictionary, rng: RandomNumberGenerator
) -> Array:
	var road = rules["road"]
	var border = int(rules["border"])
	var rw = int(road["width"])
	var sw = int(road["sidewalk"])
	var lo = border + int(road["margin"])
	var hi = n - 1 - border - int(road["margin"])
	var gap = int(road["min_gap"])
	var n_ns = rng.randi_range(int(road["vertical"]["min"]), int(road["vertical"]["max"]))
	var n_ew = rng.randi_range(int(road["horizontal"]["min"]), int(road["horizontal"]["max"]))
	var roads = []
	for c in _pick_centres(n_ns, lo, hi, gap, rng):
		roads.append({"dir": "ns", "centre": c})
	for c in _pick_centres(n_ew, lo, hi, gap, rng):
		roads.append({"dir": "ew", "centre": c})
	# sidewalks first, then the roads over them, so a crossing is all road
	for pass_n in range(2):
		for rd in roads:
			var reach = rw / 2 + sw if pass_n == 0 else rw / 2
			for along in range(n):
				for d in range(-reach, reach + 1):
					var x = int(rd["centre"]) + d if rd["dir"] == "ns" else along
					var z = along if rd["dir"] == "ns" else int(rd["centre"]) + d
					grid[z * n + x] = S if pass_n == 0 else R
	return roads


# up to `count` road centres in lo..hi, at least `gap` cells apart, drawn in order and returned sorted
static func _pick_centres(
	count: int, lo: int, hi: int, gap: int, rng: RandomNumberGenerator
) -> Array:
	var out = []
	for _try in range(40):
		if out.size() >= count:
			break
		var c = rng.randi_range(lo, hi)
		var ok = true
		for o in out:
			if absi(int(o) - c) < gap:
				ok = false
		if ok:
			out.append(c)
	out.sort()
	return out


# every road end is a candidate gate; some are opened as tunnels through the border ring and the rest are
# walled off. The border ring becomes building everywhere else.
static func _place_gates(
	grid: PackedByteArray, n: int, roads: Array, rules: Dictionary, rng: RandomNumberGenerator
) -> Array:
	var border = int(rules["border"])
	var depth = mini(int(rules["gates"]["depth"]), border)
	var rw = int(rules["road"]["width"])
	var cell = float(rules["cell"])
	var ends = []
	for rd in roads:
		var c = int(rd["centre"])
		for side in ["n", "s"] if rd["dir"] == "ns" else ["w", "e"]:
			ends.append({"side": side, "lo": c - rw / 2, "hi": c + rw / 2})
	DailyScript.shuffle_with(ends, rng)
	var want = rng.randi_range(int(rules["gates"]["min"]), int(rules["gates"]["max"]))
	var gates = []
	for i in range(mini(want, ends.size())):
		gates.append(ends[i])
	for z in range(n):
		for x in range(n):
			if x < border or z < border or x >= n - border or z >= n - border:
				grid[z * n + x] = B
	for gt in gates:
		for k in range(int(gt["lo"]), int(gt["hi"]) + 1):
			for d in range(depth):
				var side = str(gt["side"])
				var x = k if side == "n" or side == "s" else (d if side == "w" else n - 1 - d)
				var z = k if side == "w" or side == "e" else (d if side == "n" else n - 1 - d)
				grid[z * n + x] = T
		var mid = float(int(gt["lo"]) + int(gt["hi"]) + 1) / 2.0
		var out_v: Vector2 = SIDES[gt["side"]]
		var at = Vector2(mid, float(depth) / 2.0)  # cells: along the side, depth from the outer edge
		var pos = Vector2.ZERO
		match str(gt["side"]):
			"n":
				pos = _world(n, cell, mid, at.y)
			"s":
				pos = _world(n, cell, mid, float(n) - at.y)
			"w":
				pos = _world(n, cell, at.y, mid)
			_:
				pos = _world(n, cell, float(n) - at.y, mid)
		gt["pos"] = [pos.x, pos.y]
		gt["outward"] = [out_v.x, out_v.y]
		gt["half_width"] = float(rw) * cell / 2.0
	return gates


# a plaza rectangle on grass only, drawn from the given size keys (in cells); {} if nothing fits in 80 tries
static func _place_plaza(
	grid: PackedByteArray,
	n: int,
	border: int,
	sizes: Dictionary,
	rng: RandomNumberGenerator,
	key_min: String,
	key_max: String
) -> Dictionary:
	var w = rng.randi_range(int(sizes[key_min]), int(sizes[key_max]))
	var h = rng.randi_range(int(sizes[key_min]), int(sizes[key_max]))
	for _try in range(80):
		var x0 = rng.randi_range(border, n - border - w)
		var z0 = rng.randi_range(border, n - border - h)
		if _all_grass(grid, n, border, x0, z0, w, h, false):
			_fill(grid, n, x0, z0, w, h, P)
			return {"x": x0, "z": z0, "w": w, "h": h}
	return {}


static func _place_buildings(
	grid: PackedByteArray, n: int, border: int, rules: Dictionary, rng: RandomNumberGenerator
) -> Array:
	var out = []
	var clearance = int(rules["clearance"])
	var inner = float((n - 2 * border) * (n - 2 * border))
	var used = 0
	for _try in range(int(rules["tries"])):
		var w = rng.randi_range(int(rules["size_min"]), int(rules["size_max"]))
		var h = rng.randi_range(int(rules["size_min"]), int(rules["size_max"]))
		var x0 = rng.randi_range(border, n - border - w)
		var z0 = rng.randi_range(border, n - border - h)
		if (
			_all_grass(
				grid,
				n,
				border,
				x0 - clearance,
				z0 - clearance,
				w + 2 * clearance,
				h + 2 * clearance,
				true
			)
			and float(used + w * h) / inner <= float(rules["max_share"])
		):
			_fill(grid, n, x0, z0, w, h, B)
			used += w * h
			out.append({"x": x0, "z": z0, "w": w, "h": h})
	return out


# true if every cell of the rectangle is grass (or, with allow_border, border-ring building)
static func _all_grass(
	grid: PackedByteArray, n: int, border: int, x0: int, z0: int, w: int, h: int, allow_border: bool
) -> bool:
	for z in range(z0, z0 + h):
		for x in range(x0, x0 + w):
			if x < 0 or z < 0 or x >= n or z >= n:
				return false
			var c = grid[z * n + x]
			if c == G:
				continue
			var in_ring = x < border or z < border or x >= n - border or z >= n - border
			if not (allow_border and c == B and in_ring):
				return false
	return true


static func _fill(grid: PackedByteArray, n: int, x0: int, z0: int, w: int, h: int, c: int) -> void:
	for z in range(z0, z0 + h):
		for x in range(x0, x0 + w):
			grid[z * n + x] = c


# The navigation grid: for every cell that is not a building, the distance in cells (8 directions, so a
# square distance) to the nearest building cell, capped at `cap`. Tunnel cells count as open ground. Cells
# are found by a breadth-first search from all the buildings at once, which is exact for this distance.
static func _nav_rows(grid: PackedByteArray, n: int, cap: int) -> Array:
	var dist = PackedInt32Array()
	dist.resize(n * n)
	dist.fill(-1)
	var queue = []
	for i in range(n * n):
		if grid[i] == B:
			dist[i] = 0
			queue.append(i)
	var head = 0
	while head < queue.size():
		var i = int(queue[head])
		head += 1
		var x = i % n
		var z = i / n
		for dz in range(-1, 2):
			for dx in range(-1, 2):
				var nx = x + dx
				var nz = z + dz
				if nx < 0 or nz < 0 or nx >= n or nz >= n:
					continue
				var j = nz * n + nx
				if dist[j] < 0:
					dist[j] = dist[i] + 1
					queue.append(j)
	var rows = []
	for z in range(n):
		var line = ""
		for x in range(n):
			var d = dist[z * n + x]
			line += "#" if d == 0 else str(clampi(d, 1, cap))
		rows.append(line)
	return rows


# ---------------------------------------------------------------- validation
# The rules a layout has to satisfy before the game may use it (README Milestone K, "Validate every generated
# arena"); numbers in rules["validate"]. Returns a list of problems in words, empty when the layout is fine.
# generate() throws a layout away (and tries the next attempt) when this finds any problem. It reads only
# the layout, so it also works on a layout made or damaged by hand.
#   - the start area is a clear square of plaza with room round it (the start rule in the rules)
#   - no sealed areas: every cell that is not a building can be reached from the start on foot
#   - every gate can be reached from the start along corridors at least `min_clear` cells clear of buildings
#     on every side (clearance 2 is a corridor three cells, 6 m, wide), so riders can always get in
#   - sightlines: from the start, at least `min_view` of the open ground within `view_radius` cells is in
#     plain view (no building in the way), so the player sees what is coming
static func validate(layout: Dictionary, rules: Dictionary) -> Array:
	var problems = []
	var vr = rules.get("validate", {})
	var n = int(layout["cells"])
	var cell = float(layout["cell"])
	var sx = int(layout["start"]["cell"][0])
	var sz = int(layout["start"]["cell"][1])
	var half = int(layout["start"]["half"])
	for z in range(sz - half, sz + half + 1):
		for x in range(sx - half, sx + half + 1):
			if x < 0 or z < 0 or x >= n or z >= n or str(layout["rows"][z])[x] != "p":
				problems.append("the start area is not all plaza at %d,%d" % [x, z])
				return problems
	if nav_clearance(layout, sx, sz) < half + 1:
		problems.append("the start cell has no room round it")
	var seen = _reach(layout, sx, sz, 1)
	var open_cells = 0
	var reached = 0
	for i in range(n * n):
		if nav_clearance(layout, i % n, i / n) > 0:
			open_cells += 1
			if seen[i] == 1:
				reached += 1
	if reached != open_cells:
		problems.append("%d open cells cannot be reached from the start" % (open_cells - reached))
	var wide = _reach(layout, sx, sz, int(vr.get("min_clear", 2)))
	for gt in layout["gates"]:
		var gx = int(float(gt["pos"][0]) / cell + float(n) / 2.0)
		var gz = int(float(gt["pos"][1]) / cell + float(n) / 2.0)
		if gx < 0 or gz < 0 or gx >= n or gz >= n or wide[gz * n + gx] != 1:
			problems.append("gate %s cannot be reached through wide enough corridors" % gt["side"])
	var share = view_share(layout, sx, sz, int(vr.get("view_radius", 20)))
	if share < float(vr.get("min_view", 0.0)):
		problems.append("only %d%% of the ground near the start is in view" % int(share * 100.0))
	return problems


# flood fill on foot (4 directions) from grid cell (sx, sz) over cells with clearance >= min_clear; returns
# a PackedByteArray with 1 for every cell reached
static func _reach(layout: Dictionary, sx: int, sz: int, min_clear: int) -> PackedByteArray:
	var n = int(layout["cells"])
	var seen = PackedByteArray()
	seen.resize(n * n)
	if nav_clearance(layout, sx, sz) < min_clear:
		return seen
	seen[sz * n + sx] = 1
	var queue = [sz * n + sx]
	var head = 0
	while head < queue.size():
		var i = int(queue[head])
		head += 1
		var x = i % n
		var z = i / n
		for step in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nx = x + step.x
			var nz = z + step.y
			if nx < 0 or nz < 0 or nx >= n or nz >= n or seen[nz * n + nx] == 1:
				continue
			if nav_clearance(layout, nx, nz) >= min_clear:
				seen[nz * n + nx] = 1
				queue.append(nz * n + nx)
	return seen


# the share (0 to 1) of open cells within `radius` cells of grid cell (sx, sz) that can be seen from it: a
# straight line between the cell centres crosses no building
static func view_share(layout: Dictionary, sx: int, sz: int, radius: int) -> float:
	var n = int(layout["cells"])
	var open_cells = 0
	var visible = 0
	for z in range(maxi(0, sz - radius), mini(n, sz + radius + 1)):
		for x in range(maxi(0, sx - radius), mini(n, sx + radius + 1)):
			if (x - sx) * (x - sx) + (z - sz) * (z - sz) > radius * radius:
				continue
			if nav_clearance(layout, x, z) == 0:
				continue
			open_cells += 1
			if _line_clear(layout, sx, sz, x, z):
				visible += 1
	return float(visible) / float(maxi(1, open_cells))


# true if no building cell lies on the straight line from cell (x0, z0) to cell (x1, z1) (Bresenham)
static func _line_clear(layout: Dictionary, x0: int, z0: int, x1: int, z1: int) -> bool:
	var dx = absi(x1 - x0)
	var dz = absi(z1 - z0)
	var sx = 1 if x1 > x0 else -1
	var sz = 1 if z1 > z0 else -1
	var err = dx - dz
	var x = x0
	var z = z0
	while x != x1 or z != z1:
		if nav_clearance(layout, x, z) == 0:
			return false
		var e2 = 2 * err
		if e2 > -dz:
			err -= dz
			x += sx
		if e2 < dx:
			err += dx
			z += sz
	return true


# ---------------------------------------------------------------- reading a layout
# the surface name at world metres (x, z); anything outside the grid counts as "building"
static func surface_at(layout: Dictionary, x: float, z: float) -> String:
	var n = int(layout["cells"])
	var cell = float(layout["cell"])
	var cx = int(floor(x / cell + float(n) / 2.0))
	var cz = int(floor(z / cell + float(n) / 2.0))
	if cx < 0 or cz < 0 or cx >= n or cz >= n:
		return "building"
	return LEGEND[str(layout["rows"][cz])[cx]]


# how fast a rider goes on the ground at world metres (x, z), as a share of its speed on the road (0 where
# nothing can ride). `rules` is the arena rules, "rider_speed" the table.
static func rider_speed_at(layout: Dictionary, rules: Dictionary, x: float, z: float) -> float:
	return float(rules["rider_speed"].get(surface_at(layout, x, z), 0.0))


# clearance of grid cell (cx, cz) from the navigation grid: 0 for a building or anything outside the grid,
# else 1 or more (see "nav" above)
static func nav_clearance(layout: Dictionary, cx: int, cz: int) -> int:
	var n = int(layout["cells"])
	if cx < 0 or cz < 0 or cx >= n or cz >= n:
		return 0
	var c = str(layout["nav"][cz])[cx]
	return 0 if c == "#" else int(c)


# what it costs to cross grid cell (cx, cz) for a rider: 1 / its speed share on that ground, so a path
# search that minimises the sum finds the quickest way. INF where nothing can ride (a building).
static func nav_cost(layout: Dictionary, rules: Dictionary, cx: int, cz: int) -> float:
	var n = int(layout["cells"])
	if nav_clearance(layout, cx, cz) == 0:
		return INF
	var share = float(rules["rider_speed"].get(LEGEND[str(layout["rows"][cz])[cx]], 0.0))
	return 1.0 / share if share > 0.0 else INF


# the layout as text, one line per row of cells: the LEGEND characters, north at the top
static func to_text(layout: Dictionary) -> String:
	return "\n".join(layout["rows"])
