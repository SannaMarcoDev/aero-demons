extends SceneTree
## Utah landcover native-import validation, standalone.
## Usage (always with an external timeout; failures call quit(1)):
##   godot --headless --path . --script res://tests/utah_landcover_import_check.gd
##   godot --path . --script res://tests/utah_landcover_import_check.gd
## The renderer run (Forward+) also captures screenshots to
## the external validation_250km/screenshots folder and probes real collision.
## Read-only: never modifies terrain data, sources, or the original scene.

const SIZE := 8192
const REGION := 1024
const EXPORT := "C:/Users/sanna/Documents/Codex/2026-09-14/new-chat/outputs/godot_validation_v1/native_export"
const SPLATS := "C:/Users/sanna/Documents/Codex/2026-09-14/new-chat/outputs/splatmaps_8k"
const LANDMARKS := "C:/Users/sanna/Documents/Codex/2026-09-14/new-chat/outputs/evidence/landmarks.json"
const RESULTS := "C:/Users/sanna/Documents/Codex/2026-09-14/new-chat/outputs/godot_validation_v1/validation_results"
const BASELINE := RESULTS + "/original_baseline.json"
const NAMES := ["LC_water", "LC_developed", "LC_wetlands", "LC_crops",
	"LC_herbaceous_pasture", "LC_forest", "LC_shrub_scrub", "LC_bare_ground"]

var _failures := PackedStringArray()
var _extent := 250000.0
var _spacing := _extent / SIZE
var _height_scale := (3872.37 - 893.52) / (3000.0 - 11.0)
var _height_offset := 893.52 - 11.0 * _height_scale
var _shots := RESULTS.get_base_dir().path_join("validation_250km/screenshots")

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, what: String) -> void:
	if not ok:
		_failures.append(what)
		push_error("CHECK FAIL: " + what)

func _run() -> void:
	var directory := "res://terrain/utah_landcover_250km"
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(
		directory.path_join("import_manifest.json")))
	_check(manifest != null, "import_manifest.json parses")
	_check(manifest.regions.size() == 64, "64 manifest regions")
	_check(manifest.vertex_spacing == _spacing, "manifest spacing")
	_check(absf(manifest.height_scale - _height_scale) < 1e-12, "documented height scale, not Y*5")
	_check(absf(manifest.get("height_offset", 0.0) - _height_offset) < 1e-9, "documented height datum offset")
	_check(manifest.no_resampling == true, "manifest no_resampling")
	_check(manifest.auto_shader_flags == false, "manifest no auto flags")
	_check(manifest.has("transform") and manifest.has("inverse")
		and manifest.has("landmarks") and manifest.landmarks.size() == 3
		and manifest.has("sources") and manifest.has("mask_sources"),
		"manifest transform/inverse/landmarks/sources/mask checksums")

	# Source files match the WC native manifest and were not touched on disk.
	var native: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(
		EXPORT.path_join("native_export_manifest.json")))
	for name in native.sha256:
		_check(FileAccess.get_sha256(EXPORT.path_join(name)) == native.sha256[name],
			"native manifest sha256 " + name)
	for name in manifest.sources:
		var info: Dictionary = manifest.sources[name]
		_check(FileAccess.get_sha256(info.path) == info.sha256,
			"import source sha256 " + name)
	for name in manifest.mask_sources:
		var info: Dictionary = manifest.mask_sources[name]
		_check(FileAccess.get_sha256(info.path) == info.sha256,
			"mask source sha256 " + name)

	# Original user-modified files and the existing 250 km import still match
	# the pre-import baseline snapshot.
	var baseline: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(BASELINE))
	for f in baseline.baseline_file_hashes:
		_check(FileAccess.get_sha256(f) == baseline.baseline_file_hashes[f],
			"baseline " + f)
	for f in baseline.utah_final_data_files:
		_check(FileAccess.get_sha256(
			"res://terrain/utah_final_wc_uniform_250km".path_join(f))
			== baseline.utah_final_data_files[f], "original data " + f)

	var packed := load("res://scenes/maps/utah_final.tscn") as PackedScene
	_check(packed != null, "scene loads")
	if packed == null:
		_finish(null)
		return
	var scene := packed.instantiate() as Node3D
	root.add_child(scene)
	var terrain := scene.get_node("UtahTerrain") as Terrain3D
	var camera := scene.get_node("ValidationCamera") as Camera3D
	camera.make_current()
	terrain.set_camera(camera)
	await process_frame
	await physics_frame
	# Validation scene explicitly retains editable assets for inspection.
	# Terrain3D normally frees these after uploading texture arrays in _ready().
	# Never repair the scene from the test: inspect what it actually loaded.
	_check(not terrain.free_editor_textures, "editable assets retained by scene")

	# --- Geometry / scene contract -------------------------------------------
	var locations := terrain.data.get_region_locations()
	_check(locations.size() == 64, "64 loaded regions")
	for location in locations:
		_check(location.x >= -4 and location.x <= 3 and location.y >= -4 and location.y <= 3,
			"region location range " + str(location))
	_check(terrain.region_size == REGION and terrain.mesh_lods == 10, "region size / lods")
	_check(absf(terrain.vertex_spacing - _spacing) < 0.000001, "vertex_spacing")
	_check(absf(8 * REGION * terrain.vertex_spacing - _extent) < 0.01, "terrain extent")
	_check(terrain.global_transform.is_equal_approx(Transform3D.IDENTITY), "identity transform")
	var boundary := scene.get_node("ValidationBoundaryController")
	for i in 30:
		if boundary.get_terrain_bounds().size.x > 0.0:
			break
		await physics_frame
	_check(boundary.get_terrain_bounds().is_equal_approx(Rect2(-_extent / 2, -_extent / 2, _extent, _extent)),
		"boundary bounds")
	_check(absf(boundary.get_return_distance() - (_extent / 2 - 6000.0)) < 0.001, "return distance")
	var spawn: Vector3 = scene.get_node("SpawnPoint").global_position
	var spawn_ground := terrain.data.get_height(spawn)
	_check(is_finite(spawn_ground), "spawn above terrain data")
	_check(spawn.y - spawn_ground >= 500.0, "spawn clearance >= 500 m")

	# --- Eight coherent material assets --------------------------------------
	var assets_ok := terrain.assets != null and terrain.assets.get_texture_count() == 8
	_check(assets_ok, "8 texture assets (got %s, path %s)" % [
		terrain.assets.get_texture_count() if terrain.assets else -1,
		terrain.assets.resource_path if terrain.assets else "null"])
	if assets_ok:
		for i in 8:
			var asset := terrain.assets.get_texture(i)
			if asset == null:
				_check(false, "texture id " + str(i))
				continue
			_check(asset.get_id() == i, "texture id " + str(i))
			_check(asset.get_name() == NAMES[i], "texture name " + NAMES[i])
			_check(asset.get_albedo_texture() != null and asset.get_normal_texture() != null,
				"textures present " + NAMES[i])
			if asset.get_albedo_texture() == null or asset.get_normal_texture() == null:
				continue
			var alb_size := asset.get_albedo_texture().get_size()
			var nrm_size := asset.get_normal_texture().get_size()
			_check(alb_size == terrain.assets.get_texture(0).get_albedo_texture().get_size(),
				"albedo size match " + NAMES[i])
			_check(nrm_size == terrain.assets.get_texture(0).get_normal_texture().get_size(),
				"normal size match " + NAMES[i])
	var mat := terrain.material
	_check(mat.shader_override_enabled, "shader override enabled")
	_check(mat.shader_override != null and
		mat.shader_override.resource_path.ends_with("terrain_wc_landcover.gdshader"),
		"dedicated landcover shader")
	var sparams: Dictionary = mat.get("_shader_parameters")
	_check(sparams.get(&"wc_warp_texels") == 0.0, "wc_warp_texels 0")
	_check(sparams.get(&"wc_blend_power") == 1.0, "wc_blend_power 1")
	_check(sparams.get(&"wc_colormap_strength") == 1.0, "wc_colormap_strength 1")
	_check(sparams.get(&"blend_sharpness") == 0.0, "blend_sharpness 0")
	_check(not scene.has_node("Water") and not scene.has_node("Trees"), "no water/trees nodes")
	# Shared shader must be untouched.
	_check(FileAccess.get_sha256("res://resources/terrain/terrain_wc_override.gdshader")
		== "1e86f3db7a761f9cb8f5ab7b961e884460ff83b8a2ddbfbbd48337a05c6440ac",
		"shared override shader unchanged")

	# --- Saved region maps vs manifest hashes (exact, no interpolation) ------
	var util := Terrain3DUtil.new()
	var byte_count := REGION * REGION * 4
	var seen_ids := {}
	var hole_count := 0
	for entry in manifest.regions:
		var location := Vector2i(int(entry.location[0]), int(entry.location[1]))
		var path: String = manifest.destination.path_join(util.location_to_filename(location))
		var region := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as Terrain3DRegion
		_check(region != null, "region loads " + str(location))
		if region == null:
			continue
		for type in Terrain3DRegion.TYPE_MAX:
			var image := region.get_map(type)
			var format := Image.FORMAT_RGBA8 if type == Terrain3DRegion.TYPE_COLOR else Image.FORMAT_RF
			_check(image.get_format() == format, "map format " + str(location) + "/" + str(type))
			var hash := HashingContext.new()
			hash.start(HashingContext.HASH_SHA256)
			hash.update(image.get_data().slice(0, byte_count))
			_check(hash.finish().hex_encode() == entry.map_sha256[type],
				"map sha256 " + str(location) + "/" + str(type))
		# Scan control map: ids 0..7, no holes.
		var data := region.get_map(Terrain3DRegion.TYPE_CONTROL).get_data().slice(0, byte_count)
		for off in range(0, byte_count, 4):
			var control := data.decode_u32(off)
			_check((control >> 27 & 0x1F) < 8, "base id < 8")
			_check((control >> 22 & 0x1F) < 8, "overlay id < 8")
			seen_ids[control >> 27 & 0x1F] = true
			seen_ids[control >> 22 & 0x1F] = true
			if control & 0x4:
				hole_count += 1
			_check((control & 0x3FFF) == 0, "no auto/hole/navigation/rotation/scale flags")
		_check(absf(region.get_height_range().x - entry.height_range[0]) < 0.001, "hmin " + str(location))
		_check(absf(region.get_height_range().y - entry.height_range[1]) < 0.001, "hmax " + str(location))
		region = null
	_check(hole_count == 0, "zero control holes")
	_check(seen_ids.size() == 8, "all 8 ids used, got " + str(seen_ids.keys()))

	# --- Independent source->world mapping via CPU rasters -------------------
	# Sources decoded with Godot's own loaders (EXR float image, TGA honors the
	# bottom-left origin bit), then rotated once 90 CW like the importer.
	var exr_image := Image.new()
	_check(exr_image.load(EXPORT.path_join("utah_height_m_8192.exr")) == OK, "exr loads natively")
	var splat_images := []
	for s in 2:
		var img := Image.new()
		_check(img.load(SPLATS.path_join("LC_splat_%d_0_0.tga" % s)) == OK, "tga loads " + str(s))
		splat_images.append(img)
	var color_image := Image.new()
	_check(color_image.load(EXPORT.path_join("utah_colormap_8192.png")) == OK,
		"colormap loads independently")
	var region_files := {}
	for entry in manifest.regions:
		var loc := Vector2i(int(entry.location[0]), int(entry.location[1]))
		region_files[loc] = manifest.destination.path_join(util.location_to_filename(loc))
	var region_cache := {}
	var region_for := func(loc: Vector2i) -> Terrain3DRegion:
		if not region_cache.has(loc):
			region_cache[loc] = ResourceLoader.load(region_files[loc], "",
				ResourceLoader.CACHE_MODE_IGNORE)
		return region_cache[loc]
	var samples := 0
	var landmarks: Array = JSON.parse_string(FileAccess.get_file_as_string(LANDMARKS))
	var sample_pts := [[0, 0], [0, SIZE - 1], [SIZE - 1, 0], [SIZE - 1, SIZE - 1],
		[SIZE / 2, SIZE / 2], [1023, 0], [1024, 0], [4095, 4096], [4096, 4095]]
	for lm in landmarks:
		sample_pts.append(lm.center)
	# Both sides of every region boundary, along both axes. Check height,
	# colormap and decoded controls against the same unrotated source pixels.
	for b in [1024, 2048, 3072, 4096, 5120, 6144, 7168]:
		for side in [-1, 0]:
			for probe in [0, 4096, 8191]:
				sample_pts.append([probe, SIZE - 1 - (b + side)])
				sample_pts.append([b + side, SIZE - 1 - probe])
	for pt in sample_pts:
		var sx: int = pt[0]
		var sy: int = pt[1]
		var pos := Vector3((SIZE - 1 - sy - SIZE / 2) * _spacing, 0, (sx - SIZE / 2) * _spacing)
		var expected := exr_image.get_pixel(sx, sy).r * _height_scale + _height_offset
		var actual := terrain.data.get_height(pos)
		_check(is_finite(actual) and absf(actual - expected) < 0.001,
			str("height src(", sx, ",", sy, ") ", actual, " != ", expected))
		# Control ids at the same source pixel, decoded independently.
		var w := _splat_weights(splat_images[0], splat_images[1], sx, sy)
		var ids := _top_two(w)
		var gi := Vector2i(SIZE - 1 - sy, sx)  # rotated image coords (i,j)
		var loc := Vector2i(gi.x / REGION - 4, gi.y / REGION - 4)
		var region: Terrain3DRegion = region_for.call(loc)
		_check(region != null, "region at " + str(pos) + " loc " + str(loc))
		if region != null:
			var cdata := region.get_map(Terrain3DRegion.TYPE_CONTROL).get_data()
			var c := cdata.decode_u32(((gi.y % REGION) * REGION + (gi.x % REGION)) * 4)
			_check(int(c >> 27 & 0x1F) == ids[0], str("base id ", sx, ",", sy))
			_check(int(c >> 22 & 0x1F) == ids[1], str("overlay id ", sx, ",", sy))
			var expected_blend := 0
			if ids[0] != ids[1] and w[ids[0]] + w[ids[1]] > 0:
				expected_blend = int(float(w[ids[1]]) * 255.0 / (w[ids[0]] + w[ids[1]]))
			_check(int(c >> 14 & 255) == expected_blend, str("blend ", sx, ",", sy))
			var actual_color := region.get_map(Terrain3DRegion.TYPE_COLOR).get_pixel(
				gi.x % REGION, gi.y % REGION)
			_check(actual_color == color_image.get_pixel(sx, sy),
				str("colormap ", sx, ",", sy))
		samples += 1
	# Global range: derive from the saved regions' own height ranges (the
	# runtime get_height_range() reports 0 as a sentinel low bound).
	var gmin := INF
	var gmax := -INF
	for entry in manifest.regions:
		gmin = minf(gmin, float(entry.height_range[0]))
		gmax = maxf(gmax, float(entry.height_range[1]))
	_check(absf(gmin - manifest.height_range_m[0]) < 0.01, "global hmin")
	_check(absf(gmax - manifest.height_range_m[1]) < 0.01, "global hmax")

	# --- Real collision raycast (renderer run only) --------------------------
	var collision_note := "skipped (headless)"
	if RenderingServer.get_rendering_device() != null:
		_check(terrain.get("collision") != null, "scene collision exists")
		_check(terrain.collision.get_mode() == 1, "scene dynamic game collision enabled")
		var space := scene.get_world_3d().direct_space_state
		var hit := {}
		for i in 60:
			await physics_frame
			hit = space.intersect_ray(PhysicsRayQueryParameters3D.create(
				spawn + Vector3(0, 500, 0), spawn + Vector3(0, -5000, 0)))
			if not hit.is_empty():
				break
		_check(not hit.is_empty(), "collision raycast hit")
		if not hit.is_empty():
			_check(absf(hit.position.y - spawn_ground) < 2.0,
				"raycast height vs data " + str(hit.position.y) + " vs " + str(spawn_ground))
			collision_note = "hit y=%.2f expected %.2f" % [hit.position.y, spawn_ground]

	# --- Screenshots on the real renderer ------------------------------------
	var shots_note := "skipped (headless)"
	if RenderingServer.get_rendering_device() != null:
		DirAccess.make_dir_recursive_absolute(_shots)
		for i in 6:
			await process_frame
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.size = _extent * 1.04
		await _shot(camera, Vector3(0, 40000, 0), -90.0, "overview_topdown")
		camera.projection = Camera3D.PROJECTION_PERSPECTIVE
		for lm in landmarks:
			var wx: float = (SIZE - 1 - int(lm.center[1]) - SIZE / 2) * _spacing
			var wz: float = (int(lm.center[0]) - SIZE / 2) * _spacing
			var ground := terrain.data.get_height(Vector3(wx, 0, wz))
			var view_offset := 900.0 * _extent / 50000.0
			await _shot(camera, Vector3(wx, ground + view_offset, wz + view_offset), -45.0,
				"landmark_" + lm.label.get_slice(" ", 0))
		await _shot(camera, Vector3(0, spawn_ground + 40, 200), -25.0, "detail_ground")
		shots_note = "5 shots in " + _shots

	util.free()
	region_cache.clear()
	_finish(scene, {"samples": samples, "collision": collision_note, "shots": shots_note})

func _finish(scene: Node, extra: Dictionary = {}) -> void:
	if _failures.is_empty():
		print("UTAH LANDCOVER IMPORT CHECK PASS regions=64 extent=", _extent / 1000.0, "km ids=8 holes=0 ",
			"samples=", extra.get("samples", 0), " collision=", extra.get("collision", "n/a"),
			" shots=", extra.get("shots", "n/a"),
			" renderer=", RenderingServer.get_current_rendering_method())
	else:
		print("UTAH LANDCOVER IMPORT CHECK FAIL ", _failures.size(), " failures")
	if scene != null:
		scene.free()
	await process_frame
	quit(0 if _failures.is_empty() else 1)

func _shot(camera: Camera3D, pos: Vector3, pitch: float, name: String) -> void:
	camera.global_position = pos
	camera.rotation_degrees = Vector3(pitch, 0, 0)
	for i in 4:
		await process_frame
	var image := get_root().get_texture().get_image()
	_check(image != null and image.get_width() > 0, "screenshot image " + name)
	if image != null:
		_check(image.save_png(_shots.path_join(name + ".png")) == OK, "screenshot saved " + name)

func _splat_weights(img0: Image, img1: Image, sx: int, sy: int) -> PackedByteArray:
	var p0 := img0.get_pixel(sx, sy)
	var p1 := img1.get_pixel(sx, sy)
	return PackedByteArray([p0.r8, p0.g8, p0.b8, p0.a8, p1.r8, p1.g8, p1.b8, p1.a8])

func _top_two(w: PackedByteArray) -> Vector2i:
	var base := 0
	var overlay := 0
	var strongest := 0
	var second := 0
	for i in 8:
		var s: int = w[i]
		if s > strongest:
			overlay = base; second = strongest; base = i; strongest = s
		elif s > second:
			overlay = i; second = s
	return Vector2i(base, overlay)
