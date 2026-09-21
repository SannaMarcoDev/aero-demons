extends SceneTree
## City integration, authored exclusions and collision regression; no terrain writes.
const Development = preload("res://scripts/maps/garda_development.gd")
const ORIGIN := Vector3(-36418.484, 234.52104, 413.42773)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	for audio in root.get_node("AudioManager").get_children():
		if audio is AudioStreamPlayer:
			audio.stop()
			audio.stream = null
	var city: Node3D = load("res://scenes/maps/airport_city.tscn").instantiate()
	root.add_child(city)
	await physics_frame
	await physics_frame
	var visual := city.get_node("Visuals")
	var meshes := visual.find_children("*", "MeshInstance3D", true, false)
	var shapes := visual.find_children("*", "CollisionShape3D", true, false)
	assert(meshes.size() >= 170 and shapes.size() >= 110, "Authored blocks and collision proxies imported")
	var bounds := AABB()
	var first := true
	for mesh: MeshInstance3D in meshes:
		if mesh.name.begins_with("city_road_"):
			assert(mesh.lod_bias == 128.0 and mesh.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "Road import must retain terrain contact without shadow draws")
		assert(not "proxy" in mesh.name and not "collision" in mesh.name, "Collision-only meshes must not render")
		var aabb := mesh.global_transform * mesh.get_aabb()
		bounds = aabb if first else bounds.merge(aabb)
		first = false
		for i in mesh.mesh.get_surface_count():
			var material := mesh.get_active_material(i) as BaseMaterial3D
			assert(material != null and material.albedo_texture != null)
			assert(material.normal_enabled and material.normal_texture != null)
	assert(bounds.size.x > 4500 and bounds.size.x < 5200)
	assert(bounds.size.z > 4800 and bounds.size.z < 5400)
	for name in ["city_wind_farm", "city_telecommunications", "city_waterfront", "city_research_headquarters", "city_road_bay_viaduct", "city_airport_support"]:
		assert(visual.find_child(name, true, false) != null, name)
	assert(visual.find_children("*", "AnimationPlayer", true, false).is_empty(), "Static environment")
	assert("buffer = PackedFloat32Array(" in FileAccess.get_file_as_string("res://scenes/maps/airport_city.tscn"), "Headless baking must not discard tree transforms")
	var tree_count := 0
	for node in city.get_children():
		if node is MultiMeshInstance3D:
			tree_count += node.multimesh.instance_count
			assert(node.material_override.get_shader_parameter("wind_strength") == 0.0)
			if DisplayServer.get_name() != "headless":
				for i in node.multimesh.instance_count:
					assert(is_equal_approx(node.multimesh.get_instance_transform(i).basis.determinant(), 0.343))
	assert(tree_count == 168)
	var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/environment/airport/source/city_layout.json"))
	assert(layout.blocks.size() == 42 and layout.roads.size() >= 60)
	for block: Dictionary in layout.blocks:
		assert(Development.contains(ORIGIN + Vector3(block.center[0], 0, block.center[1])))
	for road: Dictionary in layout.roads:
		for point: Array in road.points:
			assert(Development.contains(ORIGIN + Vector3(point[0], 0, point[1])), road.name)
	for point in [Vector3.ZERO, Vector3(425, 0, 965), Vector3(0, 0, -2500), Vector3(0, 0, 2500), Vector3(1418, 0, 2766)]:
		assert(Development.contains(ORIGIN + point), "Airfield approaches and existing user roads remain clear")
	assert(not Development.contains(ORIGIN + Vector3(-3000, 0, 1300)), "Nearby woodland no longer excluded by a 4 km disk")
	assert(not Development.contains(Vector3.ZERO))
	assert(not Development.contains(Vector3(NAN, 0, 0)))
	var space := city.get_world_3d().direct_space_state
	var bridge := Vector3(-1150, 204.0 - ORIGIN.y, -1800)
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(bridge + Vector3.UP * 3, bridge - Vector3.UP * 3))
	assert(not hit.is_empty() and absf(hit.position.y - bridge.y) < 0.1, "Viaduct deck has matching collision")
	# No new city collision caps the preserved runway or the main hangar taxi aisle.
	assert(space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(0, 8, 1200), Vector3(0, 8, -1200))).is_empty())
	assert(space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(425, 6, 1160), Vector3(425, 6, 900))).is_empty())
	var map: Node3D = load("res://scenes/maps/garda_final.tscn").instantiate()
	assert(map.get_node("AirportCity").position.is_equal_approx(ORIGIN))
	assert(map.get_node("AirportCity").transform == map.get_node("Airport").transform)
	if DisplayServer.get_name() != "headless":
		var clouds = map.get_node("SunshineCloudsDriverGD").clouds_resource
		map.get_node("Sky3D").compositor = null
		RenderingServer.call_on_render_thread(clouds.clear_compute)
		await RenderingServer.frame_post_draw
	map.free()
	print("PASS: AIRPORT CITY meshes=", meshes.size(), " collisions=", shapes.size(), " bounds=", bounds, " street_trees=", tree_count)
	city.queue_free()
	for frame in 4: await process_frame
	quit()
