extends Node
## F toggles Sky3D screen-space fog at runtime.

@export var sky_path: NodePath = "../Sky3D"

func _input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode != KEY_F:
		return
	var sky := get_node(sky_path)
	sky.fog_enabled = not sky.fog_enabled
	print("Fog: ", "ON" if sky.fog_enabled else "OFF")
