extends SceneTree
## godot --headless --path . --script res://tests/utah_levels_check.gd

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	for path in [GameSession.UTAH_FREE_FLIGHT, GameSession.UTAH_TUTORIAL]:
		var level := load(path).instantiate() as Node3D
		root.add_child(level)
		await process_frame
		var map := level.get_node("Utah")
		assert(map.scene_file_path == "res://scenes/maps/utah_final.tscn")
		assert(level.get_node(level.terrain_path) == map.get_node("UtahTerrain"))
		assert(not map.get_node("ValidationCamera").current)
		assert(level.get_node("Player/FlightCamera").current)
		var hud := level.get_node("CombatHUD")
		assert(hud.get_node(hud.boundary_path) == map.get_node("ValidationBoundaryController"))
		assert(GameSession.selected_map == path)
		assert(GameSession.free_flight == (path == GameSession.UTAH_FREE_FLIGHT))
		assert(GameSession.level_name().begins_with("UTAH · "))
		if GameSession.free_flight:
			assert(hud.get_node("SortieController").objectives_text() == ">FREE FLIGHT")
		else:
			assert(level.has_node("Wingman1") and level.has_node("Wingman2"))
			var mission := hud.mission_controller as TutorialMission
			assert(mission.phase == TutorialMission.Phase.FLIGHT)
			assert(level.has_node("HangarArrival") and mission.radio.playing)
			assert(not mission.weapons.firing_enabled and mission.active_enemies.is_empty())
		level.free()
		await process_frame
	for audio in root.get_node("AudioManager").get_children():
		if audio is AudioStreamPlayer:
			audio.stop()
			audio.stream = null
	var flush_until := Time.get_ticks_msec() + 600
	while Time.get_ticks_msec() < flush_until:
		await process_frame
		OS.delay_msec(10)
	print("PASS: Utah levels, airborne tutorial compatibility")
	quit()
