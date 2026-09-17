extends SceneTree
## Explicit datum correction of the archived WC import; never overwrites a directory.
## godot --headless --path . --script res://tools/restore_garda_height.gd
## Source R16 and WCR stay read-only. No resampling, masks or texture changes.
const SOURCE := "res://terrain/garda_final_wc_uniform_250km"
const DESTINATION := "res://terrain/garda_geographic_250km"
const RAW := "C:/Users/sanna/Workspace/Assets/Terrain/terrain_250km_worldmachine.r16"
const INFO := "C:/Users/sanna/Workspace/Assets/Terrain/terrain_250km_info.txt"
const WCR := "C:/Users/sanna/Documents/World Creator Projects/Lago di Garda/lago di garda.wcr"
const DEM_MIN := -13.09
const DEM_MAX := 3977.87
const STAMP_MIN := 8.450164
const STAMP_MAX := 2000.0
const HEIGHT_SCALE := (DEM_MAX - DEM_MIN) / (STAMP_MAX - STAMP_MIN)
const HEIGHT_OFFSET := DEM_MIN - STAMP_MIN * HEIGHT_SCALE

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	# Let the audio server release autoload playback before the offline conversion.
	for audio in root.get_node("AudioManager").get_children():
		if audio is AudioStreamPlayer:
			audio.stop()
			audio.stream = null
	await create_timer(0.2).timeout
	if DirAccess.dir_exists_absolute(DESTINATION):
		printerr("Refusing to overwrite existing terrain: ", DESTINATION)
		quit(1)
		return
	_restore()
	print("GARDA HEIGHT RESTORE PASS regions=256 extent_km=250 source_unchanged=true")
	quit()

func _restore() -> void:
	assert(FileAccess.get_sha256(RAW) == "5f7681a6cbb0f45dd051bc2e5146ca09c792d6370000a193f3a93b90ec427a19")
	var project: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(WCR))
	var layers: Array = project.BiomeSettings.TerrainLayers.Items
	assert(layers.size() == 1)
	var stamp: Dictionary = layers[0]
	assert(stamp["$type"] == "TerrainLayerStamp" and stamp.SetHeightRange)
	assert(stamp.HeightRange.Min == STAMP_MIN and stamp.HeightRange.Max == STAMP_MAX)
	assert(stamp.HeightScale == 1.0 and stamp.HeightOffset == 0.0)
	assert(stamp.Operation == "Overwrite" and stamp.HeightBlending == 1.0)
	assert(stamp.StampTexture.get_slice("<", 0).ends_with("terrain_250km_worldmachine.r16"))
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SOURCE.path_join("import_manifest.json")))
	var previous_scale: float = manifest.height_scale
	assert(previous_scale == 3.814697265625 and manifest.regions.size() == 256)
	manifest.destination = DESTINATION
	manifest.height_scale = HEIGHT_SCALE
	manifest.height_offset = HEIGHT_OFFSET
	manifest.scene_vertex_spacing = 250000.0 / 16384.0
	manifest.conversion = "Archived WC geometry, inverse documented stamp normalization to DEM metres; no resampling; color/control maps unchanged."
	manifest.calibration = {
		"source_directory": SOURCE, "previous_height_scale": previous_scale,
		"r16_range_m": [DEM_MIN, DEM_MAX], "wc_stamp_range_m": [STAMP_MIN, STAMP_MAX],
		"formula": "Y = archived_height / previous_height_scale * height_scale + height_offset",
		"water_y_before": 408.07687,
		"water_y_after": 408.07687 / previous_scale * HEIGHT_SCALE + HEIGHT_OFFSET,
		"note": "Preserves authored WC erosion/filters, not an exact replacement by the geographic DEM.",
		"sources": {},
	}
	for path in [RAW, INFO, WCR]:
		manifest.calibration.sources[path] = FileAccess.get_sha256(path)
	assert(DirAccess.make_dir_recursive_absolute(DESTINATION) == OK)
	var util := Terrain3DUtil.new()
	for entry: Dictionary in manifest.regions:
		var location := Vector2i(int(entry.location[0]), int(entry.location[1]))
		var name := util.location_to_filename(location)
		var source_path := SOURCE.path_join(name)
		var source_hash := FileAccess.get_sha256(source_path)
		var original := ResourceLoader.load(source_path, "", ResourceLoader.CACHE_MODE_IGNORE) as Terrain3DRegion
		var image := original.get_height_map()
		assert(image.get_format() == Image.FORMAT_RF)
		var heights := image.get_data().to_float32_array()
		for i in heights.size():
			heights[i] = heights[i] / previous_scale * HEIGHT_SCALE + HEIGHT_OFFSET
		var region := Terrain3DRegion.new()
		region.set_region_size(original.get_region_size())
		region.set_vertex_spacing(original.get_vertex_spacing())
		region.set_location(location)
		region.set_height_map(Image.create_from_data(image.get_width(), image.get_height(), false, Image.FORMAT_RF, heights.to_byte_array()))
		region.set_control_map(original.get_control_map())
		region.set_color_map(original.get_color_map())
		region.set_modified(true)
		var target_path := DESTINATION.path_join(name)
		assert(region.save(target_path, false) == OK)
		var saved := ResourceLoader.load(target_path, "", ResourceLoader.CACHE_MODE_IGNORE) as Terrain3DRegion
		assert(saved.get_height_map().get_data() == heights.to_byte_array())
		assert(saved.get_control_map().get_data() == original.get_control_map().get_data())
		assert(saved.get_color_map().get_data() == original.get_color_map().get_data())
		assert(FileAccess.get_sha256(source_path) == source_hash)
		entry.source_sha256 = source_hash
		entry.height_range = [saved.get_height_range().x, saved.get_height_range().y]
		var hash := HashingContext.new()
		hash.start(HashingContext.HASH_SHA256)
		hash.update(heights.to_byte_array())
		entry.map_sha256[0] = hash.finish().hex_encode()
	for path in manifest.calibration.sources:
		assert(FileAccess.get_sha256(path) == manifest.calibration.sources[path])
	var output := FileAccess.open(DESTINATION.path_join("import_manifest.json"), FileAccess.WRITE)
	output.store_string(JSON.stringify(manifest, "\t"))
	output.close()
	util.free()
