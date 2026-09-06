extends Node3D
class_name Afterburner

## Adapts flight throttle and spin-dash boost to the blue thrusters.
@export var plume_length := 3.2
@export var boost_plume_length := 7.5
@export var light_intensity := 0.05
@export var boost_light_multiplier := 2.2

var _throttle := 0.35
var _boost := 0.0


func _ready() -> void:
	_apply_output()


func set_throttle(throttle: float) -> void:
	_throttle = clampf(throttle, 0.0, 0.5)
	_apply_output()


func set_boost(boost: float) -> void:
	_boost = clampf(boost, 0.0, 1.0)
	_apply_output()


func _apply_output() -> void:
	for thruster in get_children():
		thruster.light_intensity = light_intensity * lerpf(1.0, boost_light_multiplier, _boost)
		thruster.exhaust_length = lerpf(plume_length, boost_plume_length, _boost)
		thruster.throttle = lerpf(_throttle, 1.0, _boost)
