extends SceneTree
## Godot --headless --path . --script tests/sky3d_clear_day_check.gd
## Omit --headless and add --fixed-fps 30 -- --capture for 1080p production views.
## Runtime-only: never saves scenes, terrain, cloud resources or user settings.

func _initialize() -> void:
	call_deferred("check")

func check() -> void:
	create_timer(180.0).timeout.connect(func():
		push_error("Sky3D check timed out; inspect preceding errors")
		quit(1))
	var capture := "--capture" in OS.get_cmdline_user_args()
	assert(not capture or DisplayServer.get_name() != "headless")
	root.size = Vector2i(1920, 1080)
	root.content_scale_size = root.size
	var output := "user://sky3d_clear_day/" + Time.get_datetime_string_from_system().replace(":", "-") + "-" + str(OS.get_process_id())
	if capture:
		assert(DirAccess.make_dir_recursive_absolute(output) == OK)
	for name in ["freeroam", "tutorial"]:
		var level = load("res://scenes/levels/%s.tscn" % name).instantiate()
		root.add_child(level)
		current_scene = level
		# Freeze flight, AI, boundary and wind immediately; render the authored scene only.
		level.process_mode = Node.PROCESS_MODE_DISABLED
		var map = level.get_node("GardaLake")
		var sky: Sky3D = map.get_node("Sky3D")
		var dome: SkyDome = sky.sky
		for frame in 60:
			await process_frame
		assert(sky.is_day() and not sky.editor_time_enabled and not sky.game_time_enabled)
		assert(is_equal_approx(sky.current_time, 10.5) and sky.sun.position.y > 0.7)
		assert(sky.clouds_enabled and dome.cirrus_visible and not dome.cumulus_visible)
		assert(not sky.fog_enabled and not dome.fog_visible, "No double fog over Sunshine")
		assert(dome.cirrus_texture.get_width() == 2048 and dome.cirrus_texture.get_height() == 2048)
		assert(dome.cirrus_texture.seamless and dome.cirrus_coverage < 0.5)
		assert(dome.atm_day_tint.is_equal_approx(Color(0.74, 0.89, 1.0)))
		assert(dome.horizon_offset == 0.0 and is_equal_approx(dome.sun_disk_size, 0.009))
		assert(sky.environment.ambient_light_source == Environment.AMBIENT_SOURCE_SKY)
		assert(sky.environment.sky.process_mode == Sky.PROCESS_MODE_INCREMENTAL)
		assert(is_equal_approx(sky.sun.light_energy, 1.8))
		for property in ["atm_day_tint", "atm_darkness", "atm_thickness", "sun_disk_size", "cirrus_coverage", "cirrus_texture", "cirrus_visible", "cumulus_visible"]:
			assert(dome.get(property) == sky.sky_material.get_shader_parameter(property), "SkyDome/shader mismatch: " + property)
		var sun_pose := sky.sun.transform
		dome.process_tick(0.0) # Initialize this instance's phase in the shared shader material.
		var cloud_phase: Vector2 = sky.sky_material.get_shader_parameter("cirrus_position1")
		dome.process_tick(1.0)
		assert(sky.sky_material.get_shader_parameter("cirrus_position1") != cloud_phase, "Cirrus must drift")
		assert(sky.sun.transform == sun_pose, "Sun must remain fixed")
		var driver = map.get_node("SunshineCloudsDriverGD")
		assert(DisplayServer.get_name() == "headless" or driver.clouds_resource.enabled, "Volumetric compositor must render")
		assert(is_equal_approx(driver.clouds_resource.clouds_coverage, 0.834), "Preserve the separate volumetric layer")
		if capture:
			var player = level.get_node("Player")
			var camera: Camera3D = player.get_node("FlightCamera")
			camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
			for child in level.get_children():
				if child is CanvasLayer:
					child.hide()
			driver.retrieve_texture_data()
			for view in ["flight", "sky", "sun"]:
				player.visible = view == "flight"
				camera.global_position = player.global_position + Vector3(0, 1, 6)
				var direction := Vector3(0, -0.1, -1) if view == "flight" else Vector3(0, 0.55, -1)
				camera.look_at(camera.global_position + (sky.sun.position.normalized() if view == "sun" else direction))
				camera.force_update_transform()
				map.get_node("GardaTerrain").set_camera(camera) # Viewing only, no terrain edits.
				for frame in 96: # Settle Sunshine history and incremental sky reflections.
					await RenderingServer.frame_post_draw
				var image := root.get_texture().get_image()
				assert(image != null and image.get_size() == root.size)
				assert(image.save_png(output.path_join(name + "_" + view + ".png")) == OK)
		print("PASS: ", name, " — fixed clear morning, native cirrus, shader synchronization, existing volumes preserved")
		level.queue_free()
		for frame in 4:
			await process_frame
	if capture:
		print("Captures: ", ProjectSettings.globalize_path(output))
	quit()
