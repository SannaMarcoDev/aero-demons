extends Node3D
## Isolated asset review; does not edit or populate the airport map.
var _open := false

func _ready() -> void:
	# Local review only: resolve subpixel metal seams without changing project settings.
	get_viewport().msaa_3d = Viewport.MSAA_4X

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_O:
			_open = not _open
			$Hangar.set_open(_open)
		elif event.keycode in [KEY_1, KEY_2, KEY_3]:
			var views := {
				KEY_1: [Vector3(26, 15, 35), Vector3(0, 3, 1)],
				KEY_2: [Vector3(1, 2.3, 10), Vector3(0, 3.6, -8)],
				KEY_3: [Vector3(66, 59, 92), Vector3(0, 3, 0)],
			}
			$Camera3D.position = views[event.keycode][0]
			$Camera3D.look_at(views[event.keycode][1])
