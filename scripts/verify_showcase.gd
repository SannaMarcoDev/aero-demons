extends SceneTree

func _init() -> void:
	print("--- Running Valtellina Showcase Verification Check ---")
	
	# Check 1: Verify bake file
	var bake_path := "res://assets/forest_test/trees.bin"
	assert(FileAccess.file_exists(bake_path), "Bake file missing")
	var f := FileAccess.open(bake_path, FileAccess.READ)
	var magic := f.get_32()
	var version := f.get_32()
	var count := f.get_32()
	var model_count := f.get_32()
	assert(magic == 0x33444633, "Magic mismatch: %d" % magic)
	assert(version == 1, "Version mismatch: %d" % version)
	assert(count == 5903, "Tree count mismatch: %d" % count)
	assert(model_count == 4, "Model count mismatch: %d" % model_count)
	f.close()
	print("Pass 1: Bake file integrity OK (5903 instances, 4 models).")

	# Check 2: Verify tree models and materials
	var tree_paths := [
		"res://assets/trees/tree_rt_1.glb",
		"res://assets/trees/tree_rt_2.glb",
		"res://assets/trees/tree_rt_3.glb",
		"res://assets/trees/tree_rt_4.glb",
	]
	for p in tree_paths:
		assert(ResourceLoader.exists(p), "Model file missing: " + p)
		var ps: PackedScene = load(p)
		assert(ps != null, "Failed to load model: " + p)
		var inst := ps.instantiate()
		var mi: MeshInstance3D = null
		for c in inst.get_children():
			if c is MeshInstance3D:
				mi = c
				break
		assert(mi != null, "MeshInstance3D not found in " + p)
		assert(mi.mesh != null, "Mesh is null in " + p)
		var m: Mesh = mi.mesh
		assert(m.get_surface_count() >= 2, "Surface count < 2 in " + p)
		for s in m.get_surface_count():
			var mat: Material = m.surface_get_material(s)
			assert(mat != null, "Material missing on surface %d in %s" % [s, p])
			if s == 1:
				assert(mat is StandardMaterial3D, "Leaf material is not StandardMaterial3D")
				var smat: StandardMaterial3D = mat
				assert(smat.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR, "Leaf alpha scissor missing")
				assert(smat.albedo_texture != null, "Leaf texture missing")
		inst.free()
	print("Pass 2: Tree models, materials, textures, and alpha scissor OK.")

	# Check 3: Verify showcase scene structure
	var scene_path := "res://scenes/real_terrain_valtellina_showcase.tscn"
	assert(ResourceLoader.exists(scene_path), "Showcase scene missing")
	var scene_res: PackedScene = load(scene_path)
	assert(scene_res != null, "Failed to load showcase scene")
	var root: Node = scene_res.instantiate()
	var terrain: Terrain3D = root.get_node_or_null("Terrain3D")
	assert(terrain != null, "Terrain3D node missing in showcase")
	assert(terrain.data_directory == "res://terrain/valtellina_data", "Data directory incorrect")
	assert(terrain.material.shader_override_enabled, "Shader override not enabled")
	assert(terrain.material.shader_override != null, "Shader override resource null")
	var params: Dictionary = terrain.material.get("_shader_parameters")
	assert(params.has("worldmachine_colormap") and params["worldmachine_colormap"] != null, "Colormap param missing")
	
	var cam: Camera3D = root.get_node_or_null("FreeFlyCamera")
	assert(cam != null, "FreeFlyCamera node missing in showcase")
	assert(cam.get_script() != null, "FreeFlyCamera script missing")
	
	var sun: DirectionalLight3D = root.get_node_or_null("Sun")
	assert(sun != null, "Sun node missing in showcase")
	
	var env: WorldEnvironment = root.get_node_or_null("WorldEnvironment")
	assert(env != null, "WorldEnvironment missing")
	assert(env.environment != null and env.environment.sky != null, "ProceduralSky missing")
	root.free()
	print("Pass 3: Showcase scene node tree, shader and resources OK.")

	# Check 4: Verify screenshots exist
	var shots := [
		"res://screenshots/valtellina_showcase/01_aerial.png",
		"res://screenshots/valtellina_showcase/02_forested_slope.png",
		"res://screenshots/valtellina_showcase/03_valley_floor.png",
		"res://screenshots/valtellina_showcase/04_close_trees.png",
	]
	for s in shots:
		assert(FileAccess.file_exists(s), "Screenshot missing: " + s)
	print("Pass 4: All 4 required screenshots present.")

	print("--- ALL SHOWCASE VERIFICATIONS PASSED ---")
	quit()
