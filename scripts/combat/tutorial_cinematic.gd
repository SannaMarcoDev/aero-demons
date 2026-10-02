extends Node3D
## Tutorial formation showcase and sphere reveal, driven by one shot engine. Tweens and flight motion pause with the scene.
signal _sequence_released

const SPHERE = preload("res://scenes/vfx/energy_sphere.tscn")
const Bindings = preload("res://scripts/input/controller_bindings.gd")
const SKIP_HOLD_SECONDS := 1.0
const OPENING_SECONDS := 4.2
const HANDOFF_SECONDS := 1.4
## Airframe centres and camera keep-out half-extents in each aircraft's local frame (runtime scale).
const PIVOTS := {"lead": Vector3(0.0, -1.8, 0.5), "d2": Vector3(0.0, 1.0, -1.0), "d3": Vector3(0.0, 1.0, -1.0)}
const KEEP_OUT := {"lead": Vector3(7.0, 3.6, 10.5), "d2": Vector3(9.0, 4.2, 12.0), "d3": Vector3(9.0, 4.2, 12.0)}
const D2_SLOT := Vector3(-24.0, 2.0, 14.0)
const D3_SLOT := Vector3(24.0, -1.0, 16.0)
## A sequence is a list of segments: `{"seconds", "shots"}` holds a silent beat, `{"cue", "lines"}` plays a
## dialogue cue with one cue list per shown line. Cues fire at `at` seconds into their line or beat.
## Shot positions sit in the formation frame around `anchor`'s slot; `look` aims at an aircraft centre,
## "sphere" or "bandits" plus a formation-frame offset. `world` freezes the camera where it starts;
## `through` puts it `dist` metres beyond the anchor on the line from that subject (negative: towards it),
## so both share the frame.
## `zoom` snaps the lens through [time, fov] steps and `shake` adds handheld jitter. Cues may also move
## slots, run the control check, bank the formation, light the burners, break the interceptors or hand off.
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
	[{"handoff": true}], # `collaudo_comandi` keeps playing over gameplay.
]
const FORMATION_SEQUENCE := [{"seconds": OPENING_SECONDS, "shots": [OPENING_SHOT]}, {"cue": "collaudo", "lines": FORMATION_SHOTS}]

## Convoy path in the formation frame at the reveal's first frame: it appears at one o'clock high and
## crosses right to left, about 7 km out when the interceptors break and never closer than 3 km.
const CONVOY_START := Vector3(7300.0, 0.0, -12000.0)
const CONVOY_SPEED := 150.0
const CONVOY_CLEARANCE := 350.0
## Escort slots in the convoy frame (-Z along the path, -X towards the formation); the first four break.
const ESCORT_SLOTS := [Vector3(-420.0, 0.0, -160.0), Vector3(-470.0, -15.0, -100.0), Vector3(-370.0, -15.0, -100.0), Vector3(-520.0, -30.0, -40.0),
	Vector3(420.0, 0.0, -160.0), Vector3(470.0, -15.0, -100.0), Vector3(370.0, -15.0, -100.0),
	Vector3(0.0, 40.0, 420.0), Vector3(-60.0, 30.0, 480.0), Vector3(60.0, 30.0, 480.0)]
## Where the interceptors settle head-on, in the formation frame, ready for the weapons panels.
const BANDIT_HOLD := [Vector3(-150.0, 20.0, -2550.0), Vector3(-50.0, 0.0, -2450.0), Vector3(50.0, 0.0, -2450.0), Vector3(150.0, 20.0, -2550.0)]
const BANDIT_SPEED := 240.0
const BANDIT_TURN := 22.0
const REVEAL_SEQUENCE := [
	{"seconds": 3.0, "shots": [
		{"through": "sphere", "anchor": "d3", "dist": 70.0, "dist_to": 55.0, "pos": Vector3(0.0, 6.0, 0.0), "move": 3.0, "look": "d3", "look_offset": Vector3(0.0, 3.0, 0.0), "fov": 44.0}]},
	{"cue": "sphere", "lines": [
		[{"anchor": "d3", "pos": Vector3(11.0, 2.0, -22.0), "pos_to": Vector3(9.0, 1.6, -17.0), "move": 4.0, "look": "d3", "fov": 32.0, "d2": Vector3(-18.0, 1.5, 11.0), "d3": Vector3(18.0, -0.5, 12.0), "slot_time": 3.0}],
		[{"anchor": "d2", "pos": Vector3(-10.0, 2.5, -21.0), "pos_to": Vector3(-8.5, 2.0, -18.0), "move": 3.2, "look": "d2", "fov": 30.0}],
		[{"anchor": "d3", "pos": Vector3(26.0, 1.5, -5.0), "look": "d3", "fov": 30.0}],
		[{"through": "sphere", "anchor": "d2", "dist": 26.0, "pos": Vector3(0.0, 4.5, 0.0), "look": "sphere", "fov": 42.0, "zoom": [[0.7, 20.0], [1.1, 9.0], [1.6, 4.5]], "shake": 1.0}],
		[{"through": "sphere", "anchor": "bandits", "dist": 110.0, "dist_to": 85.0, "pos": Vector3(0.0, 15.0, 0.0), "move": 5.5, "look": "bandits", "fov": 60.0}],
		[{"through": "sphere", "anchor": "lead", "dist": 420.0, "dist_to": 400.0, "pos": Vector3(0.0, 24.0, 0.0), "move": 4.0, "look": "lead", "look_offset": Vector3(0.0, 12.0, 0.0), "fov": 9.0}],
		[{"anchor": "d3", "pos": Vector3(-11.0, 2.5, -22.0), "pos_to": Vector3(-9.5, 2.2, -18.0), "move": 3.4, "look": "d3", "look_offset": Vector3(0.0, 1.0, -2.0), "fov": 26.0, "shake": 0.25}],
		[{"anchor": "d2", "pos": Vector3(-2.5, 1.8, -22.0), "look": "d2", "fov": 24.0}],
		[{"through": "sphere", "anchor": "d3", "dist": 34.0, "pos": Vector3(-3.0, 3.5, 0.0), "look": "d3", "look_offset": Vector3(0.0, 2.0, 0.0), "fov": 30.0}],
	]},
	{"seconds": 2.6, "shots": [
		{"world": true, "anchor": "bandits", "pos": Vector3(260.0, -40.0, 200.0), "look": "bandits", "fov": 22.0, "fov_to": 26.0, "move": 2.6},
		{"at": 0.2, "break": true}]},
	{"cue": "interceptors", "lines": [
		[{"through": "lead", "anchor": "bandits", "dist": -350.0, "pos": Vector3(0.0, -10.0, 0.0), "look": "bandits", "fov": 30.0, "shake": 0.5}],
		[{"anchor": "d2", "pos": Vector3(-12.0, 1.0, -16.0), "pos_to": Vector3(-10.5, 1.0, -14.0), "move": 3.5, "look": "d2", "fov": 30.0}],
		[{"pos": Vector3(-4.0, -1.5, -26.0), "pos_to": Vector3(-3.0, -1.2, -20.0), "move": 4.0, "look": "lead", "fov": 30.0}],
		[{"pos": Vector3(0.0, 8.0, 42.0), "pos_to": Vector3(0.0, 5.5, 28.0), "move": 3.0, "look": "lead", "look_offset": Vector3(0.0, 0.0, -80.0), "fov": 48.0, "d2": Vector3(-40.0, 3.0, 20.0), "d3": Vector3(40.0, -1.0, 22.0), "slot_time": 2.4, "boost": true},
			{"at": 2.4, "handoff": true}],
	]},
]

var active := false
var escorts: Array[EnemyFighter] = []
var interceptors: Array[EnemyFighter] = []
var _camera: Camera3D
var _black: ColorRect
var _radio: RadioDialogue
var _dialogue: DialogueResource
var _sphere: Node3D
var _convoy_origin := Vector3.ZERO
var _convoy_direction := Vector3.LEFT
var _convoy_basis := Basis.IDENTITY
var _convoy_age := 0.0
var _breaking := false
var _bandits: Array[Dictionary] = []
var _fade_tween: Tween
var _hidden_overlays: Array[CanvasLayer] = []
var _running := false
var _phase := ""
var _sequence: Array = []
var _segment := -1
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
	var forward := _level_forward()
	# Opening, dialogue and handoff cover about 12 km of straight flight before the closing turn.
	var height := _clear_height(player.global_position, forward, 14, 700.0, player.global_position.y)
	_take_rig(forward, height)
	for wing in wings:
		wing.show()
	_black.modulate.a = 1.0
	_fade(0.0, 1.2)
	var skipped := await _run_sequence(FORMATION_SEQUENCE)
	if skipped:
		await _fade(1.0, 0.35)
		_settle()
	_release_rig()
	_end()
	if skipped:
		_radio.play(_dialogue, "collaudo_comandi")
		await _fade(0.0, 0.6)


## The trio spots the convoy, four escorts break towards them and the shot blends into the chase camera
## with the interceptors head-on at weapons-panel distance.
func play_reveal(radio: RadioDialogue, dialogue: DialogueResource, enemy_scene: PackedScene) -> void:
	_begin(radio, dialogue)
	_black.modulate.a = 0.0
	await _fade(1.0, 0.5)
	# The fade hides stabilization: any attitude becomes level formation flight.
	var forward := _level_forward()
	var projected := player.global_position + forward * 12000.0
	if Vector2(projected.x, projected.z).length() > player.return_distance:
		forward = Vector3(-player.global_position.x, 0.0, -player.global_position.z).normalized()
	_take_rig(forward, _clear_height(player.global_position, forward, 13, 800.0, maxf(player.global_position.y, player.min_altitude + 1000.0)))
	_spawn_convoy(enemy_scene)
	_fade(0.0, 0.8)
	var skipped := await _run_sequence(REVEAL_SEQUENCE)
	if skipped:
		await _fade(1.0, 0.35)
		_settle()
		_breaking = true
		for k in interceptors.size():
			_bandits[k] = {"dir": _rig.basis.z, "roll": 0.0, "pitch": 0.0, "hold": true}
			interceptors[k].global_transform = Transform3D(Basis.looking_at(_rig.basis.z), _rig * (BANDIT_HOLD[k] as Vector3))
	_release_rig()
	_end()
	if skipped:
		await _fade(0.0, 0.6)


func _level_forward() -> Vector3:
	var forward := -player.global_basis.z
	forward.y = 0.0
	return forward.normalized() if forward.length_squared() > 0.01 else Vector3.FORWARD


func _take_rig(forward: Vector3, height: float) -> void:
	_rig = Transform3D(Basis.looking_at(forward), Vector3(player.global_position.x, height, player.global_position.z))
	player.speed = player.cruise_speed
	player._angular_velocity = Vector3.ZERO
	for wing in _wings:
		wing.set_physics_process(false)
	_d2_slot = D2_SLOT
	_d3_slot = D3_SLOT
	_bank = 0.0
	_check_time = -1.0


func _run_sequence(sequence: Array) -> bool:
	_sequence = sequence
	_segment = -1
	_clock = 0.0
	_skip_hold = 0.0
	_skip_armed = false
	_skipped = false
	_phase = "sequence"
	_running = true
	_update_rig(0.0)
	_next_segment()
	_run_cues()
	_update_shot(0.0)
	_skip_label.text = "TIENI [%s] PER SALTARE" % Bindings.action_label("ui_accept")
	_skip_label.modulate.a = 0.6
	_skip_label.show()
	_radio.line_shown.connect(_on_line_shown)
	await _sequence_released
	_radio.line_shown.disconnect(_on_line_shown)
	_skip_label.hide()
	return _skipped


func _next_segment() -> void:
	_segment += 1
	_line = -1
	_line_time = 0.0
	_cue = 0
	if _segment >= _sequence.size():
		_start_handoff()
	elif _sequence[_segment].has("cue"):
		_radio.play(_dialogue, _sequence[_segment].cue)


func _on_line_shown(_line_data: DialogueLine) -> void:
	_line += 1
	_line_time = 0.0
	_cue = 0


func _start_handoff() -> void:
	_phase = "handoff"
	_phase_time = 0.0
	_handoff_local = _rig.affine_inverse() * _camera.global_transform
	_handoff_fov = _camera.fov


func _process_sequence(delta: float) -> void:
	_clock += delta
	_phase_time += delta
	_update_rig(delta)
	if _phase == "handoff":
		# Blend into the chase camera so control returns without a cut.
		var weight := smoothstep(0.0, 1.0, _phase_time / HANDOFF_SECONDS)
		var chase := player.get_node("FlightCamera")
		chase.snap_to_target()
		_camera.global_transform = (_rig * _handoff_local).interpolate_with(chase.global_transform, weight)
		_camera.fov = lerpf(_handoff_fov, player.camera_fov, weight)
		if weight >= 1.0:
			_phase = "released"
			_sequence_released.emit()
		return
	var segment: Dictionary = _sequence[_segment]
	_line_time += delta
	if segment.has("cue") and not _radio.playing:
		_next_segment() # Dialogue ended early: never strand the player in the cutscene.
	elif segment.has("seconds") and _line_time >= segment.seconds:
		_next_segment()
	if _phase != "sequence":
		return
	_run_cues()
	_update_shot(delta)
	_update_skip(delta)


func _run_cues() -> void:
	var segment: Dictionary = _sequence[_segment]
	var cues: Array = segment.get("shots", [])
	if segment.has("lines"):
		cues = segment.lines[_line] if _line >= 0 and _line < segment.lines.size() else []
	while _phase == "sequence" and _cue < cues.size() and cues[_cue].get("at", 0.0) <= _line_time:
		_cue += 1
		_apply_cue(cues[_cue - 1])


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
		_phase = "released"
		_radio.stop()
		_sequence_released.emit()


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
	if cue.get("break", false):
		_breaking = true
	if cue.get("handoff", false):
		_start_handoff()


func _update_shot(delta: float) -> void:
	_shot_time += delta
	var weight := smoothstep(0.0, 1.0, _shot_time / _shot.get("move", 1.0))
	var desired := _shot_transform(weight)
	_camera.global_position = desired.origin
	_camera.global_basis = _camera.global_basis.slerp(desired.basis, 1.0 - exp(-delta * 10.0)).orthonormalized()
	var fov: float = lerpf(_shot.fov, _shot.get("fov_to", _shot.fov), weight)
	if _shot.has("zoom"):
		# Manual zoom: the lens jumps between stops instead of gliding.
		for zoom_stop in _shot.zoom:
			if _shot_time >= zoom_stop[0]:
				fov = zoom_stop[1]
		fov = lerpf(_camera.fov, fov, 1.0 - exp(-delta * 16.0))
	_camera.fov = fov
	var shake: float = _shot.get("shake", 0.0)
	if shake > 0.0:
		# Handheld long lens: bounded jitter scales with zoom, keeping the subject readable.
		var amount := deg_to_rad(_camera.fov * 0.012) * shake
		_camera.rotate_object_local(Vector3.RIGHT, (sin(_clock * 17.0) + sin(_clock * 7.3)) * 0.5 * amount)
		_camera.rotate_object_local(Vector3.UP, (sin(_clock * 23.0) + sin(_clock * 5.1)) * 0.5 * amount)


func _shot_transform(weight: float) -> Transform3D:
	var pos: Vector3 = _shot_origin
	if not _shot.get("world", false):
		var anchor := _anchor_point(_shot.get("anchor", "lead"))
		if _shot.has("through"):
			anchor += _pivot(_shot.through).direction_to(anchor) * lerpf(_shot.dist, _shot.get("dist_to", _shot.dist), weight)
		pos = _keep_out(anchor + _rig.basis * (_shot.pos as Vector3).lerp(_shot.get("pos_to", _shot.pos), weight))
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
	match id:
		"sphere":
			return _sphere.global_position
		"bandits":
			var center := Vector3.ZERO
			for fighter in interceptors:
				center += fighter.global_position
			return center / interceptors.size()
	return _aircraft(id).global_transform * (PIVOTS[id] as Vector3)


func _anchor_point(id: String) -> Vector3:
	var slot := Vector3.ZERO
	match id:
		"sphere", "bandits":
			return _pivot(id)
		"d2":
			slot = _d2_slot
		"d3":
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


func _update_rig(delta: float) -> void:
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
	if is_instance_valid(_sphere):
		_update_convoy(delta)


func _set_boost(boost: float) -> void:
	if player._afterburners != null:
		player._afterburners.set_boost(boost)
	for wing in _wings:
		var burners := wing.get_node_or_null("Afterburners") as Afterburner
		if burners != null:
			burners.set_boost(boost)


## After a skip: formation back in its default slots, level, with no pending tweens.
func _settle() -> void:
	for tween in [_slot_tween, _bank_tween]:
		if tween != null and tween.is_valid():
			tween.kill()
	_d2_slot = D2_SLOT
	_d3_slot = D3_SLOT
	_bank = 0.0
	_check_time = -1.0
	_update_rig(0.0)


func _release_rig() -> void:
	_running = false
	_phase = ""
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
	escorts.clear()
	interceptors.clear()
	_bandits.clear()
	_breaking = false
	_convoy_age = 0.0
	_convoy_direction = -_rig.basis.x
	_convoy_basis = Basis.looking_at(_convoy_direction)
	var start := _rig * CONVOY_START
	start.y = _clear_height(start, _convoy_direction, 16, 900.0, _rig.origin.y + CONVOY_CLEARANCE)
	_convoy_origin = start
	_sphere = SPHERE.instantiate()
	_sphere.collision_layer = 0
	_sphere.collision_mask = 0
	_sphere.travel_velocity = _convoy_direction * CONVOY_SPEED
	add_child(_sphere)
	for i in ESCORT_SLOTS.size():
		var fighter := enemy_scene.instantiate() as EnemyFighter
		fighter.name = "Escort%02d" % (i + 1)
		fighter.label = "NON IDENTIFICATO %02d" % (i + 1)
		fighter.invulnerable = true
		fighter.set_meta("convoy_slot", i)
		add_child(fighter)
		fighter.set_physics_process(false)
		fighter.remove_from_group("targets")
		fighter.remove_from_group("combat_ai")
		fighter.get_node("Hitbox").collision_layer = 0
		fighter.get_node("GunHitbox").collision_layer = 0
		fighter.get_node("WeaponController").firing_enabled = false
		escorts.append(fighter)
		if i < BANDIT_HOLD.size():
			interceptors.append(fighter)
			_bandits.append({"dir": _convoy_direction, "roll": 0.0, "pitch": 0.0, "hold": false})
	_update_convoy(0.0)
	for fighter in escorts:
		fighter.reset_physics_interpolation()


func _update_convoy(delta: float) -> void:
	_convoy_age += delta
	var center := _convoy_origin + _convoy_direction * CONVOY_SPEED * _convoy_age
	_sphere.global_position = center
	for fighter in escorts:
		var bandit := interceptors.find(fighter)
		if _breaking and bandit >= 0:
			if _running:
				_fly_bandit(bandit, delta)
			continue
		var i: int = fighter.get_meta("convoy_slot")
		var drift := Vector3(sin(_convoy_age * 0.6 + i) * 4.0, sin(_convoy_age * 0.8 + i * 1.7) * 6.0, sin(_convoy_age * 0.5 + i * 0.9) * 5.0)
		var sway := Basis(Vector3.BACK, sin(_convoy_age * 0.7 + i * 2.1) * deg_to_rad(3.0))
		fighter.global_transform = Transform3D(_convoy_basis * sway, center + _convoy_basis * ((ESCORT_SLOTS[i] as Vector3) + drift))


## Roll first, then pull: heading changes only as fast as the bank allows, so the break reads as flight.
func _fly_bandit(k: int, delta: float) -> void:
	var fighter := interceptors[k]
	var state := _bandits[k]
	var hold_point: Vector3 = _rig * (BANDIT_HOLD[k] as Vector3)
	var to := hold_point - fighter.global_position
	state.hold = state.hold or to.length() < 300.0
	var desired: Vector3 = _rig.basis.z if state.hold else to.normalized()
	var dir: Vector3 = state.dir
	var flat := Vector3(dir.x, 0.0, dir.z).normalized()
	var turn := flat.signed_angle_to(Vector3(desired.x, 0.0, desired.z).normalized(), Vector3.UP)
	state.roll = move_toward(state.roll, clampf(-rad_to_deg(turn) * 2.5, -75.0, 75.0), 140.0 * delta)
	flat = flat.rotated(Vector3.UP, -deg_to_rad(BANDIT_TURN * state.roll / 75.0) * delta)
	state.pitch = move_toward(state.pitch, clampf(asin(clampf(desired.y, -1.0, 1.0)), -0.35, 0.35), 0.3 * delta)
	state.dir = flat * cos(state.pitch) + Vector3.UP * sin(state.pitch)
	if state.hold:
		fighter.global_position = fighter.global_position.lerp(hold_point, 1.0 - exp(-delta * 1.2))
	else:
		fighter.global_position += state.dir * BANDIT_SPEED * delta
	fighter.global_basis = Basis.looking_at(state.dir) * Basis(Vector3.BACK, -deg_to_rad(state.roll))


func release_interceptors(parent: Node3D) -> Array[EnemyFighter]:
	for fighter in interceptors:
		escorts.erase(fighter)
		fighter.reparent(parent)
		fighter.add_to_group("targets")
		fighter.add_to_group("combat_ai")
		fighter.get_node("Hitbox").collision_layer = 4
		fighter.get_node("GunHitbox").collision_layer = 4
		fighter.invulnerable = false
		fighter.speed = BANDIT_SPEED
		fighter.reset_physics_interpolation()
	return interceptors


func _physics_process(delta: float) -> void:
	# During a sequence the convoy moves with the rig in `_process`; afterwards the six carry on alone.
	if _running or not is_instance_valid(_sphere):
		return
	_update_convoy(delta)
	if not active and _convoy_age > 100.0:
		for fighter in escorts:
			fighter.queue_free()
		escorts.clear()
		_sphere.queue_free()


func _process(delta: float) -> void:
	if _running:
		_process_sequence(delta)
