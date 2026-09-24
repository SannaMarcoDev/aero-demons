extends Node3D
## Tutorial-only camera direction. Tweens and flight motion pause with the scene.
signal finished

const SPHERE = preload("res://scenes/vfx/energy_sphere.tscn")
var completed := false
var active := false
var shot := ""
var escorts: Array[EnemyFighter] = []
var interceptors: Array[EnemyFighter] = []
var _camera: Camera3D
var _black: ColorRect
var _radio: RadioDialogue
var _dialogue: DialogueResource
var _sphere: Node3D
var _convoy_direction := Vector3.RIGHT
var _forward := Vector3.FORWARD
var _right := Vector3.RIGHT
var _airborne := false
var _breaking := false
var _tracking := false
var _shake_time := 0.0
var _convoy_age := 0.0
var _hidden_overlays: Array[CanvasLayer] = []

@onready var player: PlayerFlight = get_node("../Player")
@onready var hud: CombatHUD = get_node("../CombatHUD")


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_camera = Camera3D.new()
	_camera.name = "CinematicCamera"
	_camera.far = 100000.0
	_camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(_camera)
	# Behind the HUD: radio and pause controls remain readable even over a fade.
	var overlay := CanvasLayer.new()
	overlay.layer = hud.layer - 1
	add_child(overlay)
	_black = ColorRect.new()
	_black.color = Color.BLACK
	_black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(_black)
	_black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_black.hide()


func _begin(radio: RadioDialogue, dialogue: DialogueResource) -> void:
	active = true
	_radio = radio
	_dialogue = dialogue
	player.controls_enabled = false
	player.clear_player_controls()
	player.set_physics_process(false)
	player.get_node("FlightCamera").set_physics_process(false)
	hud.set_cinematic(true)
	for child in get_parent().find_children("*", "CanvasLayer", true, false):
		if child != hud and not is_ancestor_of(child) and child.visible:
			_hidden_overlays.append(child)
			child.hide()
	_camera.global_transform = player.get_node("FlightCamera").global_transform
	_camera.fov = player.camera_fov
	_camera.make_current()


func _end() -> void:
	active = false
	_airborne = false
	_tracking = false
	_black.hide()
	var chase := player.get_node("FlightCamera")
	chase.snap_to_target()
	chase.make_current()
	chase.set_physics_process(true)
	player.clear_player_controls()
	player.set_physics_process(true)
	player.controls_enabled = true
	hud.set_cinematic(false)
	for overlay in _hidden_overlays:
		overlay.show()
	_hidden_overlays.clear()


func _fade(alpha: float, seconds := 0.65) -> void:
	_black.show()
	await create_tween().tween_property(_black, "modulate:a", alpha, seconds).finished


func _hold(seconds: float) -> void:
	await create_tween().tween_interval(seconds).finished


func _view(position_world: Vector3, target: Vector3, fov: float) -> void:
	_camera.global_position = position_world
	_camera.look_at(target)
	_camera.fov = fov


func play_intro(radio: RadioDialogue, dialogue: DialogueResource) -> void:
	_begin(radio, dialogue)
	var hangar: Node3D = get_node("../GardaLake/Airport/SmallHangars/S01_SmallHangar")
	var ground_ray := PhysicsRayQueryParameters3D.create(player.global_position, player.global_position - Vector3.UP * 20.0, 1)
	var ground_hit := get_world_3d().direct_space_state.intersect_ray(ground_ray)
	if not ground_hit.is_empty():
		player.global_position.y = ground_hit.position.y + 3.6 # Same wheel proxy clearance as PlayerFlight.
	var exit_direction: Vector3 = get_node("../Marker3D").global_position - player.global_position
	exit_direction.y = 0.0
	player.global_basis = Basis.looking_at(exit_direction.normalized())
	var start := player.global_transform
	shot = "hangar_detail"
	_view(start * Vector3(8, 2, -8), start * Vector3(0, 0, -3), 48.0)
	_black.modulate.a = 1.0
	await _fade(0.0)
	_radio.play(_dialogue, "intro")
	await _hold(4.0)
	shot = "hangar_airframe"
	_view(start * Vector3(-15, 4, -14), start.origin, 55.0)
	var pan := create_tween()
	pan.tween_method(func(t: float): _view(start * Vector3(-15, 4, -14).lerp(Vector3(-12, 3, 10), t), start.origin, 55.0), 0.0, 1.0, 5.0)
	await pan.finished
	shot = "hangar_door"
	_view(hangar.to_global(Vector3(-3, 4, 32)), hangar.to_global(Vector3(0, 2, 12)), 65.0)
	hangar.set_open(true)
	while hangar.openness < 0.999:
		await get_tree().physics_frame
	# Only the nose crosses the doorway before the side tracking shot.
	var nose_end := start.origin - start.basis.z * 10.0
	await create_tween().tween_property(player, "global_position", nose_end, 3.0).finished
	shot = "hangar_tracking"
	var exit_position := get_node("../Marker3D").global_position as Vector3
	exit_position.y = start.origin.y
	await create_tween().tween_method(func(t: float):
		player.global_position = nose_end.lerp(exit_position, t)
		var offset := Vector3(18, 2, -2).lerp(Vector3(0, 5, 28), smoothstep(0.0, 1.0, t))
		_view(player.global_position + start.basis * offset, player.global_position, 62.0)
	, 0.0, 1.0, 10.0).finished
	if _radio.playing:
		await _radio.finished
	await _fade(1.0)
	shot = "runway"
	var runway: Vector3 = get_node("../TaxiRunway").global_position
	var direction: Vector3 = get_node("../TaxiTakeoff").global_position - runway
	direction.y = 0.0
	runway.y += start.origin.y - get_node("../Marker3D").global_position.y
	player.reset_flight(Transform3D(Basis.looking_at(direction.normalized()), runway))
	player.camera_depth = 22.0
	player.get_node("FlightCamera").snap_to_target()
	_camera.global_transform = player.get_node("FlightCamera").global_transform
	_camera.fov = player.camera_fov
	await _fade(0.0)
	_end()
	completed = true
	finished.emit()


func play_reveal(radio: RadioDialogue, dialogue: DialogueResource, enemy_scene: PackedScene) -> void:
	_begin(radio, dialogue)
	shot = "reveal_fade"
	_black.modulate.a = 0.0
	await _fade(1.0)
	_forward = -player.global_basis.z
	_forward.y = 0.0
	if _forward.length_squared() < 0.01:
		_forward = Vector3.FORWARD
	_forward = _forward.normalized()
	var projected := player.global_position + _forward * 12000.0
	if Vector2(projected.x, projected.z).length() > player.return_distance:
		_forward = Vector3(-player.global_position.x, 0.0, -player.global_position.z).normalized()
	_right = _forward.cross(Vector3.UP)
	player.global_basis = Basis.looking_at(_forward)
	# The fade hides stabilization; no communicative animation is assigned to Demon 1.
	var runway := get_node_or_null("../TaxiRunway") as Node3D
	var reference_height := runway.global_position.y if runway != null else player.min_altitude
	var safe_height := maxf(player.global_position.y, reference_height + 1000.0)
	# ponytail: 1 km terrain samples for these open landscapes; continuous clearance if tighter routes are authored.
	for step in 13:
		var ahead := player.global_position + _forward * (step * 1000.0)
		var ray := PhysicsRayQueryParameters3D.create(Vector3(ahead.x, player.max_altitude, ahead.z), Vector3(ahead.x, -1000.0, ahead.z), 1)
		var hit := get_world_3d().direct_space_state.intersect_ray(ray)
		if not hit.is_empty():
			safe_height = maxf(safe_height, hit.position.y + 800.0)
	player.global_position.y = safe_height
	player._angular_velocity = Vector3.ZERO
	player.speed = player.cruise_speed
	player.grounded = false
	player._ground_contact_seen = true
	player.gear_down = false
	player._update_gear(player.gear_travel_time)
	_airborne = true
	_spawn_convoy(enemy_scene)
	_tracking = true
	shot = "sphere"
	_camera.fov = 65.0
	await _fade(0.0)
	_radio.play(_dialogue, "sphere")
	var zoom := create_tween()
	zoom.tween_property(_camera, "fov", 28.0, 0.65).set_trans(Tween.TRANS_CUBIC)
	zoom.tween_interval(0.2)
	zoom.tween_property(_camera, "fov", 16.0, 0.45)
	await zoom.finished
	if _radio.playing:
		await _radio.finished
	shot = "interceptors"
	_breaking = true
	_camera.fov = 42.0
	_radio.play(_dialogue, "interceptors")
	await create_tween().tween_property(_camera, "fov", 9.0, 0.8).finished
	if _radio.playing:
		await _radio.finished
	await _fade(1.0)
	# Handoff with sufficient separation to read the weapons panel safely.
	for i in interceptors.size():
		var fighter := interceptors[i]
		fighter.global_position = player.global_position + _forward * (2300.0 + (i % 2) * 180.0) + _right * ((i - 1.5) * 160.0)
		fighter.global_basis = Basis.looking_at(-_forward)
		fighter.reset_physics_interpolation()
	_tracking = false
	shot = "combat_handoff"
	player.get_node("FlightCamera").snap_to_target()
	_camera.global_transform = player.get_node("FlightCamera").global_transform
	_camera.fov = player.camera_fov
	await _fade(0.0)
	if player._ground_body != null:
		player._ground_body.velocity = _forward * player.speed
	_end()


func _spawn_convoy(enemy_scene: PackedScene) -> void:
	_sphere = SPHERE.instantiate()
	_sphere.collision_layer = 0
	_sphere.collision_mask = 0
	add_child(_sphere)
	_sphere.global_position = player.global_position + _forward * 7000.0 - _right * 2500.0 + Vector3.UP * 650.0
	_convoy_direction = _right
	for i in 10:
		var fighter := enemy_scene.instantiate() as EnemyFighter
		fighter.name = "Escort%02d" % (i + 1)
		fighter.label = "NON IDENTIFICATO %02d" % (i + 1)
		fighter.invulnerable = true
		fighter.airframe_scale = 2.0 # Match the player's metre-scale rig, not the old miniature AI.
		add_child(fighter)
		fighter.set_physics_process(false)
		fighter.remove_from_group("targets")
		fighter.remove_from_group("combat_ai")
		fighter.get_node("Hitbox").collision_layer = 0
		fighter.get_node("GunHitbox").collision_layer = 0
		fighter.get_node("WeaponController").firing_enabled = false
		fighter.global_basis = Basis.looking_at(_convoy_direction)
		fighter.global_position = _sphere.global_position + _forward * (450.0 if i < 5 else -450.0) + _right * ((i % 5 - 2) * 260.0)
		fighter.reset_physics_interpolation()
		escorts.append(fighter)
		if i < 4:
			interceptors.append(fighter)


func release_interceptors(parent: Node3D) -> Array[EnemyFighter]:
	for fighter in interceptors:
		escorts.erase(fighter)
		fighter.reparent(parent)
		fighter.add_to_group("targets")
		fighter.add_to_group("combat_ai")
		fighter.get_node("Hitbox").collision_layer = 4
		fighter.get_node("GunHitbox").collision_layer = 4
		fighter.invulnerable = false
	return interceptors


func _physics_process(delta: float) -> void:
	if _airborne:
		player.global_position += _forward * player.cruise_speed * delta
	if not is_instance_valid(_sphere):
		return
	_convoy_age += delta
	_sphere.global_position += _convoy_direction * 180.0 * delta
	for fighter in escorts:
		if _breaking and fighter in interceptors:
			var destination := player.global_position + _forward * 2300.0 + _right * ((interceptors.find(fighter) - 1.5) * 160.0)
			var direction := fighter.global_position.direction_to(destination)
			fighter.global_basis = fighter.global_basis.slerp(Basis.looking_at(direction), minf(delta * 1.8, 1.0))
			fighter.global_position = fighter.global_position.move_toward(destination, 480.0 * delta)
		else:
			fighter.global_position += _convoy_direction * 180.0 * delta
	if not active and _convoy_age > 100.0:
		for fighter in escorts:
			fighter.queue_free()
		escorts.clear()
		_sphere.queue_free()


func _process(delta: float) -> void:
	if active and shot == "combat_handoff":
		player.get_node("FlightCamera").snap_to_target()
		_camera.global_transform = player.get_node("FlightCamera").global_transform
	if not _tracking:
		return
	_shake_time += delta
	_camera.global_position = player.global_position + Vector3.UP * 4.0
	var focus := _sphere.global_position
	if shot == "interceptors":
		focus = Vector3.ZERO
		for fighter in interceptors:
			focus += fighter.global_position
		focus /= interceptors.size()
	var desired := Transform3D(Basis.IDENTITY, _camera.global_position).looking_at(focus).basis
	_camera.global_basis = _camera.global_basis.slerp(desired, 1.0 - exp(-delta * 7.0))
	# Bounded angular shake scales with zoom, keeping the subject readable.
	var shake := deg_to_rad(_camera.fov * 0.004)
	_camera.rotate_object_local(Vector3.RIGHT, sin(_shake_time * 17.0) * shake)
	_camera.rotate_object_local(Vector3.UP, sin(_shake_time * 23.0) * shake)
