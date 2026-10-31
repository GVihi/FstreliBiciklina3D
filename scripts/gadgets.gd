extends RefCounted
# Gadgets (README Milestone C, "New Gadgets"): the use key of the gadget slot, its uses per round and its cooldown,
# and the first gadget, the banana peel trap. The gadget in the slot is `g.gadget` (an id of data/weapons.json) and its
# numbers are `g.gadget_stats()`; this file never names a gadget outside `use()`, so the next gadget is one more
# `match` arm and a data entry.
# Rules for every gadget (README): one never harms or affects a pedestrian or a cheerleader, and no effect is a chance
# roll, so the same seed plays the same in the Daily Run. Nothing here uses a random number.

const Util = preload("res://scripts/util.gd")
const WeaponSlots = preload("res://scripts/weapon_slots.gd")

var g = null
var uses_left = 0  # uses left this round (only counted when the gadget has a limit: `uses` above 0)
var cool = 0.0  # seconds until the gadget can be used again
var peels = []  # the banana peels on the ground: {"pos": Vector3, "node": Node3D}


func _init(game) -> void:
	g = game


# A new round: the peels of the last one are gone, the cooldown is over and the uses are full again.
func begin_round() -> void:
	clear()
	cool = 0.0
	uses_left = limit()


# Takes every trap off the ground (a new round, a new run, back to the title).
func clear() -> void:
	for p in peels:
		p["node"].queue_free()
	peels.clear()


# uses per round of the gadget in the slot; 0 = no limit, and 0 for an empty slot
func limit() -> int:
	return int(g.gadget_stats().get("uses", 0))


# true when the slot holds a gadget
func has_gadget() -> bool:
	return not g.gadget_stats().is_empty()


# true when the gadget can be used right now (a round is running, the game is not paused, the cooldown is over and
# there is a use left)
func ready() -> bool:
	if not has_gadget() or g.state != "play" or g.paused:
		return false
	if cool > 0.0:
		return false
	return limit() == 0 or uses_left > 0


# The use key (G, and D-pad up on a gamepad). Returns true when the gadget was used. A key press with an empty slot
# does nothing at all; a gadget that is cooling down or out of uses makes a click.
func use() -> bool:
	if not has_gadget() or g.state != "play" or g.paused:
		return false
	if not ready():
		g.sfx.play("click")
		return false
	var st = g.gadget_stats()
	var used = false
	match g.gadget:
		"banana_peel":
			used = place_peel(st)
	if not used:
		return false
	cool = float(st["cooldown"])
	if limit() > 0:
		uses_left -= 1
	return true


# What the HUD shows for the gadget slot: its name, the key and the state ("" for an empty slot).
func hud_text() -> String:
	if not has_gadget():
		return ""
	var t = WeaponSlots.gadget_label(g.gadget)
	if limit() > 0:
		t += "  %d/%d" % [uses_left, limit()]
	if limit() > 0 and uses_left <= 0:
		return t + "  EMPTY"
	if cool > 0.0:
		return t + "  %.1fs" % cool
	return t + "  [G]"


func update(dt: float) -> void:
	if cool > 0.0:
		cool = maxf(0.0, cool - dt)
	update_peels()


# ---- banana peel trap


# Drops a peel `place_dist` metres in front of the player, on the ground. Ground a rider cannot ride on (inside a
# building) is no place for a trap, so the peel goes at the player's feet then.
func place_peel(st: Dictionary) -> bool:
	var fwd = Vector3(-sin(g.yaw), 0.0, -cos(g.yaw))
	var at: Vector3 = g.player.position + fwd * float(st["place_dist"])
	at.y = 0.0
	if g.arena.obstacle_at(at):
		at = g.player.position
		at.y = 0.0
	var root = build_peel()
	root.rotation.y = g.yaw
	g.add_child(root)
	root.position = at + Vector3(0.0, 0.04, 0.0)
	peels.append({"pos": at, "node": root})
	g.sfx.play("click")
	return true


# A flat yellow peel with a bright ring round it, so the trap can be seen on every arena style.
func build_peel() -> Node3D:
	var root = Node3D.new()
	var skin = Util.sphere(root, 0.5, Vector3.ZERO, Util.mat(Color("#f2d230")))
	skin.scale = Vector3(1.0, 0.16, 0.7)
	var tip = Util.box(
		root, Vector3(0.14, 0.05, 0.14), Vector3(0.45, 0.07, 0.0), Util.mat(Color("#5a3b14"))
	)
	tip.rotation.y = 0.5
	var ring = Util.torus(root, 0.62, 0.7, Vector3.ZERO, Util.unshaded(Color("#ffe14d")))
	ring.scale = Vector3(1.0, 0.2, 1.0)
	return root


# The first rider that rides over a peel crashes and is stunned: it stops, cannot throw and stands still for
# `stun_time` seconds, then rides on. The peel is used up. Only riders are looked at, so a pedestrian or a cheerleader
# is never affected, and a rider that is already stunned, leaving or hidden in a tunnel does not set one off.
func update_peels() -> void:
	if peels.is_empty():
		return
	var st = g.gadget_stats()
	var radius = float(st.get("trigger_radius", 1.3))
	var stun = float(st.get("stun_time", 3.0))
	for i in range(peels.size() - 1, -1, -1):
		var p = peels[i]
		for r in g.riders:
			if r["mode"] != "fly" or r["hidden"] or r.get("stun_t", 0.0) > 0.0:
				continue
			var d = Vector2(r["pos"].x - p["pos"].x, r["pos"].z - p["pos"].z).length()
			if d < radius:
				crash(r, stun)
				p["node"].queue_free()
				peels.remove_at(i)
				break


func crash(r: Dictionary, stun: float) -> void:
	r["stun_t"] = stun
	r["wind_t"] = 0.0  # a rider that was winding up a throw drops it
	var wpos = r["pos"] + Vector3(0.0, 1.0, 0.0)
	r["flash"] = 0.15
	g.set_flash(r["model"]["root"], true)
	g.sfx.play3d("thud", wpos)
	g.sfx.play3d("clank2", wpos)
	g.add_popup(wpos + Vector3(0.0, 1.2, 0.0), "CRASHED  STUNNED", g.WHITE, true)
	g.fx_sys.burst(wpos, 8, ["#ffe14d"], 3.0, 0.3, 0.4, 0.06)
