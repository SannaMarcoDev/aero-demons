extends Camera3D

@export var target_position := Vector3(0.0, 0.2, 0.0)

func _ready() -> void:
	look_at(target_position, Vector3.UP)
