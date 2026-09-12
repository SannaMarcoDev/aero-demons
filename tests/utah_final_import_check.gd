extends SceneTree
## Read-only: godot --headless --path . --script res://tests/utah_final_import_check.gd
## Omit --headless to also exercise Forward+ and the cloud compute shaders.

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var packed := load("res://scenes/maps/utah_final.tscn") as PackedScene
	assert(packed != null)
	var scene := packed.instantiate() as Node3D
	var terrain := scene.get_node("UtahTerrain") as Terrain3D
	assert(terrain.assets.get_texture_count() == 5)
	assert(terrain.material.shader_override_enabled and terrain.material.shader_override != null)
	assert(not scene.has_node("Water"))
	var camera := Camera3D.new()
	camera.position = scene.get_node("SpawnPoint").position
	camera.rotation_degrees.x = -15.0
	camera.far = 300000.0
	root.add_child(camera)
	camera.make_current()
	root.add_child(scene)
	terrain.set_camera(camera)
	await process_frame
	await physics_frame
	var locations := terrain.data.get_region_locations()
	assert(locations.size() == 256)
	for location in locations:
		assert(location.x >= -8 and location.x < 8 and location.y >= -8 and location.y < 8)
	var spacing := terrain.vertex_spacing
	assert(terrain.region_size == 1024 and terrain.mesh_lods == 10)
	assert(absf(16 * terrain.region_size * spacing - 250000.0) < 0.001)
	assert(terrain.global_transform.is_equal_approx(Transform3D.IDENTITY))
	var boundary := scene.get_node("TutorialBoundaryController")
	assert(boundary.get_terrain_bounds().is_equal_approx(Rect2(-125000, -125000, 250000, 250000)))
	assert(absf(boundary.get_return_distance() - 119000.0) < 0.001)
	# Keep the Garda default compatible while Utah uses its explicit node path.
	var legacy_boundary := Node3D.new()
	legacy_boundary.set_script(load("res://scripts/maps/tutorial_boundary_controller.gd"))
	assert(legacy_boundary.terrain_path == NodePath("../GardaTerrain"))
	legacy_boundary.free()
	var sky := scene.get_node("Sky3D") as Sky3D
	var tod := scene.get_node("Sky3D/TimeOfDay") as TimeOfDay
	assert(absf(rad_to_deg(tod.latitude) - 38.12) < 0.00001)
	assert(absf(rad_to_deg(tod.longitude) + 110.6) < 0.00001 and tod.utc == -7.0)
	assert(not sky.fog_enabled and not sky.get_node("SkyDome").fog_visible)
	assert(sky.get_node("SunLight").light_energy > 0.0)
	assert(sky.get_node("MoonLight") is DirectionalLight3D)
	var driver := scene.get_node("SunshineCloudsDriverGD") as SunshineCloudsDriverGD
	assert(driver.clouds_resource == sky.compositor.compositor_effects[0])
	assert(driver.update_continuously)
	# Sunshine deliberately disables compute when the headless renderer has no RD.
	if RenderingServer.get_rendering_device() != null:
		assert(driver.clouds_resource.enabled)
	assert(driver.tracked_directional_lights == [sky.get_node("SunLight")])
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(
		terrain.data_directory.path_join("import_manifest.json")))
	var height_scale := float(manifest.height_scale)
	assert(absf(height_scale - spacing / float(manifest.vertex_spacing)) < 0.000001)
	var minimum := float(manifest.surface.MinHeight)
	var scale := (float(manifest.surface.MaxHeight) - minimum) / 65535.0
	var sync := OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS).path_join("World Creator/Sync")
	for file in manifest.source_sha256:
		assert(FileAccess.get_sha256(sync.path_join(file)) == manifest.source_sha256[file], file)
	var samples := 0
	# Independent source-pixel -> world mapping, including both sides of tile seams.
	for ty in 4:
		for tx in 4:
			var raw := FileAccess.open(sync.path_join("heightmap_%d_%d.raw" % [tx, ty]), FileAccess.READ)
			assert(raw != null)
			for sy in [0, 63, 1024, 2047, 3072, 4095]:
				for sx in [0, 63, 1024, 2047, 3072, 4095]:
					raw.seek((sy * 4096 + sx) * 2)
					var expected := (minimum + raw.get_16() * scale) * height_scale
					var pos := Vector3((ty * 4096 + 4095 - sy - 8192) * spacing,
						0, (tx * 4096 + sx - 8192) * spacing)
					var actual := terrain.data.get_height(pos)
					assert(is_finite(actual) and absf(actual - expected) < 0.001,
						str(pos, " ", actual, " != ", expected))
					samples += 1
	var spawn: Vector3 = scene.get_node("SpawnPoint").global_position
	assert(is_finite(terrain.data.get_height(spawn)))
	assert(spawn.y - terrain.data.get_height(spawn) >= 500.0)
	for i in 8:
		await process_frame
	if RenderingServer.get_rendering_device() != null:
		assert(driver.clouds_resource.enabled)
	print("UTAH FINAL IMPORT CHECK PASS regions=256 extent_km=250x250 sources=65 samples=", samples,
		" spawn_clearance_m=", spawn.y - terrain.data.get_height(spawn),
		" renderer=", RenderingServer.get_current_rendering_method())
	scene.free()
	camera.free()
	await process_frame
	quit()
