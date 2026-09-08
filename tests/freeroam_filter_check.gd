extends SceneTree
## Godot --path . --script tests/freeroam_filter_check.gd
## -- --capture saves one PNG per mode in user://filter_comparison/.

func _initialize() -> void:
	call_deferred("check")

func check() -> void:
	var scene = load("res://scenes/levels/tutorial.tscn").instantiate()
	root.add_child(scene)
	for frame in range(60):
		await process_frame
	var initial_msaa := root.msaa_3d
	var key := InputEventKey.new()
	key.keycode = KEY_F6
	key.pressed = true
	var capture := "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless"
	if capture:
		assert(DirAccess.make_dir_recursive_absolute("user://filter_comparison") == OK)
	for step in range(scene.MODES.size() * 2):
		var expected: int = (step + 1) % scene.MODES.size()
		scene._unhandled_input(key)
		# Render each mode with clouds active, including render-buffer reallocations.
		for frame in range(60):
			await process_frame
		assert(scene.mode == expected)
		assert(root.use_taa == (scene.initial_taa if expected == 0 else expected == 1))
		assert(root.msaa_3d == initial_msaa, "Toggle must never reconfigure MSAA")
		assert(is_equal_approx(root.scaling_3d_scale, scene.initial_scale if expected == 0 else (1.25 if expected == 2 else (1.5 if expected == 3 else 1.0))))
		assert(root.scaling_3d_mode == (scene.initial_scaling if expected == 0 else (Viewport.SCALING_3D_MODE_FSR2 if expected == 4 else Viewport.SCALING_3D_MODE_BILINEAR)))
		assert(root.screen_space_aa == (scene.initial_screen_aa if expected == 0 else (Viewport.SCREEN_SPACE_AA_FXAA if expected == 5 else Viewport.SCREEN_SPACE_AA_DISABLED)))
		assert(scene.terrain_material.shader_override_enabled == (true if expected == 6 else scene.initial_override))
		if DisplayServer.get_name() != "headless":
			assert(scene.terrain_material.shader_override == (scene.terrain_filter if expected == 6 else scene.initial_shader))
			assert(is_equal_approx(scene.terrain_material.get_shader_param("depth_blur"), 2.0 if expected == 7 else scene.initial_blur))
		assert(scene.MODES[expected] in scene.label.text)
		if capture and step < scene.MODES.size():
			await RenderingServer.frame_post_draw
			assert(root.get_texture().get_image().save_png("user://filter_comparison/%02d.png" % expected) == OK)
		print("Rendered: ", scene.MODES[expected])
	key.echo = true
	scene._unhandled_input(key)
	assert(scene.mode == 0, "Held key must not cycle repeatedly")
	key.echo = false
	key.pressed = false
	scene._unhandled_input(key)
	assert(scene.mode == 0, "Key release must not cycle")
	print("PASS: F6 renders two full cycles with clouds, restores settings, leaves MSAA unchanged")
	quit()
