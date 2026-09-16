extends SceneTree
## godot --headless --path . --script tests/tutorial_mission_check.gd --fixed-fps 60
const LEVEL := preload("res://scenes/levels/tutorial.tscn")
const Bindings = preload("res://scripts/ui/controller_bindings.gd")
var arena: Node3D
var mission: TutorialMission
var hud: CombatHUD
var radio: RadioDialogue
var handoffs := 0


func _initialize() -> void:
	_run.call_deferred()


func _new_tutorial() -> void:
	arena = LEVEL.instantiate()
	arena.set_script(null)
	arena.get_node("GardaLake").free()
	arena.get_node("HorizonGraphics").free()
	root.add_child(arena)
	current_scene = arena
	hud = arena.get_node("CombatHUD")
	mission = hud.mission_controller
	radio = mission.radio
	radio.set_process(false)
	mission.flight_training_completed.connect(func(): handoffs += 1)
	assert(mission.phase == TutorialMission.Phase.OPENING)
	assert(mission.movement_practice == Vector3.ZERO and mission.acceleration_practice == 0.0)
	assert(not hud.tutorial_panel.visible and mission.tutorial_contact() == null)
	assert(get_nodes_in_group("targets").is_empty() and not GameSession.free_flight)
	for aircraft in [mission.player, arena.get_node("Wingman1"), arena.get_node("Wingman2")]:
		assert(aircraft.invulnerable)
		aircraft.apply_damage(1000)
		aircraft._hitbox.apply_damage(1000)
		aircraft.apply_napalm(1000, 1)
		aircraft._on_solid_collision(null)
		assert(aircraft.health == aircraft.max_health and aircraft._napalm_time == 0)
	assert(not mission.director.allow_player_attacks)
	var weapons: WeaponController = mission.player.get_node("WeaponController")
	var ammo := weapons.gun_ammo
	weapons.fire_gun()
	weapons.fire_missile()
	assert(weapons.gun_ammo == ammo and get_nodes_in_group("mission_projectiles").is_empty())


func _radio_until(phase: int) -> void:
	for frame in 100:
		if mission.phase == phase:
			return
		radio._process(30)
		await process_frame
	assert(false, "Radio phase not reached")


func _confirm() -> void:
	# A held confirm that predates opening cannot dismiss the panel.
	await process_frame
	var event := InputEventAction.new()
	event.action = "ui_accept"
	event.pressed = true
	Input.action_press("ui_accept")
	hud._unhandled_input(event)
	await process_frame
	assert(paused and hud.tutorial_panel.visible)
	Input.action_release("ui_accept")
	await process_frame
	await process_frame
	assert(paused == hud.tutorial_panel.visible)


func _practice(action: String) -> void:
	Input.action_press(action)
	for tick in 30:
		await physics_frame
	Input.action_release(action)
	await physics_frame


func _run() -> void:
	_new_tutorial()
	await process_frame
	# Inputs before their phase have no credit.
	await _practice("accelerate")
	await _practice("pitch_up")
	assert(mission.acceleration_practice == 0 and mission.movement_practice == Vector3.ZERO)
	await _radio_until(TutorialMission.Phase.MOVEMENT_READING)
	var position := mission.player.global_position
	var wing_position: Vector3 = arena.get_node("Wingman1").global_position
	var clock := mission.director.clock
	for frame in 6:
		await process_frame
	assert(paused and mission.player.global_position == position)
	assert(arena.get_node("Wingman1").global_position == wing_position and mission.director.clock == clock)
	mission._on_radio_finished()
	mission._on_tutorial_confirmed()
	assert(mission.phase == TutorialMission.Phase.MOVEMENT_READING)
	# Existing pause/options may cover a reading panel, but must restore its pause.
	hud._open_pause_menu()
	hud._on_resume_pressed()
	assert(paused and hud.tutorial_panel.visible)
	hud._on_joy_connection_changed(0, false)
	assert(paused and hud._pause_overlay.visible and hud.tutorial_panel.visible)
	hud._on_joy_connection_changed(0, true)
	hud._on_resume_pressed()
	assert(paused and not hud._pause_overlay.visible and hud.tutorial_panel.visible)
	# Remap confirm and flight prompts using the same production profile machinery.
	var profile := Bindings.defaults()
	var swap: Dictionary = profile.ui_accept
	profile.ui_accept = profile.ui_cancel
	profile.ui_cancel = swap
	swap = profile.pitch_up
	profile.pitch_up = profile.pitch_down
	profile.pitch_down = swap
	Bindings.apply(profile)
	hud.tutorial_panel.refresh_text()
	assert(hud.tutorial_panel._hint.text.contains(Bindings.action_label("ui_accept")))
	assert(hud.tutorial_panel._body.text.contains(Bindings.action_label("pitch_up")))
	# Wrong physical button does not confirm; remapped physical binding does.
	await process_frame
	var button := InputEventJoypadButton.new()
	button.button_index = JOY_BUTTON_A
	button.pressed = true
	assert(not hud.tutorial_panel.handle_input(button))
	button.button_index = JOY_BUTTON_B
	assert(hud.tutorial_panel.handle_input(button))
	await process_frame
	assert(not paused and mission.phase == TutorialMission.Phase.MOVEMENT)
	Bindings.apply({})
	for tick in 60:
		await physics_frame
	assert(mission.phase == TutorialMission.Phase.MOVEMENT)
	assert(hud._objectives_line.text.contains("PROVA"))
	await _practice("pitch_up")
	assert(mission.phase == TutorialMission.Phase.MOVEMENT)
	await _practice("roll_left")
	# Practice may finish near the boundary: contacts must remain reachable, not beyond it.
	mission.player.global_position = Vector3(mission.player.return_distance - 2000, 8000, 0)
	mission.player.global_basis = Basis(Vector3.UP, -PI / 2)
	await _practice("yaw_right")
	assert(mission.phase == TutorialMission.Phase.CONTACT_RADIO)
	assert(Vector2(mission.contact.position.x, mission.contact.position.z).length() < mission.player.return_distance)
	assert(mission.player.global_position.distance_to(mission.contact.global_position) < 6200)
	assert(mission.tutorial_contact() != null and not mission.terminal)
	await _radio_until(TutorialMission.Phase.SPEED_READING)
	assert(hud.tutorial_panel._body.text.contains(Bindings.action_label("brake")))
	await _confirm()
	assert(mission.phase == TutorialMission.Phase.APPROACH)
	assert(hud._objectives_line.text.contains("ACCELERA"))
	# Proximity alone, even with duplicate radio/kill events, is insufficient.
	mission.player.global_position = mission.contact.global_position
	mission._on_radio_finished()
	mission._on_enemy_destroyed(null)
	for tick in 10:
		await physics_frame
	assert(mission.phase == TutorialMission.Phase.APPROACH and handoffs == 0)
	# Acceleration alone at long distance is also insufficient.
	mission.player.global_position = mission.contact.global_position + Vector3(0, 0, 5000)
	await _practice("accelerate")
	assert(mission.phase == TutorialMission.Phase.APPROACH and mission.acceleration_practice >= mission.PRACTICE_SECONDS)
	mission.player.global_position = mission.contact.global_position + Vector3(0, 0, 1000)
	for tick in 10:
		await physics_frame
	assert(mission.phase == TutorialMission.Phase.TARGET_READING and handoffs == 1)
	mission._on_radio_finished()
	mission._on_tutorial_confirmed()
	mission._on_enemy_destroyed(null)
	assert(not mission.terminal and paused and not hud.mission_result_visible())
	assert(mission.active_enemies.size() == 2 and get_nodes_in_group("mission_projectiles").is_empty())
	await _check_weapon_panels()
	await _check_waves()
	paused = false
	arena.queue_free()
	await process_frame
	# Retry uses a fresh scene: no phase, modal, prompt, radio generation or input latch survives.
	_new_tutorial()
	await _radio_until(TutorialMission.Phase.MOVEMENT_READING)
	assert(handoffs == 1)
	paused = false
	arena.queue_free()
	await process_frame
	_new_tutorial()
	await process_frame
	radio._process(30)
	mission._finish("TEST", "Cancel pending radio")
	for frame in 5:
		await process_frame
	assert(not radio.playing and not hud.tutorial_panel.visible)
	paused = false
	arena.queue_free()
	await process_frame
	# Every loadout is explained; confirming the panels alone must start combat.
	for first: String in WeaponController.Catalog.ids():
		for second: String in WeaponController.Catalog.ids():
			GameSession.selected_missiles = [first, second]
			_new_tutorial()
			await process_frame
			radio.stop()
			mission.phase = TutorialMission.Phase.APPROACH
			mission._show_weapons_instructions()
			await _check_weapon_panels()
			mission.player.apply_damage(1000)
			assert(mission.terminal and hud._mission_title.text == "MISSIONE FALLITA")
			mission._on_radio_finished()
			mission._try_advance()
			assert(hud._mission_title.text == "MISSIONE FALLITA")
			paused = false
			arena.queue_free()
			await process_frame
	print("Tutorial mission check passed: flight, informational panels, 25 loadouts without weapon actions, vulnerability, 2/4/8, victory/defeat, pause and retry")
	quit()


func _check_weapon_panels() -> void:
	var weapons := mission.weapons
	assert(not mission.player.invulnerable and mission.director.allow_player_attacks)
	assert(weapons.firing_enabled and mission.targeting.auto_acquire)
	for enemy in mission.active_enemies:
		assert(not enemy.invulnerable and enemy.assignment_target != null)
		var health := enemy.health
		enemy.apply_damage(1)
		assert(enemy.health == health - 1)
	var health := mission.player.health
	mission.player.apply_damage(1)
	assert(mission.player.health == health - 1)
	var count := mission.spawn_root.get_child_count()
	mission._show_weapons_instructions()
	assert(mission.spawn_root.get_child_count() == count)
	var position := mission.player.global_position
	var ammo := weapons.missile_ammo
	await _confirm()
	assert(mission.phase == TutorialMission.Phase.MISSILE_READING and paused)
	assert(hud.tutorial_panel._body.text.contains(weapons.equipped_missile_ids[0]))
	assert(hud.tutorial_panel._body.text.contains(weapons.equipped_missile_ids[1]))
	await _confirm()
	assert(mission.phase == TutorialMission.Phase.GUN_READING and paused)
	assert(mission.player.global_position == position, "No simulation between reading panels")
	await _confirm()
	assert(mission.phase == TutorialMission.Phase.COMBAT and not paused)
	assert(not hud.tutorial_panel.visible and weapons.missile_ammo == ammo)
	assert(weapons.gun_ammo == weapons.gun_ammo_max)
	assert(get_nodes_in_group("mission_projectiles").is_empty())
	# No tutorial handler reacts to weapon use or refills ammunition after the panels.
	weapons.gun_ammo = 0
	mission._physics_process(1.0 / 60.0)
	assert(weapons.gun_ammo == 0 and mission.phase == TutorialMission.Phase.COMBAT)
	for wing in [arena.get_node("Wingman1"), arena.get_node("Wingman2")]:
		assert(wing.invulnerable)
		wing.apply_damage(1000)
		assert(wing.health == wing.max_health)


func _check_waves() -> void:
	for frame in 100:
		if not radio.playing:
			break
		radio._process(30)
		await process_frame
	for wave in 3:
		assert(mission.phase == TutorialMission.Phase.COMBAT)
		assert(mission.encounter_index == wave and mission.remaining == [2, 4, 8][wave])
		assert(not hud.tutorial_panel.visible)
		var victims := mission.active_enemies.duplicate()
		hud._open_pause_menu()
		for enemy in victims:
			enemy.apply_damage(enemy.health)
			mission._on_enemy_destroyed(enemy)
		await process_frame
		assert(mission.encounter_index == wave and mission.remaining == 0)
		hud._on_resume_pressed()
		for frame in 5:
			await process_frame
		assert(not hud.mission_result_visible())
		if wave < 2:
			await _radio_until(TutorialMission.Phase.COMBAT)
			var markers := arena.get_node("EnemySpawnMarkers/Encounter%d" % (wave + 2))
			for enemy in mission.active_enemies:
				assert(enemy._spawn_transform.is_equal_approx(markers.get_node(NodePath(enemy.name)).global_transform))
		else:
			assert(mission.phase == TutorialMission.Phase.OUTRO)
			for frame in 100:
				if mission.terminal:
					break
				radio._process(30)
				await process_frame
			assert(mission.terminal and paused and hud._mission_title.text == "MISSIONE COMPLETATA")
