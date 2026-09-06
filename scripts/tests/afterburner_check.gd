extends SceneTree
## Run: godot --headless --path . --script scripts/tests/afterburner_check.gd

func _initialize() -> void:
	call_deferred("_check")


func _check() -> void:
	var controller_script = load("res://scripts/vfx/afterburner.gd")
	var thruster_scene = load("res://assets/thrusters/blue_thruster/scenes/jet_thruster_vfx.tscn")
	var engines = controller_script.new()
	for index in 2:
		var thruster = thruster_scene.instantiate()
		thruster.smooth_throttle = false
		engines.add_child(thruster)
	root.add_child(engines)
	for throttle in [0.0, 0.35, 0.5]:
		engines.set_throttle(throttle)
		for thruster in engines.get_children():
			assert(is_equal_approx(thruster.throttle, throttle))
			var material = thruster.get_node("PlumeMain").get_surface_override_material(0)
			assert(is_equal_approx(material.get_shader_parameter("throttle"), throttle))
	engines.set_boost(1.0)
	for thruster in engines.get_children():
		assert(is_equal_approx(thruster.throttle, 1.0))
		assert(is_equal_approx(thruster.exhaust_length, engines.boost_plume_length))
		assert(is_equal_approx(thruster.light_intensity, engines.light_intensity * engines.boost_light_multiplier))
	engines.set_boost(0.5)
	assert(is_equal_approx(engines.get_child(0).throttle, 0.75))
	engines.set_boost(0.0)
	assert(is_equal_approx(engines.get_child(0).throttle, 0.5))
	engines.set_throttle(0.35)
	for thruster in engines.get_children():
		assert(is_equal_approx(thruster.exhaust_length, engines.plume_length))
		assert(is_equal_approx(thruster.throttle, 0.35))
	engines.set_throttle(-1.0)
	assert(engines.get_child(0).throttle == 0.0)
	engines.set_throttle(2.0)
	assert(engines.get_child(0).throttle == 0.5)
	var smooth_thruster = engines.get_child(0)
	smooth_thruster.smooth_throttle = true
	engines.set_boost(1.0)
	smooth_thruster._process(0.1)
	assert(is_equal_approx(smooth_thruster._current_throttle, 1.0))
	engines.set_boost(0.0)
	smooth_thruster._process(0.1)
	assert(is_equal_approx(smooth_thruster._current_throttle, 0.5))
	var ring_thruster = engines.get_child(0)
	for distance in [0.0, 0.1, 0.65, 2.0]:
		ring_thruster.flame_holder_distance = distance
		assert(is_equal_approx(ring_thruster.get_node("FlameHolder").position.z, -distance))
	engines.free()
	print("Afterburner throttle / boost / reset / ring distance: PASS")
	quit()
