extends SceneTree
## godot --headless --path . --script tests/aircraft_selection_check.gd

const Catalog = preload("res://scripts/aircraft/aircraft_catalog.gd")
const Session = preload("res://scripts/ui/game_session.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	assert(Catalog.ids() == [Catalog.DEFAULT_ID])
	for stale_id in ["missing", "fighter", "finished"]:
		Session.selected_aircraft_id = stale_id
		assert(Session.selected_aircraft_id == Catalog.DEFAULT_ID)
	Session.selected_aircraft_id = "finished"
	assert(Session.change_scene(self, Session.LOADOUT) == OK)
	await scene_changed
	var menu = current_scene
	while menu._transitioning:
		await process_frame
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
		assert(model.global_basis.get_scale().is_equal_approx(Vector3.ONE), "N26 must retain native metre dimensions")
		var mesh := model.get_node("Model/Airframe") as MeshInstance3D
		var size := mesh.get_aabb().size * mesh.global_basis.get_scale()
		assert(size.is_equal_approx(Vector3(14.078388, 4.744039, 20.758505)))
		assert(player.get_node("Hitbox").scale.is_equal_approx(Vector3.ONE * 2.0))
		var weapons := player.get_node("WeaponController") as WeaponController
		assert(weapons.scale.is_equal_approx(Vector3.ONE * 2.0))
		for offset in [weapons.gun_muzzle] + weapons.missile_pylons:
			var muzzle: Transform3D = weapons._muzzle_transform(offset)
			assert(muzzle.basis.get_scale().is_equal_approx(Vector3.ONE))
			assert(muzzle.origin.is_equal_approx(weapons.to_global(offset)))
		assert(player.camera_depth > 20.0, "Camera must remain behind the full-size airframe")
		var afterburners := model.get_node("Afterburners") as Node3D
		assert(afterburners.get_child_count() == 2)
		for i in afterburners.get_child_count():
			var thruster := afterburners.get_child(i) as Node3D
			var socket := mesh.get_node("Engine_Left" if i == 0 else "Engine_Right") as Node3D
			assert(thruster.global_position.distance_to(socket.global_position) < 0.001, "Exhaust detached from N26 nozzle")
			assert(is_equal_approx(thruster.nozzle_radius * thruster.global_basis.get_scale().x, 0.405), "N26 plume must fit the actual nozzle opening")
		var wing_damage := model.get_node("WingDamage") as Node3D
		assert(wing_damage != null and wing_damage.get_child_count() >= 2)
		assert(player._damage_emitters.size() == wing_damage.get_child_count())
		assert(player.get_node("WeaponController").equipped_missile_ids == Session.selected_missiles)
		player.reset_player()
		assert(player.get_node("AircraftModel") == model)
		player.free()
		await process_frame

	# All five missiles remain selectable in either slot and reach a newly spawned player.
	var missiles := ["STDM", "HSSTDM", "BAHM", "NCGBM", "MTSM"]
	assert(menu._missile_buttons.keys() == missiles)
	menu.avvia_btn.pressed.emit()
	for first: String in missiles:
		for second: String in missiles:
			for slot in 2:
				menu._select_slot(slot)
				menu._missile_buttons[[first, second][slot]].pressed.emit()
			Session.selected_aircraft_id = "fighter"
			var player = load("res://scenes/player/player.tscn").instantiate()
			player.position.y = 2000.0
			root.add_child(player)
			player.set_physics_process(false)
			assert(player.get_node("AircraftModel").scene_file_path == Catalog.get_def(Catalog.DEFAULT_ID).scene.resource_path)
			var weapons = player.get_node("WeaponController")
			assert(weapons.equipped_missile_ids == [first, second])
			weapons.cycle_missile_type()
			assert(weapons.equipped_missile_id == second)
			_check_disabled_maneuvers(player)
			player.free()
			await process_frame

	# The selection belongs to the player, never to AI sharing PlayerFlight.
	var enemy = load("res://scenes/enemies/enemy_fighter.tscn").instantiate()
	Session.selected_aircraft_id = "fa_n26"
	root.add_child(enemy)
	enemy.set_physics_process(false)
	assert(enemy.get_node("AircraftModel").scene_file_path == "res://assets/aircraft/aircraft_game_ready.glb")
	assert(enemy.get_node("WeaponController").equipped_missile_ids == ["STDM"])
	assert(enemy.airframe_scale == 0.5, "N26 sizing must not rescale AI airframes")
	# The shared maneuver implementation is not disabled for non-player airframes.
	enemy._begin_spin_dash()
	assert(enemy.spin_dash_active)
	enemy.free()
	await process_frame
	for audio in root.get_node("AudioManager").get_children():
		if audio is AudioStreamPlayer:
			audio.stop()
			audio.stream = null
	await create_timer(0.2).timeout
	current_scene.queue_free()
	await process_frame
	await process_frame
	print("PASS: internal build, default aircraft, stale selections, 25 missile pairs, disabled player maneuvers and AI isolation")
	quit()


func _check_disabled_maneuvers(player: PlayerFlight) -> void:
	Input.action_press("yaw_left")
	Input.action_press("yaw_right")
	player._update_controls()
	assert(not player.high_g_active and player.brake_input == 0.0)
	Input.action_release("yaw_left")
	Input.action_release("yaw_right")
	for tap in 2:
		Input.action_press("accelerate")
		player._flight_time += 0.05
		player._update_controls()
		player._update_spin_dash()
		assert(player.throttle_input == 1.0 and not player.spin_dash_trigger and not player.spin_dash_active)
		Input.action_release("accelerate")
		player._update_controls()
	player.spin_dash_trigger = true
	player._update_spin_dash()
	player._begin_spin_dash()
	assert(not player.spin_dash_active)
	assert(player.spin_dash_camera_fov_offset() == 0.0)
	assert(player.spin_dash_camera_depth_offset() == 0.0)
