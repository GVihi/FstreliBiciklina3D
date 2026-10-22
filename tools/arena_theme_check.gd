extends SceneTree
# Checks that a lighting theme is applied to a generated arena the way the game applies it to the roundabout
# (README Milestone K, "Theme lighting and lit windows on generated arenas"). Run from the project folder:
#   godot --headless --path . --script res://tools/arena_theme_check.gd
# Optional argument after "--": how many seeds to try (default 30).
# For every seed and every theme in Content.THEMES it dresses the arena with WorldDress, applies the theme with
# Lighting.apply_theme and checks that
#   - the sky, the sun (colour, strength, angle) and the ambient light are the theme's
#   - the windows glow at the theme's "lit" strength and the lamp heads at Lighting.LAMP_HEAD_GLOW, or not at all
#     when the theme has no lamps
#   - a theme with lamps turns on min(Lighting.MAX_LAMP_LIGHTS, lamps) lamp lights and no other, and they are the
#     ones nearest the focus point (worked out again here); a theme without lamps turns none on
#   - going from NIGHT back to DAY puts everything out again
#   - a world with fewer lamps than the limit (the roundabout has six) gets every lamp lit, in the order given,
#     when no focus is passed
# It also damages the result six ways and fails if the checks do not name each one. Exits with status 1.

const ArenaGen = preload("res://scripts/arena_gen.gd")
const WorldDress = preload("res://scripts/world_dress.gd")
const Lighting = preload("res://scripts/lighting.gd")
const Content = preload("res://scripts/content.gd")

var problems = []
var lamp_min = 1000000
var lamp_max = 0


func _initialize() -> void:
	var count = 30
	var args = OS.get_cmdline_user_args()
	if args.size() > 0:
		count = int(args[0])
	var rules = ArenaGen.load_rules()
	if rules.is_empty():
		quit(1)
		return
	if Lighting.MAX_LAMP_LIGHTS < 1 or Lighting.MAX_LAMP_LIGHTS > 16:
		problems.append(
			"Lighting.MAX_LAMP_LIGHTS is %d, outside 1 to 16" % Lighting.MAX_LAMP_LIGHTS
		)
	var first = {}
	for k in range(count):
		var seed_value = (k * 2654435761 + 4242) & 0xFFFFFFFF
		var layout = ArenaGen.generate(seed_value, rules)
		if layout.is_empty():
			problems.append("seed %08X: no layout" % seed_value)
			continue
		var dressed = WorldDress.build(layout)
		var world = _world(dressed)
		var at = layout["start"]["pos"]
		var focus = Vector3(float(at[0]), 0.0, float(at[1]))
		lamp_min = mini(lamp_min, dressed["lamps"].size())
		lamp_max = maxi(lamp_max, dressed["lamps"].size())
		for th in Content.THEMES:
			Lighting.apply_theme(th, world, focus)
			for p in _verify(th, world, focus):
				problems.append("seed %08X, %s: %s" % [seed_value, th["name"], p])
		# back to day puts everything out
		Lighting.apply_theme(Content.THEMES[3], world, focus)
		Lighting.apply_theme(Content.THEMES[0], world, focus)
		for p in _verify(Content.THEMES[0], world, focus):
			problems.append("seed %08X, NIGHT then DAY: %s" % [seed_value, p])
		if first.is_empty():
			first = {"layout": layout, "focus": focus}
		dressed["root"].free()
	_check_few_lamps()
	if not first.is_empty():
		_check_damage(first["layout"], first["focus"])
	if problems.is_empty():
		print(
			(
				"arena_theme_check: %d arenas with %d to %d lamps, %d themes each; sky, sun, ambient, windows, lamp heads and at most %d lamp lights (the ones nearest the start) follow the theme, and six kinds of damage are caught"
				% [count, lamp_min, lamp_max, Content.THEMES.size(), Lighting.MAX_LAMP_LIGHTS]
			)
		)
		quit(0)
	else:
		for i in range(mini(problems.size(), 20)):
			print("FAIL: " + problems[i])
		print("arena_theme_check: %d problems" % problems.size())
		quit(1)


func _world(dressed: Dictionary) -> Dictionary:
	var sun = DirectionalLight3D.new()
	dressed["root"].add_child(sun)
	return {
		"env": Environment.new(),
		"sky_mat": ProceduralSkyMaterial.new(),
		"sun": sun,
		"lamps": dressed["lamps"],
		"lamp_mat": dressed["lamp_mat"],
		"win_mat": dressed["win_mat"],
	}


func _near(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) < 0.004 and absf(a.g - b.g) < 0.004 and absf(a.b - b.b) < 0.004


# what must be true of a world after `th` was applied with this focus
func _verify(th: Dictionary, world: Dictionary, focus: Vector3) -> Array:
	var found = []
	var sm: ProceduralSkyMaterial = world["sky_mat"]
	if not _near(sm.sky_top_color, th["top"]) or not _near(sm.sky_horizon_color, th["hor"]):
		found.append("the sky is not the theme's")
	var sun: DirectionalLight3D = world["sun"]
	if (
		not _near(sun.light_color, th["sun"])
		or absf(sun.light_energy - float(th["sun_e"])) > 0.001
		or (sun.rotation_degrees.distance_to(Vector3(th["sun_x"], th["sun_y"], 0.0)) > 0.01)
	):
		found.append("the sun is not the theme's")
	var env: Environment = world["env"]
	if (
		not _near(env.ambient_light_color, th["amb"])
		or absf(env.ambient_light_energy - float(th["amb_e"])) > 0.001
	):
		found.append("the ambient light is not the theme's")
	if absf(world["win_mat"].emission_energy_multiplier - float(th["lit"])) > 0.001:
		found.append(
			(
				"windows glow %.2f, the theme says %.2f"
				% [world["win_mat"].emission_energy_multiplier, float(th["lit"])]
			)
		)
	var glow = Lighting.LAMP_HEAD_GLOW if th["lamps"] else 0.0
	if absf(world["lamp_mat"].emission_energy_multiplier - glow) > 0.001:
		found.append(
			(
				"lamp heads glow %.2f, expected %.2f"
				% [world["lamp_mat"].emission_energy_multiplier, glow]
			)
		)
	var lamps: Array = world["lamps"]
	var lit = []
	var dark = []
	for l in lamps:
		(lit if l.visible else dark).append(l)
	var want = mini(Lighting.MAX_LAMP_LIGHTS, lamps.size()) if th["lamps"] else 0
	if lit.size() != want:
		found.append("%d lamp lights on, expected %d of %d" % [lit.size(), want, lamps.size()])
	else:
		# every lamp that is on must be at least as near the focus as every lamp that is off
		var farthest_on = 0.0
		for l in lit:
			farthest_on = maxf(farthest_on, l.position.distance_squared_to(focus))
		for l in dark:
			if l.position.distance_squared_to(focus) < farthest_on - 0.0001:
				found.append("a lamp light is off while a farther one is on")
				break
	return found


# a world with a few lamps: all of them light, in the order they were given, without a focus
func _check_few_lamps() -> void:
	var lamps = []
	var holder = Node3D.new()
	for i in range(6):
		var l = OmniLight3D.new()
		l.position = Vector3(float(i) * 10.0, 5.0, 0.0)
		holder.add_child(l)
		lamps.append(l)
	var world = {
		"env": Environment.new(),
		"sky_mat": ProceduralSkyMaterial.new(),
		"sun": DirectionalLight3D.new(),
		"lamp_mat": StandardMaterial3D.new(),
		"win_mat": StandardMaterial3D.new(),
		"lamps": lamps,
	}
	Lighting.apply_theme(Content.THEMES[3], world)
	for l in lamps:
		if not l.visible:
			problems.append("a world with six lamps did not light them all at NIGHT")
			break
	Lighting.apply_theme(Content.THEMES[0], world)
	for l in lamps:
		if l.visible:
			problems.append("a world with six lamps left a light on by DAY")
			break
	# more lamps than the limit and no focus: the first ones
	for i in range(Lighting.MAX_LAMP_LIGHTS + 4 - 6):
		var extra = OmniLight3D.new()
		holder.add_child(extra)
		lamps.append(extra)
	Lighting.apply_theme(Content.THEMES[3], world)
	for i in range(lamps.size()):
		if lamps[i].visible != (i < Lighting.MAX_LAMP_LIGHTS):
			problems.append(
				"without a focus the first %d lamps must be the lit ones" % Lighting.MAX_LAMP_LIGHTS
			)
			break
	holder.free()
	world["sun"].free()


func _expect_caught(
	label: String, needle: String, th: Dictionary, world: Dictionary, focus: Vector3
) -> void:
	var said = _verify(th, world, focus)
	if said.is_empty():
		problems.append("the checks did not notice: %s" % label)
	elif not " | ".join(said).contains(needle):
		problems.append('the checks noticed "%s" but not by "%s": %s' % [label, needle, said[0]])


func _check_damage(layout: Dictionary, focus: Vector3) -> void:
	var night = Content.THEMES[3]
	var day = Content.THEMES[0]
	# every lamp lit: no limit
	var dressed = WorldDress.build(layout)
	var world = _world(dressed)
	Lighting.apply_theme(night, world, focus)
	for l in world["lamps"]:
		l.visible = true
	_expect_caught("no limit on lamp lights", "lamp lights on", night, world, focus)
	# the lights chosen are the first ones, not the nearest
	for l in world["lamps"]:
		l.visible = false
	for i in range(Lighting.MAX_LAMP_LIGHTS):
		world["lamps"][world["lamps"].size() - 1 - i].visible = true
	_expect_caught("the farthest lamps lit", "farther one", night, world, focus)
	# windows dark at night
	Lighting.apply_theme(night, world, focus)
	world["win_mat"].emission_energy_multiplier = 0.0
	_expect_caught("windows dark at night", "windows glow", night, world, focus)
	# lamp heads left glowing by day
	Lighting.apply_theme(day, world, focus)
	world["lamp_mat"].emission_energy_multiplier = Lighting.LAMP_HEAD_GLOW
	_expect_caught("lamp heads glowing by day", "lamp heads glow", day, world, focus)
	# a lamp light left on by day
	Lighting.apply_theme(day, world, focus)
	world["lamps"][0].visible = true
	_expect_caught("a lamp light on by day", "lamp lights on", day, world, focus)
	# the sun left where the last theme put it
	Lighting.apply_theme(night, world, focus)
	world["sun"].rotation_degrees = Vector3(-45.0, -60.0, 0.0)
	_expect_caught("the sun at the wrong angle", "sun", night, world, focus)
	dressed["root"].free()
