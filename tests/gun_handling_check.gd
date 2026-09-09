extends SceneTree
## Run: godot --headless --path . --script tests/gun_handling_check.gd


func _initialize() -> void:
	_check.call_deferred()


func _check() -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	current_scene = scene
	var player = load("res://scenes/player/player.tscn").instantiate()
	player.position = Vector3(1.3, 2000, 0)
	scene.add_child(player)
	player.speed = 0.0
	var enemy = load("res://scenes/enemies/enemy_fighter.tscn").instantiate()
	enemy.position = Vector3(0, 2000, -50)
	scene.add_child(enemy)
	var ally = load("res://scenes/enemies/enemy_fighter.tscn").instantiate()
	ally.faction_group = "combat_allies"
	ally.position = Vector3(0, 2000, -150)
	scene.add_child(ally)
	for node in scene.find_children("*", "", true, false):
		node.set_physics_process(false)
	assert(ally.get_node("GunHitbox").collision_layer == 0)
	assert(enemy.get_node("GunHitbox").collision_layer == 16)
	assert(enemy.get_node("GunHitbox").collision_mask == 0)
	assert(not enemy.get_node("GunHitbox").monitoring)
	await physics_frame
	await physics_frame
	var query := PhysicsRayQueryParameters3D.create(Vector3(1.3, 2000, 0), Vector3(1.3, 2000, -100), 4)
	query.collide_with_areas = true
	query.collide_with_bodies = false
	var space := scene.get_world_3d().direct_space_state
	assert(space.intersect_ray(query).is_empty(), "Physical/missile hull must remain unchanged")
	query.collision_mask = 16
	assert(space.intersect_ray(query).collider == enemy.get_node("GunHitbox"), "Near miss gets gun-only forgiveness")
	query.from.x = 5.0
	query.to.x = 5.0
	assert(space.intersect_ray(query).is_empty(), "Padding is bounded, not an unlimited aim cone")
	var hud := CombatHUD.new()
	player._weapons.hit_confirmed.connect(hud._on_hit_confirmed)
	player._weapons.gun_overlap_enabled = false # Exercise the retained physical projectile path.
	player._weapons.gun_spread_degrees = 0.0
	player._weapons.fire_gun()
	assert(hud._hit_remaining == 0.0, "Firing alone must not show HIT")
	var bullet: Bullet
	for child in scene.get_children():
		if child is Bullet:
			bullet = child
	assert(bullet != null and bullet.target_layers == 20)
	bullet.tracer_visible = false
	var health: float = enemy.health
	bullet._physics_process(0.06)
	assert(enemy.health == health - player._weapons.gun_damage)
	assert(hud._hit_remaining == 0.25, "Player bullet damage confirms HIT")
	hud._hit_remaining = 0.0
	var missile: HomingMissile = load("res://scenes/weapons/missile.tscn").instantiate()
	missile.hit_callback = player._weapons.hit_confirmed.emit
	missile.damage = 1.0
	scene.add_child(missile)
	missile.launch(enemy.global_transform, Vector3.ZERO, enemy)
	assert(missile._check_target_proximity())
	assert(hud._hit_remaining == 0.25, "Missile damage confirms HIT")
	hud._hit_remaining = 0.0
	var carrier: HomingMissile = load("res://scenes/weapons/missile.tscn").instantiate()
	carrier.hit_callback = player._weapons.hit_confirmed.emit
	scene.add_child(carrier)
	carrier.configure_split_payload([enemy], 0.4, 12.0, 0.35, 0.0)
	carrier.launch(player.global_transform, Vector3.ZERO, null)
	carrier._release_payload()
	for child in scene.get_children():
		if child is HomingMissile and child != carrier and child != missile:
			assert(child.hit_callback == player._weapons.hit_confirmed.emit)
			child.global_position = enemy.global_position
			assert(child._check_target_proximity())
	assert(hud._hit_remaining == 0.25, "Split payload retains hit attribution")
	hud.free()
	assert(player._weapons.target_layers == 4, "Missile mask unchanged")
	assert(not player._weapons.gun_aim_assist_enabled)
	var small: float = player._precision_input(0.0, 0.2, 1.0)
	assert(small > 0.0 and small < 0.1)
	assert(is_equal_approx(player._precision_input(0.0, -0.2, 1.0), -small))
	assert(is_equal_approx(player._precision_input(0.0, 1.0, 1.0), 1.0))
	var first: float = player._precision_input(0.0, 1.0, 1.0 / 60.0)
	assert(first > 0.0 and first < 0.2)
	assert(is_zero_approx(player._precision_input(first, 0.0, player.control_release_time)))
	for pair in [["yaw_left", "roll_left"], ["yaw_right", "roll_right"],
		["yaw_left", "switch_missile"], ["yaw_right", "switch_missile"]]:
		for yaw_event in InputMap.action_get_events(pair[0]):
			for roll_event in InputMap.action_get_events(pair[1]):
				if yaw_event is InputEventKey and roll_event is InputEventKey:
					assert(yaw_event.physical_keycode != roll_event.physical_keycode)
	enemy.apply_damage(enemy.health)
	assert(enemy.get_node("GunHitbox").collision_layer == 0)
	scene.queue_free()
	await process_frame
	print("Gun handling checks passed: padding, teams, real bullet, missile isolation, input curve/ramp, keyboard")
	quit()
