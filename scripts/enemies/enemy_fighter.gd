extends PlayerFlight
class_name EnemyFighter
## One pilot for both teams. Assignment, tactics, steering, safety and fire gates stay separate;
## PlayerFlight remains the only component applying inputs to the airframe.

signal state_changed(fighter: Node3D, state: int)
enum State { REPOSITION, SETUP_ATTACK, ATTACK, EXTEND, DEFEND, EVADE_MISSILE, RECOVER, DESTROYED }
enum Policy { ENEMY, COVER, SUPPORT }

@export_category("Assignment")
@export var policy := Policy.ENEMY
@export var cover_return_seconds := 12.0
@export var support_return_seconds := 20.0
@export var reposition_duration := 2.0
@export var reposition_distance := 850.0
@export var duel_speed := 140.0
@export var formation_spacing := 250.0

@export_category("Tactics")
@export var attack_range := 1800.0
@export var attack_cone_degrees := 25.0
@export var attack_duration := 3.5
@export var setup_stall_duration := 7.0
@export var extend_distance := 850.0
@export var extend_duration := 5.0
@export var defend_duration := 1.5
@export var evade_duration := 2.0
@export var recover_duration := 2.5
@export var evade_cooldown := 2.0
@export var threatened_distance := 1200.0
@export var missile_threat_distance := 1100.0
@export var missile_reaction_delay := 0.45
@export_range(0.1, 1.0) var evade_quality := 0.8

@export_category("Flight")
@export var turn_gain := 2.6
@export var fine_tracking_error := 0.15
@export var fine_tracking_gain := 6.0
@export var min_combat_speed := 100.0
@export var terrain_clearance := 400.0
@export var safety_lookahead := 3.0
@export var aircraft_separation := 100.0

@export_category("Weapons")
@export var gun_miss_tolerance := 25.0
@export var gun_open_range := 650.0
@export var minimum_fire_range := 150.0
@export var missile_launch_range := 1800.0
@export var burst_duration := 0.45
@export var burst_interval := 4.5
@export var reaction_delay := 0.6
@export var aim_stable_duration := 0.25
@export_range(0.0, 1.0) var aim_accuracy := 0.8

@export_category("Wreck")
@export var wreck_gravity := 26.0
@export var wreck_drag := 0.35
@export var wreck_spin_degrees := Vector3(35.0, 20.0, 150.0)
@export var wreck_explosion_interval := 2.0
@export var wreck_explosion_scale := 1.0
@export var wreck_impact_clearance := 15.0
@export var wreck_max_fall_time := 30.0

var director: Node
var role := "UNASSIGNED"
var assignment_target: Node3D
var assignment_age := 0.0
var state := State.REPOSITION
var last_transition := "SPAWN"
var fire_block := "NO_TARGET"
var gun_block := "NO_TARGET"
var missile_block := "NO_TARGET"
var safety_active := false
var wreck_cook_offs := 0
var _age := 0.0
var _state_time := 0.0
var _burst_time := 0.0
var _evade_blocked_until := 0.0
var _maneuver_point := Vector3.ZERO
var _maneuver_direction := Vector3.FORWARD
var _maneuver_origin := Vector3.ZERO
var _best_solution := INF
var _progress_time := 0.0
var _gun_stable_time := 0.0
var _missile_stable_time := 0.0
var _missile_seen_time := 0.0
var _tracked_threat: Node3D
var _terrain_data = null
var _wreck_velocity := Vector3.ZERO
var _wreck_spin := Vector3.ZERO
var _wreck_time := 0.0
var _wreck_next_explosion := 0.0


func _ready() -> void:
	super()
	add_to_group("combat_ai")
	if faction_group != "targets":
		add_to_group("combat_allies")
		_hitbox.collision_layer = 8
		_weapons.target_layers = 4
	else:
		_hitbox.collision_layer = 4
		_weapons.target_layers = 8
	_targeting.target_group = "combat_allies" if faction_group == "targets" else "targets"
	_targeting.auto_acquire = false
	_terrain_data = _find_terrain_data()
	_maneuver_point = global_position - global_basis.z * reposition_distance
	_maneuver_direction = -global_basis.z


func _physics_process(delta: float) -> void:
	if state == State.DESTROYED:
		_fall(delta)
		return
	# Use the actual simulation step, including deterministic headless checks.
	_tick_ai(delta)
	_apply_flight(delta)
	_apply_triggers()


func _update_controls() -> void:
	_tick_ai(get_physics_process_delta_time())


func assign(next_role: String, target: Node3D) -> void:
	if not is_instance_valid(assignment_target):
		assignment_target = null
	if not CombatDirector.alive(target):
		target = null
	if role == next_role and assignment_target == target:
		return
	var changed_target := assignment_target != target
	if is_instance_valid(director):
		director.release_attack(self)
	role = next_role
	assignment_target = target
	assignment_age = 0.0
	_targeting._set_target(target)
	if changed_target and state not in [State.DEFEND, State.EVADE_MISSILE, State.RECOVER, State.DESTROYED]:
		_set_state(State.REPOSITION, "NEW_ASSIGNMENT", true)


func _tick_ai(delta: float) -> void:
	pitch_input = 0.0
	yaw_input = 0.0
	roll_input = 0.0
	throttle_input = 0.0
	brake_input = 0.0
	gun_trigger = false
	missile_trigger = false
	cycle_trigger = false
	switch_missile_trigger = false
	spin_dash_trigger = false
	high_g_active = false
	safety_active = false
	if not is_alive():
		return
	_age += delta
	_state_time += delta
	assignment_age += delta
	_burst_time += delta
	if not is_instance_valid(director) and not CombatDirector.alive(assignment_target):
		assign("PLAYER_PRESSURE" if faction_group == "targets" else "SUPPORT", _targeting._first_candidate())
	if not CombatDirector.alive(assignment_target):
		assignment_target = null
	_targeting._set_target(assignment_target)
	_update_tactics(delta)
	_fly_maneuver()
	_apply_safety()
	_update_fire_solution(delta)
	gun_block = weapon_fire_block("gun")
	missile_block = weapon_fire_block("missile")
	gun_trigger = gun_block == "READY"
	missile_trigger = missile_block == "READY"
	fire_block = "READY" if gun_trigger or missile_trigger else "GUN: %s / MSL: %s" % [gun_block, missile_block]


func _update_tactics(delta: float) -> void:
	var missile := _dangerous_missile()
	if missile != _tracked_threat:
		_tracked_threat = missile
		_missile_seen_time = 0.0
	if missile != null:
		_missile_seen_time += delta
		if _missile_seen_time >= missile_reaction_delay and state != State.EVADE_MISSILE:
			_set_state(State.EVADE_MISSILE, "INCOMING_MISSILE")
	if state == State.EVADE_MISSILE:
		if missile == null or _state_time >= evade_duration:
			_set_state(State.RECOVER, "EVASION_COMPLETE")
			# A persistent missile must be re-evaluated, not trigger a fresh break every frame.
			_missile_seen_time = 0.0
		return
	if state == State.DEFEND:
		if _state_time >= defend_duration:
			_set_state(State.RECOVER, "DEFENSE_COMPLETE")
		return
	if state == State.RECOVER:
		if _state_time >= recover_duration:
			_set_state(State.REPOSITION, "RECOVERED")
		return
	if _age >= _evade_blocked_until and _tail_threat() != null:
		_set_state(State.DEFEND, "THREAT_ON_SIX")
		return
	if _outside_leash():
		if state != State.REPOSITION:
			_set_state(State.REPOSITION, "COVER_LEASH")
		return
	if assignment_target == null:
		if state != State.REPOSITION:
			_set_state(State.REPOSITION, "NO_TARGET")
		if _state_time >= reposition_duration:
			_set_state(State.REPOSITION, "HOLD_AREA", true)
		return
	var offset := assignment_target.global_position - global_position
	var distance := offset.length()
	var angle := (-global_basis.z).angle_to(offset.normalized())
	match state:
		State.REPOSITION:
			if _state_time >= reposition_duration:
				_set_state(State.SETUP_ATTACK, "POSITION_READY")
		State.SETUP_ATTACK:
			var solution := distance / attack_range + angle
			if solution < _best_solution - 0.08:
				_best_solution = solution
				_progress_time = 0.0
			else:
				_progress_time += delta
			if distance < minimum_fire_range:
				_set_state(State.EXTEND, "TOO_CLOSE")
			elif _progress_time >= setup_stall_duration:
				_set_state(State.EXTEND, "NO_PROGRESS")
			elif distance <= attack_range and angle <= deg_to_rad(attack_cone_degrees):
				if not is_instance_valid(director) or director.request_attack(self):
					_set_state(State.ATTACK, "ATTACK_AUTHORIZED")
				elif _state_time >= setup_stall_duration:
					_set_state(State.REPOSITION, "WAIT_PERMISSION")
		State.ATTACK:
			if distance < minimum_fire_range or distance > attack_range * 1.25 \
					or angle > deg_to_rad(attack_cone_degrees * 1.5) or _state_time >= attack_duration:
				_set_state(State.EXTEND, "PASS_COMPLETE")
			elif is_instance_valid(director) and assignment_target == director.player and not director.has_permission(self):
				_set_state(State.EXTEND, "PERMISSION_EXPIRED")
		State.EXTEND:
			if global_position.distance_to(_maneuver_origin) >= extend_distance or _state_time >= extend_duration:
				_set_state(State.REPOSITION, "SEPARATION_READY")


func _set_state(next_state: int, reason := "TACTICAL", restart := false) -> void:
	if state == next_state and not restart:
		return
	if state == State.ATTACK and is_instance_valid(director):
		director.release_attack(self)
	if state in [State.DEFEND, State.EVADE_MISSILE]:
		_evade_blocked_until = _age + recover_duration + evade_cooldown
	state = next_state
	last_transition = reason
	_state_time = 0.0
	_best_solution = INF
	_progress_time = 0.0
	_gun_stable_time = 0.0
	_missile_stable_time = 0.0
	_maneuver_origin = global_position
	_maneuver_direction = -global_basis.z
	if state in [State.DEFEND, State.EVADE_MISSILE]:
		var threat := _dangerous_missile() if state == State.EVADE_MISSILE else _tail_threat()
		var away := global_position - threat.global_position if threat != null else global_basis.z
		var across := away.normalized().cross(Vector3.UP)
		if across.length_squared() < 0.001:
			across = global_basis.x
		if across.dot(global_basis.x) < 0.0:
			across = -across
		_maneuver_direction = across.normalized()
	elif state == State.REPOSITION:
		_maneuver_point = _reposition_point()
	elif state == State.RECOVER:
		_maneuver_direction.y = clampf(_maneuver_direction.y, -0.1, 0.15)
		_maneuver_direction = _maneuver_direction.normalized()
	state_changed.emit(self, state)


func _outside_leash() -> bool:
	if faction_group == "targets" or not is_instance_valid(director) or not CombatDirector.alive(director.player):
		return false
	var seconds := cover_return_seconds if role == "COVER" else support_return_seconds
	return global_position.distance_to(director.player.global_position) / maxf(cruise_speed, 1.0) > seconds


func _reposition_point() -> Vector3:
	var anchor: Node3D = assignment_target
	if not CombatDirector.alive(anchor) and is_instance_valid(director) and CombatDirector.alive(director.player):
		anchor = director.player
	if not CombatDirector.alive(anchor):
		return global_position + (_spawn_transform.origin - global_position).normalized() * reposition_distance + Vector3.UP * 50.0
	var side := 1.0 if get_index() % 2 == 0 else -1.0
	# Stable points relative to the actual opponent, not random world waypoints.
	return anchor.global_position - anchor.global_basis.z * reposition_distance \
		+ anchor.global_basis.x * side * reposition_distance * 0.7 + Vector3.UP * 100.0


func _fly_maneuver() -> void:
	var point := _maneuver_point
	var desired_speed := cruise_speed
	if state == State.REPOSITION and assignment_target == null and faction_group == "allies" \
			and is_instance_valid(director) and CombatDirector.alive(director.player):
		var leader: PlayerFlight = director.player
		var side := -1.0 if policy == Policy.COVER else 1.0
		var slot := leader.global_position + leader.global_basis.x * side * formation_spacing
		# Follow a moving slot, not a stationary waypoint: match the leader once alongside.
		var formation_velocity := leader.velocity() + (slot - global_position) * 0.5
		point = global_position + formation_velocity * 3.0
		desired_speed = clampf(formation_velocity.length(), min_speed, max_speed)
	elif _outside_leash():
		point = director.player.global_position - director.player.global_basis.z * 500.0
		desired_speed = max_speed
	else:
		match state:
			State.REPOSITION:
				if role == "PLAYER_DUEL" and CombatDirector.alive(assignment_target):
					desired_speed = duel_speed
			State.SETUP_ATTACK, State.ATTACK:
				if not CombatDirector.alive(assignment_target):
					return
				var distance := global_position.distance_to(assignment_target.global_position)
				point = _lead_point(assignment_target)
				if state == State.SETUP_ATTACK:
					point = assignment_target.global_position + assignment_target.velocity() * minf(distance / maxf(speed, 1.0), 2.0)
				desired_speed = max_speed if distance > 1100.0 else cruise_speed
				if distance < 500.0:
					desired_speed = min_combat_speed
			State.EXTEND:
				point = global_position + _maneuver_direction * extend_distance
				desired_speed = cruise_speed if role == "PLAYER_DUEL" else max_speed
			State.DEFEND, State.EVADE_MISSILE:
				point = global_position + _maneuver_direction * 2000.0
				desired_speed = cruise_speed
			State.RECOVER:
				point = global_position + _maneuver_direction * 1500.0
	_steer_toward(point)
	if state == State.EVADE_MISSILE:
		pitch_input *= evade_quality
		yaw_input *= evade_quality
		roll_input *= evade_quality
	if state == State.RECOVER:
		pitch_input = clampf(pitch_input, -0.3, 0.3)
		yaw_input = clampf(yaw_input, -0.3, 0.3)
		roll_input = clampf(roll_input, -0.4, 0.4)
	throttle_input = clampf((desired_speed - speed) / 30.0, 0.0, 1.0)
	brake_input = clampf((speed - desired_speed) / 30.0, 0.0, 1.0)


func _tail_threat() -> Node3D:
	# ponytail: linear scan for a seven-aircraft prototype; spatial queries if crowds grow.
	for candidate in get_tree().get_nodes_in_group(_targeting.target_group):
		if not CombatDirector.alive(candidate):
			continue
		var offset: Vector3 = candidate.global_position - global_position
		var distance := offset.length()
		if distance < 1.0 or distance > threatened_distance:
			continue
		var direction := offset / distance
		if direction.dot(-global_basis.z) < -0.4 and (-candidate.global_basis.z).dot(-direction) > 0.8:
			return candidate
	return null


func _dangerous_missile() -> Node3D:
	var nearest: Node3D
	var nearest_distance := missile_threat_distance
	for missile in active_missiles():
		if missile.is_queued_for_deletion():
			continue
		var offset: Vector3 = global_position - missile.global_position
		var closing: Vector3 = missile.velocity - velocity()
		if offset.length() < nearest_distance and closing.dot(offset) > 0.0:
			nearest = missile
			nearest_distance = offset.length()
	return nearest


func _update_fire_solution(delta: float) -> void:
	if not CombatDirector.alive(assignment_target) or state != State.ATTACK or safety_active:
		_gun_stable_time = 0.0
		_missile_stable_time = 0.0
		return
	_gun_stable_time = _gun_stable_time + delta if _miss_distance(_lead_point(assignment_target)) <= gun_miss_tolerance else 0.0
	_missile_stable_time = _missile_stable_time + delta if _targeting._in_lock_zone(assignment_target) else 0.0


## Called again by WeaponController at the actual trigger boundary, so permissions and missile
## capacity cannot become stale between the decision and a launch.
func weapon_fire_block(kind: String) -> String:
	if not is_alive() or state == State.DESTROYED:
		return "DESTROYED"
	if not CombatDirector.alive(assignment_target):
		return "NO_TARGET"
	if state != State.ATTACK:
		return "DEFENSIVE_MANEUVER" if state in [State.DEFEND, State.EVADE_MISSILE, State.RECOVER] else "NOT_ATTACKING"
	if safety_active or _outside_leash():
		return "SAFETY_MANEUVER"
	var distance := global_position.distance_to(assignment_target.global_position)
	if distance < minimum_fire_range:
		return "TOO_CLOSE"
	if _state_time < reaction_delay:
		return "REACTION_DELAY"
	if is_instance_valid(director) and assignment_target == director.player and not director.has_permission(self):
		return "NO_ATTACK_PERMISSION"
	if kind == "gun":
		if _weapons.gun_ammo <= 0:
			return "NO_AMMO"
		if distance > gun_open_range:
			return "OUT_OF_RANGE"
		if _miss_distance(_lead_point(assignment_target)) > gun_miss_tolerance:
			return "OUT_OF_CONE"
		if _gun_stable_time < aim_stable_duration:
			return "AIM_UNSTABLE"
		if fmod(_burst_time, maxf(burst_interval, 0.01)) >= burst_duration:
			return "BURST_PAUSE"
		if _weapons._gun_cooldown > 0.0:
			return "WEAPON_COOLDOWN"
	else:
		var salvo := _weapons._missile_salvo_size(_weapons.get_equipped_def())
		if _weapons.missile_ammo >= 0 and _weapons.missile_ammo < salvo:
			return "NO_AMMO"
		if distance > missile_launch_range:
			return "OUT_OF_RANGE"
		if not _targeting._in_lock_zone(assignment_target):
			return "OUT_OF_CONE"
		if not _targeting.is_locked or _missile_stable_time < aim_stable_duration:
			return "LOCK_UNSTABLE"
		if _weapons._missile_cooldown > 0.0:
			return "WEAPON_COOLDOWN"
		if is_instance_valid(director) and assignment_target == director.player and not director.missile_slot_available(salvo):
			return "MISSILE_LIMIT"
	if not _clear_shot(kind):
		return "TRAJECTORY_BLOCKED"
	return "READY"


func _clear_shot(kind: String) -> bool:
	var offsets: Array = [_weapons.gun_muzzle] if kind == "gun" else _weapons.missile_pylons
	if offsets.is_empty():
		return false
	for offset in offsets:
		var start := _weapons._muzzle_transform(offset).origin
		var endpoint := start - global_basis.z * global_position.distance_to(assignment_target.global_position)
		var query := PhysicsRayQueryParameters3D.create(start, endpoint)
		query.exclude = [_hitbox.get_rid()]
		query.collide_with_areas = true
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty() and hit.collider != assignment_target.get_node_or_null("Hitbox"):
			return false
	return true


func _apply_safety() -> void:
	var ahead := global_position + velocity() * safety_lookahead
	var terrain_danger := false
	if _terrain_data != null:
		for sample in [global_position, ahead, global_position.lerp(ahead, 0.5)]:
			var ground: float = _terrain_data.get_height(sample)
			if not is_nan(ground) and sample.y - ground < terrain_clearance:
				terrain_danger = true
	var query := PhysicsRayQueryParameters3D.create(global_position, ahead)
	query.exclude = [_hitbox.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if terrain_danger or not hit.is_empty():
		safety_active = true
		var up_local := global_basis.inverse() * Vector3.UP
		roll_input = clampf(atan2(up_local.x, up_local.y) * turn_gain, -1.0, 1.0)
		pitch_input = -clampf(up_local.y, 0.0, 1.0)
		yaw_input = 0.0
		brake_input = 0.0
		throttle_input = 1.0
		return
	for aircraft in get_tree().get_nodes_in_group("combat_ai") + get_tree().get_nodes_in_group("player"):
		if aircraft == self or not CombatDirector.alive(aircraft):
			continue
		var offset: Vector3 = aircraft.global_position - global_position
		var relative: Vector3 = aircraft.velocity() - velocity()
		var time := clampf(-offset.dot(relative) / maxf(relative.length_squared(), 0.001), 0.0, safety_lookahead)
		if (offset + relative * time).length() < aircraft_separation:
			safety_active = true
			# Opposing headings yield opposing right vectors: both pilots break right.
			_steer_toward(global_position - global_basis.z * 400.0 + global_basis.x * 700.0 + Vector3.UP * 200.0)
			return


func debug_text() -> String:
	return "%s | ROLE: %s | TARGET: %s\nSTATE: %s | STATE_TIME: %.1f | LAST_TRANSITION: %s | FIRE_BLOCK: %s" % [
		name, role, assignment_target.name if CombatDirector.alive(assignment_target) else "NONE",
		State.keys()[state], _state_time, last_transition, fire_block]


func _steer_toward(point: Vector3) -> void:
	var local := global_basis.inverse() * (point - global_position)
	if local.length_squared() < 0.001:
		return
	var direction := local.normalized()
	var lateral := Vector2(direction.x, direction.y)
	var behind := direction.z > 0.0
	if not behind and lateral.length() <= fine_tracking_error:
		var up_local := global_basis.inverse() * Vector3.UP
		roll_input = clampf(atan2(up_local.x, up_local.y) * turn_gain, -1.0, 1.0)
		pitch_input = clampf(-direction.y * fine_tracking_gain, -1.0, 1.0)
		yaw_input = clampf(direction.x * fine_tracking_gain, -1.0, 1.0)
		return
	var bank_error := atan2(direction.x, direction.y)
	roll_input = clampf(bank_error * turn_gain, -1.0, 1.0)
	var pull := 1.0 if behind else lateral.length()
	pitch_input = -clampf(pull * turn_gain * maxf(cos(bank_error), 0.0), 0.0, 1.0)
	yaw_input = clampf(direction.x * 1.5, -1.0, 1.0)


## How far the nose ray passes from the aim point, which is the only number that decides whether
## bullets connect.
func _miss_distance(aim: Vector3) -> float:
	var offset := aim - global_position
	var forward := -global_basis.z
	var along := offset.dot(forward)
	if along <= 0.0:
		return INF
	return (offset - forward * along).length()


func _lead_point(target: Node3D) -> Vector3:
	var offset := target.global_position - global_position
	var closing := maxf(_weapons.gun_projectile_speed + speed, 1.0)
	var travel_time := offset.length() / closing
	return target.global_position + target.velocity() * travel_time * aim_accuracy


func _die() -> void:
	if state == State.DESTROYED:
		return
	_set_state(State.DESTROYED, "AIRCRAFT_DESTROYED")
	fire_block = "DESTROYED"
	gun_block = "DESTROYED"
	missile_block = "DESTROYED"
	super()
	visible = true
	_begin_wreck()


## The kill takes the airframe out of the fight — `is_alive()` is already false, so targeting,
## missiles have let go of it — and hands what is left to the fall.
func _begin_wreck() -> void:
	_wreck_velocity = -global_basis.z * speed
	_wreck_spin = Vector3(
		randf_range(-1.0, 1.0) * wreck_spin_degrees.x,
		randf_range(-1.0, 1.0) * wreck_spin_degrees.y,
		(1.0 if randf() < 0.5 else -1.0) * wreck_spin_degrees.z,
	)
	_wreck_time = 0.0
	_wreck_next_explosion = wreck_explosion_interval
	gun_trigger = false
	missile_trigger = false
	if _targeting != null:
		_targeting.set_physics_process(false)
	# Dead engines. The plume material is one shared resource, so writing a throttle here would
	# dim every other aircraft's nozzles as well; hiding this instance's own node does not.
	var burners := get_node_or_null("Afterburners")
	if burners != null:
		burners.hide()


## Ballistic, tumbling, and still trailing the damage smoke it caught before dying. The
## `DamageFire` emitters read the health ratio, which is zero, so they need nothing here.
func _fall(delta: float) -> void:
	_wreck_time += delta
	_wreck_velocity.y -= wreck_gravity * delta
	_wreck_velocity *= maxf(1.0 - wreck_drag * delta, 0.0)
	global_position += _wreck_velocity * delta
	rotate_object_local(Vector3.RIGHT, deg_to_rad(_wreck_spin.x) * delta)
	rotate_object_local(Vector3.UP, deg_to_rad(_wreck_spin.y) * delta)
	rotate_object_local(Vector3.BACK, deg_to_rad(_wreck_spin.z) * delta)
	basis = basis.orthonormalized()
	# Whatever still reads the aircraft gets the truth about how fast it is going down.
	speed = _wreck_velocity.length()

	if _wreck_time >= _wreck_next_explosion:
		_wreck_next_explosion += wreck_explosion_interval
		wreck_cook_offs += 1
		Explosion.spawn(get_parent(), global_position, wreck_explosion_scale)

	if _reached_ground():
		Explosion.spawn_aircraft(get_parent(), global_position, 3.0)
		queue_free()
	elif _wreck_time >= wreck_max_fall_time:
		# No terrain under it, so nobody is watching it land either.
		queue_free()


func _reached_ground() -> bool:
	if _terrain_data == null:
		return false
	var ground: float = _terrain_data.get_height(global_position)
	if is_nan(ground):
		return false
	return global_position.y - ground <= wreck_impact_clearance


func _find_terrain_data():
	var scene := get_tree().current_scene
	if scene == null:
		scene = get_parent()
	if scene == null:
		return null
	for node in scene.find_children("*", "Terrain3D", true, false):
		return node.get("data")
	return null


func velocity() -> Vector3:
	return _wreck_velocity if state == State.DESTROYED else super()
