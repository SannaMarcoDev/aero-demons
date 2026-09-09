extends SceneTree
## Run: godot --headless --path . --script tests/flight_inertia_check.gd


func _initialize() -> void:
	var player := PlayerFlight.new()
	var enemy := EnemyFighter.new()
	for aircraft in [player, enemy]:
		aircraft.speed = aircraft.cruise_speed
		aircraft.pitch_input = -1.0
		aircraft._apply_rotation(1.0 / 60.0)
		assert(is_equal_approx(aircraft._angular_velocity.x, 0.75))
		for tick in 59:
			aircraft._apply_rotation(1.0 / 60.0)
		assert(is_equal_approx(aircraft._angular_velocity.x, 32.0))
	assert(player.basis.is_equal_approx(enemy.basis), "Player and AI share the same inertia")
	player.pitch_input = 1.0
	player._apply_rotation(1.0 / 60.0)
	assert(player._angular_velocity.x > 30.0, "Cannot reverse rotation in one tick")
	player.pitch_input = 0.0
	for tick in 60:
		player._apply_rotation(1.0 / 60.0)
	assert(is_zero_approx(player._angular_velocity.x), "Release must settle, not drift forever")
	var settled := player.basis
	player._apply_rotation(0.5)
	assert(player.basis.is_equal_approx(settled))
	player.pitch_input = -1.0
	player.high_g_active = true
	for tick in 120:
		player._apply_rotation(1.0 / 60.0)
	assert(is_equal_approx(player._angular_velocity.x, 44.8))
	player.free()
	enemy.free()
	var reference := Basis.IDENTITY
	for hz in [30, 60, 120]:
		var aircraft := PlayerFlight.new()
		aircraft.pitch_input = -1.0
		for tick in hz * 2:
			aircraft._apply_rotation(1.0 / hz)
		if hz == 30:
			reference = aircraft.basis
		else:
			assert(reference.is_equal_approx(aircraft.basis), "Pitch ramp should not depend on physics tick rate")
		aircraft.free()
	print("Flight inertia checks passed: shared AI/player rates, ramp, reversal, settling, High-G, 30/60/120 Hz")
	quit()
