extends RefCounted
class_name SettingsManager

const CONFIG_PATH := "user://settings.cfg"

static func load_settings(path: String = CONFIG_PATH) -> Dictionary:
	var config := ConfigFile.new()
	var err := config.load(path)
	var settings := {
		"master_volume": 1.0,
		"music_volume": 0.8,
		"sfx_volume": 0.9,
		"fullscreen": false,
		"vsync": true
	}
	if err == OK:
		settings["master_volume"] = config.get_value("audio", "master_volume", 1.0)
		settings["music_volume"] = config.get_value("audio", "music_volume", 0.8)
		settings["sfx_volume"] = config.get_value("audio", "sfx_volume", 0.9)
		settings["fullscreen"] = config.get_value("display", "fullscreen", false)
		settings["vsync"] = config.get_value("display", "vsync", true)
	for key in ["master_volume", "music_volume", "sfx_volume"]:
		var value = settings[key]
		settings[key] = clampf(float(value), 0.0, 1.0) if (value is float or value is int) and is_finite(float(value)) else 1.0
	for key in ["fullscreen", "vsync"]:
		if not settings[key] is bool:
			settings[key] = key == "vsync"
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
	config.set_value("display", "vsync", settings.get("vsync", true))
	return config.save(path)

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

	# Preserve maximized windows when only changing an audio slider.
	if DisplayServer.get_name() == "headless":
		return
	var is_fullscreen: bool = bool(settings.get("fullscreen", false))
	var mode := DisplayServer.window_get_mode()
	var currently_fullscreen := mode in [DisplayServer.WINDOW_MODE_FULLSCREEN, DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN]
	if is_fullscreen != currently_fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if is_fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)

	var vsync: bool = bool(settings.get("vsync", true))
	if vsync:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	else:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
