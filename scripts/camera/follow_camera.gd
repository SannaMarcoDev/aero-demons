extends Camera3D

const LOOK_ORBIT_LIMIT_DEG := 180.0
const LOOK_REAR_CURVE := 8.0
const TRACK_PITCH_LIMIT_DEG := 80.0
@export_category("Camera tuning")
## Higher values follow aircraft rotation faster.
@export_range(0.1, 30.0, 0.1) var follow_response := 8.0
## Higher values respond to the look stick faster.
@export_range(0.1, 30.0, 0.1) var look_response := 8.0
const ORBIT_PIVOT_HEIGHT := 1.0
const TRACK_RESPONSE := 6.0
@export_range(0.0, 30.0, 0.5) var maneuver_yaw_deg := 12.0
const RUDDER_FRAMING_FACTOR := 0.5
const MANEUVER_RESPONSE := 8.0
const MANEUVER_RETURN_RESPONSE := 4.0
const SPEED_FOV_RESPONSE := 3.0
@export_range(0.0, 20.0, 0.5) var max_speed_fov := 4.0
@export_range(-20.0, 0.0, 0.5) var min_speed_fov := -2.0

var _follow_transform := Transform3D.IDENTITY
var _last_target_position := Vector3.ZERO
var _look_input := Vector2.ZERO
var _track_weight := 0.0
var _cycle_hold_time := 0.0
var _maneuver_offset := 0.0
var _maneuver_velocity := 0.0
var _speed_fov_offset := 0.0

@onready var target: PlayerFlight = get_parent() as PlayerFlight
@onready var _targeting: TargetLock = target.get_node_or_null("TargetLock") if target != null else null


func _ready() -> void:
	snap_to_target()


func _physics_process(delta: float) -> void:
	_update_dynamic_camera(delta)
	fov = target.camera_fov + target.spin_dash_camera_fov_offset() + _speed_fov_offset
	var target_position := target.camera_position()
	_follow_transform.origin += target_position - _last_target_position
	_last_target_position = target_position
	var follow_weight := 1.0 - exp(-follow_response * delta)
	_follow_transform = _follow_transform.interpolate_with(_chase_transform(), follow_weight)
	var look_input := Input.get_vector("look_left", "look_right", "look_up", "look_down") * SettingsManager.controls_sensitivity
	if SettingsManager.controls_invert_y:
		look_input.y = -look_input.y
	look_input = look_input.limit_length(1.0)
	_look_input = _look_input.lerp(look_input, 1.0 - exp(-look_response * delta))
	if look_input.is_zero_approx() and _look_input.length_squared() < 0.000001:
		_look_input = Vector2.ZERO

	var normal_transform := _dynamic_transform(_orbit_transform(_follow_transform, _look_input))

	# Hold cycle_target (>0.25s) to center current target — only camera moves, no aircraft input.
	if _targeting == null and target != null:
		_targeting = target.get_node_or_null("TargetLock") as TargetLock
	if Input.is_action_pressed("cycle_target"):
		_cycle_hold_time += delta
	else:
		_cycle_hold_time = 0.0
	var tracking_active := _cycle_hold_time > 0.30 and _has_tracking_target()
	var target_weight := 1.0 if tracking_active else 0.0
	_track_weight = lerp(_track_weight, target_weight, 1.0 - exp(-TRACK_RESPONSE * delta))
	if _track_weight < 0.001:
		_track_weight = 0.0
		global_transform = normal_transform
	elif _track_weight > 0.999:
		_track_weight = 1.0
		global_transform = _tracking_transform(_follow_transform)
	else:
		var tracking_transform := _tracking_transform(_follow_transform)
		global_transform = normal_transform.interpolate_with(tracking_transform, _track_weight)


func snap_to_target() -> void:
	fov = target.camera_fov
	_look_input = Vector2.ZERO
	_track_weight = 0.0
	_cycle_hold_time = 0.0
	_maneuver_offset = 0.0
	_maneuver_velocity = 0.0
	_speed_fov_offset = 0.0
	_last_target_position = target.camera_position()
	_follow_transform = _chase_transform()
	global_transform = _follow_transform
	reset_physics_interpolation()


## Hung from the aircraft's camera basis rather than its transform: during a spin dash that basis
## stays on the entry heading, so the airframe rolls inside the frame.
func _chase_transform() -> Transform3D:
	var speed_range := maxf(target.max_speed - target.cruise_speed, 0.001)
	var speed_ratio := clampf((target.speed - target.cruise_speed) / speed_range, 0.0, 1.0)
	var acceleration_input := Input.get_action_strength("accelerate")
	var acceleration_shift := target.camera_acceleration_shift * maxf(speed_ratio, acceleration_input)
	var camera_offset := Vector3(
		0.0,
		target.camera_height,
		target.camera_depth + acceleration_shift + target.spin_dash_camera_depth_offset(),
	)
	return _target_anchor() * Transform3D(
		Basis.from_euler(Vector3(deg_to_rad(target.camera_pitch), 0.0, 0.0)),
		camera_offset,
	)


func _target_anchor() -> Transform3D:
	return Transform3D(target.camera_basis(), target.camera_position())


func _update_dynamic_camera(delta: float) -> void:
	var desired := clampf(
		target.roll_input + target.yaw_input * RUDDER_FRAMING_FACTOR, -1.0, 1.0,
	)
	if target.spin_dash_active:
		desired = 0.0
	var response := MANEUVER_RETURN_RESPONSE if is_zero_approx(desired) else MANEUVER_RESPONSE
	# Exact critically damped spring: quick into a manoeuvre, gentler back to neutral.
	var difference := _maneuver_offset - desired
	var decay := exp(-response * delta)
	var change := (_maneuver_velocity + response * difference) * delta
	_maneuver_offset = desired + (difference + change) * decay
	_maneuver_velocity = (_maneuver_velocity - response * change) * decay

	var desired_fov := 0.0
	if target.spin_dash_camera_recovery_weight() <= 0.0:
		if target.speed >= target.cruise_speed:
			desired_fov = max_speed_fov * clampf(
				inverse_lerp(target.cruise_speed, target.max_speed, target.speed), 0.0, 1.0,
			)
		else:
			desired_fov = min_speed_fov * clampf(
				inverse_lerp(target.cruise_speed, target.min_speed, target.speed), 0.0, 1.0,
			)
	_speed_fov_offset = lerpf(
		_speed_fov_offset, desired_fov, 1.0 - exp(-SPEED_FOV_RESPONSE * delta),
	)


func _dynamic_transform(camera_transform: Transform3D) -> Transform3D:
	var weight := (1.0 - clampf(_look_input.length(), 0.0, 1.0)) * (1.0 - _track_weight)
	var dynamic_rotation := Basis.from_euler(Vector3(
		0.0,
		deg_to_rad(-_maneuver_offset * maneuver_yaw_deg * weight),
		0.0,
	))
	camera_transform.basis = (camera_transform.basis * dynamic_rotation).orthonormalized()
	return camera_transform


func _orbit_transform(camera_transform: Transform3D, look_input: Vector2) -> Transform3D:
	if look_input.is_zero_approx():
		return camera_transform
	var local_camera := _target_anchor().affine_inverse() * camera_transform
	var strength := clampf(look_input.length(), 0.0, 1.0)
	var direction := look_input.normalized()
	var orbit_axis := Vector3(direction.y, direction.x, 0.0)
	# Keep the old 90-degree range through most of the stick, then open to a rear view at the rim.
	var orbit_angle := deg_to_rad(
		LOOK_ORBIT_LIMIT_DEG * 0.5 * (strength + pow(strength, LOOK_REAR_CURVE))
	)
	var orbit_rotation := Basis(orbit_axis, orbit_angle)
	var pivot := Vector3(0.0, ORBIT_PIVOT_HEIGHT, 0.0)
	var orbit_transform := Transform3D(orbit_rotation, pivot - orbit_rotation * pivot)
	return _target_anchor() * orbit_transform * local_camera


func _has_tracking_target() -> bool:
	if _targeting == null:
		return false
	var t = _targeting.target
	return t != null and is_instance_valid(t) and t is Node3D and (t as Node3D).is_inside_tree() and t.has_method("is_alive") and bool(t.call("is_alive"))


func _tracking_transform(base: Transform3D) -> Transform3D:
	var t = _targeting.target as Node3D if _targeting != null else null
	if t == null or not is_instance_valid(t):
		return base
	var anchor := _target_anchor()
	# Direction from camera to target, expressed in anchor local space — same manner as the right stick orbit.
	var cam_pos: Vector3 = base.origin
	var target_pos: Vector3 = t.global_position
	var dir_world := target_pos - cam_pos
	if dir_world.length_squared() < 0.001:
		return base
	var dir_local: Vector3 = anchor.basis.inverse() * dir_world
	var yaw := -atan2(dir_local.x, -dir_local.z)
	var horiz := Vector2(dir_local.x, dir_local.z).length()
	var pitch := atan2(dir_local.y, horiz)
	# Tracking keeps the old vertical cap; manual orbit alone is allowed to pass over the poles.
	pitch = clamp(
		pitch, deg_to_rad(-TRACK_PITCH_LIMIT_DEG), deg_to_rad(TRACK_PITCH_LIMIT_DEG)
	)
	var orbit_rotation := Basis.from_euler(Vector3(pitch, yaw, 0.0))
	var local_camera: Transform3D = anchor.affine_inverse() * base
	var pivot := Vector3(0.0, ORBIT_PIVOT_HEIGHT, 0.0)
	var orbit_transform := Transform3D(orbit_rotation, pivot - orbit_rotation * pivot)
	return anchor * orbit_transform * local_camera
