extends RefCounted
# Heat: the difficulty level the player picks before a run (README Milestone B, "Difficulty Scaling"; the design is in
# docs/HEAT.md). Level 0 is the game as it was before Heat. The table is data/heat.json (format: data/README.md): the
# modifiers (each with ranks and points, README H2.2), the clashing pairs and the presets. A preset names a set of ranks,
# and the ladder `levels` is built from the presets at load time: one entry per level with the value of EVERY effect at
# that level, so a lookup is a read and nothing is added up.
# This file only holds the table and the lookup (and the effects that need a little arithmetic: `with_extra_riders`,
# `start_hearts`, `boss_health`, `cash_factor`). Each effect is applied where it plays out (riders.gd, bosses.gd, shop.gd,
# main.gd), one chunk each (README H1.5 to H1.9); all of them are built now.

const PATH = "res://data/heat.json"
const MAX_LEVEL = 20  # sanity limit for a hand-edited table
const START_HEARTS = 3  # the hearts a run starts with at Heat 0 (the `MAXHEARTS` of `Main.reset_run`)
const MAX_MODIFIER_RANKS = 5  # sanity limit for the ranks of one modifier (README H2.2)
const MAX_POINTS = 100  # sanity limit for the points of one rank

# effect key -> its value at level 0, where it changes nothing
const NEUTRAL = {
	"rider_speed": 1.0,  # factor on how fast riders ride
	"riders_more": 0.0,  # share of riders added to a round (0.2 = 20 % more)
	"hearts_minus": 0,  # hearts taken off the 3 a run starts with
	"tough_hp_plus": 0,  # health added to a tough rider
	"boss_hp": 1.0,  # factor on boss health
	"price": 1.0,  # factor on shop prices
	"cash": 1.0,  # factor on the cash the player earns
}
# effect key -> [lowest, highest] a table may give. Heat only makes the game harder, so no key goes the easy way
const RANGES = {
	"rider_speed": [1.0, 3.0],
	"riders_more": [0.0, 2.0],
	"hearts_minus": [0, 2],
	"tough_hp_plus": [0, 5],
	"boss_hp": [1.0, 3.0],
	"price": [1.0, 3.0],
	"cash": [0.1, 1.0],
}
const WHOLE_KEYS = ["hearts_minus", "tough_hp_plus"]  # these take whole numbers only
const CAP_DEFAULTS = {"riders_max": 16, "hearts_min": 2, "cash_min": 0.5}  # see "Caps" in docs/HEAT.md

var g = null
var levels: Array = []  # one dict per level, index = level; always has level 0
var caps: Dictionary = {}
var modifiers: Array = []  # README H2.2: {"id", "name", "keys", "ranks": [{"points", "desc", "effects"}]}, rank 1 first
var clashes: Array = []  # {"a_id", "a_rank", "b_id", "b_rank", "why"}: two ranks that cannot be chosen together
var top_total: int = 0  # the most points a set of ranks without a clash is worth


func _init(game = null) -> void:
	g = game
	var t = load_table()
	levels = t["levels"]
	caps = t["caps"]
	modifiers = t["modifiers"]
	clashes = t["clashes"]
	top_total = t["top_total"]


# the last level in the table
func top_level() -> int:
	return levels.size() - 1


# a level number made valid: 0 to the top level
func clamp_level(n: int) -> int:
	return clampi(n, 0, top_level())


# a copy of the entry of `level` (name, desc and every effect), clamped like value()
func level_info(level: int) -> Dictionary:
	return levels[clamp_level(level)].duplicate()


# the value of effect `key` at `level`; -1 (the default) is the level of the run being played (`Main.heat`)
func value(key: String, level: int = -1) -> float:
	if not NEUTRAL.has(key):
		push_error('heat: unknown effect "%s"' % key)
		return 0.0
	var lv = level
	if lv < 0:
		lv = int(g.heat) if g != null else 0
	return float(levels[clamp_level(lv)][key])


# README H1.7: the hearts a run starts with at `level` (-1: the level of the run). `START_HEARTS` less `hearts_minus`, but
# never below the `hearts_min` cap of the table, and never above `START_HEARTS`, so Heat 0 and a table that is hand-edited
# the wrong way both leave the hearts at 3. MAX LIVES in shop.gd, heart drops, PATCH UP and the heart on a round clear
# work on top of this and are not changed (docs/HEAT.md).
func start_hearts(level: int = -1) -> int:
	var minus = int(value("hearts_minus", level))
	return mini(START_HEARTS, maxi(int(caps["hearts_min"]), START_HEARTS - minus))


# README H1.9: the factor on shop prices at `level` (-1: the level of the run). 1.0 at Heat 0. It is applied in
# `Shop.shop_price` before HAGGLER, which still rounds the price to 5 and keeps it at least 5.
func price_factor(level: int = -1) -> float:
	return value("price", level)


# README H1.9: the factor on the cash the player earns at `level` (-1: the level of the run). 1.0 at Heat 0, never below
# the `cash_min` cap of the table, and never above 1.0 (Heat does not pay more, so a hand-edited cap above 1 changes
# nothing). It is applied in `Shop.add_cash` before BOUNTY, the one place every cash source goes through.
func cash_factor(level: int = -1) -> float:
	return minf(1.0, maxf(value("cash", level), float(caps["cash_min"])))


# README H1.8: a boss's health with the Heat factor of `level` (-1: the level of the run). `hp` is the health the boss has
# without Heat (after the growth per round, before the extra health of the final boss). The result is rounded to the
# nearest whole number, or up with `round_up` (the angry cyclist mini boss, which is small), and is at least 1. At Heat 0
# the factor is 1.0 and `hp` comes back as it is.
func boss_health(hp: int, level: int = -1, round_up: bool = false) -> int:
	var factor = value("boss_hp", level)
	if is_equal_approx(factor, 1.0):
		return hp
	var scaled = float(hp) * factor
	return maxi(1, int(ceil(scaled - 0.000001)) if round_up else int(round(scaled)))


# README H1.6: the riders of a round with the extra riders of `level` (-1: the level of the run). `plan` is the node's own
# plan after its shuffle and `mix` the node's kinds and counts ({kind: count}). Returns a new array. The seed's riders
# keep their order and are not changed; the extras copy the mix in its proportions (largest remainder, a tie goes to the
# kind that comes first in `mix`) and are spread evenly through the round. Nothing is drawn from a random stream, so
# no stream moves. The extra share is rounded up, at least one rider, and the round never goes past the `riders_max` cap
# (a plan that is already at the cap, an empty plan and Heat 0 come back as they are).
func with_extra_riders(plan: Array, mix: Dictionary, level: int = -1) -> Array:
	var out = plan.duplicate()
	var share = value("riders_more", level)
	if share <= 0.0 or plan.is_empty():
		return out
	var wanted = maxi(1, int(ceil(float(plan.size()) * share - 0.000001)))
	var n = mini(wanted, int(caps["riders_max"]) - plan.size())
	if n <= 0:
		return out
	var extras = _extra_kinds(mix, n)
	if extras.is_empty():
		return out
	var total = plan.size() + extras.size()
	var at = {}  # position in the new plan -> index of the extra rider that goes there
	for j in range(extras.size()):
		var pos = int(floor((float(j) + 0.5) * float(total) / float(extras.size())))
		at[mini(pos, total - 1)] = j
	out = []
	var next_plan = 0
	for p in range(total):
		if at.has(p):
			out.append(extras[at[p]])
		else:
			out.append(plan[next_plan])
			next_plan += 1
	return out


# `n` riders in the proportions of `mix`, grouped by kind in the order of the mix
func _extra_kinds(mix: Dictionary, n: int) -> Array:
	var kinds = []
	var total = 0
	for kind in mix:
		if int(mix[kind]) > 0:
			kinds.append(str(kind))
			total += int(mix[kind])
	if total == 0:
		return []
	var counts = {}
	var rest = []  # the part after the point of each kind's exact share
	var given = 0
	for kind in kinds:
		var exact = float(n) * float(int(mix[kind])) / float(total)
		var whole = int(floor(exact))
		counts[kind] = whole
		rest.append(exact - float(whole))
		given += whole
	while given < n:
		var best = 0
		for i in range(1, kinds.size()):
			if rest[i] > rest[best] + 0.000001:
				best = i
		counts[kinds[best]] += 1
		rest[best] = -1.0
		given += 1
	var out = []
	for kind in kinds:
		for k in range(int(counts[kind])):
			out.append(kind)
	return out


# ---- README H2.2: sets of ranks. A set is {modifier id: rank}, a rank of 0 (or a modifier that is left out) is off. The
# Heat of a set is the sum of the points of its ranks. The game still plays by level (`Main.heat`, the presets); wiring a
# chosen set into a run is H2.5, and the stacking caps and refusing clashes in play is H2.3.


# the ids of the modifiers, in the order of the table
func modifier_ids() -> Array:
	var out = []
	for m in modifiers:
		out.append(str(m["id"]))
	return out


# the number of ranks of modifier `id` (0 for an id that does not exist)
func max_rank(id: String) -> int:
	for m in modifiers:
		if m["id"] == id:
			return m["ranks"].size()
	return 0


# the points modifier `id` is worth at `rank` in total (0 at rank 0, a rank past the end counts as the top rank)
func points_of(id: String, rank: int) -> int:
	for m in modifiers:
		if m["id"] == id:
			var r = mini(rank, m["ranks"].size())
			return int(m["ranks"][r - 1]["points"]) if r > 0 else 0
	return 0


# the Heat of a set of ranks: the sum of the points of its ranks. An id that does not exist counts 0, a rank that is
# below 0 counts 0 and one past the end counts as the top rank; clashes are not looked at here (see `is_legal`)
func total_points(ranks: Dictionary) -> int:
	var total = 0
	for id in ranks:
		total += points_of(str(id), int(ranks[id]))
	return total


# the clashes `ranks` runs into, in the order of the table (each is a copy)
func clashes_in(ranks: Dictionary) -> Array:
	var out = []
	for c in clashes:
		if (
			int(ranks.get(c["a_id"], 0)) >= int(c["a_rank"])
			and int(ranks.get(c["b_id"], 0)) >= int(c["b_rank"])
		):
			out.append(c.duplicate())
	return out


# true when every id is a modifier, every rank is 0 up to its top rank, and the set has no clash
func is_legal(ranks: Dictionary) -> bool:
	for id in ranks:
		if max_rank(str(id)) == 0:
			return false
		if (
			typeof(ranks[id]) != TYPE_INT
			or int(ranks[id]) < 0
			or int(ranks[id]) > max_rank(str(id))
		):
			return false
	return clashes_in(ranks).is_empty()


# a set made legal (a saved or hand-edited one): unknown ids dropped, ranks cast and kept between 0 and the top rank,
# rank 0 left out, and for every clash the modifier `b` of the clash goes down one rank at a time until it no longer
# clashes. The set that comes in is not changed.
func clean_set(ranks: Dictionary) -> Dictionary:
	var out = {}
	for id in ranks:
		var top = max_rank(str(id))
		var r = ranks[id]
		if top > 0 and (typeof(r) == TYPE_INT or typeof(r) == TYPE_FLOAT):
			var n = clampi(int(r), 0, top)
			if n > 0:
				out[str(id)] = n
	var hit = _first_clash(out)
	while not hit.is_empty():
		var b = hit["b_id"]
		out[b] = int(hit["b_rank"]) - 1
		if int(out[b]) <= 0:
			out.erase(b)
		hit = _first_clash(out)
	return out


func _first_clash(ranks: Dictionary) -> Dictionary:
	var hits = clashes_in(ranks)
	return hits[0] if not hits.is_empty() else {}


# every effect at its value for a set of ranks (the neutral value where no rank sets it), the same keys a level has.
# Run the set through `clean_set` first: this does not look at clashes, and a rank past the end is the top rank.
func effects_of(ranks: Dictionary) -> Dictionary:
	var out = NEUTRAL.duplicate()
	for m in modifiers:
		var r = mini(int(ranks.get(m["id"], 0)), m["ranks"].size())
		if r > 0:
			for key in m["ranks"][r - 1]["effects"]:
				out[key] = m["ranks"][r - 1]["effects"][key]
	return out


# the set of ranks the preset `level` names (a copy), and what it is worth: for every level of the table that is the
# level itself (`tools/heat_check.gd` proves it)
func preset_ranks(level: int) -> Dictionary:
	return levels[clamp_level(level)]["ranks"].duplicate()


func preset_points(level: int) -> int:
	return int(levels[clamp_level(level)]["points"])


# true when `level` changes nothing (level 0 always does, the table loader makes sure)
func is_neutral(level: int) -> bool:
	var e = levels[clamp_level(level)]
	for key in NEUTRAL:
		if not is_equal_approx(float(e[key]), float(NEUTRAL[key])):
			return false
	return true


# The level 0 that is used when the file has none: nothing changes
static func neutral_level() -> Dictionary:
	var e = NEUTRAL.duplicate()
	e["level"] = 0
	e["name"] = "NO HEAT"
	e["desc"] = "THE GAME AS IT IS"
	return e


# reads the table file; always returns {"levels": Array with at least level 0, "caps": Dictionary, "modifiers": Array,
# "clashes": Array, "top_total": int}
static func load_table(path: String = PATH) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error(
			(
				"heat: %s is missing, the game runs without Heat. Check the export include filter (data/*.json)."
				% path
			)
		)
		return parse(null)
	return parse(JSON.parse_string(FileAccess.get_file_as_string(path)))


# turns the parsed JSON into the table. Bad entries are skipped and logged with push_error, so check the Godot output
# panel after editing. The file has modifiers (each with ranks and points), clashing pairs and presets; a preset names a
# set of ranks, and `levels` is the ladder built from the presets (the effect values of its ranks), so everything that
# reads a level (`value`, `level_info`, the PLAY page) works as it did when the file held the levels themselves. Presets
# have to run 0, 1, 2 ... without a gap (a level after a gap is dropped), and level 0 is forced to change nothing, so a
# broken file can never make Heat 0 harder than the game was before Heat.
static func parse(data) -> Dictionary:
	var out = {
		"levels": [neutral_level()],
		"caps": CAP_DEFAULTS.duplicate(),
		"modifiers": [],
		"clashes": [],
		"top_total": 0,
	}
	if (
		typeof(data) != TYPE_DICTIONARY
		or typeof(data.get("modifiers")) != TYPE_ARRAY
		or typeof(data.get("presets")) != TYPE_ARRAY
	):
		push_error(
			'heat: the table is not valid, expected an object with a "modifiers" and a "presets" array'
		)
		return out
	var raw_caps = data.get("caps", {})
	if typeof(raw_caps) == TYPE_DICTIONARY:
		for key in CAP_DEFAULTS:
			if raw_caps.has(key):
				if _is_number(raw_caps[key]) and float(raw_caps[key]) > 0.0:
					out["caps"][key] = raw_caps[key]
				else:
					push_error('heat: cap "%s" needs a number above 0' % key)
	# the modifiers: an id is used once, and so is an effect key (two modifiers on one key would need a rule to combine)
	var mods = []
	var ids = {}
	var key_owner = {}
	for raw in data["modifiers"]:
		var m = _clean_modifier(raw, ids, key_owner)
		if m.size() > 0:
			mods.append(m)
			ids[m["id"]] = m
			for key in m["keys"]:
				key_owner[key] = m["id"]
	out["modifiers"] = mods
	var raw_clashes = data.get("clashes", [])
	if typeof(raw_clashes) == TYPE_ARRAY:
		for raw in raw_clashes:
			var c = _clean_clash(raw, ids)
			if c.size() > 0:
				out["clashes"].append(c)
	else:
		push_error('heat: "clashes" has to be an array')
	out["top_total"] = _best_total(mods, out["clashes"])
	# the presets, which become the levels
	var by_level = {}
	for raw in data["presets"]:
		var e = _clean_preset(raw, by_level, ids)
		if e.size() > 0:
			by_level[e["level"]] = e
	if not by_level.has(0):
		push_error("heat: level 0 is missing, the game runs without Heat")
		return out
	var list = []
	while by_level.has(list.size()):
		list.append(by_level[list.size()])
	if by_level.size() > list.size():
		push_error(
			(
				"heat: the presets have to run 0, 1, 2 without a gap, so everything after level %d is skipped"
				% (list.size() - 1)
			)
		)
	var zero = list[0]
	if not zero["ranks"].is_empty():
		push_error("heat: level 0 must change nothing, its ranks are cleared")
		zero = _level_from_ranks(0, str(zero["name"]), str(zero["desc"]), {}, ids)
		list[0] = zero
	out["levels"] = list
	return out


# the entry of a level: every effect at its neutral value, then the effects of each rank in `ranks` ({id: rank}, ranks of
# 1 and up, every id in `ids`), the set itself and its points
static func _level_from_ranks(
	level: int, level_name: String, desc: String, ranks: Dictionary, ids: Dictionary
) -> Dictionary:
	var e = NEUTRAL.duplicate()
	e["level"] = level
	e["name"] = level_name
	e["desc"] = desc
	var points = 0
	for id in ranks:
		var rank_entry = ids[id]["ranks"][int(ranks[id]) - 1]
		for key in rank_entry["effects"]:
			e[key] = rank_entry["effects"][key]
		points += int(rank_entry["points"])
	e["ranks"] = ranks.duplicate()
	e["points"] = points
	return e


# one preset: {"level", "name", "desc", "ranks": {id: rank}}; returns {} (and logs why) when it is unusable. A modifier
# that is left out is at rank 0, and a rank of 0 is the same as leaving it out
static func _clean_preset(raw, seen: Dictionary, ids: Dictionary) -> Dictionary:
	if typeof(raw) != TYPE_DICTIONARY:
		push_error("heat: preset is not an object: %s" % str(raw))
		return {}
	var label = str(raw.get("level", "?"))
	if not _is_whole(raw.get("level")):
		push_error('heat: preset "%s" needs a whole number "level"' % label)
		return {}
	var level = int(raw["level"])
	if level < 0 or level > MAX_LEVEL:
		push_error("heat: level %d is outside 0 to %d" % [level, MAX_LEVEL])
		return {}
	if seen.has(level):
		push_error("heat: duplicate level %d" % level)
		return {}
	for key in ["name", "desc"]:
		if typeof(raw.get(key)) != TYPE_STRING or str(raw[key]) == "":
			push_error('heat: level %d needs a text "%s"' % [level, key])
			return {}
	var ranks = {}
	var raw_ranks = raw.get("ranks", {})
	if typeof(raw_ranks) != TYPE_DICTIONARY:
		push_error('heat: level %d: "ranks" has to be an object {modifier id: rank}' % level)
		return {}
	for id in raw_ranks:
		if not ids.has(id):
			push_error('heat: level %d names the modifier "%s", which does not exist' % [level, id])
			return {}
		var r = raw_ranks[id]
		if not _is_whole(r) or int(r) < 0 or int(r) > ids[id]["ranks"].size():
			push_error(
				(
					'heat: level %d: the rank of "%s" is %s, it has to be 0 to %d'
					% [level, id, str(r), ids[id]["ranks"].size()]
				)
			)
			return {}
		if int(r) > 0:
			ranks[str(id)] = int(r)
	return _level_from_ranks(level, str(raw["name"]), str(raw["desc"]), ranks, ids)


# one modifier: {"id", "name", "ranks": [{"points", "desc", effect keys ...}, ...]}, rank 1 first. Returns {"id", "name",
# "keys": [effect keys], "ranks": [{"points", "desc", "effects": {key: value}}]}, or {} (and logs why)
static func _clean_modifier(raw, ids: Dictionary, key_owner: Dictionary) -> Dictionary:
	if typeof(raw) != TYPE_DICTIONARY:
		push_error("heat: modifier is not an object: %s" % str(raw))
		return {}
	var id = str(raw.get("id", "?"))
	if typeof(raw.get("id")) != TYPE_STRING or not id.is_valid_identifier() or id != id.to_lower():
		push_error('heat: modifier "%s" needs a lower case "id" (letters, digits and _)' % id)
		return {}
	if ids.has(id):
		push_error('heat: duplicate modifier "%s"' % id)
		return {}
	if typeof(raw.get("name")) != TYPE_STRING or str(raw["name"]) == "":
		push_error('heat: modifier "%s" needs a text "name"' % id)
		return {}
	var raw_ranks = raw.get("ranks")
	if (
		typeof(raw_ranks) != TYPE_ARRAY
		or raw_ranks.is_empty()
		or raw_ranks.size() > MAX_MODIFIER_RANKS
	):
		push_error('heat: modifier "%s" needs 1 to %d ranks' % [id, MAX_MODIFIER_RANKS])
		return {}
	var ranks = []
	var keys = []
	var last_points = 0
	for i in range(raw_ranks.size()):
		var rr = raw_ranks[i]
		var where = 'modifier "%s", rank %d' % [id, i + 1]
		if typeof(rr) != TYPE_DICTIONARY:
			push_error("heat: %s is not an object" % where)
			return {}
		if not _is_whole(rr.get("points")) or int(rr["points"]) <= last_points:
			push_error(
				'heat: %s needs whole "points" above the rank before it (%d)' % [where, last_points]
			)
			return {}
		if int(rr["points"]) > MAX_POINTS:
			push_error("heat: %s has more than %d points" % [where, MAX_POINTS])
			return {}
		last_points = int(rr["points"])
		if typeof(rr.get("desc")) != TYPE_STRING or str(rr["desc"]) == "":
			push_error('heat: %s needs a text "desc"' % where)
			return {}
		var effects = {}
		for key in rr:
			if key == "points" or key == "desc":
				continue
			if not NEUTRAL.has(key):
				push_error('heat: %s has "%s", which is not an effect' % [where, key])
				return {}
			var v = rr[key]
			if not _is_number(v):
				push_error('heat: %s needs a number for "%s"' % [where, key])
				return {}
			if float(v) < float(RANGES[key][0]) or float(v) > float(RANGES[key][1]):
				push_error(
					(
						'heat: %s: "%s" is %s, it has to be %s to %s'
						% [where, key, str(v), str(RANGES[key][0]), str(RANGES[key][1])]
					)
				)
				return {}
			if WHOLE_KEYS.has(key):
				if float(int(v)) != float(v):
					push_error('heat: %s: "%s" has to be a whole number' % [where, key])
					return {}
				effects[key] = int(v)
			else:
				effects[key] = float(v)
		if effects.is_empty():
			push_error("heat: %s changes no effect" % where)
			return {}
		if i == 0:
			keys = effects.keys()
			keys.sort()
			for key in keys:
				if key_owner.has(key):
					push_error(
						(
							'heat: modifier "%s" sets "%s", which "%s" sets already'
							% [id, key, key_owner[key]]
						)
					)
					return {}
		else:
			var these = effects.keys()
			these.sort()
			if these != keys:
				push_error("heat: %s sets other effects than rank 1 does" % where)
				return {}
		ranks.append({"points": int(rr["points"]), "desc": str(rr["desc"]), "effects": effects})
	return {"id": id, "name": str(raw["name"]), "keys": keys, "ranks": ranks}


# one clashing pair: {"a": [id, rank], "b": [id, rank], "why": text}. Two ranks that are both at or above these cannot be
# chosen together; `b` is the one that is held back when `a` is there (`clean_set`). Returns {} (and logs why) when unusable
static func _clean_clash(raw, ids: Dictionary) -> Dictionary:
	if typeof(raw) != TYPE_DICTIONARY:
		push_error("heat: clash is not an object: %s" % str(raw))
		return {}
	var out = {}
	for side in ["a", "b"]:
		var pair = raw.get(side)
		if typeof(pair) != TYPE_ARRAY or pair.size() != 2 or typeof(pair[0]) != TYPE_STRING:
			push_error('heat: a clash needs "%s": [modifier id, rank]' % side)
			return {}
		if not ids.has(pair[0]):
			push_error('heat: a clash names the modifier "%s", which does not exist' % str(pair[0]))
			return {}
		if (
			not _is_whole(pair[1])
			or int(pair[1]) < 1
			or int(pair[1]) > ids[pair[0]]["ranks"].size()
		):
			push_error(
				(
					'heat: a clash names rank %s of "%s", which has ranks 1 to %d'
					% [str(pair[1]), pair[0], ids[pair[0]]["ranks"].size()]
				)
			)
			return {}
		out[side + "_id"] = str(pair[0])
		out[side + "_rank"] = int(pair[1])
	if out["a_id"] == out["b_id"]:
		push_error('heat: a clash is between two different modifiers, not "%s" twice' % out["a_id"])
		return {}
	if typeof(raw.get("why")) != TYPE_STRING or str(raw["why"]) == "":
		push_error('heat: a clash needs a text "why"')
		return {}
	out["why"] = str(raw["why"])
	return out


# the most points a set of ranks can be worth without a clash, found by trying every combination (the table is small)
static func _best_total(mods: Array, clashes: Array) -> int:
	return _best_from(mods, 0, {}, clashes, 0)


static func _best_from(mods: Array, i: int, ranks: Dictionary, clashes: Array, points: int) -> int:
	if i == mods.size():
		return points if _hit_clash(ranks, clashes).is_empty() else 0
	var best = 0
	var m = mods[i]
	for r in range(m["ranks"].size() + 1):
		ranks[m["id"]] = r
		var add = int(m["ranks"][r - 1]["points"]) if r > 0 else 0
		best = maxi(best, _best_from(mods, i + 1, ranks, clashes, points + add))
	ranks.erase(m["id"])
	return best


# the first clash `ranks` runs into ({} when it has none): both of its ranks are reached
static func _hit_clash(ranks: Dictionary, clashes: Array) -> Dictionary:
	for c in clashes:
		if (
			int(ranks.get(c["a_id"], 0)) >= int(c["a_rank"])
			and int(ranks.get(c["b_id"], 0)) >= int(c["b_rank"])
		):
			return c
	return {}


static func _is_number(v) -> bool:
	return typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT


static func _is_whole(v) -> bool:
	return _is_number(v) and float(int(v)) == float(v)
