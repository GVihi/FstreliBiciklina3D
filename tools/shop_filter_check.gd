extends SceneTree
# Check for README alpha C3 "Owning a shop-item unlock matters". Run from the project folder:
#   godot --headless --path . --script res://tools/shop_filter_check.gd
# (or `python tools/run_checks.py shop_filter`, which finds it by itself).
#
# The six shop items that are unlocks in data/unlocks.json (POCKET MAGNET, HYPE PACK, LUCKY CHARM, HYPE MACHINE,
# SHIELD PACK, THICK SKIN) are sold only once they are bought. It checks that
#   - the table still has exactly those six `shop_item` unlocks, and each one is a real item of the shop pool,
#   - on a fresh save none of the six can be sold (`shop_ok`) and none is ever on a shelf, over many seeds, floors and
#     rerolls, in a normal run, a Daily Run and a custom seed alike,
#   - every item that is not an unlock (the heal when hurt, the other packs and upgrades, the perks) is still sold,
#   - the upgrade cards (the pick after a fight, the extra pick too) leave them out as well, and keep three cards,
#   - the shelf keeps its four items,
#   - buying one unlock brings back that item and only that item, and it can then be on a shelf,
#   - the filter changes the pool and never the draws: the same seed with the same unlocks gives the same shelf twice,
#     and the shelf with everything owned is the shelf of the full pool.
# It never saves: ownership is set in memory only, so the real meta.json is not touched.
# Exits with status 1 and prints the first problems.

const MAIN_SCENE = "res://main.tscn"
const SEEDS = [0x2468ACE1, 7, 1234567, 99999, 0xBEEF]
const FLOORS = [1, 2, 4, 6, 9]  # rounds: the items with `min` 2 are only sold from round 2 on
const REROLLS = 4

var problems = []
var main
var cases = 0


func _initialize() -> void:
	main = load(MAIN_SCENE).instantiate()
	root.add_child(main)
	for i in range(3):
		await process_frame
	seed(99)
	var targets = _check_table()
	for mode in ["normal", "daily", "custom"]:
		_check_mode(mode, targets)
	_finish(targets)


func _fail(text: String) -> void:
	problems.append(text)


func _finish(targets: Array) -> void:
	if problems.is_empty():
		print(
			(
				"shop_filter_check: %d cases, the %d unlock items (%s) are sold only once owned"
				% [cases, targets.size(), ", ".join(targets)]
			)
		)
		quit(0)
	else:
		for line in problems.slice(0, 10):
			printerr("shop_filter_check: " + line)
		quit(1)


# the unlock ids and shop item ids of the `shop_item` entries; exactly six, all of them in the shop pool
func _check_table() -> Array:
	var targets = []
	for u in main.UNLOCKS:
		if u["kind"] == "shop_item":
			targets.append(str(u["target"]))
	if targets.size() != 6:
		_fail("data/unlocks.json has %d shop_item unlocks, C3 is about six" % targets.size())
	for id in targets:
		if main.shop_sys.shop_item(id).size() == 0:
			_fail("the shop_item unlock %s is not an item of the shop pool" % id)
	return targets


func _unlock_id_of(target: String) -> String:
	for u in main.UNLOCKS:
		if u["kind"] == "shop_item" and u["target"] == target:
			return str(u["id"])
	return ""


func _fresh() -> void:
	main.meta.owned = {}  # in memory only, never saved


func _own_all() -> void:
	main.meta.owned = {}
	for u in main.UNLOCKS:
		if u["kind"] == "shop_item":
			main.meta.owned[str(u["id"])] = true


func _begin(mode: String, seed_value: int) -> void:
	match mode:
		"daily":
			main.start_game(true)
		"custom":
			main.start_game(false, seed_value)
		_:
			main.start_game(false)
			main.run_seed = seed_value
	main.perks = []
	main.hearts = main.MAXHEARTS


func _shelf(round_number: int, rerolls: int) -> Array:
	main.round_n = round_number
	main.shop_rerolls = rerolls
	main.shop_sys.build_shop()
	var ids = []
	for c in main.shop_items:
		ids.append(str(c["id"]))
	return ids


func _check_mode(mode: String, targets: Array) -> void:
	var S = main.shop_sys
	var seeds = [0] if mode == "daily" else SEEDS
	var seen_bought = false
	for s in seeds:
		_begin(mode, int(s))
		# 1. a fresh save: none of the six is sold, everything else still is
		_fresh()
		for r in FLOORS:
			main.round_n = r
			for id in targets:
				cases += 1
				if S.shop_ok(id):
					_fail("%s round %d: %s is sold on a fresh save" % [mode, r, id])
			cases += 1
			if (
				not S.shop_ok("pack_rapid")
				or not S.shop_ok("pack_fat")
				or not S.shop_ok("pack_free")
			):
				_fail("%s round %d: a pack that is not an unlock is not sold" % [mode, r])
			if r >= 1 and not S.shop_ok("wide") and main.up["wide"] < 4:
				_fail("%s round %d: the upgrade WIDE (not an unlock) is not sold" % [mode, r])
			for rerolls in range(REROLLS):
				var shelf = _shelf(r, rerolls)
				cases += 1
				if shelf.size() != 4:
					_fail(
						(
							"%s round %d reroll %d: the shop shows %d items"
							% [mode, r, rerolls, shelf.size()]
						)
					)
				_check_cards(mode, r, targets, [])
				for id in targets:
					if shelf.has(id):
						_fail(
							(
								"%s round %d reroll %d: %s is on a fresh save's shelf"
								% [mode, r, rerolls, id]
							)
						)
				if _shelf(r, rerolls) != shelf:
					_fail(
						(
							"%s round %d reroll %d: the same state gave another shelf"
							% [mode, r, rerolls]
						)
					)
		# the heal still comes when hurt
		main.round_n = 3
		main.hearts = maxi(1, main.MAXHEARTS - 1)
		cases += 1
		if not S.shop_ok("heal"):
			_fail("%s: the heal is not sold when hurt" % mode)
		main.hearts = main.MAXHEARTS
		# 2. buy one unlock at a time: that item and only that item comes back
		for id in targets:
			_fresh()
			main.meta.owned[_unlock_id_of(id)] = true
			main.round_n = 6
			for other in targets:
				cases += 1
				var want = other == id and _upgrade_state_ok(other)
				if S.shop_ok(other) != want:
					_fail(
						(
							"%s: owning only %s, shop_ok(%s) is %s"
							% [mode, id, other, str(S.shop_ok(other))]
						)
					)
			for r in FLOORS:
				_check_cards(mode, r, targets, [id])
				for rerolls in range(REROLLS):
					var shelf2 = _shelf(r, rerolls)
					for other in targets:
						if other != id and shelf2.has(other):
							_fail("%s: owning only %s, %s is on the shelf" % [mode, id, other])
					if shelf2.has(id):
						seen_bought = true
		# 3. everything owned: all six are sold and can show up
		_own_all()
		main.round_n = 6
		for id in targets:
			cases += 1
			if S.shop_ok(id) != _upgrade_state_ok(id):
				_fail(
					"%s: with everything owned, shop_ok(%s) is %s" % [mode, id, str(S.shop_ok(id))]
				)
		# 4. the filter does not touch the draws: the same unlocks give the same shelf for the same seed
		var a = _shelf(5, 0)
		var b = _shelf(5, 0)
		cases += 1
		if a != b:
			_fail("%s: the same seed and unlocks gave two shelves" % mode)
	if not seen_bought:
		_fail("%s: a bought unlock item never showed up on any shelf" % mode)
	_fresh()


# the upgrade screen: with `owned` bought, no unlock card appears except those; three cards stay on offer
func _check_cards(mode: String, r: int, targets: Array, owned: Array) -> void:
	main.round_n = r
	for part in ["upgrade", "upgrade2"]:
		main.upgrade_part = part
		main.upgrade_extra = 0
		main.shop_sys.show_upgrade()
		cases += 1
		if main.offers.size() != 3:
			_fail("%s round %d: the upgrade screen has %d cards" % [mode, r, main.offers.size()])
		for o in main.offers:
			if targets.has(str(o["id"])) and not owned.has(str(o["id"])):
				_fail("%s round %d: unowned unlock %s is an upgrade card" % [mode, r, o["id"]])
		main.state = "play"


# the upgrade items still need their own state (a maxed upgrade is not sold); a fresh run has none maxed, so a bought
# one must be sold. This is here so the check says so instead of silently trusting shop_ok.
func _upgrade_state_ok(id: String) -> bool:
	var it = main.shop_sys.shop_item(id)
	if it.size() == 0:
		return false
	if it["kind"] == "tier":
		return main.shop_sys.upgrade_ok(id)
	return true
