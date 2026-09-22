extends SceneTree
## Run: godot --headless --path . --script tests/level_flight_check.gd


func _initialize() -> void:
	_run.call_deferred()


func _level_ticks(aircraft: PlayerFlight, ticks: int) -> void:
	for tick in ticks:
		aircraft._level_flight_inputs()
		aircraft._apply_rotation(1.0 / 60.0)


func _assert_level(aircraft: PlayerFlight, label: String) -> void:
	assert(aircraft.global_basis.y.dot(Vector3.UP) > 0.995, label + ": wings must end upright")
	assert(absf(aircraft.global_basis.z.y) < 0.02, label + ": nose must end on the horizon")


func _run() -> void:
	var player := PlayerFlight.new()
	# Bare airframe: a non-player faction skips the catalog/gear wiring in _ready.
	player.faction_group = "check"
	root.add_child(player)
	player.speed = player.cruise_speed

	# Combo detection: accelerate+brake together engages the autopilot in flight.
	Input.action_press("accelerate")
	Input.action_press("brake")
	player._update_controls()
	assert(player.level_flight_active, "both triggers held must engage level flight")
	assert(player.throttle_input == 0.0 and player.brake_input == 0.0)
	assert(player.yaw_input == 0.0)
	# On the ground the same buttons stay taxi throttle and wheel brake.
	player.grounded = true
	player._update_controls()
	assert(not player.level_flight_active, "grounded aircraft must not level")
	assert(player.throttle_input == 1.0 and player.brake_input == 1.0)
	player.grounded = false
	Input.action_release("accelerate")
	Input.action_release("brake")
	player._update_controls()
	assert(not player.level_flight_active, "releasing the combo hands control back")

	# Banked and diving: the recovery ends wings-upright with the nose on the horizon.
	player.basis = Basis.from_euler(Vector3(deg_to_rad(-35.0), 0.0, deg_to_rad(70.0)))
	player._angular_velocity = Vector3.ZERO
	_level_ticks(player, 600)
	_assert_level(player, "banked dive")

	# Inverted: shortest roll back to belly-down, heading preserved.
	player.basis = Basis.from_euler(Vector3(0.0, deg_to_rad(40.0), PI))
	player._angular_velocity = Vector3.ZERO
	var heading := Vector2(player.basis.z.x, player.basis.z.z)
	_level_ticks(player, 600)
	_assert_level(player, "inverted")
	var leveled_heading := Vector2(player.basis.z.x, player.basis.z.z)
	assert(leveled_heading.angle_to(heading) < deg_to_rad(5.0), "inverted recovery keeps heading")

	# Vertical dive has no heading: the canopy fallback still pulls the nose out.
	player.basis = Basis.looking_at(Vector3.DOWN, Vector3.BACK)
	player._angular_velocity = Vector3.ZERO
	_level_ticks(player, 600)
	_assert_level(player, "vertical dive")

	# Neutral throttle during the combo drifts speed back to cruise.
	player.speed = player.min_speed
	var before := player.speed
	player._apply_flight(1.0 / 60.0)
	assert(player.speed > before, "neutral throttle must drift toward cruise")

	# Pause/clear and reset both drop the maneuver flag.
	player.level_flight_active = true
	player.clear_player_controls()
	assert(not player.level_flight_active)
	player.level_flight_active = true
	player.reset_flight(Transform3D.IDENTITY)
	assert(not player.level_flight_active)

	player.queue_free()
	var audio_manager := root.get_node_or_null("AudioManager")
	if audio_manager != null:
		for audio in audio_manager.get_children():
			if audio is AudioStreamPlayer:
				audio.stop()
				audio.stream = null
	await process_frame
	await process_frame
	print("PASS: level flight combo, ground gate, banked/inverted/vertical recovery, cruise drift, flag reset")
	quit()
