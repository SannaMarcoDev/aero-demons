extends SceneTree
## Godot --path . --script tests/ui/settings_apply_check.gd  (needs a real GPU context)
## Verifies SettingsManager.apply_settings actually drives the scene nodes.

const Settings = preload("res://scripts/core/settings_manager.gd")

func _initialize() -> void:
	call_deferred("check")

func check() -> void:
	var level = load("res://scenes/levels/freeroam.tscn").instantiate()
	root.add_child(level)
	for i in 10:
		await process_frame
	var sky: Sky3D = level.get_node("GardaLake/Sky3D")
	var env: Environment = sky.environment

	var s := Settings.load_settings()
	s.quality_preset = Settings.QUALITY_CUSTOM
	s.shadows = Settings.SHADOWS_OFF
	s.ssao = true
	s.glow = true
	s.tonemap = Settings.TONEMAP_FILMIC
	s.exposure = 1.5
	s.sky_cirrus = false
	s.sky_cumulus = true
	s.sky_fog = true
	s.render_scale = 0.67
	s.upscaler = Settings.UPSCALER_FSR
	s.fsr_sharpness = 0.6
	Settings.apply_settings(s)
	for i in 10:
		await process_frame
	assert(not sky.sun.shadow_enabled, "shadows OFF must disable sun shadows")
	assert(env.ssao_enabled and env.glow_enabled)
	assert(env.tonemap_mode == Environment.TONE_MAPPER_FILMIC)
	assert(is_equal_approx(env.tonemap_exposure, 1.5))
	assert(not sky.sky.cirrus_visible and sky.sky.cumulus_visible)
	assert(sky.fog_enabled and sky.sky.fog_visible)
	assert(root.scaling_3d_mode == Viewport.SCALING_3D_MODE_FSR)
	assert(is_equal_approx(root.scaling_3d_scale, 0.67))
	assert(is_equal_approx(root.fsr_sharpness, 0.6))

	s.shadows = Settings.SHADOWS_ULTRA
	s.ssao = false
	s.upscaler = Settings.UPSCALER_FSR2
	s.render_scale = 1.25
	Settings.apply_settings(s)
	for i in 10:
		await process_frame
	assert(sky.sun.shadow_enabled and sky.sun.directional_shadow_max_distance == 8000.0)
	assert(is_equal_approx(root.scaling_3d_scale, 1.0), "FSR2 clamps supersampling")
	assert(not env.ssao_enabled)

	level.queue_free()
	for i in 3:
		await process_frame
	print("PASS: settings apply live")
	quit()
