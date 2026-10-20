"""Export to .glb, report triangles against the budget, render a preview sheet, validate the exported file."""
import math
from pathlib import Path

import bpy
from mathutils import Vector

from . import geo, palette

REPO = Path(__file__).resolve().parents[3]
MODELS_DIR = REPO / "assets" / "models"
PREVIEW_DIR = REPO / "docs" / "model_previews"


def stats() -> dict:
    meshes = geo.all_meshes()
    tris = sum(sum(len(p.vertices) - 2 for p in o.data.polygons) for o in meshes)
    pts = [o.matrix_world @ Vector(c) for o in meshes for c in o.bound_box]
    lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    mats = sorted({s.material.name for o in meshes for s in o.material_slots if s.material})
    return {"tris": tris, "objects": len(meshes), "materials": mats, "min": lo, "max": hi, "size": hi - lo}


def export_glb(name: str) -> Path:
    MODELS_DIR.mkdir(parents=True, exist_ok=True)
    path = MODELS_DIR / (name + ".glb")
    bpy.ops.object.select_all(action="DESELECT")
    for o in geo.all_meshes():
        o.select_set(True)
    bpy.ops.export_scene.gltf(filepath=str(path), export_format="GLB", use_selection=True, export_apply=True,
                              export_yup=True, export_materials="EXPORT", export_cameras=False, export_lights=False)
    return path


def _look_at(cam, target: Vector) -> None:
    cam.rotation_euler = (target - cam.location).to_track_quat("-Z", "Y").to_euler()


def render_preview(name: str, info: dict, st: dict) -> Path:
    """Four-angle preview sheet (front-left, back-right, side, high 3/4) rendered with the CPU renderer."""
    from PIL import Image, ImageDraw

    PREVIEW_DIR.mkdir(parents=True, exist_ok=True)
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.samples = 24
    sc.cycles.use_denoising = False
    sc.render.resolution_x, sc.render.resolution_y = 640, 480
    sc.view_settings.view_transform = "Standard"

    world = bpy.data.worlds.new("preview_world")
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    bg.inputs["Color"].default_value = (0.42, 0.62, 0.92, 1.0)    # light sky blue
    bg.inputs["Strength"].default_value = 1.1
    sc.world = world

    centre = (st["min"] + st["max"]) / 2.0
    radius = max(st["size"].length / 2.0, 0.1)

    ground = geo._mat_cache.get("__ground") or bpy.data.materials.new("preview_ground")
    ground.use_nodes = True
    ground.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = geo.hex_to_rgba("#C9C5BC")
    bpy.ops.mesh.primitive_plane_add(size=radius * 14, location=(centre.x, centre.y, st["min"].z - 0.001))
    plane = bpy.context.object
    plane.data.materials.append(ground)

    bpy.ops.object.light_add(type="SUN", location=(4, -4, 8))
    sun = bpy.context.object
    sun.data.energy = 3.5
    sun.data.angle = math.radians(8)
    sun.data.color = (1.0, 0.96, 0.88)
    sun.rotation_euler = (math.radians(50), math.radians(8), math.radians(35))

    bpy.ops.object.camera_add()
    cam = bpy.context.object
    sc.camera = cam
    cam.data.lens = 50
    dist = radius * 3.0 / math.tan(math.radians(20)) / 2.4

    views = [(35, 22), (145, 22), (-90, 8), (20, 62)]
    frames = []
    tmp = PREVIEW_DIR / ("_tmp_" + name)
    tmp.mkdir(parents=True, exist_ok=True)
    for i, (az, el) in enumerate(views):
        a, e = math.radians(az), math.radians(el)
        cam.location = centre + Vector((math.sin(a) * math.cos(e), -math.cos(a) * math.cos(e), math.sin(e))) * dist
        _look_at(cam, centre)
        sc.render.filepath = str(tmp / ("v%d.png" % i))
        bpy.ops.render.render(write_still=True)
        frames.append(Image.open(sc.render.filepath).convert("RGB"))

    w, h = frames[0].size
    head = 56
    sheet = Image.new("RGB", (w * 2, h * 2 + head), (24, 26, 30))
    for i, f in enumerate(frames):
        sheet.paste(f, ((i % 2) * w, head + (i // 2) * h))
    d = ImageDraw.Draw(sheet)
    size = st["size"]
    budget = palette.BUDGETS.get(info.get("category", "prop"), 0)
    line1 = "%s   (%s)" % (name, info.get("category", "prop"))
    line2 = "%d tris / budget %d    size %.2f x %.2f x %.2f m (x, y, z)    %d materials" % (
        st["tris"], budget, size.x, size.y, size.z, len(st["materials"]))
    d.text((12, 8), line1, fill=(255, 196, 0))
    d.text((12, 30), line2, fill=(230, 230, 225))
    out = PREVIEW_DIR / (name + ".png")
    sheet.save(out)
    for f in tmp.iterdir():
        f.unlink()
    tmp.rmdir()
    return out


def validate_glb(path: Path, st: dict) -> list:
    """Re-read the exported file: it must load, hold the same height, and be Y-up (glTF)."""
    import trimesh

    problems = []
    scene = trimesh.load(str(path), force="scene")
    ext = scene.extents
    if abs(ext[1] - st["size"].z) > 0.01:
        problems.append("height in the file is %.3f m but the model is %.3f m tall" % (ext[1], st["size"].z))
    if abs(ext[0] - st["size"].x) > 0.01 or abs(ext[2] - st["size"].y) > 0.01:
        problems.append("width/depth in the file differ from the model")
    tris = sum(len(g.faces) for g in scene.geometry.values())
    if tris < st["tris"] * 0.9 or tris > st["tris"] * 1.1:
        problems.append("triangle count in the file (%d) differs from the model (%d)" % (tris, st["tris"]))
    return problems


def finish(name: str, info: dict, preview: bool = True) -> bool:
    """Report, export, validate and (optionally) preview. Returns True when everything is within budget and valid."""
    st = stats()
    budget = palette.BUDGETS.get(info.get("category", "prop"), 0)
    ok = True
    print("\n== %s (%s)" % (name, info.get("category", "prop")))
    print("   triangles: %d / %d %s" % (st["tris"], budget, "OK" if st["tris"] <= budget else "OVER BUDGET"))
    ok = ok and st["tris"] <= budget
    print("   size (m):  x %.2f  y %.2f  z %.2f" % (st["size"].x, st["size"].y, st["size"].z))
    print("   materials: %d (%s)" % (len(st["materials"]), ", ".join(m.replace("M_", "") for m in st["materials"])))
    path = export_glb(name)
    print("   exported:  %s (%.1f KB)" % (path.relative_to(REPO), path.stat().st_size / 1024.0))
    problems = validate_glb(path, st)
    for p in problems:
        print("   PROBLEM:  " + p)
    ok = ok and not problems
    if preview:
        print("   preview:   %s" % render_preview(name, info, st).relative_to(REPO))
    return ok
