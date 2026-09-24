extends SceneTree
## node tools/run_godot_check.cjs 90 LOG GODOT --headless --path . --fixed-fps 60 --script tests/tutorial_mission_check.gd
## Runs the production mission/cameras with the real hangar and a lightweight ground collider.
var arena: Node3D
var mission: TutorialMission
var hud: CombatHUD
var shots: Dictionary = {}
var handoffs := 0


func _initialize() -> void:
	_run.call_deferred()


func _load_mission() -> void:
	arena = load("res://scenes/levels/tutorial.tscn").instantiate()
	arena.set_script(null)
	var hangar := arena.get_node("GardaLake/Airport/SmallHangars/S01_SmallHangar")
	hangar.get_parent().remove_child(hangar)
	arena.get_node("GardaLake").free()
	arena.get_node("HorizonGraphics").free()
	var parent := arena
	for node_name in ["GardaLake", "Airport", "SmallHangars"]:
		var node := Node3D.new()
		node.name = node_name
		parent.add_child(node)
		parent = node
	parent.add_child(hangar)
	var ground := StaticBody3D.new()
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(100000, 2, 100000)
	collider.shape = shape
	ground.add_child(collider)
	ground.position.y = 233.52
	arena.add_child(ground)
	root.add_child(arena)
	current_scene = arena
	hud = arena.get_node("CombatHUD")
	mission = hud.mission_controller
	mission.flight_training_completed.connect(func(): handoffs += 1)


func _tick() -> void:
	await physics_frame
	await process_frame
	shots[mission.cinematic.shot] = true


func _confirm() -> void:
	for frame in 3:
		await process_frame
	var event := InputEventAction.new()
	event.action = "ui_accept"
	event.pressed = true
	Input.action_press("ui_accept")
	hud._unhandled_input(event)
	await process_frame
	Input.action_release("ui_accept")
	for frame in 4:
		await process_frame


func _run() -> void:
	_load_mission()
	for frame in 4000:
		await _tick()
		if mission.phase == TutorialMission.Phase.TAKEOFF:
			break
	assert(mission.phase == TutorialMission.Phase.TAKEOFF, "Intro must hand off on runway")
	assert(mission.cinematic.completed and not mission.cinematic.active)
	assert(not hud.cinematic_mode and mission.player.controls_enabled)
	assert(get_nodes_in_group("targets").is_empty())
	assert(mission.player.global_position.distance_to(mission.runway.global_position) < 6.0)
	for name in ["hangar_detail", "hangar_airframe", "hangar_door", "hangar_tracking", "runway"]:
		assert(shots.has(name), "Missing intro shot " + name)
	var p := mission.player
	Input.action_press("accelerate")
	for tick in 2400:
		if p.speed >= p.rotation_speed and p.rotation.x < deg_to_rad(9.0):
			Input.action_press("pitch_up", 0.45)
		else:
			Input.action_release("pitch_up")
		await _tick()
		if mission.phase == TutorialMission.Phase.GEAR:
			break
	Input.action_release("accelerate")
	Input.action_release("pitch_up")
	assert(mission.phase == TutorialMission.Phase.GEAR, "Real takeoff must reach safe altitude")
	assert(p.gear_down)
	p.toggle_landing_gear()
	for frame in 200:
		await _tick()
		if mission.phase == TutorialMission.Phase.FLIGHT:
			break
	assert(mission.phase == TutorialMission.Phase.FLIGHT)
	assert(mission.radio.playing and not paused)
	assert(mission.wings.all(func(wing): return wing.visible and not wing.is_physics_processing()))
	# Pause must stop camera/formation motion, dialogue, and mission progression together.
	hud._open_pause_menu()
	var before := p.global_transform
	var time_before := mission._formation_time
	for frame in 10:
		await process_frame
	assert(p.global_transform == before and mission._formation_time == time_before)
	hud._on_resume_pressed()
	for frame in 5:
		await _tick()
	assert(not paused)
	# Conversation alone must not bypass the exercise gate.
	mission.radio.minimum_line_seconds = 0.01
	mission.radio.seconds_per_character = 0.0001
	for frame in 1000:
		await _tick()
		if mission._conversation_finished:
			break
	assert(mission._conversation_finished and mission.phase == TutorialMission.Phase.FLIGHT)
	for action in ["roll_left", "yaw_right"]:
		Input.action_press(action, 0.3)
		for frame in 28:
			await _tick()
		Input.action_release(action)
		await _tick()
	for frame in 2000:
		await _tick()
		if paused:
			break
	assert(mission.phase == TutorialMission.Phase.TARGET_READING and paused, "Reveal did not finish: phase=%s practice=%s shot=%s altitude=%s gear=%s" % [mission.phase, mission.movement_practice, mission.cinematic.shot, p.position.y, p.landing_gear_retracted()])
	assert(handoffs == 1 and mission.remaining == 4 and mission.active_enemies.size() == 4)
	assert(get_nodes_in_group("targets").size() == 4)
	assert(mission.cinematic.escorts.size() == 6)
	assert(not hud.cinematic_mode and not mission.cinematic.active)
	assert(not mission.director.allow_player_attacks and not mission.weapons.firing_enabled)
	for name in ["sphere", "interceptors", "combat_handoff"]:
		assert(shots.has(name), "Missing reveal shot " + name)
	before = p.global_transform
	await _confirm()
	assert(paused and mission.phase == TutorialMission.Phase.MISSILE_READING)
	await _confirm()
	assert(paused and mission.phase == TutorialMission.Phase.GUN_READING)
	assert(p.global_transform == before, "No flight between weapons panels")
	await _confirm()
	assert(not paused and mission.phase == TutorialMission.Phase.COMBAT)
	assert(not p.invulnerable and mission.weapons.firing_enabled)
	assert(mission.director.allow_player_attacks)
	for enemy in mission.active_enemies:
		assert(enemy.is_physics_processing() and enemy.assignment_target != null)
	var victims := mission.active_enemies.duplicate()
	for enemy in victims:
		enemy.apply_damage(enemy.health)
		mission._on_enemy_destroyed(enemy) # Duplicate callbacks cannot double count.
	assert(mission.remaining == 0 and mission.terminal and paused)
	assert(hud._mission_title.text == "MISSIONE COMPLETATA")
	assert(not mission.radio.playing)
	paused = false
	arena.queue_free()
	await process_frame
	# Fresh retry must restore intro, hidden wingmen and locked weapons.
	_load_mission()
	await _tick()
	assert(mission.phase == TutorialMission.Phase.OPENING and not mission.terminal)
	assert(not mission.player.controls_enabled and not mission.weapons.firing_enabled)
	assert(get_nodes_in_group("targets").is_empty())
	arena.queue_free()
	await process_frame
	for audio in root.get_node("AudioManager").get_children():
		if audio is AudioStreamPlayer:
			audio.stop()
			audio.stream = null
	# Fixed-fps runs faster than the audio mixer: give queued playback teardown wall time.
	var flush_until := Time.get_ticks_msec() + 600
	while Time.get_ticks_msec() < flush_until:
		await process_frame
		OS.delay_msec(10)
	print("PASS: cinematic tutorial: intro, takeoff, formation, pause, conversation gate, 10 escorts / 4 interceptors, weapons panels, victory and retry")
	quit()
