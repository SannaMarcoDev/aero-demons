extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	# The former two-terrain overlay is now a single complete map.
	var scene = load("res://scenes/maps/garda_final.tscn").instantiate()
	var terrain = scene.get_node("GardaTerrain")
	assert(terrain.position == Vector3.ZERO)
	assert(not scene.has_node("WC_Terrain") and not scene.has_node("GardaLakeTerrain"))
	assert(scene.has_node("Sky3D/SunLight"))
	assert(scene.has_node("SunshineCloudsDriverGD"))
	assert(scene.has_node("TutorialBoundaryController"))
	for path in ["res://scenes/levels/freeroam.tscn", "res://scenes/levels/tutorial.tscn"]:
		var level = load(path).instantiate()
		assert(level.get_node("GardaLake").scene_file_path == scene.scene_file_path)
		assert(level.has_node("GardaLake/GardaTerrain"))
		level.free()
	var camera := Camera3D.new()
	camera.position = Vector3(0, 2000, 0)
	camera.far = 400000.0
	root.add_child(camera)
	camera.make_current()
	root.add_child(scene)
	await process_frame
	var regions = terrain.data.get_region_locations()
	assert(regions.size() == 256, "Missing terrain regions")
	print("GARDA MAP INTEGRATION PASS regions=", regions.size(), " spacing=", terrain.vertex_spacing)
	if "--capture" in OS.get_cmdline_user_args():
		for frame in 60:
			await process_frame
		await RenderingServer.frame_post_draw
		var path = OS.get_environment("TEMP").path_join("garda_overlay_check.png")
		assert(root.get_texture().get_image().save_png(path) == OK)
		print("CAPTURE ", path)
	root.remove_child(scene)
	scene.free()
	quit()
