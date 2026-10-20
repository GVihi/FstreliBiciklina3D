extends RefCounted
# Loads the perk and duo tables from res://data/perks.json.
# Perk *effects* stay in code (they check g.perks.has("id") where they apply). Format and rules: data/README.md.
# JSON numbers arrive as floats, so they are cast to the types the game code expects.

const PATH = "res://data/perks.json"

# returns {"perks": Array of shop entries (kind "perk"), "duos": Array of {a, b, name, desc}}, both in file order
static func load_table() -> Dictionary:
	var out = {"perks": [], "duos": []}
	if not FileAccess.file_exists(PATH):
		push_error("perks: %s is missing, there will be no perks. Check the export include filter (data/*.json)." % PATH)
		return out
	var data = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if typeof(data) != TYPE_DICTIONARY:
		push_error("perks: %s is not valid, expected an object with \"perks\" and \"duos\" arrays" % PATH)
		return out
	var ids = {}
	for raw in data.get("perks", []):
		var p = _clean_perk(raw, ids)
		if p.size() > 0:
			ids[p["id"]] = true
			out["perks"].append(p)
	var seen_names = {}
	for raw in data.get("duos", []):
		var d = _clean_duo(raw, ids, seen_names)
		if d.size() > 0:
			seen_names[d["name"]] = true
			out["duos"].append(d)
	return out

# a perk is a shop entry: same fields as an item, with kind fixed to "perk"
static func _clean_perk(raw, ids: Dictionary) -> Dictionary:
	if typeof(raw) != TYPE_DICTIONARY:
		push_error("perks: entry is not an object: %s" % str(raw))
		return {}
	for key in ["id", "name", "desc"]:
		if typeof(raw.get(key)) != TYPE_STRING:
			push_error("perks: entry %s needs a text \"%s\"" % [str(raw.get("id", "?")), key])
			return {}
	for key in ["cost", "min"]:
		if typeof(raw.get(key)) != TYPE_FLOAT and typeof(raw.get(key)) != TYPE_INT:
			push_error("perks: %s needs a number \"%s\"" % [raw["id"], key])
			return {}
	if ids.has(raw["id"]):
		push_error("perks: duplicate id \"%s\"" % raw["id"])
		return {}
	return {"id": raw["id"], "kind": "perk", "name": raw["name"], "desc": raw["desc"],
		"cost": int(raw["cost"]), "min": int(raw["min"])}

# a duo needs two different perks that exist, and a unique name (the name is how the game looks a duo up)
static func _clean_duo(raw, ids: Dictionary, seen_names: Dictionary) -> Dictionary:
	if typeof(raw) != TYPE_DICTIONARY:
		push_error("perks: duo is not an object: %s" % str(raw))
		return {}
	for key in ["a", "b", "name", "desc"]:
		if typeof(raw.get(key)) != TYPE_STRING:
			push_error("perks: duo %s needs a text \"%s\"" % [str(raw.get("name", "?")), key])
			return {}
	if raw["a"] == raw["b"] or not ids.has(raw["a"]) or not ids.has(raw["b"]):
		push_error("perks: duo %s needs two different existing perks, got \"%s\" and \"%s\"" % [raw["name"], raw["a"], raw["b"]])
		return {}
	if seen_names.has(raw["name"]):
		push_error("perks: duplicate duo name \"%s\"" % raw["name"])
		return {}
	return {"a": raw["a"], "b": raw["b"], "name": raw["name"], "desc": raw["desc"]}
