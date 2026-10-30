extends SceneTree
# Checks the far-distance visibility of foes and thrown phones. Run from the project folder:
#   godot --headless --path . --script res://tools/visibility_check.gd
#
# Rim (scripts/rim.gd): the rim material carries the distance settings, they grow with distance (a thicker, stronger,
# brighter rim and a fill) and start before the far end, and the shader measures the distance from the camera.
# Halo (scripts/halo.gd): a phone built by Models.build_phone has one halo, it uses the shared material, it does not
# test depth and it is sized from the distance in the shader; `hide_on` switches it off.
# This check cannot see how it looks: that is for a person in the game (far riders and phones, all four themes).
# Exits with status 1 and prints the problems.

const Rim = preload("res://scripts/rim.gd")
const Halo = preload("res://scripts/halo.gd")
const Models = preload("res://scripts/models.gd")

var problems = []


func _initialize() -> void:
	_rim()
	_halo()
	if problems.is_empty():
		print("visibility_check: the rim grows with distance and a thrown phone carries a halo")
		quit(0)
	else:
		print("visibility_check: %d problem(s)" % problems.size())
		for p in problems:
			print("  " + p)
		quit(1)


func _fail(text: String) -> void:
	if problems.size() < 40:
		problems.append(text)


func _rim() -> void:
	for kind in [Rim.FOE, Rim.FRIEND]:
		var m: ShaderMaterial = Rim.material_for(kind)
		var fs = float(m.get_shader_parameter("far_start"))
		var fe = float(m.get_shader_parameter("far_end"))
		if fs <= 0.0 or fs >= fe:
			_fail("%s rim: far_start %.1f is not below far_end %.1f" % [kind, fs, fe])
		if (
			float(m.get_shader_parameter("far_strength"))
			<= float(m.get_shader_parameter("strength"))
		):
			_fail("%s rim is not stronger far away" % kind)
		if float(m.get_shader_parameter("far_power")) >= float(m.get_shader_parameter("power")):
			_fail("%s rim is not thicker far away" % kind)
		if float(m.get_shader_parameter("far_fill")) <= 0.0:
			_fail("%s rim has no fill far away" % kind)
		if float(m.get_shader_parameter("far_boost")) < 1.0:
			_fail("%s rim is dimmer far away" % kind)
	if not Rim.SHADER.contains("length(VERTEX)"):
		_fail("the rim shader does not measure the distance to the camera")
	# the foe and bystander colours stay different
	if (
		Rim.material_for(Rim.FOE).get_shader_parameter("rim_color")
		== (Rim.material_for(Rim.FRIEND).get_shader_parameter("rim_color"))
	):
		_fail("foes and bystanders share a rim colour")


func _halo() -> void:
	var ph = Models.build_phone()
	var h = Halo.of(ph)
	if h == null:
		_fail("a phone has no halo")
	else:
		var n = 0
		for ch in ph.get_children():
			if ch.name == Halo.NODE_NAME:
				n += 1
		if n != 1:
			_fail("a phone has %d halos, not 1" % n)
		if not (h is MeshInstance3D) or h.material_override != Halo.material():
			_fail("the halo does not use the shared material")
		if not h.visible:
			_fail("a new halo is hidden")
		if h is MeshInstance3D and h.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			_fail("the halo casts a shadow")
		Halo.hide_on(ph)
		if h.visible:
			_fail("hide_on left the halo on")
	for word in ["depth_test_disabled", "blend_add", "POSITION", "cam_dist", "min_angle"]:
		if not Halo.SHADER.contains(word):
			_fail("the halo shader is missing '%s'" % word)
	if Halo.MIN_ANGLE <= 0.0 or Halo.FADE_NEAR >= Halo.FADE_FAR:
		_fail("the halo size or fade settings are wrong")
	ph.free()
	# a phone without a halo (ENABLED false) must still work with hide_on
	var plain = Node3D.new()
	Halo.hide_on(plain)
	plain.free()
