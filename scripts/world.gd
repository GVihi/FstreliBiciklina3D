extends RefCounted
# Builds the arena: a roundabout. The player stands on the central island, the ring road runs around it
# and riders circle it. See ring.gd for how the old straight street coordinates map onto the circle.
#
#   radius  8        low concrete barrier around the island (street z = 2.75)
#   radius 10 .. 16  three bike lanes (street z = 0.5 / -2.5 / -5.5)
#   radius 18 .. 24  far sidewalk (walkers + joggers), then the facade of the buildings
#   angle  180 deg   the road dives into a black tunnel block: riders enter and leave there

const Util = preload("res://scripts/util.gd")
const Toon = preload("res://scripts/toon.gd")
const Ring = preload("res://scripts/ring.gd")


static func build(root: Node3D, _hx: float = 0.0) -> Dictionary:
	var out = {}

	# ---------- environment + sun ----------
	var env = Environment.new()
	var sky_mat = ProceduralSkyMaterial.new()
	var sky = Sky.new()
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.65, 0.7)
	env.ambient_light_energy = 0.8
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	Toon.setup_glow(env)
	var we = WorldEnvironment.new()
	we.environment = env
	root.add_child(we)

	var sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL  # 1 shadow map instead of 4 splits
	sun.directional_shadow_max_distance = 36.0
	root.add_child(sun)

	out["env"] = env
	out["sky_mat"] = sky_mat
	out["sun"] = sun

	# ---------- materials ----------
	var asphalt = Util.mat(Color(0.17, 0.17, 0.19), 0.95)
	var walk = Util.mat(Color(0.56, 0.55, 0.51), 0.95)
	var curb = Util.mat(Color(0.74, 0.73, 0.69), 0.9)
	var paint = Util.mat(Color(0.93, 0.93, 0.9), 0.8)
	var concrete = Util.mat(Color(0.62, 0.62, 0.6), 0.95)
	var hazard = Util.mat(Color(0.95, 0.75, 0.15), 0.7)
	var brick = Util.mat(Color(0.52, 0.34, 0.28), 0.95)
	var dark_wall = Util.mat(Color(0.3, 0.3, 0.33), 0.95)
	var grass = Util.mat(Color(0.2, 0.3, 0.2), 1.0)
	var black = Util.unshaded(Color(0.0, 0.0, 0.0))
	var metal = Util.mat(Color(0.25, 0.27, 0.3), 0.5, 0.6)
	var trunk = Util.mat(Color(0.3, 0.2, 0.12), 1.0)
	var leaf = Util.mat(Color(0.18, 0.38, 0.2), 1.0)
	var leaf2 = Util.mat(Color(0.24, 0.46, 0.24), 1.0)

	var win_mat = Util.glow(Color(1.0, 0.85, 0.5), 0.0)
	win_mat.albedo_color = Color(0.25, 0.32, 0.4)
	var lamp_mat = Util.glow(Color(1.0, 0.9, 0.65), 0.0)
	out["win_mat"] = win_mat
	out["lamp_mat"] = lamp_mat

	# ---------- ground ----------
	var RB = Ring.RHO_B
	var paving = Util.mat(Color(0.62, 0.6, 0.55), 0.95)
	var lawn = Util.mat(Color(0.3, 0.46, 0.27), 1.0)
	var stone = Util.mat(Color(0.5, 0.5, 0.52), 0.95)
	var water = Util.mat(Color(0.35, 0.62, 0.85), 0.2)
	Util.box(root, Vector3(300.0, 0.1, 300.0), Vector3(0, -0.12, 0), grass)
	Util.slab(root, 0.0, 2.2, -0.1, 0.16, lawn)  # island: lawn in the middle
	Util.slab(root, 2.2, RB, -0.1, 0.0, paving)  #         paving around it
	Util.slab(root, RB, Ring.rho(2.0), -0.1, 0.0, walk)  # strip between barrier and road
	Util.slab(root, Ring.rho(2.0), Ring.rho(-7.0), -0.1, 0.0, asphalt)  # the ring road, street z -7 .. 2
	Util.slab(root, Ring.rho(-7.0), Ring.rho(-13.0), -0.1, 0.0, walk)  # far sidewalk
	Util.slab(root, Ring.rho(2.1) - 0.11, Ring.rho(2.1) + 0.11, 0.0, 0.12, curb)
	Util.slab(root, Ring.rho(-7.1) - 0.11, Ring.rho(-7.1) + 0.11, 0.0, 0.12, curb)

	# fountain in the middle of the island
	Util.cyl(root, 1.35, 1.45, 0.5, Vector3(0, 0.4, 0), stone)
	Util.cyl(root, 1.15, 1.15, 0.05, Vector3(0, 0.66, 0), water)
	Util.cyl(root, 0.18, 0.24, 1.5, Vector3(0, 1.3, 0), stone)
	Util.sphere(root, 0.3, Vector3(0, 2.1, 0), stone)
	for i in range(5):
		var a = TAU * float(i) / 5.0 + 0.3
		Util.sphere(root, 0.42, Vector3(sin(a) * 1.85, 0.4, -cos(a) * 1.85), leaf, 0.8)

	# ---------- road markings ----------
	var gate_h = Ring.GATE_HALF / Ring.RHO_REF
	for zline in [-4.0, -1.0]:
		var dm = MeshInstance3D.new()
		dm.mesh = Util.dashes_mesh(Ring.rho(zline), 0.12, 1.6, 3.2, 0.013, PI, gate_h + 0.05)
		dm.material_override = paint
		dm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(dm)
	for zedge in [-6.8, 1.8]:
		var em = Util.slab(
			root, Ring.rho(zedge) - 0.06, Ring.rho(zedge) + 0.06, 0.0, 0.013, paint, 0.0, TAU, false
		)
		em.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# ---------- the island edge is only paint now: you can walk out onto the road ----------
	var edge = Util.slab(root, RB - 0.2, RB + 0.2, 0.0, 0.014, hazard, 0.0, TAU, false)
	edge.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# ---------- the tunnel: a black block over the road at the back; riders appear and vanish inside it ----------
	Util.slab(
		root, Ring.GATE_RHO_IN, Ring.rho(-13.0) + 1.6, 0.0, 7.5, black, PI - gate_h, PI + gate_h
	)

	# planter on the island in front of the tunnel: the player cannot walk past it
	var pl_a = Ring.player_lim() / Ring.RHO_REF + 0.06
	Util.slab(root, 1.0, Ring.GATE_RHO_IN, 0.0, 1.1, stone, pl_a, TAU - pl_a)
	Util.slab(root, 1.0, Ring.GATE_RHO_IN, 1.1, 1.18, lawn, pl_a, TAU - pl_a, false)
	for tdeg in [-6.0, 6.0]:
		var ta = PI + deg_to_rad(tdeg)
		var tr_r = 5.2
		Util.cyl(root, 0.14, 0.18, 2.4, Vector3(sin(ta) * tr_r, 2.3, -cos(ta) * tr_r), trunk)
		Util.sphere(root, 1.2, Vector3(sin(ta) * tr_r, 3.9, -cos(ta) * tr_r), leaf)

	# ---------- buildings all around the ring ----------
	var nb = 28
	for i in range(nb):
		var ang = TAU * float(i) / float(nb) - PI + TAU / float(nb) * 0.5
		if absf(wrapf(ang - PI, -PI, PI)) < gate_h + 0.17:
			continue
		var h = 6.5 + float((i * 7) % 5) * 1.2
		var bx = Node3D.new()
		bx.position = Vector3(sin(ang) * 24.4, 0.0, -cos(ang) * 24.4)
		bx.rotation.y = -ang
		root.add_child(bx)
		Util.box(
			bx, Vector3(5.4, h, 1.1), Vector3(0, h * 0.5, 0), brick if i % 3 != 1 else dark_wall
		)
		var rows = [2.6, 5.0]
		if h > 8.4:
			rows.append(7.4)
		for wy in rows:
			for wx in [-1.5, 1.5]:
				var wm = Util.box(bx, Vector3(1.5, 1.5, 0.1), Vector3(wx, wy, 0.6), win_mat)
				wm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# ---------- street lamps along the far side of the road ----------
	var lamps = []
	for ldeg in [25.0, 85.0, 140.0, 220.0, 275.0, 335.0]:
		var la = deg_to_rad(ldeg)
		var lp = Node3D.new()
		lp.position = Vector3(sin(la) * Ring.rho(-7.6), 0.0, -cos(la) * Ring.rho(-7.6))
		lp.rotation.y = -la * 1.0
		root.add_child(lp)
		Util.cyl(lp, 0.06, 0.08, 5.2, Vector3(0, 2.6, 0), metal)
		Util.box(lp, Vector3(0.06, 0.06, 1.4), Vector3(0, 5.2, 0.7), metal)
		Util.box(lp, Vector3(0.45, 0.1, 0.28), Vector3(0, 5.12, 1.3), lamp_mat)
		var ol = OmniLight3D.new()
		ol.position = Vector3(0, 4.9, 1.3)
		ol.omni_range = 13.0
		ol.light_energy = 2.2
		ol.light_color = Color(1.0, 0.85, 0.6)
		ol.visible = false
		lp.add_child(ol)
		lamps.append(ol)
	out["lamps"] = lamps

	# ---------- trees on the far sidewalk ----------
	for tdeg2 in [0.0, 30.0, -30.0, 85.0, -85.0, 115.0, -115.0, 148.0, -148.0]:
		var tha = deg_to_rad(tdeg2)
		var trr = Ring.rho(-12.4)
		var tp = Vector3(sin(tha) * trr, 0.0, -cos(tha) * trr)
		Util.cyl(root, 0.14, 0.18, 2.4, tp + Vector3(0, 1.2, 0), trunk)
		Util.sphere(root, 1.3, tp + Vector3(0, 3.3, 0), leaf)
		Util.sphere(root, 0.9, tp + Vector3(0.5, 4.1, 0.2), leaf2)

	return out
