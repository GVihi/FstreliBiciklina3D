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
#   "roads":     [{"dir": "ns" or "ew", "centre": cell index across the road}] (ns roads run north to south)
#   "plazas":    [{"x", "z", "w", "h", "start": bool}] in cells; the first one holds the start area
#   "buildings": [{"x", "z", "w", "h"}] block rectangles in cells (the border ring is not listed)
#   "gates":     [{"side": "n", "s", "w" or "e", "lo", "hi" (cells along that side), "pos": [x, z] (metres,
#                centre of the tunnel block), "outward": [x, z] (unit vector), "half_width": metres}]
#   "start":     {"cell": [cx, cz], "pos": [x, z], "half": cells} a clear (2 * half + 1) square of plaza
#   "walkable_m2": ground a player or rider can stand on (everything but buildings and tunnels)
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
	for attempt in range(tries):
		var layout = _attempt(run_seed, attempt, rules)
		if not layout.is_empty():
			return layout
	push_error("arena: seed %08X gave no usable layout in %d attempts" % [run_seed, tries])
	return {}


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
	return {
		"version": int(rules.get("version", 1)),
		"seed": run_seed,
		"attempt": attempt,
		"cell": cell,
		"cells": n,
		"border": border,
		"rows": rows,
		"roads": roads,
		"plazas": plazas,
		"buildings": buildings,
		"gates": gates,
		"start": {"cell": [sc.x, sc.y], "pos": [sp.x, sp.y], "half": half},
		"walkable_m2": int(round(area)),
	}


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


# the layout as text, one line per row of cells: the LEGEND characters, north at the top
static func to_text(layout: Dictionary) -> String:
	return "\n".join(layout["rows"])
