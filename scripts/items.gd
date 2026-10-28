extends RefCounted
# Loads the shop item table (heals, packs and upgrade tiers) from res://data/items.json.
# Perks and duos are in data/perks.json (perks.gd). Item *effects* (what a tier changes) stay in shop.gd.
# Format and rules: data/README.md. JSON numbers arrive as floats, so they are cast to the types the game code expects.

const Needs = preload("res://scripts/needs.gd")

const PATH = "res://data/items.json"
const KINDS = ["heal", "pack", "tier"]
const PACK_KEYS = ["rapid", "big", "shield", "hype", "free"]


# returns {"items": Array of item dicts, in file order, "upgrades": Array of {id, name, desc} in the upgrade offer order}
static func load_table() -> Dictionary:
	var out = {"items": [], "upgrades": []}
	if not FileAccess.file_exists(PATH):
		push_error(
			(
				"items: %s is missing, the shop will be empty. Check the export include filter (data/*.json)."
				% PATH
			)
		)
		return out
	var data = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if typeof(data) != TYPE_DICTIONARY or typeof(data.get("items")) != TYPE_ARRAY:
		push_error('items: %s is not valid, expected an object with an "items" array' % PATH)
		return out
	var by_id = {}
	for raw in data["items"]:
		var it = _clean(raw, by_id)
		if it.size() > 0:
			by_id[it["id"]] = it
			out["items"].append(it)
	for id in data.get("upgrade_order", []):
		if by_id.has(id) and by_id[id]["kind"] == "tier":
			out["upgrades"].append({"id": id, "name": by_id[id]["name"], "desc": by_id[id]["desc"]})
		else:
			push_error('items: upgrade_order lists "%s", which is not a tier item' % str(id))
	return out


# validates one entry and fixes number types; returns {} (and logs why) when the entry is unusable
static func _clean(raw, by_id: Dictionary) -> Dictionary:
	if typeof(raw) != TYPE_DICTIONARY:
		push_error("items: entry is not an object: %s" % str(raw))
		return {}
	for key in ["id", "kind", "name", "desc"]:
		if typeof(raw.get(key)) != TYPE_STRING:
			push_error('items: entry %s needs a text "%s"' % [str(raw.get("id", "?")), key])
			return {}
	for key in ["cost", "min"]:
		if typeof(raw.get(key)) != TYPE_FLOAT and typeof(raw.get(key)) != TYPE_INT:
			push_error('items: %s needs a number "%s"' % [raw["id"], key])
			return {}
	if not KINDS.has(raw["kind"]):
		push_error(
			(
				'items: %s has unknown kind "%s" (perks live in data/perks.json)'
				% [raw["id"], raw["kind"]]
			)
		)
		return {}
	if by_id.has(raw["id"]):
		push_error('items: duplicate id "%s"' % raw["id"])
		return {}
	var it = {
		"id": raw["id"],
		"kind": raw["kind"],
		"name": raw["name"],
		"desc": raw["desc"],
		"cost": int(raw["cost"]),
		"min": int(raw["min"])
	}
	var needs = Needs.clean(raw.get("needs"), raw["id"])  # optional: what the item needs to matter (needs.gd)
	if needs.size() > 0:
		it["needs"] = needs
	if raw["kind"] == "heal":
		it["heal"] = int(raw.get("heal", 1))
	if raw["kind"] == "pack":
		var pending = {}
		var src = raw.get("pending", {})
		if typeof(src) != TYPE_DICTIONARY or src.size() == 0:
			push_error('items: pack %s needs a "pending" object' % raw["id"])
			return {}
		for k in src:
			if not PACK_KEYS.has(k):
				push_error('items: pack %s has unknown pending key "%s"' % [raw["id"], str(k)])
				return {}
			# same types main.gd gives the `pending` dictionary: rapid/big seconds (float), free darts (int), shield/hype (bool)
			if k == "rapid" or k == "big":
				pending[k] = float(src[k])
			elif k == "free":
				pending[k] = int(src[k])
			else:
				pending[k] = bool(src[k])
		it["pending"] = pending
	return it
