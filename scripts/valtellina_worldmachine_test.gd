extends Node3D
## Isolated, read-only benchmark. Run this scene with -- --capture-wm for PNGs.
## Keys 1–4: viewpoints; G: geometry reference; U: unlit color; Esc: exit.
const OUTPUT = "res://terrain/worldmachine/validation"
const VIEWS = [
	["01_overview", Vector3(-360, 35000, -360), Vector3(-360, 0, -360)],
	["02_valley", Vector3(-6500, 850, -360), Vector3(1500, 450, -360)],
	["03_slope", Vector3(1000, 2500, 1200), Vector3(0, 1700, -4500)],
	["04_summit", Vector3(-1300, 5100, -7000), Vector3(-1320, 3400, -11820)],
]
@onready var terrain: Terrain3D = $Terrain3D
@onready var camera: Camera3D = $Camera3D

func _ready() -> void:
	terrain.set_camera(camera)
	set_view(0)
	if "--capture-wm" in OS.get_cmdline_user_args():
		await capture()

func set_view(index: int) -> void:
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL if index == 0 else Camera3D.PROJECTION_PERSPECTIVE
	camera.size = 33000.0
	camera.fov = 65.0
	camera.position = VIEWS[index][1]
	camera.look_at(VIEWS[index][2], Vector3.FORWARD if index == 0 else Vector3.UP)
	DisplayServer.window_set_title("WM Valtellina | " + VIEWS[index][0] + " | 1-4 views, G geometry, U unlit")

func _unhandled_key_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo():
		return
	if event.keycode >= KEY_1 and event.keycode <= KEY_4:
		set_view(event.keycode - KEY_1)
	elif event.keycode == KEY_G:
		terrain.material.set_shader_param("geometry_only", not terrain.material.get_shader_param("geometry_only"))
	elif event.keycode == KEY_U:
		terrain.material.set_shader_param("unlit_colormap", not terrain.material.get_shader_param("unlit_colormap"))
	elif event.keycode == KEY_ESCAPE:
		get_tree().quit()

func save_frame(filename: String) -> void:
	# Allow clipmap recentering and GPU uploads before reading the actual viewport.
	for frame in range(20):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	assert(not image.is_empty(), "Empty viewport capture")
	var error := image.save_png(OUTPUT.path_join(filename + ".png"))
	assert(error == OK, "Failed to save screenshot")
	print("Screenshot: ", filename)

func capture() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	for frame in range(10):
		await get_tree().process_frame
	assert(terrain.vertex_spacing == 5.0)
	assert(terrain.material.shader_override_enabled)
	assert(terrain.material.get_shader_param("worldmachine_colormap") != null)
	# Compare actual Terrain3D heights with the original R16 at world-grid samples.
	var source := FileAccess.open("res://terrain/valtellina_heightmap_6000x6000.r16", FileAccess.READ)
	assert(source != null)
	var max_error := 0.0
	for z in range(-14000, 15000, 2000):
		for x in range(-14000, 15000, 2000):
			var column := int((x + 15360) / 5)
			var row := int((z + 15360) / 5)
			source.seek(2 * (row * 6000 + column))
			var expected := 220.13600158691406 + source.get_16() / 65535.0 * 3458.289291381836
			var actual := terrain.data.get_height(Vector3(x, 0, z))
			assert(is_finite(actual), "Missing terrain height")
			max_error = maxf(max_error, absf(actual - expected))
	source.close()
	print("Terrain3D ", terrain.get_version(), " | regions ", terrain.data.get_region_count(), " | max R16 height error (m): ", max_error)
	assert(max_error < 0.1, "Terrain coordinates differ from verified R16 origin")
	# Read-only samples for independent alignment checks.
	var samples := FileAccess.open(OUTPUT.path_join("terrain_heights.csv"), FileAccess.WRITE)
	samples.store_line("x,z,height")
	for z in range(-15000, 15001, 100):
		for x in range(-15000, 15001, 100):
			samples.store_line("%d,%d,%.6f" % [x, z, terrain.data.get_height(Vector3(x, 0, z))])
	samples.close()
	for i in range(VIEWS.size()):
		set_view(i)
		assert(camera.position.y > terrain.data.get_height(camera.position) + 20.0, "Camera inside terrain")
		terrain.material.set_shader_param("geometry_only", false)
		await save_frame(VIEWS[i][0] + "_color")
		terrain.material.set_shader_param("geometry_only", true)
		await save_frame(VIEWS[i][0] + "_geometry")
	terrain.material.set_shader_param("geometry_only", false)
	terrain.material.set_shader_param("unlit_colormap", true)
	set_view(0)
	await save_frame("01_overview_unlit")
	get_tree().quit()
