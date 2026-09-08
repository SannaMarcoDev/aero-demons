extends SceneTree
## Run: godot --headless --path . --script tests/enemy_fighter_check.gd
## Real freeroam aircraft/weapon scenes, without loading the terrain into the physics world.

var arena: Node3D
var player: PlayerFlight
var director: CombatDirector
var enemies: Array[EnemyFighter] = []
var allies: Array[EnemyFighter] = []


class Ridge extends RefCounted:
	func get_height(point: Vector3) -> float:
		return 1900.0 if point.z < -200.0 else 0.0


func _initialize() -> void:
	call_deferred("_check")


func _check() -> void:
	seed(1)
	var session = load("res://scripts/ui/game_session.gd")
	var saved_loadout: Array[String] = session.selected_missiles.duplicate()
	session.selected_missiles.assign(["HSSTDM", "STDM"])
	arena = load("res://scenes/levels/tutorial.tscn").instantiate()
	arena.set_script(null)
	arena.get_node("GardaLake").free()
	if arena.has_node("CombatHUD"):
		arena.get_node("CombatHUD").free()
	root.add_child(arena)
	current_scene = arena
	player = arena.get_node("Player")
	director = arena.get_node("CombatDirector")
	director.set_physics_process(false)
	player.set_physics_process(false)
	player._targeting.set_physics_process(false)
	for pilot: EnemyFighter in get_nodes_in_group("combat_ai"):
		pilot.set_physics_process(false)
		pilot._targeting.set_physics_process(false)
		if pilot.faction_group == "targets":
			enemies.append(pilot)
		else:
			allies.append(pilot)
	assert(enemies.size() == 4 and allies.size() == 2)
	assert(player._weapons.equipped_missile_ids == session.selected_missiles)
	session.selected_missiles = saved_loadout
	for enemy in enemies:
		assert(enemy.is_in_group("targets") and not enemy.is_in_group("combat_allies"))
		assert(enemy._hitbox.collision_layer == 4 and enemy._weapons.target_layers == 8)
		assert(enemy._weapons.equipped_missile_ids == ["STDM"])
		assert(enemy.get_node("AircraftModel").scene_file_path == "res://assets/aircraft/aircraft_game_ready.glb")
		assert(enemy.find_children("*", "Camera3D", true, false).is_empty())
	for ally in allies:
		assert(ally.is_in_group("allies") and ally.is_in_group("combat_allies") and not ally.is_in_group("targets"))
		assert(ally._hitbox.collision_layer == 8 and ally._weapons.target_layers == 4)
	assert(player.is_in_group("combat_allies"))
	assert(player._targeting._get_candidates().all(func(p): return p not in allies))
	assert(director.duel_opponent == enemies[1])
	assert(enemies[0].role == "PLAYER_PRESSURE")
	assert(enemies[2].assignment_target == allies[0] and enemies[3].assignment_target == allies[1])
	var old_target := enemies[2].assignment_target
	director._assign_roles()
	assert(enemies[2].assignment_target == old_target)
	assert(allies[0].assignment_target != director.duel_opponent)
	assert(allies[1].assignment_target != director.duel_opponent)

	# Player interest selects the ongoing duel, but selection alone is not a defensive trigger.
	player._targeting._set_target(enemies[0])
	director._assign_roles()
	assert(director.duel_opponent == enemies[0])
	assert(enemies[0].state != EnemyFighter.State.DEFEND)
	# Roles are only assignments: permission is exclusive, expiring, and relief stops new passes.
	for enemy in enemies.slice(0, 2):
		enemy.assign("PLAYER_PRESSURE", player)
	assert(director.request_attack(enemies[0]))
	assert(not director.request_attack(enemies[1]))
	director._update_pressure(director.sustained_pressure_duration)
	assert(director.mode == CombatDirector.Mode.RELIEF)
	assert(director.has_permission(enemies[0]), "Existing passes are not frozen by relief")
	director.release_attack(enemies[0])
	assert(not director.request_attack(enemies[1]))
	director._update_pressure(director.relief_duration)
	assert(director.mode == CombatDirector.Mode.NORMAL and director.request_attack(enemies[1]))
	director.clock += director.permission_duration + 0.1
	assert(not director.has_permission(enemies[1]))

	# Clear the immediate area for deterministic flight/state and weapon checks.
	for index in enemies.size():
		enemies[index].position = Vector3(10000 + index * 1500, 2000, 0)
	for index in allies.size():
		allies[index].position = Vector3(-10000 - index * 1500, 2000, 0)
	var enemy := enemies[0]
	enemy.position = Vector3(0, 2000, 0)
	enemy.basis = Basis.IDENTITY
	player.position = Vector3(0, 2000, -1200)
	player.basis = Basis.IDENTITY
	enemy.assign("PLAYER_PRESSURE", player)
	enemy._set_state(EnemyFighter.State.SETUP_ATTACK, "TEST")
	enemy._tick_ai(0.1)
	assert(enemy.state == EnemyFighter.State.ATTACK)
	enemy._tick_ai(enemy.attack_duration + 0.1)
	assert(enemy.state == EnemyFighter.State.EXTEND)
	assert(not director.has_permission(enemy))
	var exit_direction := enemy._maneuver_direction
	player.position.x += 500
	enemy._tick_ai(0.1)
	assert(enemy._maneuver_direction == exit_direction, "EXTEND must not chase a moving target")
	enemy._tick_ai(enemy.extend_duration)
	assert(enemy.state == EnemyFighter.State.REPOSITION)
	# A target behind the nose and not aiming at us cannot sustain an infinite setup circle.
	player.position = Vector3(0, 2000, 1000)
	player.basis = Basis(Vector3.UP, PI)
	enemy._set_state(EnemyFighter.State.SETUP_ATTACK, "TEST")
	enemy._tick_ai(0.1)
	enemy._tick_ai(enemy.setup_stall_duration + 0.1)
	assert(enemy.state == EnemyFighter.State.EXTEND and enemy.last_transition == "NO_PROGRESS")

	player.basis = Basis.IDENTITY
	enemy._evade_blocked_until = 0.0
	enemy._tick_ai(0.1)
	assert(enemy.state == EnemyFighter.State.DEFEND)
	enemy._tick_ai(enemy.defend_duration + 0.1)
	assert(enemy.state == EnemyFighter.State.RECOVER)
	enemy._tick_ai(0.5)
	assert(enemy.state == EnemyFighter.State.RECOVER, "Persistent pursuit must not cancel recovery")
	enemy._tick_ai(enemy.recover_duration)
	assert(enemy.state == EnemyFighter.State.REPOSITION)
	var start := enemy.position
	for tick in 120:
		enemy._physics_process(1.0 / 60.0)
	assert(enemy.position.distance_to(start) > 100.0 and enemy.global_basis.is_finite())
	assert(enemy.speed >= enemy.min_speed and enemy.speed <= enemy.max_speed)

	# Cover interrupts a distant chase for a real tail threat; the offensive wing avoids the duel.
	player.position = Vector3(0, 2000, 0)
	player.basis = Basis.IDENTITY
	enemy.position = Vector3(0, 2000, 800)
	enemy.basis = Basis.IDENTITY
	allies[0].position = Vector3(-200, 2000, 0)
	director._assign_roles()
	assert(director.most_dangerous_to(player) == enemy)
	assert(allies[0].assignment_target == enemy)
	allies[0].position = Vector3(-10000, 2000, 0)
	allies[0]._tick_ai(0.1)
	assert(allies[0]._outside_leash() and allies[0].state == EnemyFighter.State.REPOSITION)

	# Terrain ahead (not only under the aircraft) overrides the final control and inhibits fire.
	_setup_attack(enemy, player)
	enemy._terrain_data = Ridge.new()
	enemy._apply_safety()
	assert(enemy.safety_active and enemy.pitch_input < 0.0 and enemy.throttle_input > 0.0)
	assert(enemy.weapon_fire_block("gun") == "SAFETY_MANEUVER")
	enemy._terrain_data = null
	# Real gun fire through the shared controller, not direct apply_damage pretending to be combat.
	_setup_attack(enemy, player)
	enemy._weapons.gun_spread_degrees = 0.0
	await physics_frame
	await physics_frame
	_arm(enemy)
	# A friendly airframe on the initial trajectory blocks both AI weapon paths.
	enemies[2].position = Vector3(0, 2000, -100)
	await physics_frame
	await physics_frame
	assert(enemy.weapon_fire_block("gun") == "TRAJECTORY_BLOCKED")
	enemies[2].position = Vector3(13000, 2000, 0)
	await physics_frame
	await physics_frame
	assert(enemy.weapon_fire_block("gun") == "READY", enemy.weapon_fire_block("gun"))
	var ammo := enemy._weapons.gun_ammo
	enemy._weapons.fire_gun()
	assert(enemy._weapons.gun_ammo == ammo - 1)
	for tick in 20:
		await physics_frame
	assert(player.health < player.max_health, "Enemy cannon must really damage the player")

	# Launch budget is checked on the real weapon boundary, including direct fire_missile calls.
	_arm(enemy)
	enemy._weapons.fire_missile()
	assert(player.active_missiles().size() == 1)
	var first: HomingMissile = player.active_missiles()[0]
	first.set_physics_process(false)
	enemy._weapons._missile_cooldown = 0.0
	enemy._weapons.fire_missile()
	assert(player.active_missiles().size() == 2)
	var second: HomingMissile = player.active_missiles()[1]
	second.set_physics_process(false)
	enemy._weapons._missile_cooldown = 0.0
	var missile_ammo := enemy._weapons.missile_ammo
	enemy._weapons.fire_missile()
	assert(enemy._weapons.missile_ammo == missile_ammo)
	assert(enemy.weapon_fire_block("missile") == "MISSILE_LIMIT")
	enemy.apply_damage(enemy.health)
	assert(enemy.state == EnemyFighter.State.DESTROYED)
	assert(not director.has_permission(enemy) and director.active_player_missiles() == 2)
	assert(enemy.visible and not enemy._afterburners.visible and enemy._hitbox.collision_layer == 0)
	assert(not enemy._engine_audio.playing and not player._targeting._target_alive(enemy))
	first._lose_tracking()
	assert(director.active_player_missiles() == 1)
	second.lifetime = 0.01
	second._physics_process(0.1)
	assert(director.active_player_missiles() == 0, "Missiles expire even in a headless renderer")
	first.queue_free()
	second.queue_free()
	enemy._fall(enemy.wreck_explosion_interval)
	assert(enemy.wreck_cook_offs == 1)
	enemy._fall(enemy.wreck_max_fall_time)
	assert(enemy.is_queued_for_deletion())

	# Allied cannon uses the enemy layer. The player cannot lock or missile an ally.
	var ally := allies[1]
	var victim := enemies[3]
	player.position = Vector3(1000, 2000, 0)
	_setup_attack(ally, victim)
	ally._weapons.gun_spread_degrees = 0.0
	await physics_frame
	await physics_frame
	_arm(ally)
	assert(ally.weapon_fire_block("gun") == "READY", ally.weapon_fire_block("gun"))
	ally._weapons.fire_gun()
	for tick in 20:
		await physics_frame
	assert(victim.health < victim.max_health, "Wingmen must deal real damage")
	assert(not player._weapons._valid_missile_target(ally))
	# Recovery can be interrupted by an actually closing missile, with a reaction delay.
	var threat := HomingMissile.new()
	arena.add_child(threat)
	threat.position = ally.position + Vector3(0, 0, 300)
	threat.velocity = Vector3(0, 0, -500)
	ally.missile_incoming(threat)
	ally._set_state(EnemyFighter.State.RECOVER, "TEST")
	ally._tick_ai(0.1)
	assert(ally.state == EnemyFighter.State.RECOVER)
	ally._tick_ai(ally.missile_reaction_delay)
	assert(ally.state == EnemyFighter.State.EVADE_MISSILE)
	var break_direction := ally._maneuver_direction
	threat.position.x += 30
	ally._tick_ai(0.1)
	assert(ally._maneuver_direction == break_direction)
	ally.missile_cleared(threat)
	threat.queue_free()
	ally._tick_ai(0.1)
	assert(ally.state == EnemyFighter.State.RECOVER)

	# Target death/fewer enemies do not leave stale targets, roles, or permissions.
	for fighter in enemies:
		if is_instance_valid(fighter) and fighter != victim and fighter.is_alive():
			fighter.apply_damage(fighter.health)
	director._refresh_pilots()
	director._assign_roles()
	assert(director.duel_opponent == victim)
	assert(victim.assignment_target == player)
	assert(allies[0].assignment_target == victim and allies[1].assignment_target == victim)
	# Keep the optional physical cannon path covered; arcade overlap has its own check.
	player._weapons.gun_overlap_enabled = false
	ally.position = Vector3(-10000, 2000, 0)
	player.position = Vector3(0, 2000, 0)
	player.basis = Basis.IDENTITY
	player.speed = 0.0
	victim.position = Vector3(0, 2000, -150)
	victim.basis = Basis.IDENTITY
	player._targeting._set_target(victim)
	player._targeting._physics_process(3.0)
	player._weapons.gun_spread_degrees = 0.0
	await physics_frame
	await physics_frame
	var hull := victim.health
	player._weapons.fire_gun()
	for tick in 20:
		await physics_frame
	assert(victim.health < hull, "Player cannon still hits enemy hitboxes")
	victim.apply_damage(victim.health - 1.0)
	player._weapons.equip_missile("STDM")
	player._weapons.fire_missile()
	assert(victim.active_missiles().size() == 1)
	for tick in 60:
		await physics_frame
	assert(not victim.is_alive(), "Player missile must finish the opponent")
	director._refresh_pilots()
	director._assign_roles()
	assert(director.duel_opponent == null)
	assert(allies[0].assignment_target == null and allies[1].assignment_target == null)
	# With combat over, converge to moving left/right slots and match the player's speed.
	player.position = Vector3(0, 2000, 0)
	player.basis = Basis(Vector3.UP, 0.65)
	player.speed = player.cruise_speed
	for wing in allies:
		var side := -1.0 if wing.policy == EnemyFighter.Policy.COVER else 1.0
		wing.position = player.position + player.basis * Vector3(side * 350.0, 0, 350.0)
		wing.basis = player.basis
		wing._set_state(EnemyFighter.State.REPOSITION, "TEST_FORMATION", true)
	for tick in 1800:
		player._apply_flight(1.0 / 60.0)
		for wing in allies:
			wing._physics_process(1.0 / 60.0)
	for wing in allies:
		var side := -1.0 if wing.policy == EnemyFighter.Policy.COVER else 1.0
		var slot := player.position + player.basis.x * side * wing.formation_spacing
		assert(wing.position.distance_to(slot) < 60.0, "Wingman must hold its moving formation slot")
		assert(absf(wing.speed - player.speed) < 5.0)
		assert(not wing.gun_trigger and not wing.missile_trigger)
	director.debug_visible = true
	director._update_debug()
	assert("PLAYER_ATTACKERS" in director._debug_label.text and "FIRE_BLOCK" in director._debug_label.text)
	arena.queue_free()
	await process_frame
	print("Dogfight check passed: scene, teams, roles, permissions, relief, FSM, cover, real weapons, missile lifecycle, wrecks, debug")
	quit()


func _setup_attack(shooter: EnemyFighter, target: PlayerFlight) -> void:
	shooter.position = Vector3(0, 2000, 0)
	shooter.basis = Basis.IDENTITY
	shooter.speed = shooter.cruise_speed
	target.position = Vector3(0, 2000, -220)
	target.basis = Basis.IDENTITY
	target.speed = 0.0
	shooter.assign("PLAYER_PRESSURE" if target == player else "SUPPORT", target)
	shooter._set_state(EnemyFighter.State.ATTACK, "TEST")
	shooter._targeting._physics_process(3.0)


func _arm(shooter: EnemyFighter) -> void:
	assert(director.request_attack(shooter))
	shooter._state_time = 2.0
	shooter._burst_time = 0.1
	shooter._gun_stable_time = 1.0
	shooter._missile_stable_time = 1.0
	shooter.safety_active = false
	shooter._weapons._gun_cooldown = 0.0
	shooter._weapons._missile_cooldown = 0.0
