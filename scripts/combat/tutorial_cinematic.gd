extends Node3D
## Tutorial formation showcase and combat reveal. Tweens and flight motion pause with the scene.
signal _formation_released

const SPHERE = preload("res://scenes/vfx/energy_sphere.tscn")
const Bindings = preload("res://scripts/input/controller_bindings.gd")
const SKIP_HOLD_SECONDS := 1.0
const OPENING_SECONDS := 4.2
const HANDOFF_SECONDS := 1.4
const HANDOFF_LINE := 16
## Airframe centres and camera keep-out half-extents in each aircraft's local frame (runtime scale).
const PIVOTS := {"lead": Vector3(0.0, -1.8, 0.5), "d2": Vector3(0.0, 1.0, -1.0), "d3": Vector3(0.0, 1.0, -1.0)}
const KEEP_OUT := {"lead": Vector3(7.0, 3.6, 10.5), "d2": Vector3(9.0, 4.2, 12.0), "d3": Vector3(9.0, 4.2, 12.0)}
const D2_SLOT := Vector3(-24.0, 2.0, 14.0)
const D3_SLOT := Vector3(24.0, -1.0, 16.0)
## Exterior-only shots, one entry per `collaudo` line. Positions sit in the formation frame around
## `anchor`'s slot; `look` aims at an aircraft centre plus a formation-frame offset. Cues may also
## move slots, run the control check, bank the formation or light the burners.
const OPENING_SHOT := {"world": true, "anchor": "lead", "pos": Vector3(-230.0, 45.0, -900.0), "look": "lead", "fov": 16.0, "fov_to": 34.0, "move": OPENING_SECONDS}
const FORMATION_SHOTS := [
	[{"anchor": "d2", "pos": Vector3(7.0, 2.5, -24.0), "pos_to": Vector3(6.0, 2.2, -21.0), "move": 2.6, "look": "d2", "fov": 38.0},
		{"at": 2.6, "pos": Vector3(16.0, 3.0, -32.0), "look": "lead", "look_offset": Vector3(0.0, 0.0, -1.0), "fov": 34.0}],
	[],
	[{"pos": Vector3(-10.0, 1.0, 13.0), "pos_to": Vector3(-9.5, 0.2, -12.0), "move": 8.0, "look": "lead", "look_offset": Vector3(0.0, 0.0, 4.0), "look_to": Vector3(0.0, 0.0, -5.0), "fov": 46.0},
		{"at": 0.4, "check": true}],
	[],
	[{"anchor": "d3", "pos": Vector3(16.0, 1.5, -3.0), "pos_to": Vector3(14.5, 1.2, -4.0), "move": 3.4, "look": "d3", "fov": 30.0}],
	[{"anchor": "d2", "pos": Vector3(1.0, 6.5, 20.0), "pos_to": Vector3(1.5, 6.0, 17.0), "move": 4.6, "look": "lead", "look_offset": Vector3(0.0, -6.0, -30.0), "fov": 40.0}],
	[{"anchor": "d3", "pos": Vector3(-7.0, 2.0, -22.0), "look": "d3", "fov": 34.0},
		{"at": 2.6, "pos": Vector3(6.0, -0.5, -17.0), "pos_to": Vector3(3.8, -1.0, -12.5), "move": 3.0, "look": "lead", "look_offset": Vector3(0.0, -0.6, -3.0), "fov": 24.0, "fov_to": 18.0}],
	[{"anchor": "d3", "pos": Vector3(-4.0, -9.0, -26.0), "pos_to": Vector3(-3.0, -8.0, -21.0), "move": 6.0, "look": "d3", "fov": 30.0}],
	[{"pos": Vector3(-64.0, 3.0, -2.0), "pos_to": Vector3(-62.0, 4.0, -8.0), "move": 2.2, "look": "lead", "look_offset": Vector3(-8.0, 1.5, 5.0), "fov": 32.0, "d2": Vector3(-16.0, 1.2, 9.0), "slot_time": 2.4}],
	[{"anchor": "d3", "pos": Vector3(3.0, 2.5, 26.0), "look": "d3", "look_offset": Vector3(0.0, -60.0, -500.0), "fov": 30.0}],
	[{"anchor": "d2", "pos": Vector3(-12.0, 4.0, 30.0), "pos_to": Vector3(-11.0, 3.5, 25.0), "move": 5.6, "look": "d2", "fov": 28.0}],
	[{"pos": Vector3(5.0, 4.0, -320.0), "look": "lead", "look_offset": Vector3(3.0, 1.0, 6.0), "fov": 8.5, "fov_to": 7.5, "move": 5.6}],
	[{"pos": Vector3(40.0, 35.0, 30.0), "pos_to": Vector3(38.0, 33.0, 24.0), "move": 3.6, "look": "lead", "fov": 16.0}],
	[{"pos": Vector3(13.0, -3.5, -18.0), "look": "lead", "look_offset": Vector3(0.0, -2.0, 14.0), "fov": 36.0, "d2": Vector3(0.0, -7.0, 36.0), "slot_time": 3.2}],
	[{"pos": Vector3(26.0, 9.0, 26.0), "pos_to": Vector3(95.0, 42.0, 120.0), "move": 7.6, "look": "lead", "look_offset": Vector3(4.0, -3.0, -10.0), "look_to": Vector3(8.0, -8.0, -12.0), "fov": 44.0, "fov_to": 55.0, "d2": Vector3(-28.0, 3.0, 18.0), "d3": Vector3(28.0, -1.0, 18.0), "slot_time": 3.0, "boost": true},
		{"at": 0.3, "bank": 30.0}],
	[{"at": 1.6, "bank": 0.0},
		{"at": 2.4, "boost": false}],
]

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
var _shake_intensity := 0.0
var _shake_tween: Tween
var _fade_tween: Tween
var _convoy_age := 0.0
var _hidden_overlays: Array[CanvasLayer] = []
var _formation := false
var _formation_phase := ""
var _wings: Array[EnemyFighter] = []
var _rig := Transform3D.IDENTITY
var _d2_slot := D2_SLOT
var _d3_slot := D3_SLOT
var _bank := 0.0
var _clock := 0.0
var _phase_time := 0.0
var _line := -1
var _line_time := 0.0
var _cue := 0
var _shot: Dictionary = {}
var _shot_time := 0.0
var _shot_origin := Vector3.ZERO
var _check_time := -1.0
var _slot_tween: Tween
var _bank_tween: Tween
var _handoff_local := Transform3D.IDENTITY
var _handoff_fov := 0.0
var _skip_hold := 0.0
var _skip_armed := false
var _skipped := false
var _skip_label: Label

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
	_skip_label = Label.new()
	_skip_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_skip_label.add_theme_font_size_override("font_size", 18)
	_skip_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_skip_label.add_theme_constant_override("outline_size", 6)
	overlay.add_child(_skip_label)
	_skip_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_skip_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_skip_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_skip_label.position -= Vector2(32.0, 28.0)
	_skip_label.hide()


func _begin(radio: RadioDialogue, dialogue: DialogueResource) -> void:
	active = true
	_radio = radio
	_dialogue = dialogue
	_shake_intensity = 0.0
	_shake_time = 0.0
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
	_shake_intensity = 0.0
	_shake_time = 0.0
	if _shake_tween != null and _shake_tween.is_valid():
		_shake_tween.kill()
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
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = create_tween()
	await _fade_tween.tween_property(_black, "modulate:a", alpha, seconds).finished


func play_formation(radio: RadioDialogue, dialogue: DialogueResource, wings: Array[EnemyFighter]) -> void:
	_begin(radio, dialogue)
	_wings = wings
	var forward := -player.global_basis.z
	forward.y = 0.0
	forward = forward.normalized() if forward.length_squared() > 0.01 else Vector3.FORWARD
	# Opening, dialogue and handoff cover about 12 km of straight flight before the closing turn.
	var height := _clear_height(player.global_position, forward, 14, 700.0, player.global_position.y)
	_rig = Transform3D(Basis.looking_at(forward), Vector3(player.global_position.x, height, player.global_position.z))
	player.speed = player.cruise_speed
	player._angular_velocity = Vector3.ZERO
	for wing in wings:
		wing.set_physics_process(false)
		wing.show()
	_d2_slot = D2_SLOT
	_d3_slot = D3_SLOT
	_bank = 0.0
	_clock = 0.0
	_line = -1
	_cue = 0
	_check_time = -1.0
	_skip_hold = 0.0
	_skip_armed = false
	_skipped = false
	_formation = true
	_formation_phase = "opening"
	_phase_time = 0.0
	_update_formation(0.0)
	_apply_cue(OPENING_SHOT)
	_skip_label.text = "TIENI [%s] PER SALTARE" % Bindings.action_label("ui_accept")
	_skip_label.modulate.a = 0.6
	_skip_label.show()
	_black.modulate.a = 1.0
	_fade(0.0, 1.2)
	radio.line_shown.connect(_on_formation_line)
	await _formation_released
	radio.line_shown.disconnect(_on_formation_line)
	_skip_label.hide()
	if _skipped:
		await _fade(1.0, 0.35)
		for tween in [_slot_tween, _bank_tween]:
			if tween != null and tween.is_valid():
				tween.kill()
		_d2_slot = D2_SLOT
		_d3_slot = D3_SLOT
		_bank = 0.0
		_check_time = -1.0
		_update_formation(0.0)
	_release_formation()
	_end()
	if _skipped:
		_radio.play(_dialogue, "collaudo_comandi")
		await _fade(0.0, 0.6)


func _on_formation_line(_line_data: DialogueLine) -> void:
	_line += 1
	_line_time = 0.0
	_cue = 0
	if _line == HANDOFF_LINE:
		_start_handoff()


func _start_handoff() -> void:
	_formation_phase = "handoff"
	_phase_time = 0.0
	_handoff_local = _rig.affine_inverse() * _camera.global_transform
	_handoff_fov = _camera.fov


func _process_formation(delta: float) -> void:
	_clock += delta
	_phase_time += delta
	_update_formation(delta)
	if _formation_phase == "handoff":
		# Blend into the chase camera so control returns without a cut.
		var weight := smoothstep(0.0, 1.0, _phase_time / HANDOFF_SECONDS)
		var chase := player.get_node("FlightCamera")
		chase.snap_to_target()
		_camera.global_transform = (_rig * _handoff_local).interpolate_with(chase.global_transform, weight)
		_camera.fov = lerpf(_handoff_fov, player.camera_fov, weight)
		if weight >= 1.0:
			_formation_phase = "released"
			_formation_released.emit()
		return
	if _formation_phase == "opening" and _phase_time >= OPENING_SECONDS:
		_formation_phase = "dialogue"
		_radio.play(_dialogue, "collaudo")
	elif _formation_phase == "dialogue":
		if not _radio.playing:
			_start_handoff() # Dialogue ended early: never strand the player in the cutscene.
			return
		_line_time += delta
		var cues: Array = FORMATION_SHOTS[_line] if _line >= 0 and _line < FORMATION_SHOTS.size() else []
		while _cue < cues.size() and cues[_cue].get("at", 0.0) <= _line_time:
			_apply_cue(cues[_cue])
			_cue += 1
	_update_shot(delta)
	_update_skip(delta)


func _update_skip(delta: float) -> void:
	var held := Input.is_action_pressed("ui_accept")
	if not _skip_armed:
		# A press carried over from the mission menu must be released first.
		_skip_armed = not held
		return
	_skip_hold = _skip_hold + delta if held else 0.0
	_skip_label.modulate.a = lerpf(0.6, 1.0, _skip_hold / SKIP_HOLD_SECONDS)
	if _skip_hold >= SKIP_HOLD_SECONDS:
		_skipped = true
		_formation_phase = "released"
		_radio.stop()
		_formation_released.emit()


func _apply_cue(cue: Dictionary) -> void:
	if cue.has("pos"):
		_shot = cue
		_shot_time = 0.0
		if cue.get("world", false):
			_shot_origin = _anchor_point(cue.get("anchor", "lead")) + _rig.basis * cue.pos
		_camera.global_transform = _shot_transform(0.0)
		_camera.fov = cue.fov
	if cue.has("d2") or cue.has("d3"):
		if _slot_tween != null and _slot_tween.is_valid():
			_slot_tween.kill()
		_slot_tween = create_tween().set_parallel().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_slot_tween.tween_property(self, "_d2_slot", cue.get("d2", _d2_slot), cue.get("slot_time", 2.5))
		_slot_tween.tween_property(self, "_d3_slot", cue.get("d3", _d3_slot), cue.get("slot_time", 2.5))
	if cue.has("bank"):
		if _bank_tween != null and _bank_tween.is_valid():
			_bank_tween.kill()
		_bank_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_bank_tween.tween_property(self, "_bank", cue.bank, 1.6)
	if cue.get("check", false):
		_check_time = 0.0
	if cue.has("boost"):
		_set_boost(1.0 if cue.boost else 0.0)


func _update_shot(delta: float) -> void:
	_shot_time += delta
	var weight := smoothstep(0.0, 1.0, _shot_time / _shot.get("move", 1.0))
	var desired := _shot_transform(weight)
	_camera.global_position = desired.origin
	_camera.global_basis = _camera.global_basis.slerp(desired.basis, 1.0 - exp(-delta * 10.0)).orthonormalized()
	_camera.fov = lerpf(_shot.fov, _shot.get("fov_to", _shot.fov), weight)


func _shot_transform(weight: float) -> Transform3D:
	var pos: Vector3 = _shot_origin
	if not _shot.get("world", false):
		pos = _anchor_point(_shot.get("anchor", "lead")) + _rig.basis * (_shot.pos as Vector3).lerp(_shot.get("pos_to", _shot.pos), weight)
		pos = _keep_out(pos)
	var offset: Vector3 = _shot.get("look_offset", Vector3.ZERO)
	var target := _pivot(_shot.look) + _rig.basis * offset.lerp(_shot.get("look_to", offset), weight)
	return Transform3D(Basis.IDENTITY, pos).looking_at(target, Vector3.UP)


func _aircraft(id: String) -> Node3D:
	match id:
		"d2":
			return _wings[0]
		"d3":
			return _wings[1]
	return player


func _pivot(id: String) -> Vector3:
	return _aircraft(id).global_transform * (PIVOTS[id] as Vector3)


func _anchor_point(id: String) -> Vector3:
	var slot := Vector3.ZERO
	if id == "d2":
		slot = _d2_slot
	elif id == "d3":
		slot = _d3_slot
	return _rig * (Basis(Vector3.BACK, -deg_to_rad(_bank)) * slot)


## Exterior shots only: a camera inside an airframe's keep-out ellipsoid is pushed to its surface.
func _keep_out(pos: Vector3) -> Vector3:
	for id in PIVOTS:
		var body := _aircraft(id).global_transform
		var local: Vector3 = body.affine_inverse() * pos - PIVOTS[id]
		var reach := (local / (KEEP_OUT[id] as Vector3)).length()
		if reach < 1.0:
			pos = body * (local / maxf(reach, 0.001) + (PIVOTS[id] as Vector3))
	return pos


func _update_formation(delta: float) -> void:
	# Coordinated-looking turn: heading follows the bank; aircraft roll, the camera frame does not.
	_rig.basis = _rig.basis.rotated(Vector3.UP, -deg_to_rad(_bank) * 0.13 * delta).orthonormalized()
	_rig.origin += -_rig.basis.z * player.cruise_speed * delta
	var bank := Basis(Vector3.BACK, -deg_to_rad(_bank))
	var controls := Vector3.ZERO
	if _check_time >= 0.0:
		# Pitch, roll, yaw both ways while Aegis reads the telemetry.
		_check_time += delta
		var step := int(_check_time / 1.1)
		if step >= 6:
			_check_time = -1.0
		elif fmod(_check_time, 1.1) < 0.8:
			controls[int(step / 2.0)] = -1.0 if step % 2 == 0 else 1.0
	player.global_transform = Transform3D(_rig.basis * bank, _rig.origin)
	if player._surface_controls != null and player._surface_controls.has_method("set_controls"):
		player._surface_controls.call("set_controls", controls.x, controls.y, controls.z, delta)
	for i in _wings.size():
		var slot := _d2_slot if i == 0 else _d3_slot
		var drift := Vector3(sin(_clock * 0.7 + i * 2.0) * 0.6, sin(_clock * 0.9 + i * 1.3) * 1.1, sin(_clock * 0.5 + i) * 0.8)
		var sway := Basis(Vector3.BACK, sin(_clock * 0.8 + i * 2.4) * deg_to_rad(2.0))
		_wings[i].global_transform = Transform3D(_rig.basis * bank * sway, _rig * (bank * (slot + drift)))


func _set_boost(boost: float) -> void:
	if player._afterburners != null:
		player._afterburners.set_boost(boost)
	for wing in _wings:
		var burners := wing.get_node_or_null("Afterburners") as Afterburner
		if burners != null:
			burners.set_boost(boost)


func _release_formation() -> void:
	_formation = false
	_formation_phase = ""
	_set_boost(0.0)
	player.global_transform = Transform3D(_rig.basis, _rig.origin)
	player.speed = player.cruise_speed
	player._angular_velocity = Vector3.ZERO
	player.reset_physics_interpolation()
	if player._surface_controls != null and player._surface_controls.has_method("reset_controls"):
		player._surface_controls.call("reset_controls")
	for wing in _wings:
		wing.global_basis = _rig.basis
		wing.speed = player.speed
		wing.reset_physics_interpolation()
		wing.set_physics_process(true)


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
	player.global_position.y = _clear_height(player.global_position, _forward, 13, 800.0, maxf(player.global_position.y, player.min_altitude + 1000.0))
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
	_shake_intensity = 1.0
	if _shake_tween != null and _shake_tween.is_valid():
		_shake_tween.kill()
	_shake_tween = create_tween()
	_shake_tween.tween_interval(0.5)
	_shake_tween.tween_property(self, "_shake_intensity", 0.0, 0.8).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
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


# ponytail: 1 km terrain samples for these open landscapes; continuous clearance if tighter routes are authored.
# Terrain3D builds collision only near the camera, so far samples read the height maps instead of raycasting.
func _clear_height(origin: Vector3, forward: Vector3, steps: int, margin: float, height: float) -> float:
	var terrain := get_tree().current_scene.find_children("*", "Terrain3D", true, false)
	if terrain.is_empty():
		return height
	for step in steps:
		var ground: float = terrain[0].data.get_height(origin + forward * (step * 1000.0))
		if not is_nan(ground):
			height = maxf(height, ground + margin)
	return height


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
	if _formation:
		_process_formation(delta)
		return
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
	if _shake_intensity > 0.0:
		_shake_time += delta
		# Bounded angular shake scales with zoom, keeping the subject readable.
		var shake := deg_to_rad(_camera.fov * 0.004) * _shake_intensity
		_camera.rotate_object_local(Vector3.RIGHT, sin(_shake_time * 17.0) * shake)
		_camera.rotate_object_local(Vector3.UP, sin(_shake_time * 23.0) * shake)
