extends SceneTree
## Imports terrain/source/riva_sample (tools/terrain/fetch_riva_sample.cjs) into the project:
## Terrain3D regions (4 m over 40.96 km), land-use masks, albedo photos and the 199.68 km context chunks.
## godot --headless --path . --script res://tools/terrain/build_riva_sample.gd [-- --context | --buildings]
## --context: context chunks, cover and photos only (after `fetch_riva_sample.cjs context` and `photo`).
## --buildings: building boxes only (after `fetch_riva_sample.cjs buildings`), on the saved regions.
const SOURCE := "res://terrain/source/riva_sample/"
const REGIONS := "res://terrain/riva_sample/"
const TEXTURES := "res://textures/terrain/riva_sample/"
const CONTEXT_SCENE := "res://resources/terrain/riva_sample_context.scn"
const CONTEXT_MATERIAL := "res://resources/terrain/riva_sample_context_material.tres"
const REGION_SIZE := 512
const CONTEXT_CHUNK := 512 # DEM cells per chunk side: 15.36 km at 30 m.
# Mesh cell stride by the chunk's gap to the core (the playable area): 60, 120, 240 m cells.
const CONTEXT_STRIDES := [[10000.0, 2], [30000.0, 4], [INF, 8]]
const SKIRT_DEPTH := 50.0 # per stride: chunk edges hang down over LOD and stride cracks.
# Curvature lowers far chunks below their mesh AABB (785 m at 100 km): keep them from being culled.
const CURVATURE_CULL_MARGIN := 1000.0
const HIDDEN_DEPTH := 40.0 # The context mesh sinks under the Terrain3D core edge band.
const CORE_TEXTURES := ["masks_a.png", "masks_b.png", "relief_core.png"]
const CONTEXT_TEXTURES := ["context_cover.png", "photo_core.jpg", "photo_wide.jpg", "photo_context.jpg", "photo_far.jpg"]
const BUILDINGS := "res://resources/terrain/riva_sample_buildings.res"
const BUILDING_MIN_HEIGHT := 2.5 # lower DBM roofs: building missing in 2014, use OSM height or default
const BUILDING_DEFAULT_HEIGHT := 7.0
const BUILDING_MAX_HEIGHT := 60.0
const BUILDING_SINK := 1.0 # below the lowest footprint corner, so slopes leave no gap
const ROOF_PITCH := 0.45 # rise/run, ~24 degrees: Garda clay-tile roofs

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SOURCE + "manifest.json"))
	var context_only := OS.get_cmdline_user_args().has("--context")
	if OS.get_cmdline_user_args().has("--buildings"):
		_save_buildings(manifest.core)
	else:
		if not context_only:
			_save_regions(manifest.core)
			_save_buildings(manifest.core)
		_copy_textures(CONTEXT_TEXTURES if context_only else CORE_TEXTURES + CONTEXT_TEXTURES)
		_save_context(manifest.context, manifest.core)
	print("PASS: RIVA SAMPLE BUILD COMPLETE")
	quit()

func _read_floats(file_name: String, size: int) -> PackedFloat32Array:
	var bytes := FileAccess.get_file_as_bytes(SOURCE + file_name)
	assert(bytes.size() == size * size * 4, "Unexpected size: " + file_name)
	return bytes.to_float32_array()

func _save_regions(core: Dictionary) -> void:
	var size: int = core.size
	var spacing: float = core.step
	var bytes := FileAccess.get_file_as_bytes(SOURCE + core.file)
	assert(bytes.size() == size * size * 4, "Unexpected size: " + core.file)
	var heights := Image.create_from_data(size, size, false, Image.FORMAT_RF, bytes)
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
			var region := Terrain3DRegion.new()
			region.set_region_size(REGION_SIZE)
			region.set_vertex_spacing(spacing)
			var location := Vector2i(first + rx, first + rz)
			region.set_location(location)
			region.set_map(Terrain3DRegion.TYPE_HEIGHT, heights.get_region(Rect2i(rx * REGION_SIZE, rz * REGION_SIZE, REGION_SIZE, REGION_SIZE)))
			region.set_map(Terrain3DRegion.TYPE_CONTROL, control.duplicate())
			region.set_map(Terrain3DRegion.TYPE_COLOR, color.duplicate())
			region.calc_height_range()
			region.set_modified(true)
			assert(region.save(REGIONS + util.location_to_filename(location), false) == OK)
	util.free()
	print("Regions: ", count * count, " of ", REGION_SIZE, " vertices at ", spacing, " m")

func _save_buildings(core: Dictionary) -> void:
	if not FileAccess.file_exists(SOURCE + "buildings.json"):
		print("Buildings: skipped, no buildings.json (fetch_riva_sample.cjs buildings)")
		return
	var buildings: Array = JSON.parse_string(FileAccess.get_file_as_string(SOURCE + "buildings.json"))
	var spacing: float = core.step
	var span := REGION_SIZE * spacing
	var util := Terrain3DUtil.new()
	var heights := {}
	var ground := func(p: Vector2) -> float:
		var location := Vector2i(floori(p.x / span), floori(p.y / span))
		if not heights.has(location):
			var region: Terrain3DRegion = load(REGIONS + util.location_to_filename(location))
			heights[location] = region.get_map(Terrain3DRegion.TYPE_HEIGHT)
		var image: Image = heights[location]
		return image.get_pixel(clampi(roundi(p.x / spacing) - location.x * REGION_SIZE, 0, REGION_SIZE - 1),
			clampi(roundi(p.y / spacing) - location.y * REGION_SIZE, 0, REGION_SIZE - 1)).r
	# One surface, flat-shaded. COLOR: orthophoto roof colour (sRGB); UV: x = 1 on roofs, y = per-building seed;
	# UV2: walls (base, eaves) heights, roofs the footprint centroid (x, z).
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var from_dbm := 0
	var gabled := 0
	for i in buildings.size():
		var b: Dictionary = buildings[i]
		var ring := PackedVector2Array()
		var flat: Array = b.ring
		for k in range(0, flat.size(), 2):
			ring.append(Vector2(flat[k], flat[k + 1]))
		var rise := 0.0
		var axis := Vector2.ZERO
		if b.gable != null:
			# The footprint is close to this rectangle: walls follow it, the ridge runs along its long side.
			var centre_xz := Vector2(b.gable[0], b.gable[1])
			axis = Vector2(cos(b.gable[4]), sin(b.gable[4]))
			var along: Vector2 = axis * b.gable[2] * 0.5
			var across: Vector2 = Vector2(-axis.y, axis.x) * b.gable[3] * 0.5
			ring = PackedVector2Array([centre_xz + along + across, centre_xz - along + across,
				centre_xz - along - across, centre_xz + along - across])
			rise = b.gable[3] * 0.5 * ROOF_PITCH
			gabled += 1
		var centroid := Vector2.ZERO
		var base := INF
		for p in ring:
			centroid += p / ring.size()
			base = minf(base, ground.call(p))
		base -= BUILDING_SINK
		var centre: float = ground.call(centroid)
		var top: float = centre + (b.height if b.height > 0.0 else BUILDING_DEFAULT_HEIGHT)
		if b.roof != null and b.roof - centre >= BUILDING_MIN_HEIGHT:
			top = b.roof
			from_dbm += 1
		# The DBM median of a pitched roof is about mid-slope.
		var eaves := clampf(top - rise * 0.5, base + BUILDING_MIN_HEIGHT, base + BUILDING_MAX_HEIGHT)
		var colour := Color(b.colour[0], b.colour[1], b.colour[2])
		var seed_value := fposmod(i * 0.618034, 1.0)
		var wall_uv := Vector2(0.0, seed_value)
		var roof_uv := Vector2(1.0, seed_value)
		var heights_uv := Vector2(base, eaves)
		var area := 0.0
		for k in ring.size():
			area += ring[k].cross(ring[(k + 1) % ring.size()])
		for k in ring.size():
			var p0 := ring[k]
			var p1 := ring[(k + 1) % ring.size()]
			var edge := p1 - p0
			if edge.length_squared() < 0.0001:
				continue
			var out := Vector2(edge.y, -edge.x).normalized() * signf(area)
			var n := Vector3(out.x, 0.0, out.y)
			var a0 := Vector3(p0.x, base, p0.y)
			var a1 := Vector3(p1.x, base, p1.y)
			var up := Vector3.UP * (eaves - base)
			_triangle(st, a0, a1, a1 + up, n, colour, wall_uv, heights_uv)
			_triangle(st, a0, a1 + up, a0 + up, n, colour, wall_uv, heights_uv)
		if b.gable != null:
			var ridge := Vector3.UP * (eaves + rise)
			var r0: Vector3 = Vector3(b.gable[0], 0.0, b.gable[1]) + Vector3(axis.x, 0.0, axis.y) * b.gable[2] * 0.5
			var r1: Vector3 = r0 - Vector3(axis.x, 0.0, axis.y) * b.gable[2]
			var e: Array[Vector3] = []
			for p in ring:
				e.append(Vector3(p.x, eaves, p.y))
			# ring: 0 = +along +across, 1 = -along +across, 2 = -along -across, 3 = +along -across.
			for slope: Array in [[e[0], e[1], r1 + ridge, r0 + ridge], [e[3], e[2], r1 + ridge, r0 + ridge]]:
				var n: Vector3 = (slope[1] - slope[0]).cross(slope[3] - slope[0]).normalized()
				n *= signf(n.y)
				_triangle(st, slope[0], slope[1], slope[2], n, colour, roof_uv, centroid)
				_triangle(st, slope[0], slope[2], slope[3], n, colour, roof_uv, centroid)
			var end := Vector3(axis.x, 0.0, axis.y)
			_triangle(st, e[0], e[3], r0 + ridge, end, colour, wall_uv, heights_uv)
			_triangle(st, e[1], e[2], r1 + ridge, -end, colour, wall_uv, heights_uv)
		else:
			var indices := Geometry2D.triangulate_polygon(ring)
			if indices.is_empty():
				ring = Geometry2D.convex_hull(ring)
				indices = Geometry2D.triangulate_polygon(ring)
			for k in range(0, indices.size(), 3):
				_triangle(st, Vector3(ring[indices[k]].x, eaves, ring[indices[k]].y),
					Vector3(ring[indices[k + 1]].x, eaves, ring[indices[k + 1]].y),
					Vector3(ring[indices[k + 2]].x, eaves, ring[indices[k + 2]].y), Vector3.UP, colour, roof_uv, centroid)
	util.free()
	st.index()
	var mesh := st.commit()
	assert(ResourceSaver.save(mesh, BUILDINGS, ResourceSaver.FLAG_COMPRESS) == OK)
	print("Buildings: ", buildings.size(), " (", gabled, " gabled), ", from_dbm, " with DBM roof height, ",
		mesh.surface_get_array_len(0), " vertices")

## Godot front faces wind clockwise seen from outside: (b - a) x (c - a) points against the normal.
func _triangle(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, normal: Vector3, colour: Color, uv: Vector2, uv2: Vector2) -> void:
	if (b - a).cross(c - a).dot(normal) > 0.0:
		var swap := b
		b = c
		c = swap
	for v in [a, b, c]:
		st.set_normal(normal)
		st.set_color(colour)
		st.set_uv(uv)
		st.set_uv2(uv2)
		st.add_vertex(v)

func _copy_textures(names: Array) -> void:
	DirAccess.make_dir_recursive_absolute(TEXTURES)
	for name: String in names:
		assert(DirAccess.copy_absolute(SOURCE + name, TEXTURES + name) == OK)
		var import_file := TEXTURES + name + ".import"
		if FileAccess.file_exists(import_file):
			continue
		# Data: lossless with mipmaps; alpha is data, so no alpha-border fix. VRAM compression would
		# smear the classes. Photos (jpg): VRAM compressed, 16384 px is ~170 MB instead of ~1 GB.
		# Relief normals: BC5 (R, G only), 5120 px is ~35 MB.
		var relief := name.begins_with("relief")
		var file := FileAccess.open(import_file, FileAccess.WRITE)
		file.store_string("[remap]\n\nimporter=\"texture\"\ntype=\"CompressedTexture2D\"\n\n[params]\n\n"
			+ "compress/mode=%d\ncompress/normal_map=%d\nmipmaps/generate=true\ndetect_3d/compress_to=0\nprocess/fix_alpha_border=false\nprocess/premult_alpha=false\n"
			% [2 if name.ends_with(".jpg") or relief else 0, 1 if relief else 0])
	print("Textures copied to ", TEXTURES)

func _save_context(context: Dictionary, core: Dictionary) -> void:
	var size: int = context.size
	var step: float = context.step
	var half: float = context.half
	var heights := _read_floats(context.file, size)
	var height_at := func(c: int, r: int) -> float:
		return heights[clampi(r, 0, size - 1) * size + clampi(c, 0, size - 1)]
	assert((size - 1) % CONTEXT_CHUNK == 0, "Context cells must split into chunks")
	var chunks := (size - 1) / CONTEXT_CHUNK
	var span := CONTEXT_CHUNK * step
	var root := Node3D.new()
	root.name = "ContextTerrain"
	var material: Material = load(CONTEXT_MATERIAL)
	var triangles := 0
	for cz in chunks:
		for cx in chunks:
			var x0 := -half + cx * span
			var z0 := -half + cz * span
			var gap := maxf(maxf(x0 - core.half, -core.half - x0 - span), maxf(z0 - core.half, -core.half - z0 - span))
			var stride := 0
			for entry: Array in CONTEXT_STRIDES:
				if gap < entry[0]:
					stride = entry[1]
					break
			var mesh := _context_chunk(height_at, cx * CONTEXT_CHUNK, cz * CONTEXT_CHUNK, stride, step, half, core.half)
			if mesh == null:
				continue
			var chunk := MeshInstance3D.new()
			chunk.name = "Chunk_%d_%d" % [cx, cz]
			chunk.mesh = mesh
			chunk.material_override = material
			chunk.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			chunk.extra_cull_margin = CURVATURE_CULL_MARGIN
			root.add_child(chunk)
			chunk.owner = root
			triangles += mesh.surface_get_array_index_len(0) / 3
	var scene := PackedScene.new()
	assert(scene.pack(root) == OK)
	assert(ResourceSaver.save(scene, CONTEXT_SCENE, ResourceSaver.FLAG_COMPRESS) == OK)
	print("Context: ", root.get_child_count(), " chunks, ", triangles, " triangles at full detail")
	root.free()

## One chunk from DEM cell (c0, r0): stride-spaced vertices, a hole under the core (60 m triangles
## cannot stay below the LiDAR cliffs; only the edge band remains, its inner vertices sunk by HIDDEN_DEPTH),
## skirts on all four edges, automatic LODs. Null when the chunk lies inside the hole.
func _context_chunk(height_at: Callable, c0: int, r0: int, stride: int, step: float, half: float, core_half: float) -> ArrayMesh:
	var n := CONTEXT_CHUNK / stride + 1
	var core_inner := core_half - 2.0 * step * stride
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	vertices.resize(n * n)
	normals.resize(n * n)
	for j in n:
		for i in n:
			var c := c0 + i * stride
			var r := r0 + j * stride
			var x := -half + c * step
			var z := -half + r * step
			var y: float = height_at.call(c, r)
			if absf(x) < core_inner and absf(z) < core_inner:
				y -= HIDDEN_DEPTH
			vertices[j * n + i] = Vector3(x, y, z)
			var dx: float = height_at.call(c + stride, r) - height_at.call(c - stride, r)
			var dz: float = height_at.call(c, r + stride) - height_at.call(c, r - stride)
			normals[j * n + i] = Vector3(-dx, 2.0 * step * stride, -dz).normalized()
	var indices := PackedInt32Array()
	var cell := step * stride
	for j in n - 1:
		for i in n - 1:
			var x0 := -half + c0 * step + i * cell
			var z0 := -half + r0 * step + j * cell
			if maxf(absf(x0), absf(x0 + cell)) < core_inner and maxf(absf(z0), absf(z0 + cell)) < core_inner:
				continue
			var a := j * n + i
			# Clockwise seen from above: Godot front faces point up.
			indices.append_array([a, a + 1, a + n, a + 1, a + n + 1, a + n])
	if indices.is_empty():
		return null
	# Skirts: each edge vertex repeated SKIRT_DEPTH * stride lower, quads wound both ways (no outward bookkeeping).
	for edge in [range(0, n), range(n * (n - 1), n * n), range(0, n * n, n), range(n - 1, n * n, n)]:
		var previous := -1
		for k: int in edge:
			var low := vertices.size()
			vertices.append(vertices[k] - Vector3(0.0, SKIRT_DEPTH * stride, 0.0))
			normals.append(normals[k])
			if previous >= 0:
				indices.append_array([previous, k, low, previous, low - 1, low, previous, low, k, previous, low, low - 1])
			previous = k
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var importer := ImporterMesh.new()
	importer.add_surface(Mesh.PRIMITIVE_TRIANGLES, arrays)
	importer.generate_lods(25.0, 60.0, [])
	return importer.get_mesh()
