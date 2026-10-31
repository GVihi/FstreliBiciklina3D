extends SceneTree
# Check for README alpha B9 "Offers and drops make sense for the weapon in your hands". Run from the project folder:
#   godot --headless --path . --script res://tools/offer_sense_check.gd
# (or `python tools/run_checks.py offer_sense`, which finds it by itself). Optional argument after "--": how many
# seeds to try for each weapon (default 10).
#
# For every weapon that can be in the primary slot (weapon_slots.gd, so a new weapon is checked as soon as it is
# added), over many seeds, every floor of the run map and random loadouts (clip levels, hearts, perks), it checks that
#   - nothing the game offers or drops fails the test of scripts/needs.gd: no upgrade card, shop item or drop whose
#     `needs` do not hold (the ammo family with a clip below 3, cash with no shop ahead, boss perks with no boss ahead)
#   - the shelves stay full: the shop always shows four items and an upgrade screen three, and the same state gives
#     the same offers twice (the seeded draws are not touched by the test)
#   - a kill's drops (`drop_kill`) and the drops of `maybe_drop` are all drops that can matter
# and one case for each example under "Known so far" of B9 and for each decision of B9.2:
#   - the AMMO family (AMMO drop, cache ammo reward, SALVAGE, SCAVENGER, COUNTER, the duos MATADOR, HEADHUNTER and
#     SCRAPYARD) is hidden until the clip is 3 or more, for the weapon's own clip, and comes back with a bigger one
#   - FREE DARTS, SLIDE SHOT and QUICK DRAW stay offered with every weapon
#   - EXTENDED CLIP says the real step of the weapon (+1 dart with the pistol, +2 with the dart gun)
#   - LAST SHELL stays a perk of every weapon, SNIPER only with a boss ahead
#   - the cash entries need a shop ahead and DEADEYE, HEADHUNTER and SNIPER a boss ahead, read from the run map
#   - the deflect entries (COUNTER, BOOMERANG, the duos BOUNTY HUNTER and RICOCHET) and MELEE REACH need a melee weapon
#     in the slot, which a new player does not have until the gummy worm is bought (`has_melee`)
# Exits with status 1 and prints the first problems.

const Needs = preload("res://scripts/needs.gd")
const WeaponSlots = preload("res://scripts/weapon_slots.gd")
const MAIN_SCENE = "res://main.tscn"
const ITEMS_PATH = "res://data/items.json"
const PERKS_PATH = "res://data/perks.json"
const KILL_DRAWS = 40  # `drop_kill` calls per loadout
const BOSS_DRAWS = 20  # `maybe_drop` calls per loadout

# The ammo family: every entry that goes through `add_shells` and is hidden until the clip is 3+ (B9.2).
const AMMO_PERKS = ["salvage", "scavenger", "counter"]
const AMMO_DUOS = ["MATADOR", "HEADHUNTER", "SCRAPYARD"]
# Cash entries need a shop ahead, boss entries a boss ahead (B9.2).
const CASH_PERKS = ["haggler", "bounty"]
const CASH_DUOS = ["BOUNTY HUNTER", "LIFE INSURANCE"]
const BOSS_PERKS = ["deadeye"]
const BOSS_DUOS = ["HEADHUNTER", "SNIPER"]
# Deflect entries need a melee weapon in the slot (the melee lock: the slot starts empty).
const MELEE_PERKS = ["counter", "boomerang"]
const MELEE_DUOS = ["BOUNTY HUNTER", "RICOCHET"]

var problems = []
var main
var cases = 0


func _initialize() -> void:
	var count = 10
	var args = OS.get_cmdline_user_args()
	if args.size() > 0:
		count = maxi(1, int(args[0]))
	main = load(MAIN_SCENE).instantiate()
	root.add_child(main)
	for i in range(3):
		await process_frame
	seed(99)
	_check_data()
	for weapon in WeaponSlots.PRIMARY_WEAPONS:
		_check_known_cases(str(weapon))
		_sweep(str(weapon), count)
	_finish()


func _fail(text: String) -> void:
	problems.append(text)


# ---------------------------------------------------------------- the data files
# every `needs` in the data files uses a key the test knows, and the decisions of B9.2 are in them
func _check_data() -> void:
	var items = _load_json(ITEMS_PATH).get("items", [])
	var perks_file = _load_json(PERKS_PATH)
	var perks = perks_file.get("perks", [])
	var duos = perks_file.get("duos", [])
	for list in [items, perks, duos]:
		for e in list:
			if e.has("needs"):
				_check_needs_keys(str(e.get("id", e.get("name", "?"))), e["needs"])
	for id in AMMO_PERKS:
		_expect_needs(perks, "id", id, "clip_min", 3)
	for id in CASH_PERKS:
		_expect_needs(perks, "id", id, "shop_ahead", true)
	for id in BOSS_PERKS:
		_expect_needs(perks, "id", id, "boss_ahead", true)
	for nm in AMMO_DUOS:
		_expect_needs(duos, "name", nm, "clip_min", 3)
	for nm in CASH_DUOS:
		_expect_needs(duos, "name", nm, "shop_ahead", true)
	for nm in BOSS_DUOS:
		_expect_needs(duos, "name", nm, "boss_ahead", true)
	for id in MELEE_PERKS:
		_expect_needs(perks, "id", id, "melee", true)
	for nm in MELEE_DUOS:
		_expect_needs(duos, "name", nm, "melee", true)
	_expect_needs(items, "id", "heal", "hurt", true)
	_expect_needs(perks, "id", "lastshell", "", null)  # a pistol perk, no needs of its own
	var drop_needs = main.DROP_NEEDS
	if drop_needs.get("ammo", {}).get("clip_min", 0) != 3:
		_fail("DROP_NEEDS: the ammo drop must need a clip of 3")
	if not drop_needs.get("cash", {}).get("shop_ahead", false):
		_fail("DROP_NEEDS: the cash drop must need a shop ahead")
	if not drop_needs.get("heart", {}).get("hurt", false):
		_fail("DROP_NEEDS: the heart must need hurt hearts")


func _load_json(path: String) -> Dictionary:
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(data) != TYPE_DICTIONARY:
		_fail("%s is not a JSON object" % path)
		return {}
	return data


func _check_needs_keys(who: String, needs) -> void:
	if typeof(needs) != TYPE_DICTIONARY:
		_fail("%s: needs is not an object" % who)
		return
	for key in needs:
		if not Needs.KEYS.has(key):
			_fail('%s: unknown need "%s"' % [who, str(key)])


# the entry whose `field` is `value` has `need` set to `want`; an empty `need` means "has no needs at all"
func _expect_needs(list: Array, field: String, value: String, need: String, want) -> void:
	for e in list:
		if str(e.get(field, "")) != value:
			continue
		var needs = e.get("needs", {})
		if need == "":
			if needs.size() > 0:
				_fail("%s should have no needs (decided in B9.2), has %s" % [value, str(needs)])
		elif not needs.has(need) or needs[need] != want:
			_fail("%s should need %s = %s (B9.2), has %s" % [value, need, str(want), str(needs)])
		return
	_fail("%s is missing from the data file" % value)


# ---------------------------------------------------------------- the known examples, per weapon
func _start(weapon: String, seed_value: int) -> void:
	main.start_game(false, seed_value)
	if not main.equip_primary(weapon) and main.primary != weapon:
		_fail("cannot put %s in the primary slot" % weapon)
	main.equip_melee("melee")  # the older rules are tested with the melee weapon in the slot, as before the lock
	main.MAXSHELLS = int(main.primary_stats()["start_clip"])
	main.hearts = main.MAXHEARTS
	main.perks = []


# puts the player on this floor (0-based) of the run map, on a lane that is on the map, at the given round
func _at_floor(f: int, lane: int = 0) -> void:
	main.map_floor = f
	main.map_lane = lane
	main.round_n = f + 1
	main.state = "play"


func _check_known_cases(weapon: String) -> void:
	_start(weapon, 0x2468ACE1)
	var P = main.pickup_sys
	var S = main.shop_sys
	var start_clip = int(main.primary_stats()["start_clip"])
	var step = int(main.primary_stats()["clip_step"])
	var max_clip = int(main.primary_stats()["max_clip"])
	var last = main.run_map["floors"].size() - 1
	_at_floor(2)  # floor 3: every perk of the pool can be on the shelf, a shop and a boss are still ahead

	# 1. the AMMO family follows the clip the player holds (B9.2: hidden until the clip is 3+)
	for clip in [1, 2, 3, 4, max_clip]:
		main.MAXSHELLS = clip
		var ammo_ok = clip >= 3
		cases += 1
		if P.drop_ok("ammo") != ammo_ok:
			_fail(
				(
					"%s clip %d: the AMMO drop should be %s"
					% [weapon, clip, "offered" if ammo_ok else "hidden"]
				)
			)
		if not ammo_ok and P.matter_drop("ammo") == "ammo":
			_fail("%s clip %d: a cache or boss draw still gave AMMO" % [weapon, clip])
		for id in AMMO_PERKS:
			if S.shop_ok(id) != ammo_ok:
				_fail(
					(
						"%s clip %d: perk %s should be %s"
						% [weapon, clip, id, "offered" if ammo_ok else "hidden"]
					)
				)
		for d in main.DUOS:
			if AMMO_DUOS.has(d["name"]) and Needs.ok(d.get("needs", {}), main) != ammo_ok:
				_fail(
					(
						"%s clip %d: duo %s should be %s"
						% [weapon, clip, d["name"], "shown" if ammo_ok else "hidden"]
					)
				)
	# the weapon's own starting clip decides what a player gets from the first shop on
	main.MAXSHELLS = start_clip
	if P.drop_ok("ammo") != (start_clip >= 3):
		_fail(
			"%s (start clip %d): the AMMO drop is %s" % [weapon, start_clip, str(P.drop_ok("ammo"))]
		)
	# a clip that is not yet full is what ammo needs: the first EXTENDED CLIP levels bring it back with a small clip
	main.MAXSHELLS = start_clip
	var levels = 0
	while main.MAXSHELLS < 3 and levels < 6:
		S.apply_upgrade("clip")
		levels += 1
	if main.MAXSHELLS >= 3 and not P.drop_ok("ammo"):
		_fail("%s: with a clip of %d the AMMO drop should be back" % [weapon, main.MAXSHELLS])
	main.MAXSHELLS = start_clip

	# 2. FREE DARTS, SLIDE SHOT and QUICK DRAW stay (B9.2)
	cases += 1
	if not S.shop_ok("pack_free"):
		_fail("%s: FREE DARTS is not offered" % weapon)
	if not S.shop_ok("slideshot"):
		_fail("%s: SLIDE SHOT is not offered" % weapon)
	for d in main.DUOS:
		if d["name"] == "QUICK DRAW" and d.has("needs"):
			_fail("QUICK DRAW should have no needs (B9.2), has %s" % str(d["needs"]))

	# 3. EXTENDED CLIP says the real step of the weapon (B9.2)
	cases += 1
	var want = "+%d dart%s per clip" % [step, "" if step == 1 else "s"]
	var clip_card = S.shop_item("clip")
	if S.item_desc(clip_card) != want:
		_fail(
			'%s: EXTENDED CLIP says "%s", the step is %d' % [weapon, S.item_desc(clip_card), step]
		)
	if main.MAXSHELLS + step <= max_clip:
		var stat = S.upgrade_stat("clip")
		var expect_stat = "DARTS %d > %d" % [main.MAXSHELLS, main.MAXSHELLS + step]
		if stat != expect_stat:
			_fail('%s: EXTENDED CLIP stat line "%s", expected "%s"' % [weapon, stat, expect_stat])

	# 4. LAST SHELL stays a perk of every weapon (B9.2), SNIPER needs a boss ahead
	cases += 1
	if not S.shop_ok("lastshell"):
		_fail("%s: LAST SHELL is not offered" % weapon)

	# 5. cash and boss entries follow the run map (B9.2): both ahead on floor 3, nothing ahead on the last floor
	cases += 1
	_at_floor(2)
	if not main.node_type_ahead("shop") or not main.node_type_ahead("boss"):
		_fail("%s: floor 3 should have a shop and a boss ahead" % weapon)
	for id in CASH_PERKS + BOSS_PERKS:
		if not S.shop_ok(id):
			_fail("%s: %s should be offered with its node ahead" % [weapon, id])
	if not P.drop_ok("cash"):
		_fail("%s: the CASH drop should be dropped with a shop ahead" % weapon)
	_at_floor(last)
	if main.node_type_ahead("shop") or main.node_type_ahead("boss"):
		_fail("%s: the last floor should have no shop and no boss ahead" % weapon)
	for id in CASH_PERKS + BOSS_PERKS:
		if S.shop_ok(id):
			_fail("%s: %s is offered on the last floor, with nothing ahead" % [weapon, id])
	if P.drop_ok("cash"):
		_fail("%s: the CASH drop is dropped on the last floor" % weapon)
	main.MAXSHELLS = max_clip  # the ammo rule must not hide behind the clip here
	for d in main.DUOS:
		var shown = Needs.ok(d.get("needs", {}), main)
		if (CASH_DUOS.has(d["name"]) or BOSS_DUOS.has(d["name"])) and shown:
			_fail("%s: duo %s is shown on the last floor, with nothing ahead" % [weapon, d["name"]])
	# the shop is on floor 9 and the boss on floor 10: standing in the shop on floor 9, only the boss is ahead
	_at_floor(last - 1)
	if main.node_type_ahead("shop") or not main.node_type_ahead("boss"):
		_fail("%s: after the floor 9 shop only the boss should be ahead" % weapon)
	# a hurt player gets hearts, a healthy one does not (the first rule of the test, B9.1)
	main.hearts = main.MAXHEARTS
	if P.drop_ok("heart") or S.shop_ok("heal"):
		_fail("%s: a heart or PATCH UP at full hearts" % weapon)
	main.hearts = main.MAXHEARTS - 1
	_at_floor(0)
	if not P.drop_ok("heart") or not S.shop_ok("heal"):
		_fail("%s: no heart or PATCH UP when hurt" % weapon)
	main.hearts = main.MAXHEARTS

	# 6. the deflect entries and MELEE REACH follow the melee slot: hidden while it is empty, offered with a weapon
	cases += 1
	_at_floor(2)  # a shop and a boss ahead, so only the melee rule can hide anything
	main.MAXSHELLS = max_clip  # the ammo rule (COUNTER) must not hide behind the clip here
	main.perks = []
	for held in [false, true]:
		main.equip_melee("melee" if held else "")
		var word = "offered" if held else "hidden"
		for id in MELEE_PERKS:
			if S.shop_ok(id) != held:
				_fail("%s: perk %s should be %s with melee %s" % [weapon, id, word, str(held)])
		if S.upgrade_ok("rubber") != held:
			_fail("%s: MELEE REACH should be %s with melee %s" % [weapon, word, str(held)])
		for d in main.DUOS:
			if MELEE_DUOS.has(d["name"]) and Needs.ok(d.get("needs", {}), main) != held:
				_fail(
					"%s: duo %s should be %s with melee %s" % [weapon, d["name"], word, str(held)]
				)
	main.equip_melee("melee")


# ---------------------------------------------------------------- the sweep
func _sweep(weapon: String, count: int) -> void:
	var rng = RandomNumberGenerator.new()
	rng.seed = 4711
	for n in range(count):
		_start(weapon, 1000 + n * 7919)
		var floors = main.run_map["floors"]
		var lane = rng.randi() % floors[0].size()
		for f in range(floors.size()):
			_at_floor(f, lane)
			_random_loadout(rng)
			_state_checks("%s seed %d floor %d" % [weapon, 1000 + n * 7919, f + 1])
			var next = main.next_lanes()
			if next.is_empty():
				break
			lane = int(next[rng.randi() % next.size()])
		main.clear_pickups()


func _random_loadout(rng: RandomNumberGenerator) -> void:
	var stats = main.primary_stats()
	var clip = int(stats["start_clip"]) + (rng.randi() % 4) * int(stats["clip_step"])
	main.MAXSHELLS = mini(clip, int(stats["max_clip"]))
	main.hearts = main.MAXHEARTS if rng.randf() < 0.5 else maxi(1, main.MAXHEARTS - 1)
	main.perks = []
	main.equip_melee("melee" if rng.randf() < 0.5 else "")  # both a bought worm and the empty slot of a new player
	for it in main.SHOP_POOL:
		if it["kind"] == "perk" and rng.randf() < 0.3:
			main.perks.append(it["id"])


func _ids(list: Array) -> Array:
	var out = []
	for o in list:
		out.append(str(o["id"]))
	return out


func _state_checks(label: String) -> void:
	cases += 1
	var S = main.shop_sys
	var P = main.pickup_sys
	# the upgrade screen: three offers, each one passes, the same state gives the same offers
	main.upgrade_part = "upgrade"
	main.upgrade_extra = 0
	S.show_upgrade()
	var first = _ids(main.offers)
	if main.state != "upgrade" or main.offers.size() != 3:
		_fail("%s: the upgrade screen has %d offers" % [label, main.offers.size()])
	for o in main.offers:
		if not S.upgrade_ok(o["id"]):
			_fail("%s: offered upgrade %s fails its test" % [label, o["id"]])
	main.state = "play"
	S.show_upgrade()
	if _ids(main.offers) != first:
		_fail("%s: the same state gave different upgrade offers" % label)
	main.state = "play"
	# the shop: four items, each one passes, no duo that cannot matter is advertised, the same state gives the same shelf
	main.shop_rerolls = 0
	S.build_shop()
	var shelf = _ids(main.shop_items)
	if main.shop_items.size() != 4:
		_fail("%s: the shop shows %d items" % [label, main.shop_items.size()])
	for c in main.shop_items:
		if not S.shop_ok(c["id"]) or not Needs.ok(S.shop_item(c["id"]).get("needs", {}), main):
			_fail("%s: the shop sells %s, which fails its test" % [label, c["id"]])
		if c["kind"] == "perk" and str(c["tag"]).begins_with("DUO"):
			for d in main.DUOS:
				if (
					str(c["tag"]).contains(str(d["name"]))
					and not Needs.ok(d.get("needs", {}), main)
				):
					_fail(
						"%s: the shop advertises duo %s, which cannot matter" % [label, d["name"]]
					)
	S.build_shop()
	if _ids(main.shop_items) != shelf:
		_fail("%s: the same state gave a different shop" % label)
	# the ammo family with a small clip
	if main.MAXSHELLS < 3:
		for id in AMMO_PERKS:
			if shelf.has(id):
				_fail("%s: %s is on the shelf with a clip of %d" % [label, id, main.MAXSHELLS])
	# drops: whatever a kill or a boss drops, or a cache gives, can matter
	for t in main.DROPS + main.objective_sys.REWARDS:
		var m = P.matter_drop(t)
		if m != "" and not P.drop_ok(m):
			_fail("%s: a %s draw gave %s, which cannot matter" % [label, t, m])
	main.state = "play"
	for i in range(KILL_DRAWS):
		P.drop_kill(Vector3(0.0, 0.0, 0.0), i % 2 == 0)
		_check_field(label, "drop_kill")
		main.clear_pickups()
	for i in range(BOSS_DRAWS):
		P.maybe_drop(Vector3(0.0, 0.0, 0.0), 1.0)
		_check_field(label, "maybe_drop")
		main.clear_pickups()


# every drop on the field is a drop that can matter now
func _check_field(label: String, source: String) -> void:
	for pk in main.pickups:
		if not main.pickup_sys.drop_ok(str(pk["type"])):
			_fail("%s: %s dropped %s, which cannot matter" % [label, source, str(pk["type"])])


func _finish() -> void:
	if problems.is_empty():
		print(
			"offer_sense_check: %d cases, nothing is offered or dropped that cannot matter" % cases
		)
		quit(0)
	else:
		print("offer_sense_check: %d problem(s) in %d cases" % [problems.size(), cases])
		for p in problems.slice(0, 12):
			print("  " + p)
		quit(1)
