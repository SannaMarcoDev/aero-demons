extends Node3D
## Isolated, read-only forest scatter benchmark. Run this scene for screenshots
## and metrics. Reads the offline-baked instance data (assets/forest_test/trees.bin);
## never regenerates the scatter and never writes to terrain data.
##
## Args (after --):
##   --capture-forest   save screenshots to docs/forest_test/ and quit
##   --benchmark        render a fixed viewpoint and print FPS/frametime/draw calls
##   --no-vsync         disable vsync for uncapped timing (benchmark only)
##   --limit=N          show only the first N instances (progressive benchmarks)
##   --bake=PATH        load a different baked instance file (e.g. stress profile)
##   --seed=NN          deterministic top view (capture path only)

const OUT := "res://docs/forest_test"
const MASK_PATH := "res://terrain/worldmachine/valtellina_forest_density.png"

var cfg: Resource
var terrain: Terrain3D
var camera: Camera3D
var _models: Array = []  # [{mesh, basis}]
var _instance_count := 0
var _limit := -1  # <0 = all instances; used for progressive benchmarks
var _bake_override := ""
var _batches: Array = []  # [{mmi, aabb, count}]
var _mask_img: Image

@onready var sun: DirectionalLight3D = $Sun

const VIEWS := [
	["01_top", Camera3D.PROJECTION_ORTHOGONAL, 620.0],
	["02_oblique", Camera3D.PROJECTION_PERSPECTIVE, 65.0],
	["03_close", Camera3D.PROJECTION_PERSPECTIVE, 65.0],
	["04_trunk", Camera3D.PROJECTION_PERSPECTIVE, 65.0],
]

func _ready() -> void:
	cfg = load("res://assets/forest_test/forest_config.tres")
	terrain = $Terrain3D
	camera = $Camera3D
	terrain.set_camera(camera)
	var args := OS.get_cmdline_user_args()
	for a in args:
		if a.begins_with("--limit="):
			_limit = a.get_slice("=", 1).to_int()
		elif a.begins_with("--bake="):
			_bake_override = a.get_slice("=", 1)
	_mask_img = Image.load_from_file(MASK_PATH)
	_load_models()
	_build_forest()
	set_view(0)
	if "--capture-forest" in args:
		await capture()
	elif "--benchmark" in args:
		await benchmark()
	else:
		DisplayServer.window_set_title("Forest test | 1-4 views, Esc exit")

func _load_models() -> void:
	_models.clear()
	for path in cfg.tree_models:
		var ps: PackedScene = load(path)
		var inst := ps.instantiate()
		var mi := _find_mesh_instance(inst)
		assert(mi != null, "No MeshInstance3D found in " + path)
		_models.append({"mesh": mi.mesh, "basis": mi.transform.basis})
		inst.free()

func _find_mesh_instance(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node
	for c in node.get_children():
		var r := _find_mesh_instance(c)
		if r != null:
			return r
	return null

func sample_mask(wx: float, wz: float) -> float:
	# Same centrally-configurable mapping as the bake (see ForestConfig).
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
	return _mask_img.get_pixel(px, py).r

func _dense_forest_point() -> Vector3:
	# Find the highest-density world point inside the test area, so the top view
	# sits over actual forest (the valley-floor centre is often a clearing).
	var half: float = cfg.test_area_size / 2.0
	var center: Vector3 = cfg.test_area_center
	var best := center
	var best_d := -1.0
	var step := 25.0
	var x := center.x - half
	while x <= center.x + half:
		var z := center.z - half
		while z <= center.z + half:
			var d := sample_mask(x, z)
			if d > best_d:
				best_d = d
				best = Vector3(x, 0, z)
			z += step
		x += step
	return best

func _build_forest() -> void:
	var path: String = cfg.bake_path if _bake_override == "" else _bake_override
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		printerr("Missing baked instance data at ", path, ". Run scripts/valtellina_forest_bake.gd first.")
		return
	var magic := f.get_32()
	var version := f.get_32()
	var count := f.get_32()
	var model_count := f.get_32()
	assert(magic == 0x33444633 and version == 1)
	_instance_count = count

	var half: float = cfg.test_area_size / 2.0
	var center: Vector3 = cfg.test_area_center
	var min_x: float = center.x - half
	var min_z: float = center.z - half
	var chunk: float = cfg.chunk_size

	# Group instance transforms per (cell_x, cell_z, model) into frustum-culled batches.
	var groups := {}
	var n: int = count if _limit < 0 else mini(count, _limit)
	_instance_count = n
	for i in n:
		var px := f.get_float()
		var py := f.get_float()
		var pz := f.get_float()
		var yaw := f.get_float()
		var scale := f.get_float()
		var model := f.get_16()
		assert(model >= 0 and model < _models.size())
		var cx := int(floor((px - min_x) / chunk))
		var cz := int(floor((pz - min_z) / chunk))
		var key: String = "%d,%d,%d" % [cx, cz, model]
		if not groups.has(key):
			groups[key] = []
		var basis: Basis = Basis(Vector3.UP, yaw) * _models[model].basis * Basis.from_scale(Vector3(scale, scale, scale))
		(groups[key] as Array).append(Transform3D(basis, Vector3(px, py, pz)))
	f.close()

	_batches.clear()
	var mm_count := 0
	for key in groups:
		var parts: PackedStringArray = key.split(",")
		var cx: int = parts[0].to_int()
		var cz: int = parts[1].to_int()
		var model: int = parts[2].to_int()
		var txs: Array = groups[key]
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "MM_%d_%d_%d" % [cx, cz, model]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = _models[model].mesh
		mm.instance_count = txs.size()
		for j in txs.size():
			mm.set_instance_transform(j, txs[j])
		mmi.multimesh = mm
		mmi.cast_shadow = 1 if cfg.cast_shadows else 0  # 1=ON, 0=OFF
		# Batch AABB for frustum culling: union of the actual transformed mesh
		# bounds (canopy, scale, rotation), not the global terrain height range.
		var aabb := _cell_aabb_from_transforms(txs, model)
		mmi.custom_aabb = aabb
		add_child(mmi)
		_batches.append({"mmi": mmi, "aabb": aabb, "count": txs.size()})
		mm_count += 1
	print("Forest loaded: %d instances in %d cell batches (chunk %.0fm)" % [_instance_count, mm_count, chunk])

func _cell_aabb_from_transforms(txs: Array, model: int) -> AABB:
	var mesh_aabb: AABB = (_models[model].mesh as Mesh).get_aabb()
	var mn := Vector3(INF, INF, INF)
	var mx := Vector3(-INF, -INF, -INF)
	for tx in txs:
		var t: Transform3D = tx
		for cx in [mesh_aabb.position.x, mesh_aabb.position.x + mesh_aabb.size.x]:
			for cy in [mesh_aabb.position.y, mesh_aabb.position.y + mesh_aabb.size.y]:
				for cz in [mesh_aabb.position.z, mesh_aabb.position.z + mesh_aabb.size.z]:
					var w := t * Vector3(cx, cy, cz)
					mn = mn.min(w)
					mx = mx.max(w)
	return AABB(mn, mx - mn)

func set_view(index: int) -> void:
	var v: Array = VIEWS[index]
	camera.projection = v[1]
	camera.far = 80000.0
	camera.near = 0.1
	if v[1] == Camera3D.PROJECTION_ORTHOGONAL:
		camera.size = v[2]
		# Straight down over the densest forest point, north (-Z) up, so the frame
		# matches the mask orientation.
		var focus: Vector3 = _dense_forest_point()
		var top: float = terrain.data.get_height(focus)
		camera.position = Vector3(focus.x, top + 2000.0, focus.z)
		camera.look_at(Vector3(focus.x, 0, focus.z), Vector3(0, 0, -1))
	else:
		camera.fov = v[2]
		match index:
			1:  # medium oblique
				var c: Vector3 = cfg.test_area_center
				camera.position = Vector3(c.x + 700, terrain.data.get_height(c) + 900, c.z + 900)
				camera.look_at(Vector3(c.x, terrain.data.get_height(c), c.z))
			2:  # close among trees
				var c2: Vector3 = cfg.test_area_center + Vector3(-60, 0, -60)
				camera.position = Vector3(c2.x + 25, terrain.data.get_height(c2) + 8, c2.z + 25)
				camera.look_at(Vector3(c2.x, terrain.data.get_height(c2) + 5, c2.z))
			3:  # ground-level trunk contact check (side on, near a tree)
				var c3: Vector3 = cfg.test_area_center + Vector3(-40, 0, -40)
				camera.position = Vector3(c3.x, terrain.data.get_height(c3) + 3.0, c3.z)
				camera.look_at(Vector3(c3.x + 30, terrain.data.get_height(c3) + 1.0, c3.z + 12))
	DisplayServer.window_set_title("Forest test | " + v[0] + " | 1-4 views")

func _unhandled_key_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo():
		return
	if event.keycode >= KEY_1 and event.keycode <= KEY_4:
		set_view(event.keycode - KEY_1)
	elif event.keycode == KEY_ESCAPE:
		get_tree().quit()

func save_frame(filename: String) -> void:
	for frame in range(20):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	assert(not image.is_empty(), "Empty viewport capture")
	var error := image.save_png(OUT.path_join(filename + ".png"))
	assert(error == OK, "Failed to save screenshot")
	print("Screenshot: ", filename)

func _set_debug_trees(on: bool) -> void:
	# Bright unshaded override so the forest pattern is legible from above.
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.15, 0.9, 0.15) if on else Color.WHITE
	mat.albedo_color.a = 1.0
	for c in get_children():
		if c is MultiMeshInstance3D:
			var mmi: MultiMeshInstance3D = c
			if on:
				mmi.material_override = mat
			else:
				mmi.material_override = null

func capture() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	for frame in range(10):
		await get_tree().process_frame
	# Readable top view over dense forest with the bright-green override. Zoom to
	# ~320 m so the conifer canopies are clearly readable, not sub-pixel dots.
	_set_debug_trees(true)
	set_view(0)
	camera.size = 320.0
	await save_frame("01_top")
	# Full test-area forest pattern (bright green, unshaded).
	camera.size = cfg.test_area_size * 1.1
	await save_frame("05_top_pattern")
	_set_debug_trees(false)
	# Perspective views (normal lit material).
	for i in [1, 2, 3]:
		set_view(i)
		await save_frame(VIEWS[i][0])
	# Save the mask crop (raw) for the Python diagnostic that adds labels.
	_save_mask_block()
	get_tree().quit()

func _save_mask_block() -> void:
	var mask := Image.load_from_file(MASK_PATH)
	var center: Vector3 = cfg.test_area_center
	var half: float = cfg.test_area_size / 2.0
	var wmin: float = cfg.mask_world_min
	var wspan: float = cfg.mask_world_span
	var u0: float = (center.x - half + wmin) / wspan
	var u1: float = (center.x + half + wmin) / wspan
	var v0: float = (center.z - half + wmin) / wspan
	var v1: float = (center.z + half + wmin) / wspan
	var px0 := clampi(int(u0 * (cfg.mask_size - 1)), 0, cfg.mask_size - 1)
	var px1 := clampi(int(u1 * (cfg.mask_size - 1)), 0, cfg.mask_size - 1)
	var py0 := clampi(int(v0 * (cfg.mask_size - 1)), 0, cfg.mask_size - 1)
	var py1 := clampi(int(v1 * (cfg.mask_size - 1)), 0, cfg.mask_size - 1)
	var crop := mask.get_region(Rect2i(px0, py0, maxi(px1 - px0, 1), maxi(py1 - py0, 1)))
	var err := crop.save_png(OUT.path_join("mask_test_block.png"))
	assert(err == OK, "Failed to save mask block")
	print("Screenshot: mask_test_block")

func _count_visible_instances() -> int:
	# Instances in cell batches whose AABB centre is inside the camera frustum.
	# This is a submitted/visible estimate; the true culled count is renderer-owned.
	var vis := 0
	for b in _batches:
		var aabb: AABB = b.aabb
		if camera.is_position_in_frustum(aabb.get_center()):
			vis += b.count
	return vis

func benchmark() -> void:
	# Fixed camera over the forest (medium oblique).
	set_view(1)
	if "--no-vsync" in OS.get_cmdline_user_args():
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var adapter := RenderingServer.get_video_adapter_name()
	var vendor := RenderingServer.get_video_adapter_vendor()
	var logical := get_viewport().get_visible_rect().size
	var physical := get_window().size
	var vsync := DisplayServer.window_get_vsync_mode()
	var method: String = str(ProjectSettings.get_setting("rendering/renderer/rendering_method"))
	print("HW: ", vendor, " / ", adapter)
	print("Renderer: ", method, " | logical: ", logical, " | physical: ", physical, " | vsync: ", vsync)
	var frames := 240
	var deltas := PackedFloat32Array()
	var last := Time.get_ticks_usec()
	for i in frames:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		deltas.append(float(now - last) / 1000.0)
		last = now
	deltas.sort()
	var sum := 0.0
	for d in deltas:
		sum += d
	var avg_ms := sum / float(deltas.size())
	var median_ms := deltas[int(deltas.size() / 2)]
	var p95 := deltas[int(deltas.size() * 0.95)]
	var fps := 1000.0 / avg_ms
	var draw_calls := Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	var objects := Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
	var prims := Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
	var vis := _count_visible_instances()
	print("Benchmark: resident=%d visible=%d | FPS=%.1f | avg=%.2fms median=%.2fms p95=%.2fms | draw_calls=%d objects=%d primitives=%d" % [
		_instance_count, vis, fps, avg_ms, median_ms, p95, int(draw_calls), int(objects), int(prims)])
	get_tree().quit()
