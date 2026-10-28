extends RefCounted
# Loads the unlock table (what the player can buy with meta coins) from res://data/unlocks.json.
# The Unlocks page, the Loadout page and the shop filter (`shop_item_owned` in main.gd, used by `shop_ok` in shop.gd)
# read it. Format and rules: data/README.md.
# JSON numbers arrive as floats, so they are cast to the types the game code expects.

const ItemsTable = preload("res://scripts/items.gd")
const PerksTable = preload("res://scripts/perks.gd")

const PATH = "res://data/unlocks.json"
const KINDS = ["starting_perk", "shop_item", "weapon", "cosmetic"]
# these kinds point at a perk or shop item that already exists, and take its name and text from it
const FROM_TARGET = ["starting_perk", "shop_item"]


# returns {"price_curve": Array of int (coins for tier 1, 2, ...), "unlocks": Array of dicts in file order,
# "skipped": how many entries were unusable and left out}
# every unlock is {id, kind, target, name, desc, tier, cost, planned}
static func load_table() -> Dictionary:
	var out = {"price_curve": [], "unlocks": [], "skipped": 0}
	if not FileAccess.file_exists(PATH):
		push_error(
			(
				"unlocks: %s is missing, nothing can be unlocked. Check the export include filter (data/*.json)."
				% PATH
			)
		)
		return out
	var data = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if typeof(data) != TYPE_DICTIONARY or typeof(data.get("unlocks")) != TYPE_ARRAY:
		push_error('unlocks: %s is not valid, expected an object with an "unlocks" array' % PATH)
		return out
	var curve = clean_curve(data.get("price_curve"))
	if curve.is_empty():
		push_error(
			'unlocks: "price_curve" must be a list of whole numbers above 0 that get bigger; the table is not used'
		)
		return out
	out["price_curve"] = curve
	var known = {"items": {}, "perks": {}}
	for it in ItemsTable.load_table()["items"]:
		known["items"][it["id"]] = it
	for p in PerksTable.load_table()["perks"]:
		known["perks"][p["id"]] = p
	var ids = {}
	var targets = {}
	for raw in data["unlocks"]:
		var u = clean_unlock(raw, curve, known, ids, targets)
		if u.size() == 0:
			out["skipped"] += 1
			continue
		ids[u["id"]] = true
		targets[u["kind"] + ":" + u["target"]] = true
		out["unlocks"].append(u)
	return out


# the price curve: a non-empty list of whole numbers above 0, each bigger than the one before; [] when it is not
static func clean_curve(raw) -> Array:
	var curve = []
	if typeof(raw) != TYPE_ARRAY or raw.is_empty():
		return curve
	for v in raw:
		if typeof(v) != TYPE_FLOAT and typeof(v) != TYPE_INT:
			return []
		if int(v) < 1 or (curve.size() > 0 and int(v) <= curve[-1]):
			return []
		curve.append(int(v))
	return curve


# validates one entry and fixes number types; returns {} (and logs why) when the entry is unusable.
# `known` is {"items": id -> item, "perks": id -> perk}; `ids` and `targets` are what was accepted before this entry.
static func clean_unlock(
	raw, curve: Array, known: Dictionary, ids: Dictionary, targets: Dictionary
) -> Dictionary:
	if typeof(raw) != TYPE_DICTIONARY:
		push_error("unlocks: entry is not an object: %s" % str(raw))
		return {}
	for key in ["id", "kind", "target"]:
		if typeof(raw.get(key)) != TYPE_STRING or str(raw[key]) == "":
			push_error('unlocks: entry %s needs a text "%s"' % [str(raw.get("id", "?")), key])
			return {}
	var id = str(raw["id"])
	var kind = str(raw["kind"])
	var target = str(raw["target"])
	if not KINDS.has(kind):
		push_error('unlocks: %s has unknown kind "%s"' % [id, kind])
		return {}
	if ids.has(id):
		push_error('unlocks: duplicate id "%s"' % id)
		return {}
	if targets.has(kind + ":" + target):
		push_error('unlocks: %s unlocks %s "%s" a second time' % [id, kind, target])
		return {}
	var tier_ok = typeof(raw.get("tier")) == TYPE_FLOAT or typeof(raw.get("tier")) == TYPE_INT
	if not tier_ok or int(raw["tier"]) < 1 or int(raw["tier"]) > curve.size():
		push_error('unlocks: %s needs a "tier" from 1 to %d' % [id, curve.size()])
		return {}
	var tier = int(raw["tier"])
	var name = ""
	var desc = ""
	if FROM_TARGET.has(kind):
		var source = _source_of(kind, target, known)
		if source.size() == 0:
			push_error('unlocks: %s points at "%s", which is not a usable %s' % [id, target, kind])
			return {}
		if bool(raw.get("planned", false)):
			push_error('unlocks: %s is "planned", but %s "%s" exists' % [id, kind, target])
			return {}
		name = str(source["name"])
		desc = str(source["desc"])
	else:
		for key in ["name", "desc"]:
			if typeof(raw.get(key)) != TYPE_STRING or str(raw[key]) == "":
				push_error('unlocks: %s needs a text "%s"' % [id, key])
				return {}
		name = str(raw["name"])
		desc = str(raw["desc"])
	var cost = int(curve[tier - 1])
	if raw.has("cost"):
		var c = raw["cost"]
		if (typeof(c) != TYPE_FLOAT and typeof(c) != TYPE_INT) or int(c) < 0:
			push_error('unlocks: %s has a "cost" that is not a whole number from 0' % id)
			return {}
		cost = int(c)
	return {
		"id": id,
		"kind": kind,
		"target": target,
		"name": name,
		"desc": desc,
		"tier": tier,
		"cost": cost,
		"planned": bool(raw.get("planned", false))
	}


# the perk or shop item an entry points at, {} when there is none or it cannot be unlocked
static func _source_of(kind: String, target: String, known: Dictionary) -> Dictionary:
	if kind == "starting_perk":
		return known["perks"].get(target, {})
	var item = known["items"].get(target, {})
	if item.size() > 0 and item["kind"] == "heal":
		return {}  # the heal is always on sale
	return item


# The unlocks that the coins of one run put within reach for the first time: not owned, not planned, and the meta
# balance went from below the price to the price or above it. `table` is the "unlocks" array, `owned` the owned ids
# as keys, `before` and `after` the balance around the payout. Returns the entries in table order.
static func newly_affordable(table: Array, owned: Dictionary, before: int, after: int) -> Array:
	var out = []
	for u in table:
		if owned.has(u["id"]) or u["planned"]:
			continue
		var cost = int(u["cost"])
		if before < cost and cost <= after:
			out.append(u)
	return out


# how an unlock shows on the Unlocks page: "owned", "soon" (its target is not in the game yet), "afford" (the
# balance covers the price) or "locked"
static func state_of(u: Dictionary, owned: bool, balance: int) -> String:
	if owned:
		return "owned"
	if u["planned"]:
		return "soon"
	if balance >= u["cost"]:
		return "afford"
	return "locked"
