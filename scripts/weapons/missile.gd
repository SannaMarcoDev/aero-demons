extends Node3D
class_name HomingMissile

const MissileCatalog = preload("res://scripts/weapons/missile_catalog.gd")
const MISSILE_THRUSTER_SOUND: AudioStream = preload("res://assets/audio/sfx/weapons/missile-thruster.mp3")

@export var speed := 380.0
@export var acceleration := 760.0
@export var max_turn_rate_degrees := 60.0
@export var seeker_fov_degrees := 55.0
@export var max_range := 5000.0
@export var lifetime := 12.0
@export var damage := 60.0
var hit_callback := Callable()
@export var proximity_radius := 25.0
@export var missile_id := "STDM"
@export var burn_total := 0.0
@export var burn_duration := 0.0
@export var gravity := 24.0

var target = null
var velocity := Vector3.ZERO
var audio_enabled := true
var audio_volume_db_offset := 0.0

var _age := 0.0
var _distance_traveled := 0.0
var _current_speed := 0.0
var _launched := false
var _detonated := false
var _ballistic := false
var _fall_time := 0.0
var _straight_flight_remaining := 0.0
var _payload_enabled := false
var _payload_targets: Array = []
var _payload_split_delay := 0.0
var _payload_spread_degrees := 0.0
var _payload_straight_time := 0.0
var _payload_phase := 0.0
var _smoke_intensity := 1.0
var _flame_budget := 0.0
var _flame_emission_scale := 1.0
var _smoke_core_budget := 0.0
var _smoke_trail_budget := 0.0

# --- Idea B/C/D/F: visibilità ---
var _boost_remaining := 0.0
var _phase := 0.0
var _light_scale := 1.0
var _vis_scale := 1.0
const BOOST_DURATION := 0.42
const BASE_LIGHT_ENERGY := 6.0
const BASE_LIGHT_RANGE := 18.0
var _flame: GPUParticles3D = null
var _smoke_core: GPUParticles3D = null
var _smoke_trail: GPUParticles3D = null
var _engine_light: OmniLight3D = null
var _thruster_audio: AudioStreamPlayer3D


func launch(start_transform: Transform3D, inherited_velocity: Vector3, target_ref) -> void:
	global_transform = start_transform
	target = target_ref
	_age = 0.0
	_distance_traveled = 0.0
	_fall_time = 0.0
	_ballistic = false
	_detonated = false
	_launched = true
	_current_speed = maxf(inherited_velocity.length(), 1.0)
	velocity = -global_basis.z * _current_speed
	_orient_to_velocity()
	_cache_nodes()
	_apply_visual()
	_trigger_boost()
	_start_thruster()
	_play_spatial_audio(&"play_missile_launch")
	if target != null and target.has_method("missile_incoming"):
		target.call("missile_incoming", self)
	if _payload_enabled:
		_notify_payload_incoming()


func _physics_process(delta: float) -> void:
	if not _launched or _detonated:
		return
	_age += delta
	if not _ballistic and (_age >= lifetime or _distance_traveled >= max_range):
		_payload_enabled = false
		_lose_tracking()
	_update_visuals(delta)
	if _payload_enabled and _age >= _payload_split_delay:
		_release_payload()
		return

	if _ballistic:
		_fall_time += delta
		velocity.y -= gravity * delta
		velocity *= (1.0 - 0.12 * delta)
		var prev_pos := global_position
		global_position += velocity * delta
		_orient_to_velocity()
		var space_state := get_world_3d().direct_space_state
		if space_state != null:
			var query := PhysicsRayQueryParameters3D.create(prev_pos, global_position)
			query.collide_with_areas = false
			query.collide_with_bodies = true
			var hit := space_state.intersect_ray(query)
			if not hit.is_empty():
				global_position = hit.get("position", global_position)
				_detonate()
				return
		if global_position.y <= 0.0 or _fall_time >= 5.0 or _age >= 25.0:
			_detonate()
			return
		return

	var straight_flight := _straight_flight_remaining > 0.0
	_straight_flight_remaining = maxf(_straight_flight_remaining - delta, 0.0)
	_current_speed = move_toward(_current_speed, speed, acceleration * delta)
	if _payload_enabled:
		# Carrier stage: accelerates and flies straight forward along launch trajectory until split
		pass
	elif _target_is_alive(target):
		if _check_target_proximity():
			return
		if not straight_flight:
			_steer_toward_target(delta)
	else:
		_lose_tracking()

	if _ballistic:
		return

	velocity = velocity.normalized() * _current_speed
	var prev_pos := global_position
	var trail_from := _flame_origin()
	global_position += velocity * delta
	_distance_traveled += velocity.length() * delta
	_orient_to_velocity()
	var trail_to := _flame_origin()
	_flame_budget = _emit_particle_segment(_flame, trail_from, trail_to, delta, _flame_budget, _flame_emission_scale)
	_emit_smoke_segment(trail_from, trail_to, delta)

	if not _payload_enabled and _check_target_proximity():
		return

	var space_state := get_world_3d().direct_space_state
	if space_state != null:
		var query := PhysicsRayQueryParameters3D.create(prev_pos, global_position)
		query.collide_with_areas = false
		query.collide_with_bodies = true
		var hit := space_state.intersect_ray(query)
		if not hit.is_empty():
			global_position = hit.get("position", global_position)
			_detonate()
			return


## Arms this instance as a straight-flying carrier. Children are ordinary homing missiles.
func configure_split_payload(targets: Array, delay: float, spread_degrees: float, straight_time: float, phase: float) -> void:
	_payload_targets = targets.duplicate()
	_payload_split_delay = maxf(delay, 0.0)
	_payload_spread_degrees = maxf(spread_degrees, 0.0)
	_payload_straight_time = maxf(straight_time, 0.0)
	_payload_phase = phase
	_payload_enabled = not _payload_targets.is_empty()
	set_smoke_intensity(0.0)
	if _launched:
		_notify_payload_incoming()


func _notify_payload_incoming() -> void:
	for payload_target in _payload_targets:
		if _target_is_alive(payload_target) and payload_target.has_method("missile_incoming"):
			payload_target.call("missile_incoming", self)


func set_straight_flight(duration: float) -> void:
	_straight_flight_remaining = maxf(duration, 0.0)


func set_smoke_intensity(intensity: float) -> void:
	_smoke_intensity = clampf(intensity, 0.0, 1.0)


func _flame_origin() -> Vector3:
	return _flame.global_position if _flame != null else global_position


func _emit_smoke_segment(from: Vector3, to: Vector3, delta: float) -> void:
	_smoke_core_budget = _emit_particle_segment(_smoke_core, from, to, delta, _smoke_core_budget, _smoke_intensity)
	_smoke_trail_budget = _emit_particle_segment(_smoke_trail, from, to, delta, _smoke_trail_budget, _smoke_intensity)


func _emit_particle_segment(emitter: GPUParticles3D, from: Vector3, to: Vector3, delta: float, budget: float, density: float) -> float:
	if emitter == null or density <= 0.0 or delta <= 0.0:
		return budget
	var rate := float(emitter.amount) / emitter.lifetime * density
	var generated := rate * delta
	var count := floori(budget + generated)
	for index in count:
		var weight := (float(index + 1) - budget) / generated
		var xform := Transform3D(Basis.IDENTITY, from.lerp(to, clampf(weight, 0.0, 1.0)))
		emitter.emit_particle(xform, Vector3.ZERO, Color.WHITE, Color.WHITE, GPUParticles3D.EMIT_FLAG_POSITION)
	return budget + generated - float(count)


func _release_payload() -> void:
	_payload_enabled = false
	var scene := load("res://scenes/weapons/missile.tscn") as PackedScene
	var parent := get_parent()
	if scene != null and parent != null:
		for index in _payload_targets.size():
			var payload_target = _payload_targets[index]
			if not _target_is_alive(payload_target):
				continue
			var child := scene.instantiate() as HomingMissile
			if child == null:
				continue
			var direction := _payload_direction(payload_target as Node3D, index, _payload_targets.size())
			var up := global_basis.y.normalized()
			if absf(direction.dot(up)) > 0.98:
				up = global_basis.x.normalized()
			child.missile_id = missile_id
			child.speed = speed
			child.acceleration = acceleration
			child.max_turn_rate_degrees = max_turn_rate_degrees
			child.seeker_fov_degrees = seeker_fov_degrees
			child.max_range = max_range
			child.lifetime = lifetime
			child.damage = damage
			child.hit_callback = hit_callback
			child.proximity_radius = proximity_radius
			child.burn_total = burn_total
			child.burn_duration = burn_duration
			child.gravity = gravity
			child.audio_enabled = true
			child.audio_volume_db_offset = -14.0
			child.set_smoke_intensity(0.10)
			child.set_straight_flight(_payload_straight_time)
			parent.add_child(child)
			child.add_to_group("mission_projectiles")
			child.launch(Transform3D(Basis.looking_at(direction, up), global_position), velocity, payload_target)
	_detonated = true
	_stop_thruster()
	_clear_threat()
	queue_free()


func _payload_direction(payload_target: Node3D, index: int, count: int) -> Vector3:
	var desired := payload_target.global_position - global_position
	if desired.length_squared() <= 0.000001:
		desired = -global_basis.z
	else:
		desired = desired.normalized()
	var angle := _payload_phase + TAU * float(index) / maxf(float(count), 1.0)
	var radial := global_basis.x.normalized() * cos(angle) + global_basis.y.normalized() * sin(angle)
	return (desired + radial * tan(deg_to_rad(_payload_spread_degrees))).normalized()


func _check_target_proximity() -> bool:
	if not _target_is_alive(target):
		return false
	var target_position: Vector3 = target.get("global_position")
	if global_position.distance_to(target_position) > proximity_radius:
		return false
	if damage > 0.0:
		target.call("apply_damage", damage)
	if burn_total > 0.0 and burn_duration > 0.0 and target.has_method("apply_napalm"):
		target.call("apply_napalm", burn_total, burn_duration, self)
	elif burn_total > 0.0 and target.has_method("apply_damage"):
		# fallback se il bersaglio non ha DoT: applica subito il burn come danno unico
		target.call("apply_damage", burn_total)
	if (damage > 0.0 or burn_total > 0.0) and hit_callback.is_valid():
		hit_callback.call()
	_detonate()
	return true


func _steer_toward_target(delta: float) -> void:
	if not _target_is_alive(target):
		_lose_tracking()
		return
	var target_position: Vector3 = target.get("global_position")
	var offset := target_position - global_position
	if offset.length_squared() <= 0.000001:
		return
	var current_direction := velocity.normalized()
	var desired_direction := offset.normalized()
	var angle := current_direction.angle_to(desired_direction)
	if angle > deg_to_rad(seeker_fov_degrees):
		_lose_tracking()
		return
	var max_turn := deg_to_rad(max_turn_rate_degrees) * delta
	var turn_weight := 1.0 if angle <= max_turn else max_turn / angle
	var direction := current_direction.slerp(desired_direction, clampf(turn_weight, 0.0, 1.0)).normalized()
	velocity = direction * _current_speed


func _lose_tracking() -> void:
	if _ballistic:
		return
	_ballistic = true
	_clear_threat()
	_stop_thruster()
	_cache_nodes()
	if _engine_light != null:
		_engine_light.light_energy = 0.0
	if _flame != null:
		_flame.emitting = false
	if _smoke_core != null:
		_smoke_core.emitting = false
	if _smoke_trail != null:
		_smoke_trail.emitting = false


func _target_is_alive(candidate) -> bool:
	if candidate == null or not is_instance_valid(candidate) or not (candidate is Node3D):
		return false
	if not candidate.is_inside_tree() or not candidate.has_method("is_alive"):
		return false
	return bool(candidate.call("is_alive"))


func _exit_tree() -> void:
	_clear_threat()


func _clear_threat() -> void:
	if target != null and is_instance_valid(target) and target.has_method("missile_cleared"):
		target.call("missile_cleared", self)
	target = null
	for payload_target in _payload_targets:
		if payload_target != null and is_instance_valid(payload_target) and payload_target.has_method("missile_cleared"):
			payload_target.call("missile_cleared", self)
	_payload_targets.clear()


func _detonate() -> void:
	if _detonated:
		return
	_detonated = true
	_stop_thruster()
	_play_spatial_audio(&"play_missile_hit")
	var scale := 0.35 if missile_id == "MTSM" else 1.0
	if missile_id == "BAHM":
		scale = 1.7
	elif missile_id == "NCGBM":
		scale = 1.25
	Explosion.spawn(get_parent(), global_position, scale)
	_clear_threat()
	queue_free()


func _play_spatial_audio(method: StringName) -> void:
	if not audio_enabled:
		return
	var audio_manager := get_node_or_null("/root/AudioManager")
	if audio_manager != null:
		if is_equal_approx(audio_volume_db_offset, 0.0):
			audio_manager.call(method, get_parent(), global_position)
		else:
			var base_vol := -4.0 if method == &"play_missile_launch" else -7.5
			audio_manager.call(method, get_parent(), global_position, base_vol + audio_volume_db_offset)


func _start_thruster() -> void:
	if not audio_enabled:
		return
	if _thruster_audio == null:
		_thruster_audio = AudioStreamPlayer3D.new()
		_thruster_audio.stream = MISSILE_THRUSTER_SOUND
		var audio_manager := get_node_or_null("/root/AudioManager")
		if audio_manager != null and audio_manager.has_method("setup_sfx_3d"):
			audio_manager.setup_sfx_3d(_thruster_audio, -10.0 + audio_volume_db_offset)
		else:
			_thruster_audio.bus = &"SFX"
			_thruster_audio.volume_db = -10.0 + audio_volume_db_offset
		_thruster_audio.finished.connect(_on_thruster_finished)
		add_child(_thruster_audio)
	if not _thruster_audio.playing:
		_thruster_audio.play()


func _stop_thruster() -> void:
	if _thruster_audio != null:
		_thruster_audio.stop()


func _on_thruster_finished() -> void:
	if audio_enabled and _launched and not _detonated and is_inside_tree() and not _ballistic:
		_thruster_audio.play()


func _cache_nodes() -> void:
	if _flame == null:
		_flame = get_node_or_null("Flame") as GPUParticles3D
	if _smoke_core == null:
		_smoke_core = get_node_or_null("SmokeCore") as GPUParticles3D
	if _smoke_trail == null:
		_smoke_trail = get_node_or_null("SmokeTrail") as GPUParticles3D
	if _engine_light == null:
		_engine_light = get_node_or_null("EngineLight") as OmniLight3D


func _trigger_boost() -> void:
	_boost_remaining = BOOST_DURATION
	_phase = randf() * 6.28
	if _engine_light != null:
		_engine_light.light_energy = BASE_LIGHT_ENERGY * _light_scale * 2.4
		_engine_light.omni_range = BASE_LIGHT_RANGE * (0.85 + 0.3 * _vis_scale) * 1.35
	_flame_budget = 0.0
	_flame_emission_scale = 1.9
	_smoke_core_budget = 0.0
	_smoke_trail_budget = 0.0


func _update_visuals(delta: float) -> void:
	if _ballistic:
		return
	_cache_nodes()
	if _engine_light == null:
		return
	_phase += delta
	var flick := 0.5 * sin(_phase * 19.0) + 0.5 * sin(_phase * 7.3 + 1.7)
	var flick_factor := 1.0 - 0.18 * (0.5 - 0.5 * flick)
	if _boost_remaining > 0.0:
		_boost_remaining = maxf(_boost_remaining - delta, 0.0)
		var t := _boost_remaining / BOOST_DURATION
		var boost_factor := 1.0 + t * 1.4
		_engine_light.light_energy = BASE_LIGHT_ENERGY * _light_scale * boost_factor * flick_factor
		_engine_light.omni_range = BASE_LIGHT_RANGE * (0.85 + 0.3 * _vis_scale) * (1.0 + t * 0.35)
		_flame_emission_scale = 1.0 + t * 0.9
	else:
		_engine_light.light_energy = BASE_LIGHT_ENERGY * _light_scale * flick_factor
		_flame_emission_scale = 1.0


func _apply_visual() -> void:
	var body := get_node_or_null("Body") as MeshInstance3D
	if body == null:
		return
	var def := MissileCatalog.get_def(missile_id)
	var col: Color = def.get("color", Color(0.22, 0.28, 0.35, 1))
	var mat := body.get_active_material(0) as StandardMaterial3D
	if mat != null:
		mat = mat.duplicate()
		mat.albedo_color = col
		# ponytail: emissive cheap glow without extra geo, visible at 2km
		mat.emission_enabled = true
		if missile_id == "BAHM":
			mat.emission = Color(0.38, 0.32, 0.30)
			mat.emission_energy_multiplier = 1.25
		elif missile_id == "NCGBM":
			mat.emission = Color(1.0, 0.32, 0.08)
			mat.emission_energy_multiplier = 1.55
		elif missile_id == "HSSTDM":
			mat.emission = Color(0.45, 0.72, 0.95)
			mat.emission_energy_multiplier = 1.35
		elif missile_id == "MTSM":
			mat.emission = Color(0.36, 0.26, 0.50)
			mat.emission_energy_multiplier = 1.15
		else:
			mat.emission = col.lightened(0.35)
			mat.emission_energy_multiplier = 1.4
		body.material_override = mat
	var scl: float = float(def.get("scale", 1.0))
	# Idea D: mesh base già 2.3x (0.14→0.32), enforce minimum per non tornare invisibile
	scl = maxf(scl, 1.15)
	if missile_id == "BAHM":
		scl *= 1.12
	elif _payload_enabled:
		scl *= 1.25
	_vis_scale = scl
	body.scale = Vector3.ONE * scl

	_cache_nodes()
	# --- luce motore per tipo ---
	if _engine_light != null:
		var light_col: Color
		if missile_id == "HSSTDM":
			light_col = Color(0.55, 0.82, 1.0)
			_light_scale = 1.0
		elif missile_id == "MTSM":
			light_col = Color(1.0, 0.62, 0.30)
			_light_scale = 1.0
		elif missile_id == "BAHM":
			light_col = Color(1.0, 0.5, 0.18)
			_light_scale = 1.25
		elif missile_id == "NCGBM":
			light_col = Color(1.0, 0.32, 0.08)
			_light_scale = 1.15
		else:
			light_col = Color(1.0, 0.60, 0.28)
			_light_scale = 1.0
		_engine_light.light_color = light_col
		_engine_light.light_energy = BASE_LIGHT_ENERGY * _light_scale
		_engine_light.omni_range = BASE_LIGHT_RANGE * (0.85 + 0.3 * _vis_scale)

	# --- scala particelle proporzionale alla taglia ---
	var payload_visual_scale := 1.0
	if _flame != null:
		var pm := _flame.process_material as ParticleProcessMaterial
		if pm != null:
			pm = pm.duplicate() as ParticleProcessMaterial
			var f := (0.9 + 0.22 * _vis_scale) * payload_visual_scale
			pm.scale_min *= f
			pm.scale_max *= f
			_flame.process_material = pm
	for emitter in [_smoke_core, _smoke_trail]:
		if emitter == null:
			continue
		var pmat := emitter.process_material as ParticleProcessMaterial
		if pmat == null:
			continue
		pmat = pmat.duplicate() as ParticleProcessMaterial
		var f2 := (0.85 + 0.3 * _vis_scale) * payload_visual_scale * 0.72
		pmat.scale_min *= f2
		pmat.scale_max *= f2
		if missile_id == "BAHM":
			pmat.color = Color(0.88, 0.88, 0.9, 0.78)
		elif missile_id == "NCGBM":
			pmat.color = Color(0.94, 0.92, 0.9, 0.72)
		elif missile_id == "HSSTDM":
			pmat.color = Color(0.92, 0.95, 1.0, 0.68)
		elif missile_id == "MTSM":
			pmat.color = Color(0.9, 0.9, 0.93, 0.70)
		else:
			pmat.color = Color(0.94, 0.95, 0.97, 0.72)
		emitter.process_material = pmat
		# Schiarisce anche il materiale condiviso senza alterare il fumo dei danni.
		var quad := emitter.draw_pass_1 as QuadMesh
		if quad != null:
			quad = quad.duplicate() as QuadMesh
			var smat := quad.material as ShaderMaterial
			if smat != null:
				smat = smat.duplicate() as ShaderMaterial
				if missile_id == "BAHM":
					smat.set_shader_parameter("soot_tint", Color(0.68, 0.68, 0.7, 1))
					smat.set_shader_parameter("aged_tint", Color(0.9, 0.9, 0.92, 1))
				elif missile_id == "NCGBM":
					smat.set_shader_parameter("soot_tint", Color(0.74, 0.72, 0.7, 1))
					smat.set_shader_parameter("aged_tint", Color(0.95, 0.93, 0.91, 1))
				else:
					smat.set_shader_parameter("soot_tint", Color(0.74, 0.75, 0.78, 1))
					smat.set_shader_parameter("aged_tint", Color(0.96, 0.97, 1.0, 1))
				smat.set_shader_parameter("edge_start", 0.0)
				smat.set_shader_parameter("edge_falloff", 0.8)
				smat.set_shader_parameter("erosion", 0.5)
				smat.set_shader_parameter("erosion_young", 0.25)
				smat.set_shader_parameter("noise_contrast", 1.5)
				smat.set_shader_parameter("opacity", 0.7)
				# ponytail: same particle count keeps the narrower trail equally dense
				quad.material = smat
			emitter.draw_pass_1 = quad


func _orient_to_velocity() -> void:
	if velocity.length_squared() <= 0.000001:
		return
	var direction := velocity.normalized()
	var up := Vector3.UP
	if absf(direction.dot(up)) > 0.98:
		up = Vector3.FORWARD
	look_at(global_position + direction, up)
