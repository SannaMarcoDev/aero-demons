extends Node3D
## Player-facing, repeatable 1080p Ultra Garda benchmark. Never saves user settings.
const Session = preload("res://scripts/ui/game_session.gd")
const Settings = preload("res://scripts/ui/settings_manager.gd")
const Sampler = preload("res://tools/benchmark_sampler.gd")

@onready var progress_label: Label = $Overlay/Progress
@onready var result_panel: CenterContainer = $Overlay/ResultPanel
@onready var result_label: Label = $Overlay/ResultPanel/Panel/VBox/Result
@onready var detail_label: Label = $Overlay/ResultPanel/Panel/VBox/Detail
@onready var menu_button: Button = $Overlay/ResultPanel/Panel/VBox/MenuButton

var _saved_settings: Dictionary
var _content_scale_size: Vector2i
var _level: Node3D
var _running := true


func _ready() -> void:
	_saved_settings = Settings.load_settings()
	_content_scale_size = get_tree().root.content_scale_size
	menu_button.pressed.connect(_return_to_menu)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		_show_result("Serve una finestra grafica per il benchmark.", "")
		return
	if DisplayServer.screen_get_size(DisplayServer.window_get_current_screen()).x < 1920 \
			or DisplayServer.screen_get_size(DisplayServer.window_get_current_screen()).y < 1080:
		_show_result("Serve uno schermo di almeno 1920×1080 per un confronto valido.", "")
		return
	progress_label.text = "BENCHMARK  •  CARICAMENTO SCENARIO GARDA"
	_level = load(Session.FREE_FLIGHT).instantiate()
	add_child(_level)
	var player: Node3D = _level.get_node("Player")
	var camera: Camera3D = player.get_node("FlightCamera")
	var forest: Node = _level.get_node("GardaLake/Forests")
	var driver: Node = _level.get_node("GardaLake/SunshineCloudsDriverGD")
	player.set_physics_process(false)
	_level.get_node("GardaLake/TutorialBoundaryController").set_physics_process(false)
	driver.set_process(false)
	driver.retrieve_texture_data()
	_level.get_node("GardaLake/Sky3D/SkyDome").process_method = 2
	_level.set_process_unhandled_input(false) # Disable the level's F6 filter toggle.
	_level.label.hide()
	var horizon = _level.get_node("HorizonGraphics")
	horizon.apply_blur(false)
	horizon.label.hide()
	horizon.set_process_unhandled_input(false) # F7 otherwise writes user://graphics.cfg.
	_level.get_node("CombatHUD").set_process_unhandled_input(false) # No pause/options during capture.
	var settings := _saved_settings.duplicate(true)
	settings.merge(Settings.QUALITY_PRESETS[Settings.QUALITY_ULTRA], true)
	settings.merge({"quality_preset": Settings.QUALITY_ULTRA, "resolution": "1920x1080",
		"window_mode": Settings.WINDOW_MODE_WINDOWED, "vsync": false, "fps_limit": 0,
		"render_scale": 1.0, "upscaler": Settings.UPSCALER_OFF, "aa_mode": Settings.AA_TAA,
		"clouds_coverage": 0.834, "tonemap": Settings.TONEMAP_ACES, "exposure": 1.0}, true)
	Settings.apply_settings(settings)
	var viewport := get_tree().root
	viewport.size = Vector2i(1920, 1080)
	viewport.content_scale_size = viewport.size
	RenderingServer.viewport_set_measure_render_time(viewport.get_viewport_rid(), true)
	Sampler.place_aircraft(player, camera, Sampler.GARDA_LOCATIONS[0], 0.0)
	while not forest.built:
		await get_tree().process_frame
	await get_tree().create_timer(8.0).timeout
	var passes: Array[Dictionary] = []
	var results: Array[Dictionary] = []
	var all_frames: Array[float] = []
	for round_index in 3:
		var frame_count := 0
		var elapsed_ms := 0.0
		for loc in Sampler.GARDA_LOCATIONS:
			progress_label.text = "BENCHMARK  •  PASSAGGIO %d/3  •  %s" % [round_index + 1, loc.id.to_upper()]
			var result: Dictionary = await Sampler.measure(get_tree(), viewport, player, camera, forest, loc, 3.5, 6.0)
			result["location"] = loc.id
			result["round"] = round_index + 1
			frame_count += int(result["frames"])
			elapsed_ms += float(result["elapsed_ms"])
			all_frames.append_array(result["frame_times_ms"])
			result.erase("frame_times_ms")
			results.append(result)
		passes.append({"round": round_index + 1, "fps": frame_count * 1000.0 / elapsed_ms})
	var pass_fps: Array[float] = []
	for pass_result in passes:
		pass_fps.append(pass_result.fps)
	pass_fps.sort()
	var average_fps := pass_fps[1] # Median of three equally weighted, six-view passes.
	all_frames.sort()
	var slow_count := maxi(1, ceili(all_frames.size() * 0.01))
	var slow_ms := 0.0
	for index in range(all_frames.size() - slow_count, all_frames.size()):
		slow_ms += all_frames[index]
	var low_fps := slow_count * 1000.0 / slow_ms
	var score := roundi(average_fps * 1000.0 / 60.0)
	var graphics_settings := settings.duplicate()
	for key in ["master_volume", "music_volume", "sfx_volume", "controls_invert_y",
			"controls_sensitivity", "controls_bindings", "fullscreen"]:
		graphics_settings.erase(key)
	var folder := "user://benchmarks"
	var error := DirAccess.make_dir_recursive_absolute(folder)
	var path := folder.path_join(Time.get_datetime_string_from_system().replace(":", "-") + ".json")
	var file := FileAccess.open(path, FileAccess.WRITE) if error == OK else null
	var save_error := FileAccess.get_open_error() if error == OK else error
	if file != null:
		file.store_string(JSON.stringify({"score": score, "average_fps": average_fps,
			"one_percent_low_fps": low_fps, "score_reference": "1000 points = 60 average FPS",
			"method": "median of 3 six-view passes; 1% low = inverse of mean slowest 1% frame times",
			"scene": Session.FREE_FLIGHT, "preset": "Ultra / 1920x1080 / native TAA / uncapped / V-Sync off",
			"settings": graphics_settings, "godot": Engine.get_version_info().string,
			"editor_binary": OS.has_feature("editor"), "debug_build": OS.is_debug_build(),
			"os": OS.get_name(), "cpu": OS.get_processor_name(),
			"gpu": RenderingServer.get_video_adapter_name(),
			"renderer": RenderingServer.get_current_rendering_method(),
			"driver": RenderingServer.get_current_rendering_driver_name(),
			"passes": passes, "results": results}, "\t"))
		file.flush()
		save_error = file.get_error()
		file.close()
		if save_error != OK:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
			file = null
	await _cleanup()
	var detail := "1000 PUNTI = 60 FPS  •  1080p ULTRA  •  3 PASSAGGI\n%s" % (
			"Risultato salvato: %s" % ProjectSettings.globalize_path(path) if file != null else "Impossibile salvare il JSON: %s" % error_string(save_error))
	if OS.is_debug_build() or OS.has_feature("editor"):
		detail += "\nBuild di debug/editor: confronta solo risultati ottenuti con la stessa build."
	_show_result("SCORE  %d\nFPS MEDI  %.1f\n1%% LOW  %.1f FPS" % [score, average_fps, low_fps], detail)


func _cleanup() -> void:
	if _level != null:
		_level.queue_free()
		_level = null
		await get_tree().process_frame
	RenderingServer.viewport_set_measure_render_time(get_tree().root.get_viewport_rid(), false)
	get_tree().root.content_scale_size = _content_scale_size
	Settings.apply_settings(_saved_settings)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _show_result(message: String, detail: String) -> void:
	_running = false
	$Overlay/Background.show()
	progress_label.hide()
	result_label.text = message
	detail_label.text = detail
	result_panel.show()
	menu_button.grab_focus()


func _return_to_menu() -> void:
	if Session.change_scene(get_tree(), Session.MAIN_MENU) != OK:
		detail_label.text = "Impossibile tornare al menu."


func _unhandled_input(event: InputEvent) -> void:
	if _running and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
	elif not _running and event.is_action_pressed("ui_cancel"):
		_return_to_menu()
		get_viewport().set_input_as_handled()
