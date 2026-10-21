extends RefCounted
# Small helpers for building meshes and doing ray maths from code.
#
# PERFORMANCE: mat(), unshaded() and every mesh helper below hand out SHARED resources from a cache.
# Building a rider used to create ~45 meshes and 12 materials from scratch on every spawn, and that
# was the main source of hitches. Now the first rider builds them and every later one reuses them.
# Never change a material or mesh you got from here (use glow() for materials you animate).

static var _mats := {}
static var _meshes := {}


static func mat(col: Color, rough: float = 0.9, metal: float = 0.0) -> StandardMaterial3D:
	var key = "m%s_%.3f_%.3f" % [col.to_html(true), rough, metal]
	if _mats.has(key):
		return _mats[key]
	var m = StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	m.metallic = metal
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON  # hard-edged cartoon shading
	m.specular_mode = BaseMaterial3D.SPECULAR_TOON
	_mats[key] = m
	return m


static func unshaded(col: Color) -> StandardMaterial3D:
	var key = "u%s" % col.to_html(true)
	if _mats.has(key):
		return _mats[key]
	var m = StandardMaterial3D.new()
	m.albedo_color = col
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mats[key] = m
	return m


# Shared emissive material for things that never change brightness (pickups, phone screen).
static func glow_shared(col: Color, energy: float) -> StandardMaterial3D:
	var key = "g%s_%.3f" % [col.to_html(true), energy]
	if _mats.has(key):
		return _mats[key]
	var m = glow(col, energy)
	_mats[key] = m
	return m


# ---- shared meshes (instances still scale / rotate themselves) ----
static func box_mesh(size: Vector3) -> BoxMesh:
	var key = "b%.4f_%.4f_%.4f" % [size.x, size.y, size.z]
	if _meshes.has(key):
		return _meshes[key]
	var bm = BoxMesh.new()
	bm.size = size
	_meshes[key] = bm
	return bm


static func sphere_mesh(r: float) -> SphereMesh:
	var key = "s%.4f" % r
	if _meshes.has(key):
		return _meshes[key]
	var sm = SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	sm.radial_segments = 14
	sm.rings = 8
	_meshes[key] = sm
	return sm


static func cyl_mesh(r_top: float, r_bot: float, h: float) -> CylinderMesh:
	var key = "c%.4f_%.4f_%.4f" % [r_top, r_bot, h]
	if _meshes.has(key):
		return _meshes[key]
	var cm = CylinderMesh.new()
	cm.top_radius = r_top
	cm.bottom_radius = r_bot
	cm.height = h
	cm.radial_segments = 12
	cm.rings = 1
	_meshes[key] = cm
	return cm


static func torus_mesh(inner: float, outer: float, rings: int = 24, segs: int = 8) -> TorusMesh:
	var key = "t%.4f_%.4f_%d_%d" % [inner, outer, rings, segs]
	if _meshes.has(key):
		return _meshes[key]
	var tm = TorusMesh.new()
	tm.inner_radius = inner
	tm.outer_radius = outer
	tm.rings = rings
	tm.ring_segments = segs
	_meshes[key] = tm
	return tm


# Tiny parts (spokes, bolts, eyes) are not worth a shadow-pass draw call each.
static func trim_shadows(node: Node, min_size: float = 0.16) -> void:
	if node is MeshInstance3D:
		var mi: MeshInstance3D = node
		if mi.mesh != null:
			var ext = mi.mesh.get_aabb().size * mi.scale
			if maxf(ext.x, maxf(ext.y, ext.z)) < min_size:
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for ch in node.get_children():
		trim_shadows(ch, min_size)


static func glow(col: Color, energy: float) -> StandardMaterial3D:
	var m = StandardMaterial3D.new()
	m.albedo_color = col
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = energy
	return m


static func box(parent: Node, size: Vector3, pos: Vector3, m: Material) -> MeshInstance3D:
	var mi = MeshInstance3D.new()
	mi.mesh = box_mesh(size)
	mi.material_override = m
	mi.position = pos
	parent.add_child(mi)
	return mi


static func sphere(
	parent: Node, r: float, pos: Vector3, m: Material, sy: float = 1.0
) -> MeshInstance3D:
	var mi = MeshInstance3D.new()
	mi.mesh = sphere_mesh(r)
	mi.material_override = m
	mi.position = pos
	mi.scale = Vector3(1.0, sy, 1.0)
	parent.add_child(mi)
	return mi


static func cyl(
	parent: Node, r_top: float, r_bot: float, h: float, pos: Vector3, m: Material
) -> MeshInstance3D:
	var mi = MeshInstance3D.new()
	mi.mesh = cyl_mesh(r_top, r_bot, h)
	mi.material_override = m
	mi.position = pos
	parent.add_child(mi)
	return mi


static func torus(
	parent: Node, inner: float, outer: float, pos: Vector3, m: Material
) -> MeshInstance3D:
	var mi = MeshInstance3D.new()
	mi.mesh = torus_mesh(inner, outer)
	mi.material_override = m
	mi.position = pos
	parent.add_child(mi)
	return mi


# A "bar" is a unit-length box we stretch between two 2D points (side view, XY plane).
static func bar(parent: Node, th_y: float, th_z: float, z: float, m: Material) -> MeshInstance3D:
	var mi = MeshInstance3D.new()
	mi.mesh = box_mesh(Vector3(1.0, th_y, th_z))
	mi.material_override = m
	mi.position = Vector3(0.0, 0.0, z)
	parent.add_child(mi)
	return mi


static func set_bar(mi: MeshInstance3D, a: Vector2, b: Vector2) -> void:
	var d = b - a
	mi.position.x = (a.x + b.x) * 0.5
	mi.position.y = (a.y + b.y) * 0.5
	mi.rotation.z = atan2(d.y, d.x)
	mi.scale.x = maxf(d.length(), 0.001)


static func fbar(
	parent: Node, a: Vector2, b: Vector2, th: float, m: Material, z: float = 0.0
) -> MeshInstance3D:
	var mi = bar(parent, th, th, z, m)
	set_bar(mi, a, b)
	return mi


# Ray vs ellipsoid. Returns distance along the ray, or -1.0 for a miss.
static func ray_ellipsoid(o: Vector3, d: Vector3, c: Vector3, r: Vector3) -> float:
	var oc = (o - c) / r
	var dd = d / r
	var a = dd.dot(dd)
	var b = 2.0 * oc.dot(dd)
	var cc = oc.dot(oc) - 1.0
	var disc = b * b - 4.0 * a * cc
	if disc < 0.0:
		return -1.0
	var sq = sqrt(disc)
	var t0 = (-b - sq) / (2.0 * a)
	var t1 = (-b + sq) / (2.0 * a)
	if t0 > 0.0:
		return t0
	if t1 > 0.0:
		return t1
	return -1.0


# Ray vs ellipsoid whose long axis is turned by yaw (rotation about Y, like Node3D.rotation.y).
static func ray_ellipsoid_yaw(o: Vector3, d: Vector3, c: Vector3, r: Vector3, yaw: float) -> float:
	var inv = Basis(Vector3.UP, -yaw)
	return ray_ellipsoid(inv * (o - c), inv * d, Vector3.ZERO, r)


# ---- ring (circular) geometry for the roundabout ----
# Angles use the street convention: point = (r * sin(a), y, -r * cos(a)), so a = 0 is straight ahead of the player.
static func _rp(r: float, a: float, y: float) -> Vector3:
	return Vector3(r * sin(a), y, -r * cos(a))


static func _quad(
	m: Dictionary,
	a: Vector3,
	b: Vector3,
	c: Vector3,
	d: Vector3,
	na: Vector3,
	nb: Vector3,
	nc: Vector3,
	nd: Vector3
) -> void:
	var v: PackedVector3Array = m["v"]
	var n: PackedVector3Array = m["n"]
	var idx: PackedInt32Array = m["i"]
	var base = v.size()
	v.append(a)
	v.append(b)
	v.append(c)
	v.append(d)
	n.append(na)
	n.append(nb)
	n.append(nc)
	n.append(nd)
	var want = (na + nb + nc + nd).normalized()
	var cr = (b - a).cross(c - a)
	if cr.dot(want) > 0.0:  # Godot front faces are clockwise
		idx.append_array([base, base + 2, base + 1, base, base + 3, base + 2])
	else:
		idx.append_array([base, base + 1, base + 2, base, base + 2, base + 3])


static func _mesh_of(m: Dictionary) -> ArrayMesh:
	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = m["v"]
	arrays[Mesh.ARRAY_NORMAL] = m["n"]
	arrays[Mesh.ARRAY_INDEX] = m["i"]
	var am = ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return am


static func _new_mb() -> Dictionary:
	return {"v": PackedVector3Array(), "n": PackedVector3Array(), "i": PackedInt32Array()}


# A ring (or a sector of one) with thickness: top, inner wall, outer wall, end caps.
static func slab_mesh(
	r0: float,
	r1: float,
	y0: float,
	y1: float,
	th0: float = 0.0,
	th1: float = TAU,
	per_circle: int = 96,
	sides: bool = true
) -> ArrayMesh:
	var key = (
		"slab%.3f_%.3f_%.3f_%.3f_%.4f_%.4f_%d_%s"
		% [r0, r1, y0, y1, th0, th1, per_circle, str(sides)]
	)
	if _meshes.has(key):
		return _meshes[key]
	var m = _new_mb()
	var span = th1 - th0
	var n = maxi(2, int(ceil(float(per_circle) * absf(span) / TAU)))
	var up = Vector3.UP
	for i in range(n):
		var a = th0 + span * float(i) / float(n)
		var b = th0 + span * float(i + 1) / float(n)
		_quad(m, _rp(r0, a, y1), _rp(r1, a, y1), _rp(r1, b, y1), _rp(r0, b, y1), up, up, up, up)
		if sides and y1 - y0 > 0.001:
			var oa = _rp(1.0, a, 0.0)
			var ob = _rp(1.0, b, 0.0)
			_quad(m, _rp(r1, a, y1), _rp(r1, a, y0), _rp(r1, b, y0), _rp(r1, b, y1), oa, oa, ob, ob)
			if r0 > 0.001:
				_quad(
					m,
					_rp(r0, b, y1),
					_rp(r0, b, y0),
					_rp(r0, a, y0),
					_rp(r0, a, y1),
					-ob,
					-ob,
					-oa,
					-oa
				)
	if sides and y1 - y0 > 0.001 and absf(span) < TAU - 0.001:
		var ta = Vector3(-cos(th0), 0.0, -sin(th0))  # outward at the start of the sector
		var tb = Vector3(cos(th1), 0.0, sin(th1))  # outward at the end
		_quad(
			m,
			_rp(r0, th0, y1),
			_rp(r0, th0, y0),
			_rp(r1, th0, y0),
			_rp(r1, th0, y1),
			ta,
			ta,
			ta,
			ta
		)
		_quad(
			m,
			_rp(r1, th1, y1),
			_rp(r1, th1, y0),
			_rp(r0, th1, y0),
			_rp(r0, th1, y1),
			tb,
			tb,
			tb,
			tb
		)
	var am = _mesh_of(m)
	_meshes[key] = am
	return am


static func slab(
	parent: Node,
	r0: float,
	r1: float,
	y0: float,
	y1: float,
	m: Material,
	th0: float = 0.0,
	th1: float = TAU,
	sides: bool = true
) -> MeshInstance3D:
	var mi = MeshInstance3D.new()
	mi.mesh = slab_mesh(r0, r1, y0, y1, th0, th1, 96, sides)
	mi.material_override = m
	parent.add_child(mi)
	return mi


# Flat painted dashes laid on a circle (one mesh for all of them). Dashes whose centre falls inside
# [skip_c - skip_half, skip_c + skip_half] are left out (the tunnel).
static func dashes_mesh(
	r: float, w: float, dash_len: float, period: float, y: float, skip_c: float, skip_half: float
) -> ArrayMesh:
	var key = (
		"dash%.3f_%.3f_%.3f_%.3f_%.4f_%.3f_%.3f" % [r, w, dash_len, period, y, skip_c, skip_half]
	)
	if _meshes.has(key):
		return _meshes[key]
	var m = _new_mb()
	var count = int(round(TAU * r / period))
	var up = Vector3.UP
	for i in range(count):
		var ac = TAU * (float(i) + 0.5) / float(count) - PI
		if absf(wrapf(ac - skip_c, -PI, PI)) < skip_half:
			continue
		var da = dash_len * 0.5 / r
		for s in range(3):
			var a = ac - da + 2.0 * da * float(s) / 3.0
			var b = ac - da + 2.0 * da * float(s + 1) / 3.0
			_quad(
				m,
				_rp(r - w * 0.5, a, y),
				_rp(r + w * 0.5, a, y),
				_rp(r + w * 0.5, b, y),
				_rp(r - w * 0.5, b, y),
				up,
				up,
				up,
				up
			)
	var am = _mesh_of(m)
	_meshes[key] = am
	return am
