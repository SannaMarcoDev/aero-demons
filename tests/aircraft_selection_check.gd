extends SceneTree
## godot --headless --path . --script tests/aircraft_selection_check.gd

const Catalog = preload("res://scripts/aircraft/aircraft_catalog.gd")
const Session = preload("res://scripts/ui/game_session.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	Session.selected_aircraft_id = "missing"
	assert(Session.change_scene(self, Session.LOADOUT) == OK)
	await scene_changed
	var menu = current_scene
	assert(Session.selected_aircraft_id == Catalog.DEFAULT_ID)
	assert(menu._aircraft_step and menu.aircraft_scroll.visible)
	assert(not menu.missile_list.is_visible_in_tree())
	assert(menu._aircraft_buttons.size() == Catalog.ids().size())
	for id: String in Catalog.ids():
		var definition := Catalog.get_def(id)
		var previous := Session.selected_aircraft_id
		menu._aircraft_buttons[id].grab_focus()
		assert(Session.selected_aircraft_id == previous, "Focus only previews; selection requires confirmation")
		assert(menu._preview_aircraft_id == id)
		menu._aircraft_buttons[id].pressed.emit()
		assert(Session.selected_aircraft_id == id)
		assert(menu.preview_root.get_child_count() == 1)
		var preview := menu.preview_root.get_child(0) as Node3D
		assert(preview.scene_file_path == definition.scene.resource_path)
		assert(preview.transform.is_equal_approx(definition.transform))
		menu.avvia_btn.pressed.emit()
		assert(not menu._aircraft_step and menu.missile_list.is_visible_in_tree())
		assert(menu._preview_aircraft_id == id and menu.slot1_btn.has_focus())
		menu._on_pick("NCGBM")
		menu.back_btn.pressed.emit()
		assert(menu._aircraft_step and menu._aircraft_buttons[id].has_focus())
		assert(Session.selected_missiles[0] == "NCGBM")

		var player = load("res://scenes/player/player.tscn").instantiate()
		player.position.y = 2000.0
		root.add_child(player)
		player.set_physics_process(false)
		var model := player.get_node("AircraftModel") as Node3D
		assert(model.scene_file_path == definition.scene.resource_path)
		assert(model.position.is_equal_approx(preview.position * player.airframe_scale))
		assert(model.scale.is_equal_approx(preview.scale * player.airframe_scale))
		var afterburners := player.get_node("Afterburners") as Node3D
		assert(afterburners.get_child_count() == definition.engines.size())
		for i in afterburners.get_child_count():
			var thruster := afterburners.get_child(i) as Node3D
			assert((afterburners.transform * thruster.position).is_equal_approx(definition.engines[i] * player.airframe_scale))
		assert(player.get_node("WeaponController").equipped_missile_ids == Session.selected_missiles)
		player.reset_player()
		assert(player.get_node("AircraftModel") == model)
		player.free()
		await process_frame

	# The selection belongs to the player, never to AI sharing PlayerFlight.
	var enemy = load("res://scenes/enemies/enemy_fighter.tscn").instantiate()
	Session.selected_aircraft_id = "fa_n26"
	root.add_child(enemy)
	enemy.set_physics_process(false)
	assert(enemy.get_node("AircraftModel").scene_file_path == "res://assets/aircraft/aircraft_game_ready.glb")
	enemy.free()
	await process_frame
	print("Aircraft selection check passed: all %d airframes, previews, two-step flow, persistence, exhausts, weapons and AI isolation" % Catalog.ids().size())
	quit()
