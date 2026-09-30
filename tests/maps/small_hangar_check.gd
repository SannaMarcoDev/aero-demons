extends SceneTree
## Run through tools/run_godot_check.cjs (45 s deadline).

func _initialize() -> void:
	_run.call_deferred()

func _ray(world: World3D, from: Vector3, to: Vector3) -> Dictionary:
	return world.direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from, to))

func _run() -> void:
	for audio in root.get_node("AudioManager").get_children():
		if audio is AudioStreamPlayer:
			audio.stop()
			audio.stream = null
	var packed: PackedScene = load("res://scenes/maps/small_hangar.tscn")
	var hangar: Node3D = packed.instantiate()
	root.add_child(hangar)
	var player: AnimationPlayer = hangar.get_node("Model/AnimationPlayer")
	assert(player.has_animation("SmallHangar"))
	assert(is_equal_approx(player.get_animation("SmallHangar").length, 12.0))
	var upper: Node3D = hangar.get_node("Model/SmallHangar/DoorUpper")
	var lower: Node3D = upper.get_node("DoorLower")
	assert(hangar.get_node("ShellCollision").get_child_count() == 9)
	assert(hangar.get_node("DoorUpperCollision/Shape").shape is BoxShape3D)
	var triangles := 0
	var surfaces := 0
	for mesh: MeshInstance3D in hangar.find_children("*", "MeshInstance3D", true, false):
		assert(mesh.mesh != null)
		for surface in mesh.mesh.get_surface_count():
			var arrays := mesh.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
			assert(uv.size() == vertices.size())
			for v in vertices:
				assert(v.is_finite())
			assert(mesh.mesh.surface_get_material(surface) != null)
			triangles += arrays[Mesh.ARRAY_INDEX].size() / 3
			surfaces += 1
	assert(triangles == 37620 and surfaces == 21)
	await physics_frame
	await physics_frame
	var world := hangar.get_world_3d()
	assert(not _ray(world, Vector3(0, 2.5, 16), Vector3(0, 2.5, 10)).is_empty(), "Closed door must collide")
	hangar.set_open(true, true)
	await physics_frame
	await physics_frame
	assert(is_equal_approx(absf(upper.rotation.x), PI / 2.0))
	var bottom := lower.to_global(Vector3(0, -2.55, 0))
	assert(absf(bottom.z - 12.36) < 0.002 and absf(bottom.y - 5.16) < 0.002)
	assert(_ray(world, Vector3(0, 2.5, 16), Vector3(0, 2.5, 10)).is_empty(), "Open door must not block taxi")
	assert(_ray(world, Vector3(0, 4.75, 16), Vector3(0, 4.75, 10)).is_empty(), "4.75 m tail clearance")
	assert(not _ray(world, Vector3(0, 4.95, 16), Vector3(0, 4.95, 12.6)).is_empty(), "Folded door overhead collision")
	assert(not _ray(world, Vector3(0, 1, 0), Vector3(0, -1, 0)).is_empty(), "Floor collision")
	for x in [-10.0, 10.0]:
		var hit := _ray(world, Vector3(x, 12, 0), Vector3(x, 0, 0))
		assert(not hit.is_empty() and absf(hit.position.y - 3.09) < 0.2, "Roof collision must match the sloped roof")
	# Check all sampled poses, plus reversible motion without teleporting.
	for i in range(61):
		hangar._apply_pose(i / 60.0)
		bottom = lower.to_global(Vector3(0, -2.55, 0))
		assert(absf(bottom.z - 12.36) < 0.004, "Pose %d bottom=%s upper=%s lower=%s" % [i, bottom, upper.rotation, lower.rotation])
		assert(hangar.get_node("DoorLowerCollision").global_transform.is_equal_approx(lower.global_transform))
	hangar.set_open(false, true)
	hangar.set_open(true)
	for i in range(60):
		await physics_frame
	assert(hangar.openness > 0.1 and hangar.openness < 0.5)
	var pose: Transform3D = upper.transform
	hangar.set_open(false)
	assert(upper.transform.is_equal_approx(pose), "Reversal must not jump")
	for i in range(90):
		await physics_frame
	assert(is_zero_approx(hangar.openness))
	var second: Node3D = packed.instantiate()
	root.add_child(second)
	second.position.x = 50
	var first_mesh: MeshInstance3D = upper as MeshInstance3D
	var second_mesh: MeshInstance3D = second.get_node("Model/SmallHangar/DoorUpper")
	assert(first_mesh.mesh == second_mesh.mesh, "Instances share mesh/material resources")
	second.set_open(true, true)
	assert(is_zero_approx(hangar.openness) and is_equal_approx(second.openness, 1.0))
	second.free()
	hangar.free()
	await create_timer(0.25).timeout
	print("PASS: SMALL_HANGAR_CHECK 37620 triangles, 21 surfaces, UV/PBR, 61 poses, opening/closing/reversal, real collision rays, shared meshes, independent instances")
	quit()
