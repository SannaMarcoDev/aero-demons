extends SceneTree
## godot --headless --path . --script tests/menu_transition_check.gd
## Omit --headless to save transition frames in user://menu_transition_check/.
const Session = preload("res://scripts/ui/game_session.gd")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	Session.menu_section = ""
	assert(Session.change_scene(self, Session.MAIN_MENU) == OK)
	await scene_changed
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(Vector2i(1920, 1080))
		await process_frame
	var menu = current_scene
	var camera = menu.hangar_camera
	var home: Transform3D = camera.transform
	var rear: Vector3 = camera.rear_position
	# Both signals must remain wired; repeated activation is ignored in flight.
	menu.storia_btn.pressed.emit()
	menu.free_flight_btn.pressed.emit()
	assert(menu._transitioning and current_scene == menu)
	await create_timer(0.4).timeout
	assert(menu.menu_ui.modulate.a < 0.01 and menu.vignette.modulate.a < 0.01)
	assert(camera._travel > 0.0 and camera._travel < 1.0)
	await _capture("01_departure")
	await create_timer(0.8).timeout
	await _capture("02_orbit")
	await _settle()
	assert(menu.storia_menu.visible and menu.alps_btn.has_focus())
	assert(camera.position.is_equal_approx(camera.rear_position))
	assert(is_equal_approx(menu.menu_ui.modulate.a, 1.0))
	await _capture("03_sorties")
	# An empty-UI reference verifies the actual requested rear angle.
	menu.menu_ui.hide()
	menu.vignette.hide()
	await _capture("04_rear_angle")
	menu.menu_ui.show()
	menu.vignette.show()
	await menu._on_storia_back_pressed()
	assert(menu.root_menu.visible and camera.transform.is_equal_approx(home))
	menu.free_flight_btn.pressed.emit()
	menu.free_flight_btn.pressed.emit()
	await scene_changed
	await _settle()
	assert(current_scene.scene_file_path == Session.LOADOUT and Session.free_flight)
	assert(current_scene.hangar_camera.position.is_equal_approx(rear))
	assert(is_equal_approx(current_scene.get_node("Main").modulate.a, 1.0))
	assert(current_scene.get_node("Main/LeftPanel").position.x > current_scene.get_node("Main/RightPanel").position.x)
	await _capture("05_free_flight")
	current_scene.back_btn.pressed.emit()
	await scene_changed
	await _settle()
	assert(current_scene.root_menu.visible and current_scene.free_flight_btn.has_focus())
	assert(current_scene.hangar_camera.transform.is_equal_approx(home))
	# Operations -> loadout -> operations keeps the rear viewpoint.
	await current_scene._on_storia_pressed()
	current_scene.alps_btn.pressed.emit()
	await scene_changed
	await _settle()
	assert(not Session.free_flight and current_scene._aircraft_step)
	current_scene.avvia_btn.pressed.emit()
	assert(not current_scene._aircraft_step)
	current_scene.back_btn.pressed.emit()
	assert(current_scene._aircraft_step)
	current_scene.back_btn.pressed.emit()
	await scene_changed
	await _settle()
	assert(current_scene.storia_menu.visible and current_scene.hangar_camera._travel == 1.0)
	# Stop test-owned audio before teardown so headless playback can release it.
	for player in root.get_node("AudioManager").get_children():
		if player is AudioStreamPlayer:
			player.stop()
	await create_timer(0.1).timeout
	current_scene.queue_free()
	await process_frame
	await process_frame
	print("MENU_TRANSITION_CHECK_PASSED")
	quit(0)

func _settle() -> void:
	while current_scene._transitioning:
		await process_frame

func _capture(stem: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await process_frame
	await RenderingServer.frame_post_draw
	var directory := "user://menu_transition_check"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	assert(root.get_texture().get_image().save_png(directory.path_join(stem + ".png")) == OK)
