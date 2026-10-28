extends RefCounted
# Pickups: drops from kills, floating collectibles, magnet and collection.
# Shared game state stays on main.gd (g); this file holds the logic.

const Models = preload("res://scripts/models.gd")
const Needs = preload("res://scripts/needs.gd")

const LAND_TRIES = 12  # directions tried for a landing spot
const LAND_NEAR = 0.5  # metres: a drop comes down at least this far from the kill ...
const LAND_FAR = 2.0  # ... and at most this far (before a wall pushes the spot out)
const LAND_MAX = 4.0  # metres: a landing spot is never further from the kill than this, even after a push out of a wall
const LAND_APART = 0.7  # metres: drops from one kill try not to lie closer to each other than this
const LAND_STEP = 0.5  # metres between the points checked on the way from the kill to the spot
# a landed drop can lie far from the player now, so it stays longer (first guess, tune by playing: B8.3)
const BLINK_AFTER = 11.0  # seconds on the ground until it starts to blink (the last 3 s before it vanishes)
const VANISH_AFTER = 14.0  # seconds on the ground until it is gone
const MAX_ON_FIELD = 10  # drops on the field at once; a kill with more than this loses its extra drops

var g = null


func _init(game) -> void:
	g = game


# true when a drop of this kind can change the next round for what the player holds now (DROP_NEEDS, needs.gd)
func drop_ok(t: String) -> bool:
	return Needs.ok(g.DROP_NEEDS.get(t, {}), g)


# The drop that is really spawned for a drawn kind: the kind itself when it can matter, otherwise cash (what a heart
# has always become at full hearts) when cash can matter, otherwise "" (nothing). Only the pool changes, never the draw.
func matter_drop(t: String) -> String:
	if drop_ok(t):
		return t
	if t != "cash" and drop_ok("cash"):
		return "cash"
	return ""


func maybe_drop(pos: Vector3, chance: float) -> void:
	if g.state != "play" or g.pickups.size() >= MAX_ON_FIELD:
		return
	if randf() > chance + g.up["luck"]:
		return
	var t = matter_drop(g.pick_one(g.DROPS))
	if t != "":
		spawn_pickup(t, pos)


# every defeated rider feeds you: usually ammo, sometimes cash or a life, now and then a power-up
func drop_kill(pos: Vector3, tough: bool) -> void:
	if g.state != "play":
		return
	var rank = g.shop_sys.style_rank()
	var drops = []
	if randf() < 0.28 + 0.04 * float(rank) + (0.15 if g.perks.has("scavenger") else 0.0):
		drops.append("ammo")
	if randf() < 0.07 + 0.02 * float(rank):
		drops.append("heart")  # kept only while hearts are missing, by the drop test below
	if randf() < 0.15:
		drops.append("cash")
	if tough and g.perks.has("salvage"):
		if not drops.has("ammo"):
			drops.append("ammo")
		if g.shop_sys.has_duo("SCRAPYARD"):
			drops.append("ammo")
			drops.append("cash")
	if randf() < (0.7 if tough else 0.12) + g.up["luck"]:
		drops.append(g.pick_one(["rapid", "big", "slow", "shield"]))
	for t in drops:
		if g.pickups.size() < MAX_ON_FIELD and drop_ok(t):  # a drop that cannot matter now is simply not dropped
			spawn_pickup(t, pos)


# Where a pickup comes down: LAND_NEAR to LAND_FAR (0.5 to 2 m) from `kill`, the place where the rider was
# eliminated, in a random direction, kept on ground a pickup may lie on (`clamp_walk`). The player is not
# involved: the loot stays where the fight was and the player has to walk to it. Same rule on every arena. On
# open ground (a generated arena) the spot must also be reachable: the way from the kill to it crosses no wall,
# because a spot pushed out of a building can end up round the corner or on the far side of a block. A spot
# pushed further than LAND_MAX from the kill does not count either. Up to LAND_TRIES directions are tried; the
# first spot that passes wins, and a spot that lies on another drop (within LAND_APART) is only used when no
# other direction works (then the one furthest from the other drops), so several drops from one kill fan out.
# If no direction works, the drop lies on the kill itself (kept off the wall, or just where a rider can stand
# when even that is a nook).
func landing_spot(y_land: float, kill: Vector3) -> Vector3:
	var open = g.arena.rider_pursuit()
	var crowded_spot = null  # the spot that passed except that it lies on another drop, furthest from the other drops
	var crowded_gap = -1.0
	for _k in range(LAND_TRIES):
		var la = randf() * TAU
		var ld = randf_range(LAND_NEAR, LAND_FAR)
		var land = g.clamp_walk(
			Vector3(kill.x + sin(la) * ld, y_land, kill.z - cos(la) * ld), "pickup"
		)
		# a wall pushes a spot out to the nearest free ground, which can be far or round a corner: it only
		# counts when it is within reach and (on open ground) nothing is in the way
		if Vector2(land.x - kill.x, land.z - kill.z).length() > LAND_MAX:
			continue
		if open and not way_clear(kill, land):
			continue
		var gap = gap_to_drops(land)
		if gap < LAND_APART:
			if gap > crowded_gap:
				crowded_spot = land
				crowded_gap = gap
			continue
		return land
	if crowded_spot != null:
		return crowded_spot
	# boxed in (the kill is in a nook with no room for the pickup margin, which clamp_walk would send 10 m
	# away): drop it on the kill, on ground a rider can stand on, so it can always be picked up
	var feet = g.clamp_walk(Vector3(kill.x, y_land, kill.z), "pickup")
	if Vector2(feet.x - kill.x, feet.z - kill.z).length() > LAND_MAX:
		feet = g.clamp_walk(Vector3(kill.x, y_land, kill.z), "player")
	return feet


# the flat distance from the spot to the nearest other drop (its landing spot), or a large number when there is none
func gap_to_drops(spot: Vector3) -> float:
	var gap = 1000.0
	for pk in g.pickups:
		var l: Vector3 = pk["land"]
		gap = minf(gap, Vector2(l.x - spot.x, l.z - spot.z).length())
	return gap


# true if the straight way from a to b (sampled every LAND_STEP metres) crosses nothing a boss cannot walk on
func way_clear(a: Vector3, b: Vector3) -> bool:
	var n = maxi(1, int(ceil(a.distance_to(b) / LAND_STEP)))
	for i in range(1, n + 1):
		if g.arena.obstacle_at(a.lerp(b, float(i) / float(n))):
			return false
	return true


func spawn_pickup(t: String, pos: Vector3) -> void:
	var inf = g.DROP_INFO[t]
	var m = Models.build_pickup(inf["col"], inf["ch"])
	g.add_child(m["root"])
	var T = 1.0
	var y_land = 0.55
	var land = landing_spot(y_land, pos)  # lands within a short distance of the kill, wherever the player is
	var vel = Vector3((land.x - pos.x) / T, 4.9 * T + (y_land - pos.y) / T, (land.z - pos.z) / T)
	g.pickups.append(
		{
			"type": t,
			"node": m["root"],
			"m": m,
			"start": pos,
			"vel0": vel,
			"t": 0.0,
			"T": T,
			"pos": pos,
			"land": land,
			"landed": false,
			"rest": 0.0
		}
	)
	m["root"].position = pos


func collect_pickup(pk: Dictionary) -> void:
	var i = g.pickups.find(pk)
	if i >= 0:
		g.pickups.remove_at(i)
	var inf = g.DROP_INFO[pk["type"]]
	g.add_popup(pk["pos"] + Vector3(0, 0.6, 0), inf["name"], inf["col"])
	var t = pk["type"]
	if t == "heart":
		g.hearts = mini(g.MAXHEARTS, g.hearts + 1)
	elif t == "rapid":
		g.buffs["rapid"] = 8.0
	elif t == "big":
		g.buffs["big"] = 10.0
	elif t == "slow":
		g.buffs["slow"] = 6.0
	elif t == "shield":
		g.buffs["shield"] = 1.0
	elif t == "ammo":
		g.combat_sys.add_shells(4 if g.perks.has("scavenger") else 2)
	else:
		g.score += 500 * (2 if g.hype_t > 0.0 else 1)
		g.hi_check()
		g.shop_sys.add_cash(15)
	g.sfx.play("pickup")
	g.add_hype(8.0)
	g.cheer = maxf(g.cheer, 0.6)
	pk["node"].queue_free()


func update_pickups(dt: float) -> void:
	for i in range(g.pickups.size() - 1, -1, -1):
		var pk = g.pickups[i]
		var node: Node3D = pk["node"]
		pk["t"] += dt
		if not pk["landed"]:
			var t: float = pk["t"]
			var v0: Vector3 = pk["vel0"]
			var s0: Vector3 = pk["start"]
			var p = s0 + v0 * t + Vector3(0.0, -4.9 * t * t, 0.0)
			pk["pos"] = p
			if t >= pk["T"]:
				pk["landed"] = true
				pk["rest"] = 0.0
				pk["pos"] = pk["land"]
		else:
			pk["rest"] += dt
			var l: Vector3 = pk["land"]
			if g.up["magnet"] > 0:
				var dl = Vector3(g.player.position.x - l.x, 0.0, g.player.position.z - l.z)
				var dn = dl.length()
				if dn > 0.05 and dn < 3.5 + 3.0 * float(g.up["magnet"]):
					l += dl / dn * minf(6.5 * dt, dn)
					pk["land"] = l
			pk["pos"] = Vector3(l.x, l.y + sin(g.time * 5.0 + i) * 0.06, l.z)
		var pos: Vector3 = pk["pos"]
		node.position = pos
		node.rotation.y += dt * 2.5
		node.visible = true
		if pk["landed"] and pk["rest"] > BLINK_AFTER and int(g.time * 10.0) % 2 == 0:
			node.visible = false
		if (
			Vector2(pos.x - g.player.position.x, pos.z - g.player.position.z).length() < 1.0
			and pos.y < 1.6
		):
			collect_pickup(pk)
			continue
		if pk["landed"] and pk["rest"] > VANISH_AFTER:
			pk["node"].queue_free()
			g.pickups.remove_at(i)
