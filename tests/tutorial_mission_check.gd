extends SceneTree
## godot --headless --path . --script tests/tutorial_mission_check.gd --fixed-fps 60
# Load after SceneTree initialization: the map contains native rendering resources.
const LEVEL := "res://scenes/levels/tutorial.tscn"
const Bindings = preload("res://scripts/ui/controller_bindings.gd")
var arena: Node3D
var mission: TutorialMission
var hud: CombatHUD
var radio: RadioDialogue
var handoffs := 0


func _initialize() -> void:
	_run.call_deferred()


func _new_tutorial(ground_start := false) -> void:
	arena = load(LEVEL).instantiate()
	arena.set_script(null)
	if ground_start:
		var airport := arena.get_node("GardaLake/Airport")
		airport.get_parent().remove_child(airport)
		airport.owner = null
		arena.add_child(airport)
	else:
		arena.get_node("Player").start_on_ground = false
		arena.get_node("Player").position = Vector3(0, 8000, 0)
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
	await _check_ground_departure()
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
	for audio in root.get_node("AudioManager").get_children():
		if audio is AudioStreamPlayer:
			audio.stop()
			audio.stream = null
	await create_timer(0.1).timeout
	print("PASS: Tutorial mission check passed: flight, informational panels, 25 loadouts without weapon actions, vulnerability, 2/4/8, victory/defeat, pause and retry")
	quit()


func _check_ground_departure() -> void:
	_new_tutorial(true)
	var p := mission.player
	var spawn := p.global_transform
	assert(p.speed == 0.0 and p.gear_down and p.gear_extension == 1.0)
	assert(p.get_node("AircraftModel").scale.is_equal_approx(Vector3.ONE))
	for tick in 90:
		await physics_frame
	assert(p.position.y < spawn.origin.y and p.position.x == spawn.origin.x and p.position.z == spawn.origin.z)
	await _radio_until(TutorialMission.Phase.GROUND_READING)
	assert(p.speed == 0.0 and p.grounded and paused)
	await _confirm()
	p.set_physics_process(false) # Drive production movement deterministically below.
	for tick in 90:
		await physics_frame
		p._apply_flight(1.0 / 60.0)
	assert(p.grounded and p.speed == 0.0 and p._ground_body.is_on_floor())
	p.toggle_landing_gear()
	assert(p.gear_down, "Cannot retract wheels while grounded")
	# Gate is independent of mission safety, and covers direct weapon calls.
	mission.weapons.firing_enabled = true
	for extension in [1.0, 0.5, 0.01]:
		p.gear_extension = extension
		assert(not mission.weapons._pilot_allows_fire("gun"))
		assert(not mission.weapons._pilot_allows_fire("missile"))
	p.gear_extension = 1.0
	mission.weapons.firing_enabled = false
	# No engine input must not creep back to cruise speed; brake wins over throttle.
	p.throttle_input = 1.0
	for tick in 30:
		await physics_frame
		p._apply_flight(1.0 / 60.0)
	assert(is_equal_approx(p.speed, p.ground_acceleration * 0.5) and p.speed < 4.0, "Taxi acceleration must be gentler than flight")
	p.yaw_input = 1.0
	await physics_frame
	p._apply_flight(1.0 / 60.0)
	assert(p._angular_velocity.y < 0.0 and absf(p._angular_velocity.y) <= p.ground_steering_acceleration / 60.0 + 0.001)
	p.yaw_input = -1.0
	await physics_frame
	p._apply_flight(1.0 / 60.0)
	assert(absf(p._angular_velocity.y) < 0.001, "Steering reversal must ramp, not snap")
	p.yaw_input = 0.0
	p.ground_brake_input = 1.0
	for tick in 30:
		await physics_frame
		p._apply_flight(1.0 / 60.0)
	assert(p.speed == 0.0)
	p.throttle_input = 0.0
	p.ground_brake_input = 0.0
	# Follow authored points with the real steering and pavement collision, no repositioning.
	var points: Array[Vector3] = [mission.taxi_markers[0].position,
		Vector3(mission.taxi_markers[1].position.x, 0, mission.taxi_markers[0].position.z + 35),
		mission.taxi_markers[1].position, mission.taxi_markers[2].position]
	for index in points.size():
		var destination := points[index]
		for tick in 6000:
			var offset := destination - p.global_position
			offset.y = 0.0
			if offset.length() < 10.0:
				break
			var forward := -p.global_basis.z
			forward.y = 0.0
			var angle := forward.signed_angle_to(offset.normalized(), Vector3.UP)
			p.yaw_input = clampf(-angle * 3.0, -1.0, 1.0)
			p.throttle_input = 0.5 if p.speed < 10.0 else 0.0
			p.brake_input = 0.5 if p.speed > 11.0 else 0.0
			await physics_frame
			p._apply_flight(1.0 / 60.0)
		if p._ground_body.is_on_wall():
			for collision_index in p._ground_body.get_slide_collision_count():
				var collision := p._ground_body.get_slide_collision(collision_index)
				print("GROUND_COLLISION ", collision.get_collider_shape(), " at ", collision.get_position())
		assert(Vector2(p.position.x - destination.x, p.position.z - destination.z).length() < 10.0, "Taxi marker unreachable: %d at %s" % [index, p.position])
		print("GROUND_MARKER_REACHED ", index + 1)
	# Reaching marker 3 while facing across the runway must not advance.
	assert(mission.phase == TutorialMission.Phase.TAXI_ALIGN)
	var runway := mission.taxi_markers[3].position - mission.taxi_markers[2].position
	runway.y = 0.0
	var fast_alignment_checked := false
	for tick in 1200:
		var forward := -p.global_basis.z
		forward.y = 0.0
		var angle := forward.signed_angle_to(runway.normalized(), Vector3.UP)
		p.yaw_input = clampf(-angle * 3.0, -1.0, 1.0)
		p.throttle_input = 0.0
		p.brake_input = 0.0
		if absf(angle) < deg_to_rad(mission.runway_alignment_degrees):
			# Above the removed 12 m/s cap: alignment/proximity alone must unlock checkpoint 3.
			p.speed = 45.0
			mission._update_taxi()
			assert(mission.phase == TutorialMission.Phase.TAKEOFF_READING, "Checkpoint 3 must accept high-speed alignment")
			fast_alignment_checked = true
			p.speed = 3.0
			break
		# A tight rolling turn inside the marker radius.
		p.speed = 3.0
		await physics_frame
		p._apply_flight(1.0 / 60.0)
		if mission.phase == TutorialMission.Phase.TAKEOFF_READING:
			break
	assert(fast_alignment_checked and mission.phase == TutorialMission.Phase.TAKEOFF_READING)
	await process_frame
	await process_frame
	await _confirm()
	assert(mission.phase == TutorialMission.Phase.TAKEOFF and not paused)
	p.yaw_input = 0.0
	p.throttle_input = 1.0
	var runway_height := p.position.y
	for tick in 1800:
		p.yaw_input = clampf(-(-p.global_basis.z).signed_angle_to(runway.normalized(), Vector3.UP) * 3.0, -1.0, 1.0)
		p.pitch_input = -0.15 if p.speed >= p.rotation_speed and p.rotation.x < deg_to_rad(10.0) else 0.0
		await physics_frame
		p._apply_flight(1.0 / 60.0)
		if mission.phase == TutorialMission.Phase.GEAR:
			break
	assert(not p.grounded and p.position.y > runway_height + 100.0, "Takeoff failed at %s speed %.1f, grounded %s" % [p.position, p.speed, p.grounded])
	assert(mission.phase == TutorialMission.Phase.GEAR, "Unexpected takeoff phase %s paused %s at %s" % [mission.phase, paused, p.position])
	assert(p.gear_down and not paused)
	p.toggle_landing_gear()
	p._update_gear(p.gear_travel_time * 0.5)
	assert(not p.landing_gear_retracted())
	mission._physics_process(1.0 / 60.0)
	assert(mission.phase == TutorialMission.Phase.GEAR)
	p._update_gear(p.gear_travel_time)
	await physics_frame
	await process_frame
	assert(mission.phase == TutorialMission.Phase.MOVEMENT_READING and paused)
	assert(mission.movement_practice.x >= mission.PRACTICE_SECONDS and mission.movement_practice.z >= mission.PRACTICE_SECONDS and mission.movement_practice.y == 0.0)
	mission.weapons.firing_enabled = true
	assert(mission.weapons._pilot_allows_fire("gun") and mission.weapons._pilot_allows_fire("missile"))
	p.toggle_landing_gear()
	assert(not mission.weapons._pilot_allows_fire("gun"), "Deployment blocks fire immediately")
	p.toggle_landing_gear()
	await _confirm()
	assert(mission.phase == TutorialMission.Phase.MOVEMENT)
	await physics_frame
	await _practice("roll_left")
	await _radio_until(TutorialMission.Phase.APPROACH)
	assert(not paused and not hud.tutorial_panel.visible, "Do not repeat throttle training after takeoff")
	assert(mission.acceleration_practice >= mission.PRACTICE_SECONDS)
	paused = false
	p.reset_player()
	assert(p.global_transform == spawn and p.speed == 0.0 and p.gear_extension == 1.0)
	arena.queue_free()
	await process_frame
	print("GROUND_DEPARTURE_CHECK_PASSED")


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
