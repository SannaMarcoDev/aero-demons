extends SceneTree
## godot --headless --path . --script tests/dogfight_simulation_check.gd --fixed-fps 60
## Exercise live decision/flight/weapon ordering for 4, 6 and 1 enemies, not handcrafted states.

var gun_shots := {"targets": 0, "allies": 0}
var launches := {"targets": 0, "allies": 0}
var visited: Dictionary = {}


func _initialize() -> void:
	call_deferred("_check")


func _check() -> void:
	seed(7)
	for count in [4, 6, 1]:
		gun_shots = {"targets": 0, "allies": 0}
		launches = {"targets": 0, "allies": 0}
		visited.clear()
		var arena: Node3D = load("res://scenes/levels/tutorial.tscn").instantiate()
		arena.set_script(null)
		arena.get_node("GardaLake").free()
		if arena.has_node("CombatHUD"): arena.get_node("CombatHUD").free()
		if count == 1:
			# Final one-on-one also works when both wingmen have already been lost.
			arena.get_node("Wingman1").free()
			arena.get_node("Wingman2").free()
			for index in range(2, 5):
				arena.get_node("EnemyFighter%d" % index).free()
		if count == 6:
			for index in range(5, 7):
				var extra: EnemyFighter = load("res://scenes/enemies/enemy_fighter.tscn").instantiate()
				extra.name = "EnemyFighter%d" % index
				extra.position = Vector3((index - 5.5) * 2000, 2100, -2500)
				arena.add_child(extra)
		root.add_child(arena)
		current_scene = arena
		var director: CombatDirector = arena.get_node("CombatDirector")
		var player: PlayerFlight = arena.get_node("Player")
		player.set_physics_process(false)
		for pilot: EnemyFighter in get_nodes_in_group("combat_ai"):
			pilot._weapons.gun_fired.connect(_gun.bind(pilot.faction_group))
			pilot._weapons.missile_launched.connect(_missile.bind(pilot.faction_group))
		var relief_ticks := 0
		var reachable_ticks := 0
		for tick in 3600:
			await physics_frame
			# A passive player flies straight; actual weapons may destroy it. No health overrides.
			if player.is_alive():
				player._apply_flight(1.0 / 60.0)
			if director.mode == CombatDirector.Mode.RELIEF:
				relief_ticks += 1
			assert(director.active_player_missiles() <= director.max_player_missiles)
			assert(director.permissions.size() <= director.max_player_attackers)
			if CombatDirector.alive(player) and CombatDirector.alive(director.duel_opponent):
				if player.global_position.distance_to(director.duel_opponent.global_position) < director.duel_range:
					reachable_ticks += 1
			for pilot: EnemyFighter in get_nodes_in_group("combat_ai"):
				visited[pilot.state] = true
				assert(pilot.global_basis.is_finite() and pilot.global_position.is_finite())
				if pilot.is_alive():
					assert(pilot.speed >= pilot.min_speed and pilot.speed <= pilot.max_speed)
		assert(visited.has(EnemyFighter.State.ATTACK), "Live pilots must reach ATTACK")
		assert(visited.has(EnemyFighter.State.EXTEND), "Real passes must end")
		assert(launches["targets"] > 0, "Enemies must create actual missile threats")
		if count > 1:
			assert(launches["allies"] > 0 or gun_shots["allies"] > 0, "Wingmen must actually engage")
		assert(reachable_ticks > 60, "A duel must be within reach, not just named in the director")
		print("Dogfight simulation (%d enemies): guns=%s missiles=%s relief=%.1fs reachable=%.1fs player_hull=%.0f states=%s" % [
			count, gun_shots, launches, relief_ticks / 60.0, reachable_ticks / 60.0, player.health, visited.keys()])
		arena.queue_free()
		await process_frame
	print("Dogfight simulation check passed: 180 simulated seconds, 4/6/1 enemies, live weapons, bounded pressure, finite flight")
	quit()


func _gun(team: String) -> void:
	gun_shots[team] += 1


func _missile(_projectile: Node3D, team: String) -> void:
	launches[team] += 1
