extends SceneTree
## Read-only: 250 km extent, documented vertical datum, original WC colors/masks.
## godot --headless --audio-driver WASAPI --path . --script res://tests/garda_final_import_check.gd
const SOURCE := "res://terrain/garda_final_wc_uniform_250km"
const SCALE := (3977.87 - -13.09) / (2000.0 - 8.450164)
const OFFSET := -13.09 - 8.450164 * SCALE

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	for audio in root.get_node("AudioManager").get_children():
		if audio is AudioStreamPlayer:
			audio.stop()
			audio.stream = null
	await create_timer(0.2).timeout
	_check()
	await process_frame
	print("PASS: GARDA FINAL IMPORT CHECK")
	quit()

func _check() -> void:
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.make_current()
	var scene: Node3D = load("res://scenes/maps/garda_final.tscn").instantiate()
	var terrain := scene.get_node("GardaTerrain") as Terrain3D
	assert(terrain.assets.get_texture_count() == 7)
	assert(terrain.data_directory == "res://terrain/garda_geographic_250km")
	root.add_child(scene)
	terrain.set_camera(camera)
	var locations := terrain.data.get_region_locations()
	assert(locations.size() == 256)
	var spacing := terrain.vertex_spacing
	assert(terrain.region_size == 1024 and terrain.mesh_lods == 10)
	assert(absf(16 * terrain.region_size * spacing - 250000.0) < 0.001)
	assert(terrain.global_transform.is_equal_approx(Transform3D.IDENTITY))
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(
		terrain.data_directory.path_join("import_manifest.json")))
	assert(absf(manifest.height_scale - SCALE) < 1e-12)
	# Water was tuned to 185.213 m (~0.86 m above nominal affine 184.348 m) to align with the visual shoreline.
	assert(absf(scene.get_node("Water").position.y - 185.213) < 0.001 or absf(scene.get_node("Water").position.y - (408.07687 / 3.814697265625 * SCALE + OFFSET)) < 1.0)
	var raw: FileAccess
	for path: String in manifest.calibration.sources:
		assert(FileAccess.get_sha256(path) == manifest.calibration.sources[path], "Changed calibration source: " + path)
		if path.ends_with(".r16"):
			raw = FileAccess.open(path, FileAccess.READ)
	assert(raw != null and raw.get_length() == 8192 * 8192 * 2)
	var util := Terrain3DUtil.new()
	var samples := 0
	var dem_samples := 0
	var before_squared := 0.0
	var after_squared := 0.0
	var peak := -INF
	for entry: Dictionary in manifest.regions:
		var location := Vector2i(int(entry.location[0]), int(entry.location[1]))
		assert(locations.has(location))
		var name := util.location_to_filename(location)
		var source_path := SOURCE.path_join(name)
		assert(FileAccess.get_sha256(source_path) == entry.source_sha256)
		var original := ResourceLoader.load(source_path, "", ResourceLoader.CACHE_MODE_IGNORE) as Terrain3DRegion
		var saved := terrain.data.get_region(location)
		assert(saved != null)
		assert(saved.get_control_map().get_data() == original.get_control_map().get_data())
		assert(saved.get_color_map().get_data() == original.get_color_map().get_data())
		var hash := HashingContext.new()
		hash.start(HashingContext.HASH_SHA256)
		hash.update(saved.get_height_map().get_data())
		assert(hash.finish().hex_encode() == entry.map_sha256[0])
		peak = maxf(peak, saved.get_height_range().y)
		# Both sides of every region seam, plus interior samples, through Terrain3D's query.
		for y in [0, 63, 511, 1023]:
			for x in [0, 63, 511, 1023]:
				var expected := original.get_height_map().get_pixel(x, y).r / 3.814697265625 * SCALE + OFFSET
				var position := Vector3((location.x * 1024 + x) * spacing, 0, (location.y * 1024 + y) * spacing)
				var actual := terrain.data.get_height(position)
				assert(is_finite(actual) and absf(actual - expected) < 0.001)
				samples += 1
		# Independent R16 reference: north-up 8192 raster -> WC's clockwise world rotation.
		# WC's authored erosion/filters remain, so compare aggregate error, not exact equality.
		for y in range(64, 1024, 128):
			for x in range(64, 1024, 128):
				var column := ((location.y + 8) * 1024 + y) / 2
				var row := 8191 - ((location.x + 8) * 1024 + x) / 2
				raw.seek((int(row) * 8192 + int(column)) * 2)
				var reference := -13.09 + raw.get_16() * (3990.96 / 65535.0)
				before_squared += pow(original.get_height_map().get_pixel(x, y).r - reference, 2)
				after_squared += pow(saved.get_height_map().get_pixel(x, y).r - reference, 2)
				dem_samples += 1
	assert(absf(peak - 3839.30615) < 0.01)
	assert(sqrt(after_squared / dem_samples) < 130.0)
	assert(after_squared < before_squared * 0.04, "Datum restoration must reduce DEM error")
	print("GARDA extent_km=250 peak_m=", peak, " samples=", samples,
		" DEM_samples=", dem_samples, " DEM_RMSE_before_m=", sqrt(before_squared / dem_samples),
		" DEM_RMSE_after_m=", sqrt(after_squared / dem_samples))
	raw.close()
	util.free()
	scene.free()
	camera.free()
