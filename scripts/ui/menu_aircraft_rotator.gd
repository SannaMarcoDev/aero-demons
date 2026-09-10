extends Node3D

@export var bank_range_deg := 9.0
@export var pitch_range_deg := 3.5
@export var yaw_range_deg := 5.0
@export var cycle_speed := 0.35

var _base_transform: Transform3D
var _time := 0.0

@onready var afterburners: Afterburner = $Afterburners


func _ready() -> void:
	_base_transform = transform
	if afterburners != null:
		afterburners.set_throttle(0.85)


func _process(delta: float) -> void:
	_time += delta * cycle_speed

	# Smooth aerodynamic cruise oscillation
	var roll := sin(_time * 1.0) * deg_to_rad(bank_range_deg)
	var pitch := cos(_time * 0.7 + 0.5) * deg_to_rad(pitch_range_deg)
	var yaw := sin(_time * 0.5 + 1.2) * deg_to_rad(yaw_range_deg)

	# Subtle high-altitude float
	var heave_y := sin(_time * 1.3) * 0.08
	var drift_x := sin(_time * 0.6) * 0.12

	var rot := Basis.from_euler(Vector3(pitch, yaw, roll))
	transform.basis = _base_transform.basis * rot
	transform.origin = _base_transform.origin + Vector3(drift_x, heave_y, 0.0)
