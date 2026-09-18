extends SceneTree
## Read-only runtime regression and optional fixed-camera forest A/B benchmark.
## godot --headless --path . --script res://tools/garda_forest_review.gd
## Omit --headless and pass -- --capture for images/timings (no clouds/TAA/upscaling).
const MAP := "res://scenes/maps/garda_final.tscn"
const OUT := "res://subagent-artifacts/garda-forest/review"
var mmis: Array[MultiMeshInstance3D] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	# A backup scene with the same UID can silently redirect both playable maps.
	var map_uid := ResourceLoader.get_resource_uid(MAP)
	assert(ResourceUID.get_id_path(map_uid) == MAP, "Garda UID redirected: keep scene backups outside Godot's import scan")
	var capture := "--capture" in OS.get_cmdline_user_args()
	assert(not capture or DisplayServer.get_name() != "headless")
	for audio in root.get_node("AudioManager").get_children():
		if audio is AudioStreamPlayer:
			audio.stop()
			audio.stream = null
	root.size = Vector2i(1920, 1080)
	root.content_scale_size = root.size
	root.use_taa = false
	root.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	root.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	root.scaling_3d_scale = 1.0
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	var camera := Camera3D.new()
	camera.far = 400000
	camera.fov = 70
	camera.position = Vector3(0, 7000, 0)
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	root.add_child(camera)
	camera.make_current()
	var map: Node3D = load(MAP).instantiate()
	root.add_child(map)
	current_scene = map
	var terrain: Terrain3D = map.get_node("GardaTerrain")
	terrain.set_camera(camera)
	map.get_node("TutorialBoundaryController").set_physics_process(false)
	var driver = map.get_node("SunshineCloudsDriverGD")
	driver.set_process(false)
	driver.update_continuously = false
	driver.clouds_resource.enabled = false
	map.get_node("Sky3D/SkyDome").process_method = 2
	var forest = map.get_node("Forests")
	var heights := PackedFloat32Array()
	for patch in forest.patches:
		heights.append(terrain.data.get_height(Vector3(patch.x, 0, patch.y)))
	for frame in 600:
		if forest.built:
			break
		await process_frame
	assert(forest.built and forest.tree_count > 1000 and forest.tree_count < forest.max_trees, "Default groves must fit the budget without truncation")
	for i in forest.patches.size():
		var p: Vector4 = forest.patches[i]
		assert(terrain.data.get_height(Vector3(p.x, 0, p.y)) == heights[i], "Placement changed terrain")
	assert(forest.suitable(Vector3(0, 1000, 0), Vector3.UP))
	assert(not forest.suitable(Vector3(0, 185.213, 0), Vector3.UP))
	assert(not forest.suitable(Vector3(0, 2700, 0), Vector3.UP))
	assert(not forest.suitable(Vector3(0, 1000, 0), Vector3.RIGHT))
	assert(not forest.suitable(Vector3(-36418.484, 250, 413.428), Vector3.UP))
	assert(not forest.suitable(Vector3(NAN, 1000, 0), Vector3.UP))
	assert(not forest.suitable(Vector3(0, 1000, 0), Vector3(NAN, NAN, NAN)))
	var sample: Dictionary = forest.make_patch(terrain.data, forest.patches[0], 0, 32)
	assert(sample.transforms.size() == 32)
	assert(sample == forest.make_patch(terrain.data, forest.patches[0], 0, 32), "Placement must be deterministic")
	assert(forest.make_patch(terrain.data, forest.patches[0], 0, 0).transforms.is_empty())
	assert(sample.transforms != forest.make_patch(terrain.data, forest.patches[0], 1, 32).transforms)
	_collect(terrain)
	var count := 0
	var asset := terrain.assets.get_mesh_asset(forest.MESH_ID)
	assert(asset.get_lod_count() == 3 and asset.last_lod == 2 and asset.last_shadow_lod == 2 and asset.shadow_impostor == 2)
	for lod in 3:
		assert(asset.get_mesh(lod).get_surface_count() == 1)
		assert(asset.get_mesh(lod).surface_get_array_index_len(0) / 3 == [4752, 580, 6][lod])
	var material := asset.material_override as StandardMaterial3D
	assert(material.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR)
	assert(material.distance_fade_mode == BaseMaterial3D.DISTANCE_FADE_PIXEL_DITHER)
	assert(material.albedo_texture.get_image().has_mipmaps())
	var shadow_modes := {}
	for mmi in mmis:
		var shadow_only := mmi.name.ends_with("_LS")
		var lod := 2 if shadow_only else int(mmi.name.right(1))
		var range_lod := 1 if shadow_only else lod
		assert(mmi.multimesh.mesh == asset.get_mesh(lod))
		assert(mmi.visibility_range_end >= [450.0, 1000.0, 18000.0][range_lod])
		assert(mmi.visibility_range_end < [451.0, 1005.0, 18050.0][range_lod])
		assert(mmi.multimesh.use_colors)
		shadow_modes[mmi] = mmi.cast_shadow
		if shadow_only:
			assert(mmi.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY)
		else:
			assert(mmi.cast_shadow == (GeometryInstance3D.SHADOW_CASTING_SETTING_ON if lod == 2 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF))
			if lod == 0:
				count += mmi.multimesh.instance_count
	# Dummy renderer cannot read MultiMesh GPU transforms. Check the actual native storage in both modes.
	var stored_count := 0
	for location in terrain.data.get_region_locations():
		var region := terrain.data.get_region(location)
		var offset := Vector3(location.x, 0, location.y) * terrain.vertex_spacing * terrain.get_region_size()
		for cell in region.get_instances().get(forest.MESH_ID, {}).values():
			for stored in cell[0]:
				var t: Transform3D = stored
				t.origin += offset
				stored_count += 1
				assert(t.basis.y.normalized().is_equal_approx(Vector3.UP), "Trees must stay upright")
				assert(absf(t.origin.y + 0.15 - terrain.data.get_height(t.origin)) < 0.02)
				assert(forest.suitable(t.origin + Vector3.UP * 0.15, terrain.data.get_normal(t.origin)))
	assert(count == forest.tree_count and stored_count == count and mmis.size() < count / 10)
	var report := {"trees": count, "batches": mmis.size(), "build_ms": forest.build_msec,
		"largest_patch_ms": forest.largest_patch_msec, "gpu": RenderingServer.get_video_adapter_name(),
		"captures": []}
	print("FOREST STATS ", report)
	if capture:
		assert(DirAccess.make_dir_recursive_absolute(OUT) == OK)
		var tree: Transform3D = sample.transforms[16]
		var target := Vector3(0, terrain.data.get_height(Vector3(0, 0, -2200)), -2200)
		var views := [
			{"id": "near", "target": tree.origin + Vector3.UP * 5, "offset": Vector3(24, 10, 34)},
			{"id": "low_flight", "target": target, "offset": Vector3(900, 600, 1200)},
			{"id": "cruise", "target": target, "offset": Vector3(0, 6500, 5000)},
		]
		for view in views:
			camera.position = view.target + view.offset
			camera.position.y = maxf(camera.position.y, terrain.data.get_height(camera.position) + 10)
			camera.look_at(view.target)
			# Reversed second round reduces order/clock bias. Same native instances throughout.
			for mode in ["off", "on", "no_shadows", "no_shadows", "on", "off"]:
				for mmi in mmis:
					mmi.visible = mode != "off" and not (mode == "no_shadows" and shadow_modes[mmi] == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY)
					mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if mode == "no_shadows" else shadow_modes[mmi]
				var settle_end := Time.get_ticks_msec() + 1200
				while Time.get_ticks_msec() < settle_end:
					await RenderingServer.frame_post_draw
				var gpu: Array[float] = []
				var frames: Array[float] = []
				var sample_end := Time.get_ticks_msec() + 2000
				while Time.get_ticks_msec() < sample_end:
					var start := Time.get_ticks_usec()
					await RenderingServer.frame_post_draw
					frames.append((Time.get_ticks_usec() - start) / 1000.0)
					gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()))
				gpu.sort()
				frames.sort()
				var item := {"view": view.id, "mode": mode, "gpu_ms": gpu[gpu.size() / 2], "frame_ms": frames[frames.size() / 2],
					"p95_ms": frames[int(frames.size() * 0.95)], "draw_calls": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)}
				report.captures.append(item)
				print("FOREST CAPTURE ", item)
				assert(root.get_texture().get_image().save_png(OUT.path_join(view.id + "_" + mode + ".png")) == OK)
		var file := FileAccess.open(OUT.path_join("report.json"), FileAccess.WRITE)
		file.store_string(JSON.stringify(report, "\t"))
		file.close()
	map.queue_free()
	camera.queue_free()
	mmis.clear()
	for frame in 4:
		await process_frame
	print("GARDA FOREST REVIEW PASS")
	quit()

func _collect(node: Node) -> void:
	if node is MultiMeshInstance3D and "_M1_" in node.name:
		mmis.append(node)
	for child in node.get_children(true):
		_collect(child)
