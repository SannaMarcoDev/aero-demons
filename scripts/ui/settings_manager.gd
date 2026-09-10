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

const FPS_LIMITS: Array[int] = [0, 30, 60, 120, 144, 240]
const RENDER_SCALES: Array[float] = [1.0, 0.77, 0.67, 0.59, 0.5]
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
		"upscaler": UPSCALER_OFF,
		"render_scale": 1.0,
		"aa_mode": AA_FXAA,
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
		settings["upscaler"] = config.get_value("rendering", "upscaler", UPSCALER_OFF)
		settings["render_scale"] = config.get_value("rendering", "render_scale", 1.0)
		settings["aa_mode"] = config.get_value("rendering", "aa_mode", AA_FXAA)
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
	config.set_value("rendering", "upscaler", settings.get("upscaler", UPSCALER_OFF))
	config.set_value("rendering", "render_scale", settings.get("render_scale", 1.0))
	config.set_value("rendering", "aa_mode", settings.get("aa_mode", AA_FXAA))
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
	var scale := clampf(float(settings.get("render_scale", 1.0)), 0.4, 1.0)
	if scaling_mode != Viewport.SCALING_3D_MODE_BILINEAR and root.scaling_3d_scale > 1.0:
		root.scaling_3d_scale = 1.0
	root.scaling_3d_mode = scaling_mode
	root.scaling_3d_scale = scale
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
