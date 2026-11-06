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
# README H3.1: what a Heat point pays on top of a run's base pay (docs/HEAT.md, "Rewards"): a share of the base in percent per
# point, and the least a run that earned any base pay gets from Heat 1 up
const REWARD_DEFAULTS = {"pct_per_point": 10, "min": 1}
const MAX_REWARD_PCT = 100  # sanity limit for the percent per point

var g = null
var levels: Array = []  # one dict per level, index = level; always has level 0
var caps: Dictionary = {}
var rewards: Dictionary = {}  # README H3.1: {"pct_per_point", "min"}, see `reward_bonus`
var modifiers: Array = []  # README H2.2: {"id", "name", "keys", "ranks": [{"points", "desc", "effects"}]}, rank 1 first
var clashes: Array = []  # {"a_id", "a_rank", "b_id", "b_rank", "why"}: two ranks that cannot be chosen together
var top_total: int = 0  # the most points a set of ranks without a clash is worth
var set_ranks: Dictionary = {}  # README H2.3: the legal set of ranks being played ({id: rank}); empty while a level is played
var set_effects: Dictionary = {}  # every effect at the value of `set_ranks`; empty = no set, `value()` reads the level


func _init(game = null) -> void:
	g = game
	var t = load_table()
	levels = t["levels"]
	caps = t["caps"]
	rewards = t["rewards"]
	modifiers = t["modifiers"]
	clashes = t["clashes"]
	top_total = t["top_total"]


# the last level in the table
func top_level() -> int:
	return levels.size() - 1


# a level number made valid: 0 to the top level
func clamp_level(n: int) -> int:
	return clampi(n, 0, top_level())


# README H1.11: the highest level the player has open (`heat_open` of meta.json, 0 for a player with no win yet or an old
# file), never past the top level of the table, so a table that lost levels cannot leave one "open" that is not there
func open_level() -> int:
	var open = int(g.meta.heat_open) if g != null and g.meta != null else 0
	return clampi(open, 0, top_level())


# a level number made valid and open: 0 up to `open_level`
func clamp_open(n: int) -> int:
	return clampi(n, 0, open_level())


# a copy of the entry of `level` (name, desc and every effect), clamped like value()
func level_info(level: int) -> Dictionary:
	return levels[clamp_level(level)].duplicate()


# the value of effect `key` at `level`; -1 (the default) is the run being played: the set of ranks chosen with `play_set`
# (README H2.3) if there is one, else the level of the run (`Main.heat`). A level given on purpose always reads the table.
func value(key: String, level: int = -1) -> float:
	if not NEUTRAL.has(key):
		push_error('heat: unknown effect "%s"' % key)
		return 0.0
	var lv = level
	if lv < 0:
		if not set_effects.is_empty():
			return float(set_effects[key])
		lv = int(g.heat) if g != null else 0
	return float(levels[clamp_level(lv)][key])


# README H1.10: how a level is written where the player sees it (the run bar, the pause menu, the run summary): "HEAT 3",
# and with `with_name` the level's name after it, "HEAT 3  FEWER LIVES". Level 0 is always plain "HEAT 0", because its
# table name ("NO HEAT") would only say the same twice. -1 (the default) is the level of the run being played.
func label(level: int = -1, with_name: bool = false) -> String:
	var lv = level
	if lv < 0:
		lv = int(g.heat) if g != null else 0
	lv = clamp_level(lv)
	var text = "HEAT %d" % lv
	if with_name and lv > 0:
		# README H2.4: the run being played with a set of the player's own is not the preset of its level, so it says CUSTOM
		var own = level == -1 and not custom_set().is_empty()
		text += "  " + ("CUSTOM" if own else str(levels[lv]["name"]))
	return text


# README H1.7: the hearts a run starts with at `level` (-1: the run being played). `START_HEARTS` less `hearts_minus`, but
# never below the `hearts_min` cap of the table, and never above `START_HEARTS`, so Heat 0 and a table that is hand-edited
# the wrong way both leave the hearts at 3. README H2.3: and never below 1. `hearts_minus` is at most 2 (RANGES), so a
# table that loaded cannot get there; the floor is for a table or a set that skipped that check together with a
# `hearts_min` cap under 1 (the loader accepts 0.4, which reads as 0). MAX LIVES in shop.gd, heart drops, PATCH UP and the
# heart on a round clear work on top of this and are not changed (docs/HEAT.md).
func start_hearts(level: int = -1) -> int:
	var minus = int(value("hearts_minus", level))
	var least = maxi(1, int(caps["hearts_min"]))
	return mini(START_HEARTS, maxi(least, START_HEARTS - minus))


# README H1.9: the factor on shop prices at `level` (-1: the level of the run). 1.0 at Heat 0. It is applied in
# `Shop.shop_price` before HAGGLER, which still rounds the price to 5 and keeps it at least 5.
func price_factor(level: int = -1) -> float:
	return value("price", level)


# README H1.9: the factor on the cash the player earns at `level` (-1: the level of the run). 1.0 at Heat 0, never below
# the `cash_min` cap of the table, and never above 1.0 (Heat does not pay more, so a hand-edited cap above 1 changes
# nothing). It is applied in `Shop.add_cash` before BOUNTY, the one place every cash source goes through.
func cash_factor(level: int = -1) -> float:
	return minf(1.0, maxf(value("cash", level), float(caps["cash_min"])))


# README H3.2: the Heat bonus on a run's `base` pay (docs/HEAT.md, "Rewards"), in whole numbers, for `points` Heat points
# (-1, the default, is the run being played: the points of the set of ranks played, or else the level of the run). It is
# `pct_per_point` percent of `base` per point, rounded to the nearest whole number (a half goes up), and at least `min`
# from Heat 1 up. It is 0 at Heat 0 and 0 when `base` is 0, so a run that earned nothing is paid nothing and Heat 0 pays
# exactly what it did before Heat. The sum is whole numbers until the one division, because `base * 0.10 * points` as a
# float may land a half on either side (16.5 as 16.499999 or 16.500001). `Meta.award_run` calls it for the coins and for the
# XP, so this is the only place that works the bonus out.
func reward_bonus(base: int, points: int = -1) -> int:
	var pts = points
	if pts < 0:
		if has_set():
			pts = set_points()
		else:
			pts = int(g.heat) if g != null else 0
	pts = clampi(pts, 0, total_cap())
	if pts <= 0 or base <= 0:
		return 0
	var pct = int(rewards["pct_per_point"])
	var scaled = floori(float(base * pts * pct + 50) / 100.0)
	return maxi(int(rewards["min"]), scaled)


# the most Heat points a run can have: the top total of a set, or the top level when that is higher (a table of presets
# only). Keeps a bad number from a save from paying more than the table can ever ask for.
func total_cap() -> int:
	return maxi(top_total, top_level())


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
# Heat of a set is the sum of the points of its ranks. README H2.3 lets the game play a set (`play_set`, `clear_set`):
# clashes are refused there and every cap of the table holds where the effect plays out. The page that chooses a set is
# H2.4 and the saves are H2.5 (`load_saved`); a run plays by level (`Main.heat`, the presets) unless a set is played.


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


# README H2.3: play `ranks` from now on: every lookup with no level given (`value`, `start_hearts`, `price_factor`,
# `cash_factor`, `boss_health`, `with_extra_riders`) reads this set until `clear_set`. A set with a clash is refused the way
# `clean_set` says (the second modifier of the clash goes down until it fits; `clashes_in(ranks)` before the call has the
# reasons), so what is played is always legal and never worth more than `top_total`. Returns the set that is played (a copy;
# the set that came in is not changed). An empty set is played as no ranks at all, which is Heat 0 (the neutral values).
func play_set(ranks: Dictionary) -> Dictionary:
	set_ranks = clean_set(ranks)
	set_effects = effects_of(set_ranks)
	return set_ranks.duplicate()


# README H2.3: go back to playing by level (`Main.heat`). A Daily Run does this, because it is Heat 0 for everybody.
func clear_set() -> void:
	set_ranks = {}
	set_effects = {}


# true while a set is played (see `play_set`)
func has_set() -> bool:
	return not set_effects.is_empty()


# what the set being played is worth (0 when no set is played)
func set_points() -> int:
	return total_points(set_ranks)


# the set of ranks the preset `level` names (a copy), and what it is worth: for every level of the table that is the
# level itself (`tools/heat_check.gd` proves it)
func preset_ranks(level: int) -> Dictionary:
	return levels[clamp_level(level)]["ranks"].duplicate()


func preset_points(level: int) -> int:
	return int(levels[clamp_level(level)]["points"])


# ---- README H2.4: the rules of the modifiers page. The page (hud.gd, input.gd) only draws and clicks; what a rank change
# may do, what a set is called and which set is played is decided here, so `tools/heat_mods_check.gd` can test it.


# the level whose preset is exactly `ranks` (rank 0 and a missing id are the same), or -1 for a set of the player's own
func preset_matching(ranks: Dictionary) -> int:
	for lv in range(levels.size()):
		var p = levels[lv]["ranks"]
		var same = true
		for id in modifier_ids():
			if int(p.get(id, 0)) != int(ranks.get(id, 0)):
				same = false
				break
		if same:
			return lv
	return -1


# the set of the player's own that is chosen: `Main.heat_ranks` if it is legal, has a rank in it, is worth exactly the level of
# the run (`Main.heat`, which is always the total of a chosen set) and is not just a preset; else {} (play by level)
func custom_set() -> Dictionary:
	if g == null or typeof(g.get("heat_ranks")) != TYPE_DICTIONARY:
		return {}
	var ranks = clean_set(g.heat_ranks)
	if (
		ranks.is_empty()
		or total_points(ranks) != clamp_level(int(g.heat))
		or preset_matching(ranks) >= 0
	):
		return {}
	return ranks


# the set the page shows and changes: the player's own set, or the preset of the level when there is none
func chosen_ranks() -> Dictionary:
	var own = custom_set()
	if not own.is_empty():
		return own
	return preset_ranks(int(g.heat) if g != null else 0)


# can modifier `id` of `ranks` move by `d` ranks (+1 or -1) when sets worth up to `open_total` points can be played? Returns
# {"ok": bool, "ranks": the set after the change (a copy; the same set when it is refused), "why": the reason in capitals
# when it is refused, "" when it is not, "kind": "top", "off", "clash", "open" or "" for the short tag the page writes}. Going down is always allowed above rank 0. Going up is refused at the top rank, for
# a clash (with the reason written in the table), and when the set would be worth more than `open_total` (README H2.4, docs/HEAT.md:
# a set can be played when its total is at most the highest open level).
func try_step(ranks: Dictionary, id: String, d: int, open_total: int) -> Dictionary:
	var out = {"ok": false, "ranks": ranks.duplicate(), "why": "", "kind": ""}
	var top = max_rank(id)
	var now = int(ranks.get(id, 0))
	if top == 0:
		out["why"] = "NO SUCH MODIFIER"
		return out
	var to = now + (1 if d > 0 else -1)
	if to < 0:
		out["why"] = "ALREADY OFF"
		out["kind"] = "off"
		return out
	if to > top:
		out["why"] = "ALREADY AT THE TOP RANK"
		out["kind"] = "top"
		return out
	var next = ranks.duplicate()
	if to == 0:
		next.erase(id)
	else:
		next[id] = to
	if d > 0:
		var hit = clashes_in(next)
		if not hit.is_empty():
			out["why"] = str(hit[0]["why"])
			out["kind"] = "clash"
			return out
		if total_points(next) > open_total:
			out["why"] = (
				"HEAT %d IS NOT OPEN YET (OPEN UP TO HEAT %d): WIN A RUN AT HEAT %d TO OPEN HEAT %d"
				% [total_points(next), open_total, open_total, open_total + 1]
			)
			out["kind"] = "open"
			return out
	out["ok"] = true
	out["ranks"] = next
	return out


# the level of the preset one step from `ranks` (d = -1 down, 1 up) among the levels 0 to `open_total`, or -1 when there is none.
# A set that is a preset steps from its own level; a set of the player's own counts as sitting at its total, so down goes to the
# preset worth the same Heat and up to the next one.
func preset_step(ranks: Dictionary, d: int, open_total: int) -> int:
	var at = preset_matching(ranks)
	var to = at + (1 if d > 0 else -1)
	if at < 0:
		var total = total_points(ranks)
		to = total + 1 if d > 0 else total
	if to < 0 or to > mini(open_total, top_level()):
		return -1
	return to


# README H2.4: the set that `Main` keeps after the page chose `ranks`. A set that is exactly a preset is kept as that level
# (`Main.heat` = the level, no own set), so it plays by level exactly as the picker of H1.4 does; any other set is the player's
# own (`Main.heat_ranks`) and `Main.heat` is its total, so the Heat number is always what the set is worth. Returns
# {"heat": int, "ranks": Dictionary} ({} when the set is a preset).
func settle(ranks: Dictionary) -> Dictionary:
	var legal = clean_set(ranks)
	var lv = preset_matching(legal)
	if lv >= 0:
		return {"heat": lv, "ranks": {}}
	return {"heat": clamp_level(total_points(legal)), "ranks": legal}


# a rank written out: "OFF" or "RANK 2 OF 3" (the page never says a rank with a colour alone)
func rank_text(id: String, rank: int) -> String:
	if rank <= 0:
		return "OFF"
	return "RANK %d OF %d" % [rank, max_rank(id)]


# what rank `rank` of modifier `id` does, in capitals, or what rank 0 does
func rank_desc(id: String, rank: int) -> String:
	if rank <= 0:
		return "OFF: ADDS NOTHING"
	for m in modifiers:
		if m["id"] == id:
			return str(m["ranks"][mini(rank, m["ranks"].size()) - 1]["desc"])
	return ""


# the points of every rank of `id` in a line, the current rank in brackets: "1 / [2] / 4"; rank 0 is "[0] / 1 / 2 / 4"
func points_line(id: String, rank: int) -> String:
	var parts = []
	for r in range(0, max_rank(id) + 1):
		var p = str(points_of(id, r))
		parts.append("[%s]" % p if r == rank else p)
	return " / ".join(parts)


# the name of the modifier `id`
func modifier_name(id: String) -> String:
	for m in modifiers:
		if m["id"] == id:
			return str(m["name"])
	return id


# the modifiers of a set in the order of the table, written for one line: "SWIFT RIDERS 2, CROWD 1"; "" for no ranks
func set_text(ranks: Dictionary) -> String:
	var parts = []
	for id in modifier_ids():
		var r = int(ranks.get(id, 0))
		if r > 0:
			parts.append("%s %d" % [modifier_name(id), r])
	return ", ".join(parts)


# ---- README H2.5: saving the set and showing it. `settings.cfg` and `run.json` keep the set of the player's own next to
# the level (`heat_set`, {modifier id: rank}); the rules for reading it back live here so both files read it the same way
# and `tools/heat_save_check.gd` can test them without a file.


# the set of ranks the run being played has: the player's own set when there is one, else the preset of its level ({} at Heat 0)
func played_ranks() -> Dictionary:
	var own = custom_set()
	if not own.is_empty():
		return own
	return preset_ranks(int(g.heat) if g != null else 0)


# the modifiers of the run being played in one line for the run bar, the pause menu and the run summary, in the order of the
# table: "SWIFT RIDERS 2, CROWD 1"; "" at Heat 0, where there is nothing to list
func modifiers_line() -> String:
	return set_text(played_ranks())


# what a save file says about the chosen set. `level` is the Heat level saved next to it and `raw` whatever the file held under
# `heat_set` (nothing, for a file written before H2.5). Returns {"heat": int, "ranks": Dictionary} the way `settle` does.
# A file with no set, or one that is not a set ({id: rank}), reads as the preset of its level, so an old file plays exactly as
# before. A set is made legal first (`clean_set`: unknown ids dropped, ranks kept to the table, a clash resolved); one that is
# empty after that, or is worth more than the top level of the ladder (what the page can hold, see docs/HEAT.md), is
# ignored and the saved level is used. Otherwise the set wins over the level, so the Heat number is always what the set is worth.
func load_saved(level: int, raw) -> Dictionary:
	var lv = clamp_level(level)
	if typeof(raw) != TYPE_DICTIONARY:
		return {"heat": lv, "ranks": {}}
	var legal = clean_set(raw)
	if legal.is_empty() or total_points(legal) > top_level():
		return {"heat": lv, "ranks": {}}
	return settle(legal)


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
# "clashes": Array, "top_total": int, "rewards": Dictionary}
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
		"rewards": REWARD_DEFAULTS.duplicate(),
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
	# README H3.1: the rewards. A missing or bad entry keeps the default, so Heat 0 still pays as before (0 percent of anything)
	var raw_rewards = data.get("rewards", {})
	if typeof(raw_rewards) == TYPE_DICTIONARY:
		for key in REWARD_DEFAULTS:
			if raw_rewards.has(key):
				var v = raw_rewards[key]
				var top = MAX_REWARD_PCT if key == "pct_per_point" else MAX_POINTS
				if _is_whole(v) and int(v) >= 0 and int(v) <= top:
					out["rewards"][key] = int(v)
				else:
					push_error('heat: reward "%s" needs a whole number from 0 to %d' % [key, top])
	else:
		push_error('heat: "rewards" has to be an object')
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
