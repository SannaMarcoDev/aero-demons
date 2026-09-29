extends Node3D
## Replay theatre. Time belongs to the recording, not to the gameplay simulation.
const Data = preload("res://scripts/replay/replay_data.gd")
const Actor = preload("res://scripts/replay/replay_actor.gd")
const PREROLL := 6.0 # Longest current world-space particle lifetime is 5.2 seconds.

var data: Dictionary = {}
var file_path := ""
var time := 0.0
var speed := 1.0
var playing := false
var seeking := false
var camera_mode := 1
var target_index := -1
var camera: Camera3D
var _world: Node3D
var _actors: Node3D
var _proxies: Dictionary = {}
var _layer: CanvasLayer
var _controls: PanelContainer
var _library: PanelContainer
var _files: ItemList
var _timeline: HSlider
var _time_label: Label
var _status: Label
var _play: Button
var _mode: OptionButton
var _targets: OptionButton
var _fov: SpinBox
var _record_button: Button
var _save_dialog: FileDialog
var _dragging := false
var _camera_recording := false
var _next_camera_sample := 0.0
var _mouse_look := false
var _fly_speed := 150.0
var _distance := 65.0
var _orbit := Vector2(0.0, 0.15)
var _muted := false
var _exporting := false
var _export_frame := 0
var _export_pid := -1
var _old_music_paused := false
var _old_auto_quit := true
var _shot_dirty := false

func _ready() -> void:
	if "--replay-self-check" in OS.get_cmdline_user_args():
		_run_self_check.call_deferred()
		return
	_old_auto_quit = get_tree().auto_accept_quit
	get_tree().auto_accept_quit = false
	camera = Camera3D.new()
	camera.name = "ReplayCamera"
	camera.far = 100000.0
	camera.near = 0.2
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(camera)
	camera.make_current()
	_actors = Node3D.new()
	_actors.name = "VisualActors"
	add_child(_actors)
	_build_ui()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var music = get_node_or_null("/root/AudioManager")
	if music != null and music.get("_music_player") != null:
		_old_music_paused = music._music_player.stream_paused
		music._music_player.stream_paused = true
		music.stop_alarm()
		music._ui_player.stop()
	var requested := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--replay-file="):
			requested = arg.trim_prefix("--replay-file=")
		if arg == "--replay-export":
			_exporting = true
	if requested.is_empty():
		requested = get_node("/root/ReplayRecorder").selected_path
	_refresh_files()
	if not requested.is_empty():
		open_replay(requested)
	if _exporting:
		if data.is_empty() or not OS.has_feature("movie"):
			push_error("Replay export requires a valid recording and --write-movie.")
			get_tree().quit(1)
			return
		camera_mode = 4 if not data.get("shot", []).is_empty() else 3
		_mode.select(camera_mode)
		_layer.hide()
		playing = true
		_update_camera(0.0)
		print("REPLAY_EXPORT_STARTED ", file_path)

func _run_self_check() -> void:
	assert(Engine.max_fps == 30)
	var sample := Data.self_check()
	for track in sample.actors:
		var proxy := Actor.new()
		add_child(proxy)
		proxy.setup(track)
		assert(not proxy.visual.is_processing() and not proxy.visual.is_physics_processing())
		assert(proxy.visual.get_groups().is_empty())
		proxy.render_at(0.5, 0.0, 0.0, false)
		assert(proxy.global_position.is_equal_approx(Vector3(2.5, 0, 0)))
		proxy.reset_effects()
		proxy.render_at(1.5, 0.0, 0.0, false)
		assert(proxy.global_position.is_equal_approx(Vector3(7.5, 0, 0)))
		proxy.free()
	# Exercise the real capture path, including spawn, impact, destruction and audio.
	var live := Node3D.new()
	add_child(live)
	var player := (load(Data.SCENES[0]) as PackedScene).instantiate() as Node3D
	player.position = Vector3(0, 500, 0)
	live.add_child(player)
	player.set("controls_enabled", false)
	var enemy := (load(Data.SCENES[1]) as PackedScene).instantiate() as Node3D
	enemy.position = Vector3(0, 500, -500)
	live.add_child(enemy)
	enemy.set_physics_process(false)
	var recorder := get_node("/root/ReplayRecorder")
	var original_scene_path := scene_file_path
	scene_file_path = Data.LEVELS.keys()[0]
	recorder.start_recording()
	recorder.recording_path = Data.DIRECTORY.path_join(".capture-check-%d.aeroreplay" % Time.get_ticks_usec())
	var missile := (load(Data.SCENES[2]) as PackedScene).instantiate() as Node3D
	live.add_child(missile)
	missile.call("launch", Transform3D(Basis.IDENTITY, enemy.position + Vector3(0, 0, 10)), Vector3(0, 0, -200), enemy)
	player.get_node("WeaponController").call("fire_gun")
	for frame in 40:
		await get_tree().physics_frame
	assert(recorder.stop_recording().is_empty())
	var result := Data.load_file(recorder.recording_path)
	assert(result.has("data"), str(result.get("error", "")))
	var scenes: Array = result.data.actors.map(func(track: Dictionary): return track.scene)
	assert(Data.SCENES[2] in scenes and Data.SCENES[3] in scenes and Data.SCENES[4] in scenes and "audio" in scenes)
	if not "--replay-keep-check" in OS.get_cmdline_user_args():
		assert(DirAccess.remove_absolute(recorder.recording_path) == OK)
	# Restarting a take must reuse exit hooks, not connect them twice.
	recorder.start_recording()
	recorder.recording_path = Data.DIRECTORY.path_join(".restart-check-%d.tmp-replay" % Time.get_ticks_usec())
	assert(recorder.stop_recording().is_empty())
	assert(DirAccess.remove_absolute(recorder.recording_path) == OK)
	scene_file_path = original_scene_path
	live.free()
	for track in result.data.actors:
		var proxy := Actor.new()
		add_child(proxy)
		proxy.setup(track)
		proxy.render_at(lerpf(track.born, track.end, 0.5), 0.0, 0.0, false)
		proxy.free()
	recorder.data.clear()
	recorder.selected_path = ""
	# Exercise the same camera recording/save/interpolation path as the buttons.
	camera = Camera3D.new()
	add_child(camera)
	_actors = Node3D.new()
	add_child(_actors)
	_build_ui()
	data = result.data
	file_path = Data.DIRECTORY.path_join(".shot-check-%d.tmp-replay" % Time.get_ticks_usec())
	camera_mode = 0
	_toggle_camera_recording()
	for frame in 5:
		camera.position.x += 10.0
		_process(0.2)
	assert(not _camera_recording and is_equal_approx(data.shot.back()[0], data.duration))
	assert(data.shot.size() == data.shot_fov.size() and data.shot.size() >= 3)
	assert(_save_shot() and not _shot_dirty)
	var saved_shot := Data.load_file(file_path)
	assert(saved_shot.has("data") and saved_shot.data.shot == data.shot)
	camera_mode = 4
	time = data.duration * 0.5
	_update_camera(0.0)
	assert(camera.global_transform.is_equal_approx(Data.value_at(data.shot, time)))
	target_index = 0
	for mode in [1, 2]:
		camera_mode = mode
		_update_camera(0.0)
		var subject: Vector3 = Data.value_at(data.actors[0].poses, time).origin
		assert((-camera.global_basis.z).dot(camera.global_position.direction_to(subject)) > 0.999)
	camera_mode = 3
	_update_camera(0.0)
	assert(camera.global_transform.is_equal_approx(Data.value_at(data.camera, time)))
	assert(DirAccess.remove_absolute(file_path) == OK)
	_clear_proxies()
	data.clear()
	for node in get_tree().root.find_children("*", "Node", true, false):
		if node is AudioStreamPlayer or node is AudioStreamPlayer3D:
			node.stop()
			node.stream = null
	await get_tree().create_timer(0.25).timeout
	print("REPLAY_SELF_CHECK_COMPLETE")
	get_tree().quit()

func _exit_tree() -> void:
	get_tree().auto_accept_quit = _old_auto_quit
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var music = get_node_or_null("/root/AudioManager")
	if not _exporting and music != null and music.get("_music_player") != null:
		music._music_player.stream_paused = _old_music_paused

func _button(parent: Node, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(action)
	parent.add_child(button)
	return button

func _build_ui() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 120
	add_child(_layer)
	_status = Label.new()
	_status.position = Vector2(20, 16)
	_status.add_theme_color_override("font_shadow_color", Color.BLACK)
	_status.add_theme_constant_override("shadow_offset_x", 1)
	_status.add_theme_constant_override("shadow_offset_y", 1)
	_layer.add_child(_status)
	_controls = PanelContainer.new()
	_controls.name = "ReplayControls"
	_layer.add_child(_controls)
	_controls.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_controls.offset_left = 20
	_controls.offset_right = -20
	_controls.offset_top = -175
	_controls.offset_bottom = -20
	var column := VBoxContainer.new()
	_controls.add_child(column)
	var transport := HBoxContainer.new()
	column.add_child(transport)
	_button(transport, "|◀", func(): seek_to(0.0))
	_button(transport, "−5 s", func(): seek_to(time - 5.0))
	_button(transport, "−1f", func(): seek_to(time - 1.0 / 30.0))
	_play = _button(transport, "▶ Play", _toggle_play)
	_button(transport, "+1f", func(): seek_to(time + 1.0 / 30.0))
	_button(transport, "+5 s", func(): seek_to(time + 5.0))
	var rates := OptionButton.new()
	for rate in [0.1, 0.25, 0.5, 1.0, 2.0]:
		rates.add_item("%s×" % rate)
		rates.set_item_metadata(rates.item_count - 1, rate)
	rates.select(3)
	rates.item_selected.connect(func(index: int): speed = rates.get_item_metadata(index))
	transport.add_child(rates)
	_time_label = Label.new()
	transport.add_child(_time_label)
	_timeline = HSlider.new()
	_timeline.step = 0.001
	_timeline.custom_minimum_size.y = 24
	_timeline.drag_started.connect(func(): _dragging = true; playing = false)
	_timeline.drag_ended.connect(func(changed: bool):
		_dragging = false
		if changed: seek_to(_timeline.value))
	_timeline.value_changed.connect(func(value: float):
		if not _dragging and not seeking: seek_to(value))
	column.add_child(_timeline)
	var cameras := HBoxContainer.new()
	column.add_child(cameras)
	_mode = OptionButton.new()
	for title in ["Camera libera", "Inseguimento", "Orbita", "Camera originale", "Regia salvata"]:
		_mode.add_item(title)
	_mode.select(camera_mode)
	_mode.item_selected.connect(func(index: int): camera_mode = index; _update_camera(0.0))
	cameras.add_child(_mode)
	_targets = OptionButton.new()
	_targets.custom_minimum_size.x = 230
	_targets.item_selected.connect(func(index: int): target_index = _targets.get_item_id(index); _update_camera(0.0))
	cameras.add_child(_targets)
	_button(cameras, "Vicino al soggetto", _focus_target)
	var label := Label.new()
	label.text = " FOV "
	cameras.add_child(label)
	_fov = SpinBox.new()
	_fov.min_value = 5
	_fov.max_value = 120
	_fov.value = 65
	_fov.value_changed.connect(func(value: float): camera.fov = value)
	cameras.add_child(_fov)
	var actions := HBoxContainer.new()
	column.add_child(actions)
	_button(actions, "K · Keyframe", _add_camera_key)
	_record_button = _button(actions, "C · Registra camera", _toggle_camera_recording)
	_button(actions, "Salva regia", _save_shot)
	_button(actions, "Esporta · 60 fps", func():
		if data.is_empty(): return
		playing = false
		_save_dialog.current_file = "aero_demons_%d.avi" % Time.get_unix_time_from_system()
		_save_dialog.popup_centered_ratio(0.75))
	var mute := CheckButton.new()
	mute.text = "Muto"
	mute.toggled.connect(func(value: bool): _muted = value)
	actions.add_child(mute)
	_button(actions, "Archivio", func(): playing = false; _refresh_files(); _library.show())
	_button(actions, "H · Nascondi UI", func(): _controls.hide(); _status.hide())
	_button(actions, "Menu", _return_to_menu)
	_library = PanelContainer.new()
	_library.name = "ReplayLibrary"
	_layer.add_child(_library)
	_library.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_library.offset_left = -490
	_library.offset_right = 490
	_library.offset_top = -290
	_library.offset_bottom = 230
	var browser := VBoxContainer.new()
	_library.add_child(browser)
	var heading := Label.new()
	heading.text = "  AERO DEMONS / REPLAY ARCHIVE"
	heading.add_theme_font_size_override("font_size", 26)
	browser.add_child(heading)
	var help := Label.new()
	help.text = "  I voli vengono registrati automaticamente. F6 ferma/salva, F7 apre il replay.\n  RMB + WASD: camera · Q/E: quota · Shift: rapido · rotella: velocità/distanza\n  Spazio: pausa · frecce: ±5 s · K: keyframe · C: registra camera · H: interfaccia"
	browser.add_child(help)
	_files = ItemList.new()
	_files.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_files.custom_minimum_size = Vector2(900, 300)
	_files.item_activated.connect(func(index: int): open_replay(_files.get_item_metadata(index)))
	browser.add_child(_files)
	var library_actions := HBoxContainer.new()
	browser.add_child(library_actions)
	_button(library_actions, "Apri selezionato", func():
		var selected := _files.get_selected_items()
		if not selected.is_empty(): open_replay(_files.get_item_metadata(selected[0])))
	_button(library_actions, "Aggiorna", _refresh_files)
	_button(library_actions, "Cartella replay", func(): OS.shell_open(ProjectSettings.globalize_path(Data.DIRECTORY)))
	_button(library_actions, "Chiudi", func(): _library.hide())
	_button(library_actions, "Menu principale", _return_to_menu)
	_save_dialog = FileDialog.new()
	_save_dialog.title = "Regia salvata / camera originale · AVI oppure PNG lossless + WAV (senza limite AVI di 4 GiB)"
	_save_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	_save_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_save_dialog.filters = PackedStringArray(["*.avi ; Video AVI (massimo 4 GiB)", "*.png ; Sequenza PNG lossless + audio WAV"])
	_save_dialog.current_dir = ProjectSettings.globalize_path(Data.DIRECTORY)
	_save_dialog.file_selected.connect(_export_video)
	_layer.add_child(_save_dialog)
	_status.text = "Scegli un replay dall'archivio."

func _refresh_files() -> void:
	_files.clear()
	DirAccess.make_dir_recursive_absolute(Data.DIRECTORY)
	var names := DirAccess.get_files_at(Data.DIRECTORY)
	names.sort()
	names.reverse()
	for filename in names:
		if filename.ends_with(".aeroreplay"):
			_files.add_item(filename.trim_suffix(".aeroreplay"))
			_files.set_item_metadata(_files.item_count - 1, Data.DIRECTORY.path_join(filename))
	if _files.item_count > 0:
		_files.select(0)

func open_replay(path: String) -> void:
	if seeking:
		return
	playing = false
	_stop_camera_recording()
	if _shot_dirty and not _save_shot():
		return
	var loaded := Data.load_file(path)
	if loaded.has("error"):
		_status.text = loaded.error
		return
	_clear_proxies()
	if _world != null:
		remove_child(_world)
		_world.queue_free()
	data = loaded.data
	_shot_dirty = false
	file_path = path
	_camera_recording = false
	_record_button.text = "C · Registra camera"
	time = 0.0
	camera.global_transform = Data.value_at(data.camera, 0.0)
	camera.fov = Data.value_at(data.fov, 0.0)
	_world = (load(Data.LEVELS[data.level]) as PackedScene).instantiate() as Node3D
	# Load scenery only: no player, AI, mission timers, damage or weapon scripts.
	for node in _world.find_children("*", "Camera3D", true, false):
		node.get_parent().remove_child(node)
		node.free()
	for node in _world.find_children("*", "Node", true, false):
		if Data.script_path(node) == "res://scripts/maps/tutorial_boundary_controller.gd":
			node.set_script(null)
	_world.transform = data.map_transform
	add_child(_world)
	camera.make_current()
	_targets.clear()
	target_index = -1
	for index in data.actors.size():
		var actor: Dictionary = data.actors[index]
		if actor.scene in Data.SCENES.slice(0, 3):
			_targets.add_item("%s · #%d" % [actor.label, index], index)
			if target_index < 0:
				target_index = index
	_timeline.max_value = data.duration
	_timeline.set_value_no_signal(0.0)
	_library.hide()
	_controls.show()
	_render_world(0.0, 0.0, false)
	_update_camera(0.0)
	_status.text = "%s · %d attori · RMB + WASD/QE · rotella: velocità/distanza · H: UI" % [path.get_file(), data.actors.size()]
	if data.get("engine", "") != Engine.get_version_info().string:
		_status.text += "\nReplay creato con un'altra versione del motore: la resa può differire."
	print("REPLAY_LOADED actors=", data.actors.size(), " duration=", data.duration)

func _clear_proxies() -> void:
	for proxy in _proxies.values():
		proxy.free()
	_proxies.clear()

func _render_world(at: float, step: float, audible: bool) -> void:
	for index in data.actors.size():
		var track: Dictionary = data.actors[index]
		var present: bool = at >= track.born and at <= track.end + 0.00001
		if not present:
			if _proxies.has(index):
				_proxies[index].free()
				_proxies.erase(index)
			continue
		if not _proxies.has(index):
			var proxy := Actor.new()
			proxy.name = "ReplayActor_%d" % index
			_actors.add_child(proxy)
			proxy.setup(track)
			_proxies[index] = proxy
		_proxies[index].render_at(at, step, speed if playing else 0.0, audible and not _muted)

func seek_to(destination: float) -> void:
	if data.is_empty() or seeking or _exporting:
		return
	playing = false
	_stop_camera_recording()
	seeking = true
	var target := clampf(destination, 0.0, data.duration)
	# Replaying a bounded history across rendered frames rebuilds moving-emitter trails.
	# Multiple GPU steps in one CPU frame would all use the final emitter transform.
	_clear_proxies()
	var cursor := maxf(0.0, target - PREROLL)
	_render_world(cursor, 0.0, false)
	while cursor < target - 0.00001:
		var step := minf(1.0 / 30.0, target - cursor)
		cursor += step
		time = cursor
		_render_world(cursor, step, false)
		_update_camera(0.0)
		_status.text = "Ricostruzione effetti… %d%%" % int(100.0 * (1.0 - (target - cursor) / PREROLL))
		await get_tree().process_frame
		if not is_inside_tree():
			return
	time = target
	_timeline.set_value_no_signal(time)
	seeking = false
	_status.text = "Replay in pausa · effetti ricostruiti · Spazio per riprodurre"
	print("REPLAY_SEEK_COMPLETE ", time)

func _process(delta: float) -> void:
	if data.is_empty() or seeking:
		return
	if _exporting:
		time = minf(float(_export_frame) / 60.0, data.duration)
		_render_world(time, 0.0 if _export_frame == 0 else 1.0 / 60.0, true)
		_update_camera(0.0)
		_export_frame += 1
		if float(_export_frame) / 60.0 > data.duration + 1.0 / 60.0:
			_finish_export()
		return
	var previous := time
	if playing and not _dragging:
		time = minf(time + delta * speed, data.duration)
		if time >= data.duration:
			playing = false
	_render_world(time, time - previous, true)
	_update_camera(delta)
	if _camera_recording:
		if not playing:
			_stop_camera_recording()
		elif time >= _next_camera_sample:
			_store_camera_key()
			_next_camera_sample = time + 1.0 / 30.0
	if not _dragging:
		_timeline.set_value_no_signal(time)
	_time_label.text = "%02d:%06.3f / %02d:%06.3f" % [floori(time / 60.0), fmod(time, 60.0), floori(data.duration / 60.0), fmod(data.duration, 60.0)]
	_play.text = "Ⅱ Pausa" if playing else "▶ Play"
	_fov.set_value_no_signal(camera.fov)

func _finish_export() -> void:
	set_process(false)
	# Stop streams before Movie Maker's final audio mix releases their playbacks.
	for node in get_tree().root.find_children("*", "Node", true, false):
		if node is AudioStreamPlayer or node is AudioStreamPlayer3D:
			node.stop()
			node.stream = null
	await RenderingServer.frame_post_draw
	print("REPLAY_EXPORT_COMPLETE samples=", _export_frame)
	get_tree().quit()

func _toggle_play() -> void:
	if data.is_empty() or seeking:
		return
	if time >= data.duration:
		seek_to(0.0)
	else:
		playing = not playing

func _update_camera(delta: float) -> void:
	if data.is_empty():
		return
	if camera_mode >= 3:
		var poses: Array = data.get("shot", []) if camera_mode == 4 else data.camera
		var fovs: Array = data.get("shot_fov", []) if camera_mode == 4 else data.fov
		if not poses.is_empty():
			camera.global_transform = Data.value_at(poses, time, true, camera_mode == 3)
			camera.fov = clampf(Data.value_at(fovs, time), 5.0, 120.0)
		return
	if camera_mode == 0:
		if _mouse_look:
			var direction := Vector3(float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)),
				float(Input.is_physical_key_pressed(KEY_E)) - float(Input.is_physical_key_pressed(KEY_Q)),
				float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W)))
			camera.position += camera.basis * direction.normalized() * _fly_speed * (4.0 if Input.is_physical_key_pressed(KEY_SHIFT) else 1.0) * delta
		return
	if target_index < 0:
		return
	var pose: Transform3D = Data.value_at(data.actors[target_index].poses, time, true, true)
	var offset := Vector3(0, _distance * 0.22, _distance)
	if camera_mode == 1:
		offset = pose.basis.orthonormalized() * offset
	else:
		offset = Vector3(sin(_orbit.x) * cos(_orbit.y), sin(_orbit.y), cos(_orbit.x) * cos(_orbit.y)) * _distance
	var desired := Transform3D(Basis.IDENTITY, pose.origin + offset).looking_at(pose.origin, Vector3.UP)
	camera.global_transform = camera.global_transform.interpolate_with(desired, 1.0 - exp(-delta * 8.0)) if delta > 0.0 else desired

func _focus_target() -> void:
	if target_index < 0:
		return
	var mode := camera_mode
	camera_mode = 1
	_update_camera(0.0)
	camera_mode = mode

func _store_camera_key() -> void:
	_shot_dirty = true
	for pair in [["shot", camera.global_transform], ["shot_fov", camera.fov]]:
		var keys: Array = data[pair[0]]
		var index := Data.lower_key(keys, time) if not keys.is_empty() else -1
		if index >= 0 and is_equal_approx(float(keys[index][0]), time):
			keys[index][1] = pair[1]
		elif index >= 0 and float(keys[index][0]) < time:
			keys.insert(index + 1, [time, pair[1]])
		else:
			keys.push_front([time, pair[1]])

func _add_camera_key() -> void:
	if data.is_empty() or seeking:
		return
	_store_camera_key()
	_status.text = "Keyframe camera a %.3f s · Salva regia per conservarlo" % time

func _toggle_camera_recording() -> void:
	if data.is_empty() or seeking:
		return
	_camera_recording = not _camera_recording
	if _camera_recording:
		for field in ["shot", "shot_fov"]:
			while not data[field].is_empty() and float(data[field].back()[0]) >= time:
				data[field].pop_back()
		if camera_mode >= 3:
			camera_mode = 0
			_mode.select(0)
		_store_camera_key()
		_next_camera_sample = time
		playing = true
	else:
		_store_camera_key()
	_record_button.text = "■ Ferma camera" if _camera_recording else "C · Registra camera"
	_status.text = "Camera: nuova ripresa da %.3f s. Salva regia per conservarla." % time

func _stop_camera_recording() -> void:
	if not _camera_recording:
		return
	_store_camera_key()
	_camera_recording = false
	_record_button.text = "C · Registra camera"

func _save_shot() -> bool:
	if data.is_empty():
		return false
	_stop_camera_recording()
	var error := Data.save_file(file_path, data)
	_status.text = "Regia salvata · seleziona 'Regia salvata' per rivederla." if error.is_empty() else error
	if error.is_empty():
		_shot_dirty = false
	return error.is_empty()

func _export_video(output: String) -> void:
	if _export_pid > 0 and OS.is_process_running(_export_pid):
		_status.text = "Un export è già in corso. Attendi la chiusura della finestra di rendering."
		return
	if not _save_shot():
		return
	if not output.get_extension().to_lower() in ["avi", "png"]:
		output += ".avi"
	var args := PackedStringArray(["--path", ProjectSettings.globalize_path("res://"), "--write-movie", output,
		"--log-file", output + ".log", "--fixed-fps", "60", Data.VIEWER, "--", "--replay-file=" + ProjectSettings.globalize_path(file_path), "--replay-export"])
	_export_pid = OS.create_process(OS.get_executable_path(), args)
	_status.text = ("Export avviato (PID %d): %s\nLa finestra si chiude a fine replay. Non interromperla; avanzamento/errori in %s.log." % [_export_pid, output, output]) if _export_pid > 0 else "Impossibile avviare Movie Maker."

func _return_to_menu() -> void:
	if seeking:
		return
	_stop_camera_recording()
	if _shot_dirty and not _save_shot():
		return
	GameSession.menu_section = ""
	GameSession.change_scene(get_tree(), GameSession.MAIN_MENU)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_stop_camera_recording()
		if not _shot_dirty or _save_shot():
			get_tree().quit()

func _unhandled_input(event: InputEvent) -> void:
	if _exporting:
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			_mouse_look = event.pressed
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if _mouse_look else Input.MOUSE_MODE_VISIBLE
		elif event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			var multiplier := 1.2 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.2
			if camera_mode == 0:
				_fly_speed = clampf(_fly_speed * multiplier, 1.0, 5000.0)
			else:
				_distance = clampf(_distance / multiplier, 3.0, 10000.0)
	elif event is InputEventMouseMotion and _mouse_look:
		if camera_mode == 0:
			camera.rotation.y -= event.relative.x * 0.003
			camera.rotation.x = clampf(camera.rotation.x - event.relative.y * 0.003, -1.55, 1.55)
			camera.rotation.z = 0.0
		elif camera_mode == 2:
			_orbit.x -= event.relative.x * 0.005
			_orbit.y = clampf(_orbit.y + event.relative.y * 0.005, -1.5, 1.5)
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_SPACE: _toggle_play()
			KEY_LEFT: seek_to(time - 5.0)
			KEY_RIGHT: seek_to(time + 5.0)
			KEY_K: _add_camera_key()
			KEY_C: _toggle_camera_recording()
			KEY_H:
				_controls.visible = not _controls.visible
				_status.visible = _controls.visible
			KEY_ESCAPE:
				_mouse_look = false
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
				_controls.show()
				_status.show()
			_:
				return
		get_viewport().set_input_as_handled()
