extends SceneTree
## Run: Godot --headless --path . --script tests/airport_asset_check.gd

func _initialize() -> void:
	call_deferred("_check")

func _check() -> void:
	# This asset-only test does not need the project's autoplay music.
	var audio := root.get_node_or_null("AudioManager")
	if audio != null:
		for player in audio.get_children():
			if player is AudioStreamPlayer:
				player.stop()
				player.stream = null
	await process_frame
	var packed := load("res://scenes/maps/airport.tscn") as PackedScene
	assert(packed != null, "Airport container loads")
	var airport := packed.instantiate() as Node3D
	root.add_child(airport)
	await physics_frame
	await physics_frame
	assert(airport.transform.is_equal_approx(Transform3D.IDENTITY))
	assert(airport.has_node("Visuals/airport_layout"))
	assert(airport.has_node("CollisionBodies/static_airport/pavement"))
	assert(airport.has_node("Markers/road_connection"))
	var visual := airport.get_node("Visuals/airport_layout")
	var meshes := visual.find_children("*", "MeshInstance3D", true, false)
	assert(meshes.size() == 103, "Separate mesh count preserved")
	var runway := visual.find_child("runway_surface", true, false) as MeshInstance3D
	assert(runway != null)
	var bounds := runway.global_transform * runway.get_aabb()
	assert(absf(bounds.size.x - 60.0) < 0.01)
	assert(absf(bounds.size.z - 2400.0) < 0.01, "Blender Y maps to Godot -Z at 1:1 scale")
	assert(absf(bounds.position.y) < 0.001)
	assert(runway.global_position.is_equal_approx(Vector3.ZERO))
	var shelters := visual.find_children("arched_shelter_*", "Node3D", true, false)
	assert(shelters.size() == 4)
	for name in ["south_operations", "north_workshop", "radar_equipment"]:
		var envelope := visual.find_child(name + "_envelope", true, false) as MeshInstance3D
		assert(absf((envelope.global_transform * envelope.get_aabb()).position.y) < 0.01, "Building rests on pavement")
	var materials: Dictionary = {}
	for node in meshes:
		var instance := node as MeshInstance3D
		for index in instance.mesh.get_surface_count():
			var material := instance.get_active_material(index) as BaseMaterial3D
			assert(material != null)
			assert(material.albedo_texture != null, "Every surface has an actual Poly Haven albedo")
			assert(material.normal_enabled and material.normal_texture != null, "Normal maps survive glTF import")
			if material is ORMMaterial3D:
				assert((material as ORMMaterial3D).orm_texture != null)
			else:
				assert((material as StandardMaterial3D).roughness_texture != null)
			materials[material.resource_name] = true
	assert(materials.size() == 13, "Shared exported materials")
	assert(visual.find_children("hangar_truss_*", "MeshInstance3D", true, false).size() == 15)
	var first_skin := visual.find_child("shelter_skin_01", true, false) as MeshInstance3D
	for index in range(2, 5):
		var linked_skin := visual.find_child("shelter_skin_%02d" % index, true, false) as MeshInstance3D
		assert(linked_skin.mesh == first_skin.mesh, "Shelters preserve shared geometry")
	var space := airport.get_world_3d().direct_space_state
	# Sample both sides of the pavement seams and all main paved zones.
	for x in [-159.0, -145.99, -30.01, -29.99, 0.0, 29.99, 30.01, 109.99, 110.01, 190.0, 330.0, 520.0]:
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(x, 2, 1180), Vector3(x, -2, 1180)))
		assert(not hit.is_empty(), "Continuous south cross-taxiway: %s" % x)
	for point in [Vector3(0, 2, -1100), Vector3(-460, 2, 300), Vector3(-310, 2, 870), Vector3(-200, 2, -550)]:
		assert(not space.intersect_ray(PhysicsRayQueryParameters3D.create(point, point - Vector3(0, 4, 0))).is_empty())
	for x in [425.0, 190.0]:
		var entrance_z := 1139.0 if x == 425.0 else 1113.0
		assert(space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(x, 6, entrance_z + 15), Vector3(x, 6, entrance_z - 15))).is_empty(), "Open entrance must not be capped by collision")
	assert(not space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(425, 8, 950), Vector3(425, 8, 775))).is_empty(), "Hangar rear wall collides")
	assert(not space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(394, 5, 965), Vector3(398, 5, 965))).is_empty(), "Interior structural column collides without capping the aisle")
	var dome_hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(-354, 50, -990), Vector3(-354, 0, -990)))
	assert(not dome_hit.is_empty() and absf(dome_hit.position.y - 32.2) < 0.02)
	print("PASS: AIRPORT_ASSET_CHECK_OK meshes=103 materials=13 PBR_maps=ok linked_shelters=ok runway=60x2400 collision_seams_and_openings=ok")
	airport.free()
	quit(0)
