@tool
extends Node3D

const GEAR_ANIMATION: StringName = &"Scene"
const GEAR_TRAVEL_SECONDS := 0.8

@onready var _gear_animation: AnimationPlayer = $Model/AnimationPlayer


func _ready() -> void:
	set_gear(1.0)


func set_gear(extension: float) -> void:
	if _gear_animation.current_animation != GEAR_ANIMATION:
		_gear_animation.play(GEAR_ANIMATION)
	_gear_animation.seek(GEAR_TRAVEL_SECONDS * (1.0 - clampf(extension, 0.0, 1.0)), true)
	_gear_animation.pause()
	$Model/Hull/Canopy.rotation = Vector3.ZERO
	$Model/Hull/Airbrake_1.rotation = Vector3.ZERO
	$Model/Hull/Airbrake_2.rotation = Vector3.ZERO
