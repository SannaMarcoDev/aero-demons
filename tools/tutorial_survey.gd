extends SceneTree
## Run: Godot --path . --script tools/tutorial_survey.gd
## Add -- --check for a headless geometry check; -- --hold to keep the viewer open.
## Add -- --no-clouds for a diagnostic terrain pass (runtime only).
## In viewer: Left/Right change viewpoint, Escape exits. PNGs go to user://tutorial_survey/.

const MAP := "res://scenes/maps/tutorial_map.tscn"
var camera: Camera3D
var views: Array[Dictionary] = []
var selected := 0
var busy := true

func _initialize() -> void:
	call_deferred("survey")

func survey() -> void:
	var map := load(MAP).instantiate() as Node3D
	root.add_child(map)
	current_scene = map
	var terrain = map.get_node("WC_Terrain")
	var regions = terrain.data.get_region_locations()
	assert(not regions.is_empty(), "Terrain has no regions")
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	var region_width: float = terrain.get_region_size() * terrain.vertex_spacing
	for region in regions:
		low = low.min(Vector2(region) * region_width)
		high = high.max((Vector2(region) + Vector2.ONE) * region_width)
	var middle := (low + high) * 0.5
	var height_range: Vector2 = terrain.data.get_height_range()
	var center := Vector3(middle.x, (height_range.x + height_range.y) * 0.5, middle.y)
	var radius: float = maxf(high.x - low.x, high.y - low.y) * 0.42
	var clouds = map.get_node("SunshineCloudsDriverGD").clouds_resource
	var above: float = maxf(clouds.cloud_ceiling + 1800.0, height_range.y + 1000.0)
	views = [
		{"name": "01_spawn", "eye": Vector3(0, 2000, 0), "target": Vector3(0, 1600, -4000)},
		{"name": "02_north", "eye": center + Vector3(0, radius * 0.35, -radius), "target": center},
		{"name": "03_east", "eye": center + Vector3(radius, radius * 0.35, 0), "target": center},
		{"name": "04_south", "eye": center + Vector3(0, radius * 0.35, radius), "target": center},
		{"name": "05_west", "eye": center + Vector3(-radius, radius * 0.35, 0), "target": center},
		{"name": "06_above_clouds", "eye": Vector3(middle.x, above, middle.y + radius * 0.4), "target": center},
		{"name": "07_cloud_horizon", "eye": Vector3(middle.x, above, middle.y), "target": Vector3(middle.x, clouds.cloud_ceiling, middle.y - radius)},
		{"name": "08_top", "eye": Vector3(middle.x, maxf(above, height_range.y + radius * 1.5), middle.y), "target": center},
	]
	# Keep lateral views near the terrain instead of hiding them above the cloud deck.
	for i in range(1, 5):
		var eye: Vector3 = views[i].eye
		var ground: float = terrain.data.get_height(eye)
		eye.y = maxf(1500.0, ground + 350.0) if is_finite(ground) else 1800.0
		views[i].eye = eye
	if "--no-clouds" in OS.get_cmdline_user_args():
		clouds.enabled = false
	for view in views:
		assert(view.eye.is_finite() and view.target.is_finite())
		assert(view.eye.distance_to(view.target) > 1.0)
	assert(views[5].eye.y > clouds.cloud_ceiling)
	assert(views[6].eye.y > clouds.cloud_ceiling)
	print("Survey bounds: ", low, " .. ", high, "; heights: ", height_range)
	if "--check" in OS.get_cmdline_user_args():
		print("PASS: 8 valid viewpoints, including two above cloud ceiling")
		quit()
		return
	if DisplayServer.get_name() == "headless":
		push_error("Screenshots require a graphical Forward+ renderer; use -- --check headlessly")
		quit(1)
		return
	camera = Camera3D.new()
	camera.fov = 70.0
	camera.near = 2.0
	camera.far = maxf(100000.0, radius * 8.0)
	root.add_child(camera)
	camera.make_current()
	terrain.set_camera(camera)
	root.size = Vector2i(1280, 720)
	var output := ProjectSettings.globalize_path("user://tutorial_survey/" + Time.get_datetime_string_from_system().replace(":", "-"))
	if DirAccess.make_dir_recursive_absolute(output) != OK:
		push_error("Cannot create " + output)
		quit(1)
		return
	var manifest := FileAccess.open(output.path_join("views.json"), FileAccess.WRITE)
	if manifest == null:
		push_error("Cannot write survey manifest")
		quit(1)
		return
	manifest.store_string(JSON.stringify(views, "\t"))
	manifest.close()
	for i in views.size():
		show_view(i)
		# ponytail: fixed settling time; use convergence detection if cloud history needs it.
		await create_timer(3.0).timeout
		await RenderingServer.frame_post_draw
		var error := root.get_texture().get_image().save_png(output.path_join(views[i].name + ".png"))
		if error != OK:
			push_error("Screenshot failed: " + error_string(error))
			quit(1)
			return
		print("Captured ", views[i].name)
	print("Survey saved: ", output)
	busy = false
	if "--hold" not in OS.get_cmdline_user_args():
		quit()

func show_view(index: int) -> void:
	selected = wrapi(index, 0, views.size())
	var view := views[selected]
	camera.position = view.eye
	var direction: Vector3 = view.target - view.eye
	camera.look_at(view.target, Vector3.FORWARD if absf(direction.normalized().y) > 0.99 else Vector3.UP)
	root.title = "Tutorial survey — " + view.name + " | Left/Right: view | Escape: exit"

func _process(_delta: float) -> bool:
	if Input.is_physical_key_pressed(KEY_ESCAPE):
		quit()
	if not busy:
		var step := int(Input.is_action_just_pressed("ui_right")) - int(Input.is_action_just_pressed("ui_left"))
		if step != 0:
			show_view(selected + step)
	return false
