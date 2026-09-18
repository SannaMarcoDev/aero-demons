extends Node
## Runtime-only pilot groves. Terrain3D batches/culls them; never saves region data.
const MESH_ID := 1
const AIRPORT := Vector2(-36418.484, 413.428)
const AIRPORT_CLEARANCE := 4000.0
const MIN_HEIGHT := 195.0 # Water is 185.213 m; leave the shore clear.
const MAX_HEIGHT := 1850.0
const MIN_NORMAL_Y := 0.819152 # 35 degrees; leave cliffs and most exposed rock clear.

@export var enabled := true
@export var seed_value := 7319
@export_range(8.0, 40.0, 1.0) var spacing := 16.0
@export_range(1, 100000, 1) var max_trees := 60000
# Centre X/Z and ellipse radii in world metres. Bounded trial areas, not the whole 250 km map.
@export var patches: Array[Vector4] = [
	Vector4(0, -2200, 1400, 900),
	Vector4(-3100, -5100, 1000, 1500),
	Vector4(3700, -4700, 1300, 1100),
	Vector4(900, -9700, 1600, 900),
	Vector4(-34000, -6500, 1200, 900),
	Vector4(-28500, 1800, 900, 1300),
	Vector4(-119500, -114300, 900, 1000),
]

var built := false
var tree_count := 0
var build_msec := 0.0
var largest_patch_msec := 0.0

func _ready() -> void:
	if enabled:
		_populate.call_deferred()
	else:
		built = true

func _populate() -> void:
	var terrain := get_parent().get_node("GardaTerrain") as Terrain3D
	assert(terrain != null and terrain.assets.get_mesh_asset(MESH_ID) != null)
	assert(spacing >= 8.0 and max_trees > 0 and max_trees <= 100000)
	var start := Time.get_ticks_usec()
	for index in patches.size():
		var patch_start := Time.get_ticks_usec()
		var batch := make_patch(terrain.data, patches[index], index, max_trees - tree_count)
		var transforms: Array[Transform3D] = batch.transforms
		if not transforms.is_empty():
			terrain.instancer.add_transforms(MESH_ID, transforms, batch.colors)
			tree_count += transforms.size()
		largest_patch_msec = maxf(largest_patch_msec, (Time.get_ticks_usec() - patch_start) / 1000.0)
		if tree_count >= max_trees:
			break
		# One bounded patch per frame; no per-tree nodes or per-frame placement afterwards.
		await get_tree().process_frame
	build_msec = (Time.get_ticks_usec() - start) / 1000.0
	built = true

func make_patch(data: Terrain3DData, patch: Vector4, index: int, budget: int) -> Dictionary:
	var transforms: Array[Transform3D] = []
	var colors := PackedColorArray()
	if budget <= 0:
		return {"transforms": transforms, "colors": colors}
	assert(spacing >= 8.0 and patch.z > 0.0 and patch.w > 0.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + index * 104729
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.frequency = 0.0025
	noise.fractal_octaves = 3
	var center := Vector2(patch.x, patch.y)
	var radii := Vector2(patch.z, patch.w)
	var steps := Vector2i(ceil(radii.x * 2.0 / spacing), ceil(radii.y * 2.0 / spacing))
	# ponytail: bounded pilot groves; use geographic masks/streaming before covering all 250 km.
	for z in steps.y:
		for x in steps.x:
			var jitter := Vector2(rng.randf_range(0.1, 0.9), rng.randf_range(0.1, 0.9))
			var point := center - radii + (Vector2(x, z) + jitter) * spacing
			var edge := ((point - center) / radii).length()
			var mask := noise.get_noise_2d(point.x, point.y)
			if edge > 0.8 + mask * 0.45 or mask < -0.24:
				continue
			var position := Vector3(point.x, 0, point.y)
			position.y = data.get_height(position)
			if not position.is_finite() or not suitable(position, data.get_normal(position)):
				continue
			var scale_value := rng.randf_range(0.85, 1.3)
			var basis := Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(Vector3.ONE * scale_value)
			position.y -= 0.15 # Bury the base slightly; trunks remain upright on slopes.
			transforms.append(Transform3D(basis, position))
			var shade := rng.randf_range(0.8, 1.05)
			colors.append(Color(shade, shade, shade * 0.96, 1.0))
			if transforms.size() >= budget:
				return {"transforms": transforms, "colors": colors}
	return {"transforms": transforms, "colors": colors}

func suitable(position: Vector3, normal: Vector3) -> bool:
	return position.is_finite() and normal.is_finite() \
		and position.y >= MIN_HEIGHT and position.y <= MAX_HEIGHT \
		and normal.y >= MIN_NORMAL_Y \
		and Vector2(position.x, position.z).distance_squared_to(AIRPORT) >= AIRPORT_CLEARANCE * AIRPORT_CLEARANCE
