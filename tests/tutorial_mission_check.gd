extends SceneTree
## godot --headless --path . --script tests/tutorial_mission_check.gd --fixed-fps 60
## Add -- --capture without --headless to check the real map and save HUD screenshots.

const LEVEL := preload("res://scenes/levels/tutorial.tscn")
var arena: Node3D
var mission: TutorialMission
var hud: CombatHUD
var radio: RadioDialogue
var spoken: Array[String] = []
var spawn_counts: Array[int] = []
var started := Time.get_ticks_msec()
var capture := "--capture" in OS.get_cmdline_user_args()


func _initialize() -> void:
	_run.call_deferred()


func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() - started > 120000:
		push_error("Tutorial mission check timed out")
		quit(1)
	return false


func _new_tutorial() -> void:
	arena = LEVEL.instantiate()
	if not capture:
		arena.set_script(null)
		arena.get_node("GardaLake").free()
		arena.get_node("HorizonGraphics").free()
	root.add_child(arena)
	current_scene = arena
	hud = arena.get_node("CombatHUD")
	mission = hud.mission_controller
	radio = mission.radio
	# Drive the production subtitle clock deterministically, without skipping dialogue parsing/events.
	radio.set_process(false)
	radio.line_shown.connect(_line_shown)
	_freeze_aircraft()
	assert(mission.remaining == 0 and get_nodes_in_group("targets").is_empty())
	assert(not mission.director.allow_player_attacks and not GameSession.free_flight)
	assert(hud.mode_label == "TUTORIAL" and not mission.player.invulnerable)
	for wing in [arena.get_node("Wingman1"), arena.get_node("Wingman2")]:
		wing.destroyed.connect(func(_aircraft): assert(false, "Tutorial wingmen must never be destroyed"))
	_check_wingman_protection()


func _check_wingman_protection() -> void:
	for number in [1, 2]:
		var wing: EnemyFighter = arena.get_node("Wingman%d" % number)
		assert(wing.invulnerable)
		wing.apply_damage(wing.max_health * 10.0)
		wing._hitbox.apply_damage(wing.max_health * 10.0)
		wing._on_solid_collision(null)
		wing.apply_napalm(1000.0, 1.0)
		wing._process(2.0)
		assert(wing.health == wing.max_health and mission.wing_alive(number))
		assert(wing._napalm_time == 0.0 and wing.state != EnemyFighter.State.DESTROYED)
		assert(wing.visible and wing._hitbox.collision_layer == 8 and not wing.is_queued_for_deletion())


func _freeze_aircraft() -> void:
	arena.get_node("Player").set_physics_process(false)
	for aircraft in get_nodes_in_group("combat_ai"):
		aircraft.set_physics_process(false)


func _line_shown(line: DialogueLine) -> void:
	spoken.append(line.character)
	if line.character.begins_with("Wing"):
		assert(mission.wing_alive(int(line.character.right(1))), "Dead wingmen must not speak")
	if not line.has_tag("spawn"):
		return
	_freeze_aircraft()
	spawn_counts.append(mission.remaining)
	var markers: Node3D = arena.get_node("EnemySpawnMarkers/Encounter%d" % (mission.encounter_index + 1))
	assert(mission.remaining == markers.get_child_count())
	for enemy in mission.active_enemies:
		var marker: Marker3D = markers.get_node(NodePath(enemy.name))
		assert(enemy.global_transform.is_equal_approx(marker.global_transform))
		assert(enemy._spawn_transform.is_equal_approx(marker.global_transform), "Ready must see the authored spawn")
		assert(enemy.is_in_group("targets") and enemy.is_in_group("combat_ai") and not enemy.invulnerable)
		assert(hud._target_alive(enemy), "HUD and radar must see live spawned targets")
		assert(mission.player.global_position.distance_to(enemy.global_position) < CombatHUD.RADAR_RANGE)
		assert(enemy.director == mission.director and enemy.assignment_target != mission.player)
		enemy._weapons.gun_fired.connect(_enemy_fired.bind(enemy))
		enemy._weapons.missile_launched.connect(_enemy_launched.bind(enemy))
		assert(enemy.role not in ["PLAYER_DUEL", "PLAYER_PRESSURE"])
		if mission.wing_alive(1) or mission.wing_alive(2):
			assert(CombatDirector.alive(enemy.assignment_target) and enemy.assignment_target.is_in_group("allies"))
		else:
			assert(enemy.assignment_target == null)
	# Receiving the same displayed-line event twice must not create another group.
	mission._on_radio_line(line)
	assert(mission.remaining == markers.get_child_count())


func _tick_radio() -> void:
	radio._process(30.0)
	await process_frame


func _wait_for_wave(index: int) -> void:
	for frame in 100:
		if mission.encounter_index == index and mission.phase == TutorialMission.Phase.COMBAT:
			return
		assert(not mission.terminal)
		await _tick_radio()
	assert(false, "Expected encounter did not spawn")


func _kill_wave() -> void:
	var victims := mission.active_enemies.duplicate()
	for enemy in victims:
		enemy.apply_damage(enemy.health)
		mission._on_enemy_destroyed(enemy) # Duplicate notifications cannot underflow or advance twice.
	assert(mission.remaining == 0 and mission.active_enemies.is_empty())
	assert(not hud.mission_result_visible(), "No victory at a kill boundary, including the last wave")
	assert(victims.all(func(e): return is_instance_valid(e)), "Wreck lifetime must not hold up the mission")


func _run() -> void:
	var normal := CombatDirector.new()
	assert(normal.allow_player_attacks, "Other arenas retain the existing attack policy")
	normal.free()
	_new_tutorial()
	await _tick_radio()
	await _tick_radio()
	assert(radio.playing and radio.visible and not mission.terminal)
	await _capture("01_briefing")
	# Pausing the always-processing HUD must stop both subtitles and mission progression.
	hud._open_pause_menu()
	var line := radio.current_line
	var remaining_time := radio._remaining
	for frame in 5:
		await _tick_radio()
	assert(radio.current_line == line and radio._remaining == remaining_time)
	assert(mission.remaining == 0)
	hud._on_resume_pressed()
	await _wait_for_wave(0)
	await _capture("02_first_contact")
	await _check_attack_policy()
	# Exercise real AI/physics ordering too, not just manually requested attack permissions.
	for aircraft in get_nodes_in_group("combat_ai"):
		aircraft.set_physics_process(true)
	for tick in 360:
		await physics_frame
		for enemy in mission.active_enemies:
			assert(enemy.assignment_target != mission.player)
		assert(mission.player.active_missiles().is_empty())
	_freeze_aircraft()
	# Clear the whole first wave while its contact radio is still playing.
	assert(radio.playing)
	_kill_wave()
	await process_frame
	assert(mission.encounter_index == 0 and radio.playing)
	_check_wingman_protection()
	await _wait_for_wave(1)
	await _capture("03_second_contact")
	assert(spawn_counts == [2, 4])
	_check_wingman_protection()
	_kill_wave()
	var before_last_contact := spoken.size()
	await _wait_for_wave(2)
	await _capture("04_final_contact")
	assert(spawn_counts == [2, 4, 8])
	assert(spoken.slice(before_last_contact).has("Wing 2"))
	assert(mission.director.permissions.is_empty())
	_kill_wave()
	for frame in 100:
		if mission.phase == TutorialMission.Phase.OUTRO:
			break
		await _tick_radio()
	assert(mission.phase == TutorialMission.Phase.OUTRO and not mission.terminal and radio.playing)
	await _tick_radio()
	await _capture("05_final_radio")
	for frame in 100:
		if mission.terminal:
			break
		await _tick_radio()
	assert(mission.terminal and paused and hud._mission_title.text == "MISSIONE COMPLETATA")
	_check_wingman_protection()
	assert(not radio.playing and not radio.visible and spawn_counts == [2, 4, 8])
	await _capture("06_completed")
	paused = false
	arena.queue_free()
	await process_frame

	# Fresh runs start empty; defeat must cancel even a pending asynchronous dialogue read.
	for after_first_wave in [false, true]:
		_new_tutorial()
		await _tick_radio()
		if after_first_wave:
			await _wait_for_wave(0)
			_kill_wave()
		else:
			radio._process(30.0)
		mission.player.apply_damage(1000.0)
		var spawned := mission.spawn_root.get_child_count()
		for frame in 10:
			await _tick_radio()
		assert(mission.terminal and paused and hud._mission_title.text == "MISSIONE FALLITA")
		assert(not radio.playing and not radio.visible)
		assert(mission.spawn_root.get_child_count() == spawned, "No delayed spawns after defeat")
		paused = false
		arena.queue_free()
		await process_frame
	print("Tutorial mission check passed: 2/4/8, marker transforms, radio/radar sync, no player attacks, immortal wingmen (damage, hitbox, collision, napalm), pause, defeat, final radio before victory")
	quit()


func _check_attack_policy() -> void:
	var player := mission.player
	var enemy := mission.active_enemies[0]
	var saved_player := player.global_transform
	var saved_enemy := enemy.global_transform
	var saved_speed := player.speed
	enemy.global_position = player.global_position + Vector3(0, 0, 300)
	enemy.global_basis = Basis.IDENTITY
	player.speed = 0.0
	enemy.assign("PLAYER_PRESSURE", player)
	enemy._set_state(EnemyFighter.State.ATTACK, "TEST")
	enemy._state_time = 2.0
	enemy._burst_time = 0.1
	enemy._gun_stable_time = 1.0
	enemy._missile_stable_time = 1.0
	enemy.safety_active = false
	enemy._targeting._physics_process(3.0)
	assert(not mission.director.request_attack(enemy))
	mission.director.permissions[enemy] = mission.director.clock + 30.0
	assert(not mission.director.has_permission(enemy), "Stale permissions cannot bypass the tutorial rule")
	for kind in ["gun", "missile"]:
		assert(enemy.weapon_fire_block(kind) == "NO_ATTACK_PERMISSION")
	var gun_ammo := enemy._weapons.gun_ammo
	var missile_ammo := enemy._weapons.missile_ammo
	enemy._weapons.fire_gun()
	enemy._weapons.fire_missile()
	assert(enemy._weapons.gun_ammo == gun_ammo and enemy._weapons.missile_ammo == missile_ammo)
	assert(player.active_missiles().is_empty() and player.health == player.max_health)

	# Enemies still fire at wingmen: protection must not disable targeting or weapon behavior.
	var wing: EnemyFighter = arena.get_node("Wingman1")
	var saved_wing := wing.global_transform
	var saved_wing_speed := wing.speed
	wing.global_position = enemy.global_position - Vector3(0, 0, 220)
	wing.speed = 0.0
	enemy.assign("ENGAGE_WINGMAN", wing)
	enemy._set_state(EnemyFighter.State.ATTACK, "TEST")
	enemy._state_time = 2.0
	enemy._gun_stable_time = 1.0
	enemy._missile_stable_time = 1.0
	enemy._targeting._physics_process(3.0)
	enemy._weapons._gun_cooldown = 0.0
	enemy._weapons._missile_cooldown = 0.0
	assert(mission.director.request_attack(enemy))
	await physics_frame
	await physics_frame
	assert(enemy.weapon_fire_block("gun") == "READY", enemy.weapon_fire_block("gun"))
	enemy._weapons.fire_gun()
	enemy._weapons.fire_missile()
	assert(enemy._weapons.gun_ammo == gun_ammo - 1)
	assert(enemy._weapons.missile_ammo == missile_ammo - 1 and wing.active_missiles().size() == 1)
	assert(player.active_missiles().is_empty())
	for projectile in get_nodes_in_group("mission_projectiles"):
		projectile.queue_free()
	wing.global_transform = saved_wing
	wing.speed = saved_wing_speed
	player.global_transform = saved_player
	player.speed = saved_speed
	enemy.global_transform = saved_enemy
	mission.director._assign_roles()
	assert(enemy.assignment_target != player)


func _enemy_fired(enemy: EnemyFighter) -> void:
	assert(enemy.assignment_target != mission.player, "No cannon passes against the tutorial player")


func _enemy_launched(missile: HomingMissile, enemy: EnemyFighter) -> void:
	_enemy_fired(enemy)
	assert(not mission.player.active_missiles().has(missile), "No missile may track the tutorial player")


func _capture(stem: String) -> void:
	if not capture or DisplayServer.get_name() == "headless":
		return
	await process_frame
	await RenderingServer.frame_post_draw
	var directory := "user://tutorial_mission_check"
	DirAccess.make_dir_recursive_absolute(directory)
	assert(root.get_texture().get_image().save_png(directory.path_join(stem + ".png")) == OK)
