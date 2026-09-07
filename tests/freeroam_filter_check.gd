extends SceneTree
## Godot --path . --script tests/freeroam_filter_check.gd

func _initialize() -> void:
	call_deferred("check")

func check() -> void:
	var scene = load("res://scenes/levels/freeroam.tscn").instantiate()
	root.add_child(scene)
	for frame in range(60):
		await process_frame
	var initial_msaa := root.msaa_3d
	var key := InputEventKey.new()
	key.keycode = KEY_F6
	key.pressed = true
	for expected in [1, 2, 0, 1, 2, 0]:
		scene._unhandled_input(key)
		# Render each preset with the cloud compositor active, not all in one frame.
		for frame in range(60):
			await process_frame
		assert(scene.mode == expected)
		assert(root.use_taa == (true if expected == 1 else (scene.initial_taa if expected == 0 else false)))
		assert(root.msaa_3d == initial_msaa, "Toggle must never reconfigure MSAA")
		if DisplayServer.get_name() != "headless":
			assert(is_equal_approx(scene.terrain_material.get_shader_param("depth_blur"), 2.0 if expected == 2 else scene.initial_blur))
		assert(scene.MODES[expected] in scene.label.text)
	key.echo = true
	scene._unhandled_input(key)
	assert(scene.mode == 0, "Held key must not cycle repeatedly")
	key.echo = false
	key.pressed = false
	scene._unhandled_input(key)
	assert(scene.mode == 0, "Key release must not cycle")
	print("PASS: F6 renders two full cycles with clouds, restores settings, leaves MSAA unchanged")
	quit()
