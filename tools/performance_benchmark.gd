extends "res://tools/freeroam_benchmark.gd"
## Standalone GPU benchmark, never writes user settings. No --fixed-fps/headless.
## -- --out=user://performance --diagnose --quick --capture --views=spawn,clouds
const Settings = preload("res://scripts/ui/settings_manager.gd")
var output_dir := "user://performance"
var diagnose := false
var capture := false
var view_filter := PackedStringArray()

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg == "--quick": quick = true
		elif arg == "--diagnose": diagnose = true
		elif arg == "--capture": capture = true
		elif arg.begins_with("--out="): output_dir = arg.trim_prefix("--out=")
		elif arg.begins_with("--views="): view_filter = arg.trim_prefix("--views=").split(",")
		else: assert(false, "Unknown option " + arg)
	benchmark.call_deferred()

func benchmark() -> void:
	assert(DisplayServer.get_name() != "headless", "GPU benchmark requires Forward+")
	assert(DirAccess.make_dir_recursive_absolute(output_dir) == OK)
	scene = load("res://scenes/levels/freeroam.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	player = scene.get_node("Player")
	camera = player.get_node("FlightCamera")
	terrain = scene.get_node("GardaLake/GardaTerrain")
	sun = scene.get_node("GardaLake/Sky3D/SunLight")
	world_env = scene.get_node("GardaLake/Sky3D")
	player.set_physics_process(false)
	scene.get_node("GardaLake/TutorialBoundaryController").set_physics_process(false)
	var settings := Settings.load_settings("user://performance_nonexistent.cfg")
	settings.merge(Settings.QUALITY_PRESETS[Settings.QUALITY_ULTRA], true)
	settings.merge({"resolution": "1920x1080", "window_mode": 0, "vsync": false, "fps_limit": 0,
		"render_scale": 1.0, "upscaler": Settings.UPSCALER_FSR2}, true)
	Settings.apply_settings(settings)
	root.size = Vector2i(1920, 1080)
	root.content_scale_size = root.size
	viewport_rid = root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(viewport_rid, true)
	# Freeze weather for repeatable A/B, retaining all shader work and quality budgets.
	var driver = scene.get_node("GardaLake/SunshineCloudsDriverGD")
	driver.set_process(false)
	var clouds = driver.clouds_resource
	clouds.current_time = 0.0
	clouds.extra_large_scale_clouds_position = Vector3.ZERO
	clouds.large_scale_clouds_position = Vector3.ZERO
	clouds.medium_scale_clouds_position = Vector3.ZERO
	clouds.detail_clouds_position = Vector3.ZERO
	world_env.get_node("SkyDome").process_method = 2
	var locations := [
		{"id": "spawn", "pos": Vector3(0, 7114, 0), "pitch": -6.0, "yaw": 15.0},
		{"id": "clouds", "pos": Vector3(-60000, 3800, -10000), "pitch": -3.0, "yaw": 0.0},
		{"id": "lake", "pos": Vector3(-60000, 1200, 30000), "pitch": 2.0, "yaw": -55.0},
		{"id": "alpine", "pos": Vector3(-119420, 3400, -115080), "pitch": -24.0, "yaw": 80.0},
		{"id": "airport", "pos": Vector3(-36418, 275, 1500), "pitch": -2.0, "yaw": 0.0},
		{"id": "flight", "path_from": Vector3(-80000, 900, 60000), "path_to": Vector3(-74000, 900, 54000), "pitch": -3.0, "yaw": 0.0},
	]
	place_aircraft(locations[0], 0.0)
	while not scene.get_node("GardaLake/Forests").built:
		await process_frame
	await create_timer(8.0).timeout
	var variants := ["ultra", "clouds_off", "terrain_off", "shadows_off", "hud_off"] if diagnose else ["ultra"]
	for round_index in range(1 if quick else 3):
		for loc in locations:
			if not view_filter.is_empty() and loc.id not in view_filter: continue
			for variant in variants:
				clouds.enabled = variant != "clouds_off"
				terrain.visible = variant != "terrain_off"
				sun.shadow_enabled = variant != "shadows_off"
				scene.get_node("CombatHUD").visible = variant != "hud_off"
				await measure(loc, {"phase": "performance", "round": round_index + 1, "preset": variant}, 2.0 if quick else 3.5, 3.0 if quick else 6.0)
				if capture and round_index == 0:
					await RenderingServer.frame_post_draw
					assert(root.get_texture().get_image().save_png(output_dir.path_join(loc.id + "_" + variant + ".png")) == OK)
	var file := FileAccess.open(output_dir.path_join("results.json"), FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify({"gpu": RenderingServer.get_video_adapter_name(), "godot": Engine.get_version_info().string,
		"driver": RenderingServer.get_current_rendering_driver_name(), "settings": settings,
		"vsync": DisplayServer.window_get_vsync_mode(), "window": str(root.size),
		"clouds": {"resolution_scale": clouds.resolution_scale, "steps": clouds.max_step_count,
			"lighting_steps": clouds.max_lighting_steps, "coverage": clouds.clouds_coverage}, "results": results}, "\t"))
	file.close()
	world_env.compositor = null
	RenderingServer.call_on_render_thread(clouds.clear_compute)
	await RenderingServer.frame_post_draw
	scene.queue_free()
	for frame in 3: await process_frame
	print("PERFORMANCE BENCHMARK PASS: ", ProjectSettings.globalize_path(output_dir))
	quit()
