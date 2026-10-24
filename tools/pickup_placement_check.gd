extends SceneTree
# Check for where pickups come down on a generated arena (README Milestone K, Gameplay on open ground:
# "Pedestrians, cheerleaders and pickups placed on generated arenas"). Run from the project folder:
#   godot --headless --path . --script res://tools/pickup_placement_check.gd
# Optional argument after "--": how many seeds to try (default 20).
# On every generated arena it stands the player at many walkable points (including right against walls) and asks
# for landing spots, and checks that
#   - every landing spot is ground a pickup may lie on (clamp_walk gives it back unchanged)
#   - the way from the player to the spot crosses no wall (at least 99.5 % of spots: a player in a one-cell
#     nook may have no better one)
#   - the spot is within reach of the player (at most 8 m: it is thrown 2.2 to 4.8 m, a push out of a wall adds a little)
#   - a spawned pickup node and its record end up on that spot when it lands
# and that on the roundabout a landing spot is still one direction, 2.2 to 4.8 m from the player, as before.
# Exits with status 1 and prints the first problems.

const ArenaGenScript = preload("res://scripts/arena_gen.gd")
const GeneratedArenaScript = preload("res://scripts/arena_generated.gd")
const MAIN_SCENE = "res://main.tscn"
const POINTS = 60  # player positions per arena
const SPOTS = 6  # landing spots asked for at each position
const MIN_CLEAR_SHARE = 0.995
const MAX_DISTANCE = 8.0

var problems = []
var main = null
var nooks = 0  # landing spots dropped at the feet of a player standing in a nook


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
				"%d of %d landing spots (%.2f %%) have a wall between them and the player"
				% [blocked, spots, 100.0 * float(blocked) / float(spots)]
			)
		)
	if problems.is_empty():
		print(
			(
				"pickup_placement_check: %d arenas, %d landing spots, %d with a wall in the way, %d at the feet of a player in a nook, all on free ground"
				% [count, spots, blocked, nooks]
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


# the roundabout draws one direction, 2.2 to 4.8 m from the player, and clamps it
func _check_roundabout() -> void:
	if main.arena.rider_pursuit():
		_fail("the roundabout says rider_pursuit(): the check cannot cover it")
		return
	main.start_game()
	main.state = "check"
	for i in range(40):
		var spot = main.pickup_sys.landing_spot(0.55)
		var d = Vector2(spot.x - main.player.position.x, spot.z - main.player.position.z).length()
		if d > 4.8 + 3.0:
			_fail("roundabout: a landing spot is %.1f m from the player" % d)
			return
		if main.clamp_walk(spot, "pickup").distance_to(spot) > 0.001:
			_fail("roundabout: a landing spot is not on ground a pickup may lie on")
			return


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
		var p = Vector3(rng.randf_range(-half, half), 0.0, rng.randf_range(-half, half))
		p = arena.clamp_walk(p, "player")
		if n % 3 == 0:  # stand right against a wall: push a point into the nearest building and clamp it back
			p = arena.clamp_walk(p + Vector3(0.9, 0.0, 0.0), "player")
		main.player.position = p
		for s in range(SPOTS):
			var spot = main.pickup_sys.landing_spot(0.55)
			spots += 1
			if arena.clamp_walk(spot, "pickup").distance_to(spot) > 0.001:
				# only a player standing in a nook (no room for the pickup margin anywhere near) may have a spot
				# that is not pickup ground: it is then at the player's feet, on ground the player can stand on
				var feet_ok = (
					arena.clamp_walk(spot, "player").distance_to(spot) < 0.001
					and Vector2(spot.x - p.x, spot.z - p.z).length() < 1.0
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
			var d = Vector2(spot.x - p.x, spot.z - p.z).length()
			if d > MAX_DISTANCE:
				_fail("arena %d: a landing spot is %.1f m from the player at %s" % [k, d, p])
			if not main.pickup_sys.way_clear(p, spot):
				blocked += 1
	# one real pickup: it lands where its record says and the node follows
	main.player.position = arena.start_position()
	main.pickups.clear()
	main.pickup_sys.spawn_pickup("ammo", arena.start_position() + Vector3(0.0, 1.0, 0.0))
	if main.pickups.size() != 1:
		_fail("arena %d: spawn_pickup did not record a pickup" % k)
	else:
		var pk = main.pickups[0]
		main.pickup_sys.update_pickups(pk["T"] + 0.1)
		if not pk["landed"]:
			_fail("arena %d: the pickup has not landed after its flight time" % k)
		elif arena.obstacle_at(pk["pos"]):
			_fail("arena %d: the pickup landed on ground it cannot lie on" % k)
		pk["node"].queue_free()
		main.pickups.clear()
	return [spots, blocked]
