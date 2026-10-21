"""Shape helpers: chunky bevelled boxes, cylinders, tapered forms, hazard stripes, materials, joining.

Conventions
  * 1 Blender unit = 1 metre. Z is up. Models FACE -Y (Blender's front view).
    The glTF export turns that into +Z, so in Godot a model faces +Z (rotate it 180 degrees to face -Z).
  * Origin: at the model's base, centred (feet on the ground).
  * Everything is flat shaded and bevelled once: chunky and faceted, no smooth curves, no outlines.
"""
import math

import bpy  # must come first: it makes bmesh and mathutils importable
import bmesh  # noqa: E402
from mathutils import Euler, Vector  # noqa: E402

from . import palette

_mat_cache = {}


def reset() -> None:
    """Empty scene. Call at the start of every model."""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    _mat_cache.clear()


def _srgb_to_linear(c: float) -> float:
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def hex_to_rgba(h: str, linear: bool = True):
    h = h.lstrip("#")
    r, g, b = (int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4))
    if linear:
        r, g, b = _srgb_to_linear(r), _srgb_to_linear(g), _srgb_to_linear(b)
    return (r, g, b, 1.0)


def mat(name: str):
    """Material from the shared palette (created once per scene)."""
    if name in _mat_cache:
        return _mat_cache[name]
    if name not in palette.PALETTE:
        raise KeyError("'%s' is not in the palette: %s" % (name, ", ".join(sorted(palette.PALETTE))))
    hexc, rough, metal, glows = palette.PALETTE[name]
    m = bpy.data.materials.new("M_" + name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = hex_to_rgba(hexc)
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    if glows:
        bsdf.inputs["Emission Color"].default_value = hex_to_rgba(hexc)
        bsdf.inputs["Emission Strength"].default_value = 1.0
    m.diffuse_color = hex_to_rgba(hexc)
    _mat_cache[name] = m
    return m


def _make_object(name: str, bm: "bmesh.types.BMesh", mat_name: str, loc, rot=(0.0, 0.0, 0.0)):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for p in me.polygons:
        p.use_smooth = False
    me.materials.append(mat(mat_name))
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    ob.location = Vector(loc)
    ob.rotation_euler = Euler([math.radians(a) for a in rot], "XYZ")
    return ob


def _bevel(bm, amount: float) -> None:
    if amount > 0.0:
        bmesh.ops.bevel(bm, geom=list(bm.edges), offset=amount, segments=1, affect="EDGES")


def box(name, size, loc, mat_name, bevel=0.03, rot=(0, 0, 0), taper=None, base=False):
    """Chunky bevelled box. size = (x, y, z) in metres; loc = its centre (or its bottom-centre when base=True).
    taper = (sx, sy) scales the top face in x and y (a wedge-like chunk: helmets, panels, hoods)."""
    sx, sy, sz = size
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        top = v.co.z > 0
        v.co.x *= sx
        v.co.y *= sy
        v.co.z *= sz
        if taper and top:
            v.co.x *= taper[0]
            v.co.y *= taper[1]
    _bevel(bm, min(bevel, 0.45 * min(size)))
    if base:
        loc = (loc[0], loc[1], loc[2] + sz / 2.0)
    return _make_object(name, bm, mat_name, loc, rot)


def cyl(name, radius, depth, loc, mat_name, sides=8, bevel=0.0, rot=(0, 0, 0), base=False, radius_top=None):
    """Low-sided cylinder along Z (rotate to point it elsewhere). radius_top makes it a cone or taper."""
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=sides,
                          radius1=radius, radius2=radius if radius_top is None else radius_top, depth=depth)
    _bevel(bm, min(bevel, 0.45 * min(radius, depth / 2.0)))
    if base:
        loc = (loc[0], loc[1], loc[2] + depth / 2.0)
    return _make_object(name, bm, mat_name, loc, rot)


def blob(name, radius, loc, mat_name, squash=(1.0, 1.0, 1.0)):
    """Faceted low-poly rounded lump (20 faces, scaled by squash): knuckles, knobs, bags."""
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=1, radius=radius)
    for v in bm.verts:
        v.co.x *= squash[0]
        v.co.y *= squash[1]
        v.co.z *= squash[2]
    return _make_object(name, bm, mat_name, loc)


def tube(name, rings, mat_name, sides=12, cap_start=True, cap_end=True, radius_fn=None):
    """A faceted tube lofted through rings, for soft rubbery shapes (jelly clubs, tails, hoses).
    rings = list of (centre (x, y, z), radius) in order from start to end. Each ring is a polygon of `sides` points
    perpendicular to the path; the ends are closed with a flat cap (use a few small rings to make a dome).
    radius_fn(i, angle) -> extra radius (metres) for point `angle` (radians) of ring `i`: spiral ridges, seams.
    Flat shaded like everything else in the kit, so it stays chunky."""
    bm = bmesh.new()
    pts = [Vector(c) for c, _ in rings]
    up = Vector((0.0, 0.0, 1.0))
    grid = []
    for i, (c, r) in enumerate(rings):
        a = pts[max(i - 1, 0)]
        b = pts[min(i + 1, len(pts) - 1)]
        t = (b - a).normalized()
        n1 = t.cross(up)
        if n1.length < 1e-6:
            n1 = t.cross(Vector((1.0, 0.0, 0.0)))
        n1.normalize()
        n2 = t.cross(n1).normalized()
        ring = []
        for k in range(sides):
            ang = 2.0 * math.pi * k / sides
            rr = r + (radius_fn(i, ang) if radius_fn else 0.0)
            ring.append(bm.verts.new(Vector(c) + (n1 * math.cos(ang) + n2 * math.sin(ang)) * rr))
        grid.append(ring)
    for i in range(len(grid) - 1):
        for k in range(sides):
            k2 = (k + 1) % sides
            bm.faces.new((grid[i][k], grid[i][k2], grid[i + 1][k2], grid[i + 1][k]))
    if cap_start:
        bm.faces.new(list(reversed(grid[0])))
    if cap_end:
        bm.faces.new(grid[-1])
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    return _make_object(name, bm, mat_name, (0, 0, 0))


def sparkles(name, tube_rings, mat_name, count, size=0.008, seed=1, lift=0.0015, sides=12):
    """Tiny glitter flecks sitting just above the surface of a tube made from the same rings (and the same `sides`).
    Each fleck is one small diamond facing outwards. Deterministic for a given seed."""
    import random

    rnd = random.Random(seed)
    bm = bmesh.new()
    pts = [Vector(c) for c, _ in tube_rings]
    up = Vector((0.0, 0.0, 1.0))
    for _ in range(count):
        f = rnd.uniform(0.0, len(tube_rings) - 1.001)
        i = int(f)
        u = f - i
        c = pts[i].lerp(pts[i + 1], u)
        r = tube_rings[i][1] * (1.0 - u) + tube_rings[i + 1][1] * u
        t = (pts[i + 1] - pts[i]).normalized()
        n1 = t.cross(up)
        if n1.length < 1e-6:
            n1 = t.cross(Vector((1.0, 0.0, 0.0)))
        n1.normalize()
        n2 = t.cross(n1).normalized()
        ang = rnd.uniform(0.0, 2.0 * math.pi)
        out = (n1 * math.cos(ang) + n2 * math.sin(ang)).normalized()
        side = out.cross(t).normalized()
        s = size * rnd.uniform(0.6, 1.4)
        base = c + out * (r * math.cos(math.pi / sides) + lift)   # the flat of the facet, not its corner
        quad = [base + t * s, base + side * s * 0.6, base - t * s, base - side * s * 0.6]
        bm.faces.new([bm.verts.new(p) for p in quad])
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    return _make_object(name, bm, mat_name, (0, 0, 0))


def poly_prism(name, pts_xz, y_front, thickness, mat_name, loc=(0, 0, 0)):
    """A flat polygon in the XZ plane (list of (x, z)), extruded into the model from y_front by `thickness`.
    Convex polygons only. Used for hazard stripes, decals and plates."""
    bm = bmesh.new()
    front = [bm.verts.new((x, y_front, z)) for x, z in pts_xz]
    back = [bm.verts.new((x, y_front + thickness, z)) for x, z in pts_xz]
    bm.faces.new(front)
    bm.faces.new(list(reversed(back)))
    n = len(pts_xz)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((front[j], front[i], back[i], back[j]))
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    return _make_object(name, bm, mat_name, loc)


def _clip_x(poly, x_min, x_max):
    """Clip a convex polygon of (x, z) points to x_min <= x <= x_max (Sutherland-Hodgman)."""
    def clip(points, inside, cut):
        out = []
        for i in range(len(points)):
            a, b = points[i], points[(i + 1) % len(points)]
            ia, ib = inside(a), inside(b)
            if ia:
                out.append(a)
            if ia != ib:
                out.append(cut(a, b))
        return out
    cut_at = lambda xc: (lambda a, b: (xc, a[1] + (b[1] - a[1]) * (xc - a[0]) / (b[0] - a[0])))
    poly = clip(poly, lambda p: p[0] >= x_min, cut_at(x_min))
    if poly:
        poly = clip(poly, lambda p: p[0] <= x_max, cut_at(x_max))
    return poly


def hazard_stripes(name, width, height, center_x, bottom_z, y_front, mat_a="hazard_yellow", mat_b="hazard_black",
                   stripes=5, slant=0.6, thickness=0.02):
    """The recurring hazard-stripe panel, on the model's front face (-Y side). Returns the created objects.
    A dark backing plate with `stripes` slanted yellow bands on top, clipped to the panel."""
    objs = []
    x0 = center_x - width / 2.0
    objs.append(poly_prism(name + "_back", [(x0, bottom_z), (x0 + width, bottom_z),
                                            (x0 + width, bottom_z + height), (x0, bottom_z + height)],
                           y_front, thickness, mat_b))
    pitch = width / stripes
    shift = slant * height
    for i in range(-1, stripes + 1):
        xb = x0 + i * pitch
        quad = [(xb, bottom_z), (xb + pitch * 0.5, bottom_z),
                (xb + pitch * 0.5 + shift, bottom_z + height), (xb + shift, bottom_z + height)]
        clipped = _clip_x(quad, x0, x0 + width)
        if len(clipped) >= 3 and abs(clipped[0][0] - clipped[-1][0]) + abs(clipped[0][1] - clipped[-1][1]) > 1e-6:
            objs.append(poly_prism("%s_s%d" % (name, i), clipped, y_front - thickness * 0.5, thickness * 0.5, mat_a))
    return objs


def all_meshes():
    return [o for o in bpy.context.scene.objects if o.type == "MESH"]


def join_all(name: str):
    """Join every mesh into one object with one surface per material: the cheapest thing to draw."""
    meshes = all_meshes()
    bpy.ops.object.select_all(action="DESELECT")
    for o in meshes:
        o.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    ob.name = name
    ob.data.name = name
    return ob
