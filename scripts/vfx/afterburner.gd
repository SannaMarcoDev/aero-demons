extends Node3D
class_name Afterburner

## Adapts flight throttle and spin-dash boost to jet_exhaust instances.
## Dry throttle (0-0.5) maps below afterburner onset; boost pushes into it.

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
	# 0.5 dry maps to 0.85, just under the exhaust's afterburner onset.
	var dry := _throttle * 1.7
	for exhaust in get_children():
		exhaust.throttle = lerpf(dry, 1.0, _boost)
