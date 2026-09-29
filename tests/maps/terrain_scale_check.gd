extends SceneTree

# Read-only: run with --headless for data checks, or without it and with
# -- --render for a single-region GPU comparison (not a whole-map benchmark).
const DATA_DIR = "res://terrain/garda_final_wc_uniform_250km"

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var files := DirAccess.get_files_at(DATA_DIR)
	var count := 0
	var disk_bytes := 0
	for file in files:
		if file.begins_with("terrain3d") and file.ends_with(".res"):
			count += 1
			var handle := FileAccess.open(DATA_DIR.path_join(file), FileAccess.READ)
			disk_bytes += handle.get_length()
	print("DATA regions=", count, " disk_MiB=", disk_bytes / 1048576.0)
	var region = load(DATA_DIR.path_join("terrain3d_00_00.res"))
	var original: Image = region.get_height_map()
	assert(original.get_format() == Image.FORMAT_RF)
	var before := original.get_data().to_float32_array()
	var after := before.duplicate()
	var start := Time.get_ticks_usec()
	for i in after.size():
		after[i] *= 2.0
	var elapsed := Time.get_ticks_usec() - start
	for i in before.size():
		assert(after[i] == before[i] * 2.0)
		if i % original.get_width() != 0:
			assert(is_equal_approx((after[i] - after[i - 1]) / 8.0, (before[i] - before[i - 1]) / 4.0))
	var scaled := Image.create_from_data(original.get_width(), original.get_height(), false, Image.FORMAT_RF, after.to_byte_array())
	assert(scaled.get_data().size() == original.get_data().size())
	assert(original.get_data().to_float32_array() == before)
	print("CHECK PASS samples=", before.size(), " region_size=", original.get_width(), " height_range=", region.get_height_range(), " scaled_range=", region.get_height_range() * 2.0, " scale_ms=", elapsed / 1000.0)
	print("MAP_BYTES_PER_REGION ", original.get_data().size() + region.get_control_map().get_data().size() + region.get_color_map().get_data().size())
	if not "--render" in OS.get_cmdline_user_args():
		quit()
		return
	DisplayServer.window_set_size(Vector2i(1280, 720))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var scene = load("res://scenes/maps/garda_final.tscn").instantiate()
	var source = scene.get_node("GardaTerrain")
	var terrain := Terrain3D.new()
	terrain.region_size = original.get_width()
	terrain.vertex_spacing = 4.0
	terrain.assets = source.assets
	terrain.material = source.material.duplicate()
	root.add_child(terrain)
	scene.free()
	region.set_location(Vector2i.ZERO)
	assert(terrain.data.add_region(region) == OK)
	var camera := Camera3D.new()
	camera.far = 30000.0
	root.add_child(camera)
	camera.make_current()
	terrain.set_camera(camera)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, -30, 0)
	root.add_child(sun)
	var reference_heights: Array[float] = []
	for z in range(64, 512, 64):
		for x in range(64, 512, 64):
			reference_heights.append(terrain.data.get_height(Vector3(x * 4.0, 0, z * 4.0)))
	var finite_count := 0
	for height in reference_heights:
		if is_finite(height):
			finite_count += 1
	print("HEIGHT_QUERY finite_samples=", finite_count, "/", reference_heights.size())
	if finite_count == 0:
		push_error("No solid terrain sampled; benchmark is not valid.")
		quit(1)
		return
	for factor in [1.0, 2.0, 1.0, 2.0]:
		terrain.vertex_spacing = 4.0 * factor
		region.set_height_map(original if factor == 1.0 else scaled)
		region.calc_height_range()
		terrain.data.update_maps(Terrain3DRegion.TYPE_HEIGHT)
		var sample := 0
		for z in range(64, 512, 64):
			for x in range(64, 512, 64):
				var height: float = terrain.data.get_height(Vector3(x * 4.0 * factor, 0, z * 4.0 * factor))
				if not (is_nan(height) and is_nan(reference_heights[sample])) and not is_equal_approx(height, reference_heights[sample] * factor):
					push_error("Height mismatch: %s vs %s, factor %s" % [height, reference_heights[sample], factor])
					quit(1)
					return
				sample += 1
		camera.position = Vector3(1024, 2200, 2800) * factor
		camera.look_at(Vector3(1024, 900, 1024) * factor)
		for frame in 120:
			await process_frame
		var times: Array[float] = []
		var last := Time.get_ticks_usec()
		for frame in 300:
			await process_frame
			var now := Time.get_ticks_usec()
			times.append((now - last) / 1000.0)
			last = now
		times.sort()
		print("RENDER factor=", factor, " median_ms=", times[150], " p95_ms=", times[285], " video_MiB=", Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0, " primitives=", Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	root.remove_child(terrain)
	terrain.free()
	quit()
