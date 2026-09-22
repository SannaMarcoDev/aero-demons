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
	var stage = menu.get_node("AircraftViewportContainer/SubViewport/MenuAircraftStage")
	assert(stage.get_node("Hangar/HAS_Concrete_Floor") is MeshInstance3D)
	assert(stage.get_node("Aircraft").scene_file_path == "res://scenes/aircraft/fa_n26.tscn")
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
