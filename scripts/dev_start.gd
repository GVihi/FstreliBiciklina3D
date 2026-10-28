extends RefCounted
# Developer-only start options (roadmap alpha D2.1): start the game with a number of meta coins and some unlocks owned,
# so the balance pass can test "with three or four unlocks" without grinding for them. Two user arguments, after `--`:
#   godot --path . -- --dev-coins=500 --dev-unlocks=item_magnet,item_heart,weapon_dart_gun
#   godot --path . -- --dev-unlocks=all
# --dev-coins=N          the coin balance is N (not added to the saved one), from 0 to MAX_COINS
# --dev-unlocks=a,b,c    these unlock ids (`id` in data/unlocks.json) are owned; `all` means every unlock that is not
#                        planned (a planned unlock has no weapon or item in the game yet)
# Three rules keep it from hurting anyone:
#   - it never touches the normal save: as soon as either argument is given, `SaveUtil.read_only` is switched on and
#     no file in user:// is written or deleted for the rest of the session (see save_util.gd),
#   - it never ships enabled: nothing happens without the argument, and an exported game (release or debug) ignores the
#     argument: `allowed()` is true only for the Godot editor binary (`godot --path .`), so the exe given to testers
#     cannot be put into this mode by anyone,
#   - a wrong value never stops the game: it is left out and named in `problems`, which main.gd prints.
# What is applied to the coins and the unlocks is in meta.gd `apply_dev_start`; the wiring is in main.gd.

const ARG_COINS = "--dev-coins="
const ARG_UNLOCKS = "--dev-unlocks="
const UNLOCKS_ALL = "all"
const MAX_COINS = 1000000


# true when the game runs from the Godot editor binary (the editor, or `godot --path .`), false in every exported game
static func allowed() -> bool:
	return OS.has_feature("editor")


# Reads the arguments. `table` is the list of unlock dictionaries (Unlocks.load_table()["unlocks"]).
# Returns {"active": an option was given, "coins": -1 for none or the balance, "unlocks": ids to own,
# "problems": texts about values that were left out}.
static func parse(args: PackedStringArray, table: Array) -> Dictionary:
	var out = {"active": false, "coins": -1, "unlocks": [], "problems": []}
	var by_id = {}
	for u in table:
		by_id[str(u["id"])] = u
	for arg in args:
		if arg.begins_with(ARG_COINS):
			out["active"] = true
			var text = arg.substr(ARG_COINS.length())
			if not text.is_valid_int() or int(text) < 0 or int(text) > MAX_COINS:
				out["problems"].append(
					(
						"%s%s: expected a whole number from 0 to %d, left out"
						% [ARG_COINS, text, MAX_COINS]
					)
				)
			else:
				out["coins"] = int(text)
		elif arg.begins_with(ARG_UNLOCKS):
			out["active"] = true
			_add_unlocks(arg.substr(ARG_UNLOCKS.length()), by_id, table, out)
	return out


static func _add_unlocks(text: String, by_id: Dictionary, table: Array, out: Dictionary) -> void:
	for raw in text.split(",", false):
		var id = raw.strip_edges()
		if id == UNLOCKS_ALL:
			for u in table:
				if not bool(u["planned"]) and not out["unlocks"].has(str(u["id"])):
					out["unlocks"].append(str(u["id"]))
		elif not by_id.has(id):
			out["problems"].append("--dev-unlocks: no unlock with the id '%s', left out" % id)
		elif bool(by_id[id]["planned"]):
			out["problems"].append(
				"--dev-unlocks: '%s' is planned (not in the game yet), left out" % id
			)
		elif not out["unlocks"].has(id):
			out["unlocks"].append(id)
