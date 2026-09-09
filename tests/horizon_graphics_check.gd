extends SceneTree
## Godot --headless --path . --script tests/horizon_graphics_check.gd
## Graphical -- --capture also saves the real C/D UI at user://horizon_graphics_check_<run>/.
## Uses a unique settings file, never the player's graphics.cfg.

func _initialize() -> void:
	call_deferred("check")

func check() -> void:
	var run_id := "%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	var settings_path := "user://horizon_graphics_check_" + run_id + ".cfg"
	var output := "user://horizon_graphics_check_" + run_id
	var capture := "--capture" in OS.get_cmdline_user_args()
	assert(not capture or DisplayServer.get_name() != "headless")
	assert(not FileAccess.file_exists(settings_path))
	if capture:
		root.size = Vector2i(1280, 720)
		root.content_scale_size = root.size
		assert(DirAccess.make_dir_recursive_absolute(output) == OK)
	var key := InputEventKey.new()
	key.keycode = KEY_F7
	key.pressed = true
	for index in 3:
		var scene = load("res://scenes/levels/tutorial.tscn" if index == 1 else "res://scenes/levels/freeroam.tscn").instantiate()
		var option = scene.get_node("HorizonGraphics")
		option.settings_path = settings_path
		root.add_child(scene)
		current_scene = scene
		var player = scene.get_node("Player")
		player.set_physics_process(false)
		var camera: Camera3D = player.get_node("FlightCamera")
		camera.set_physics_process(false)
		var pose := Transform3D(Basis.from_euler(Vector3(deg_to_rad(-17.0), 0.0, deg_to_rad(-18.0))), Vector3(-4700, 12000, 850))
		player.reset_flight(pose)
		camera.snap_to_target()
		var map = scene.get_node("GardaLake")
		map.get_node("TutorialBoundaryController").set_physics_process(false)
		map.get_node("GardaTerrain").set_camera(camera)
		var clouds = map.get_node("SunshineCloudsDriverGD").clouds_resource
		var environment_attributes = map.get_node("Sky3D").camera_attributes
		var viewport_state := [root.msaa_3d, root.use_taa, root.scaling_3d_mode, root.scaling_3d_scale, root.screen_space_aa]
		assert(camera.attributes == option.attributes and camera.attributes != environment_attributes)
		assert(camera.attributes.exposure_multiplier == environment_attributes.exposure_multiplier)
		assert(camera.attributes.auto_exposure_enabled == environment_attributes.auto_exposure_enabled)
		assert(not environment_attributes.dof_blur_far_enabled)
		assert(is_equal_approx(clouds.atmospheric_density, 2.0))
		assert(is_equal_approx(clouds.use_environment_fog, 0.65))
		assert(clouds.atmosphere_color.is_equal_approx(Color(0.55, 0.64, 0.75)))
		assert(clouds.sampled_environment_fog_color.is_equal_approx(clouds.atmosphere_color))
		assert(not map.get_node("Sky3D").fog_enabled and not map.get_node("Sky3D/SkyDome").fog_visible)
		assert(map.get_node("SunshineCloudsDriverGD").ambience_sample_environment == null)
		assert(option.attributes.dof_blur_far_enabled == (index == 1), "Default C, saved D, then saved C")
		assert(("D ·" if index == 1 else "C · Standard") in option.label.text)
		assert(is_equal_approx(option.attributes.dof_blur_amount, 0.08))
		assert(option.attributes.dof_blur_far_distance == 35000.0)
		assert(option.attributes.dof_blur_far_transition == 45000.0)
		if index == 0:
			assert(not FileAccess.file_exists(settings_path), "Startup must not save settings")
			option.settings.set_value("unrelated", "sentinel", 17)
			if capture:
				for frame in 120:
					await process_frame
				map.get_node("SunshineCloudsDriverGD").set_process(false)
				for frame in 96:
					await RenderingServer.frame_post_draw
				assert(root.get_texture().get_image().save_png(output.path_join("C-standard.png")) == OK)
		if index < 2:
			# Real input dispatch must work even with the tutorial pause menu open.
			if index == 1:
				scene.get_node("CombatHUD")._open_pause_menu()
			# Viewport dispatch also works without an OS-focused window in headless tests.
			root.push_input(key)
			assert(option.attributes.dof_blur_far_enabled == (index == 0))
			key.echo = true
			root.push_input(key)
			key.echo = false
			key.pressed = false
			root.push_input(key)
			key.pressed = true
			assert(option.attributes.dof_blur_far_enabled == (index == 0), "Echo/release must not toggle")
			assert(option.attributes.dof_blur_far_enabled == option.settings.get_value("graphics", "horizon_blur"))
			var saved := ConfigFile.new()
			assert(saved.load(settings_path) == OK)
			assert(saved.get_value("graphics", "horizon_blur") == (index == 0))
			assert(saved.get_value("unrelated", "sentinel") == 17)
			if index == 1:
				scene.get_node("CombatHUD")._close_pause_menu()
			if capture and index == 0:
				for frame in 96:
					await RenderingServer.frame_post_draw
				assert(root.get_texture().get_image().save_png(output.path_join("D-optional.png")) == OK)
		assert(viewport_state == [root.msaa_3d, root.use_taa, root.scaling_3d_mode, root.scaling_3d_scale, root.screen_space_aa])
		assert(scene.mode == 0, "F7 must not cycle F6 filters")
		assert(not environment_attributes.dof_blur_far_enabled, "Shared exposure/DOF resource unchanged")
		assert(is_equal_approx(clouds.atmospheric_density, 2.0) and is_equal_approx(clouds.use_environment_fog, 0.65))
		assert(clouds.atmosphere_color.is_equal_approx(Color(0.55, 0.64, 0.75)))
		scene.queue_free()
		await process_frame
	assert(DirAccess.remove_absolute(settings_path) == OK)
	if capture:
		print("Captures: ", ProjectSettings.globalize_path(output))
	print("PASS: C default, F7 D/C, persistence across both scenes, pause/echo/release, exposure preserved, no F6/atmosphere changes")
	quit()
