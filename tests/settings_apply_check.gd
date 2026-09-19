extends SceneTree
## Godot --path . --script tests/settings_apply_check.gd  (needs a real GPU context)
## Verifies SettingsManager.apply_settings actually drives the scene nodes.

const Settings = preload("res://scripts/ui/settings_manager.gd")

func _initialize() -> void:
	call_deferred("check")

func check() -> void:
	var defaults = load(Settings.CLOUDS_RESOURCE_PATH)
	var ultra: Dictionary = Settings.CLOUD_PRESETS[Settings.CLOUDS_ULTRA]
	assert(defaults.resolution_scale == ultra.res and defaults.max_step_count == ultra.steps)
	assert(defaults.max_lighting_steps == ultra.light_steps and defaults.blur_quality == ultra.blur_q)
	assert(not SunshineCloudsGD.camera_cut(Transform3D.IDENTITY, Transform3D(Basis(Vector3.UP, 0.1), Vector3(2, 0, 0))))
	assert(SunshineCloudsGD.camera_cut(Transform3D.IDENTITY, Transform3D(Basis.IDENTITY, Vector3(1001, 0, 0))))
	assert(SunshineCloudsGD.camera_cut(Transform3D.IDENTITY, Transform3D(Basis(Vector3.UP, PI / 3.0), Vector3.ZERO)))
	var level = load("res://scenes/levels/freeroam.tscn").instantiate()
	root.add_child(level)
	for i in 10:
		await process_frame
	var sky: Sky3D = level.get_node("GardaLake/Sky3D")
	var driver = level.get_node("GardaLake/SunshineCloudsDriverGD")
	var clouds: SunshineCloudsGD = driver.clouds_resource
	var env: Environment = sky.environment

	var s := Settings.load_settings()
	s.quality_preset = Settings.QUALITY_CUSTOM
	s.clouds_quality = Settings.CLOUDS_OFF
	s.shadows = Settings.SHADOWS_OFF
	s.ssao = true
	s.glow = true
	s.tonemap = Settings.TONEMAP_FILMIC
	s.exposure = 1.5
	s.sky_cirrus = false
	s.sky_cumulus = true
	s.sky_fog = true
	s.clouds_coverage = 0.5
	s.render_scale = 0.67
	s.upscaler = Settings.UPSCALER_FSR
	s.fsr_sharpness = 0.6
	Settings.apply_settings(s)
	for i in 10:
		await process_frame
	assert(not clouds.enabled, "clouds OFF must disable the compositor effect")
	assert(is_equal_approx(clouds.clouds_coverage, 0.5))
	assert(not sky.sun.shadow_enabled, "shadows OFF must disable sun shadows")
	assert(env.ssao_enabled and env.glow_enabled)
	assert(env.tonemap_mode == Environment.TONE_MAPPER_FILMIC)
	assert(is_equal_approx(env.tonemap_exposure, 1.5))
	assert(not sky.sky.cirrus_visible and sky.sky.cumulus_visible)
	assert(sky.fog_enabled and sky.sky.fog_visible)
	assert(root.scaling_3d_mode == Viewport.SCALING_3D_MODE_FSR)
	assert(is_equal_approx(root.scaling_3d_scale, 0.67))
	assert(is_equal_approx(root.fsr_sharpness, 0.6))

	s.clouds_quality = Settings.CLOUDS_LOW
	s.shadows = Settings.SHADOWS_ULTRA
	s.ssao = false
	s.upscaler = Settings.UPSCALER_FSR2
	s.render_scale = 1.25
	Settings.apply_settings(s)
	for i in 10:
		await process_frame
	assert(clouds.enabled and clouds.resolution_scale == 3, "LOW = eighth-res clouds")
	assert(is_equal_approx(clouds.max_step_count, 128.0))
	assert(is_equal_approx(clouds.max_lighting_steps, 8.0))
	assert(driver.tracked_directional_light_shadow_steps.size() == 1 and driver.tracked_directional_light_shadow_steps[0] == 6, "driver sun steps follow preset")
	assert(clouds.directional_lights_data[0].w == 6.0, "light data carries the step count")
	assert(sky.sun.shadow_enabled and sky.sun.directional_shadow_max_distance == 8000.0)
	assert(is_equal_approx(root.scaling_3d_scale, 1.0), "FSR2 clamps supersampling")
	assert(not env.ssao_enabled)

	s.clouds_quality = Settings.CLOUDS_ULTRA
	Settings.apply_settings(s)
	for i in 10:
		await process_frame
	assert(clouds.resolution_scale == 1 and is_equal_approx(clouds.max_step_count, 700.0))
	assert(clouds.max_lighting_steps == 16.0 and clouds.blur_quality == 1.0)
	assert(driver.tracked_directional_light_shadow_steps == [16] and clouds.directional_lights_data[0].w == 16.0)
	assert(clouds.history_valid)
	for quality in [Settings.CLOUDS_HIGH, Settings.CLOUDS_MEDIUM, Settings.CLOUDS_ULTRA]:
		s.clouds_quality = quality
		Settings.apply_settings(s)
		for i in 10: await process_frame
		var p: Dictionary = Settings.CLOUD_PRESETS[quality]
		assert(clouds.resolution_scale == p.res and clouds.max_step_count == p.steps)
		assert(driver.tracked_directional_light_shadow_steps == [p.sun_steps])
		assert(clouds.directional_lights_data[0].w == p.sun_steps)
	var size := clouds.last_size
	var pipeline := clouds.pipeline
	assert(size != Vector2i.ZERO and pipeline.is_valid())
	# Audio/control updates also reapply graphics. The same quality must not
	# invalidate the cloud buffers, history and pipelines.
	Settings.apply_settings(s)
	assert(clouds.last_size == size, "Unchanged cloud resolution must retain buffers")
	for i in 10:
		await process_frame
	assert(clouds.pipeline == pipeline, "Unchanged quality must not rebuild the pipeline")
	sky.compositor = null
	RenderingServer.call_on_render_thread(clouds.clear_compute)
	await RenderingServer.frame_post_draw
	assert(not clouds.history_valid, "Retired GPU buffers must invalidate temporal history")
	level.queue_free()
	for i in 3:
		await process_frame
	print("PASS: settings apply live; unchanged cloud quality preserves GPU buffers and pipeline")
	quit()
