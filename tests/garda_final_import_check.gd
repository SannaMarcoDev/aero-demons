extends SceneTree
## Read-only check: 250 km extent and the same WC scaling factor on X/Y/Z.
## godot --headless --path . --script res://tests/garda_final_import_check.gd

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	quit(0 if _check() else 1)

func _check() -> bool:
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.make_current()
	var scene: Node3D = load("res://scenes/maps/garda_final.tscn").instantiate()
	var terrain := scene.get_node("GardaTerrain") as Terrain3D
	# Runtime frees the CPU texture list after uploading it (free_editor_textures).
	assert(terrain.assets.get_texture_count() == 7)
	root.add_child(scene)
	terrain.set_camera(camera)
	var locations := terrain.data.get_region_locations()
	assert(locations.size() == 256)
	for location in locations:
		assert(location.x >= -8 and location.x < 8 and location.y >= -8 and location.y < 8)
	var spacing := terrain.vertex_spacing
	assert(terrain.region_size == 1024)
	assert(absf(16 * terrain.region_size * spacing - 250000.0) < 0.001)
	assert(terrain.global_transform.is_equal_approx(Transform3D.IDENTITY))
	assert(terrain.mesh_lods == 10)
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(
		terrain.data_directory.path_join("import_manifest.json")))
	var height_scale := float(manifest.get("height_scale", 1.0))
	assert(absf(height_scale - spacing / float(manifest.vertex_spacing)) < 0.000001,
		"Vertical and horizontal WC scaling must match")
	var minimum := float(manifest.surface.MinHeight)
	var scale := (float(manifest.surface.MaxHeight) - minimum) / 65535.0
	var sync := OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS).path_join("World Creator/Sync")
	var samples := 0
	# Independent source-pixel -> world mapping, including both sides of tile seams.
	for ty in 4:
		for tx in 4:
			var path := sync.path_join("heightmap_%d_%d.raw" % [tx, ty])
			assert(FileAccess.get_sha256(path) == manifest.source_sha256[path.get_file()])
			var raw := FileAccess.open(path, FileAccess.READ)
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
	scene.free()
	print("GARDA FINAL IMPORT CHECK PASS extent_km=250x250 spacing_m=", spacing,
		" height_scale=", height_scale, " samples=", samples)
	return true
