extends RefCounted
# Viewmodel pass (Milestone F2): the gun and the gummy worm are drawn by their own camera, in their own SubViewport,
# and composited over the world, below the HUD. Two things follow from that:
#   - the viewmodel has its own field of view, so it no longer stretches with the FOV slider, the dash kick or other camera zooms
#   - it has its own depth buffer, so the gun can never poke into a wall, a rider or a boss
# The gun nodes stay children of the main camera (lighting, the muzzle light and the dart spawn point keep working);
# they are only moved to render layer 2, which the main camera no longer draws and this camera draws alone.
# Set VIEWMODEL_PASS to false in main.gd to go back to the old single-camera look.

const LAYER_MASK = 2  # render layer 2, as a bit mask
const FOV_HIP = 78.0  # same as the default world FOV, so the gun looks the same as before at default settings
const FOV_ADS = 40.0  # zoomed while aiming down sights, like the world camera
const NEAR = 0.01
const FAR = 4.0  # the gun is under a metre long; a short range keeps depth precision and the extra shadow pass tiny

var g = null
var viewport: SubViewport = null
var camera: Camera3D = null
var env: Environment = null


func _init(game) -> void:
	g = game


# main_cam: the world camera; nodes: the viewmodel roots (gun, rubber); world_env: the world's Environment (for ambient light)
func setup(main_cam: Camera3D, nodes: Array, world_env: Environment) -> void:
	main_cam.cull_mask = main_cam.cull_mask & ~LAYER_MASK
	for n in nodes:
		_to_layer(n)

	var layer = CanvasLayer.new()
	layer.layer = 0  # the HUD is on layer 1, so it draws over the gun
	g.add_child(layer)
	var box = SubViewportContainer.new()
	box.stretch = true  # the viewport follows the window size
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE  # never swallow clicks meant for the menus
	layer.add_child(box)
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	viewport = SubViewport.new()
	viewport.transparent_bg = true
	viewport.handle_input_locally = false
	viewport.msaa_3d = g.get_viewport().msaa_3d
	viewport.screen_space_aa = g.get_viewport().screen_space_aa
	box.add_child(viewport)  # no own World3D: it draws the same world as the main viewport

	# own environment: no sky (the world shows through), no glow, same ambient light and tone mapping as the world
	env = Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.tonemap_mode = world_env.tonemap_mode
	env.tonemap_exposure = world_env.tonemap_exposure
	env.glow_enabled = false
	sync_env(world_env)

	camera = Camera3D.new()
	camera.cull_mask = LAYER_MASK
	camera.near = NEAR
	camera.far = FAR
	camera.fov = FOV_HIP
	camera.environment = env
	viewport.add_child(camera)
	camera.make_current()


# gives the gun's meshes to the viewmodel layer. Lights are left alone: they light by their own cull mask, not by layer.
func _to_layer(n: Node) -> void:
	if n is GeometryInstance3D:  # meshes and the 3D text on the gun
		n.layers = LAYER_MASK
	for ch in n.get_children():
		_to_layer(ch)


# the world environment changes with the lighting theme; the viewmodel follows its ambient light
func sync_env(world_env: Environment) -> void:
	env.ambient_light_color = world_env.ambient_light_color
	env.ambient_light_energy = world_env.ambient_light_energy
	env.tonemap_mode = world_env.tonemap_mode
	env.tonemap_exposure = world_env.tonemap_exposure


func set_msaa(mode: int) -> void:
	viewport.msaa_3d = mode


func set_screen_space_aa(mode: int) -> void:
	viewport.screen_space_aa = mode


# once per frame after the world camera has moved: same position and roll (so shake and slide tilt carry over), own FOV
func update(ads_t: float) -> void:
	camera.global_transform = g.cam.global_transform
	camera.fov = lerpf(FOV_HIP, FOV_ADS, ads_t)


# Where a dart should leave the gun. The muzzle is where the viewmodel camera draws it; the world camera may use another FOV,
# so the point is taken from the muzzle's spot on screen and put back into the world along the world camera's ray.
func muzzle_point(muzzle: Node3D) -> Vector3:
	var p = muzzle.global_position
	if camera == null or viewport.size.x <= 0 or viewport.size.y <= 0:
		return p
	update(g.ads_t)
	var depth = -(g.cam.global_transform.affine_inverse() * p).z
	if depth < 0.05:
		return p
	var shown = camera.unproject_position(p)
	var main_size = g.get_viewport().get_visible_rect().size
	var on_main = Vector2(
		shown.x / float(viewport.size.x) * main_size.x,
		shown.y / float(viewport.size.y) * main_size.y
	)
	return g.cam.project_position(on_main, depth)
