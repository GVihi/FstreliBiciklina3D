extends RefCounted
# Procedural low-poly models: cyclists, pedestrians and the foam-dart shotgun.
# Everything is built from primitives so there are no art assets to import.

const Util = preload("res://scripts/util.gd")
const Toon = preload("res://scripts/toon.gd")
const Halo = preload("res://scripts/halo.gd")

const SKIN = "#e8b98a"
const SKIN_DARK = "#c79869"


static func kit_of(i: int) -> Dictionary:
	var kits = [
		{
			"suit": Color.html("#1d56b3"),
			"dark": Color.html("#0f2f66"),
			"acc": Color.html("#ff6a2b")
		},
		{
			"suit": Color.html("#c8322b"),
			"dark": Color.html("#7d1a16"),
			"acc": Color.html("#ffffff")
		},
		{
			"suit": Color.html("#2f9e57"),
			"dark": Color.html("#1a5c33"),
			"acc": Color.html("#ffd23f")
		},
		{
			"suit": Color.html("#26262c"),
			"dark": Color.html("#0e0e11"),
			"acc": Color.html("#ee3c8a")
		},
		{
			"suit": Color.html("#e9c824"),
			"dark": Color.html("#9a8410"),
			"acc": Color.html("#1d56b3")
		},
		{"suit": Color.html("#5a2a8c"), "dark": Color.html("#331552"), "acc": Color.html("#f2b630")}
	]
	return kits[i]


# ------------------------------------------------------------------
#  Cyclist. Built facing +X. root > pivot(yaw flip) > bike / man
#  bike and man are separate nodes so they can fly apart when hit.
# ------------------------------------------------------------------
static func build_rider(type: String, kit: Dictionary) -> Dictionary:
	var root = Node3D.new()
	var pivot = Node3D.new()
	root.add_child(pivot)

	var bike = Node3D.new()
	bike.position = Vector3(0, 0.5, 0)
	pivot.add_child(bike)
	var bg = Node3D.new()  # geometry holder, net offset 0 (ground level)
	bg.position = Vector3(0, -0.5, 0)
	bike.add_child(bg)

	var man = Node3D.new()
	man.position = Vector3(0, 0.9, 0)
	pivot.add_child(man)
	var mg = Node3D.new()
	mg.position = Vector3(0, -0.9, 0)
	man.add_child(mg)

	var frame = Util.mat(kit["acc"], 0.4, 0.2)
	var tyre = Util.mat(Color.html("#101215"), 0.9)
	var rim = Util.mat(Color.html("#9aa0a8"), 0.4, 0.8)
	var blk = Util.mat(Color.html("#17191c"), 0.7)
	var skin = Util.mat(Color.html(SKIN), 0.8)
	var skin_d = Util.mat(Color.html(SKIN_DARK), 0.8)
	var suit = Util.mat(kit["suit"], 0.7)
	var suit_d = Util.mat(kit["dark"], 0.7)
	var white = Util.mat(Color.html("#f6f6f2"), 0.6)
	var lens = Util.mat(Color.html("#0a1426"), 0.2, 0.3)

	# ---- bike frame (side view coordinates, x forward, y up) ----
	var bb = Vector2(0.0, 0.32)
	Util.fbar(bg, bb, Vector2(-0.14, 0.86), 0.04, frame)  # seat tube
	Util.fbar(bg, Vector2(-0.13, 0.84), Vector2(0.40, 0.84), 0.04, frame)  # top tube
	Util.fbar(bg, bb, Vector2(0.40, 0.78), 0.05, frame)  # down tube
	Util.fbar(bg, Vector2(0.40, 0.74), Vector2(0.43, 0.92), 0.05, frame)  # head tube
	Util.fbar(bg, bb, Vector2(-0.50, 0.34), 0.03, frame, 0.05)  # chain stay
	Util.fbar(bg, bb, Vector2(-0.50, 0.34), 0.03, frame, -0.05)
	Util.fbar(bg, Vector2(-0.14, 0.84), Vector2(-0.50, 0.34), 0.03, frame, 0.05)  # seat stay
	Util.fbar(bg, Vector2(-0.14, 0.84), Vector2(-0.50, 0.34), 0.03, frame, -0.05)
	Util.fbar(bg, Vector2(0.43, 0.80), Vector2(0.50, 0.34), 0.035, frame, 0.05)  # fork
	Util.fbar(bg, Vector2(0.43, 0.80), Vector2(0.50, 0.34), 0.035, frame, -0.05)
	Util.fbar(bg, Vector2(0.43, 0.92), Vector2(0.50, 0.97), 0.035, blk)  # stem
	Util.box(bg, Vector3(0.05, 0.03, 0.44), Vector3(0.50, 0.97, 0), blk)  # handlebar
	Util.box(bg, Vector3(0.26, 0.05, 0.12), Vector3(-0.15, 0.89, 0), blk)  # saddle

	# ---- wheels ----
	var wheels = []
	for wx in [0.50, -0.50]:
		var w = Node3D.new()
		w.position = Vector3(wx, 0.34, 0)
		bg.add_child(w)
		var t = Util.torus(w, 0.305, 0.365, Vector3.ZERO, tyre)
		t.rotation.x = PI * 0.5
		Util.box(w, Vector3(0.62, 0.012, 0.012), Vector3.ZERO, rim)
		Util.box(w, Vector3(0.012, 0.62, 0.012), Vector3.ZERO, rim)
		Util.sphere(w, 0.03, Vector3(0.33, 0.0, 0.04), frame)  # marker so you can see it spin
		wheels.append(w)

	# ---- cranks + legs ----
	var cranks = []
	var thighs = []
	var shins = []
	var shoes = []
	for i in range(2):
		var z = 0.12 if i == 0 else -0.12
		var cr = Util.bar(bg, 0.03, 0.03, z, blk)
		cranks.append(cr)
		var th = Util.bar(mg, 0.125, 0.125, z, suit if i == 0 else suit_d)
		thighs.append(th)
		var sh = Util.bar(mg, 0.085, 0.085, z, skin if i == 0 else skin_d)
		shins.append(sh)
		var shoe = Util.box(mg, Vector3(0.22, 0.07, 0.10), Vector3(0, 0, z), white)
		shoes.append(shoe)

	# ---- torso, arms, head ----
	var hip = Vector2(-0.12, 0.95)
	var shoulder = Vector2(0.26, 1.36)
	Util.set_bar(Util.bar(mg, 0.22, 0.34, 0.0, suit), hip, shoulder)
	Util.set_bar(
		Util.bar(mg, 0.04, 0.35, 0.0, Util.mat(kit["acc"], 0.6)),
		hip + Vector2(0.03, 0.09),
		shoulder + Vector2(-0.01, 0.09)
	)
	for z in [0.19, -0.19]:
		Util.fbar(mg, shoulder, Vector2(0.42, 1.14), 0.08, suit, z)
		Util.fbar(mg, Vector2(0.42, 1.14), Vector2(0.50, 0.97), 0.06, skin, z)
		Util.sphere(mg, 0.045, Vector3(0.50, 0.97, z), blk)
	Util.sphere(mg, 0.115, Vector3(0.37, 1.50, 0), skin)
	Util.sphere(mg, 0.14, Vector3(0.34, 1.56, 0), white, 0.78)  # helmet
	Util.box(mg, Vector3(0.22, 0.02, 0.05), Vector3(0.34, 1.64, 0), Util.mat(kit["acc"], 0.6))
	Util.box(mg, Vector3(0.03, 0.045, 0.17), Vector3(0.475, 1.52, 0), lens)  # shades

	if type == "courier":
		Util.box(
			mg,
			Vector3(0.34, 0.36, 0.38),
			Vector3(-0.22, 1.30, 0),
			Util.mat(Color.html("#ff7a2b"), 0.7)
		)
		Util.box(mg, Vector3(0.345, 0.05, 0.385), Vector3(-0.22, 1.30, 0), white)

	Util.trim_shadows(root)
	return {
		"root": root,
		"pivot": pivot,
		"bike": bike,
		"man": man,
		"wheels": wheels,
		"cranks": cranks,
		"thighs": thighs,
		"shins": shins,
		"shoes": shoes
	}


static func pose_rider(d: Dictionary, cph: float, wph: float) -> void:
	for w in d["wheels"]:
		var wn: Node3D = w
		wn.rotation.z = -wph
	var hip = Vector2(-0.12, 0.95)
	var bb = Vector2(0.0, 0.32)
	for i in range(2):
		var ang = -cph + PI * float(i)
		var ped = bb + Vector2(cos(ang), sin(ang)) * 0.17
		var v = ped - hip
		var dist = maxf(v.length(), 0.05)
		var mid = hip + v * 0.5
		var perp = Vector2(-v.y, v.x) / dist
		var h = sqrt(maxf(0.0, 0.43 * 0.43 - (dist * 0.5) * (dist * 0.5)))
		var knee = mid + perp * h
		Util.set_bar(d["thighs"][i], hip, knee)
		Util.set_bar(d["shins"][i], knee, ped)
		Util.set_bar(d["cranks"][i], bb, ped)
		var shoe: Node3D = d["shoes"][i]
		shoe.position = Vector3(ped.x + 0.05, ped.y, shoe.position.z)


# ------------------------------------------------------------------
#  Pedestrian. Built facing +X.
# ------------------------------------------------------------------
static func build_civ(kind: String, pal: Dictionary) -> Dictionary:
	var root = Node3D.new()
	var geo = Node3D.new()
	root.add_child(geo)
	var skin = Util.mat(pal["skin"], 0.8)
	var shirt = Util.mat(pal["shirt"], 0.8)
	var pants = Util.mat(pal["pants"], 0.8)
	var hair = Util.mat(pal["hair"], 0.9)
	var shoe = Util.mat(Color.html("#222428"), 0.8)

	var legs = []
	var arms = []
	for z in [0.1, -0.1]:
		var lp = Node3D.new()
		lp.position = Vector3(0, 0.92, z)
		geo.add_child(lp)
		Util.box(lp, Vector3(0.14, 0.9, 0.15), Vector3(0, -0.45, 0), pants)
		Util.box(lp, Vector3(0.25, 0.07, 0.14), Vector3(0.04, -0.9, 0), shoe)
		legs.append(lp)
	Util.box(geo, Vector3(0.26, 0.55, 0.42), Vector3(0, 1.2, 0), shirt)
	for z in [0.27, -0.27]:
		var ap = Node3D.new()
		ap.position = Vector3(0, 1.42, z)
		geo.add_child(ap)
		Util.box(ap, Vector3(0.1, 0.5, 0.1), Vector3(0, -0.25, 0), shirt)
		Util.sphere(ap, 0.05, Vector3(0, -0.55, 0), skin)
		arms.append(ap)
	Util.sphere(geo, 0.12, Vector3(0.02, 1.62, 0), skin)
	Util.sphere(geo, 0.13, Vector3(-0.01, 1.68, 0), hair, 0.65)
	if kind == "granny":
		Util.sphere(geo, 0.07, Vector3(-0.12, 1.72, 0), hair)  # bun
		Util.box(geo, Vector3(0.12, 0.26, 0.2), Vector3(0.0, 0.88, 0.37), Util.mat(pal["bag"], 0.8))
	elif kind == "walker":
		Util.box(geo, Vector3(0.1, 0.26, 0.2), Vector3(-0.1, 0.9, 0.36), Util.mat(pal["bag"], 0.8))
	elif kind == "jogger":
		Util.box(
			geo,
			Vector3(0.27, 0.03, 0.14),
			Vector3(0.03, 1.7, 0),
			Util.mat(Color.html("#ee3c8a"), 0.7)
		)  # headband
	var cam_prop = Util.box(
		geo, Vector3(0.12, 0.09, 0.06), Vector3(0.40, 1.42, 0), Util.mat(Color.html("#111111"), 0.5)
	)
	cam_prop.visible = false
	var s = 0.88 if kind == "granny" else 1.0
	Util.trim_shadows(root)
	return {"root": root, "geo": geo, "legs": legs, "arms": arms, "cam": cam_prop, "scale": s}


static func pose_civ(d: Dictionary, ph: float, photo: bool, fast: bool) -> void:
	var amp = 0.8 if fast else 0.5
	var sw = sin(ph) * amp
	var l0: Node3D = d["legs"][0]
	var l1: Node3D = d["legs"][1]
	var a0: Node3D = d["arms"][0]
	var a1: Node3D = d["arms"][1]
	var cp: Node3D = d["cam"]
	l0.rotation.z = sw
	l1.rotation.z = -sw
	if photo:
		a0.rotation.z = 1.45
		a1.rotation.z = 1.35
		cp.visible = true
	else:
		a0.rotation.z = -sw * 0.9
		a1.rotation.z = sw * 0.9
		cp.visible = false


# ------------------------------------------------------------------
#  Foam-dart pump shotgun (first-person viewmodel). Barrel points to -Z.
# ------------------------------------------------------------------
const GUN_MODEL_GLB = true  # Milestone F2: the gun comes from assets/models/dart_gun.glb; false = the procedural gun below
const GUN_MODEL_PATH = "res://assets/models/dart_gun.glb"
# gun root height (m) that puts the tops of the sights on the middle of the screen while aiming; the modelled sights
# stand 0.078 m above the root, the old procedural ones 0.062 m
const GUN_MODEL_ADS_Y = -0.078
const GUN_PROC_ADS_Y = -0.062
# where the ammo number sits on the gun's left side (the side that faces you): just outside the left receiver plate, whose
# face is at x = -0.045 (the number has to be in front of it, not inside it), and just outside the old receiver
const GUN_MODEL_AMMO_POS = Vector3(-0.050, -0.018, -0.10)
const GUN_PROC_AMMO_POS = Vector3(-0.041, 0.0, -0.05)


static func build_gun() -> Dictionary:
	if GUN_MODEL_GLB:
		var d = _build_gun_from_glb()
		if not d.is_empty():
			return d
		push_warning("dart_gun.glb could not be loaded, using the procedural gun")
	return _build_gun_procedural()


# The modelled gun (tools/models/models/dart_gun.py). The .glb holds two meshes: "dart_gun" (everything fixed) and
# "pump" (the slide, already placed at (0, -0.05, -0.30) like the procedural pump). The barrel points to -Z.
static func _build_gun_from_glb() -> Dictionary:
	if not ResourceLoader.exists(GUN_MODEL_PATH):
		return {}
	var scene = load(GUN_MODEL_PATH)
	if not (scene is PackedScene):
		return {}
	var inst: Node = scene.instantiate()
	var body = inst.get_node_or_null("dart_gun")
	var pump = inst.get_node_or_null("pump")
	if not (body is Node3D) or not (pump is Node3D):
		inst.free()
		return {}
	var root = Node3D.new()
	inst.remove_child(body)
	inst.remove_child(pump)
	inst.free()
	root.add_child(body)
	root.add_child(pump)
	return _finish_gun(root, pump, GUN_MODEL_ADS_Y, GUN_MODEL_AMMO_POS)


# the muzzle point and the muzzle-flash light, shared by the modelled and the procedural gun
static func _finish_gun(
	root: Node3D,
	pump: Node3D,
	ads_y: float,
	ammo_pos: Vector3,
	muzzle_pos: Vector3 = Vector3(0, 0.03, -0.66),
	pump_z: float = -0.30
) -> Dictionary:
	var muzzle = Node3D.new()
	muzzle.position = muzzle_pos
	root.add_child(muzzle)
	var light = OmniLight3D.new()
	light.omni_range = 6.0
	light.light_color = Color(1.0, 0.8, 0.5)
	light.light_energy = 0.0
	muzzle.add_child(light)
	var flash = _build_muzzle_flash()
	muzzle.add_child(flash)
	var ammo = _build_ammo_label(ammo_pos)
	root.add_child(ammo)
	for ch in root.get_children():
		if ch is MeshInstance3D:
			ch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return {
		"root": root,
		"pump": pump,
		"muzzle": muzzle,
		"light": light,
		"flash": flash,
		"ammo": ammo,
		"ads_y": ads_y,
		"pump_z": pump_z
	}


# The ammo count on the gun: a small glowing number on the left side of the receiver, facing you (update_gun in player.gd
# sets the text and colour). The HUD ammo display stays as it is.
static func _build_ammo_label(pos: Vector3) -> Label3D:
	var l = Label3D.new()
	l.text = "6"
	l.font_size = 72
	l.pixel_size = 0.0007  # 72 px = about 5 cm tall
	l.position = pos
	l.rotation = Vector3(0.0, -PI * 0.5 + 0.5, 0.0)  # faces -X, turned about 30 degrees back towards the player so it is not seen edge-on
	l.outline_size = 10
	l.outline_modulate = Color(0.04, 0.05, 0.07)
	l.shaded = false
	l.double_sided = false
	l.modulate = Color(0.22, 0.91, 1.0)
	l.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return l


# The muzzle flash: a hot white core, an orange cone forward and a three-armed star across the barrel, all unshaded so it
# glows in any light. It sits on the muzzle, is hidden until a shot (update_gun in player.gd) and is a child of the gun so
# it goes to the viewmodel layer with the rest of the gun.
static func _build_muzzle_flash() -> Node3D:
	var f = Node3D.new()
	var hot = Util.unshaded(Color(1.0, 0.96, 0.75))
	var warm = Util.unshaded(Color(1.0, 0.62, 0.16))
	Util.sphere(f, 0.035, Vector3.ZERO, hot)
	var cone = Util.cyl(f, 0.0, 0.03, 0.30, Vector3(0, 0, -0.15), warm)  # tip towards -Z, away from the gun
	cone.rotation.x = -PI * 0.5
	var core = Util.cyl(f, 0.0, 0.016, 0.20, Vector3(0, 0, -0.10), hot)
	core.rotation.x = -PI * 0.5
	for i in range(3):
		var spike = Util.box(f, Vector3(0.22, 0.012, 0.012), Vector3(0, 0, -0.02), warm)
		spike.rotation.z = float(i) * PI / 3.0
	for ch in f.get_children():
		if ch is MeshInstance3D:
			ch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	f.visible = false
	return f


static func _build_gun_procedural() -> Dictionary:
	var root = Node3D.new()
	var orange = Util.mat(Color.html("#ff6a2b"), 0.5)
	var orange_d = Util.mat(Color.html("#c24a16"), 0.5)
	var dark = Util.mat(Color.html("#23252a"), 0.4, 0.4)
	var blue = Util.mat(Color.html("#1c63c8"), 0.5)

	Util.box(root, Vector3(0.07, 0.10, 0.34), Vector3(0, 0, -0.05), orange)  # receiver
	var barrel = Util.cyl(root, 0.022, 0.022, 0.52, Vector3(0, 0.03, -0.40), dark)
	barrel.rotation.x = PI * 0.5
	var tube = Util.cyl(root, 0.018, 0.018, 0.40, Vector3(0, -0.022, -0.33), dark)
	tube.rotation.x = PI * 0.5
	Util.box(root, Vector3(0.012, 0.016, 0.02), Vector3(0, 0.063, -0.64), blue)  # front sight
	Util.box(root, Vector3(0.03, 0.012, 0.012), Vector3(0, 0.058, -0.12), dark)  # rear sight
	var stock = Util.box(root, Vector3(0.05, 0.11, 0.24), Vector3(0, -0.04, 0.22), orange_d)
	stock.rotation.x = -0.12
	var grip = Util.box(root, Vector3(0.045, 0.12, 0.06), Vector3(0, -0.10, 0.08), orange_d)
	grip.rotation.x = 0.25
	var pump = Util.box(root, Vector3(0.06, 0.055, 0.16), Vector3(0, -0.05, -0.30), blue)  # animated slide

	return _finish_gun(root, pump, GUN_PROC_ADS_Y, GUN_PROC_AMMO_POS)


# ------------------------------------------------------------------
#  Dart Nerf Pistol (first-person viewmodel). Barrel points to -Z. Same dictionary as build_gun(): the slide is the
#  "pump" (it rests at z = PISTOL_SLIDE_Z and update_gun moves it back when a dart is fired).
#  Built from boxes and cylinders, no .glb: a small chunky toy in the orange and blue of the dart gun.
# ------------------------------------------------------------------
const PISTOL_ADS_Y = -0.072  # the tops of the sights are 0.072 m above the root
const PISTOL_SLIDE_Z = -0.05
const PISTOL_AMMO_POS = Vector3(-0.026, -0.075, 0.062)  # on the left face of the grip, facing the player
const PISTOL_MUZZLE_POS = Vector3(0.0, 0.04, -0.30)


static func build_pistol() -> Dictionary:
	var root = Node3D.new()
	var orange = Util.mat(Color.html("#ff6a2b"), 0.5)
	var orange_d = Util.mat(Color.html("#c24a16"), 0.5)
	var dark = Util.mat(Color.html("#23252a"), 0.4, 0.4)
	var blue = Util.mat(Color.html("#1c63c8"), 0.5)
	var white = Util.mat(Color.html("#f2f2ee"), 0.6)

	Util.box(root, Vector3(0.044, 0.045, 0.22), Vector3(0, -0.002, -0.02), blue)  # frame under the slide
	var grip = Util.box(root, Vector3(0.042, 0.135, 0.062), Vector3(0, -0.085, 0.068), orange_d)
	grip.rotation.x = 0.22
	Util.box(root, Vector3(0.046, 0.012, 0.066), Vector3(0, -0.153, 0.094), dark)  # grip base
	Util.box(root, Vector3(0.012, 0.03, 0.012), Vector3(0, -0.04, 0.0), dark)  # trigger
	Util.box(root, Vector3(0.008, 0.008, 0.07), Vector3(0, -0.058, -0.03), dark)  # trigger guard, bottom
	Util.box(root, Vector3(0.008, 0.026, 0.008), Vector3(0, -0.047, -0.065), dark)  # trigger guard, front
	var barrel = Util.cyl(root, 0.016, 0.016, 0.16, Vector3(0, 0.035, -0.22), dark)
	barrel.rotation.x = PI * 0.5
	var tip = Util.cyl(root, 0.021, 0.021, 0.03, Vector3(0, 0.035, -0.295), orange)  # orange nerf muzzle ring
	tip.rotation.x = PI * 0.5
	Util.box(root, Vector3(0.036, 0.012, 0.03), Vector3(0, 0.03, -0.17), orange_d)  # barrel collar under the slide
	Util.box(root, Vector3(0.012, 0.016, 0.014), Vector3(0, 0.067, -0.255), white)  # front sight
	Util.box(root, Vector3(0.03, 0.01, 0.01), Vector3(0, 0.067, 0.045), dark)  # rear sight
	# the slide: moves back when a dart is fired and rests a little back while it reloads
	var slide = Node3D.new()
	slide.position = Vector3(0, 0.04, PISTOL_SLIDE_Z)
	root.add_child(slide)
	Util.box(slide, Vector3(0.042, 0.05, 0.19), Vector3.ZERO, orange)
	Util.box(slide, Vector3(0.044, 0.012, 0.19), Vector3(0, 0.026, 0), orange_d)  # raised top rib
	for i in range(3):  # grip grooves at the back of the slide, slightly darker than the slide
		Util.box(
			slide, Vector3(0.045, 0.044, 0.004), Vector3(0, 0, 0.06 + 0.014 * float(i)), orange_d
		)

	return _finish_gun(
		root, slide, PISTOL_ADS_Y, PISTOL_AMMO_POS, PISTOL_MUZZLE_POS, PISTOL_SLIDE_Z
	)


# ------------------------------------------------------------------
#  v4 additions: bosses, angry cyclist, phone, rubber, cheerleaders, pickups
# ------------------------------------------------------------------
static func _scaled(mi: MeshInstance3D, s: Vector3) -> MeshInstance3D:
	mi.scale = s
	return mi


# Standing person used by the minister / president and the dismounted cyclist.
# Built facing +Z (the direction bosses charge in). Returns pivots to animate.
static func build_fighter(c: Dictionary) -> Dictionary:
	var root = Node3D.new()
	var geo = Node3D.new()
	root.add_child(geo)
	var suit = Util.mat(c["suit"], 0.7)
	var dark = Util.mat(c["dark"], 0.7)
	var skin = Util.mat(c["skin"], 0.8)
	var shoe = Util.mat(Color.html("#17191c"), 0.7)
	var white = Util.mat(Color.html("#f6f6f2"), 0.6)
	var blk = Util.mat(Color.html("#16181b"), 0.6)

	var legs = []
	for x in [0.13, -0.13]:
		var lp = Node3D.new()
		lp.position = Vector3(x, 0.95, 0)
		geo.add_child(lp)
		Util.box(lp, Vector3(0.18, 0.95, 0.2), Vector3(0, -0.47, 0), dark)
		Util.box(lp, Vector3(0.2, 0.09, 0.32), Vector3(0, -0.93, 0.06), shoe)
		legs.append(lp)
	Util.box(geo, Vector3(0.52, 0.64, 0.3), Vector3(0, 1.27, 0), suit)
	if c.has("stripe"):
		Util.box(geo, Vector3(0.54, 0.07, 0.32), Vector3(0, 1.2, 0), Util.mat(c["stripe"], 0.6))
	if c.has("tie"):
		Util.box(geo, Vector3(0.16, 0.34, 0.02), Vector3(0, 1.36, 0.155), white)
		Util.box(geo, Vector3(0.07, 0.32, 0.03), Vector3(0, 1.34, 0.165), Util.mat(c["tie"], 0.6))

	var arms = []
	var bases = c["arm_base"]
	var side = [0.34, -0.34]
	for i in range(2):
		var ap = Node3D.new()
		ap.position = Vector3(side[i], 1.5, 0)
		ap.rotation.x = bases[i]
		geo.add_child(ap)
		Util.box(ap, Vector3(0.12, 0.52, 0.12), Vector3(0, -0.26, 0), suit)
		Util.sphere(ap, 0.075, Vector3(0, -0.56, 0), blk if c.get("gloves", false) else skin)
		arms.append(ap)
	if c.get("paper", false):
		var a0: Node3D = arms[0]
		Util.box(a0, Vector3(0.34, 0.04, 0.42), Vector3(0, -0.6, 0.18), white)
	if c.get("mic", false):
		var a1: Node3D = arms[1]
		Util.cyl(a1, 0.02, 0.02, 0.3, Vector3(0, -0.72, 0.0), Util.mat(Color.html("#2b2f36"), 0.5))
		Util.sphere(a1, 0.08, Vector3(0, -0.9, 0.0), Util.mat(Color.html("#8a8f98"), 0.4, 0.5))

	Util.sphere(geo, 0.15, Vector3(0, 1.78, 0), skin)
	if c.has("hair"):
		Util.sphere(geo, 0.16, Vector3(0, 1.84, -0.02), Util.mat(c["hair"], 0.9), 0.7)
	if c.get("helmet", false):
		Util.sphere(geo, 0.18, Vector3(0, 1.85, -0.01), white, 0.8)
		Util.box(geo, Vector3(0.3, 0.03, 0.05), Vector3(0, 1.93, 0.05), Util.mat(c["acc"], 0.6))
	if c.get("glasses", false):
		Util.box(geo, Vector3(0.3, 0.05, 0.02), Vector3(0, 1.8, 0.15), blk)
	for x in [0.055, -0.055]:
		Util.box(geo, Vector3(0.03, 0.03, 0.02), Vector3(x, 1.79, 0.145), blk)
	var b1 = Util.box(geo, Vector3(0.1, 0.02, 0.02), Vector3(0.06, 1.835, 0.15), blk)
	b1.rotation.z = 0.4
	var b2 = Util.box(geo, Vector3(0.1, 0.02, 0.02), Vector3(-0.06, 1.835, 0.15), blk)
	b2.rotation.z = -0.4
	var mouth = Util.box(
		geo, Vector3(0.09, 0.05, 0.02), Vector3(0, 1.7, 0.145), Util.mat(Color.html("#5a1a1a"), 0.8)
	)
	Util.trim_shadows(root)
	return {"root": root, "geo": geo, "legs": legs, "arms": arms, "arm_base": bases, "mouth": mouth}


static func pose_fighter(d: Dictionary, ph: float) -> void:
	var s = sin(ph)
	var l0: Node3D = d["legs"][0]
	var l1: Node3D = d["legs"][1]
	l0.rotation.x = s * 0.9
	l1.rotation.x = -s * 0.9
	var bases = d["arm_base"]
	for i in range(2):
		var a: Node3D = d["arms"][i]
		a.rotation.x = bases[i] + sin(ph + PI * float(i)) * 0.25
	var m: Node3D = d["mouth"]
	m.scale = Vector3(1.0, 0.6 + absf(s) * 1.2, 1.0)
	var g: Node3D = d["geo"]
	g.position.y = absf(s) * 0.06


static func build_runner(kit: Dictionary) -> Dictionary:
	return build_fighter(
		{
			"suit": kit["suit"],
			"dark": kit["dark"],
			"acc": kit["acc"],
			"skin": Color.html(SKIN),
			"stripe": kit["acc"],
			"helmet": true,
			"gloves": true,
			"arm_base": [-1.45, -1.45]
		}
	)


static func build_minister(variant: int) -> Dictionary:
	var c = {
		"suit": Color.html("#4a4034") if variant == 1 else Color.html("#3d4756"),
		"dark": Color.html("#23262c"),
		"acc": Color.html("#f2b630"),
		"skin": Color.html("#f0c8a0"),
		"tie": Color.html("#c8322b") if variant == 1 else Color.html("#1d56b3"),
		"hair": Color.html("#b8b8b8") if variant == 1 else Color.html("#2a2018"),
		"glasses": variant == 1,
		"paper": true,
		"mic": true,
		"arm_base": [-1.0, -1.75]
	}
	return build_fighter(c)


# Boss models face +Z. Returns {"root": Node3D, ... animation handles}.
static func build_boss(kind: String, variant: int, kit: Dictionary) -> Dictionary:
	if kind == "runner":
		var d = build_runner(kit)
		d["fighter"] = true
		return d
	if kind == "minister":
		var d2 = build_minister(variant)
		d2["fighter"] = true
		return d2
	var root = Node3D.new()
	var white = Util.mat(Color.html("#f1f3ef"), 0.5)
	var blk = Util.mat(Color.html("#16181b"), 0.7)
	var grey = Util.mat(Color.html("#c9ced4"), 0.4, 0.5)
	if kind == "mower":
		var green = Util.mat(Color.html("#2fae5f"), 0.5)
		Util.box(root, Vector3(1.0, 0.45, 1.3), Vector3(0, 0.5, 0), white)
		Util.box(root, Vector3(1.02, 0.1, 1.32), Vector3(0, 0.4, 0), green)
		Util.sphere(root, 0.5, Vector3(0, 0.78, -0.1), Util.mat(Color.html("#dde2dc"), 0.5), 0.5)
		for x in [0.56, -0.56]:
			for z in [0.45, -0.45]:
				var w = Util.cyl(root, 0.2, 0.2, 0.13, Vector3(x, 0.2, z), blk)
				w.rotation.z = PI * 0.5
		var eyes = Util.glow(Color(1.0, 0.15, 0.15), 2.0)
		for x in [0.25, -0.25]:
			Util.box(root, Vector3(0.24, 0.08, 0.05), Vector3(x, 0.66, 0.66), eyes)
			var br = Util.box(root, Vector3(0.28, 0.04, 0.04), Vector3(x, 0.74, 0.67), blk)
			br.rotation.z = -0.35 if x > 0 else 0.35
		var blade = Util.cyl(root, 0.52, 0.52, 0.03, Vector3(0, 0.1, 0), grey)
		return {"root": root, "spin": blade, "eyes": eyes, "fighter": false}
	# wifi node
	var red = Util.glow(Color(0.9, 0.2, 0.24), 2.0)
	var body = Node3D.new()
	root.add_child(body)
	Util.cyl(body, 0.3, 0.3, 1.3, Vector3(0, 0.75, 0), Util.mat(Color.html("#f4f5f6"), 0.4))
	Util.sphere(body, 0.3, Vector3(0, 1.4, 0), Util.mat(Color.html("#f4f5f6"), 0.4))
	Util.cyl(body, 0.31, 0.31, 0.08, Vector3(0, 0.55, 0), red)
	for x in [0.12, -0.12]:
		Util.box(body, Vector3(0.1, 0.06, 0.03), Vector3(x, 1.38, 0.28), red)
		var b = Util.box(body, Vector3(0.12, 0.025, 0.025), Vector3(x, 1.46, 0.29), blk)
		b.rotation.z = -0.4 if x > 0 else 0.4
	for i in range(4):
		Util.box(
			body,
			Vector3(0.05, 0.04, 0.02),
			Vector3(-0.1 + i * 0.07, 1.2 + (0.04 if i % 2 == 0 else 0.0), 0.3),
			blk
		)
	for x in [0.2, -0.2]:
		var ant = Util.cyl(body, 0.012, 0.012, 0.5, Vector3(x * 1.6, 1.85, 0), grey)
		ant.rotation.z = -0.35 if x > 0 else 0.35
		Util.sphere(body, 0.045, Vector3(x * 2.0, 2.08, 0), red)
	return {"root": root, "body": body, "eyes": red, "fighter": false}


static func build_phone() -> Node3D:
	var root = Node3D.new()
	var shell = Util.mat(Color.html("#2b2f36"), 0.5)
	Util.box(root, Vector3(0.5, 0.12, 0.34), Vector3.ZERO, shell)
	Util.box(
		root,
		Vector3(0.22, 0.012, 0.12),
		Vector3(-0.1, 0.065, -0.07),
		Util.glow_shared(Color.html("#3fa0ff"), 1.2)
	)
	Util.box(
		root, Vector3(0.58, 0.07, 0.09), Vector3(0, 0.13, 0.0), Util.mat(Color.html("#1b1e23"), 0.5)
	)
	for r in range(3):
		for c in range(3):
			Util.box(
				root,
				Vector3(0.04, 0.01, 0.04),
				Vector3(0.08 + c * 0.055, 0.065, -0.07 + r * 0.055),
				Util.mat(Color.html("#6b727c"), 0.5)
			)
	Util.sphere(root, 0.02, Vector3(0.2, 0.065, 0.12), Util.glow_shared(Color(1.0, 0.2, 0.15), 2.0))
	Halo.attach(root)  # a glow that stays visible from far away (halo.gd)
	return root


# Melee weapon (Milestone F3): a giant glossy, glittery pink jelly-rubber club, held by the knob. The model comes from
# assets/models/jelly_club.glb (tools/models/models/jelly_club.py): one mesh, the knob at z = +0.2 (in your hand) and the
# head at z = -1.0, the same reach as the old worm. RUBBER_MODEL_GLB = false brings the old procedural gummy worm back.
const RUBBER_MODEL_GLB = true
const RUBBER_MODEL_PATH = "res://assets/models/jelly_club.glb"


static func build_rubber() -> Dictionary:
	if RUBBER_MODEL_GLB:
		var d = _build_rubber_from_glb()
		if not d.is_empty():
			return d
		push_warning("jelly_club.glb could not be loaded, using the procedural worm")
	return _build_rubber_procedural()


static func _build_rubber_from_glb() -> Dictionary:
	if not ResourceLoader.exists(RUBBER_MODEL_PATH):
		return {}
	var scene = load(RUBBER_MODEL_PATH)
	if not (scene is PackedScene):
		return {}
	var inst: Node = scene.instantiate()
	var club = inst.get_node_or_null("jelly_club")
	if not (club is Node3D):
		inst.free()
		return {}
	var root = Node3D.new()
	inst.remove_child(club)
	inst.free()
	root.add_child(club)
	for ch in root.get_children():
		if ch is MeshInstance3D:
			ch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var wob = _rubber_wobble_materials(club) if RUBBER_WOBBLE else []
	return {"root": root, "paddle": club, "wobble": wob}


# Wobble (Milestone F3): the club bends and ripples like jelly. The bend is done in the vertex shader, so the mesh stays one
# object; player.gd drives the uniforms with a spring (update_gun). The shader copies colour and roughness from
# the .glb's own materials, so the look is the same as without it. RUBBER_WOBBLE = false keeps the club rigid.
const RUBBER_WOBBLE = true
const RUBBER_REACH_Z = Vector2(0.2, -1.0)  # z of the knob (in your hand) and of the tip, the same as the model
const RUBBER_SHADER = """
shader_type spatial;
render_mode @RENDER_MODES@;     // filled in by _rubber_shader_code(): toon or ordinary lighting, the same as every other material

uniform vec4 albedo : source_color = vec4(1.0, 0.31, 0.64, 1.0);
uniform float roughness : hint_range(0.0, 1.0) = 0.12;
uniform float glitter = 0.0;         // 1 for the glitter flecks: bright and twinkling instead of lit
uniform vec2 wob = vec2(0.0);        // how far the tip is pushed sideways and up (metres); the bend grows towards the tip
uniform float jelly = 0.0;           // strength of the ripple that runs down the club (metres)
uniform float phase = 0.0;           // moves the ripple and the twinkle
uniform float squash = 0.0;          // above 0 stretches the club along its length and thins it
uniform float flash = 0.0;           // 1 right after a hit: the whole club lights up white
uniform float knob_z = 0.2;
uniform float tip_z = -1.0;

varying vec3 rest_pos;

void vertex() {
	rest_pos = VERTEX;
	float h = clamp((knob_z - VERTEX.z) / (knob_z - tip_z), 0.0, 1.0);   // 0 at the hand, 1 at the tip
	VERTEX.z = knob_z + (VERTEX.z - knob_z) * (1.0 + squash);
	VERTEX.xy *= 1.0 - squash * 0.5;
	VERTEX.x += wob.x * h * h + jelly * sin(h * 9.0 - phase) * h;
	VERTEX.y += wob.y * h * h + jelly * 0.6 * sin(h * 7.0 - phase * 1.3 + 1.0) * h;
}

void fragment() {
	float rim = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 2.0);
	if (glitter > 0.5) {
		float tw = 0.65 + 0.35 * sin(phase * 0.6 + dot(rest_pos, vec3(97.0, 57.0, 31.0)));
		ALBEDO = vec3(1.0, 0.9, 0.96);
		ROUGHNESS = 0.4;
		EMISSION = vec3(1.0, 0.85, 0.94) * tw * 0.9;
	} else {
		ALBEDO = albedo.rgb;
		ROUGHNESS = roughness;
		SPECULAR = 1.0;
		EMISSION = albedo.rgb * 0.22 + vec3(1.0, 0.7, 0.88) * rim * 0.5;   // lifts the shadow side and rims it, so it reads as jelly
	}
	EMISSION += vec3(1.0, 0.85, 0.95) * flash * 0.8;
}
"""


# RUBBER_SHADER with the lighting modes that match the rest of the game (see toon.gd, Toon.ENABLED)
static func _rubber_shader_code() -> String:
	var modes = (
		"diffuse_toon, specular_toon" if Toon.ENABLED else "diffuse_burley, specular_schlick_ggx"
	)
	return RUBBER_SHADER.replace("@RENDER_MODES@", modes)


# swaps every surface of the club for a ShaderMaterial with the wobble; returns those materials (empty if it could not)
static func _rubber_wobble_materials(club: Node) -> Array:
	var mi: MeshInstance3D = null
	if club is MeshInstance3D:
		mi = club
	else:
		for ch in club.get_children():
			if ch is MeshInstance3D:
				mi = ch
				break
	if mi == null or mi.mesh == null:
		return []
	var sh = Shader.new()
	sh.code = _rubber_shader_code()
	var out = []
	for i in range(mi.mesh.get_surface_count()):
		var src = mi.mesh.surface_get_material(i)
		var m = ShaderMaterial.new()
		m.shader = sh
		if src is BaseMaterial3D:
			m.set_shader_parameter("albedo", src.albedo_color)
			m.set_shader_parameter("roughness", src.roughness)
			m.set_shader_parameter("glitter", 1.0 if src.metallic > 0.5 else 0.0)  # the glitter surface is the metallic one
		m.set_shader_parameter("knob_z", RUBBER_REACH_Z.x)
		m.set_shader_parameter("tip_z", RUBBER_REACH_Z.y)
		mi.set_surface_override_material(i, m)
		out.append(m)
	return out


# The old melee weapon: a GIANT ribbed, rubbery pink gummy worm, held by the tail. The tail is at +Z (in your hand) and
# the worm reaches out along -Z with a lazy S-curve. Each rib is a flattened sphere; light and dark pink alternate.
static func _build_rubber_procedural() -> Dictionary:
	var root = Node3D.new()
	var light = Util.mat(Color.html("#ff95cb"), 0.25)
	var dark = Util.mat(Color.html("#ff5fae"), 0.3)
	var segs = 22
	var z0 = 0.2
	var z1 = -1.0
	var first = null
	for i in range(segs):
		var t = float(i) / float(segs - 1)
		var z = lerpf(z0, z1, t)
		var sway = 0.045 * sin(t * PI * 2.2)  # S-curve
		var droop = -0.03 * sin(t * PI)  # sags a little in the middle
		# fat in the middle, thinner at the tail, a rounded head
		var rad = 0.07 + 0.03 * sin(t * PI) - 0.02 * (1.0 - t) * (1.0 - t)
		if i == segs - 1:
			rad = 0.085  # head
		var seg = Util.sphere(root, 0.5, Vector3(sway, droop, z), light if i % 2 == 0 else dark)
		seg.scale = Vector3(rad * 2.0, rad * 2.0, 0.085)  # flattened: overlapping discs make the ribs
		if first == null:
			first = seg
		if i == segs - 1:
			seg.scale = Vector3(rad * 2.0, rad * 2.0, 0.14)
			var eye_m = Util.mat(Color.html("#ffffff"), 0.3)
			var pupil_m = Util.mat(Color.html("#16181d"), 0.4)
			for sx in [-1.0, 1.0]:
				var eye = Util.sphere(
					root, 0.022, Vector3(sway + sx * 0.04, droop + 0.035, z - 0.045), eye_m
				)
				var pup = Util.sphere(
					root, 0.011, Vector3(sway + sx * 0.04, droop + 0.037, z - 0.062), pupil_m
				)
	for ch in root.get_children():
		if ch is MeshInstance3D:
			ch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return {"root": root, "paddle": first}


# Cheerleader built facing +X like the pedestrians.
static func build_cheer(i: int) -> Dictionary:
	var root = Node3D.new()
	var geo = Node3D.new()
	root.add_child(geo)
	var skin = Util.mat(Color.html("#f3d2b0") if i % 2 == 1 else Color.html("#f0c8a0"), 0.8)
	var orange = Util.mat(Color.html("#ff6a2b"), 0.6)
	var white = Util.mat(Color.html("#ffffff"), 0.6)
	var hair = Util.mat(Color.html("#f4d35e"), 0.8)
	for z in [0.08, -0.08]:
		Util.box(geo, Vector3(0.1, 0.62, 0.1), Vector3(0, 0.31, z), skin)
		Util.box(geo, Vector3(0.18, 0.05, 0.12), Vector3(0.03, 0.025, z), white)
	Util.box(geo, Vector3(0.34, 0.22, 0.42), Vector3(0, 0.72, 0), white)
	Util.box(geo, Vector3(0.35, 0.04, 0.43), Vector3(0, 0.63, 0), orange)
	Util.box(geo, Vector3(0.22, 0.36, 0.32), Vector3(0, 1.0, 0), orange)
	Util.box(geo, Vector3(0.225, 0.05, 0.325), Vector3(0, 1.0, 0), white)
	Util.sphere(geo, 0.115, Vector3(0.01, 1.35, 0), skin)
	Util.sphere(geo, 0.125, Vector3(-0.015, 1.4, 0), hair, 0.7)
	Util.sphere(geo, 0.06, Vector3(-0.15, 1.38, 0.0), hair)
	Util.sphere(geo, 0.04, Vector3(-0.2, 1.3, 0.0), hair)
	var arms = []
	var poms = []
	var pc = [Color.html("#ff6a2b"), Color.html("#ffffff")]
	for z in [0.22, -0.22]:
		var ap = Node3D.new()
		ap.position = Vector3(0, 1.15, z)
		geo.add_child(ap)
		Util.box(ap, Vector3(0.07, 0.42, 0.07), Vector3(0, -0.21, 0), skin)
		for k in range(3):
			Util.sphere(
				ap,
				0.075,
				Vector3(0.05 * (k - 1), -0.46 - 0.03 * (k % 2), 0.04 * (k - 1)),
				Util.mat(pc[k % 2], 0.7)
			)
		arms.append(ap)
	Util.trim_shadows(root)
	return {"root": root, "geo": geo, "arms": arms}


static func pose_cheer(d: Dictionary, ph: float, chv: float) -> void:
	var amp = 0.3 + chv * 0.3
	var a0: Node3D = d["arms"][0]
	var a1: Node3D = d["arms"][1]
	a0.rotation.z = 2.5 + sin(ph * 1.3) * amp
	a1.rotation.z = 2.5 + cos(ph * 1.3) * amp


# Pickup: glowing orb with a white ring and a letter.
static func build_pickup(col: Color, ch: String) -> Dictionary:
	var root = Node3D.new()
	var orb = Util.sphere(root, 0.3, Vector3.ZERO, Util.glow_shared(col, 1.4))
	var ring = Util.torus(root, 0.31, 0.36, Vector3.ZERO, Util.unshaded(Color.WHITE))
	ring.rotation.x = PI * 0.5
	var lab = Label3D.new()
	lab.text = ch
	lab.font_size = 96
	lab.pixel_size = 0.0045
	lab.outline_size = 14
	lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lab.no_depth_test = true
	lab.modulate = Color.WHITE
	root.add_child(lab)
	return {"root": root, "orb": orb, "ring": ring}
