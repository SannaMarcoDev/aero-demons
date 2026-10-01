extends SceneTree
## Imports terrain/source/riva_sample (tools/terrain/fetch_riva_sample.cjs) into the project:
## Terrain3D regions (2 m), land-use masks, albedo photos and the low-resolution context mesh.
## godot --headless --path . --script res://tools/terrain/build_riva_sample.gd [-- --context]
## --context: context mesh, cover and photos only (after `fetch_riva_sample.cjs context` and `photo`).
const SOURCE := "res://terrain/source/riva_sample/"
const REGIONS := "res://terrain/riva_sample/"
const TEXTURES := "res://textures/terrain/riva_sample/"
const CONTEXT_MESH := "res://resources/terrain/riva_sample_context.res"
const REGION_SIZE := 512
const CONTEXT_MESH_STRIDE := 2 # 60 m mesh cells over the 30 m context DEM.
const HIDDEN_DEPTH := 40.0 # The context mesh sinks under the Terrain3D core edge band.
const CORE_TEXTURES := ["masks_a.png", "masks_b.png"]
const CONTEXT_TEXTURES := ["context_cover.png", "photo_core.jpg", "photo_context.jpg"]

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SOURCE + "manifest.json"))
	var context_only := OS.get_cmdline_user_args().has("--context")
	if not context_only:
		_save_regions(manifest.core)
	_copy_textures(CONTEXT_TEXTURES if context_only else CORE_TEXTURES + CONTEXT_TEXTURES)
	_save_context_mesh(manifest.context, manifest.core)
	print("PASS: RIVA SAMPLE BUILD COMPLETE")
	quit()

func _read_floats(file_name: String, size: int) -> PackedFloat32Array:
	var bytes := FileAccess.get_file_as_bytes(SOURCE + file_name)
	assert(bytes.size() == size * size * 4, "Unexpected size: " + file_name)
	return bytes.to_float32_array()

func _save_regions(core: Dictionary) -> void:
	var size: int = core.size
	var spacing: float = core.step
	var heights := _read_floats(core.file, size)
	var util := Terrain3DUtil.new()
	DirAccess.make_dir_recursive_absolute(REGIONS)
	for old in DirAccess.get_files_at(REGIONS):
		if old.begins_with("terrain3d") and old.ends_with(".res"):
			DirAccess.remove_absolute(REGIONS + old)
	# Raster column c is world x = -half + c * spacing; region L starts at vertex L * REGION_SIZE.
	var first := -int(core.half / spacing) / REGION_SIZE
	var count := size / REGION_SIZE
	var control := Image.create(REGION_SIZE, REGION_SIZE, false, Image.FORMAT_RF)
	var color := Image.create(REGION_SIZE, REGION_SIZE, false, Image.FORMAT_RGBA8)
	color.fill(Color.WHITE)
	for rz in count:
		for rx in count:
			var block := PackedFloat32Array()
			block.resize(REGION_SIZE * REGION_SIZE)
			for y in REGION_SIZE:
				var row := (rz * REGION_SIZE + y) * size + rx * REGION_SIZE
				for x in REGION_SIZE:
					block[y * REGION_SIZE + x] = heights[row + x]
			var region := Terrain3DRegion.new()
			region.set_region_size(REGION_SIZE)
			region.set_vertex_spacing(spacing)
			var location := Vector2i(first + rx, first + rz)
			region.set_location(location)
			region.set_map(Terrain3DRegion.TYPE_HEIGHT, Image.create_from_data(REGION_SIZE, REGION_SIZE, false, Image.FORMAT_RF, block.to_byte_array()))
			region.set_map(Terrain3DRegion.TYPE_CONTROL, control.duplicate())
			region.set_map(Terrain3DRegion.TYPE_COLOR, color.duplicate())
			region.calc_height_range()
			region.set_modified(true)
			assert(region.save(REGIONS + util.location_to_filename(location), false) == OK)
	util.free()
	print("Regions: ", count * count, " of ", REGION_SIZE, " vertices at ", spacing, " m")

func _copy_textures(names: Array) -> void:
	DirAccess.make_dir_recursive_absolute(TEXTURES)
	for name: String in names:
		assert(DirAccess.copy_absolute(SOURCE + name, TEXTURES + name) == OK)
		var import_file := TEXTURES + name + ".import"
		if FileAccess.file_exists(import_file):
			continue
		# Data: lossless with mipmaps; alpha is data, so no alpha-border fix. VRAM compression would
		# smear the classes. Photos (jpg): VRAM compressed, 10240 px is ~70 MB instead of ~560.
		var file := FileAccess.open(import_file, FileAccess.WRITE)
		file.store_string("[remap]\n\nimporter=\"texture\"\ntype=\"CompressedTexture2D\"\n\n[params]\n\n"
			+ "compress/mode=%d\nmipmaps/generate=true\ndetect_3d/compress_to=0\nprocess/fix_alpha_border=false\nprocess/premult_alpha=false\n"
			% (2 if name.ends_with(".jpg") else 0))
	print("Textures copied to ", TEXTURES)

func _save_context_mesh(context: Dictionary, core: Dictionary) -> void:
	var size: int = context.size
	var step: float = context.step
	var half: float = context.half
	var heights := _read_floats(context.file, size)
	var height_at := func(c: int, r: int) -> float:
		return heights[clampi(r, 0, size - 1) * size + clampi(c, 0, size - 1)]
	var cells := (size - 1) / CONTEXT_MESH_STRIDE
	var n := cells + 1
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	vertices.resize(n * n)
	normals.resize(n * n)
	uvs.resize(n * n)
	var core_inner: float = core.half - 2.0 * step * CONTEXT_MESH_STRIDE
	for r in n:
		for c in n:
			var sc := c * CONTEXT_MESH_STRIDE
			var sr := r * CONTEXT_MESH_STRIDE
			var x := -half + sc * step
			var z := -half + sr * step
			var y: float = height_at.call(sc, sr)
			if absf(x) < core_inner and absf(z) < core_inner:
				y -= HIDDEN_DEPTH
			var i := r * n + c
			vertices[i] = Vector3(x, y, z)
			var dx: float = height_at.call(sc + 1, sr) - height_at.call(sc - 1, sr)
			var dz: float = height_at.call(sc, sr + 1) - height_at.call(sc, sr - 1)
			normals[i] = Vector3(-dx, 2.0 * step, -dz).normalized()
			uvs[i] = Vector2((sc + 0.5) / size, (sr + 0.5) / size)
	var indices := PackedInt32Array()
	for r in cells:
		for c in cells:
			# Hole under the core: 60 m triangles cannot stay below 2 m LiDAR cliffs (up to
			# 156 m above). Only the edge band remains, its inner vertices sunk by HIDDEN_DEPTH.
			var x0 := -half + c * CONTEXT_MESH_STRIDE * step
			var z0 := -half + r * CONTEXT_MESH_STRIDE * step
			var x1 := x0 + CONTEXT_MESH_STRIDE * step
			var z1 := z0 + CONTEXT_MESH_STRIDE * step
			if maxf(absf(x0), absf(x1)) < core_inner and maxf(absf(z0), absf(z1)) < core_inner:
				continue
			var a := r * n + c
			# Clockwise seen from above: Godot front faces point up.
			indices.append_array([a, a + 1, a + n, a + 1, a + n + 1, a + n])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var importer := ImporterMesh.new()
	importer.add_surface(Mesh.PRIMITIVE_TRIANGLES, arrays)
	importer.generate_lods(25.0, 60.0, [])
	var mesh := importer.get_mesh()
	assert(ResourceSaver.save(mesh, CONTEXT_MESH, ResourceSaver.FLAG_COMPRESS) == OK)
	print("Context mesh: ", n, "x", n, " vertices, ", mesh.get_surface_count(), " surface")
