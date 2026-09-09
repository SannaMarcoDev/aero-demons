extends SceneTree
## godot --headless --path . --script tests/gun_overlap_check.gd


func _initialize() -> void:
	_check.call_deferred()


func _check() -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	current_scene = scene
	var player = load("res://scenes/player/player.tscn").instantiate()
	player.position.y = 2000.0
	scene.add_child(player)
	var enemy = load("res://scenes/enemies/enemy_fighter.tscn").instantiate()
	enemy.position = Vector3(0, 2000, -500)
	scene.add_child(enemy)
	for node in scene.find_children("*", "", true, false):
		node.set_physics_process(false)
	var camera: Camera3D = player.get_node("FlightCamera")
	camera.make_current()
	camera.snap_to_target()
	var weapons: WeaponController = player._weapons
	weapons._targeting._set_target(enemy)
	await physics_frame
	await physics_frame
	assert(weapons.gun_overlap_enabled)
	assert(not enemy._weapons.gun_overlap_enabled)
	assert(weapons._gun_pippers_overlap(enemy))
	var health: float = enemy.health
	for tick in 6:
		weapons.fire_gun()
		weapons._physics_process(1.0 / 60.0)
	assert(is_equal_approx(enemy.health, health - weapons.gun_damage), "Exactly one hit per 0.1 seconds")
	for child in scene.get_children():
		if child is Bullet:
			assert(child.damage == 0.0, "Player tracers must not double damage")
	weapons._update_gun_overlap(0.05, true)
	weapons._update_gun_overlap(0.01, false)
	weapons._update_gun_overlap(0.05, true)
	assert(is_equal_approx(enemy.health, health - weapons.gun_damage), "Release resets overlap")
	enemy.position.x = 400.0
	assert(not weapons._gun_pippers_overlap(enemy))
	weapons._update_gun_overlap(0.1, true)
	enemy.position.x = 0.0
	weapons._update_gun_overlap(0.05, true)
	assert(is_equal_approx(enemy.health, health - weapons.gun_damage), "Losing alignment resets overlap")
	weapons._update_gun_overlap(0.05, true)
	assert(is_equal_approx(enemy.health, health - 2.0 * weapons.gun_damage))
	var wall := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(100, 100, 10)
	collision.shape = box
	wall.add_child(collision)
	wall.position = Vector3(0, 2000, -250)
	scene.add_child(wall)
	await physics_frame
	await physics_frame
	assert(not weapons._gun_pippers_overlap(enemy), "No overlap damage through terrain")
	weapons._update_gun_overlap(0.5, true)
	assert(is_equal_approx(enemy.health, health - 2.0 * weapons.gun_damage))
	weapons.reset_loadout()
	assert(weapons._overlap_time == 0.0 and weapons._overlap_target == null)
	scene.queue_free()
	await process_frame
	print("Gun overlap checks passed: cadence, visual tracers, release, lost alignment, occlusion, reset, AI isolation")
	quit()
