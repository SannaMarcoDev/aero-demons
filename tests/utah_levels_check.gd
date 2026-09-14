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
			for i in 3:
				assert(level.get_node("EnemySpawnMarkers/Encounter%d" % (i + 1)).get_child_count() == [2, 4, 8][i])
		level.free()
		await process_frame
	print("UTAH LEVELS CHECK PASS")
	quit()
