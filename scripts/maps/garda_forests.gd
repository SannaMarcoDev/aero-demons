extends Node
## Camera-local woodland over the entire DEM. No region edits, per-tree nodes or collisions.
const MESH_ID := 1
const Landcover = preload("res://scripts/maps/garda_landcover.gd")
const Development = preload("res://scripts/maps/garda_development.gd")
const MIN_HEIGHT := 195.0
const MAX_HEIGHT := 1850.0
const MIN_NORMAL_Y := 0.819152 # 35 degrees: exposed cliffs remain bare.
const TILE := 488.28125

@export var enabled := true
@export var seed_value := 7319
@export_range(8.0, 40.0, 0.5) var spacing := 12.0
@export_range(2, 20, 1) var radius := 16 # ~7.8 km; beyond the shader's 7 km disappearance.
var tiles: Dictionary = {}
var pending: Array[Vector2i] = []
var _retired: Array[Node3D] = []
var center := Vector2i(2147483647, 2147483647)
var built := false
var tree_count := 0
var build_msec := 0.0
var largest_tile_msec := 0.0
var cover_image: Image
var cover_texture: ImageTexture
var noise := FastNoiseLite.new()
var _started := 0
@onready var terrain: Terrain3D = get_parent().get_node("GardaTerrain")

func _ready() -> void:
	noise.seed = seed_value
	noise.frequency = 0.0025
	noise.fractal_octaves = 3
	cover_image = Landcover.IMAGE
	cover_texture = ImageTexture.create_from_image(cover_image)
	terrain.material.set_shader_param("forest_cover", cover_texture)
	var water := get_parent().get_node_or_null("Water") as MeshInstance3D
	if water != null:
		water.get_active_material(0).set_shader_parameter("land_cover", cover_texture)
	terrain.visibility_changed.connect(func():
		for tile: Node3D in tiles.values(): tile.visible = terrain.visible)
	built = not enabled
	set_process(enabled)

func _process(_delta: float) -> void:
	# Spread GPU buffer destruction too, not just generation, across frames.
	if not _retired.is_empty(): _retired.pop_back().queue_free()
	var camera := get_viewport().get_camera_3d()
	if camera == null: return
	update_center(camera.global_position)
	if pending.is_empty(): return
	# ponytail: one tile/frame; worker generation only if flight outruns the preload margin.
	var start := Time.get_ticks_usec()
	_build_tile(pending.pop_front())
	largest_tile_msec = maxf(largest_tile_msec, (Time.get_ticks_usec() - start) / 1000.0)
	if pending.is_empty():
		built = true
		build_msec = (Time.get_ticks_usec() - _started) / 1000.0

func update_center(position: Vector3) -> void:
	var cell := Vector2i(floori(position.x / TILE), floori(position.z / TILE))
	if cell == center: return
	center = cell
	_started = Time.get_ticks_usec()
	pending.clear()
	for key: Vector2i in tiles.keys():
		if key.distance_squared_to(center) > radius * radius:
			tree_count -= tiles[key].get_meta("trees")
			tiles[key].hide()
			_retired.append(tiles[key])
			tiles.erase(key)
	for z in range(-radius, radius + 1):
		for x in range(-radius, radius + 1):
			var key := center + Vector2i(x, z)
			if x * x + z * z <= radius * radius and key.x >= -256 and key.y >= -256 and key.x < 256 and key.y < 256 and not tiles.has(key):
				pending.append(key)
	pending.sort_custom(func(a: Vector2i, b: Vector2i): return a.distance_squared_to(center) < b.distance_squared_to(center))
	built = pending.is_empty()

func make_tile(key: Vector2i) -> Dictionary:
	var transforms: Array[Transform3D] = []
	var colors := PackedColorArray()
	var species := PackedInt32Array()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + key.x * 73856093 + key.y * 19349663
	var steps := ceili(TILE / spacing)
	# A tile is just a streaming boundary, never a density boundary. No ellipse or global cap.
	for z in steps:
		for x in steps:
			var point := (Vector2(key) + (Vector2(x, z) + Vector2(rng.randf_range(0.1, 0.9), rng.randf_range(0.1, 0.9))) / steps) * TILE
			var cover := Landcover.sample(Vector3(point.x, 0, point.y))
			var density := smoothstep(0.12, 0.72, cover.r) * (0.80 + 0.20 * smoothstep(-0.4, 0.3, noise.get_noise_2d(point.x, point.y)))
			if rng.randf() > density: continue
			var position := Vector3(point.x, 0, point.y)
			position.y = terrain.data.get_height(position)
			var normal := terrain.data.get_normal(position)
			if not suitable(position, normal) or normal.y < MIN_NORMAL_Y + 0.001: continue
			var scale_value := rng.randf_range(0.65, 1.5)
			var width := scale_value * rng.randf_range(0.72, 1.25)
			var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(width, scale_value, width))
			position.y -= 0.15
			transforms.append(Transform3D(basis, position))
			var shade := rng.randf_range(0.70, 1.05)
			colors.append(Color(shade * rng.randf_range(0.83, 1.05), shade, shade * rng.randf_range(0.90, 1.12), 1.0))
			# Mixed stands below the treeline, mostly broadleaf by the lake.
			species.append(2 if rng.randf() < 0.08 + 0.80 * smoothstep(600.0, 1650.0, position.y) else MESH_ID)
	return {"transforms": transforms, "colors": colors, "species": species}

func _build_tile(key: Vector2i) -> void:
	var data := make_tile(key)
	var transforms: Array[Transform3D] = data.transforms
	var tile := Node3D.new()
	tile.name = "Tile_%d_%d" % [key.x, key.y]
	tile.set_meta("trees", transforms.size())
	tile.visible = terrain.visible
	add_child(tile)
	tile.position = Vector3(key.x * TILE, 0, key.y * TILE)
	tiles[key] = tile
	tree_count += transforms.size()
	for mesh_id in [MESH_ID, 2]:
		var selected: Array[Transform3D] = []
		var colors := PackedColorArray()
		for i in transforms.size():
			if data.species[i] == mesh_id:
				selected.append(transforms[i])
				colors.append(data.colors[i])
		if not selected.is_empty(): _add_batch(tile, mesh_id, selected, colors)

func _add_batch(tile: Node3D, mesh_id: int, transforms: Array[Transform3D], colors: PackedColorArray) -> void:
	var asset := terrain.assets.get_mesh_asset(mesh_id)
	var batch: MultiMesh
	var bounds: AABB
	for lod in 3:
		batch = MultiMesh.new()
		batch.transform_format = MultiMesh.TRANSFORM_3D
		batch.use_colors = true
		batch.mesh = asset.get_mesh(lod)
		batch.instance_count = transforms.size()
		for i in transforms.size():
			var transform := transforms[i]
			transform.origin -= tile.position
			batch.set_instance_transform(i, transform)
			batch.set_instance_color(i, colors[i])
		if lod == 0: bounds = batch.get_aabb()
		batch.custom_aabb = bounds # All LODs switch at the same distance.
		var node := MultiMeshInstance3D.new()
		node.name = "Trees_M%d_L%d" % [mesh_id, lod]
		node.multimesh = batch
		node.material_override = asset.material_override
		node.extra_cull_margin = 1.0
		node.visibility_range_begin = [0.0, 140.0, 650.0][lod]
		node.visibility_range_end = [140.0, 650.0, 8500.0][lod]
		node.visibility_range_begin_margin = [0.0, 24.0, 80.0][lod]
		node.visibility_range_end_margin = [24.0, 80.0, 0.0][lod]
		node.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if lod < 2 else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		tile.add_child(node)
	# Same inexpensive LOD2 shadow proxy as the Terrain3D asset, also for nearby trees.
	var shadow := MultiMeshInstance3D.new()
	shadow.name = "Trees_M%d_LS" % mesh_id
	shadow.multimesh = batch
	shadow.material_override = asset.material_override
	shadow.extra_cull_margin = 1.0
	shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	shadow.visibility_range_end = 650.0
	tile.add_child(shadow)

func suitable(position: Vector3, normal: Vector3) -> bool:
	return position.is_finite() and normal.is_finite() \
		and position.y >= MIN_HEIGHT and position.y <= MAX_HEIGHT \
		and normal.y >= MIN_NORMAL_Y \
		and not Development.contains(position)
