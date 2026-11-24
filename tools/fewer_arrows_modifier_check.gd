extends SceneTree
# Check for the FEWER ARROWS round modifier (README Milestone D, MD7.4). Run from the project folder:
#   godot --headless --path . --script res://tools/fewer_arrows_modifier_check.gd
# Exits with status 1 and prints the first problems.
#
# A round whose node holds the "fewer_arrows" modifier draws the edge arrows for the FEWER_ARROWS_MAX (3) strongest
# threats instead of MAX_ARROWS (8): the HUD reads Threats.arrow_limit(has_modifier("fewer_arrows")). The radar and
# the rider bell read the whole threat list and are not touched, and the modifier draws no random number. Checked
# here, on a generated arena (no modifier is built in, the node is given it):
#   - Threats.arrow_limit is 8 without the modifier and 3 with it, and never below 1;
#   - in a FEWER ARROWS round twelve riders behind the player give 3 arrows, the same 3 strongest ones the round
#     without the modifier draws first (which gives 8), and the round after, without the modifier, gives 8 again;
#   - one rider gives one arrow and two riders two arrows: the arrows are thinned out, never switched off;
#   - the threat list (what the radar reads) and the rider bell's ranking are the same with the modifier and without;
#   - the name is written FEWER ARROWS, and the row in data/map_rules.json is there and, at weight 0, moves no map.

const MapGen = preload("res://scripts/map_gen.gd")
const Threats = preload("res://scripts/threats.gd")
const RiderWarning = preload("res://scripts/rider_warning.gd")

const SEEDS = [0x9E378A43, 1, 2]
const CROWD = 12  # riders behind the player: more than either limit

var bad: Array = []
var main = null


func _initialize() -> void:
	_check_limit()
	await _check_rounds()
	_check_rules()
	if bad.is_empty():
		print(
			"fewer_arrows_modifier_check: a FEWER ARROWS round draws 3 edge arrows, every other round 8"
		)
		quit(0)
	else:
		print("fewer_arrows_modifier_check: %d problem(s)" % bad.size())
		for p in bad.slice(0, 12):
			print("  " + p)
		quit(1)


func _boot() -> void:
	main = load("res://main.tscn").instantiate()
	main.generated_arena = true
	root.add_child(main)
	for i in range(3):
		await process_frame
	seed(5)


# starts the round of the first node of the map (a normal fight)
func _play_first_node() -> void:
	main.map_floor = 0
	main.map_lane = 0
	main.round_n = 1
	main.start_round()
	main.hits.fill(true)


# the one function that decides how many arrows the HUD may draw
func _check_limit() -> void:
	if Threats.MAX_ARROWS != 8:
		bad.append("MAX_ARROWS is %d, expected 8" % Threats.MAX_ARROWS)
	if Threats.arrow_limit(false) != Threats.MAX_ARROWS:
		bad.append(
			"a round without the modifier is limited to %d arrows" % Threats.arrow_limit(false)
		)
	if Threats.arrow_limit(true) != 3:
		bad.append(
			"a FEWER ARROWS round is limited to %d arrows, expected 3" % Threats.arrow_limit(true)
		)
	if Threats.arrow_limit(true) < 1:
		bad.append("a FEWER ARROWS round may draw no arrow at all")
	if Threats.FEWER_ARROWS_MAX >= Threats.MAX_ARROWS:
		bad.append("FEWER_ARROWS_MAX is not fewer than MAX_ARROWS")


# a rider on open ground at pos, riding at the player, made the way tools/threat_check.gd makes one
func _rider(pos: Vector3, yaw: float) -> void:
	var r = main.rider_sys.spawn_rider(0, 1)
	r["can_throw"] = false
	r["pos"] = pos
	r["yaw"] = yaw
	r["hidden"] = false
	r["entered"] = true
	r["ride_speed"] = 8.0
	r["mode"] = "fly"


# n riders behind the player (off screen), the farthest first, all riding at the player; the round's own riders go
func _crowd(n: int) -> void:
	main.clear_riders()
	main.clear_bosses()
	main.state = "play"
	main.force_captured = true
	main.player.position = main.arena.start_position()
	main.yaw = 0.0
	main.pitch = 0.0
	var behind = Vector3(0.0, 0.0, 1.0)  # the camera looks along -z at yaw 0, so +z is behind it
	for i in range(n):
		var p: Vector3 = main.player.position + behind * (12.0 + 4.0 * float(n - 1 - i))
		_rider(p, main.rider_sys.yaw_of(-behind))


# n riders behind the player: the threat list and the bell's ranking at once, then the arrows the real HUD drew a few
# frames later
func _snapshot(n: int) -> Dictionary:
	_crowd(n)
	var list = main.threat_list()
	var bell = RiderWarning.ranked(list, main.player.position, main.yaw)
	for f in range(4):
		await process_frame
	return {"arrows": main.hud.arrows.duplicate(), "threats": str(list), "bell": str(bell)}


func _check_rounds() -> void:
	await _boot()
	if main.modifier_names(["fewer_arrows"]) != ["FEWER ARROWS"]:
		bad.append(
			(
				"fewer_arrows is written %s, expected [FEWER ARROWS]"
				% str(main.modifier_names(["fewer_arrows"]))
			)
		)
	for seed_value in SEEDS:
		var tag = "seed %X" % seed_value
		main.heat = 0
		main.start_game(false, seed_value)
		main.hits.resize(400)
		main.hits.fill(false)
		if main.run_map.is_empty():
			bad.append("%s: no run map" % tag)
			continue
		var first: Dictionary = main.run_map["floors"][0][0]["content"]
		var saved_mods = first["modifiers"]
		# a round without the modifier: all 8 arrows
		first["modifiers"] = []
		_play_first_node()
		if main.has_modifier("fewer_arrows"):
			bad.append("%s: has_modifier('fewer_arrows') is true in a round without it" % tag)
		var plain: Dictionary = await _snapshot(CROWD)
		if plain["arrows"].size() != Threats.MAX_ARROWS:
			(
				bad
				. append(
					(
						"%s: %d riders behind the player gave %d arrows without the modifier, expected %d"
						% [tag, CROWD, plain["arrows"].size(), Threats.MAX_ARROWS]
					)
				)
			)
		# a FEWER ARROWS round: 3 arrows, the strongest ones
		first["modifiers"] = ["fewer_arrows"]
		_play_first_node()
		if not main.has_modifier("fewer_arrows"):
			bad.append("%s: has_modifier('fewer_arrows') is false" % tag)
		var fewer: Dictionary = await _snapshot(CROWD)
		_check_fewer("%s, fewer_arrows" % tag, plain, fewer)
		# thinned out, never switched off
		for n in [1, 2]:
			var few: Dictionary = await _snapshot(n)
			if few["arrows"].size() != n:
				(
					bad
					. append(
						(
							"%s, fewer_arrows: %d rider(s) behind the player gave %d arrow(s), expected %d"
							% [tag, n, few["arrows"].size(), n]
						)
					)
				)
		# the round after, without the modifier, is back to 8
		first["modifiers"] = []
		_play_first_node()
		if main.has_modifier("fewer_arrows"):
			bad.append("%s: has_modifier('fewer_arrows') is still true in the round after" % tag)
		var after: Dictionary = await _snapshot(CROWD)
		if after["arrows"].size() != Threats.MAX_ARROWS:
			bad.append(
				(
					"%s: the round after gave %d arrows, expected %d"
					% [tag, after["arrows"].size(), Threats.MAX_ARROWS]
				)
			)
		first["modifiers"] = saved_mods
	main.queue_free()
	await process_frame


# the FEWER ARROWS round drew 3 arrows, they are the first 3 of the plain round's, and the radar's list and the
# bell's ranking are untouched
func _check_fewer(where: String, plain: Dictionary, fewer: Dictionary) -> void:
	var a: Array = fewer["arrows"]
	var b: Array = plain["arrows"]
	if a.size() != Threats.FEWER_ARROWS_MAX:
		bad.append(
			(
				"%s: %d riders behind the player gave %d arrows, expected %d"
				% [where, CROWD, a.size(), Threats.FEWER_ARROWS_MAX]
			)
		)
	for i in range(mini(a.size(), b.size())):
		if (
			a[i]["kind"] != b[i]["kind"]
			or absf(a[i]["dist"] - b[i]["dist"]) > 0.75
			or absf(a[i]["strength"] - b[i]["strength"]) > 0.05
		):
			(
				bad
				. append(
					(
						"%s: arrow %d is not the plain round's arrow %d (%.1f m, %.2f against %.1f m, %.2f)"
						% [
							where,
							i,
							i,
							a[i]["dist"],
							a[i]["strength"],
							b[i]["dist"],
							b[i]["strength"]
						]
					)
				)
			)
			break
	if plain["threats"] != fewer["threats"]:
		bad.append("%s: the threat list (the radar's) changed with the modifier" % where)
	if plain["bell"] != fewer["bell"]:
		bad.append("%s: the rider bell's ranking changed with the modifier" % where)


# the row is in the rules, and at weight 0 it moves no map
func _check_rules() -> void:
	var rules = MapGen.load_rules()
	var row = rules["content"]["modifiers"]["types"].get("fewer_arrows", {})
	if row.is_empty():
		bad.append("there is no fewer_arrows row in modifiers.types of data/map_rules.json")
		return
	if not row.has("weight") or not row.has("min_floor"):
		bad.append("the fewer_arrows row has no weight or no min_floor: %s" % str(row))
		return
	if row.has("forces_theme"):
		bad.append("the fewer_arrows row forces a theme: %s" % str(row))
	if int(row["weight"]) != 0:
		return  # turned on in MD7.6, where map_check checks how often it turns up
	var plain = rules.duplicate(true)
	plain["content"]["modifiers"]["types"].erase("fewer_arrows")
	for n in range(40):
		var seed_value = (n * 40503 + 7) & 0xFFFFFFFF
		var gates = 2 + (seed_value % 4)
		var m = MapGen.generate(seed_value, plain, gates)
		var w = MapGen.generate(seed_value, rules, gates)
		if m.is_empty() or w.is_empty():
			bad.append("seed %08X: no map" % seed_value)
			continue
		if JSON.stringify(m, "", true) != JSON.stringify(w, "", true):
			bad.append("seed %08X: the map changed with the weight 0 row in the rules" % seed_value)
			break
