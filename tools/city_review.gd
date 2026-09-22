extends SceneTree
## Read-only site survey / reproducible city views. Run through run_godot_check.cjs.
const ORIGIN := Vector3(-36418.484, 234.52104, 413.42773)
const SPACING := 15.258789
var output := "res://subagent-artifacts/city-revision/baseline"
var survey := false
var closeups := false
var motion := false
var catalog := false

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg == "--survey": survey = true
		elif arg == "--closeups": closeups = true
		elif arg == "--motion": motion = true
		elif arg == "--catalog": catalog = true
		elif arg.begins_with("--out="): output = arg.trim_prefix("--out=")
	_run.call_deferred()

func _run() -> void:
	for audio in root.get_node("AudioManager").get_children():
		if audio is AudioStreamPlayer:
			audio.stop()
			audio.stream = null
	assert(DirAccess.make_dir_recursive_absolute(output) == OK)
	if survey:
		_survey()
	else:
		await _views()
	print("PASS: CITY REVIEW")
	quit()

func _survey() -> void:
	var first := Vector2i(floori((ORIGIN.x - 4000) / SPACING), floori((ORIGIN.z - 3300) / SPACING))
	var size := Vector2i(435, 415)
	var regions: Dictionary = {}
	var util := Terrain3DUtil.new()
	var heights: Array = []
	for z in size.y:
		for x in size.x:
			var pixel := first + Vector2i(x, z)
			var region := Vector2i(floori(pixel.x / 1024.0), floori(pixel.y / 1024.0))
			if not regions.has(region):
				var resource := load("res://terrain/garda_geographic_250km/" + util.location_to_filename(region)) as Terrain3DRegion
				assert(resource != null)
				regions[region] = resource.get_height_map()
			var height: float = regions[region].get_pixel(posmod(pixel.x, 1024), posmod(pixel.y, 1024)).r
			assert(is_finite(height))
			heights.append(snappedf(height, 0.0001))
	var file := FileAccess.open(output.path_join("site.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"origin": [ORIGIN.x, ORIGIN.y, ORIGIN.z], "spacing": SPACING,
		"first": [first.x * SPACING - ORIGIN.x, first.y * SPACING - ORIGIN.z],
		"size": [size.x, size.y], "water": 185.213, "heights": heights}))
	file.close()
	util.free()
	print("SITE vertices=", heights.size(), " regions=", regions.size())

func _views() -> void:
	assert(DisplayServer.get_name() != "headless")
	var scene: Node3D = load("res://scenes/maps/garda_final.tscn").instantiate()
	root.add_child(scene)
	var camera := Camera3D.new()
	camera.far = 100000.0
	camera.fov = 62.0
	scene.add_child(camera)
	camera.make_current()
	var terrain: Terrain3D = scene.get_node("GardaTerrain")
	terrain.set_camera(camera)
	var settings_class = load("res://scripts/ui/settings_manager.gd")
	var settings: Dictionary = settings_class.load_settings("user://city_review_nonexistent.cfg")
	settings.merge(settings_class.QUALITY_PRESETS[settings_class.QUALITY_ULTRA], true)
	settings.merge({"upscaler": settings_class.UPSCALER_OFF, "aa_mode": settings_class.AA_TAA,
		"vsync": false, "fps_limit": 0, "resolution": "1920x1080", "window_mode": 0}, true)
	settings_class.apply_settings(settings)
	root.size = Vector2i(1920, 1080)
	root.content_scale_size = root.size
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	var sky = scene.get_node("Sky3D")
	sky.get_node("SkyDome").process_method = 2
	var driver = scene.get_node("SunshineCloudsDriverGD")
	driver.set_process(false)
	driver.retrieve_texture_data()
	var clouds = driver.clouds_resource
	clouds.current_time = 0.0
	clouds.extra_large_scale_clouds_position = Vector3.ZERO
	clouds.large_scale_clouds_position = Vector3.ZERO
	clouds.medium_scale_clouds_position = Vector3.ZERO
	clouds.detail_clouds_position = Vector3.ZERO
	var views := [
		{"id": "overview", "pos": Vector3(2400, 2700, 3700), "target": Vector3(-850, 0, -150)},
		{"id": "bay", "pos": Vector3(-3800, 1050, -2100), "target": Vector3(-900, 30, 0)},
		{"id": "district", "pos": Vector3(-650, 240, 500), "target": Vector3(-1700, 30, -400)},
		{"id": "taxi", "pos": Vector3(425, 8, 1040), "target": Vector3(190, 5, 1110)},
	]
	if closeups:
		views = [
			{"id": "street", "pos": Vector3(-1170, 60, 535), "target": Vector3(-1520, 12, 280)},
			{"id": "waterfront", "pos": Vector3(-1050, 75, -2220), "target": Vector3(-1420, -35, -1940)},
			{"id": "apron", "pos": Vector3(445, 12, 1260), "target": Vector3(300, 7, 980)},
			{"id": "approach", "pos": Vector3(0, 75, 1770), "target": Vector3(0, 1, 150)},
		]
	if catalog:
		views = [
			{"id":"city_street", "pos":Vector3(-1230,35,250), "target":Vector3(-1560,20,250)},
			{"id":"skyline", "pos":Vector3(-1100,165,-580), "target":Vector3(-1580,60,-50)},
			{"id":"telecom", "pos":Vector3(-3080,115,-660), "target":Vector3(-2810,30,-830)},
			{"id":"bridge", "pos":Vector3(-1090,50,-2130), "target":Vector3(-1130,-30,-1780)},
			{"id":"bay_road", "pos":Vector3(-1840,95,-1930), "target":Vector3(-1890,-10,-1580)},
			{"id":"control_tower", "pos":Vector3(-335,38,750), "target":Vector3(-520,35,660)},
			{"id":"logistics", "pos":Vector3(1260,100,1430), "target":Vector3(880,20,1000)},
			{"id":"user_road_link", "pos":Vector3(1220,130,2520), "target":Vector3(1320,42,2586)},
		]
	var results: Array = []
	for view in views:
		camera.position = ORIGIN + view.pos
		camera.look_at(ORIGIN + view.target)
		var forest = scene.get_node("Forests")
		forest.update_center(camera.position)
		while not forest.built: await process_frame
		await create_timer(2.0).timeout
		var frames: Array[float] = []
		var gpu: Array[float] = []
		var start := Time.get_ticks_usec()
		var previous := start
		while Time.get_ticks_usec() - start < 3000000:
			await RenderingServer.frame_post_draw
			var now := Time.get_ticks_usec()
			frames.append((now - previous) / 1000.0)
			previous = now
			gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()))
		var elapsed := (Time.get_ticks_usec() - start) / 1000.0
		frames.sort()
		gpu.sort()
		results.append({"view": view.id, "fps": frames.size() * 1000.0 / elapsed,
			"gpu_ms": gpu[gpu.size() / 2], "p95_ms": frames[int(frames.size() * 0.95)],
			"max_ms": frames.back(), "trees": forest.tree_count,
			"draws": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)})
		assert(root.get_texture().get_image().save_png(output.path_join(view.id + ".png")) == OK)
		print("CITY VIEW ", results.back())
	if motion:
		camera.position = ORIGIN + Vector3(-800, 200, 850)
		camera.position.y = terrain.data.get_height(camera.position) + 200.0
		camera.look_at(camera.position + Vector3(-900, -160, -1500))
		var forest = scene.get_node("Forests")
		forest.update_center(camera.position)
		while not forest.built: await process_frame
		await create_timer(2.0).timeout
		var frames: Array[float] = []
		var gpu: Array[float] = []
		var start := Time.get_ticks_usec()
		var previous := start
		while Time.get_ticks_usec() - start < 8000000:
			var t := float(Time.get_ticks_usec() - start) / 8000000.0
			camera.position = ORIGIN + Vector3(-800, 0, 850).lerp(Vector3(-2400, 0, -1500), t)
			camera.position.y = terrain.data.get_height(camera.position) + 200.0
			camera.look_at(camera.position + Vector3(-900, -160, -1500))
			await RenderingServer.frame_post_draw
			var now := Time.get_ticks_usec()
			frames.append((now - previous) / 1000.0)
			previous = now
			gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()))
		var raw := frames.duplicate()
		frames.sort()
		gpu.sort()
		results.append({"view": "low_pass", "fps": raw.size() * 1000000.0 / (Time.get_ticks_usec() - start),
			"gpu_ms": gpu[gpu.size() / 2], "p95_ms": frames[int(frames.size() * 0.95)],
			"max_ms": frames.back(), "raw_frame_ms": raw})
		assert(root.get_texture().get_image().save_png(output.path_join("low_pass.png")) == OK)
		print("CITY LOW PASS fps=", results.back().fps, " p95_ms=", results.back().p95_ms, " max_ms=", results.back().max_ms)
	var file := FileAccess.open(output.path_join("measurements.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"resolution": "1920x1080 native TAA Ultra", "gpu": RenderingServer.get_video_adapter_name(), "views": results}, "\t"))
	file.close()
	clouds.enabled = false
	RenderingServer.call_on_render_thread(clouds.clear_compute)
	await RenderingServer.frame_post_draw
	scene.queue_free()
	for frame in 8: await process_frame
