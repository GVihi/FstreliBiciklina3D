extends SceneTree
# Check for the look of the rain modifier (README Milestone D, MD6.2). Run from the project folder:
#   godot --headless --path . --script res://tools/rain_look_check.gd
# Exits with status 1 and prints the first problems.
#
# A round whose node holds "rain" is drawn under a greyer, darker sky with a wet ground and streaks around the camera;
# rain forces no theme. Checked here:
#   - the theme function: every theme turned rainy has sky, horizon and ambient colours that are greyer and not
#     brighter than before and no darker than the NIGHT theme's, a sun that is not stronger and not below NIGHT's, the
#     same lamps, lit windows and ambient energy, and the theme it was made from is not changed;
#   - the streak count follows the SHAKE AND FLASH setting: none at 0, STREAKS at 1, never more;
#   - a real round on a generated arena with rain: the node's own theme is kept, the sky is darker than the dry one,
#     the ground parts are drawn with a wet copy of their material (the original is not changed), the streaks are
#     shown while the round is played, follow fx_scale, stay inside their box and are hidden in every other state;
#   - the round after, without rain: the dry sky, the original ground materials and no streaks, and so after
#     apply_theme without rain (the title screen); a NIGHT-themed rain round is not darker than NIGHT.
# What it cannot check is how it looks and what it costs: that is the screenshot and the frame times of MD6.2.

const Content = preload("res://scripts/content.gd")
const Rain = preload("res://scripts/rain.gd")

const SEEDS = [0x9E378A43, 1]
const EPS = 0.0001

var bad: Array = []
var main = null


func _init() -> void:
	_check_rainy_theme()
	_check_streak_count()
	await _check_rounds()
	if bad.is_empty():
		print(
			"rain_look_check: rain is greyer and no darker than NIGHT, the ground is wet, the streaks follow the setting, and all of it is put back"
		)
		quit(0)
	else:
		print("rain_look_check: %d problem(s)" % bad.size())
		for p in bad.slice(0, 12):
			print("  " + p)
		quit(1)


func _saturation(c: Color) -> float:
	return maxf(c.r, maxf(c.g, c.b)) - minf(c.r, minf(c.g, c.b))


func _check_rainy_theme() -> void:
	var night_i = Content.theme_index("NIGHT")
	if night_i < 0:
		bad.append("there is no NIGHT theme in Content.THEMES")
		return
	var low: Dictionary = Content.THEMES[night_i]
	for th in Content.THEMES:
		var tag = "theme %s" % th["name"]
		var before = th.duplicate()
		var rainy = Rain.rainy_theme(th, low)
		if th != before:
			bad.append("%s: rainy_theme changed the theme it was given" % tag)
		for key in ["top", "hor", "amb"]:
			var was: Color = th[key]
			var now: Color = rainy[key]
			if Rain.luma(now) > Rain.luma(was) + EPS:
				bad.append("%s: %s is brighter in rain" % [tag, key])
			if Rain.luma(now) < Rain.luma(low[key]) - EPS and Rain.luma(was) >= Rain.luma(low[key]):
				bad.append("%s: %s is darker than NIGHT's in rain" % [tag, key])
			if _saturation(now) > _saturation(was) + EPS:
				bad.append("%s: %s is not greyer in rain" % [tag, key])
		if float(rainy["sun_e"]) > float(th["sun_e"]) + EPS:
			bad.append("%s: the sun is stronger in rain" % tag)
		if float(rainy["sun_e"]) < minf(float(th["sun_e"]), float(low["sun_e"])) - EPS:
			bad.append("%s: the sun is weaker than NIGHT's in rain" % tag)
		for key in ["lamps", "lit", "amb_e", "sun_x", "sun_y", "name"]:
			if rainy[key] != th[key]:
				bad.append("%s: rain changed %s" % [tag, key])
	# the day is plainly darker in rain: this is what the player sees
	var day: Dictionary = Content.THEMES[0]
	if Rain.luma(Rain.rainy_theme(day, low)["top"]) >= Rain.luma(day["top"]) - 0.01:
		bad.append("a DAY sky is not darker in rain")


func _check_streak_count() -> void:
	if Rain.streak_count(0.0) != 0:
		bad.append("streaks at fx_scale 0: %d, expected 0" % Rain.streak_count(0.0))
	if Rain.streak_count(1.0) != Rain.STREAKS:
		bad.append(
			"streaks at fx_scale 1: %d, expected %d" % [Rain.streak_count(1.0), Rain.STREAKS]
		)
	if Rain.streak_count(5.0) > Rain.STREAKS or Rain.streak_count(-1.0) != 0:
		bad.append("streak_count does not clamp fx_scale to 0..1")
	if Rain.streak_count(0.5) != int(Rain.STREAKS * 0.5):
		bad.append("streaks at fx_scale 0.5: %d" % Rain.streak_count(0.5))


func _boot() -> void:
	main = load("res://main.tscn").instantiate()
	main.generated_arena = true
	root.add_child(main)
	for i in range(3):
		await process_frame
	seed(5)


func _play_first_node() -> void:
	main.map_floor = 0
	main.map_lane = 0
	main.round_n = 1
	main.start_round()
	main.hits.fill(true)


func _ground_materials() -> Dictionary:
	var out = {}
	var parts: Dictionary = main.world.get("ground_parts", {})
	for part_name in Rain.WET_PARTS:
		if parts.has(part_name):
			out[part_name] = parts[part_name].material_override
	return out


func _sky_top() -> Color:
	return main.world["sky_mat"].sky_top_color


# the round just started, as seen after one frame of play: whether it is drawn as a rain round
func _expect_look(where: String, rain: bool, dry_top: Color, dry_ground: Dictionary) -> void:
	main.state = "play"
	main.fx_scale = 1.0
	main.rain_sys.update(0.016)
	var holder = main.rain_sys.holder
	var shown = holder != null and holder.visible
	if shown != rain:
		bad.append("%s: streaks shown is %s, expected %s" % [where, shown, rain])
	var top = _sky_top()
	if rain and Rain.luma(top) >= Rain.luma(dry_top) - 0.01:
		bad.append("%s: the sky is not darker than the dry one" % where)
	if not rain and not top.is_equal_approx(dry_top):
		bad.append("%s: the sky is not the dry one" % where)
	var ground = _ground_materials()
	if ground.is_empty():
		bad.append("%s: the world has no ground parts to get wet" % where)
		return
	for part_name in ground:
		var m = ground[part_name]
		if rain:
			if m == dry_ground[part_name]:
				bad.append("%s: %s is not wet" % [where, part_name])
			elif m.roughness != Rain.WET_ROUGHNESS:
				bad.append("%s: %s has roughness %s" % [where, part_name, m.roughness])
			elif Rain.luma(m.albedo_color) >= Rain.luma(dry_ground[part_name].albedo_color):
				bad.append("%s: %s is not darker wet" % [where, part_name])
		elif m != dry_ground[part_name]:
			bad.append("%s: %s was not put back" % [where, part_name])
	main.state = "title"


func _check_streaks_in_play() -> void:
	var rs = main.rain_sys
	main.state = "play"
	main.fx_scale = 1.0
	rs.update(0.016)
	var mm = rs.holder.multimesh
	if mm.visible_instance_count != Rain.STREAKS:
		bad.append("%d streaks drawn at fx_scale 1" % mm.visible_instance_count)
	rs.update(3.7)  # a long fall: every streak has wrapped round the bottom of the box at least once
	for i in range(mm.visible_instance_count):
		var p: Vector3 = mm.get_instance_transform(i).origin
		if (
			absf(p.x) > Rain.BOX_HALF + EPS
			or absf(p.z) > Rain.BOX_HALF + EPS
			or p.y < -Rain.BOX_BELOW - EPS
			or p.y > Rain.BOX_HEIGHT - Rain.BOX_BELOW + EPS
		):
			bad.append("streak %d is outside its box at %s" % [i, p])
			break
	var cam_pos: Vector3 = main.cam.global_position
	if not rs.holder.global_position.is_equal_approx(cam_pos):
		bad.append("the streaks do not follow the camera")
	main.fx_scale = 0.5
	rs.update(0.016)
	if mm.visible_instance_count != int(Rain.STREAKS * 0.5):
		bad.append("%d streaks drawn at fx_scale 0.5" % mm.visible_instance_count)
	main.fx_scale = 0.0
	rs.update(0.016)
	if rs.holder.visible:
		bad.append("streaks are drawn at fx_scale 0")
	main.fx_scale = 1.0
	for st in ["clear", "over", "title", "map", "shop", "loading"]:
		main.state = st
		rs.update(0.016)
		if rs.holder.visible:
			bad.append("streaks are drawn in state %s" % st)
	main.state = "title"


func _check_rounds() -> void:
	var night_theme = Content.theme_index("NIGHT")
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
		first["theme"] = 0  # DAY
		first["modifiers"] = []
		_play_first_node()
		var dry_top = _sky_top()
		var dry_ground = _ground_materials()
		_expect_look("%s, no modifier" % tag, false, dry_top, dry_ground)
		first["modifiers"] = ["rain"]
		_play_first_node()
		if main.theme_idx != 0:
			bad.append("%s: rain changed the theme to %d" % [tag, main.theme_idx])
		if not main.rain_sys.round_rain:
			bad.append("%s: a rain round is not marked as one" % tag)
		_expect_look("%s, rain" % tag, true, dry_top, dry_ground)
		if seed_value == SEEDS[0]:
			_check_streaks_in_play()
		var original_roughness = {}
		for part_name in dry_ground:
			original_roughness[part_name] = dry_ground[part_name].roughness
		first["modifiers"] = []
		_play_first_node()
		if main.rain_sys.round_rain:
			bad.append("%s: the round after rain is still marked as rain" % tag)
		_expect_look("%s, the round after rain" % tag, false, dry_top, dry_ground)
		for part_name in dry_ground:
			if dry_ground[part_name].roughness != original_roughness[part_name]:
				bad.append("%s: rain changed the material of %s" % [tag, part_name])
		# the title screen asks for the plain theme: nothing may stay wet
		first["modifiers"] = ["rain"]
		_play_first_node()
		main.apply_theme(0)
		_expect_look("%s, apply_theme without rain" % tag, false, dry_top, dry_ground)
		# rain on a NIGHT-themed node is not darker than NIGHT
		first["theme"] = night_theme
		_play_first_node()
		var night_top: Color = Content.THEMES[night_theme]["top"]
		if Rain.luma(_sky_top()) < Rain.luma(night_top) - EPS:
			bad.append("%s: a rainy NIGHT sky is darker than NIGHT" % tag)
		first["theme"] = saved_theme
		first["modifiers"] = saved_mods
	main.queue_free()
	await process_frame
