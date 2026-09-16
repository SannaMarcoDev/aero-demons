extends SceneTree
## godot --headless --path . --script tests/hangar_lighting_check.gd

func _initialize() -> void:
	_check.call_deferred()

func _check() -> void:
	# This scene-only check does not exercise the autoplay music autoload.
	root.get_node("AudioManager")._music_player.stop()
	await create_timer(0.1).timeout
	var stage: Node3D = load("res://scenes/ui/menu_aircraft_stage.tscn").instantiate()
	root.add_child(stage)
	await process_frame
	var hangar := stage.get_node("Hangar")
	assert(hangar.has_node("HAS_Arch_Rib_10"), "Updated hangar must be imported")
	assert(hangar.has_node("HAS_LED_Floodlight_L_6"))
	assert(not hangar.has_node("HAS_Pendant_0_1"), "Old hanging lights must be gone")
	assert(stage.find_children("*", "Label3D", true, false).is_empty())
	assert(not stage.has_node("FloorMarkings") and not stage.has_node("ServiceEquipment"))
	var lights := stage.get_node("Lighting").get_children()
	assert(lights.size() == 8)
	for light: Light3D in lights:
		assert(light.light_energy > 0.0)
		assert(light.position.y > 0.0 and light.position.y < 9.8)
		assert(absf(light.position.x) < 16.0)
	assert(stage.get_node("HangarReflections").update_mode == ReflectionProbe.UPDATE_ONCE)
	for wheel_name in ["NoseWheel", "LeftWheel", "RightWheel"]:
		var wheel: MeshInstance3D = stage.get_node("Aircraft/DisplayLandingGear/" + wheel_name)
		assert(is_zero_approx(wheel.global_position.y - wheel.mesh.top_radius))
	stage.free()
	await process_frame
	print("HANGAR_LIGHTING_CHECK_PASSED")
	quit(0)
