extends SceneTree
## Runtime regression on the actual DEM. Visual/performance captures: landscape_review.gd.
const MAP := "res://scenes/maps/garda_final.tscn"

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	assert(ResourceUID.get_id_path(ResourceLoader.get_resource_uid(MAP)) == MAP)
	for audio in root.get_node("AudioManager").get_children():
		if audio is AudioStreamPlayer:
			audio.stop()
			audio.stream = null
	var map: Node3D = load(MAP).instantiate()
	var forest = map.get_node("Forests")
	forest.radius = 2 # Same code, a small resident window; graphical harness uses the full radius.
	map.get_node("GroundCover").process_mode = Node.PROCESS_MODE_DISABLED
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.make_current()
	root.add_child(map)
	forest.set_process(false)
	var terrain: Terrain3D = map.get_node("GardaTerrain")
	terrain.set_camera(camera)
	map.get_node("TutorialBoundaryController").set_physics_process(false)
	assert(forest.suitable(Vector3(0, 1000, 0), Vector3.UP))
	for point in [Vector3(0, 185, 0), Vector3(0, 2700, 0), Vector3(-36418, 250, 414), Vector3(NAN, 1000, 0)]:
		assert(not forest.suitable(point, Vector3.UP))
	assert(not forest.suitable(Vector3(0, 1000, 0), Vector3.RIGHT))
	assert(not forest.suitable(Vector3(0, 1000, 0), Vector3(NAN, NAN, NAN)))
	var asset := terrain.assets.get_mesh_asset(forest.MESH_ID)
	for lod in 3:
		assert(asset.get_mesh(lod).get_surface_count() == 1)
		assert(asset.get_mesh(lod).surface_get_array_index_len(0) / 3 == [3640, 598, 6][lod])
	var material := asset.material_override as ShaderMaterial
	assert(is_equal_approx(material.get_shader_parameter("alpha_cut"), 0.4))
	for name in ["atlas", "crown_normals"]:
		assert(material.get_shader_parameter(name).get_image().has_mipmaps())
	var sample_key := Vector2i(0, -5)
	var sample: Dictionary = forest.make_tile(sample_key)
	assert(not sample.transforms.is_empty())
	assert(sample == forest.make_tile(sample_key), "Placement must be independent of load order")
	for transform: Transform3D in sample.transforms:
		assert(floori(transform.origin.x / forest.TILE) == sample_key.x and floori(transform.origin.z / forest.TILE) == sample_key.y)
	var sample_pixel := Vector2i((Vector2(sample_key) + Vector2(0.5, 0.5)) * forest.TILE / 250000.0 * forest.cover_image.get_width() + Vector2.ONE * forest.cover_image.get_width() * 0.5)
	var first_cover := -1.0
	# Teleport far outside all former ellipses, negative coordinates, and revisit.
	for point in [Vector3(0, 3000, -2200), Vector3(488.5, 3000, -2200), Vector3(14000, 3000, -4000), Vector3(-22000, 3000, -7000), Vector3(-120000, 3000, -114000), Vector3(0, 3000, -2200)]:
		camera.position = point
		var height := terrain.data.get_height(point)
		var retained = forest.tiles.get(sample_key)
		forest.update_center(point)
		if point.x == 488.5: assert(forest.tiles[sample_key] == retained, "Crossing a tile boundary must retain overlapping tiles")
		while not forest.built:
			forest._process(0.016)
			await process_frame
		await process_frame
		assert(forest.pending.is_empty() and forest.tiles.size() <= 13)
		assert(forest.get_child_count() == forest.tiles.size(), "Evicted tiles must be freed, not hidden forever")
		assert(forest.tree_count > 0, "Eligible remote terrain must receive trees")
		assert(terrain.data.get_height(point) == height)
		var count := 0
		for key: Vector2i in forest.tiles:
			assert(key.distance_squared_to(forest.center) <= 4)
			var tile: Node3D = forest.tiles[key]
			count += tile.get_meta("trees")
			if tile.get_child_count() == 0: continue
			assert(tile.get_child_count() in [4, 8]) # Four LOD/proxy nodes per resident species.
			var generated: Dictionary = forest.make_tile(key)
			for batch_start in range(0, tile.get_child_count(), 4):
				var lod0 := tile.get_child(batch_start) as MultiMeshInstance3D
				var mesh_id := int(lod0.name.get_slice("_", 1).trim_prefix("M"))
				var species_asset := terrain.assets.get_mesh_asset(mesh_id)
				for lod in 3:
					var node := tile.get_child(batch_start + lod) as MultiMeshInstance3D
					assert(node.multimesh.mesh == species_asset.get_mesh(lod))
					assert(node.cast_shadow == (GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if lod < 2 else GeometryInstance3D.SHADOW_CASTING_SETTING_ON))
					assert(node.multimesh.custom_aabb == lod0.multimesh.custom_aabb)
					assert(node.visibility_range_begin == [0.0, 140.0, 650.0][lod])
					assert(node.visibility_range_end == [140.0, 650.0, 8500.0][lod])
					assert(node.multimesh.instance_count == lod0.multimesh.instance_count)
					if DisplayServer.get_name() != "headless": assert(node.multimesh.buffer == lod0.multimesh.buffer)
				var shadow := tile.get_child(batch_start + 3) as MultiMeshInstance3D
				assert(shadow.multimesh == tile.get_child(batch_start + 2).multimesh)
				assert(shadow.visibility_range_end == 650.0)
				assert(shadow.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY)
				var instance := 0
				for i in generated.transforms.size():
					if generated.species[i] != mesh_id: continue
					var transform: Transform3D = generated.transforms[i]
					if DisplayServer.get_name() != "headless":
						transform = lod0.multimesh.get_instance_transform(instance)
						transform.origin += tile.position
					instance += 1
					var world := transform.origin + Vector3.UP * 0.15
					assert(transform.basis.y.normalized().is_equal_approx(Vector3.UP))
					assert(absf(world.y - terrain.data.get_height(world)) < 0.02)
					assert(forest.suitable(world, terrain.data.get_normal(world)))
				assert(instance == lod0.multimesh.instance_count)
		assert(count == forest.tree_count)
		print("STREAM CHECK ", point, " trees=", count, " tiles=", forest.tiles.size())
		if point.x == 0:
			assert(forest.make_tile(sample_key) == sample)
			var value: float = forest.cover_image.get_pixelv(sample_pixel).r
			assert(value > 0.0)
			if first_cover >= 0.0: assert(value == first_cover, "Revisit must not accumulate density")
			first_cover = value
		assert(forest.cover_image.has_mipmaps())
	terrain.hide()
	for tile: Node3D in forest.tiles.values(): assert(not tile.visible)
	terrain.show()
	for tile: Node3D in forest.tiles.values(): assert(tile.visible)
	# Outside the DEM: no clamped/wrapped population and no retained old tile nodes.
	camera.position = Vector3(500000, 3000, 500000)
	forest._process(0.016)
	await process_frame
	assert(forest.built and forest.tiles.is_empty() and forest.tree_count == 0)
	for frame in 14:
		forest._process(0.016)
		await process_frame
	assert(forest.get_child_count() == 0, "Retired GPU batches must also be freed")
	for location in terrain.data.get_region_locations():
		for mesh_id in [forest.MESH_ID, 2]:
			assert(terrain.data.get_region(location).get_instances().get(mesh_id, {}).is_empty(), "Streaming must not write Terrain3D region instances")
	if DisplayServer.get_name() != "headless":
		assert(terrain.material.get_shader_param("forest_cover") == forest.cover_texture)
		var clouds = map.get_node("SunshineCloudsDriverGD").clouds_resource
		map.get_node("Sky3D").compositor = null
		RenderingServer.call_on_render_thread(clouds.clear_compute)
		await RenderingServer.frame_post_draw
	map.queue_free()
	camera.queue_free()
	for frame in 4: await process_frame
	print("PASS: GARDA FOREST STREAMING / LODS / EXCLUSIONS / REVISIT / EVICTION")
	quit()
