extends SceneTree
# Checks the unlock table (README Milestone I: "Define the unlock list and price curve in a data table"):
#   - data/unlocks.json loads with no entry skipped,
#   - the price curve rises and the cheapest unlock costs no more than one short run pays,
#   - every perk can be unlocked as a starting perk, and no unlock is listed twice,
#   - the names and texts of perks and shop items come from the perk or item itself,
#   - a price follows the tier, unless the entry sets its own cost,
#   - bad entries are refused (unknown kind, unknown target, the heal, a tier off the curve, a repeat, a missing text).
# Run from the project folder:
#   godot --headless --path . --script res://tools/unlocks_check.gd
# or with tools\run_unlocks_check.bat on Windows.
# Exits with status 1 and prints the problems when a check fails.

const UnlocksTable = preload("res://scripts/unlocks.gd")
const PerksTable = preload("res://scripts/perks.gd")
const ItemsTable = preload("res://scripts/items.gd")

const CHEAPEST_MAX = 100  # coins: the cheapest unlock must be within reach of one short run (score / 100 plus boss coins)

var problems = []


func _initialize() -> void:
	var table = UnlocksTable.load_table()
	_check_table(table)
	_check_perks(table)
	_check_names_and_prices(table)
	_check_bad_entries()
	_finish(table)


func _finish(table: Dictionary) -> void:
	if problems.is_empty():
		var total = 0
		for u in table["unlocks"]:
			total += u["cost"]
		print(
			(
				"unlocks_check: %d unlocks, prices %s, %d coins to buy everything"
				% [table["unlocks"].size(), str(table["price_curve"]), total]
			)
		)
		quit(0)
	else:
		for line in problems.slice(0, 10):
			printerr("unlocks_check: " + line)
		quit(1)


func _fail(text: String) -> void:
	problems.append(text)


func _check_table(table: Dictionary) -> void:
	if table["skipped"] != 0:
		_fail("%d entries of unlocks.json were skipped (see the errors above)" % table["skipped"])
	if table["unlocks"].is_empty():
		_fail("no unlocks were loaded")
		return
	var curve = table["price_curve"]
	if curve.is_empty():
		_fail("the price curve did not load")
		return
	if curve[0] > CHEAPEST_MAX:
		_fail(
			(
				"the first price is %d coins, more than the %d one short run pays"
				% [curve[0], CHEAPEST_MAX]
			)
		)
	var seen_ids = {}
	var seen_targets = {}
	for u in table["unlocks"]:
		if seen_ids.has(u["id"]):
			_fail("id %s is used twice" % u["id"])
		seen_ids[u["id"]] = true
		var key = u["kind"] + ":" + u["target"]
		if seen_targets.has(key):
			_fail("%s is unlocked twice" % key)
		seen_targets[key] = true
		if u["cost"] < 0:
			_fail("%s has a negative cost" % u["id"])


# every perk of perks.json can be unlocked as a starting perk
func _check_perks(table: Dictionary) -> void:
	var unlocked = {}
	for u in table["unlocks"]:
		if u["kind"] == "starting_perk":
			unlocked[u["target"]] = true
	for p in PerksTable.load_table()["perks"]:
		if not unlocked.has(p["id"]):
			_fail("perk %s has no starting_perk unlock" % p["id"])
	# the heal is always on sale and must not be gated
	for u in table["unlocks"]:
		if u["kind"] == "shop_item" and u["target"] == "heal":
			_fail("the heal is listed as a shop_item unlock")


func _check_names_and_prices(table: Dictionary) -> void:
	var perks = {}
	for p in PerksTable.load_table()["perks"]:
		perks[p["id"]] = p
	var items = {}
	for it in ItemsTable.load_table()["items"]:
		items[it["id"]] = it
	var curve = table["price_curve"]
	var raw = JSON.parse_string(FileAccess.get_file_as_string(UnlocksTable.PATH))
	var own_cost = {}
	for r in raw["unlocks"]:
		if r.has("cost"):
			own_cost[str(r["id"])] = true
	for u in table["unlocks"]:
		var source = {}
		if u["kind"] == "starting_perk":
			source = perks.get(u["target"], {})
		elif u["kind"] == "shop_item":
			source = items.get(u["target"], {})
		if source.size() > 0 and (u["name"] != source["name"] or u["desc"] != source["desc"]):
			_fail("%s does not use the name and text of %s" % [u["id"], u["target"]])
		if u["tier"] < 1 or u["tier"] > curve.size():
			_fail("%s has tier %d, off the price curve" % [u["id"], u["tier"]])
		elif not own_cost.has(u["id"]) and u["cost"] != curve[u["tier"] - 1]:
			_fail(
				(
					"%s costs %d, not the %d of tier %d"
					% [u["id"], u["cost"], curve[u["tier"] - 1], u["tier"]]
				)
			)
		if u["planned"] and (u["kind"] == "starting_perk" or u["kind"] == "shop_item"):
			_fail("%s is planned, but its target exists" % u["id"])


func _check_bad_entries() -> void:
	var curve = [60, 120]
	var known = {
		"items":
		{
			"magnet": {"id": "magnet", "kind": "tier", "name": "POCKET MAGNET", "desc": "pulls"},
			"heal": {"id": "heal", "kind": "heal", "name": "PATCH UP", "desc": "+1 life"}
		},
		"perks":
		{"steady": {"id": "steady", "kind": "perk", "name": "STEADY HANDS", "desc": "less spread"}}
	}
	var good = {"id": "a", "kind": "starting_perk", "target": "steady", "tier": 1}
	var u = UnlocksTable.clean_unlock(good, curve, known, {}, {})
	if u.size() == 0 or u["cost"] != 60 or u["name"] != "STEADY HANDS":
		_fail("a good entry was refused or read wrong: %s" % str(u))
	var bad = [
		["unknown kind", {"id": "b", "kind": "hat", "target": "steady", "tier": 1}],
		["unknown perk", {"id": "b", "kind": "starting_perk", "target": "nope", "tier": 1}],
		["unknown item", {"id": "b", "kind": "shop_item", "target": "nope", "tier": 1}],
		["the heal", {"id": "b", "kind": "shop_item", "target": "heal", "tier": 1}],
		["tier 0", {"id": "b", "kind": "shop_item", "target": "magnet", "tier": 0}],
		["tier off the curve", {"id": "b", "kind": "shop_item", "target": "magnet", "tier": 3}],
		["no tier", {"id": "b", "kind": "shop_item", "target": "magnet"}],
		[
			"negative cost",
			{"id": "b", "kind": "shop_item", "target": "magnet", "tier": 1, "cost": -5}
		],
		[
			"weapon without a name",
			{"id": "b", "kind": "weapon", "target": "x", "desc": "d", "tier": 1}
		],
		[
			"planned perk",
			{"id": "b", "kind": "starting_perk", "target": "steady", "tier": 1, "planned": true}
		],
		["not an object", 5]
	]
	for pair in bad:
		if UnlocksTable.clean_unlock(pair[1], curve, known, {}, {}).size() > 0:
			_fail("a bad entry was accepted: %s" % pair[0])
	if UnlocksTable.clean_unlock(good, curve, known, {"a": true}, {}).size() > 0:
		_fail("a repeated id was accepted")
	if UnlocksTable.clean_unlock(good, curve, known, {}, {"starting_perk:steady": true}).size() > 0:
		_fail("a second unlock of the same perk was accepted")
	var weapon = {
		"id": "w",
		"kind": "weapon",
		"target": "x",
		"name": "X",
		"desc": "d",
		"tier": 2,
		"planned": true
	}
	var w = UnlocksTable.clean_unlock(weapon, curve, known, {}, {})
	if w.size() == 0 or w["cost"] != 120 or not w["planned"]:
		_fail("a good weapon entry was refused or read wrong: %s" % str(w))
	if UnlocksTable.clean_curve([60, 120]).size() != 2:
		_fail("a good price curve was refused")
	for curve_bad in [[], [0, 5], [60, 60], [100, 50], ["a"], "x", null]:
		if UnlocksTable.clean_curve(curve_bad).size() > 0:
			_fail("a bad price curve was accepted: %s" % str(curve_bad))
