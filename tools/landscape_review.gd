extends SceneTree
## Reproducible real-map lookdev; never saves settings, scenes or Terrain3D regions.
## Run with tools/run_godot_check.cjs; -- --out=... --style=authored --motion
const Settings = preload("res://scripts/ui/settings_manager.gd")
var output := "res://subagent-artifacts/landscape/baseline"
var style := "authored"
var motion := false
var video := false
var gameplay := false
var views_filter := PackedStringArray()
var scene: Node3D
var camera: Camera3D
var terrain: Terrain3D
var results: Array = []

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): output = arg.trim_prefix("--out=")
		elif arg.begins_with("--style="): style = arg.trim_prefix("--style=")
		elif arg == "--motion": motion = true
		elif arg == "--gameplay": gameplay = true
		elif arg == "--video":
			motion = true
			video = true
		elif arg.begins_with("--views="): views_filter = arg.trim_prefix("--views=").split(",")
	_run.call_deferred()

func _run() -> void:
	assert(DisplayServer.get_name() != "headless")
	assert(DirAccess.make_dir_recursive_absolute(output) == OK)
	scene = load("res://scenes/levels/freeroam.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	var player = scene.get_node("Player")
	player.set_physics_process(false)
	player.hide()
	scene.get_node("CombatHUD").hide()
	for node in scene.find_children("*", "CanvasLayer", true, false): node.hide()
	scene.get_node("GardaLake/TutorialBoundaryController").set_physics_process(false)
	var settings := Settings.load_settings("user://landscape_nonexistent.cfg")
	settings.merge(Settings.QUALITY_PRESETS[Settings.QUALITY_ULTRA], true)
	settings.merge({"upscaler": Settings.UPSCALER_OFF, "aa_mode": Settings.AA_TAA,
		"vsync": false, "fps_limit": 0, "resolution": "1920x1080", "window_mode": 0}, true)
	Settings.apply_settings(settings)
	root.size = Vector2i(1920, 1080)
	root.content_scale_size = root.size
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	camera = Camera3D.new()
	camera.far = 400000
	camera.fov = 70
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	scene.add_child(camera)
	camera.make_current()
	terrain = scene.get_node("GardaLake/GardaTerrain")
	terrain.set_camera(camera)
	var sky = scene.get_node("GardaLake/Sky3D")
	sky.get_node("SkyDome").process_method = 2
	var driver = scene.get_node("GardaLake/SunshineCloudsDriverGD")
	driver.set_process(false)
	driver.retrieve_texture_data()
	var clouds = driver.clouds_resource
	clouds.current_time = 0.0
	clouds.extra_large_scale_clouds_position = Vector3.ZERO
	clouds.large_scale_clouds_position = Vector3.ZERO
	clouds.medium_scale_clouds_position = Vector3.ZERO
	clouds.detail_clouds_position = Vector3.ZERO
	if style == "no_clouds": clouds.enabled = false
	if style not in ["authored", "no_clouds"]:
		var env: Environment = sky.environment
		env.fog_enabled = true
		env.fog_mode = Environment.FOG_MODE_DEPTH
		env.fog_light_color = Color(0.57, 0.67, 0.76)
		env.fog_light_energy = 0.7
		env.fog_sky_affect = 0.0
		env.fog_depth_begin = 700.0
		env.fog_depth_end = 65000.0
		env.fog_depth_curve = 0.85
		if style == "overcast":
			sky.sun_energy = 1.15
			env.ambient_light_color = Color(0.73, 0.82, 0.94)
			env.ambient_light_energy = 0.65
			env.fog_depth_end = 28000.0
			clouds.clouds_coverage = 0.90
		elif style == "clear":
			clouds.clouds_coverage = 0.76
			sky.sun_energy = 1.65
	if style == "scattered":
		sky.environment.fog_enabled = false # Sunshine already supplies altitude-aware aerial perspective.
		clouds.clouds_coverage = 0.72
		clouds.clouds_density = 0.022
		clouds.atmospheric_density = 1.3
		clouds.cloud_floor = 2600.0
		clouds.cloud_ceiling = 4400.0
		clouds.large_noise_scale = 6500.0
		clouds.medium_noise_scale = 1300.0
		clouds.small_noise_scale = 320.0
	while not scene.get_node("GardaLake/Forests").built: await process_frame
	# Fixed world positions, not samples derived from the changing forest population.
	var center := Vector3(0, terrain.data.get_height(Vector3(0, 0, -2200)), -2200)
	var low_pass := center + Vector3(900, 170, 1300)
	low_pass.y = maxf(low_pass.y, terrain.data.get_height(low_pass) + 40.0)
	var views := [
		{"id": "ground", "pos": center + Vector3(75, 3, 140), "target": center + Vector3(0, 9, 0)},
		{"id": "grove", "pos": center + Vector3(140, 65, 220), "target": center + Vector3(0, 8, 0)},
		{"id": "low_flight", "pos": center + Vector3(900, 520, 1300), "target": center + Vector3(-1800, 100, -2600)},
		{"id": "low_pass", "pos": low_pass, "target": low_pass + Vector3(-1500, -70, -2500)},
		{"id": "cruise", "pos": center + Vector3(0, 3300, 5500), "target": center + Vector3(-4000, 0, -7000)},
		{"id": "airport", "pos": Vector3(-36418, 280, 1500), "target": Vector3(-36418, 260, -3000)},
		{"id": "lake", "pos": Vector3(-45300, 430, 40), "target": Vector3(-45242, 408, 0)},
		{"id": "coast", "pos": Vector3(-54000, 460, -11000), "target": Vector3(-50000, 408, -10000)},
		{"id": "alpine", "pos": Vector3(-118420, 2626, -115300), "target": Vector3(-120920, 1876, -114800)},
		{"id": "high", "pos": Vector3(-30000, 11000, 18000), "target": Vector3(-45000, 408, -5000)},
		{"id": "upper_cruise", "pos": center + Vector3(0, 5000, 5500), "target": center + Vector3(-4000, 0, -7000)},
	]
	# Previously outside every authored forest ellipse: coverage regression views.
	for remote in [{"id": "east", "point": Vector3(14000, 0, -4000)}, {"id": "west", "point": Vector3(-22000, 0, -7000)}]:
		var point: Vector3 = remote.point
		point.y = terrain.data.get_height(point) + 350.0
		views.append({"id": remote.id, "pos": point, "target": point + Vector3(1800, -250, -1800)})
	# An additional true meadow-height view: deterministic terrain-only search, unchanged across revisions.
	var meadow := Vector3.ZERO
	for z in range(-3200, -1200, 40):
		for x in range(-800, 800, 40):
			var p := Vector3(x, 0, z)
			p.y = terrain.data.get_height(p)
			if p.is_finite() and p.y > 200 and p.y < 1700 and terrain.data.get_normal(p).y > 0.995:
				meadow = p
				break
		if meadow != Vector3.ZERO: break
	assert(meadow != Vector3.ZERO)
	views.append({"id": "meadow", "pos": meadow + Vector3(0, 1.8, 0), "target": meadow + Vector3(-25, 3, -70)})
	for view in views:
		if not views_filter.is_empty() and view.id not in views_filter: continue
		camera.position = view.pos
		camera.position.y = maxf(camera.position.y, terrain.data.get_height(camera.position) + 3.0)
		camera.look_at(view.target)
		scene.get_node("GardaLake/Forests").update_center(camera.global_position)
		while not scene.get_node("GardaLake/Forests").built: await process_frame
		await create_timer(2.0).timeout
		for round_index in 2:
			var frames: Array[float] = []
			var gpu: Array[float] = []
			var start := Time.get_ticks_usec()
			var previous := start
			while Time.get_ticks_usec() - start < 2000000:
				await RenderingServer.frame_post_draw
				var now := Time.get_ticks_usec()
				frames.append((now - previous) / 1000.0)
				previous = now
				gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()))
			var elapsed := (Time.get_ticks_usec() - start) / 1000.0
			frames.sort()
			gpu.sort()
			results.append({"view": view.id, "round": round_index, "fps": frames.size() * 1000.0 / elapsed,
				"gpu_ms": gpu[gpu.size() / 2], "p95_ms": frames[int(frames.size() * 0.95)], "max_ms": frames.back(),
				"trees": scene.get_node("GardaLake/Forests").tree_count,
				"draws": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
				"primitives": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)})
		assert(root.get_texture().get_image().save_png(output.path_join(view.id + ".png")) == OK)
		print("LANDSCAPE ", results.back())
	if motion or gameplay:
		driver.set_process(true) # Exercise real wind/temporal updates, not only a moving camera.
	if motion:
		# Separate 8-second flight segments; teleport/warmup and screenshot I/O are not timed.
		for route in [
			{"id": "valley", "origin": center},
			{"id": "lake", "origin": Vector3(-45300, 330, 40)},
			{"id": "alpine", "origin": Vector3(-118420, 3100, -115300)},
			{"id": "upper_cruise", "origin": Vector3(0, 4830, -2200)},
		]:
			var origin: Vector3 = route.origin
			camera.position = origin + Vector3(900, 170, 1300)
			camera.position.y = maxf(camera.position.y, terrain.data.get_height(camera.position) + 40.0)
			camera.look_at(camera.position + Vector3(-1500, -70, -2500))
			scene.get_node("GardaLake/Forests").update_center(camera.global_position)
			while not scene.get_node("GardaLake/Forests").built: await process_frame
			await create_timer(2.0).timeout
			var frames: Array[float] = []
			var gpu: Array[float] = []
			var start := Time.get_ticks_usec()
			var previous := start
			while Time.get_ticks_usec() - start < 8000000:
				var t := float(Time.get_ticks_usec() - start) / 8000000.0
				camera.position = origin + Vector3(900, 170, 1300).lerp(Vector3(-800, 90, -900), t)
				camera.position.y = maxf(camera.position.y, terrain.data.get_height(camera.position) + 40)
				camera.look_at(camera.position + Vector3(-1500, -70, -2500))
				await RenderingServer.frame_post_draw
				var now := Time.get_ticks_usec()
				frames.append((now - previous) / 1000.0)
				previous = now
				gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()))
			var raw := frames.duplicate()
			frames.sort()
			gpu.sort()
			results.append({"view": "moving_" + route.id, "fps": raw.size() * 1000000.0 / (Time.get_ticks_usec() - start),
				"gpu_ms": gpu[gpu.size() / 2], "p95_ms": frames[int(frames.size() * 0.95)], "max_ms": frames.back(), "raw_frame_ms": raw})
		camera.position = low_pass
		camera.look_at(camera.position + Vector3(-1500, -70, -2500))
		scene.get_node("GardaLake/Forests").update_center(camera.global_position)
		while not scene.get_node("GardaLake/Forests").built: await process_frame
		await create_timer(2.0).timeout # Settle TAA/cloud history after the return teleport.
		Engine.max_fps = 60
		for frame in 240:
			var t := float(frame) / 239.0
			camera.position = center + Vector3(900, 170, 1300).lerp(Vector3(-800, 90, -900), t)
			camera.position.y = maxf(camera.position.y, terrain.data.get_height(camera.position) + 40)
			camera.look_at(camera.position + Vector3(-1500, -70, -2500))
			await RenderingServer.frame_post_draw
			if video:
				assert(root.get_texture().get_image().save_jpg(output.path_join("motion_%03d.jpg" % frame), 0.94) == OK)
			elif frame % 20 == 0:
				assert(root.get_texture().get_image().save_png(output.path_join("motion_%03d.png" % frame)) == OK)
		Engine.max_fps = 0
	var forest = scene.get_node("GardaLake/Forests")
	if gameplay:
		Engine.max_fps = 0
		player.start_on_ground = false
		var start := Vector3(900, 0, -900)
		start.y = terrain.data.get_height(start) + 600.0
		player.reset_flight(Transform3D(Basis.IDENTITY, start))
		player.set_physics_process(true)
		scene.get_node("CombatHUD").show()
		camera = player.get_node("FlightCamera")
		camera.make_current()
		terrain.set_camera(camera)
		for shot in 3:
			await create_timer(4.0).timeout
			await RenderingServer.frame_post_draw
			assert(player.health > 0.0 and player.global_position.distance_to(start) > 300.0)
			assert(root.get_texture().get_image().save_png(output.path_join("gameplay_%d.png" % shot)) == OK)
			results.append({"view": "gameplay_%d" % shot, "position": str(player.global_position), "health": player.health})
	var report := {"style": style, "godot": Engine.get_version_info().string, "gpu": RenderingServer.get_video_adapter_name(),
		"resolution": str(root.size), "taa": root.use_taa, "trees": forest.tree_count, "last_stream_ms": forest.build_msec,
		"forest_tile_ms": forest.largest_tile_msec, "resident_tiles": forest.tiles.size(),
		"results": results, "grass_tile_ms": scene.get_node("GardaLake/GroundCover").largest_tile_ms, "meadow": str(meadow), "render_memory_mb": Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0}
	var file := FileAccess.open(output.path_join("results.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	for audio in root.get_node("AudioManager").get_children():
		if audio is AudioStreamPlayer:
			audio.stop()
			audio.stream = null
	clouds.enabled = false
	sky.compositor = null
	RenderingServer.call_on_render_thread(clouds.clear_compute)
	await RenderingServer.frame_post_draw
	scene.queue_free()
	for frame in 8: await process_frame
	print("PASS: LANDSCAPE REVIEW")
	quit()
