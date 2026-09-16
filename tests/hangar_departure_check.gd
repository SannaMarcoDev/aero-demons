extends SceneTree
## godot --headless --path . --script tests/hangar_departure_check.gd
## Without --headless, captures the departure in user://hangar_departure_check/.
const Session = preload("res://scripts/ui/game_session.gd")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	for free_flight in [true, false]:
		Session.free_flight = free_flight
		Session.menu_section = ""
		# A lightweight destination tests the real scene switch without loading terrain.
		Session.selected_map = Session.MAIN_MENU
		assert(Session.change_scene(self, Session.LOADOUT) == OK)
		await scene_changed
		var menu = current_scene
		while menu._transitioning:
			await process_frame
		var hangar: Node = menu.door_player.get_parent()
		var left: Node3D = hangar.get_node("HAS_Front_Door_Left")
		var right: Node3D = hangar.get_node("HAS_Front_Door_Right")
		var left_closed := left.position
		var right_closed := right.position
		menu.avvia_btn.pressed.emit()
		assert(not menu._aircraft_step)
		menu.avvia_btn.pressed.emit()
		menu.avvia_btn.pressed.emit()
		menu.back_btn.pressed.emit()
		assert(menu._launching and not menu._aircraft_step)
		assert(not menu.loading_screen.visible)
		await create_timer(0.5).timeout
		assert(is_zero_approx(menu.get_node("Main").modulate.a))
		assert(left.position.x < left_closed.x and right.position.x > right_closed.x)
		assert(not menu.loading_screen.visible)
		await create_timer(1.0).timeout
		assert(left.position.x < left_closed.x - 1.0 and right.position.x > right_closed.x + 1.0)
		assert(not menu.loading_screen.visible)
		if free_flight:
			await _capture("01_opening")
		await menu.door_player.animation_finished
		assert(is_equal_approx(left.position.x, -8.1))
		assert(is_equal_approx(right.position.x, 8.1))
		assert(menu.loading_screen.visible)
		assert(menu.loading_screen.get_node("Label").text == "CARICAMENTO…")
		if free_flight:
			await _capture("02_open")
		var saw_black := false
		while current_scene == menu:
			if menu.loading_screen.modulate.a >= 0.999:
				saw_black = true
				if free_flight:
					await _capture("03_loading")
			await process_frame
		assert(saw_black, "The black loading frame must precede the scene switch")
		if current_scene == null:
			await scene_changed
		assert(current_scene.scene_file_path == Session.MAIN_MENU)
	for audio in root.get_node("AudioManager").get_children():
		if audio is AudioStreamPlayer:
			audio.stop()
	await create_timer(0.1).timeout
	current_scene.queue_free()
	await process_frame
	await process_frame
	print("HANGAR_DEPARTURE_CHECK_PASSED")
	quit(0)

func _capture(stem: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var directory := "user://hangar_departure_check"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	assert(root.get_texture().get_image().save_png(directory.path_join(stem + ".png")) == OK)
