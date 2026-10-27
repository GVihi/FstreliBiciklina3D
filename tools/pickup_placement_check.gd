extends SceneTree
# Check for where drops come down (README alpha item B8 "Drops stay where the rider fell", and Milestone K, Gameplay
# on open ground: "Pedestrians, cheerleaders and pickups placed on generated arenas"). Run from the project folder:
#   godot --headless --path . --script res://tools/pickup_placement_check.gd
# Optional argument after "--": how many seeds to try (default 20).
# A drop comes down within a short distance of the KILL (where the rider was eliminated), not of the player. On every
# generated arena it puts kills at many walkable points (including right against walls), with the player far away,
# asks for landing spots, and checks that
#   - every landing spot is ground a pickup may lie on (clamp_walk gives it back unchanged)
#   - the way from the kill to the spot crosses no wall (at least 99.5 % of spots: a kill in a one-cell
#     nook may have no better spot)
#   - the spot is within LAND_MAX (4 m) of the kill and, with the player far away, nowhere near the player
#   - several drops from one kill fan out instead of lying on top of each other
#   - a spawned pickup node and its record end up on that spot when it lands
# and that the roundabout follows the same rule (no second path for it), and that the POCKET MAGNET pulls a landed drop
# only when the player is within 3.5 + 3.0 * level metres of it, and never a drop still in flight.
# Exits with status 1 and prints the first problems.

const ArenaGenScript = preload("res://scripts/arena_gen.gd")
const GeneratedArenaScript = preload("res://scripts/arena_generated.gd")
const PickupsScript = preload("res://scripts/pickups.gd")
const MAIN_SCENE = "res://main.tscn"
const POINTS = 60  # kill positions per arena
const SPOTS = 6  # landing spots asked for at each position
const MIN_CLEAR_SHARE = 0.995
const MAX_DISTANCE = PickupsScript.LAND_MAX  # from the kill, never from the player
const FAR_PLAYER = 12.0  # metres: a player this far from the kill gets no drop near them
const FAN_DROPS = 4  # drops from one kill in the fan-out test
const FAN_CLOSE = 0.3  # metres: two drops closer than this lie on top of each other
const MAX_STACKED_SHARE = 0.02

var problems = []
var main = null
var nooks = 0  # landing spots dropped on a kill that stands in a nook
var stacked = 0  # kills where two of the FAN_DROPS drops lie on top of each other
var fans = 0


func _initialize() -> void:
	var count = 20
	var args = OS.get_cmdline_user_args()
	if args.size() > 0:
		count = int(args[0])
	main = load(MAIN_SCENE).instantiate()
	root.add_child(main)
	for i in range(3):
		await process_frame
	seed(99)
	_check_roundabout()
	_check_magnet()
	var spots = 0
	var blocked = 0
	for k in range(count):
		var layout = ArenaGenScript.generate((k * 2654435761 + 31) & 0xFFFFFFFF)
		if layout.is_empty():
			continue
		var r = _check_arena(layout, k)
		spots += r[0]
		blocked += r[1]
	if spots > 0 and float(blocked) / float(spots) > 1.0 - MIN_CLEAR_SHARE:
		_fail(
			(
				"%d of %d landing spots (%.2f %%) have a wall between them and the kill"
				% [blocked, spots, 100.0 * float(blocked) / float(spots)]
			)
		)
	if fans > 0 and float(stacked) / float(fans) > MAX_STACKED_SHARE:
		_fail(
			(
				"%d of %d kills have two drops lying on top of each other (closer than %.1f m)"
				% [stacked, fans, FAN_CLOSE]
			)
		)
	if problems.is_empty():
		print(
			(
				"pickup_placement_check: %d arenas, %d landing spots, %d with a wall in the way, %d on a kill in a nook, %d of %d fans stacked, all on free ground"
				% [count, spots, blocked, nooks, stacked, fans]
			)
		)
		quit(0)
	else:
		print("pickup_placement_check: %d problem(s)" % problems.size())
		for p in problems.slice(0, 12):
			print("  " + p)
		quit(1)


func _fail(text: String) -> void:
	problems.append(text)


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


# the roundabout follows the same rule as the generated arenas: near the kill, on ground a pickup may lie on
func _check_roundabout() -> void:
	if main.arena.rider_pursuit():
		_fail("the roundabout says rider_pursuit(): the check cannot cover it")
		return
	main.start_game()
	main.state = "check"
	var rng = RandomNumberGenerator.new()
	rng.seed = 7
	var start: Vector3 = main.arena.start_position()
	main.player.position = start
	var far_kills = 0
	for i in range(40):
		var kill = main.clamp_walk(
			Vector3(
				start.x + rng.randf_range(-30.0, 30.0), 0.5, start.z + rng.randf_range(-30.0, 30.0)
			),
			"player"
		)
		var spot = main.pickup_sys.landing_spot(0.55, kill)
		var d = _flat(spot, kill)
		if d > MAX_DISTANCE:
			_fail("roundabout: a landing spot is %.1f m from the kill" % d)
			return
		if main.clamp_walk(spot, "pickup").distance_to(spot) > 0.001:
			_fail("roundabout: a landing spot is not on ground a pickup may lie on")
			return
		if _flat(kill, start) >= FAR_PLAYER:
			far_kills += 1
			if _flat(spot, start) < FAR_PLAYER - MAX_DISTANCE - 0.01:
				_fail(
					(
						"roundabout: a drop from a kill %.1f m away came down near the player"
						% _flat(kill, start)
					)
				)
				return
	if far_kills == 0:
		_fail("roundabout: no kill was far enough from the player to test with")


# the magnet pulls a landed drop only from within 3.5 + 3.0 * level metres, never one in flight
func _check_magnet() -> void:
	main.start_game()
	main.state = "check"
	var old_level = main.up["magnet"]
	var ppos = Vector3(0.0, 0.0, 0.0)
	main.player.position = ppos
	for level in [0, 1, 2]:
		main.up["magnet"] = level
		var reach = 3.5 + 3.0 * float(level)
		for dist in [reach - 1.0, reach + 1.0]:
			var pulled = _landed_drop_pulled(ppos + Vector3(dist, 0.0, 0.0))
			var should = level > 0 and dist < reach
			if pulled != should:
				_fail(
					(
						"magnet level %d: a landed drop %.1f m from the player %s (reach %.1f m)"
						% [
							level,
							dist,
							"was pulled" if pulled else "was not pulled",
							reach if level > 0 else 0.0
						]
					)
				)
	# a drop still in flight is never pulled, even next to a level 2 magnet
	main.up["magnet"] = 2
	main.pickups.clear()
	var near = ppos + Vector3(3.0, 0.0, 0.0)
	main.pickup_sys.spawn_pickup("ammo", near + Vector3(0.0, 1.0, 0.0))
	if main.pickups.size() == 1:
		var pk = main.pickups[0]
		var before: Vector3 = pk["land"]
		main.pickup_sys.update_pickups(0.1)
		if pk["landed"]:
			_fail("magnet: the drop landed after 0.1 s, the in flight test cannot run")
		elif pk["land"].distance_to(before) > 0.0001:
			_fail("magnet: a drop still in flight was pulled towards the player")
		pk["node"].queue_free()
	main.pickups.clear()
	main.up["magnet"] = old_level


# makes one landed drop at `at`, runs 0.1 s of update_pickups, and says whether it moved
func _landed_drop_pulled(at: Vector3) -> bool:
	main.pickups.clear()
	main.pickup_sys.spawn_pickup("ammo", at + Vector3(0.0, 1.0, 0.0))
	if main.pickups.size() != 1:
		return false
	var pk = main.pickups[0]
	pk["landed"] = true
	pk["rest"] = 0.0
	pk["land"] = at
	pk["pos"] = at
	main.pickup_sys.update_pickups(0.1)
	var moved = _flat(pk["land"], at) > 0.0001
	pk["node"].queue_free()
	main.pickups.clear()
	return moved


# returns [spots asked for, spots with a wall in the way]
func _check_arena(layout: Dictionary, k: int) -> Array:
	var arena = GeneratedArenaScript.new(layout)
	main.arena = arena
	main.state = "check"
	var half = float(layout["cells"]) * float(layout["cell"]) / 2.0
	var rng = RandomNumberGenerator.new()
	rng.seed = 1000 + k
	var spots = 0
	var blocked = 0
	for n in range(POINTS):
		var kill = Vector3(rng.randf_range(-half, half), 0.5, rng.randf_range(-half, half))
		kill = arena.clamp_walk(kill, "player")
		if n % 3 == 0:  # a kill right against a wall: push a point into the nearest building and clamp it back
			kill = arena.clamp_walk(kill + Vector3(0.9, 0.0, 0.0), "player")
		# the player stands at the far corner of the arena, wherever that is walkable
		var player = arena.clamp_walk(Vector3(-kill.x, 0.0, -kill.z), "player")
		main.player.position = player
		main.pickups.clear()
		var far = _flat(kill, player) >= FAR_PLAYER
		for s in range(SPOTS):
			var spot = main.pickup_sys.landing_spot(0.55, kill)
			spots += 1
			if arena.clamp_walk(spot, "pickup").distance_to(spot) > 0.001:
				# only a kill standing in a nook (no room for the pickup margin anywhere near) may have a spot
				# that is not pickup ground: it is then on the kill, on ground a rider can stand on
				var feet_ok = (
					arena.clamp_walk(spot, "player").distance_to(spot) < 0.001
					and _flat(spot, kill) < 1.0
				)
				if not feet_ok:
					_fail(
						(
							"arena %d: a landing spot at %s is not ground a pickup may lie on"
							% [k, spot]
						)
					)
				else:
					nooks += 1
			var d = _flat(spot, kill)
			if d > MAX_DISTANCE:
				_fail("arena %d: a landing spot is %.1f m from the kill at %s" % [k, d, kill])
			if far and _flat(spot, player) < FAR_PLAYER - MAX_DISTANCE - 0.01:
				_fail(
					(
						"arena %d: a drop from a kill %.1f m away came down near the player"
						% [k, _flat(kill, player)]
					)
				)
			if not main.pickup_sys.way_clear(kill, spot):
				blocked += 1
		# several drops from one kill: each is recorded, so the next one avoids it
		main.pickups.clear()
		for f in range(FAN_DROPS):
			main.pickup_sys.spawn_pickup("ammo", kill + Vector3(0.0, 0.5, 0.0))
		fans += 1
		var lands = []
		for pk in main.pickups:
			lands.append(pk["land"])
		var on_top = false
		for a in range(lands.size()):
			for b in range(a + 1, lands.size()):
				if _flat(lands[a], lands[b]) < FAN_CLOSE:
					on_top = true
		if on_top:
			stacked += 1
		for pk in main.pickups:
			pk["node"].queue_free()
		main.pickups.clear()
	# one real pickup: it lands where its record says, near the kill and not by the player, and the node follows
	var kill = arena.start_position() + Vector3(0.0, 1.0, 0.0)
	main.player.position = arena.clamp_walk(Vector3(-kill.x + 20.0, 0.0, -kill.z + 20.0), "player")
	main.pickups.clear()
	main.pickup_sys.spawn_pickup("ammo", kill)
	if main.pickups.size() != 1:
		_fail("arena %d: spawn_pickup did not record a pickup" % k)
	else:
		var pk = main.pickups[0]
		if _flat(pk["land"], kill) > MAX_DISTANCE:
			_fail(
				(
					"arena %d: the pickup's landing spot is %.1f m from the kill"
					% [k, _flat(pk["land"], kill)]
				)
			)
		main.pickup_sys.update_pickups(pk["T"] + 0.1)
		if not pk["landed"]:
			_fail("arena %d: the pickup has not landed after its flight time" % k)
		elif arena.obstacle_at(pk["pos"]):
			_fail("arena %d: the pickup landed on ground it cannot lie on" % k)
		elif _flat(pk["pos"], pk["land"]) > 0.001:
			_fail("arena %d: the pickup did not come to rest on its landing spot" % k)
		pk["node"].queue_free()
		main.pickups.clear()
	return [spots, blocked]
