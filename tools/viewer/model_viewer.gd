extends Node3D
# Model viewer (development tool, not part of the game).
# Open tools/viewer/model_viewer.tscn in Godot and press F6 (Run Current Scene).
# It shows every .glb in res://assets/models/ under the game's DAY lighting, next to a 1.8 m person-height marker.
#
#   Left / Right arrows   previous / next model
#   Mouse drag            orbit            Mouse wheel   zoom
#   W                     wireframe on / off        R   reset the camera
#
# The text shows triangles, size in metres and the number of surfaces (draw calls) of the model.

const MODEL_DIR = "res://assets/models"
const SUN_COLOR = Color("#fff4e0")
const SKY_TOP = Color("#4f98d8")
const SKY_HORIZON = Color("#dbe9ee")

var paths = []
var index = 0
var model: Node3D = null
var cam: Camera3D
var label: Label
var yaw = 0.6
var pitch = -0.3
var dist = 4.0
var focus = Vector3(0.0, 0.5, 0.0)
var wire = false

func _ready() -> void:
	_build_scene()
	_find_models()
	if paths.is_empty():
		label.text = "No .glb files found in %s\nBuild one with: python tools/models/build.py test_crate" % MODEL_DIR
		return
	_show(0)

func _build_scene() -> void:
	var sky_mat = ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = SKY_TOP
	sky_mat.sky_horizon_color = SKY_HORIZON
	sky_mat.ground_horizon_color = SKY_HORIZON
	var sky = Sky.new()
	sky.sky_material = sky_mat
	var env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.68, 0.76)
	env.ambient_light_energy = 0.75
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	var we = WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun = DirectionalLight3D.new()
	sun.light_color = SUN_COLOR
	sun.light_energy = 1.1
	sun.rotation_degrees = Vector3(-55.0, -30.0, 0.0)
	sun.shadow_enabled = true
	add_child(sun)

	var floor_mesh = MeshInstance3D.new()
	var plane = PlaneMesh.new()
	plane.size = Vector2(40.0, 40.0)
	floor_mesh.mesh = plane
	var floor_mat = StandardMaterial3D.new()
	floor_mat.albedo_color = Color("#C9C5BC")
	floor_mat.roughness = 0.9
	floor_mesh.material_override = floor_mat
	add_child(floor_mesh)

	# a 1.8 m tall marker to judge scale
	var marker = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = Vector3(0.5, 1.8, 0.3)
	marker.mesh = box
	marker.position = Vector3(2.0, 0.9, 0.0)
	var marker_mat = StandardMaterial3D.new()
	marker_mat.albedo_color = Color(0.45, 0.5, 0.58, 0.55)
	marker_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	marker.material_override = marker_mat
	add_child(marker)

	cam = Camera3D.new()
	cam.fov = 60.0
	add_child(cam)

	var layer = CanvasLayer.new()
	add_child(layer)
	label = Label.new()
	label.position = Vector2(16.0, 12.0)
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	label.add_theme_constant_override("outline_size", 6)
	layer.add_child(label)

func _find_models() -> void:
	paths.clear()
	var dir = DirAccess.open(MODEL_DIR)
	if dir == null:
		return
	for f in dir.get_files():
		if f.ends_with(".glb"):
			paths.append(MODEL_DIR + "/" + f)
	paths.sort()

func _collect_meshes(node: Node, out: Array) -> void:
	if node is MeshInstance3D:
		out.append(node)
	for c in node.get_children():
		_collect_meshes(c, out)

func _show(i: int) -> void:
	index = posmod(i, paths.size())
	if model != null:
		model.queue_free()
		model = null
	var res = load(paths[index])
	if res == null or not (res is PackedScene):
		label.text = "Could not load " + paths[index]
		return
	model = res.instantiate()
	add_child(model)

	var meshes = []
	_collect_meshes(model, meshes)
	var tris = 0
	var surfaces = 0
	var box = AABB()
	var first = true
	for mi in meshes:
		var m: Mesh = mi.mesh
		if m == null:
			continue
		surfaces += m.get_surface_count()
		for s in range(m.get_surface_count()):
			var arrays = m.surface_get_arrays(s)
			var idx = arrays[Mesh.ARRAY_INDEX]
			if idx != null:
				tris += idx.size() / 3
			else:
				tris += arrays[Mesh.ARRAY_VERTEX].size() / 3
		var bb: AABB = mi.global_transform * mi.get_aabb()
		if first:
			box = bb
			first = false
		else:
			box = box.merge(bb)
	focus = box.get_center()
	dist = maxf(box.size.length() * 1.3, 1.0)
	label.text = "%s   (%d / %d)\n%d triangles   %d surfaces   size %.2f x %.2f x %.2f m (x, y, z)\nLeft/Right: model   drag: orbit   wheel: zoom   W: wireframe   R: reset" % [
		paths[index].get_file(), index + 1, paths.size(), tris, surfaces, box.size.x, box.size.y, box.size.z]
	_place_camera()

func _place_camera() -> void:
	var dir = Vector3(sin(yaw) * cos(pitch), -sin(pitch), cos(yaw) * cos(pitch))
	cam.position = focus + dir * dist
	cam.look_at(focus, Vector3.UP)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		yaw -= event.relative.x * 0.01
		pitch = clampf(pitch - event.relative.y * 0.01, -1.4, 1.4)
		_place_camera()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			dist = maxf(0.3, dist * 0.9)
			_place_camera()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			dist = minf(60.0, dist * 1.1)
			_place_camera()
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_RIGHT and not paths.is_empty():
			_show(index + 1)
		elif event.keycode == KEY_LEFT and not paths.is_empty():
			_show(index - 1)
		elif event.keycode == KEY_W:
			wire = not wire
			get_viewport().debug_draw = Viewport.DEBUG_DRAW_WIREFRAME if wire else Viewport.DEBUG_DRAW_DISABLED
		elif event.keycode == KEY_R and not paths.is_empty():
			yaw = 0.6
			pitch = -0.3
			_show(index)
