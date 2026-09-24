extends SceneTree
## Run with tools/run_godot_check.cjs; checks the composed airport, surfaces and reusable hangars.

func _initialize() -> void:
	_check.call_deferred()

func _check() -> void:
	for player in root.get_node("AudioManager").get_children():
		if player is AudioStreamPlayer:
			player.stop()
			player.stream = null
	# Let the autoload's audio mixer release stopped playback before this short test exits.
	await create_timer(0.25).timeout
	var airport: Node3D = load("res://scenes/maps/main_airport_layout.tscn").instantiate()
	root.add_child(airport)
	await physics_frame
	await physics_frame
	var meshes := airport.find_children("*", "MeshInstance3D", true, false)
	var collisions := airport.find_children("*", "CollisionShape3D", true, false)
	assert(meshes.size() == 134, "119 infrastructure meshes + 3 instances of the five-mesh small hangar")
	assert(collisions.size() == 57, "One pavement union + 23 placeholders + 3 sets of 11 hangar shapes")
	assert(airport.find_children("S0*_Shelter*", "", true, false).is_empty(), "No residual orange blocks or solid block colliders")
	var runway_bounds := AABB()
	var first := true
	for mesh: MeshInstance3D in meshes:
		assert(mesh.mesh != null and mesh.mesh.get_surface_count() > 0)
		if mesh.name != "LiftCables":
			assert(mesh.scale.is_equal_approx(Vector3.ONE))
		for surface in mesh.mesh.get_surface_count():
			assert(mesh.mesh.surface_get_material(surface) != null)
		if mesh.name.begins_with("RWY_18_36_"):
			var bounds: AABB = mesh.global_transform * mesh.get_aabb()
			runway_bounds = bounds if first else runway_bounds.merge(bounds)
			first = false
	assert(is_equal_approx(runway_bounds.size.x, 60.0))
	assert(is_equal_approx(runway_bounds.size.z, 2400.0))
	var design: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/environment/airport/source/layout_v2/geometry.json"))
	var rays := 0
	var space := airport.get_world_3d().direct_space_state
	for route: Dictionary in design.routes:
		for point: Array in route.points:
			var origin := Vector3(float(point[0]), 3.0, -float(point[1]))
			var query := PhysicsRayQueryParameters3D.create(origin, origin - Vector3.UP * 6.0)
			var hit := space.intersect_ray(query)
			assert(not hit.is_empty(), "Missing pavement collision on " + route.name + " at " + str(origin))
			assert(absf(hit.position.y) < 0.02, "Route must remain on the flat pavement")
			rays += 1
	for point: Vector3 in [Vector3(0, 3, -1190), Vector3(0, 3, 0), Vector3(0, 3, 1190)]:
		assert(not space.intersect_ray(PhysicsRayQueryParameters3D.create(point, point - Vector3.UP * 6)).is_empty())
	var placements: Array = JSON.parse_string(FileAccess.get_file_as_string("res://assets/environment/airport/source/layout_v2/asset_placements.json"))
	var hangars := airport.get_node("SmallHangars").get_children()
	assert(hangars.size() == 3)
	var shared_mesh: Mesh = hangars[0].get_node("Model/SmallHangar/HangarStatic").mesh
	for i in hangars.size():
		var hangar: Node3D = hangars[i]
		var p: Array = placements[i].position_blender
		assert(hangar.position.is_equal_approx(Vector3(p[0], p[2], -p[1])))
		var scale_factor: float = float(placements[i].scale)
		assert(hangar.scale.is_equal_approx(Vector3.ONE * scale_factor), "Blender/Godot hangar scale must agree")
		assert((hangar.global_basis * Vector3.BACK).normalized().is_equal_approx(Vector3.RIGHT), "Entrance must face apron +X")
		assert(hangar.get_node("Model/SmallHangar/HangarStatic").mesh == shared_mesh)
		assert(11.6 * scale_factor > 14.0784 + 2.0 and 4.88 * scale_factor > 4.744 + 1.0, "N26 needs wingtip and tail clearance")
		var front: Vector3 = hangar.to_global(Vector3(0, 0, 12.36))
		assert(absf(front.x - float(placements[i].front_x)) < 0.001, "Door must meet original stand lead-in")
		assert(not space.intersect_ray(PhysicsRayQueryParameters3D.create(hangar.to_global(Vector3(0, 2.5 / scale_factor, 15)), hangar.to_global(Vector3(0, 2.5 / scale_factor, 10)))).is_empty(), "Closed door collision")
		hangar.set_open(true, true)
	await physics_frame
	await physics_frame
	for hangar: Node3D in hangars:
		var scale_factor: float = hangar.scale.x
		assert(space.intersect_ray(PhysicsRayQueryParameters3D.create(hangar.to_global(Vector3(0, 4.9 / scale_factor, 15)), hangar.to_global(Vector3(0, 4.9 / scale_factor, 10)))).is_empty(), "Open door must clear N26 tail")
		for z in [0.0, 12.0, 13.0, 18.0]:
			var origin: Vector3 = hangar.to_global(Vector3(0, 2 / scale_factor, z))
			var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(origin, origin - Vector3.UP * 4))
			assert(not hit.is_empty() and absf(hit.position.y) < 0.02, "Hangar floor must remain flush with apron")
	hangars[1].set_open(false, true)
	await physics_frame
	await physics_frame
	assert(is_equal_approx(hangars[0].openness, 1.0) and is_zero_approx(hangars[1].openness) and is_equal_approx(hangars[2].openness, 1.0), "Doors must remain independent despite shared mesh resources")
	shared_mesh = null
	airport.queue_free()
	await process_frame
	await process_frame
	print("PASS: MAIN_AIRPORT_LAYOUT meshes=", meshes.size(), " colliders=", collisions.size(), " route_collision_samples=", rays, " small_hangars=3 N26_front_clearance=PASS doors=PASS")
	quit(0)
