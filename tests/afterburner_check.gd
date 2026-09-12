extends SceneTree
## Run: godot --headless --path . --script tests/afterburner_check.gd

func _initialize() -> void:
	call_deferred("_check")


func _check() -> void:
	var controller_script = load("res://scripts/vfx/afterburner.gd")
	var exhaust_scene = load("res://scenes/vfx/jet_exhaust.tscn")
	var engines = controller_script.new()
	for index in 2:
		engines.add_child(exhaust_scene.instantiate())
	root.add_child(engines)
	for throttle in [0.0, 0.35, 0.5]:
		engines.set_throttle(throttle)
		for exhaust in engines.get_children():
			assert(is_equal_approx(exhaust.throttle, throttle * 1.7))
	engines.set_boost(1.0)
	for exhaust in engines.get_children():
		assert(is_equal_approx(exhaust.throttle, 1.0))
	engines.set_boost(0.5)
	assert(is_equal_approx(engines.get_child(0).throttle, lerpf(0.5 * 1.7, 1.0, 0.5)))
	engines.set_boost(0.0)
	assert(is_equal_approx(engines.get_child(0).throttle, 0.5 * 1.7))
	engines.set_throttle(-1.0)
	assert(engines.get_child(0).throttle == 0.0)
	engines.set_throttle(2.0)
	assert(is_equal_approx(engines.get_child(0).throttle, 0.5 * 1.7))
	# Twins must not share throttle state.
	var mat_a = engines.get_child(0).get_node("Volume").material_override
	var mat_b = engines.get_child(1).get_node("Volume").material_override
	assert(mat_a != mat_b, "Twin engines must not share throttle state")
	engines.free()
	print("Afterburner throttle / boost mapping: PASS")
	quit()
