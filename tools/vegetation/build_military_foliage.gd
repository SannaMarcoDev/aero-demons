extends SceneTree
## Rebuild the Unity Terrain tree instances as chunked GPU instances (no runtime parsing).
const BASE := "res://assets/environment/military_airport/"
const MODELS := ["FoliageMeshes/Grass/SM_Plant_7_far.glb", "FoliageMeshes/SM_ElmTree_3_far.glb"]
const NAMES := ["AirbaseDemoMap", "Overview"]
const SIZES := [Vector2(1400, 1000), Vector2(2500, 1500)]

func _initialize() -> void:
	_build.call_deferred()

func _build() -> void:
	var meshes: Array[Mesh] = []
	var transforms: Array[Transform3D] = []
	for model_path in MODELS:
		var model: Node3D = load(BASE + "models/" + model_path).instantiate()
		root.add_child(model)
		var visual: MeshInstance3D = model.find_children("*", "MeshInstance3D", true, false)[0]
		var mesh := visual.mesh.duplicate() as ArrayMesh
		for surface in mesh.get_surface_count():
			if visual.get_surface_override_material(surface):
				mesh.surface_set_material(surface, visual.get_surface_override_material(surface))
		meshes.append(mesh)
		transforms.append(visual.global_transform)
		root.remove_child(model)
		model.free()
	for scene_index in NAMES.size():
		var name: String = NAMES[scene_index]
		var rows: Array = JSON.parse_string(FileAccess.get_file_as_string(BASE + "foliage/" + name + "_source.json"))
		var groups := {}
		var size: Vector2 = SIZES[scene_index]
		for row: Array in rows:
			var kind: int = int(row[0])
			var x: float = float(row[1])
			var z: float = float(row[3])
			var key := Vector3i(kind, mini(int(x * 8), 7), mini(int(z * 8), 7))
			if not groups.has(key):
				groups[key] = []
			var basis := Basis(Vector3.UP, -float(row[6])).scaled(Vector3(float(row[4]), float(row[5]), float(row[4])))
			var origin := Vector3(x * size.x, float(row[2]) * 600.0, -z * size.y)
			groups[key].append(Transform3D(basis, origin) * transforms[kind])
		var scene := Node3D.new()
		scene.name = name + "Foliage"
		for key: Vector3i in groups:
			var instances: Array = groups[key]
			var multi := MultiMesh.new()
			multi.transform_format = MultiMesh.TRANSFORM_3D
			multi.mesh = meshes[key.x]
			multi.instance_count = instances.size()
			# Dummy renderer (--headless) drops set_instance_transform(); persist the raw 3D buffer.
			var buffer := PackedFloat32Array()
			buffer.resize(instances.size() * 12)
			for i in instances.size():
				var t: Transform3D = instances[i]
				var offset := i * 12
				buffer[offset] = t.basis.x.x
				buffer[offset + 1] = t.basis.y.x
				buffer[offset + 2] = t.basis.z.x
				buffer[offset + 3] = t.origin.x
				buffer[offset + 4] = t.basis.x.y
				buffer[offset + 5] = t.basis.y.y
				buffer[offset + 6] = t.basis.z.y
				buffer[offset + 7] = t.origin.y
				buffer[offset + 8] = t.basis.x.z
				buffer[offset + 9] = t.basis.y.z
				buffer[offset + 10] = t.basis.z.z
				buffer[offset + 11] = t.origin.z
			multi.buffer = buffer
			multi.custom_aabb = AABB(Vector3(key.y * size.x / 8.0 - 30, -30, -(key.z + 1) * size.y / 8.0 - 30), Vector3(size.x / 8.0 + 60, 90, size.y / 8.0 + 60))
			var node := MultiMeshInstance3D.new()
			node.name = "Plant" if key.x == 0 else "ElmTree"
			node.name += "_%d_%d" % [key.y, key.z]
			node.multimesh = multi
			scene.add_child(node)
			node.owner = scene
		var packed := PackedScene.new()
		if packed.pack(scene) != OK or ResourceSaver.save(packed, BASE + "foliage/" + name + ".scn") != OK:
			push_error("Failed to save " + name + " foliage")
			quit(1)
			return
		print("FOLIAGE ", name, " ", rows.size(), " instances / ", groups.size(), " batches")
		scene.free()
	print("PASS: MILITARY_FOLIAGE")
	quit()
