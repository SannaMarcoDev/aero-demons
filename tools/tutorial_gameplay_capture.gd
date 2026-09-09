extends "res://tools/tutorial_orbit_capture.gd"
## Real follow-camera comparison. Shares production/legacy state and --check validation.

func _initialize() -> void:
	super._initialize()
	orbit_mode = false
