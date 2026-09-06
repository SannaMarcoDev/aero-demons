extends Node3D
class_name Afterburner

## Drives the exhaust plumes from engine throttle. The plume material is shared between
## nozzles, so one uniform write covers both.

@export var plume_material: ShaderMaterial
@export var light_energy := 5.0
@export var light_range := 9.0
@export var boost_plume_length := 7.5
@export var boost_light_multiplier := 2.2

var _lights: Array[OmniLight3D] = []
var _normal_plume_length := 3.2
var _throttle := 0.0
var _boost := 0.0


func _ready() -> void:
	for node in find_children("*", "OmniLight3D", true):
		_lights.append(node)
	_normal_plume_length = float(plume_material.get_shader_parameter("plume_length"))
	_apply_output()


func set_throttle(throttle: float) -> void:
	_throttle = clampf(throttle, 0.0, 1.0)
	_apply_output()


func set_boost(boost: float) -> void:
	_boost = clampf(boost, 0.0, 1.0)
	_apply_output()


func _apply_output() -> void:
	plume_material.set_shader_parameter("throttle", _throttle)
	plume_material.set_shader_parameter("plume_length", lerpf(_normal_plume_length, boost_plume_length, _boost))
	var lit := pow(_throttle, 1.6)
	var boost_light := lerpf(1.0, boost_light_multiplier, _boost)
	for light in _lights:
		light.light_energy = light_energy * (0.08 + 0.92 * lit) * boost_light
		light.omni_range = light_range * (0.45 + 0.55 * lit) * lerpf(1.0, 1.5, _boost)
