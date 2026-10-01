extends Node
## Bends the map with the Earth around the active camera: the terrain and these materials include
## res://resources/shaders/earth_curvature.gdshaderinc. ~8 m at 10 km, ~785 m at 100 km.
@export var earth_radius := 6371000.0
@export var terrain: Terrain3D
@export var materials: Array[ShaderMaterial] = []

func _ready() -> void:
	process_priority = 1000 # After the camera has moved this frame.
	_apply("earth_radius", earth_radius)

func _process(_delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera != null:
		_apply("curvature_origin", camera.global_position)

func _apply(parameter: StringName, value: Variant) -> void:
	if terrain != null:
		terrain.material.set_shader_param(parameter, value)
	for material in materials:
		material.set_shader_parameter(parameter, value)
