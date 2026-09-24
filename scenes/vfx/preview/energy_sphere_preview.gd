extends "res://scripts/camera/free_fly_camera.gd"
## Isolated look-dev; never loaded by a mission. --verify runs the bounded smoke check.

const SPHERE = preload("res://scenes/vfx/energy_sphere.tscn")
const PLAYER = preload("res://scenes/player/player.tscn")
var orbit := false
var aircraft: Node3D
@onready var sphere: StaticBody3D = $"../EnergySphere"
@onready var preview_environment: Environment = $"../WorldEnvironment".environment


func _ready() -> void:
	super._ready()
	set_view(0)
	if "--verify" in OS.get_cmdline_user_args():
		_verify.call_deferred()


func set_view(index: int) -> void:
	orbit = false
	if is_instance_valid(aircraft):
		aircraft.queue_free()
		aircraft = null
	make_current()
	var offsets := [Vector3(0, 40, 850), Vector3(0, 400, 3500), Vector3(0, 0, 310), Vector3(-800, 270, -720)]
	global_position = sphere.global_position + offsets[index]
	look_at(sphere.global_position)


func _process(delta: float) -> void:
	if is_instance_valid(aircraft):
		return
	if orbit:
		var offset := global_position - sphere.global_position
		global_position = sphere.global_position + offset.rotated(Vector3.UP, delta * 0.10)
		look_at(sphere.global_position)
	else:
		super._process(delta)
		# Review camera stays outside the solid surface, even with mouse navigation.
		var offset := global_position - sphere.global_position
		if offset.length() < sphere.diameter_m * 0.5 + 3.0:
			global_position = sphere.global_position + offset.normalized() * (sphere.diameter_m * 0.5 + 3.0)
	$"../HUD/Status".text = "Surface distance: %.0f m  |  %.0f FPS  |  Glow: %s" % [global_position.distance_to(sphere.global_position) - sphere.diameter_m * 0.5, Engine.get_frames_per_second(), preview_environment.glow_enabled]


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode >= KEY_1 and event.keycode <= KEY_4:
			set_view(event.keycode - KEY_1)
		elif event.keycode == KEY_O:
			orbit = not orbit
		elif event.keycode == KEY_G:
			preview_environment.glow_enabled = not preview_environment.glow_enabled
		elif event.keycode == KEY_B:
			preview_environment.background_mode = Environment.BG_COLOR if preview_environment.background_mode == Environment.BG_SKY else Environment.BG_SKY
			preview_environment.background_color = Color(0.002, 0.002, 0.005)
		elif event.keycode == KEY_M:
			mouse_look_enabled = not mouse_look_enabled
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if mouse_look_enabled else Input.MOUSE_MODE_VISIBLE
		elif event.keycode == KEY_H:
			$"../HUD".visible = not $"../HUD".visible
		elif event.keycode == KEY_C:
			_launch_aircraft()
		else:
			super._unhandled_input(event)
	else:
		super._unhandled_input(event)


func _launch_aircraft() -> void:
	set_view(0)
	aircraft = PLAYER.instantiate()
	aircraft.position = sphere.position + Vector3(0, 0, 700)
	get_parent().add_child(aircraft)
	aircraft.get_node("FlightCamera").make_current()
	aircraft.destroyed.connect(func(_plane: Node3D):
		make_current()
		$"../HUD/Status".text = "IMPACT / solid sphere — aircraft destroyed. 1–4 return to review; C retry.")


func _verify() -> void:
	await get_tree().physics_frame
	assert(is_equal_approx(sphere.get_node("CollisionShape3D").shape.radius, 250.0))
	# Resize a second instance: materials and collision must not mutate the first.
	var other := SPHERE.instantiate()
	other.diameter_m = 100.0
	other.position = Vector3(5000, 500, 0)
	get_parent().add_child(other)
	assert(is_equal_approx(other.get_node("CollisionShape3D").shape.radius, 50.0))
	assert(is_equal_approx(sphere.get_node("CollisionShape3D").shape.radius, 250.0))
	assert(other.get_node("Surface").material_override != sphere.get_node("Surface").material_override)
	other.queue_free()
	for direction in [Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN, Vector3.BACK, Vector3.FORWARD]:
		var query := PhysicsRayQueryParameters3D.create(sphere.global_position + direction * 600.0, sphere.global_position, 1)
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		assert(hit.get("collider") == sphere)
		assert(absf(hit.position.distance_to(sphere.global_position) - 250.0) < 0.1)
	var body := CharacterBody3D.new()
	body.collision_mask = 1
	var shape := CollisionShape3D.new()
	shape.shape = SphereShape3D.new()
	shape.shape.radius = 1.0
	body.add_child(shape)
	get_parent().add_child(body)
	body.global_position = sphere.global_position + Vector3(0, 0, 600)
	await get_tree().physics_frame
	var contact := body.move_and_collide(Vector3(0, 0, -1200))
	assert(contact != null and contact.get_collider() == sphere)
	assert(body.global_position.z >= sphere.global_position.z + 250.0)
	body.queue_free()
	_launch_aircraft()
	aircraft.controls_enabled = false
	for frame in 300:
		await get_tree().physics_frame
		if not aircraft.is_alive():
			break
	assert(not aircraft.is_alive(), "Player must hit the solid sphere, not pass through")
	# Stop preview-owned sound before freeing the aircraft; allow mixer cleanup in real time.
	for audio in get_tree().root.find_children("*", "AudioStreamPlayer3D", true, false) + get_tree().root.find_children("*", "AudioStreamPlayer", true, false):
		audio.stop()
		audio.stream = null
	set_view(0)
	var deadline := Time.get_ticks_msec() + 600
	while Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		OS.delay_msec(10) # --fixed-fps otherwise floods Jolt jobs during this wall-clock wait.
	print("PASS: energy sphere size, instance isolation, six-axis rays, swept body and actual player impact")
	get_tree().quit()
