extends SceneTree
## Run: godot --headless --path . --script tests/player_camera_check.gd

func _initialize() -> void:
	call_deferred("_check")

func _check() -> void:
	var player = load("res://scenes/player/player.tscn").instantiate()
	player.position = Vector3(100.0, 2000.0, 50.0)
	root.add_child(player)
	player.set_physics_process(false)
	var camera = player.get_node("FlightCamera")
	camera.set_physics_process(false)
	assert(camera.target == player)
	assert(camera.top_level)
	assert(camera.scale.is_equal_approx(Vector3.ONE))
	assert(camera.global_transform.is_equal_approx(camera._chase_transform()))
	var previous: Transform3D = camera.global_transform
	player.rotate_z(0.5)
	player.position.x += 100.0
	assert(camera.global_transform.is_equal_approx(previous))
	player.camera_height = 6.0
	player.camera_depth = 12.0
	player.camera_pitch = -5.0
	player.camera_fov = 80.0
	camera.snap_to_target()
	assert(is_equal_approx(camera.fov, 80.0))
	var offset: Vector3 = player.global_basis.inverse() * (camera.global_position - player.global_position)
	assert(offset.is_equal_approx(Vector3(0.0, 6.0, 12.0)))
	assert(camera.global_basis.is_equal_approx(player.global_basis * Basis.from_euler(Vector3(deg_to_rad(-5.0), 0.0, 0.0))))
	player.free()
	print("Player camera check passed")
	quit()
