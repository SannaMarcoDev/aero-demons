extends SceneTree
## Run: godot --headless --path . --script scripts/tests/explosion_contract_check.gd

func _initialize() -> void:
	call_deferred("_run_checks")


func _fail(message: String) -> void:
	printerr("FAIL: ", message)
	quit(1)


func _run_checks() -> void:
	# 1. Player script and scene actual instantiation
	var player_script = load("res://scripts/player/player_flight.gd") as Script
	if player_script == null or not player_script.can_instantiate():
		_fail("Could not load or cannot instantiate res://scripts/player/player_flight.gd")
		return
	var player_script_instance = player_script.new()
	if player_script_instance == null:
		_fail("Could not instantiate PlayerFlight script via .new()")
		return
	player_script_instance.free()

	var player_scene = load("res://scenes/player/player.tscn") as PackedScene
	if player_scene == null or not player_scene.can_instantiate():
		_fail("Could not load or cannot instantiate res://scenes/player/player.tscn")
		return

	var player = player_scene.instantiate()
	if player == null:
		_fail("Could not instantiate player.tscn")
		return
	root.add_child(player)

	# 2. Missile script and scene actual instantiation
	var missile_script = load("res://scripts/weapons/missile.gd") as Script
	if missile_script == null or not missile_script.can_instantiate():
		_fail("Could not load or cannot instantiate res://scripts/weapons/missile.gd")
		return
	var missile_script_instance = missile_script.new()
	if missile_script_instance == null:
		_fail("Could not instantiate HomingMissile script via .new()")
		return
	missile_script_instance.free()

	var missile_scene = load("res://scenes/weapons/missile.tscn") as PackedScene
	if missile_scene == null or not missile_scene.can_instantiate():
		_fail("Could not load or cannot instantiate res://scenes/weapons/missile.tscn")
		return

	var missile = missile_scene.instantiate()
	if missile == null:
		_fail("Could not instantiate missile.tscn")
		return
	root.add_child(missile)

	# 3. ExplosionFX contract check (missile detonation scale)
	var spawn_pos := Vector3(12.0, 34.0, 56.0)
	var missile_exp: ExplosionFX = ExplosionFX.spawn(root, spawn_pos, 1.7)
	if missile_exp == null:
		_fail("ExplosionFX.spawn returned null for missile explosion")
		return

	if not is_equal_approx(missile_exp.overall_scale, 1.7):
		_fail("ExplosionFX.overall_scale not set to 1.7, got %f" % missile_exp.overall_scale)
		return

	if not missile_exp.scale.is_equal_approx(Vector3.ONE * 1.7):
		_fail("ExplosionFX.scale not applied correctly: %s" % str(missile_exp.scale))
		return

	if not missile_exp.global_position.is_equal_approx(spawn_pos):
		_fail("ExplosionFX.global_position mismatch: %s vs %s" % [str(missile_exp.global_position), str(spawn_pos)])
		return

	if not missile_exp.is_playing():
		_fail("ExplosionFX is not playing after spawn()")
		return

	# 4. ExplosionFX contract check (aircraft death scale)
	var aircraft_spawn_pos := Vector3(100.0, 200.0, -300.0)
	var aircraft_exp: ExplosionFX = ExplosionFX.spawn(root, aircraft_spawn_pos, 3.0)
	if aircraft_exp == null:
		_fail("ExplosionFX.spawn returned null for aircraft explosion")
		return

	if not is_equal_approx(aircraft_exp.overall_scale, 3.0):
		_fail("ExplosionFX overall_scale expected 3.0, got %f" % aircraft_exp.overall_scale)
		return

	if not aircraft_exp.scale.is_equal_approx(Vector3.ONE * 3.0):
		_fail("ExplosionFX scale not applied correctly for aircraft scale: %s" % str(aircraft_exp.scale))
		return

	if not aircraft_exp.global_position.is_equal_approx(aircraft_spawn_pos):
		_fail("ExplosionFX aircraft position mismatch: %s vs %s" % [str(aircraft_exp.global_position), str(aircraft_spawn_pos)])
		return

	if not aircraft_exp.is_playing():
		_fail("ExplosionFX aircraft instance is not playing")
		return

	# 5. Exercise auto_free and finished signal via _on_lifetime_timer_timeout
	if not missile_exp.auto_free:
		_fail("ExplosionFX.auto_free should be true by default")
		return

	var finished_signal_received := [false]
	missile_exp.finished.connect(func(): finished_signal_received[0] = true)
	missile_exp._on_lifetime_timer_timeout()

	if not finished_signal_received[0]:
		_fail("ExplosionFX did not emit finished signal on timeout")
		return

	if missile_exp.is_playing():
		_fail("ExplosionFX is still marked playing after timeout")
		return

	# Stop aircraft explosion and queue free remaining instances
	aircraft_exp.stop_immediately()
	aircraft_exp.queue_free()
	missile.queue_free()
	player.queue_free()

	# Wait for frame processing to ensure queue_free finishes
	await process_frame
	await process_frame

	if is_instance_valid(missile_exp):
		_fail("missile_exp still valid after auto_free queue_free and process_frame")
		return
	if is_instance_valid(aircraft_exp):
		_fail("aircraft_exp still valid after queue_free and process_frame")
		return
	if is_instance_valid(missile):
		_fail("missile still valid after queue_free and process_frame")
		return
	if is_instance_valid(player):
		_fail("player still valid after queue_free and process_frame")
		return

	print("Explosion contract & player/missile load check: PASS")
	quit(0)
