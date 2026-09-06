extends Node3D
class_name PlayerFlight

const ENGINE_STEADY_SOUND: AudioStream = preload("res://assets/audio/sfx/engine/jet-engine-steady.mp3")
const ENGINE_ACCELERATING_SOUND: AudioStream = preload("res://assets/audio/sfx/engine/jet-engine-accelerating.mp3")

## Arcade flight, health and weapon triggers for one aircraft. `_update_controls()` is the only
## place input is read, so an AI subclass drives the same airframe by overriding it.

signal destroyed(aircraft: Node3D)

@export var min_speed := 87.5
@export var cruise_speed := 157.5
@export var max_speed := 262.5
@export var acceleration := 22.5
@export var deceleration := 30.0
@export var cruise_return_rate := 15.0
@export var pitch_speed := 75.0
## The playable speed floor is already above stall speed: control authority is strongest there,
## stays close to cruise handling, then falls off toward top speed.
@export_range(1.0, 1.5, 0.05) var low_speed_turn_factor := 1.15
@export_range(0.3, 1.0, 0.05) var high_speed_turn_factor := 0.7
## Pushing into negative G is deliberately weaker than pulling positive G.
@export_range(0.3, 1.0, 0.05) var pitch_down_factor := 0.75
## Rudder yaw is for fine alignment, not the aircraft's primary turning axis.
@export var yaw_speed := 15.0
@export var roll_speed := 110.0
@export var min_altitude := 190.0
@export var max_altitude := 15000.0
@export var return_distance := 40000.0
@export var arena_half_size := 40500.0

@export_category("High-G")
## Both analog triggers held: brake and double pitch/yaw rate. Tightens the turn; costs speed.
@export var high_g_turn_factor := 2.0
@export_range(0.1, 1.0, 0.05) var high_g_trigger_threshold := 0.5

@export_category("Spin dash")
## Double-tap acceleration: a brief camera charge, then two axial rolls at burst speed.
@export var spin_dash_tap_window := 0.3
@export var spin_dash_charge_time := 0.22
@export var spin_dash_duration := 0.55
@export var spin_dash_turns := 2.0
@export var spin_dash_speed := 450.0
@export var spin_dash_cooldown := 3.0
@export var spin_dash_camera_closeup := 3.5
@export var spin_dash_camera_pullback := 16.0
@export var spin_dash_camera_hold := 0.25
@export var spin_dash_camera_recovery := 1.2
@export var spin_dash_camera_fov_boost := 12.0

@export_category("Combat")
@export var max_health := 100.0
@export var faction_group := "player"
@export var label := "PLAYER"
## Health ratios where the airframe starts smoking and where the fire reaches full strength.
@export var damage_start_ratio := 0.6
@export var damage_full_ratio := 0.15

@export_category("Scale")
@export_range(0.1, 1.0, 0.05) var airframe_scale := 0.5

@export_category("Camera")
@export_range(45.0, 110.0, 0.5) var camera_fov := 70.0
@export_range(-10.0, 20.0, 0.1) var camera_height := 3.75
@export_range(1.0, 30.0, 0.1) var camera_depth := 4.0
@export_range(-20.0, 10.0, 0.1) var camera_pitch := -3.0
@export_range(0.0, 20.0, 0.1) var camera_acceleration_shift := 2.0

var speed := cruise_speed
var is_returning := false
var health := 100.0
var high_g_active := false
var spin_dash_active := false

var pitch_input := 0.0
var yaw_input := 0.0
var roll_input := 0.0
var throttle_input := 0.0
var brake_input := 0.0
var gun_trigger := false
var missile_trigger := false
var switch_missile_trigger := false
var cycle_trigger := false
var spin_dash_trigger := false

var _spawn_transform := Transform3D.IDENTITY
var _incoming_missiles: Array = []
var _damage_emitters: Array = []
var _flight_time := 0.0
var _accelerate_held := false
var _last_accelerate_tap := -1000.0
var _spin_dash_elapsed := 0.0
var _spin_dash_ready_at := 0.0
var _spin_dash_entry_basis := Basis.IDENTITY
var _spin_dash_direction := Vector3.FORWARD
var _spin_dash_entry_speed := 0.0
var _spin_dash_velocity := Vector3.ZERO
var _spin_dash_camera_hold_until := 0.0
var _spin_dash_camera_recover_until := 0.0
var _cycle_press_time := -1000.0
var _accelerating_audio_active := false
var _engine_audio: AudioStreamPlayer3D
var _accelerating_audio: AudioStreamPlayer3D

@onready var _afterburners: Afterburner = $Afterburners
@onready var _targeting: TargetLock = get_node_or_null("TargetLock")
@onready var _weapons: WeaponController = get_node_or_null("WeaponController")
@onready var _hitbox: Area3D = get_node_or_null("Hitbox") as Area3D


func _ready() -> void:
	add_to_group(faction_group)
	_scale_airframe()
	health = max_health
	_spawn_transform = global_transform
	_damage_emitters = find_children("*", "DamageFire", true, false)
	_setup_aircraft_audio()
	_setup_collision_detection()
	if _targeting != null and faction_group == "player":
		_targeting.lock_completed.connect(_on_target_lock_completed)
	_update_damage_effects()


func _scale_airframe() -> void:
	for child in get_children():
		if child is Node3D:
			var spatial := child as Node3D
			spatial.position *= airframe_scale
			spatial.scale *= airframe_scale


func _physics_process(delta: float) -> void:
	if not is_alive():
		return
	_flight_time += delta
	_update_controls()
	_update_spin_dash()
	_apply_flight(delta)
	_apply_triggers()


## Fills the control fields for this tick. The player reads the gamepad; subclasses read an AI.
func _update_controls() -> void:
	pitch_input = Input.get_axis("pitch_up", "pitch_down")
	yaw_input = Input.get_axis("yaw_left", "yaw_right")
	roll_input = Input.get_axis("roll_left", "roll_right")
	throttle_input = Input.get_action_strength("accelerate")
	brake_input = Input.get_action_strength("brake")
	gun_trigger = Input.is_action_pressed("fire_gun")
	missile_trigger = Input.is_action_just_pressed("fire_missile")
	switch_missile_trigger = Input.is_action_just_pressed("switch_missile")
	# tap (<0.35s) cycles target, long hold is for camera tracking
	if Input.is_action_just_pressed("cycle_target"):
		_cycle_press_time = _flight_time
		cycle_trigger = false
	elif Input.is_action_just_released("cycle_target"):
		cycle_trigger = (_flight_time - _cycle_press_time) < 0.30
	else:
		cycle_trigger = false
	high_g_active = (
		not spin_dash_active
		and Input.get_action_strength("yaw_left") > high_g_trigger_threshold
		and Input.get_action_strength("yaw_right") > high_g_trigger_threshold
	)
	if high_g_active:
		yaw_input = 0.0
		brake_input = maxf(brake_input, 1.0)
	spin_dash_trigger = _detect_accelerate_double_tap()


func _apply_flight(delta: float) -> void:
	if spin_dash_active:
		_apply_spin_dash(delta)
		return

	var turn_boost := high_g_turn_factor if high_g_active else 1.0
	var pitch_rate := _normal_pitch_rate() * turn_boost
	var yaw_rate := yaw_speed * _normal_turn_speed_factor() * turn_boost
	rotate_object_local(Vector3.RIGHT, deg_to_rad(-pitch_input * pitch_rate) * delta)
	rotate_object_local(Vector3.UP, deg_to_rad(-yaw_input * yaw_rate) * delta)
	rotate_object_local(Vector3.BACK, deg_to_rad(-roll_input * roll_speed) * delta)
	basis = basis.orthonormalized()

	# Without input the aircraft drifts back to cruise_speed at cruise_return_rate.
	if throttle_input > 0.01 or brake_input > 0.01:
		speed = clampf(
			speed + (throttle_input * acceleration - brake_input * deceleration) * delta,
			min_speed,
			max_speed,
		)
	else:
		var recovery := spin_dash_camera_recovery_weight()
		if recovery > 0.0:
			speed = lerpf(cruise_speed, max_speed, recovery)
		else:
			speed = clampf(
				move_toward(speed, cruise_speed, cruise_return_rate * delta),
				min_speed,
				max_speed,
			)
	global_position += _travel_direction() * speed * delta
	global_position.y = clampf(global_position.y, min_altitude, max_altitude)
	_return_to_arena(delta)

	var engine_throttle := inverse_lerp(cruise_speed, max_speed, speed)
	var boost := spin_dash_camera_recovery_weight()
	_afterburners.set_throttle(maxf(engine_throttle, boost))
	_afterburners.set_boost(boost)
	_update_engine_audio(maxf(engine_throttle, boost))


func _normal_pitch_rate() -> float:
	# Input.get_axis("pitch_up", "pitch_down") makes positive input nose-down.
	var direction_factor := pitch_down_factor if pitch_input > 0.0 else 1.0
	return pitch_speed * _normal_turn_speed_factor() * direction_factor


func _normal_turn_speed_factor() -> float:
	if speed <= cruise_speed:
		return lerpf(
			low_speed_turn_factor,
			1.0,
			clampf(inverse_lerp(min_speed, cruise_speed, speed), 0.0, 1.0),
		)
	return lerpf(
		1.0,
		high_speed_turn_factor,
		clampf(inverse_lerp(cruise_speed, max_speed, speed), 0.0, 1.0),
	)


func _setup_aircraft_audio() -> void:
	var audio_manager := get_node_or_null("/root/AudioManager")
	_engine_audio = AudioStreamPlayer3D.new()
	_engine_audio.stream = ENGINE_STEADY_SOUND
	_accelerating_audio = AudioStreamPlayer3D.new()
	_accelerating_audio.stream = ENGINE_ACCELERATING_SOUND
	if audio_manager != null and audio_manager.has_method("setup_sfx_3d"):
		audio_manager.setup_sfx_3d(_engine_audio, -6.0)
		audio_manager.setup_sfx_3d(_accelerating_audio, -6.0)
	else:
		_engine_audio.bus = &"SFX"
		_engine_audio.volume_db = -6.0
		_accelerating_audio.bus = &"SFX"
		_accelerating_audio.volume_db = -6.0
	_engine_audio.finished.connect(_on_engine_finished)
	add_child(_engine_audio)
	_engine_audio.play()
	add_child(_accelerating_audio)


func _update_engine_audio(throttle: float) -> void:
	if _engine_audio != null:
		_engine_audio.pitch_scale = lerpf(0.86, 1.14, throttle)
	var accelerating := throttle > 0.6 and throttle_input > 0.1
	if accelerating and not _accelerating_audio_active and _accelerating_audio != null:
		_accelerating_audio.play()
	_accelerating_audio_active = accelerating


func _on_engine_finished() -> void:
	if is_alive():
		_engine_audio.play()


func _on_target_lock_completed(_target: Node3D) -> void:
	_play_ui_audio(&"play_target_lock")


func _play_ui_audio(method: StringName) -> void:
	var audio_manager := get_node_or_null("/root/AudioManager")
	if audio_manager != null:
		audio_manager.call(method)


func _detect_accelerate_double_tap() -> bool:
	var pressed := throttle_input > 0.5
	var tapped := pressed and not _accelerate_held
	_accelerate_held = pressed
	if not tapped:
		return false
	var gap := _flight_time - _last_accelerate_tap
	_last_accelerate_tap = _flight_time
	return gap <= spin_dash_tap_window


func _update_spin_dash() -> void:
	if spin_dash_active or not spin_dash_trigger:
		return
	if high_g_active or is_returning or _flight_time < _spin_dash_ready_at:
		return
	_begin_spin_dash()


func _begin_spin_dash() -> void:
	spin_dash_active = true
	_spin_dash_elapsed = 0.0
	_spin_dash_entry_basis = global_basis
	_spin_dash_direction = -global_basis.z
	_spin_dash_entry_speed = speed
	_spin_dash_velocity = _spin_dash_direction * speed
	_spin_dash_camera_hold_until = 0.0
	_spin_dash_camera_recover_until = 0.0


func _apply_spin_dash(delta: float) -> void:
	var total_time := spin_dash_charge_time + spin_dash_duration
	var step := minf(delta, maxf(total_time - _spin_dash_elapsed, 0.0))
	var previous_elapsed := _spin_dash_elapsed
	var previous_position := global_position
	_spin_dash_elapsed += step
	var charge_step := maxf(
		minf(_spin_dash_elapsed, spin_dash_charge_time)
		- minf(previous_elapsed, spin_dash_charge_time),
		0.0,
	)
	var burst_step := step - charge_step
	global_position += _spin_dash_direction * (
		_spin_dash_entry_speed * charge_step + spin_dash_speed * burst_step
	)
	global_position.y = clampf(global_position.y, min_altitude, max_altitude)

	if _spin_dash_elapsed <= spin_dash_charge_time:
		var charge := clampf(_spin_dash_elapsed / maxf(spin_dash_charge_time, 0.001), 0.0, 1.0)
		basis = _spin_dash_entry_basis
		speed = _spin_dash_entry_speed
		_afterburners.set_throttle(lerpf(0.35, 0.85, charge))
		_afterburners.set_boost(0.0)
	else:
		var progress := clampf(
			(_spin_dash_elapsed - spin_dash_charge_time) / maxf(spin_dash_duration, 0.001),
			0.0,
			1.0,
		)
		var phase := progress * TAU * spin_dash_turns
		basis = (_spin_dash_entry_basis * Basis(Vector3.FORWARD, phase)).orthonormalized()
		speed = spin_dash_speed
		_afterburners.set_throttle(1.0)
		_afterburners.set_boost(1.0)
	_spin_dash_velocity = (global_position - previous_position) / maxf(step, 0.001)
	_update_engine_audio(clampf(speed / maxf(max_speed, 0.001), 0.0, 1.0))
	if _spin_dash_elapsed >= total_time:
		_end_spin_dash()


func _end_spin_dash() -> void:
	spin_dash_active = false
	basis = _spin_dash_entry_basis
	speed = max_speed
	_spin_dash_velocity = _spin_dash_direction * speed
	_spin_dash_ready_at = _flight_time + spin_dash_cooldown
	_spin_dash_camera_hold_until = _flight_time + spin_dash_camera_hold
	_spin_dash_camera_recover_until = _spin_dash_camera_hold_until + spin_dash_camera_recovery


func spin_dash_cooldown_ratio() -> float:
	if spin_dash_cooldown <= 0.0:
		return 0.0
	return clampf((_spin_dash_ready_at - _flight_time) / spin_dash_cooldown, 0.0, 1.0)


func spin_dash_camera_recovery_weight() -> float:
	if spin_dash_active or _flight_time < _spin_dash_camera_hold_until:
		return 1.0
	if _flight_time >= _spin_dash_camera_recover_until:
		return 0.0
	return smoothstep(
		0.0,
		1.0,
		(_spin_dash_camera_recover_until - _flight_time) / maxf(spin_dash_camera_recovery, 0.001),
	)


func spin_dash_camera_depth_offset() -> float:
	if spin_dash_active and _spin_dash_elapsed < spin_dash_charge_time:
		var charge := _spin_dash_elapsed / maxf(spin_dash_charge_time, 0.001)
		return -spin_dash_camera_closeup * smoothstep(0.0, 1.0, charge)
	return spin_dash_camera_pullback * spin_dash_camera_recovery_weight()


func spin_dash_camera_fov_offset() -> float:
	if spin_dash_active and _spin_dash_elapsed < spin_dash_charge_time:
		return 0.0
	return spin_dash_camera_fov_boost * spin_dash_camera_recovery_weight()


## World velocity of the airframe. Weapons read this instead of assuming the nose ray times speed.
func velocity() -> Vector3:
	if spin_dash_active:
		return _spin_dash_velocity
	return _travel_direction() * speed


func camera_position() -> Vector3:
	return global_position


## Orientation the chase camera hangs from. During a spin dash it stays on the entry heading
## so the airframe rolls inside the frame.
func camera_basis() -> Basis:
	if spin_dash_active:
		return _spin_dash_entry_basis
	return global_basis


func _travel_direction() -> Vector3:
	return -global_basis.z


func _apply_triggers() -> void:
	if _targeting != null and cycle_trigger:
		_targeting.cycle_target()
	if _weapons == null:
		return
	if switch_missile_trigger:
		_weapons.cycle_missile_type()
		_play_ui_audio(&"play_weapon_switch")
	if gun_trigger:
		_weapons.fire_gun()
	if missile_trigger:
		_weapons.fire_missile()


func reset_player() -> void:
	reset_flight(_spawn_transform)


## Test and camera rigs may reposition a live player without changing its stored spawn.
func reset_flight(start_transform: Transform3D) -> void:
	global_transform = start_transform
	if is_inside_tree():
		reset_physics_interpolation()
	speed = cruise_speed
	high_g_active = false
	spin_dash_active = false
	spin_dash_trigger = false
	_accelerate_held = false
	_last_accelerate_tap = -1000.0
	_spin_dash_elapsed = 0.0
	_spin_dash_ready_at = 0.0
	_spin_dash_entry_basis = global_basis
	_spin_dash_direction = -global_basis.z
	_spin_dash_entry_speed = speed
	_spin_dash_velocity = Vector3.ZERO
	_spin_dash_camera_hold_until = 0.0
	_spin_dash_camera_recover_until = 0.0
	_afterburners.set_boost(0.0)
	is_returning = false
	health = max_health
	visible = true
	if _hitbox != null:
		_hitbox.collision_layer = 8
	_incoming_missiles.clear()
	if faction_group == "player":
		_play_ui_audio(&"stop_alarm")
	_setup_collision_detection()
	_accelerating_audio_active = false
	if _engine_audio != null and not _engine_audio.playing:
		_engine_audio.play()
	_update_damage_effects()
	if _weapons != null:
		_weapons.reset_loadout()


func _setup_collision_detection() -> void:
	if _hitbox == null:
		return
	# Any PhysicsBody3D is solid; Areas remain reserved for combat hit detection.
	_hitbox.collision_mask = 0xFFFFFFFF
	_hitbox.monitoring = true
	_hitbox.monitorable = true
	if not _hitbox.body_entered.is_connected(_on_solid_collision):
		_hitbox.body_entered.connect(_on_solid_collision)


func _on_solid_collision(_body: Node3D) -> void:
	if is_alive():
		apply_damage(max_health)


func apply_damage(amount: float) -> void:
	if amount <= 0.0 or not is_alive():
		return
	health = maxf(health - amount, 0.0)
	_update_damage_effects()
	if health <= 0.0:
		_die()


func is_alive() -> bool:
	return health > 0.0


func target_label() -> String:
	return label


## Missiles announce themselves so the AI can break and the HUD can warn.
func missile_incoming(missile: Node3D) -> void:
	if not _incoming_missiles.has(missile):
		_incoming_missiles.append(missile)
		if faction_group == "player":
			_play_ui_audio(&"play_alarm")


func missile_cleared(missile: Node3D) -> void:
	_incoming_missiles.erase(missile)
	if faction_group == "player" and active_missiles().is_empty():
		_play_ui_audio(&"stop_alarm")


func active_missiles() -> Array:
	var prev_count := _incoming_missiles.size()
	_incoming_missiles = _incoming_missiles.filter(func(missile): return is_instance_valid(missile))
	if faction_group == "player" and prev_count > 0 and _incoming_missiles.is_empty():
		_play_ui_audio(&"stop_alarm")
	return _incoming_missiles


func _die() -> void:
	if faction_group == "player":
		_incoming_missiles.clear()
		_play_ui_audio(&"stop_alarm")
	if _hitbox != null:
		_hitbox.set_deferred("monitoring", false)
		_hitbox.set_deferred("monitorable", false)
		_hitbox.collision_layer = 0
	visible = false
	var explosion_parent := get_parent()
	if explosion_parent == null:
		explosion_parent = get_tree().current_scene
	Explosion.spawn_aircraft(explosion_parent, global_position, 3.0)
	if _engine_audio != null:
		_engine_audio.stop()
	if _accelerating_audio != null:
		_accelerating_audio.stop()
	destroyed.emit(self)


func _update_damage_effects() -> void:
	var ratio := health / maxf(max_health, 0.001)
	var intensity := clampf(inverse_lerp(damage_start_ratio, damage_full_ratio, ratio), 0.0, 1.0)
	for emitter in _damage_emitters:
		emitter.set_intensity(intensity)


func _return_to_arena(delta: float) -> void:
	var distance_from_center := Vector2(global_position.x, global_position.z).length()
	is_returning = distance_from_center > return_distance
	if not is_returning:
		return

	var center_direction := Vector3(-global_position.x, 0.0, -global_position.z).normalized()
	basis = basis.slerp(Basis.looking_at(center_direction, Vector3.UP), 1.0 - exp(-1.5 * delta))
	global_position.x = clampf(global_position.x, -arena_half_size, arena_half_size)
	global_position.z = clampf(global_position.z, -arena_half_size, arena_half_size)
