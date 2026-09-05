extends "res://scripts/valtellina_forest_test.gd"
## Reuse the existing read-only bake loader; only presentation differs.

const SHOT_DIR := "res://screenshots/valtellina_showcase"

const PRESET_VIEWS := [
	["01_aerial", Vector3(0, 3200, 1800), Vector3(0, 1100, -360)],
	["02_forested_slope", Vector3(500, 1400, 400), Vector3(-200, 800, -360)],
	["03_valley_floor", Vector3(-60, 450, 200), Vector3(-60, 430, -360)],
	["04_close_trees", Vector3(-88, 332, -350), Vector3(-95, 334, -364)],
]

func _ready() -> void:
	cfg = load("res://assets/forest_test/forest_config.tres")
	terrain = $Terrain3D
	camera = $FreeFlyCamera
	terrain.set_camera(camera)
	_load_models()
	_build_forest()
	# Start with the same forested-slope composition used for validation.
	set_preset_view(1)
	if "--capture-showcase" in OS.get_cmdline_user_args():
		camera.mouse_look_enabled = false
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		await _capture_all()

func _unhandled_key_input(_event: InputEvent) -> void:
	# Camera owns input; do not run the benchmark's numbered/debug views.
	pass

func set_preset_view(index: int) -> void:
	assert(index >= 0 and index < PRESET_VIEWS.size())
	camera.position = PRESET_VIEWS[index][1]
	camera.look_at(PRESET_VIEWS[index][2], Vector3.UP)

func _capture_all() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHOT_DIR))
	for frame in range(15):
		await get_tree().process_frame

	for i in PRESET_VIEWS.size():
		set_preset_view(i)
		for frame in range(25):
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		assert(not img.is_empty(), "Viewport capture is empty")
		var out_path := SHOT_DIR.path_join(PRESET_VIEWS[i][0] + ".png")
		var err := img.save_png(out_path)
		assert(err == OK, "Failed to save " + out_path)
		print("Saved screenshot: ", out_path)

	get_tree().quit()
