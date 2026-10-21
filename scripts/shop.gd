extends RefCounted
# Shop: between-round upgrades, the shop and its prices, perks and duos, plus style meter and cash.
# Shared game state stays on main.gd (g); this file holds the logic.

var g = null


func _init(game) -> void:
	g = game


# ------------------------------------------------------------------ upgrades
func upgrade_ok(id: String) -> bool:
	if id == "clip":
		return g.MAXSHELLS < int(g.WEAPONS["dart_gun"]["max_clip"])
	if id == "pump":
		return g.pump_base > float(g.WEAPONS["dart_gun"]["pump_min"]) + 0.01
	if id == "wide":
		return g.up["wide"] < 4
	if id == "heart":
		return g.MAXHEARTS < 4
	if id == "rubber":
		return g.up["rubber"] < 4
	if id == "hype":
		return g.hype_gain < 2.6
	if id == "luck":
		return g.up["luck"] < 0.4
	if id == "speedload":
		return g.up["reload"] < 3
	if id == "dashcd":
		return g.up["dashcd"] < 4
	if id == "magnet":
		return g.up["magnet"] < 2
	return false


func apply_upgrade(id: String) -> void:
	if id == "clip":
		g.MAXSHELLS = mini(
			int(g.WEAPONS["dart_gun"]["max_clip"]),
			g.MAXSHELLS + int(g.WEAPONS["dart_gun"]["clip_step"])
		)
	elif id == "pump":
		g.pump_base = maxf(
			float(g.WEAPONS["dart_gun"]["pump_min"]),
			g.pump_base - float(g.WEAPONS["dart_gun"]["pump_step"])
		)
	elif id == "wide":
		g.up["wide"] += 1
	elif id == "heart":
		g.MAXHEARTS += 1
		g.hearts = mini(g.MAXHEARTS, g.hearts + 1)
	elif id == "rubber":
		g.up["rubber"] += 1
	elif id == "hype":
		g.hype_gain += 0.5
	elif id == "luck":
		g.up["luck"] += 0.1
	elif id == "speedload":
		g.up["reload"] += 1
	elif id == "dashcd":
		g.up["dashcd"] += 1
	elif id == "magnet":
		g.up["magnet"] += 1


func upgrade_stat(id: String) -> String:
	if id == "clip":
		return (
			"DARTS %d > %d"
			% [
				g.MAXSHELLS,
				mini(
					int(g.WEAPONS["dart_gun"]["max_clip"]),
					g.MAXSHELLS + int(g.WEAPONS["dart_gun"]["clip_step"])
				)
			]
		)
	if id == "pump":
		return (
			"PUMP %.2fs > %.2fs"
			% [
				g.pump_base,
				maxf(
					float(g.WEAPONS["dart_gun"]["pump_min"]),
					g.pump_base - float(g.WEAPONS["dart_gun"]["pump_step"])
				)
			]
		)
	if id == "wide":
		return "LEVEL %d > %d" % [g.up["wide"], g.up["wide"] + 1]
	if id == "heart":
		return "MAX LIVES %d > %d" % [g.MAXHEARTS, g.MAXHEARTS + 1]
	if id == "rubber":
		return "LEVEL %d > %d" % [g.up["rubber"], g.up["rubber"] + 1]
	if id == "hype":
		return "GAIN x%.1f > x%.1f" % [g.hype_gain, g.hype_gain + 0.5]
	if id == "speedload":
		return "LEVEL %d > %d" % [g.up["reload"], g.up["reload"] + 1]
	if id == "dashcd":
		return (
			"COOLDOWN %.2fs > %.2fs"
			% [g.player_sys.dash_cooldown(), maxf(0.45, g.player_sys.dash_cooldown() - 0.15)]
		)
	if id == "magnet":
		return "LEVEL %d > %d" % [g.up["magnet"], g.up["magnet"] + 1]
	return (
		"DROPS +%d%% > +%d%%"
		% [int(round(g.up["luck"] * 100.0)), int(round(g.up["luck"] * 100.0 + 10.0))]
	)


func enter_upgrade() -> void:
	var pool = []
	for u in g.UPGRADES:
		if upgrade_ok(u["id"]):
			pool.append(u)
	g.offer_shuffle(pool, "upgrade")
	g.offers = pool.slice(0, 3)
	g.state = "upgrade"
	g.state_t = 0.0
	g.clear_pickups()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if g.offers.size() == 0:
		enter_shop()


func pick_upgrade(i: int) -> void:
	if i < 0 or i >= g.offers.size():
		return
	apply_upgrade(g.offers[i]["id"])
	g.sfx.play("pickup")
	g.sfx.v_cheer()
	g.sfx.say("upgrade")
	enter_shop()


# ------------------------------------------------------------------ style meter + cash + perks
func add_style(n: float) -> void:
	if g.state != "play":
		return
	g.style = minf(100.0, g.style + n)
	g.style_idle = 1.6
	g.best_rank = maxi(g.best_rank, style_rank())


func style_rank() -> int:
	return clampi(int(g.style / 20.0), 0, 4)


func style_letter() -> String:
	return ["D", "C", "B", "A", "S"][style_rank()]


# higher style, bigger score: x1.0 at D up to x2.0 at S
func style_mul() -> float:
	return 1.0 + 0.25 * float(style_rank())


func add_cash(n: int) -> void:
	var v = float(n) * (1.0 + 0.08 * float(g.round_n - 1))  # pay grows a little every round, like the shop prices
	if g.perks.has("bounty"):
		v *= 1.35
	g.cash += int(round(v))


func has_duo(nm: String) -> bool:
	for d in g.DUOS:
		if d["name"] == nm:
			return g.perks.has(d["a"]) and g.perks.has(d["b"])
	return false


func perk_name(id: String) -> String:
	for it in g.SHOP_POOL:
		if it["id"] == id:
			return it["name"]
	return id


func shop_item(id: String) -> Dictionary:
	for it in g.SHOP_POOL:
		if it["id"] == id:
			return it
	return {}


func shop_ok(id: String) -> bool:
	var it = shop_item(id)
	if it.size() == 0 or int(it["min"]) > g.round_n:
		return false
	var kind = it["kind"]
	if kind == "heal":
		return g.hearts < g.MAXHEARTS
	if kind == "tier":
		return upgrade_ok(id)
	if kind == "pack":
		return true
	return not g.perks.has(id)


func shop_tag(id: String) -> String:
	for d in g.DUOS:
		if d["a"] == id or d["b"] == id:
			var other = d["b"] if d["a"] == id else d["a"]
			if g.perks.has(other):
				return "DUO: " + d["name"] + " - " + d["desc"]
	for d2 in g.DUOS:
		if d2["a"] == id or d2["b"] == id:
			var other2 = d2["b"] if d2["a"] == id else d2["a"]
			return "PAIRS WITH " + perk_name(other2)
	return ""


func shop_price(it: Dictionary) -> int:
	var v = (
		float(it["cost"]) * (1.0 + 0.12 * float(g.round_n - 1)) * (1.0 + 0.06 * float(g.shop_buys))
	)
	if it["kind"] == "tier":
		v *= 1.0 + 0.45 * float(g.shop_lvl.get(it["id"], 0))
	if g.perks.has("haggler"):
		v *= 0.85
	return maxi(5, int(round(v / 5.0)) * 5)


func reroll_cost() -> int:
	var v = 20 + 15 * g.shop_rerolls
	if g.perks.has("haggler"):
		v = int(v * 0.5)
	return v


func build_shop() -> void:
	var pool = []
	for it in g.SHOP_POOL:
		if shop_ok(it["id"]):
			var c = it.duplicate()
			c["cost"] = shop_price(it)
			c["sold"] = false
			c["perk"] = it["kind"] == "perk"
			c["tag"] = ""
			if c["perk"]:
				c["tag"] = shop_tag(it["id"])
			elif it["kind"] == "tier":
				c["tag"] = upgrade_stat(it["id"])
			c["label"] = {"perk": "PERK", "pack": "NEXT ROUND", "tier": "UPGRADE", "heal": ""}[it["kind"]]
			pool.append(c)
	g.offer_shuffle(pool, "shop%d" % g.shop_rerolls)
	g.shop_items = []
	# 1. something affordable: a heal if you are hurt, otherwise a pack or one of the plain upgrades
	var cheap = null
	for c in pool:
		if c["kind"] == "heal":
			cheap = c
			break
	if cheap == null:
		for c in pool:
			if c["kind"] != "perk":
				cheap = c
				break
	if cheap != null:
		g.shop_items.append(cheap)
	# 2. a perk that completes a duo with something you already own
	for c in pool:
		if g.shop_items.size() < 2 and c["tag"].begins_with("DUO") and not g.shop_items.has(c):
			g.shop_items.append(c)
	# 3. at least one perk on every shelf (once you can afford to think about them)
	if g.round_n >= 2:
		var have_perk = false
		for c in g.shop_items:
			if c["kind"] == "perk":
				have_perk = true
		if not have_perk:
			for c in pool:
				if c["kind"] == "perk" and not g.shop_items.has(c):
					g.shop_items.append(c)
					break
	# 4. fill the rest at random, but never two copies of the same kind of pack
	for c in pool:
		if g.shop_items.size() < 4 and not g.shop_items.has(c):
			g.shop_items.append(c)
	g.offer_shuffle(g.shop_items, "shopfinal%d" % g.shop_rerolls)


func reroll() -> void:
	if g.state != "shop":
		return
	var cost = reroll_cost()
	if g.cash < cost:
		g.add_note("NOT ENOUGH CASH", g.RED)
		g.sfx.play("click")
		return
	g.cash -= cost
	g.shop_rerolls += 1
	build_shop()
	g.menu_sel = 0
	g.sfx.play("pickup")


func enter_shop() -> void:
	g.shop_rerolls = 0
	build_shop()
	g.menu_sel = 0
	g.state = "shop"
	g.state_t = 0.0
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	g.sfx.say("shop")


func leave_shop() -> void:
	if g.state != "shop":
		return
	g.round_n += 1
	g.start_round()


func buy(i: int) -> void:
	if g.state != "shop" or i < 0 or i >= g.shop_items.size():
		return
	var it = g.shop_items[i]
	if it["sold"]:
		g.sfx.play("click")
		return
	if g.cash < it["cost"]:
		g.add_note("NOT ENOUGH CASH", g.RED)
		g.sfx.play("click")
		return
	g.cash -= it["cost"]
	it["sold"] = true
	g.shop_buys += 1
	var id = it["id"]
	var kind = it["kind"]
	if kind == "heal":
		g.hearts = mini(g.MAXHEARTS, g.hearts + int(it["heal"]))
	elif kind == "tier":
		apply_upgrade(id)
		g.shop_lvl[id] = int(g.shop_lvl.get(id, 0)) + 1
	elif kind == "pack":
		for k in it["pending"]:  # what the pack gives next round is listed in data/items.json
			g.pending[k] = it["pending"][k]
		g.add_note(it["name"] + " READY", g.GOLD)
	else:
		g.perks[id] = true
		for d in g.DUOS:
			if (d["a"] == id or d["b"] == id) and has_duo(d["name"]):
				g.add_note("DUO UNLOCKED: " + d["name"], g.GOLD)
				g.sfx.v_cheer()
	g.sfx.play("pickup")
