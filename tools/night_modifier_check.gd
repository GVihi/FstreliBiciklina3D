extends SceneTree
# Check for the night modifier's theme and radar (README Milestone D, MD5.3). Run from the project folder:
#   godot --headless --path . --script res://tools/night_modifier_check.gd
# Exits with status 1 and prints the first problems.
#
# A round whose node holds the "night" modifier plays under the NIGHT theme whatever theme the node drew, and its radar
# reaches Threats.NIGHT_RADAR_FACTOR (0.6) of the usual range, leaving off what is beyond it. A round without the
# modifier keeps its own theme and exactly the old radar numbers. Checked here:
#   - the radar numbers: with the factor 1.0 (a round without night) radar_fraction is exactly the old formula and
#     nothing is left off; with the night factor the range is 0.6 of the old one, a thing within it is drawn farther
#     out than before and a thing beyond it is left off, not pinned on the rim;
#   - real rounds on generated arenas, in the order no modifier, night, no modifier: the middle one plays under NIGHT
#     with the short radar, the ones around it under the node's own theme with factor 1.0 (so the theme is read
#     from the node and not from the round before, which is what has_modifier still holds when the theme is
#     chosen); the node's stored theme is never changed; a node whose theme is NIGHT but has no modifier gets
#     the look and not the radar;
#   - the edge arrows are not touched: a far threat is still ranked, and _draw_threats does not know the factor;
#   - the themes of a map's nodes are the same with and without the modifier in the rules.

const MapGen = preload("res://scripts/map_gen.gd")
const Content = preload("res://scripts/content.gd")
const Threats = preload("res://scripts/threats.gd")

const SEEDS = [0x9E378A43, 1, 2]

var bad: Array = []
var main = null


func _init() -> void:
	_check_radar_numbers()
	await _check_rounds()
	_check_arrows_untouched()
	_check_map_themes()
	if bad.is_empty():
		print(
			"night_modifier_check: a night round plays under NIGHT with a radar of 0.6 of its range, every other round as before"
		)
		quit(0)
	else:
		print("night_modifier_check: %d problem(s)" % bad.size())
		for p in bad.slice(0, 12):
			print("  " + p)
		quit(1)


func _check_radar_numbers() -> void:
	if Threats.radar_factor(false) != 1.0:
		bad.append(
			(
				"a round without night has the radar factor %s, expected 1.0"
				% Threats.radar_factor(false)
			)
		)
	if not is_equal_approx(Threats.radar_factor(true), 0.6):
		bad.append(
			"a night round has the radar factor %s, expected 0.6" % Threats.radar_factor(true)
		)
	var night = Threats.radar_factor(true)
	for open_ground in [false, true]:
		var where = "open ground" if open_ground else "the roundabout"
		var usual = Threats.RADAR_RANGE_OPEN if open_ground else Threats.RADAR_RANGE_STREET
		var edge = usual * 0.6
		if not is_equal_approx(Threats.radar_range(open_ground, night), edge):
			bad.append(
				(
					"%s: the night range is %s, expected %s"
					% [where, Threats.radar_range(open_ground, night), edge]
				)
			)
		for i in range(0, 241):
			var dist = float(i) * 0.5
			var old = sqrt(minf(dist / usual, 1.0)) if open_ground else minf(dist / usual, 1.0)
			if (
				Threats.radar_fraction(dist, open_ground) != old
				or Threats.radar_fraction(dist, open_ground, 1.0) != old
			):
				bad.append(
					(
						"%s: with the factor 1.0 the radar puts %s m at %s, not at the old %s"
						% [where, dist, Threats.radar_fraction(dist, open_ground, 1.0), old]
					)
				)
				break
			if (
				Threats.radar_hides(dist, open_ground)
				or Threats.radar_hides(dist, open_ground, 1.0)
			):
				bad.append(
					(
						"%s: with the factor 1.0 the radar leaves off something %s m away"
						% [where, dist]
					)
				)
				break
			if absf(dist - edge) < 0.1:
				continue  # right on the rim, where a rounding in 0.6 could go either way
			if Threats.radar_hides(dist, open_ground, night) != (dist > edge):
				bad.append(
					(
						"%s: the night radar (range %s m) %s something %s m away"
						% [where, edge, "keeps" if dist > edge else "leaves off", dist]
					)
				)
				break
			if (
				dist > 0.0
				and dist < edge
				and (
					Threats.radar_fraction(dist, open_ground, night)
					<= Threats.radar_fraction(dist, open_ground)
				)
			):
				bad.append(
					(
						"%s: %s m is not drawn farther out on the night radar than on the usual one"
						% [where, dist]
					)
				)
				break
		if not is_equal_approx(Threats.radar_fraction(edge, open_ground, night), 1.0):
			bad.append(
				(
					"%s: the rim of the night radar is at %s, expected 1.0"
					% [where, Threats.radar_fraction(edge, open_ground, night)]
				)
			)


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


# Draws the HUD, radar included, in the night round just started, with the player 40 m from a cache: inside the
# objectives' sense range (45 m) and beyond the night radar (36 m), so the branch that leaves a cache off runs. A
# script error in it shows in the output (tools/run_checks.py reports that as a failure).
func _draw_hud_in_night_round() -> void:
	var o = main.objective_sys
	if o.caches.is_empty():
		bad.append("the first node has no cache to put beyond the night radar")
		return
	main.player.position = o.caches[0]["pos"] + Vector3(40.0, 0.0, 0.0)
	var dist = o.dist_to(o.caches[0]["pos"])
	if dist >= o.SENSE_RANGE or not Threats.radar_hides(dist, true, Threats.radar_factor(true)):
		bad.append("a cache %s m away is not between the night radar and the sense range" % dist)
	main.hud.size = Vector2(1280, 720)
	main.hud.queue_redraw()
	for i in range(2):
		await process_frame


# what the round just started has to be: the theme, and whether it is a night round with the short radar
func _expect(where: String, theme: int, night: bool) -> void:
	if main.theme_idx != theme:
		bad.append("%s: theme %d, expected %d" % [where, main.theme_idx, theme])
	if main.round_theme() != theme:
		bad.append(
			(
				"%s: round_theme() says %d in the round, expected %d"
				% [where, main.round_theme(), theme]
			)
		)
	if main.has_modifier("night") != night:
		bad.append(
			(
				"%s: has_modifier('night') is %s, expected %s"
				% [where, main.has_modifier("night"), night]
			)
		)
	var factor = Threats.radar_factor(main.has_modifier("night"))
	var want = Threats.NIGHT_RADAR_FACTOR if night else 1.0
	if factor != want:
		bad.append("%s: the radar factor is %s, expected %s" % [where, factor, want])


func _check_rounds() -> void:
	var night_theme = Content.theme_index("NIGHT")
	if night_theme < 0:
		bad.append("there is no NIGHT theme in Content.THEMES")
		return
	await _boot()
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
		var saved_theme = first["theme"]
		var saved_mods = first["modifiers"]
		first["theme"] = 0  # DAY, so a night round is plainly not the node's own theme
		first["modifiers"] = []
		_play_first_node()
		_expect("%s, no modifier" % tag, 0, false)
		first["modifiers"] = ["night"]
		_play_first_node()
		_expect("%s, night" % tag, night_theme, true)
		if seed_value == SEEDS[0]:
			await _draw_hud_in_night_round()
		if int(first["theme"]) != 0:
			bad.append("%s: the node's stored theme became %s" % [tag, first["theme"]])
		first["modifiers"] = []
		_play_first_node()
		_expect("%s, the round after night" % tag, 0, false)
		first["theme"] = night_theme  # a NIGHT-themed node that does not carry the modifier: the look, not the rule
		_play_first_node()
		_expect("%s, a NIGHT-themed node without the modifier" % tag, night_theme, false)
		first["theme"] = saved_theme
		first["modifiers"] = saved_mods
	main.queue_free()
	await process_frame


# the edge arrows keep every threat, however far: Threats.ranked has no factor, and the HUD's arrow drawing does not
# read the night modifier or leave anything off with radar_hides
func _check_arrows_untouched() -> void:
	var far = {"pos": Vector3.ZERO, "kind": "rider", "urg": 0.3, "dist": 55.0, "closing": 0.0}
	var ranked = Threats.ranked([far], true)
	if ranked.size() != 1 or ranked[0]["strength"] < Threats.MIN_STRENGTH:
		bad.append("a threat 55 m away is not ranked for an arrow")
	if not Threats.radar_hides(55.0, true, Threats.radar_factor(true)):
		bad.append(
			"a threat 55 m away is not beyond the night radar, the arrows check proves nothing"
		)
	var src = FileAccess.get_file_as_string("res://scripts/hud.gd")
	var at = src.find("func _draw_threats(")
	if at < 0:
		bad.append("hud.gd has no _draw_threats, the arrows check cannot find the arrows")
		return
	var end = src.find("\nfunc ", at + 10)
	var body = src.substr(at, end - at)
	if body.contains("night") or body.contains("radar_hides") or body.contains("radar_factor"):
		bad.append(
			"_draw_threats reads the night modifier or the radar's range, the arrows must not"
		)


# the modifier moves no theme: a map has the same theme in every node with `night` in the rules (weight 20) and without
func _check_map_themes() -> void:
	var rules = MapGen.load_rules()
	var plain = rules.duplicate(true)
	plain["content"]["modifiers"]["types"].erase("night")
	var lit = rules.duplicate(true)
	lit["content"]["modifiers"]["types"]["night"] = {"weight": 20, "min_floor": 3}
	var night_nodes = 0
	for n in range(40):
		var seed_value = (n * 40503 + 7) & 0xFFFFFFFF
		var gates = 2 + (seed_value % 4)
		var a = MapGen.generate(seed_value, plain, gates)
		var b = MapGen.generate(seed_value, lit, gates)
		if a.is_empty() or b.is_empty():
			bad.append("seed %08X: no map" % seed_value)
			continue
		for f in range(a["floors"].size()):
			for i in range(a["floors"][f].size()):
				var then = a["floors"][f][i]["content"]
				var now = b["floors"][f][i]["content"]
				if int(then["theme"]) != int(now["theme"]):
					bad.append(
						(
							"seed %08X floor %d lane %d: the theme changed from %s to %s"
							% [seed_value, f + 1, i, then["theme"], now["theme"]]
						)
					)
				if now.get("modifiers", []).has("night"):
					night_nodes += 1
	if night_nodes == 0:
		bad.append("no node held night in 40 maps with weight 20, the themes check proves nothing")
