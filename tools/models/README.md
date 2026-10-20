# 3D models

**Claude is the 3D modeler for this project.** Models are built with **Blender as a Python module (`bpy`)**: every model is a script in this folder, so it can be rebuilt, tweaked (change a number, rerun) and reviewed.

- Output: `assets/models/<name>.glb`, plus a turntable preview image next to it.
- Style and budgets: `docs/ART_DIRECTION.md` (chunky, bevelled low-poly, bright, hazard-stripe and hi-vis accents, no outlines).
- Scale: 1 unit = 1 metre. One shared palette and material set so all models match.
- Setup: `python3 -m venv venv && venv/bin/pip install bpy` (Blender 5.x as a Python module; previews render with the CPU renderer, no GPU needed).
- Limit: the working environment cannot run Godot, so each model is checked in the Blender preview, and then in the game by the owner.

The scripts and the shared style kit are created in the first steps of Milestone F in `README.md`.
