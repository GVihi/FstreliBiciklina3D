# 3D models

**Claude is the 3D modeler for this project.** Models are built with **Blender as a Python module (`bpy`)**: every model is a script in `models/`, so it can be rebuilt, tweaked (change a number, rerun) and reviewed.

- Style and budgets: `docs/ART_DIRECTION.md` (chunky, bevelled low-poly, bright, hazard-stripe and hi-vis accents, no outlines).
- Output: `assets/models/<name>.glb` and a four-angle preview sheet `docs/model_previews/<name>.png`.
- The palette (all colours and materials, shared by every model): `kit/palette.py`, swatches in `docs/model_previews/palette.png`.

## Setup (once)

```
python3 -m venv tools/models/.venv
tools/models/.venv/bin/pip install -r tools/models/requirements.txt
```

(On Windows: `tools\models\.venv\Scripts\pip install -r tools\models\requirements.txt`.) This installs Blender 5.x as a Python module; it renders previews on the CPU, no GPU needed. Python 3.11 to 3.13.

## Build

```
tools/models/.venv/bin/python tools/models/build.py test_crate       one model
tools/models/.venv/bin/python tools/models/build.py all              every model
tools/models/.venv/bin/python tools/models/build.py test_crate --no-preview
tools/models/.venv/bin/python tools/models/build.py palette          redraw the palette swatches
```

Each build prints the triangle count against its budget, the size in metres, the materials used, exports the `.glb`, re-reads it to validate it (height, size, triangle count) and renders the preview sheet. It exits with an error if a model is over budget or fails validation.

## Check a model in the game engine

Open `tools/viewer/model_viewer.tscn` in Godot and press F6. It shows every `.glb` in `assets/models/` under the game's DAY lighting, with a 1.8 m person-height marker, triangle/surface counts and a wireframe toggle (W). Left/Right switches model, mouse drag orbits, wheel zooms.

## Writing a model

A model is a file `models/<name>.py`:

```python
from kit import geo

INFO = {"category": "prop"}      # prop, rider, boss, viewmodel or building: sets the triangle budget

def build():
    geo.box("body", (0.9, 0.6, 0.55), (0, 0, 0), "safety_orange", bevel=0.05, base=True)
    geo.hazard_stripes("hazard", width=0.6, height=0.14, center_x=0, bottom_z=0.07, y_front=-0.3)
    geo.join_all("my_model")
```

Kit helpers in `kit/geo.py`: `box` (bevelled, optional `taper`), `cyl` (also cones), `blob` (faceted lump), `poly_prism` (flat polygon plate), `hazard_stripes`, `join_all`. Materials are only taken from the palette by name.

## Conventions

- 1 unit = 1 metre, Z up, origin at the base centre of the model.
- Models face **-Y** in Blender. The glTF export turns that into **+Z**, so in Godot a model faces +Z (rotate it 180 degrees to make it face -Z, Godot's "forward").
- Flat shaded, one bevel pass, no outlines, no normal maps.
- Join everything into one object with one surface per material (`join_all`) unless parts must move separately (wheels, arms, doors): those stay separate objects.
- The scripts and the kit are the source of truth; the `.glb` files are build output but are committed so the game does not need Blender to run.

## Limits

The working environment cannot run Godot, so a model is verified in the Blender preview and by the automatic file check, and then by you in the game viewer. A roadmap step is only ticked once that check is done.
