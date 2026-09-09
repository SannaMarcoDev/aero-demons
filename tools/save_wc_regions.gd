extends SceneTree
## Offline half of import_wc_garda.py: no Terrain3D node, renderer or editor writes.
## Read-only recheck: --headless --path . --script res://tools/save_wc_regions.gd
##   --quit-after 2 -- terrain/garda_final_wc/import_manifest.json --check

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	assert(args.size() >= 1)
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	var destination: String = manifest.destination
	var check_only := "--check" in args
	var util := Terrain3DUtil.new()
	assert(util.enc_base(1) == 1 << 27)
	assert(util.enc_overlay(1) == 1 << 22)
	assert(util.enc_blend(1) == 1 << 14)
	if not check_only:
		assert(not DirAccess.dir_exists_absolute(destination), "Refusing to overwrite terrain")
		assert(DirAccess.make_dir_recursive_absolute(destination) == OK)
	for entry in manifest.regions:
		if not _save_and_check(entry, manifest, args[0].get_base_dir(), util, check_only):
			quit(1)
			return
	if not check_only and not _save_assets(manifest):
		quit(1)
		return
	print("WC REGION IMPORT PASS ", manifest.regions.size(), " check_only=", check_only)
	util.free()
	quit()

func _save_and_check(entry: Dictionary, manifest: Dictionary, staging: String,
		util: Terrain3DUtil, check_only: bool) -> bool:
	var size := int(manifest.region_size)
	var location := Vector2i(int(entry.location[0]), int(entry.location[1]))
	var path: String = manifest.destination.path_join(util.location_to_filename(location))
	var byte_count := size * size * 4
	if not check_only:
		var file := FileAccess.open(staging.path_join(entry.file), FileAccess.READ)
		assert(file != null and file.get_length() == byte_count * 3)
		var region := Terrain3DRegion.new()
		region.set_region_size(size)
		region.set_vertex_spacing(manifest.vertex_spacing)
		region.set_location(location)
		for type in Terrain3DRegion.TYPE_MAX:
			var format := Image.FORMAT_RGBA8 if type == Terrain3DRegion.TYPE_COLOR else Image.FORMAT_RF
			region.set_map(type, Image.create_from_data(size, size, false, format, file.get_buffer(byte_count)))
		region.set_modified(true)
		assert(region.save(path, false) == OK)
	var saved := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as Terrain3DRegion
	assert(saved != null and saved.get_region_size() == size)
	# Terrain3D 1.0.2 stores location in the filename, not in the resource.
	assert(util.filename_to_location(path.get_file()) == location)
	assert(saved.get_vertex_spacing() == manifest.vertex_spacing)
	assert(absf(saved.get_height_range().x - entry.height_range[0]) < 0.001)
	assert(absf(saved.get_height_range().y - entry.height_range[1]) < 0.001)
	for type in Terrain3DRegion.TYPE_MAX:
		var image := saved.get_map(type)
		var format := Image.FORMAT_RGBA8 if type == Terrain3DRegion.TYPE_COLOR else Image.FORMAT_RF
		assert(image.get_format() == format and image.get_size() == Vector2i(size, size))
		# Color mipmaps are generated natively; compare the unmodified base level.
		var hash := HashingContext.new()
		assert(hash.start(HashingContext.HASH_SHA256) == OK)
		assert(hash.update(image.get_data().slice(0, byte_count)) == OK)
		assert(hash.finish().hex_encode() == entry.map_sha256[type], "Saved map differs from WC conversion")
	return true

static func _save_assets(manifest: Dictionary) -> bool:
	# WC's package gradients/tints are already baked into its exported colormap.
	# Neutral surface textures avoid applying those colors a second time.
	var white := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	white.fill(Color(1, 1, 1, 0.5))
	white.generate_mipmaps()
	var normal := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	normal.fill(Color(0.5, 0.5, 1, 1))
	normal.generate_mipmaps()
	var albedo_texture := ImageTexture.create_from_image(white)
	var normal_texture := ImageTexture.create_from_image(normal)
	for pair in [[albedo_texture, "baked_albedo.tres"], [normal_texture, "baked_normal.tres"]]:
		var path: String = manifest.destination.path_join(pair[1])
		assert(ResourceSaver.save(pair[0], path) == OK)
		pair[0].take_over_path(ProjectSettings.localize_path(path))
	var assets := Terrain3DAssets.new()
	for i in manifest.textures.size():
		var asset := Terrain3DTextureAsset.new()
		asset.set_albedo_texture(albedo_texture)
		asset.set_normal_texture(normal_texture)
		asset.set_name(manifest.textures[i].Name)
		assets.set_texture(i, asset)
	assert(ResourceSaver.save(assets, manifest.destination.path_join("wc_terrain_assets.tres")) == OK)
	return true
