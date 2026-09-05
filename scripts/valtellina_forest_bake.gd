extends SceneTree
## Offline bake for the Valtellina forest scatter test.
##
## Run headless:
##   Godot_v4.7.2 --headless --path . --script res://scripts/valtellina_forest_bake.gd \
##     -- --density=1.0 --spacing=15 --out=res://assets/forest_test/trees.bin
##
## Reads the forest density mask + Terrain3D heights and writes a compact binary
## of instance transforms (pos, yaw, scale, model_id). Runtime scene only loads
## the baked file, so it never regenerates the scatter or touches terrain data.

const MASK_PATH := "res://terrain/worldmachine/valtellina_forest_density.png"
const MAGIC := 0x33444633  # "F3D\x33"

var cfg: Resource
var terrain: Terrain3D
var mask_img: Image

func _init() -> void:
	cfg = load("res://assets/forest_test/forest_config.tres")
	_apply_cli_overrides()
	terrain = Terrain3D.new()
	terrain.data_directory = "res://terrain/valtellina_data"
	terrain.vertex_spacing = 5.0
	root.add_child(terrain)
	await process_frame
	await process_frame
	if terrain.data == null or terrain.data.get_region_count() == 0:
		printerr("Bake aborted: no terrain regions loaded")
		quit(1)
		return
	mask_img = Image.load_from_file(MASK_PATH)
	if mask_img == null or mask_img.is_empty():
		printerr("Bake aborted: could not load mask ", MASK_PATH)
		quit(1)
		return
	_bake()
	quit()

func _apply_cli_overrides() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--density="):
			cfg.density_multiplier = a.get_slice("=", 1).to_float()
		elif a.begins_with("--spacing="):
			cfg.minimum_spacing = a.get_slice("=", 1).to_float()
		elif a.begins_with("--size="):
			cfg.test_area_size = a.get_slice("=", 1).to_float()
		elif a.begins_with("--center="):
			var parts := a.get_slice("=", 1).split(",")
			cfg.test_area_center = Vector3(parts[0].to_float(), 0, parts[1].to_float())
		elif a.begins_with("--out="):
			cfg.bake_path = a.get_slice("=", 1)
		elif a.begins_with("--seed="):
			cfg.seed = a.get_slice("=", 1).to_int()

func sample_mask(wx: float, wz: float) -> float:
	# Mask mapping is centrally configurable (see ForestConfig). The default is the
	# calibrated -15360 origin with no V flip. Returns the true 16-bit grayscale
	# normalised by /65535 (Godot get_pixel().r), NOT max-normalised.
	var wmin: float = cfg.mask_world_min
	var wspan: float = cfg.mask_world_span
	var msize: int = cfg.mask_size
	var u := (wx + wmin) / wspan
	var v := (wz + wmin) / wspan
	if cfg.mask_flip_v:
		v = 1.0 - v
	if u < 0.0 or u > 1.0 or v < 0.0 or v > 1.0:
		return 0.0
	var px := clampi(int(u * (msize - 1)), 0, msize - 1)
	var py := clampi(int(v * (msize - 1)), 0, msize - 1)
	return mask_img.get_pixel(px, py).r

func _bake() -> void:
	var half: float = cfg.test_area_size / 2.0
	var center: Vector3 = cfg.test_area_center
	var spacing: float = cfg.minimum_spacing
	var rng := RandomNumberGenerator.new()
	rng.seed = cfg.seed

	var pos := PackedVector3Array()
	var yaw := PackedFloat32Array()
	var scale := PackedFloat32Array()
	var model := PackedInt32Array()
	var model_count: int = cfg.tree_models.size()
	assert(model_count > 0, "No tree models configured")
	var model_height := _model_heights()  # real world-space height (m) per model
	assert(cfg.tree_height_max >= cfg.tree_height_min, "tree_height_max must be >= tree_height_min")

	# Spatial hash (cell size = minimum_spacing) for real minimum-spacing rejection.
	# Any two trees closer than `spacing` must lie in cells whose indices differ by
	# <= 1 on each axis, so checking the 3x3 neighbourhood is sufficient.
	var hash := {}

	var x: float = center.x - half
	while x <= center.x + half:
		var z: float = center.z - half
		while z <= center.z + half:
			# Jitter within the candidate cell to break up the grid, then clamp to the
			# exact test bounds so no tree escapes the bounded area.
			var wx: float = clampf(x + rng.randf_range(-cfg.jitter, cfg.jitter) * spacing, center.x - half, center.x + half)
			var wz: float = clampf(z + rng.randf_range(-cfg.jitter, cfg.jitter) * spacing, center.z - half, center.z + half)
			# Black-mask exclusion: a zero-density cell is never a tree site.
			var dens := sample_mask(wx, wz)
			if dens <= 0.0:
				z += spacing
				continue
			if rng.randf() >= dens * cfg.density_multiplier:
				z += spacing
				continue
			# Real minimum-spacing rejection against already-placed trees.
			if _has_neighbor_within(hash, wx, wz, spacing):
				z += spacing
				continue
			var h := terrain.data.get_height(Vector3(wx, 0, wz))
			if is_finite(h):
				var mi: int = rng.randi_range(0, model_count - 1)
				pos.push_back(Vector3(wx, h, wz))
				yaw.push_back(rng.randf_range(0.0, TAU))
				# Normalise so the tree's real height lands in [tree_height_min, tree_height_max].
				var target_h: float = rng.randf_range(cfg.tree_height_min, cfg.tree_height_max)
				scale.push_back(target_h / model_height[mi])
				model.push_back(mi)
				_hash_add(hash, wx, wz, spacing)
			z += spacing
		x += spacing

	_validate(pos, model)
	_print_height_summary(scale, model, model_height)
	var bytes := PackedByteArray()
	bytes.append_array(_u32(MAGIC))
	bytes.append_array(_u32(1))
	bytes.append_array(_u32(pos.size()))
	bytes.append_array(_u32(model_count))
	for i in pos.size():
		var p := pos[i]
		bytes.append_array(_f32(p.x))
		bytes.append_array(_f32(p.y))
		bytes.append_array(_f32(p.z))
		bytes.append_array(_f32(yaw[i]))
		bytes.append_array(_f32(scale[i]))
		bytes.append_array(_u16(model[i]))

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(cfg.bake_path.get_base_dir()))
	var f := FileAccess.open(cfg.bake_path, FileAccess.WRITE)
	if f == null:
		printerr("Bake aborted: cannot write ", cfg.bake_path, " (", error_string(FileAccess.get_open_error()), ")")
		quit(1)
		return
	f.store_buffer(bytes)
	f.close()
	print("Forest bake OK: %d trees | spacing=%.1f density=%.2f seed=%d area=%.0fm | %s" % [
		pos.size(), cfg.minimum_spacing, cfg.density_multiplier, cfg.seed, cfg.test_area_size, cfg.bake_path])
	print("tree height target: %.1f..%.1fm | per-model real heights: %s" % [cfg.tree_height_min, cfg.tree_height_max, model_height])

func _hash_key(cx: int, cz: int) -> String:
	return "%d,%d" % [cx, cz]

func _hash_add(hash: Dictionary, wx: float, wz: float, spacing: float) -> void:
	var cx := int(floor(wx / spacing))
	var cz := int(floor(wz / spacing))
	var key := _hash_key(cx, cz)
	if not hash.has(key):
		hash[key] = []
	(hash[key] as Array).append(Vector3(wx, 0, wz))

func _has_neighbor_within(hash: Dictionary, wx: float, wz: float, spacing: float) -> bool:
	var cx := int(floor(wx / spacing))
	var cz := int(floor(wz / spacing))
	for ix in range(cx - 1, cx + 2):
		for iz in range(cz - 1, cz + 2):
			var key := _hash_key(ix, iz)
			if not hash.has(key):
				continue
			for p in (hash[key] as Array):
				if Vector2(wx - p.x, wz - p.z).length() < spacing:
					return true
	return false

## Independent all-pair-via-spatial-grid minimum-distance verification. Builds a
## fresh spatial hash (cell = minimum_spacing) and for every tree checks the 3x3
## neighbourhood for any other tree closer than `spacing`.
func _verify_min_spacing(pos: PackedVector3Array) -> float:
	var spacing: float = cfg.minimum_spacing
	var hash := {}
	for p in pos:
		_hash_add(hash, p.x, p.z, spacing)
	var min_d := INF
	for p in pos:
		var cx := int(floor(p.x / spacing))
		var cz := int(floor(p.z / spacing))
		for ix in range(cx - 1, cx + 2):
			for iz in range(cz - 1, cz + 2):
				var key := _hash_key(ix, iz)
				if not hash.has(key):
					continue
				for q in (hash[key] as Array):
					var d := Vector2(p.x - q.x, p.z - q.z).length()
					if d > 0.0 and d < min_d:
						min_d = d
	return min_d

## Real world-space height (Y span) of each tree model, applying the GLB import
## transform (the trees are Z-up in mesh-local space and are rotated to Y-up).
func _model_heights() -> PackedFloat32Array:
	var heights := PackedFloat32Array()
	for path in cfg.tree_models:
		var ps: PackedScene = load(path)
		var inst := ps.instantiate()
		var mi := _find_mesh_instance(inst)
		assert(mi != null, "No MeshInstance3D found in " + path)
		var aabb := mi.mesh.get_aabb()
		var tr := mi.transform
		var mn := Vector3(INF, INF, INF)
		var mx := Vector3(-INF, -INF, -INF)
		for cx in [aabb.position.x, aabb.position.x + aabb.size.x]:
			for cy in [aabb.position.y, aabb.position.y + aabb.size.y]:
				for cz in [aabb.position.z, aabb.position.z + aabb.size.z]:
					var w := tr * Vector3(cx, cy, cz)
					mn = mn.min(w)
					mx = mx.max(w)
		heights.push_back(mx.y - mn.y)
		print("model ", path.get_file(), " real height=", mx.y - mn.y, "m (baseY=", mn.y, ")")
		inst.free()
	return heights

func _find_mesh_instance(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node
	for c in node.get_children():
		var r := _find_mesh_instance(c)
		if r != null:
			return r
	return null

func _u16(v: int) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(2)
	b.encode_u16(0, v)
	return b

func _u32(v: int) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(4)
	b.encode_u32(0, v)
	return b

func _f32(v: float) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(4)
	b.encode_float(0, v)
	return b

func _print_height_summary(scale: PackedFloat32Array, model: PackedInt32Array, model_height: PackedFloat32Array) -> void:
	var mn := INF
	var mx := -INF
	for i in scale.size():
		var h := scale[i] * model_height[model[i]]
		mn = minf(mn, h)
		mx = maxf(mx, h)
	print("effective tree height: min=%.2fm max=%.2fm (target %.1f..%.1fm)" % [mn, mx, cfg.tree_height_min, cfg.tree_height_max])
	assert(mn >= cfg.tree_height_min - 0.01 and mx <= cfg.tree_height_max + 0.01, "Effective heights outside target range")

func _validate(pos: PackedVector3Array, model: PackedInt32Array) -> void:
	assert(pos.size() > 0, "No trees generated in the test area")
	assert(pos.size() == model.size())
	assert(pos.size() < 500000, "Unexpectedly large instance count")
	var half: float = cfg.test_area_size / 2.0
	var center: Vector3 = cfg.test_area_center
	# Cross-check density correlation: mean mask value at tree sites should exceed
	# the mean over the test area (trees favour dense mask cells).
	var mask_sum := 0.0
	var area := Vector2(center.x - half, center.z - half)
	var cells := 0
	var x: float = area.x
	while x <= center.x + half:
		var z: float = area.y
		while z <= center.z + half:
			mask_sum += sample_mask(x, z)
			cells += 1
			z += cfg.minimum_spacing
		x += cfg.minimum_spacing
	var tree_density := 0.0
	for p in pos:
		tree_density += sample_mask(p.x, p.z)
	tree_density /= float(pos.size())
	var area_mean := mask_sum / maxf(float(cells), 1.0)
	# mask means are the true Godot grayscale /65535 values (sample_mask -> get_pixel().r).
	print("self-check: tree-site mask mean %.3f vs area mask mean %.3f (trees should be higher)" % [tree_density, area_mean])
	assert(tree_density > area_mean, "Trees are not biased toward dense mask cells")
	# Exact test bounds (no jitter margin; the bake clamps candidates to the bounds).
	for p in pos:
		assert(is_finite(p.y), "Non-finite grounded height")
		assert(p.x >= center.x - half and p.x <= center.x + half, "Tree outside X test bounds")
		assert(p.z >= center.z - half and p.z <= center.z + half, "Tree outside Z test bounds")
		# Black-mask exclusion: no tree on a zero-density mask cell.
		assert(sample_mask(p.x, p.z) > 0.0, "Tree placed on a black (zero-density) mask cell")
	# Independent all-pair-via-spatial-grid minimum-distance verification.
	var min_d := _verify_min_spacing(pos)
	print("self-check: min pairwise distance = %.3fm (required >= %.1fm)" % [min_d, cfg.minimum_spacing])
	assert(min_d >= cfg.minimum_spacing - 0.01, "A pair of trees violates the real minimum spacing")
	var area_m2: float = cfg.test_area_size * cfg.test_area_size
	var avg_spacing := sqrt(area_m2 / float(pos.size()))
	print("self-check OK: count=%d avg tree spacing=%.1fm (min_spacing=%.1fm enforced) density-biased" % [pos.size(), avg_spacing, cfg.minimum_spacing])
