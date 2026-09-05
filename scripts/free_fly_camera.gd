extends Camera3D
## Free-fly camera with WASD navigation, mouse look, and Shift boost.

@export var move_speed: float = 80.0
@export var boost_factor: float = 4.0
@export var mouse_sensitivity: float = 0.002
@export var mouse_look_enabled: bool = true

func _ready() -> void:
	if mouse_look_enabled:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _unhandled_input(event: InputEvent) -> void:
	if mouse_look_enabled and event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		rotation = Vector3(
			clampf(rotation.x - event.relative.y * mouse_sensitivity, -deg_to_rad(89.0), deg_to_rad(89.0)),
			rotation.y - event.relative.x * mouse_sensitivity, 0.0)
	elif event is InputEventKey and event.is_pressed() and not event.is_echo():
		if event.keycode == KEY_ESCAPE:
			if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
				Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
			else:
				get_tree().quit()
	elif event is InputEventMouseButton and event.is_pressed():
		if mouse_look_enabled and event.button_index == MOUSE_BUTTON_LEFT and Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _process(delta: float) -> void:
	var move_dir := Vector3.ZERO
	if Input.is_key_pressed(KEY_W):
		move_dir -= transform.basis.z
	if Input.is_key_pressed(KEY_S):
		move_dir += transform.basis.z
	if Input.is_key_pressed(KEY_A):
		move_dir -= transform.basis.x
	if Input.is_key_pressed(KEY_D):
		move_dir += transform.basis.x
	if Input.is_key_pressed(KEY_E) or Input.is_key_pressed(KEY_SPACE):
		move_dir += Vector3.UP
	if Input.is_key_pressed(KEY_Q) or Input.is_key_pressed(KEY_CTRL):
		move_dir -= Vector3.UP

	if move_dir != Vector3.ZERO:
		var speed := move_speed
		if Input.is_key_pressed(KEY_SHIFT):
			speed *= boost_factor
		global_position += move_dir.normalized() * (speed * delta)
