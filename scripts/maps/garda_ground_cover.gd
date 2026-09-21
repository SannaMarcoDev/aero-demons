extends Node3D
## Camera-local, deterministic tufts; no collision, alpha overdraw or whole-map instances.
const TILE := 40.0
const RADIUS := 2
const CANDIDATES := 1500
const Development = preload("res://scripts/maps/garda_development.gd")
var tiles: Dictionary = {}
var pending: Array[Vector2i] = []
var center := Vector2i(2147483647, 2147483647)
var mesh: ArrayMesh
var largest_tile_ms := 0.0
@onready var terrain: Terrain3D = get_parent().get_node("GardaTerrain")

func _ready() -> void:
	mesh = make_mesh()

func _process(_delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null: return
	var camera_position := camera.global_position
	var height := terrain.data.get_height(camera_position)
	visible = is_finite(height) and camera_position.y - height < 130.0
	if not visible: return
	var cell := Vector2i(floor(camera_position.x / TILE), floor(camera_position.z / TILE))
	if cell != center:
		center = cell
		pending.clear()
		for key: Vector2i in tiles.keys():
			if absi(key.x - center.x) > RADIUS or absi(key.y - center.y) > RADIUS:
				tiles[key].queue_free()
				tiles.erase(key)
		for z in range(-RADIUS, RADIUS + 1):
			for x in range(-RADIUS, RADIUS + 1):
				var key := center + Vector2i(x, z)
				if not tiles.has(key): pending.append(key)
		pending.sort_custom(func(a: Vector2i, b: Vector2i): return a.distance_squared_to(center) < b.distance_squared_to(center))
	if not pending.is_empty():
		var start := Time.get_ticks_usec()
		_build_tile(pending.pop_front())
		largest_tile_ms = maxf(largest_tile_ms, (Time.get_ticks_usec() - start) / 1000.0)

func suitable(point: Vector3, normal: Vector3) -> bool:
	return point.is_finite() and normal.is_finite() and point.y > 197.0 and point.y < 1900.0 \
		and normal.y > 0.90 and not Development.contains(point)

func make_transforms(key: Vector2i) -> Array[Transform3D]:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key) + 7319
	var transforms: Array[Transform3D] = []
	for i in CANDIDATES:
		var point := Vector3((key.x + rng.randf()) * TILE, 0, (key.y + rng.randf()) * TILE)
		point.y = terrain.data.get_height(point)
		if not suitable(point, terrain.data.get_normal(point)): continue
		# Coherent sparse/dense clumps, not a uniform carpet.
		var density := 0.62 + 0.25 * sin(point.x * 0.057) * sin(point.z * 0.071)
		if rng.randf() > density: continue
		var tuft_basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.55, 1.25))
		transforms.append(Transform3D(tuft_basis, point - Vector3.UP * 0.035))
	return transforms

func _build_tile(key: Vector2i) -> void:
	var transforms := make_transforms(key)
	var batch := MultiMesh.new()
	batch.transform_format = MultiMesh.TRANSFORM_3D
	batch.use_colors = true
	batch.mesh = mesh
	batch.instance_count = transforms.size()
	var origin := Vector3(key.x * TILE, 0, key.y * TILE)
	for i in transforms.size():
		var tuft_transform := transforms[i]
		tuft_transform.origin -= origin
		batch.set_instance_transform(i, tuft_transform)
		var shade := 0.8 + float(i % 11) * 0.035
		batch.set_instance_color(i, Color(shade, shade, shade, 1))
	var node := MultiMeshInstance3D.new()
	node.multimesh = batch
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.visibility_range_end = 125.0
	node.extra_cull_margin = 1.0
	add_child(node)
	node.global_position = origin
	tiles[key] = node

static func make_mesh() -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3917
	for blade in 12:
		var angle := rng.randf() * TAU
		var side := Vector3(cos(angle), 0, sin(angle)) * rng.randf_range(0.012, 0.025)
		var base := Vector3(rng.randf_range(-0.30, 0.30), 0, rng.randf_range(-0.30, 0.30))
		var lean := Vector3(rng.randf_range(-0.25, 0.25), 0, rng.randf_range(-0.25, 0.25))
		var height := rng.randf_range(0.25, 0.65)
		var mid := base + Vector3.UP * height * 0.55 + lean * 0.2
		var tip := base + Vector3.UP * height + lean
		var points := [base - side, base + side, mid - side * 0.6, mid + side * 0.6, tip]
		for index in [0, 1, 2, 1, 3, 2, 2, 3, 4]:
			surface.set_normal(Vector3.UP)
			surface.set_uv(Vector2(0.5, [0.0, 0.0, 0.55, 0.55, 1.0][index]))
			surface.add_vertex(points[index])
	var material := ShaderMaterial.new()
	material.shader = preload("res://resources/terrain/garda_grass.gdshader")
	surface.set_material(material)
	return surface.commit()
