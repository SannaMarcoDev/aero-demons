extends SceneTree
## godot --headless --path . --script tests/menu_hangar_check.gd

func _initialize() -> void:
	_check.call_deferred()

func _check() -> void:
	root.get_node("AudioManager")._music_player.stop()
	await create_timer(0.1).timeout
	var menu = load("res://scenes/ui/main_menu.tscn").instantiate()
	root.add_child(menu)
	await process_frame
	var viewport: SubViewport = menu.get_node("AircraftViewportContainer/SubViewport")
	var stage = viewport.get_node("MenuAircraftStage")
	var camera = stage.get_node("Camera3D")
	assert(viewport.render_target_update_mode != SubViewport.UPDATE_ALWAYS)
	camera.travel_duration = 0.05
	var travel: Tween = camera.travel_to(true)
	assert(viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS)
	await travel.finished
	assert(viewport.render_target_update_mode == SubViewport.UPDATE_ONCE)
	camera.set_view(0.0)
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	viewport.size_changed.emit()
	assert(viewport.render_target_update_mode == SubViewport.UPDATE_ONCE)
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	menu.options_panel._changed()
	assert(viewport.render_target_update_mode == SubViewport.UPDATE_ONCE)
	assert(stage.get_node("Hangar/HAS_Concrete_Floor") is MeshInstance3D)
	assert(stage.get_node("Aircraft").scene_file_path == "res://scenes/aircraft/fa_n26.tscn")
	for fire in stage.get_node("Aircraft/WingDamage").get_children():
		assert(fire.intensity == 0.0 and not fire.get_node("Smoke").emitting)
	var exhausts: Array[Node] = stage.find_children("*JetExhaust*", "", true, false)
	for exhaust in exhausts:
		assert(not exhaust.get_node("Volume").visible, "Hangar afterburners must remain off")
	var aircraft_transform: Transform3D = stage.get_node("Aircraft").transform
	await process_frame
	assert(stage.get_node("Aircraft").transform == aircraft_transform)
	for wheel_name in ["NoseWheel", "LeftWheel", "RightWheel"]:
		var wheel: MeshInstance3D = stage.get_node("Aircraft/DisplayLandingGear/" + wheel_name)
		assert(is_zero_approx(wheel.global_position.y - wheel.mesh.top_radius))
	var panel: Control = menu.get_node("MarginContainer/MainLayout/ContentArea/RightPanel")
	assert(menu.root_menu.visible and menu.storia_btn.has_focus() and not panel.visible)
	menu.options_btn.pressed.emit()
	assert(menu.options_menu.visible and panel.visible)
	menu._show_root_menu()
	assert(not panel.visible)
	await menu._on_storia_pressed()
	assert(menu.storia_menu.visible and menu.alps_btn.has_focus() and panel.visible)
	await menu._on_storia_back_pressed()
	assert(menu.root_menu.visible and not panel.visible)
	for player in root.get_node("AudioManager").get_children():
		if player is AudioStreamPlayer:
			player.stop()
	await create_timer(0.1).timeout
	print("MENU_HANGAR_CHECK_PASSED")
	menu.queue_free()
	await process_frame
	quit(0)
