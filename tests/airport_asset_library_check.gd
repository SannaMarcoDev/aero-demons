extends SceneTree
## Isolated library regression; --capture adds actual Godot review images.
## node tools/run_godot_check.cjs 90 <log> <godot> --headless --path . --script res://tests/airport_asset_library_check.gd

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for audio in root.get_node("AudioManager").get_children():
		if audio is AudioStreamPlayer:
			audio.stop()
			audio.stream = null
	var library: Node3D = load("res://scenes/preview/airport_asset_library.tscn").instantiate()
	root.add_child(library)
	var camera = library.get_node("Camera")
	camera.mouse_look_enabled = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	for i in range(8):
		await process_frame
		await physics_frame
	assert(library.find_children("*", "Terrain3D", true, false).is_empty())
	assert(library.find_children("*", "MultiMeshInstance3D", true, false).is_empty())
	var expected := [4992, 14964, 10752, 4104, 2052, 3240, 2180, 10296, 394, 1946, 940, 9592]
	assert(camera.ASSETS.size() == 13 and camera.TITLES.size() == 13 and camera.HEIGHTS.size() == 13)
	assert(library.get_node("DisplayPads").get_child_count() == 13)
	assert(library.get_node("Labels").get_child_count() == 13)
	var report := {}
	var paths := {}
	for i in range(12):
		var asset: Node3D = library.get_node(camera.ASSETS[i])
		assert(not paths.has(asset.scene_file_path), "Duplicated model instead of a distinct building")
		paths[asset.scene_file_path] = true
		var meshes := asset.find_children("*", "MeshInstance3D", true, false)
		assert(meshes.size() == 1, "Export contains unintended scene objects")
		var mesh: Mesh = meshes[0].mesh
		var triangles := 0
		for s in mesh.get_surface_count():
			var arrays := mesh.surface_get_arrays(s)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			assert(vertices.size() == normals.size())
			for v in vertices:
				assert(v.is_finite())
			for n in normals:
				assert(n.is_finite() and n.length() > 0.9)
			assert(mesh.surface_get_material(s) != null)
			triangles += int(indices.size() / 3) if not indices.is_empty() else int(vertices.size() / 3)
		assert(triangles == expected[i], "Unexpected geometry in " + str(asset.name))
		var bounds: AABB = meshes[0].get_aabb()
		assert(absf(bounds.position.y) < 0.01 and bounds.size.x < 80 and bounds.size.z < 80)
		assert(triangles < 22000)
		if asset.name == "ControlTower":
			assert(is_equal_approx(bounds.size.y, 70.05))
		if asset.name == "SatelliteDish":
			assert(bounds.size.x > 70.0 and bounds.size.x < 71.0)
		if asset.name in ["ResidenceTerraced", "OfficesTwins", "OfficeSpire"]:
			assert(bounds.size.y > 100 and bounds.size.y < 140, "Missing skyline landmark")
		report[asset.name] = {"triangles": triangles, "size": str(bounds.size)}
	# Real editable splines and native intersection, not an imported asphalt mesh.
	var container: RoadContainer = library.get_node("RoadManager/TwoLaneRoads")
	assert(not container.flatten_terrain and not container.generate_ai_lanes)
	assert(container.get_segments().size() == 4)
	assert(container.get_intersections().size() == 1)
	var junction: RoadIntersection = container.get_node("Junction")
	assert(junction.edge_points.size() == 4 and junction._mesh.mesh.get_surface_count() > 0)
	for edge in junction.edge_points:
		assert(edge.lanes == [RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW])
		var toward: Vector3 = (junction.global_position - edge.global_position).normalized()
		assert(junction.settings._edge_inward_dir(edge, junction).dot(toward) > 0.99)
	var before := {}
	for segment in container.get_segments():
		before[segment.name] = segment.road_mesh.mesh
	container.get_node("EastEnd").position.z -= 3.0
	for i in range(4):
		await process_frame
		await physics_frame
	assert(container.get_segments().any(func(segment): return segment.road_mesh.mesh != before.get(segment.name)))
	container.get_node("EastEnd").position.z += 3.0
	# Exercise all presets, including labels and the reused free-fly camera.
	for i in range(camera.ASSETS.size() + 1):
		camera.focus_asset(i)
		assert(camera.position.is_finite() and camera.selected == i)
		assert(not library.get_node("HUD/Margin/VBox/Selection").text.is_empty())
	# Keyboard navigation must also reach 10–13, including wraparound at both ends.
	camera.focus_asset(0)
	for pair in [[KEY_LEFT, 13], [KEY_RIGHT, 0], [KEY_RIGHT, 1], [KEY_9, 9], [KEY_HOME, 0]]:
		var event := InputEventKey.new()
		event.keycode = pair[0]
		event.pressed = true
		camera._unhandled_input(event)
		assert(camera.selected == pair[1])
	if "--capture" in OS.get_cmdline_user_args():
		assert(DisplayServer.get_name() != "headless", "Captures require the real renderer")
		root.size = Vector2i(1920, 1080)
		root.msaa_3d = Viewport.MSAA_4X
		var directory := "res://subagent-artifacts/catalog-expansion/review"
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
		for i in range(camera.ASSETS.size() + 1):
			camera.focus_asset(i)
			for frame in range(25):
				await process_frame
			await RenderingServer.frame_post_draw
			assert(root.get_texture().get_image().save_png(directory.path_join("%02d.png" % i)) == OK)
		# An extra rear view exposes dish construction, not only the flattering front.
		camera.focus_asset(12)
		library.get_node("HUD/Margin/VBox/Selection").text = "12 / PARABOLA — struttura posteriore"
		camera.position = library.get_node("SatelliteDish").position + Vector3(-72, 46, -95)
		camera.look_at(library.get_node("SatelliteDish").position + Vector3.UP * 33)
		for i in range(15):
			await process_frame
		await RenderingServer.frame_post_draw
		assert(root.get_texture().get_image().save_png(directory.path_join("dish_back.png")) == OK)
		camera.position = Vector3(0, 1150, -105)
		camera.look_at(Vector3(0, 0, -105), Vector3.FORWARD)
		library.get_node("HUD/Margin/VBox/Selection").text = "PLANIMETRIA / 10 EDIFICI + 2 STRUTTURE + ROADMANAGER"
		for i in range(15):
			await process_frame
		await RenderingServer.frame_post_draw
		assert(root.get_texture().get_image().save_png(directory.path_join("top.png")) == OK)
	print("PASS: ASSET LIBRARY — ten distinct buildings, two landmarks, geometry budgets, editable roads, fourteen camera presets and keyboard cycling; ", JSON.stringify(report))
	library.queue_free()
	await process_frame
	await create_timer(0.3).timeout
	quit()
