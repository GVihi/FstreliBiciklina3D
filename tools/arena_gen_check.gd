extends SceneTree
# Checks the arena layout generator (scripts/arena_gen.gd) against data/arena_rules.json.
# Run from the project folder:
#   godot --headless --path . --script res://tools/arena_gen_check.gd
# Optional arguments after "--": a seed to print as text, and how many seeds to check (default 2000), e.g.
#   godot --headless --path . --script res://tools/arena_gen_check.gd -- 3735928559 500
# It generates every seed twice (the same seed must give the same layout), checks that different seeds give
# different layouts, and checks each layout: grid shape, border ring, gates, start area, buildings, ground
# area, and that surface_at and the rider speed table agree with the grid.
# Exits with status 1 and lists the first problems when a check fails.

const ArenaGen = preload("res://scripts/arena_gen.gd")

var problems = []


func _init() -> void:
	var show_seed = -1
	var count = 2000
	var args = OS.get_cmdline_user_args()
	if args.size() > 0:
		show_seed = int(args[0])
	if args.size() > 1:
		count = int(args[1])
	var rules = ArenaGen.load_rules()
	if rules.is_empty():
		quit(1)
		return
	if show_seed >= 0:
		var shown = ArenaGen.generate(show_seed, rules)
		print(ArenaGen.to_text(shown))
		print(
			(
				"walkable %d m2, %d gates, attempt %d"
				% [shown["walkable_m2"], shown["gates"].size(), shown["attempt"]]
			)
		)
	var seen = {}
	var retried = 0
	var area_min = 1 << 30
	var area_max = 0
	var area_sum = 0
	for k in range(count):
		var seed_value = (k * 2654435761 + 12345) & 0xFFFFFFFF
		var layout = ArenaGen.generate(seed_value, rules)
		var again = ArenaGen.generate(seed_value, rules)
		if JSON.stringify(layout) != JSON.stringify(again):
			_fail(seed_value, "the same seed gave two different layouts")
		if layout.is_empty():
			_fail(seed_value, "no layout was generated")
		else:
			_check_layout(seed_value, layout, rules)
			seen[hash(ArenaGen.to_text(layout))] = true
			retried += 1 if int(layout["attempt"]) > 0 else 0
			area_min = mini(area_min, int(layout["walkable_m2"]))
			area_max = maxi(area_max, int(layout["walkable_m2"]))
			area_sum += int(layout["walkable_m2"])
		if problems.size() >= 20:
			break
	if seen.size() < int(0.98 * float(count)) and problems.is_empty():
		_fail(0, "only %d different layouts from %d seeds" % [seen.size(), count])
	_check_speeds(rules)
	_check_validation(rules)
	if problems.is_empty():
		print(
			(
				"arena_gen_check: %d seeds, every layout repeats exactly and follows the rules (%d different, %d needed a retry, ground %d to %d m2, mean %d)"
				% [count, seen.size(), retried, area_min, area_max, area_sum / maxi(1, count)]
			)
		)
		quit(0)
	else:
		for p in problems:
			printerr(p)
		quit(1)


func _fail(seed_value: int, text: String) -> void:
	problems.append("seed %08X: %s" % [seed_value, text])


func _cell(layout: Dictionary, x: int, z: int) -> String:
	return str(layout["rows"][z])[x]


func _check_layout(sv: int, layout: Dictionary, rules: Dictionary) -> void:
	var n = int(rules["cells"])
	var border = int(rules["border"])
	var rows = layout["rows"]
	if rows.size() != n:
		_fail(sv, "%d rows, expected %d" % [rows.size(), n])
		return
	var ground = 0
	for z in range(n):
		if str(rows[z]).length() != n:
			_fail(sv, "row %d has %d cells, expected %d" % [z, str(rows[z]).length(), n])
			return
		for x in range(n):
			var c = _cell(layout, x, z)
			if not ArenaGen.LEGEND.has(c):
				_fail(sv, "cell %d,%d is '%s', not a surface" % [x, z, c])
				return
			var ring = x < border or z < border or x >= n - border or z >= n - border
			if ring and c != "b" and c != "t":
				_fail(
					sv,
					"border cell %d,%d is '%s', only building and tunnel belong there" % [x, z, c]
				)
			if c == "t" and not ring:
				_fail(sv, "tunnel cell %d,%d is not in the border ring" % [x, z])
			if c != "b" and c != "t":
				ground += 1
	var area = float(ground) * float(rules["cell"]) * float(rules["cell"])
	if int(round(area)) != int(layout["walkable_m2"]):
		_fail(
			sv, "walkable_m2 says %d, the grid has %d" % [layout["walkable_m2"], int(round(area))]
		)
	var limits = rules["walkable_m2"]
	if area < float(limits["min"]) or area > float(limits["max"]):
		_fail(sv, "ground is %d m2, allowed %s to %s" % [int(area), limits["min"], limits["max"]])
	_check_gates(sv, layout, rules)
	_check_start(sv, layout, rules)
	_check_nav(sv, layout, rules)
	for b in layout["buildings"]:
		for z in range(int(b["z"]), int(b["z"]) + int(b["h"])):
			for x in range(int(b["x"]), int(b["x"]) + int(b["w"])):
				if _cell(layout, x, z) != "b":
					_fail(
						sv,
						(
							"building at %d,%d is not all building (%d,%d is '%s')"
							% [b["x"], b["z"], x, z, _cell(layout, x, z)]
						)
					)
					return
	for rd in layout["roads"]:
		var c = int(rd["centre"])
		for along in range(border, n - border):
			var ch = _cell(layout, c, along) if rd["dir"] == "ns" else _cell(layout, along, c)
			if ch != "r":
				_fail(sv, "%s road at %d is '%s' where it should be road" % [rd["dir"], c, ch])
				return


func _check_gates(sv: int, layout: Dictionary, rules: Dictionary) -> void:
	var n = int(rules["cells"])
	var border = int(rules["border"])
	var cell = float(rules["cell"])
	var gates = layout["gates"]
	var roads = layout["roads"]
	var gmin = mini(int(rules["gates"]["min"]), roads.size() * 2)
	if gates.size() < gmin or gates.size() > int(rules["gates"]["max"]):
		_fail(sv, "%d gates, expected %d to %s" % [gates.size(), gmin, rules["gates"]["max"]])
	var tunnels = 0
	for z in range(n):
		for x in range(n):
			if _cell(layout, x, z) == "t":
				tunnels += 1
	var expected = 0
	for gt in gates:
		var side = str(gt["side"])
		var depth = mini(int(rules["gates"]["depth"]), border)
		var width = int(gt["hi"]) - int(gt["lo"]) + 1
		expected += width * depth
		for k in range(int(gt["lo"]), int(gt["hi"]) + 1):
			for d in range(depth):
				var x = k if side == "n" or side == "s" else (d if side == "w" else n - 1 - d)
				var z = k if side == "w" or side == "e" else (d if side == "n" else n - 1 - d)
				if _cell(layout, x, z) != "t":
					_fail(
						sv,
						"gate %s cell %d,%d is '%s', not tunnel" % [side, x, z, _cell(layout, x, z)]
					)
			# the road carries on just inside the tunnel
			var ix = (
				k if side == "n" or side == "s" else (border if side == "w" else n - 1 - border)
			)
			var iz = (
				k if side == "w" or side == "e" else (border if side == "n" else n - 1 - border)
			)
			if _cell(layout, ix, iz) != "r":
				_fail(sv, "no road behind gate %s at %d,%d" % [side, ix, iz])
		var pos = Vector2(gt["pos"][0], gt["pos"][1])
		var out = Vector2(gt["outward"][0], gt["outward"][1])
		var limit = float(n) * cell / 2.0
		if (
			absf(out.length() - 1.0) > 0.0001
			or pos.dot(out) < limit - float(border) * cell
			or pos.dot(out) > limit
		):
			_fail(
				sv,
				"gate %s at %s with outward %s is not on its side of the arena" % [side, pos, out]
			)
		if ArenaGen.surface_at(layout, pos.x, pos.y) != "tunnel":
			_fail(
				sv,
				(
					"gate %s: the ground at its position is %s"
					% [side, ArenaGen.surface_at(layout, pos.x, pos.y)]
				)
			)
		if absf(float(gt["half_width"]) - float(width) * cell / 2.0) > 0.0001:
			_fail(
				sv,
				"gate %s half_width %s, its opening is %d cells" % [side, gt["half_width"], width]
			)
	if tunnels != expected:
		_fail(sv, "%d tunnel cells, the gates account for %d" % [tunnels, expected])


func _check_start(sv: int, layout: Dictionary, rules: Dictionary) -> void:
	var st = layout["start"]
	var half = int(rules["start"]["half"])
	var cx = int(st["cell"][0])
	var cz = int(st["cell"][1])
	for z in range(cz - half, cz + half + 1):
		for x in range(cx - half, cx + half + 1):
			if _cell(layout, x, z) != "p":
				_fail(sv, "start area cell %d,%d is '%s', not plaza" % [x, z, _cell(layout, x, z)])
				return
	if ArenaGen.surface_at(layout, st["pos"][0], st["pos"][1]) != "plaza":
		_fail(
			sv,
			"the start position is on %s" % ArenaGen.surface_at(layout, st["pos"][0], st["pos"][1])
		)
	if layout["plazas"].is_empty() or not layout["plazas"][0]["start"]:
		_fail(sv, "the first plaza is not the start plaza")


# the navigation grid: blocked exactly where there is a building, clearance never zero elsewhere, the
# start area roomy, costs that follow the speed table. The clearance itself is compared with a slow search
# for the nearest building on every 40th seed (it costs about a million lookups per layout).
func _check_nav(sv: int, layout: Dictionary, rules: Dictionary) -> void:
	var n = int(rules["cells"])
	var cap = int(rules["nav"]["max_clearance"])
	var nav = layout["nav"]
	if nav.size() != n:
		_fail(sv, "nav has %d rows, expected %d" % [nav.size(), n])
		return
	var slow = (sv % 40) == 12345 % 40
	for z in range(n):
		if str(nav[z]).length() != n:
			_fail(sv, "nav row %d has %d cells, expected %d" % [z, str(nav[z]).length(), n])
			return
		for x in range(n):
			var is_building = _cell(layout, x, z) == "b"
			var c = ArenaGen.nav_clearance(layout, x, z)
			if is_building != (c == 0) or c > cap:
				_fail(sv, "nav at %d,%d is %d over '%s'" % [x, z, c, _cell(layout, x, z)])
				return
			if slow and not is_building:
				var best = cap
				for dz in range(-cap, cap + 1):
					for dx in range(-cap, cap + 1):
						var ox = x + dx
						var oz = z + dz
						if (
							ox >= 0
							and oz >= 0
							and ox < n
							and oz < n
							and _cell(layout, ox, oz) == "b"
						):
							best = mini(best, maxi(absi(dx), absi(dz)))
				if best != c:
					_fail(
						sv,
						(
							"nav clearance at %d,%d is %d, the nearest building is %d away"
							% [x, z, c, best]
						)
					)
					return
	var st = layout["start"]
	var need = int(rules["start"]["half"]) + 1
	if ArenaGen.nav_clearance(layout, int(st["cell"][0]), int(st["cell"][1])) < need:
		_fail(
			sv,
			(
				"the start cell has clearance %d, wants at least %d"
				% [ArenaGen.nav_clearance(layout, int(st["cell"][0]), int(st["cell"][1])), need]
			)
		)
	for gt in layout["gates"]:
		var gx = int((float(gt["pos"][0]) / float(rules["cell"])) + float(n) / 2.0)
		var gz = int((float(gt["pos"][1]) / float(rules["cell"])) + float(n) / 2.0)
		if ArenaGen.nav_clearance(layout, gx, gz) == 0:
			_fail(sv, "gate %s is blocked in the navigation grid" % gt["side"])
	var table = rules["rider_speed"]
	if (
		ArenaGen.nav_cost(layout, rules, 0, 0) != INF
		or ArenaGen.nav_cost(layout, rules, -1, 5) != INF
	):
		_fail(sv, "a building or a cell outside the grid has a finite cost")
	for z in range(n):
		for x in range(n):
			var surface = ArenaGen.LEGEND[_cell(layout, x, z)]
			if surface == "building":
				continue
			var want = 1.0 / float(table[surface])
			if absf(ArenaGen.nav_cost(layout, rules, x, z) - want) > 0.0001:
				_fail(
					sv,
					(
						"nav cost at %d,%d is %s on %s, the table gives %s"
						% [x, z, ArenaGen.nav_cost(layout, rules, x, z), surface, want]
					)
				)
				return


# every generated layout passes validate (generate throws the others away); and validate must notice what
# it is for: each case below damages a good layout by hand and expects the matching problem
func _check_validation(rules: Dictionary) -> void:
	var good = ArenaGen.generate(7, rules)
	var problems = ArenaGen.validate(good, rules)
	if not problems.is_empty():
		_fail(7, "a generated layout fails validate: %s" % problems)
		return
	var n = int(good["cells"])
	var border = int(good["border"])
	var gt = good["gates"][0]
	var side = str(gt["side"])
	var along_lo = int(gt["lo"])
	var along_hi = int(gt["hi"])
	var inner = border if side == "n" or side == "w" else n - 1 - border
	var sealed = []
	var narrow = []
	for k in range(along_lo, along_hi + 1):
		var cell_xz = Vector2i(k, inner) if side == "n" or side == "s" else Vector2i(inner, k)
		sealed.append(cell_xz)
		if k < along_hi:
			narrow.append(cell_xz)
	var st = good["start"]["cell"]
	var cx = int(st[0])
	var cz = int(st[1])
	var ring = []
	for d in range(-5, 6):
		for edge in [-5, 5]:
			ring.append(Vector2i(cx + d, cz + edge))
			ring.append(Vector2i(cx + edge, cz + d))
	var pocket = _find_pocket(good)
	var cases = [
		["a sealed gate", sealed, "b", "gate"],
		["a one-cell-wide corridor to a gate", narrow, "b", "wide enough"],
		["a walled-off pocket", pocket, "b", "cannot be reached from the start"],
		["a dirty start area", [Vector2i(cx, cz + 1)], "g", "start area"],
		["a start walled in on all sides", ring, "b", "in view"],
	]
	for c in cases:
		if c[1].is_empty():
			_fail(7, "no way found to build the case '%s'" % c[0])
			continue
		var found = ArenaGen.validate(_damaged(good, c[1], str(c[2]), rules), rules)
		var hit = false
		for text in found:
			if str(text).contains(str(c[3])):
				hit = true
		if not hit:
			_fail(7, "validate did not notice %s (it said %s)" % [c[0], found])


# a copy of the layout with the given cells set to one surface character and the navigation grid redone
func _damaged(layout: Dictionary, cells: Array, ch: String, rules: Dictionary) -> Dictionary:
	var copy = layout.duplicate(true)
	var rows = copy["rows"]
	for v in cells:
		var line: String = rows[v.y]
		rows[v.y] = line.substr(0, v.x) + ch + line.substr(v.x + 1)
	var grid = PackedByteArray()
	for line in rows:
		grid.append_array(str(line).to_ascii_buffer())
	copy["nav"] = ArenaGen._nav_rows(grid, int(copy["cells"]), int(rules["nav"]["max_clearance"]))
	return copy


# the eight cells round one open grass cell that has grass all round it, so walling them in seals it off
func _find_pocket(layout: Dictionary) -> Array:
	var n = int(layout["cells"])
	for z in range(3, n - 3):
		for x in range(3, n - 3):
			var all_grass = true
			for dz in range(-2, 3):
				for dx in range(-2, 3):
					if _cell(layout, x + dx, z + dz) != "g":
						all_grass = false
			if all_grass:
				var out = []
				for dz in range(-1, 2):
					for dx in range(-1, 2):
						if dx != 0 or dz != 0:
							out.append(Vector2i(x + dx, z + dz))
				return out
	return []


# road is fastest, then sidewalk, then grass; buildings and anything outside the grid cannot be ridden on
func _check_speeds(rules: Dictionary) -> void:
	var table = rules["rider_speed"]
	var layout = ArenaGen.generate(1, rules)
	var road = float(table["road"])
	if not (
		road >= float(table["sidewalk"])
		and float(table["sidewalk"]) > float(table["grass"])
		and float(table["grass"]) > 0.0
	):
		_fail(
			1,
			"rider speed should fall from road to sidewalk to grass and stay above zero: %s" % table
		)
	var n = int(layout["cells"])
	var cell = float(layout["cell"])
	var seen = {}
	for z in range(n):
		for x in range(n):
			var wx = (float(x) + 0.5 - float(n) / 2.0) * cell
			var wz = (float(z) + 0.5 - float(n) / 2.0) * cell
			var name = ArenaGen.surface_at(layout, wx, wz)
			if name != ArenaGen.LEGEND[_cell(layout, x, z)]:
				_fail(
					1,
					(
						"surface_at(%s, %s) is %s, the grid says %s"
						% [wx, wz, name, ArenaGen.LEGEND[_cell(layout, x, z)]]
					)
				)
				return
			var sp = ArenaGen.rider_speed_at(layout, rules, wx, wz)
			seen[name] = sp
			if name == "building" and sp != 0.0:
				_fail(1, "riders move at %s on a building" % sp)
	if ArenaGen.rider_speed_at(layout, rules, 1.0e6, 0.0) != 0.0:
		_fail(1, "riders move outside the grid")
	for name in ["road", "sidewalk", "grass"]:
		if seen.has(name) and absf(float(seen[name]) - float(table[name])) > 0.0001:
			_fail(1, "rider speed on %s is %s, the table says %s" % [name, seen[name], table[name]])
