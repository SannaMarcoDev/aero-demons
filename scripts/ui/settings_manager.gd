extends RefCounted
class_name SettingsManager

const CONFIG_PATH := "user://settings.cfg"

const WINDOW_MODE_WINDOWED := 0
const WINDOW_MODE_BORDERLESS := 1
const WINDOW_MODE_EXCLUSIVE := 2
const WINDOW_MODE_COUNT := 3

const UPSCALER_OFF := 0
const UPSCALER_FSR := 1
const UPSCALER_FSR2 := 2
const UPSCALER_COUNT := 3

const AA_OFF := 0
const AA_FXAA := 1
const AA_TAA := 2
const AA_COUNT := 3

const QUALITY_CUSTOM := 0
const QUALITY_LOW := 1
const QUALITY_MEDIUM := 2
const QUALITY_HIGH := 3
const QUALITY_ULTRA := 4
const QUALITY_COUNT := 5

const CLOUDS_OFF := 0
const CLOUDS_LOW := 1
const CLOUDS_MEDIUM := 2
const CLOUDS_HIGH := 3
const CLOUDS_ULTRA := 4
const CLOUDS_COUNT := 5

const SHADOWS_OFF := 0
const SHADOWS_LOW := 1
const SHADOWS_MEDIUM := 2
const SHADOWS_HIGH := 3
const SHADOWS_ULTRA := 4
const SHADOWS_COUNT := 5

const TONEMAP_LINEAR := 0
const TONEMAP_REINHARDT := 1
const TONEMAP_FILMIC := 2
const TONEMAP_ACES := 3
const TONEMAP_AGX := 4
const TONEMAP_COUNT := 5

const CLOUDS_RESOURCE_PATH := "res://resources/environments/tutorial_clouds.tres"
const GRAPHICS_CFG_PATH := "user://graphics.cfg"

const FPS_LIMITS: Array[int] = [0, 30, 60, 120, 144, 240]
const RENDER_SCALES: Array[float] = [0.5, 0.59, 0.67, 0.77, 1.0, 1.25, 1.5]

## SunshineClouds raymarch budgets per quality step (index = CLOUDS_*). ULTRA matches
## the authored tutorial_clouds.tres; OFF only flips the compositor effect's enabled flag.
const CLOUD_PRESETS: Array[Dictionary] = [
	{},
	{"res": 3, "steps": 128.0, "light_steps": 8.0, "lod": 1.6, "blur_q": 1.0, "blur_p": 1.2, "travel": 1500.0, "accum": 0.75, "min_d": 60.0, "max_d": 160.0, "sun_steps": 6},
	{"res": 2, "steps": 256.0, "light_steps": 12.0, "lod": 1.3, "blur_q": 1.5, "blur_p": 1.4, "travel": 2000.0, "accum": 0.8, "min_d": 55.0, "max_d": 150.0, "sun_steps": 12},
	{"res": 1, "steps": 384.0, "light_steps": 20.0, "lod": 1.0, "blur_q": 2.0, "blur_p": 1.65, "travel": 2500.0, "accum": 0.85, "min_d": 50.0, "max_d": 140.0, "sun_steps": 20},
	{"res": 0, "steps": 700.0, "light_steps": 32.0, "lod": 0.9, "blur_q": 2.0, "blur_p": 1.65, "travel": 3000.0, "accum": 0.85, "min_d": 50.0, "max_d": 140.0, "sun_steps": 32},
]

## Directional shadow presets (index = SHADOWS_*): PSSM split count and reach.
const SHADOW_PRESETS: Array[Dictionary] = [
	{"enabled": false},
	{"enabled": true, "mode": DirectionalLight3D.SHADOW_ORTHOGONAL, "distance": 1500.0},
	{"enabled": true, "mode": DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS, "distance": 2500.0},
	{"enabled": true, "mode": DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS, "distance": 4000.0},
	{"enabled": true, "mode": DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS, "distance": 8000.0},
]

## Master presets (index = QUALITY_*). Only these keys are overridden; resolution,
## upscaler, AA, coverage, tonemap and exposure stay user-controlled. CUSTOM forces nothing.
const QUALITY_PRESETS: Array[Dictionary] = [
	{},
	{"clouds_quality": CLOUDS_OFF, "shadows": SHADOWS_OFF, "ssao": false, "ssil": false, "ssr": false, "glow": false, "volumetric_fog": false, "sky_cirrus": true, "sky_cumulus": false, "sky_fog": false},
	{"clouds_quality": CLOUDS_MEDIUM, "shadows": SHADOWS_LOW, "ssao": false, "ssil": false, "ssr": false, "glow": false, "volumetric_fog": false, "sky_cirrus": true, "sky_cumulus": false, "sky_fog": false},
	{"clouds_quality": CLOUDS_HIGH, "shadows": SHADOWS_HIGH, "ssao": true, "ssil": false, "ssr": false, "glow": false, "volumetric_fog": false, "sky_cirrus": true, "sky_cumulus": false, "sky_fog": false},
	{"clouds_quality": CLOUDS_ULTRA, "shadows": SHADOWS_ULTRA, "ssao": true, "ssil": false, "ssr": false, "glow": true, "volumetric_fog": false, "sky_cirrus": true, "sky_cumulus": false, "sky_fog": false},
]
const RESOLUTIONS: Array[Vector2i] = [
	Vector2i(1280, 720),
	Vector2i(1600, 900),
	Vector2i(1920, 1080),
	Vector2i(2560, 1440),
	Vector2i(3840, 2160),
]

# Read live by PlayerFlight/FollowCamera; populated by apply_settings/ensure_controls_loaded.
static var controls_invert_y := false
static var controls_sensitivity := 1.0
static var _controls_loaded := false


static func load_settings(path: String = CONFIG_PATH) -> Dictionary:
	var config := ConfigFile.new()
	var err := config.load(path)
	var settings := {
		"master_volume": 1.0,
		"music_volume": 0.8,
		"sfx_volume": 0.9,
		"fullscreen": false,
		"window_mode": WINDOW_MODE_WINDOWED,
		"resolution": "1920x1080",
		"vsync": true,
		"fps_limit": 0,
		"upscaler": UPSCALER_FSR2,
		"render_scale": 1.0,
		"aa_mode": AA_FXAA,
		"fsr_sharpness": 0.2,
		"quality_preset": QUALITY_ULTRA,
		"clouds_quality": CLOUDS_ULTRA,
		"clouds_coverage": 0.834,
		"sky_cirrus": true,
		"sky_cumulus": false,
		"sky_fog": false,
		"shadows": SHADOWS_HIGH,
		"ssao": false,
		"ssil": false,
		"ssr": false,
		"glow": false,
		"volumetric_fog": false,
		"tonemap": TONEMAP_ACES,
		"exposure": 1.0,
		"controls_invert_y": false,
		"controls_sensitivity": 1.0,
	}
	if err == OK:
		settings["master_volume"] = config.get_value("audio", "master_volume", 1.0)
		settings["music_volume"] = config.get_value("audio", "music_volume", 0.8)
		settings["sfx_volume"] = config.get_value("audio", "sfx_volume", 0.9)
		var legacy_fullscreen = config.get_value("display", "fullscreen", false)
		var stored_mode = config.get_value("display", "window_mode", -1)
		if (stored_mode is int or stored_mode is float) and int(stored_mode) >= 0:
			settings["window_mode"] = int(stored_mode)
		elif legacy_fullscreen is bool:
			settings["window_mode"] = WINDOW_MODE_BORDERLESS if legacy_fullscreen else WINDOW_MODE_WINDOWED
		settings["resolution"] = config.get_value("display", "resolution", "1920x1080")
		settings["vsync"] = config.get_value("display", "vsync", true)
		settings["fps_limit"] = config.get_value("display", "fps_limit", 0)
		settings["upscaler"] = config.get_value("rendering", "upscaler", UPSCALER_FSR2)
		settings["render_scale"] = config.get_value("rendering", "render_scale", 1.0)
		settings["aa_mode"] = config.get_value("rendering", "aa_mode", AA_FXAA)
		settings["fsr_sharpness"] = config.get_value("rendering", "fsr_sharpness", 0.2)
		settings["quality_preset"] = config.get_value("rendering", "quality_preset", QUALITY_ULTRA)
		settings["clouds_quality"] = config.get_value("clouds", "quality", CLOUDS_ULTRA)
		settings["clouds_coverage"] = config.get_value("clouds", "coverage", 0.834)
		settings["sky_cirrus"] = config.get_value("sky", "cirrus", true)
		settings["sky_cumulus"] = config.get_value("sky", "cumulus", false)
		settings["sky_fog"] = config.get_value("sky", "fog", false)
		settings["shadows"] = config.get_value("shadows", "quality", SHADOWS_HIGH)
		settings["ssao"] = config.get_value("effects", "ssao", false)
		settings["ssil"] = config.get_value("effects", "ssil", false)
		settings["ssr"] = config.get_value("effects", "ssr", false)
		settings["glow"] = config.get_value("effects", "glow", false)
		settings["volumetric_fog"] = config.get_value("effects", "volumetric_fog", false)
		settings["tonemap"] = config.get_value("effects", "tonemap", TONEMAP_ACES)
		settings["exposure"] = config.get_value("effects", "exposure", 1.0)
		settings["controls_invert_y"] = config.get_value("controls", "invert_y", false)
		settings["controls_sensitivity"] = config.get_value("controls", "sensitivity", 1.0)
	for key in ["master_volume", "music_volume", "sfx_volume"]:
		var value = settings[key]
		settings[key] = clampf(float(value), 0.0, 1.0) if (value is float or value is int) and is_finite(float(value)) else 1.0
	var mode_value = settings["window_mode"]
	settings["window_mode"] = clampi(int(mode_value), 0, WINDOW_MODE_COUNT - 1) if mode_value is int or mode_value is float else WINDOW_MODE_WINDOWED
	settings["fullscreen"] = settings["window_mode"] != WINDOW_MODE_WINDOWED
	settings["resolution"] = resolution_to_string(parse_resolution(str(settings["resolution"])))
	for key in ["vsync"]:
		if not settings[key] is bool:
			settings[key] = true
	var upscaler_value = settings["upscaler"]
	settings["upscaler"] = clampi(int(upscaler_value), 0, UPSCALER_COUNT - 1) if upscaler_value is int or upscaler_value is float else UPSCALER_OFF
	var aa_value = settings["aa_mode"]
	settings["aa_mode"] = clampi(int(aa_value), 0, AA_COUNT - 1) if aa_value is int or aa_value is float else AA_FXAA
	settings["fps_limit"] = _nearest_fps_limit(settings["fps_limit"])
	settings["render_scale"] = _nearest_render_scale(settings["render_scale"])
	var sharpness = settings["fsr_sharpness"]
	settings["fsr_sharpness"] = clampf(float(sharpness), 0.0, 2.0) if sharpness is float or sharpness is int else 0.2
	settings["quality_preset"] = _clamp_enum(settings["quality_preset"], QUALITY_COUNT, QUALITY_ULTRA)
	settings["clouds_quality"] = _clamp_enum(settings["clouds_quality"], CLOUDS_COUNT, CLOUDS_ULTRA)
	settings["shadows"] = _clamp_enum(settings["shadows"], SHADOWS_COUNT, SHADOWS_HIGH)
	settings["tonemap"] = _clamp_enum(settings["tonemap"], TONEMAP_COUNT, TONEMAP_ACES)
	var coverage = settings["clouds_coverage"]
	settings["clouds_coverage"] = clampf(float(coverage), 0.0, 1.0) if coverage is float or coverage is int else 0.834
	var exposure = settings["exposure"]
	settings["exposure"] = clampf(float(exposure), 0.25, 4.0) if exposure is float or exposure is int else 1.0
	if not settings["sky_cirrus"] is bool:
		settings["sky_cirrus"] = true
	for key in ["sky_cumulus", "sky_fog", "ssao", "ssil", "ssr", "glow", "volumetric_fog"]:
		if not settings[key] is bool:
			settings[key] = false
	if not settings["controls_invert_y"] is bool:
		settings["controls_invert_y"] = false
	var sensitivity = settings["controls_sensitivity"]
	settings["controls_sensitivity"] = clampf(float(sensitivity), 0.5, 2.0) if sensitivity is float or sensitivity is int else 1.0
	return settings


static func save_settings(settings: Dictionary, path: String = CONFIG_PATH) -> Error:
	var config := ConfigFile.new()
	var error := config.load(path)
	if error != OK and error != ERR_FILE_NOT_FOUND:
		return error
	config.set_value("audio", "master_volume", settings.get("master_volume", 1.0))
	config.set_value("audio", "music_volume", settings.get("music_volume", 0.8))
	config.set_value("audio", "sfx_volume", settings.get("sfx_volume", 0.9))
	config.set_value("display", "fullscreen", settings.get("fullscreen", false))
	config.set_value("display", "window_mode", settings.get("window_mode", WINDOW_MODE_WINDOWED))
	config.set_value("display", "resolution", settings.get("resolution", "1920x1080"))
	config.set_value("display", "vsync", settings.get("vsync", true))
	config.set_value("display", "fps_limit", settings.get("fps_limit", 0))
	config.set_value("rendering", "upscaler", settings.get("upscaler", UPSCALER_FSR2))
	config.set_value("rendering", "render_scale", settings.get("render_scale", 1.0))
	config.set_value("rendering", "aa_mode", settings.get("aa_mode", AA_FXAA))
	config.set_value("rendering", "fsr_sharpness", settings.get("fsr_sharpness", 0.2))
	config.set_value("rendering", "quality_preset", settings.get("quality_preset", QUALITY_ULTRA))
	config.set_value("clouds", "quality", settings.get("clouds_quality", CLOUDS_ULTRA))
	config.set_value("clouds", "coverage", settings.get("clouds_coverage", 0.834))
	config.set_value("sky", "cirrus", settings.get("sky_cirrus", true))
	config.set_value("sky", "cumulus", settings.get("sky_cumulus", false))
	config.set_value("sky", "fog", settings.get("sky_fog", false))
	config.set_value("shadows", "quality", settings.get("shadows", SHADOWS_HIGH))
	config.set_value("effects", "ssao", settings.get("ssao", false))
	config.set_value("effects", "ssil", settings.get("ssil", false))
	config.set_value("effects", "ssr", settings.get("ssr", false))
	config.set_value("effects", "glow", settings.get("glow", false))
	config.set_value("effects", "volumetric_fog", settings.get("volumetric_fog", false))
	config.set_value("effects", "tonemap", settings.get("tonemap", TONEMAP_ACES))
	config.set_value("effects", "exposure", settings.get("exposure", 1.0))
	config.set_value("controls", "invert_y", settings.get("controls_invert_y", false))
	config.set_value("controls", "sensitivity", settings.get("controls_sensitivity", 1.0))
	return config.save(path)


static func parse_resolution(text: String) -> Vector2i:
	var parts := text.split("x")
	if parts.size() == 2 and parts[0].is_valid_int() and parts[1].is_valid_int():
		var size := Vector2i(parts[0].to_int(), parts[1].to_int())
		if size.x >= 640 and size.y >= 360:
			return size
	return Vector2i(1920, 1080)


static func resolution_to_string(size: Vector2i) -> String:
	return "%dx%d" % [size.x, size.y]


## Populates the live control settings without touching display or audio state. Skipped in
## headless runs so scripted checks always see the default flight model.
static func ensure_controls_loaded() -> void:
	if _controls_loaded or DisplayServer.get_name() == "headless":
		return
	_controls_loaded = true
	var settings := load_settings()
	controls_invert_y = bool(settings.get("controls_invert_y", false))
	controls_sensitivity = float(settings.get("controls_sensitivity", 1.0))


static func apply_settings(settings: Dictionary) -> void:
	# Audio buses
	var master_idx := AudioServer.get_bus_index(&"Master")
	if master_idx >= 0:
		var mv: float = float(settings.get("master_volume", 1.0))
		AudioServer.set_bus_volume_db(master_idx, linear_to_db(maxf(mv, 0.0001)))
		AudioServer.set_bus_mute(master_idx, mv <= 0.001)

	var music_idx := AudioServer.get_bus_index(&"Music")
	if music_idx >= 0:
		var mus: float = float(settings.get("music_volume", 0.8))
		AudioServer.set_bus_volume_db(music_idx, linear_to_db(maxf(mus, 0.0001)))
		AudioServer.set_bus_mute(music_idx, mus <= 0.001)

	var sfx_idx := AudioServer.get_bus_index(&"SFX")
	if sfx_idx >= 0:
		var sfx: float = float(settings.get("sfx_volume", 0.9))
		AudioServer.set_bus_volume_db(sfx_idx, linear_to_db(maxf(sfx, 0.0001)))
		AudioServer.set_bus_mute(sfx_idx, sfx <= 0.001)

	controls_invert_y = bool(settings.get("controls_invert_y", false))
	controls_sensitivity = float(settings.get("controls_sensitivity", 1.0))
	_controls_loaded = true
	Engine.max_fps = maxi(int(settings.get("fps_limit", 0)), 0)

	# Preserve maximized windows when only changing an audio slider.
	if DisplayServer.get_name() == "headless":
		return

	var tree := Engine.get_main_loop() as SceneTree
	if tree != null and tree.root != null:
		_apply_rendering(tree.root, settings)
		_apply_scene_quality(tree.root, settings)
	_apply_window(settings)

	var vsync: bool = bool(settings.get("vsync", true))
	if vsync:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	else:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)


static func _apply_rendering(root: Viewport, settings: Dictionary) -> void:
	var upscaler := int(settings.get("upscaler", UPSCALER_OFF))
	var scaling_mode := Viewport.SCALING_3D_MODE_BILINEAR
	if upscaler == UPSCALER_FSR:
		scaling_mode = Viewport.SCALING_3D_MODE_FSR
	elif upscaler == UPSCALER_FSR2:
		scaling_mode = Viewport.SCALING_3D_MODE_FSR2
	# FSR modes only accept scale <= 1.0; leave supersampling before switching algorithm.
	var scale := clampf(float(settings.get("render_scale", 1.0)), 0.4, 2.0)
	if scaling_mode != Viewport.SCALING_3D_MODE_BILINEAR:
		scale = minf(scale, 1.0)
	if scaling_mode != Viewport.SCALING_3D_MODE_BILINEAR and root.scaling_3d_scale > 1.0:
		root.scaling_3d_scale = 1.0
	root.scaling_3d_mode = scaling_mode
	root.scaling_3d_scale = scale
	root.fsr_sharpness = clampf(float(settings.get("fsr_sharpness", 0.2)), 0.0, 2.0)
	# MSAA is deliberately not exposed: switching it at runtime caused D3D12 device loss
	# with the SunshineClouds pipeline (see freeroam_filter_toggle.gd).
	match int(settings.get("aa_mode", AA_FXAA)):
		AA_TAA:
			root.use_taa = true
			root.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
		AA_FXAA:
			root.use_taa = false
			root.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
		_:
			root.use_taa = false
			root.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED


static func _apply_window(settings: Dictionary) -> void:
	var desired := int(settings.get("window_mode", WINDOW_MODE_WINDOWED))
	var want_borderless := desired == WINDOW_MODE_BORDERLESS
	if DisplayServer.window_get_flag(DisplayServer.WINDOW_FLAG_BORDERLESS) != want_borderless:
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, want_borderless)
	var target_mode := DisplayServer.WINDOW_MODE_WINDOWED
	if desired == WINDOW_MODE_BORDERLESS:
		target_mode = DisplayServer.WINDOW_MODE_FULLSCREEN
	elif desired == WINDOW_MODE_EXCLUSIVE:
		target_mode = DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
	if DisplayServer.window_get_mode() != target_mode:
		DisplayServer.window_set_mode(target_mode)
	if desired != WINDOW_MODE_WINDOWED:
		return
	var resolution := parse_resolution(str(settings.get("resolution", "1920x1080")))
	if DisplayServer.window_get_size() != resolution:
		DisplayServer.window_set_size(resolution)
		var screen := DisplayServer.window_get_current_screen()
		var centered := DisplayServer.screen_get_position(screen) \
			+ (DisplayServer.screen_get_size(screen) - resolution) / 2
		DisplayServer.window_set_position(centered)


## Applies scene-level quality: the shared SunshineClouds resource plus any Sky3D,
## SkyDome, WorldEnvironment and SunLight nodes currently in the tree. Safe in the
## main menu (finds nothing); the level HUD reapplies everything once the map exists.
static func _apply_scene_quality(root: Viewport, settings: Dictionary) -> void:
	_apply_clouds(root, settings)
	_apply_sky(root, settings)
	_apply_shadows(root, settings)
	_apply_environment(root, settings)


static func _apply_clouds(root: Viewport, settings: Dictionary) -> void:
	# The .tres is shared (not local_to_scene): runtime edits carry into every
	# scene that instances it, and benchmarks run in separate processes.
	var clouds: SunshineCloudsGD = ResourceLoader.load(CLOUDS_RESOURCE_PATH)
	if clouds == null:
		return
	var quality := clampi(int(settings.get("clouds_quality", CLOUDS_ULTRA)), 0, CLOUDS_COUNT - 1)
	clouds.enabled = quality != CLOUDS_OFF
	var sun_steps := 32
	if quality != CLOUDS_OFF:
		var p: Dictionary = CLOUD_PRESETS[quality]
		clouds.resolution_scale = int(p["res"])
		clouds.max_step_count = float(p["steps"])
		clouds.max_lighting_steps = float(p["light_steps"])
		clouds.lod_bias = float(p["lod"])
		clouds.blur_quality = float(p["blur_q"])
		clouds.blur_power = float(p["blur_p"])
		clouds.lighting_travel_distance = float(p["travel"])
		clouds.accumulation_decay = float(p["accum"])
		clouds.min_step_distance = float(p["min_d"])
		clouds.max_step_distance = float(p["max_d"])
		sun_steps = int(p["sun_steps"])
	clouds.clouds_coverage = clampf(float(settings.get("clouds_coverage", 0.834)), 0.0, 1.0)
	for node in root.find_children("*", "SunshineCloudsDriverGD", true, false):
		var steps: Array[int] = []
		steps.resize(node.tracked_directional_lights.size())
		steps.fill(sun_steps)
		node.tracked_directional_light_shadow_steps = steps


static func _apply_sky(root: Viewport, settings: Dictionary) -> void:
	for node in root.find_children("*", "Sky3D", true, false):
		var sky: Sky3D = node
		sky.fog_enabled = bool(settings.get("sky_fog", false))
		if sky.sky != null:
			sky.sky.cirrus_visible = bool(settings.get("sky_cirrus", true))
			sky.sky.cumulus_visible = bool(settings.get("sky_cumulus", false))


static func _apply_shadows(root: Viewport, settings: Dictionary) -> void:
	var preset: Dictionary = SHADOW_PRESETS[clampi(int(settings.get("shadows", SHADOWS_HIGH)), 0, SHADOWS_COUNT - 1)]
	for node in root.find_children("*", "Sky3D", true, false):
		var sun: DirectionalLight3D = (node as Sky3D).sun
		if sun == null:
			continue
		sun.shadow_enabled = bool(preset["enabled"])
		if preset["enabled"]:
			sun.directional_shadow_mode = int(preset["mode"])
			sun.directional_shadow_max_distance = float(preset["distance"])


static func _apply_environment(root: Viewport, settings: Dictionary) -> void:
	for node in root.find_children("*", "WorldEnvironment", true, false):
		var env: Environment = (node as WorldEnvironment).environment
		if env == null:
			continue
		env.ssao_enabled = bool(settings.get("ssao", false))
		env.ssil_enabled = bool(settings.get("ssil", false))
		env.ssr_enabled = bool(settings.get("ssr", false))
		env.glow_enabled = bool(settings.get("glow", false))
		var volumetric := bool(settings.get("volumetric_fog", false))
		env.volumetric_fog_enabled = volumetric
		if volumetric:
			env.volumetric_fog_density = 0.0008
			env.volumetric_fog_length = 2000.0
		env.tonemap_mode = clampi(int(settings.get("tonemap", TONEMAP_ACES)), 0, TONEMAP_COUNT - 1)
		env.tonemap_exposure = clampf(float(settings.get("exposure", 1.0)), 0.25, 4.0)


static func _clamp_enum(value, count: int, fallback: int) -> int:
	return clampi(int(value), 0, count - 1) if value is int or value is float else fallback


static func _nearest_fps_limit(value) -> int:
	var fps := int(value) if value is int or value is float else 0
	var best: int = FPS_LIMITS[0]
	var best_distance := absi(fps - best)
	for candidate in FPS_LIMITS:
		var distance := absi(fps - candidate)
		if distance < best_distance:
			best = candidate
			best_distance = distance
	return best


static func _nearest_render_scale(value) -> float:
	var scale := float(value) if value is float or value is int else 1.0
	var best: float = RENDER_SCALES[0]
	var best_distance := absf(scale - best)
	for candidate in RENDER_SCALES:
		var distance := absf(scale - candidate)
		if distance < best_distance:
			best = candidate
			best_distance = distance
	return best
