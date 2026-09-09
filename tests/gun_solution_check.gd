extends SceneTree
## Run: godot --headless --path . --script tests/gun_solution_check.gd

const Solver = preload("res://scripts/weapons/gun_solution.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var target := Vector3(0, 0, -1000)
	var still := Solver.solve(Vector3.ZERO, Vector3.ZERO, target, Vector3.ZERO, 1200, 0)
	assert(absf(still.time - 1000.0 / 1200.0) < 0.0001)
	var lateral := Solver.solve(Vector3.ZERO, Vector3.ZERO, target, Vector3(100, 0, 0), 1200, 9.8)
	var faster := Solver.solve(Vector3.ZERO, Vector3.ZERO, target, Vector3(200, 0, 0), 1200, 9.8)
	assert(faster.direction.x > lateral.direction.x)
	assert(lateral.direction.y > 0.0)
	var matched := Solver.solve(Vector3.ZERO, Vector3(100, 0, 0), target, Vector3(100, 0, 0), 1200, 9.8)
	assert(absf(matched.direction.x) < 0.00001)
	var slower := Solver.solve(Vector3.ZERO, Vector3.ZERO, target, Vector3(100, 0, 0), 600, 9.8)
	assert(slower.time > lateral.time and slower.direction.x > lateral.direction.x)
	for shooter in [Vector3.ZERO, Vector3(130, 40, -250)]:
		var muzzle := Vector3(20, 800, 50)
		var moving := Vector3(180, -35, 80)
		var solution := Solver.solve(muzzle, shooter, target + muzzle, moving, 1200, 9.8)
		assert(not solution.is_empty())
		var t: float = solution.time
		var impact: Vector3 = muzzle + (solution.direction * 1200 + shooter) * t + Vector3.DOWN * 4.9 * t * t
		assert(impact.distance_to(solution.intercept_position) < 0.02)
	assert(Solver.solve(Vector3.ZERO, Vector3.ZERO, target * 2, Vector3.ZERO, 1200, 9.8).is_empty())
	assert(Solver.solve(Vector3.ZERO, Vector3.ZERO, target, Vector3(0, 0, -1300), 1200, 0).is_empty())
	assert(Solver.solve(Vector3.ZERO, Vector3.ZERO, target, Vector3.ZERO, 0, 0).is_empty())
	assert(Solver.solve(Vector3.ZERO, Vector3.ZERO, target, Vector3.ZERO, 1200, 0, 1500, 900).is_empty())
	# Linear quadratic degeneration: approaching at exactly projectile speed.
	var linear := Solver.solve(Vector3.ZERO, Vector3.ZERO, target, Vector3(0, 0, 1200), 1200, 0)
	assert(absf(linear.time - 1000.0 / 2400.0) < 0.0001)
	var near := {"direction": Vector3.FORWARD.rotated(Vector3.UP, deg_to_rad(2.0))}
	var assisted := Solver.assisted_direction(Vector3.FORWARD, near, 2.5, 0.35)
	assert(absf(rad_to_deg(Vector3.FORWARD.angle_to(assisted)) - 0.7) < 0.001)
	assert(Solver.assisted_direction(Vector3.FORWARD, near, 1.0, 1.0).is_equal_approx(Vector3.FORWARD))
	assert(Solver.assisted_direction(Vector3.FORWARD, near, 2.5, 0.0).is_equal_approx(Vector3.FORWARD))
	var camera := Camera3D.new()
	root.add_child(camera)
	var before := camera.unproject_position(target)
	camera.position.x = 100.0
	assert(camera.unproject_position(target).distance_to(before) > 1.0)
	camera.rotation.y = PI
	assert(camera.is_position_behind(target))
	camera.free()
	print("Gun solution checks passed")
	quit()
