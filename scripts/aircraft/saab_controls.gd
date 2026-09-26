extends Node3D
class_name SaabControls
## Visual-only control surfaces. Imported meshes have their vertices in model space,
## so the scene pivots supply the hinge positions without modifying the GLB.

@export_range(0.0, 30.0, 1.0) var pitch_angle := 14.0
@export_range(0.0, 30.0, 1.0) var roll_angle := 18.0
@export_range(0.0, 30.0, 1.0) var yaw_angle := 20.0
@export_range(0.0, 45.0, 1.0) var elevon_limit := 25.0
@export_range(0.1, 30.0, 0.1) var response_speed := 9.0

@onready var _ailerons := [$AileronLPivot, $AileronRPivot]
@onready var _elevators := [$ElevatorLPivot, $ElevatorRPivot]
@onready var _flaps := [$FlapLPivot, $FlapRPivot]
@onready var _rudder: Node3D = $RudderPivot

var _pitch := 0.0
var _roll := 0.0
var _yaw := 0.0


func _ready() -> void:
	var surfaces := ["Aileron_L_001", "Aileron_R_001", "Elevator_L_001", "Elevator_R_001", "Flap_L_001", "Flap_R_001", "Rudder_001"]
	var pivots := _ailerons + _elevators + _flaps + [_rudder]
	for i in surfaces.size():
		var mesh := $Model.get_node_or_null(surfaces[i]) as MeshInstance3D
		if mesh == null:
			push_error("Missing Saab control surface: %s" % surfaces[i])
			continue
		mesh.reparent(pivots[i], true)


func set_controls(pitch: float, roll: float, yaw: float, delta: float) -> void:
	var blend := 1.0 - exp(-response_speed * maxf(delta, 0.0))
	_pitch = lerpf(_pitch, clampf(pitch, -1.0, 1.0), blend)
	_roll = lerpf(_roll, clampf(roll, -1.0, 1.0), blend)
	_yaw = lerpf(_yaw, clampf(yaw, -1.0, 1.0), blend)
	_apply_pose()


func reset_controls() -> void:
	_pitch = 0.0
	_roll = 0.0
	_yaw = 0.0
	_apply_pose()


func _apply_pose() -> void:
	var pitch_deflection := _pitch * pitch_angle
	for pivot in _flaps:
		pivot.rotation_degrees.x = pitch_deflection
	for i in 2:
		var deflection := clampf(pitch_deflection + (1.0 if i == 0 else -1.0) * _roll * roll_angle, -elevon_limit, elevon_limit)
		_elevators[i].rotation_degrees.x = deflection
		_ailerons[i].rotation_degrees.x = deflection
	_rudder.rotation_degrees.y = -_yaw * yaw_angle
