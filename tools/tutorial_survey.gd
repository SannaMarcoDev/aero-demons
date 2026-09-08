extends SceneTree
## Run: Godot --path . --script tools/tutorial_survey.gd
## Add -- --check for a headless geometry check; -- --hold to keep the viewer open.
## Add -- --no-clouds for a diagnostic terrain pass (runtime only).
## Compare --atmosphere-baseline / --atmosphere-sunshine / --atmosphere-godot.
## These are runtime overrides; baseline restores the pre-polish Sunshine density.
## Add -- --flight for a terrain-following pass, ascent and descent through clouds.
## Record with --write-movie <absolute-path>.avi --fixed-fps 30 (project movie resolution).
## --cloud-dim-sun tests cloud lighting at 25%; --cloud-original-sun restores the old 100%.
## Both affect Sunshine atmosphere too, without changing the terrain sun.
## Terrain probes (runtime only): --taa, --msaa, --terrain-grey, --no-sun-shadows,
## --terrain-soft-mips, --terrain-no-normal-maps.
## --edges adds eight boundary views; --background-noise tests native Terrain3D hills.
## In viewer: Left/Right change viewpoint, Escape exits. PNGs go to user://tutorial_survey/.

const MAP := "res://scenes/maps/garda_lake.tscn"
var camera: Camera3D
var views: Array[Dictionary] = []
var selected := 0
var busy := true
var flight_points: Array[Vector3] = []
var flight_time := 0.0
var flying := false

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
	var args := OS.get_cmdline_user_args()
	if "--edges" in args:
		# Look across each region boundary from 1 km inside, below and above clouds.
		for side in [Vector2.UP, Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT]:
			var edge := Vector2.ZERO
			var best := -INF
			for region in regions:
				var region_center := (Vector2(region) + Vector2.ONE * 0.5) * region_width
				var offset: Vector2 = region_center - middle
				var score: float = offset.dot(side) * 1000.0 - absf(offset.dot(side.orthogonal()))
				if score > best:
					best = score
					edge = region_center + side * region_width * 0.5
			var inside: Vector2 = edge - side * minf(1000.0, region_width * 0.5)
			var eye := Vector3(inside.x, 0, inside.y)
			var ground: float = terrain.data.get_height(eye)
			assert(is_finite(ground), "Boundary viewpoint must be on a terrain region")
			for altitude in [maxf(ground + 500.0, 1500.0), above]:
				eye.y = altitude
				views.append({"name": "edge_%02d" % views.size(), "eye": eye,
					"target": Vector3(edge.x + side.x * 4000.0, 0, edge.y + side.y * 4000.0)})
	if "--background-noise" in args:
		terrain.material.world_background = 2
		assert(terrain.material.world_background == 2)
	var environment: Environment = map.get_node("Sky3D").environment
	if "--taa" in args or "--msaa" in args:
		# Isolate these historical probes from the project's FSR2 default.
		root.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		root.scaling_3d_scale = 1.0
		root.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
		root.use_taa = false
	if "--taa" in args:
		root.use_taa = true
		assert(root.use_taa)
	if "--msaa" in args:
		root.msaa_3d = Viewport.MSAA_4X
		assert(root.msaa_3d == Viewport.MSAA_4X)
	if "--terrain-grey" in args:
		terrain.material.show_grey = true
		assert(terrain.material.show_grey)
	if "--terrain-no-normal-maps" in args:
		for texture in terrain.assets.texture_list:
			texture.normal_depth = 0.0
			assert(is_zero_approx(texture.normal_depth))
	if "--no-sun-shadows" in args:
		map.get_node("Sky3D/SunLight").shadow_enabled = false
		assert(not map.get_node("Sky3D/SunLight").shadow_enabled)
	if "--terrain-soft-mips" in args:
		terrain.material.set_shader_param("depth_blur", 2.0)
		if DisplayServer.get_name() != "headless":
			assert(is_equal_approx(terrain.material.get_shader_param("depth_blur"), 2.0))
	print("Terrain probes: TAA=", root.use_taa, "; MSAA=", root.msaa_3d,
		"; depth blur=", terrain.material.get_shader_param("depth_blur"))
	assert(int("--atmosphere-baseline" in args) + int("--atmosphere-sunshine" in args)
		+ int("--atmosphere-godot" in args) <= 1, "Choose only one atmosphere preset")
	if "--atmosphere-baseline" in args:
		environment.fog_enabled = false
		clouds.atmospheric_density = 0.4
	elif "--atmosphere-sunshine" in args:
		environment.fog_enabled = false
		clouds.atmospheric_density = 0.8
	elif "--atmosphere-godot" in args:
		clouds.atmospheric_density = 0.0
		environment.fog_enabled = true
		environment.fog_density = 0.000035
		environment.fog_light_color = Color(0.74, 0.84, 0.96)
		environment.fog_aerial_perspective = 0.65
		environment.fog_sky_affect = 0.0
	assert(not ("--cloud-dim-sun" in args and "--cloud-original-sun" in args), "Choose one cloud light preset")
	var driver = map.get_node("SunshineCloudsDriverGD")
	if "--cloud-dim-sun" in args:
		driver.directional_light_power_multiplier = 0.25
	elif "--cloud-original-sun" in args:
		driver.directional_light_power_multiplier = 1.0
	driver.retrieve_texture_data()
	var expected_cloud_power: float = round(2.0 * driver.directional_light_power_multiplier * 10.0) / 10.0
	assert(is_equal_approx(clouds.directional_lights_data[1].w, expected_cloud_power))
	assert(is_equal_approx(map.get_node("Sky3D/SunLight").light_energy, 2.0), "Keep terrain lighting unchanged")
	print("Cloud sun energy: ", clouds.directional_lights_data[1].w)
	if "--no-clouds" in args:
		clouds.enabled = false
	print("Atmosphere: ", args, "; environment fog=", environment.fog_enabled,
		"; density=", environment.fog_density, "; Sunshine density=", clouds.atmospheric_density)
	for view in views:
		assert(view.eye.is_finite() and view.target.is_finite())
		assert(view.eye.distance_to(view.target) > 1.0)
	assert(views[5].eye.y > clouds.cloud_ceiling)
	assert(views[6].eye.y > clouds.cloud_ceiling)
	print("Survey bounds: ", low, " .. ", high, "; heights: ", height_range)
	print("Terrain texture filtering: ", terrain.material.get_texture_filtering(), " (0=linear)")
	if DisplayServer.get_name() != "headless":
		var shader_code := RenderingServer.shader_get_code(terrain.material.get_shader_rid())
		for line in shader_code.split("\n"):
			if "uniform" in line and ("_texture_array_albedo" in line or "_texture_array_normal" in line):
				print("Terrain active sampler: ", line)
	if "--flight" in args:
		# Western valley: the old x=0 route starts above the low cloud floor.
		# Diagnostic camera, not aircraft physics: follow sampled ground with 300 m clearance.
		for i in range(121):
			var point := Vector3(-16000, 0, -i * 20.0)
			var ground: float = terrain.data.get_height(point)
			assert(is_finite(ground), "Flight path leaves terrain")
			point.y = ground + 300.0
			flight_points.append(point)
		assert(flight_points[-1].y < clouds.cloud_floor, "Ascent must start below clouds")
		flight_points.append(Vector3(flight_points[-1].x, above, flight_points[-1].z))
		assert(flight_points[-1].y > clouds.cloud_ceiling)
		print("Flight: 12 s low pass, 20 s ascent, 4 s above clouds, 20 s descent")
	if "--check" in args:
		if "--atmosphere-godot" in args:
			assert(environment.fog_enabled and is_zero_approx(clouds.atmospheric_density))
			assert(is_equal_approx(environment.fog_density, 0.000035))
		else:
			assert(not environment.fog_enabled, "Avoid stacking fog systems")
			var expected := 0.4 if "--atmosphere-baseline" in args else 0.8
			assert(is_equal_approx(clouds.atmospheric_density, expected))
		print("PASS: atmosphere preset and ", views.size(), " valid viewpoints, including two above cloud ceiling")
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
	if "--flight" in args:
		camera.position = flight_points[0]
		camera.look_at(camera.position + Vector3(0, -0.1, -1))
		await create_timer(3.0).timeout
		flying = true
		return
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

func _process(delta: float) -> bool:
	if flying:
		flight_time += delta
		if flight_time < 12.0:
			var sample := flight_time * 10.0
			var index := mini(int(sample), 119)
			camera.position = flight_points[index].lerp(flight_points[index + 1], sample - index)
		elif flight_time < 32.0:
			camera.position = flight_points[120].lerp(flight_points[121], (flight_time - 12.0) / 20.0)
		elif flight_time < 36.0:
			camera.position = flight_points[121]
		elif flight_time < 56.0:
			camera.position = flight_points[121].lerp(flight_points[120], (flight_time - 36.0) / 20.0)
		else:
			print("PASS: flight completed (low pass, ascent, descent)")
			quit()
		camera.look_at(camera.position + Vector3(0, -0.1, -1))
		root.title = "Tutorial flight | %.1f s | altitude %.0f m" % [flight_time, camera.position.y]
	if Input.is_physical_key_pressed(KEY_ESCAPE):
		quit()
	if not busy:
		var step := int(Input.is_action_just_pressed("ui_right")) - int(Input.is_action_just_pressed("ui_left"))
		if step != 0:
			show_view(selected + step)
	return false
