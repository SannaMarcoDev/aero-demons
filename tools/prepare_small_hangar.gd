extends SceneTree
## Builds only the reusable hangar and its isolated review scene.
const ASSET := "res://assets/environment/small_hangar/"
var hangar := Node3D.new()

func _initialize() -> void:
	_build.call_deferred()

func _own(node: Node, parent: Node, label: String, scene_root: Node) -> void:
	node.name = label
	parent.add_child(node)
	node.owner = scene_root

func _xyz(values: Array) -> Vector3:
	return Vector3(values[0], values[2], -values[1])

func _save(node: Node, path: String) -> void:
	var packed := PackedScene.new()
	assert(packed.pack(node) == OK)
	assert(ResourceSaver.save(packed, path) == OK)

func _build() -> void:
	for audio in root.get_node("AudioManager").get_children():
		if audio is AudioStreamPlayer:
			audio.stop()
			audio.stream = null
	hangar.name = "SmallHangar"
	hangar.set_script(load("res://scripts/maps/small_hangar.gd"))
	var model: Node3D = load(ASSET + "small_hangar.glb").instantiate()
	_own(model, hangar, "Model", hangar)
	assert(model.has_node("AnimationPlayer"))
	assert(model.get_node("AnimationPlayer").has_animation("SmallHangar"))
	var shell := StaticBody3D.new()
	_own(shell, hangar, "ShellCollision", hangar)
	var collision: Array = JSON.parse_string(FileAccess.get_file_as_string(ASSET + "source/collision.json"))
	for item: Dictionary in collision:
		var collider := CollisionShape3D.new()
		if item.type == "convex":
			var shape := ConvexPolygonShape3D.new()
			var points := PackedVector3Array()
			for point: Array in item.points:
				points.append(_xyz(point))
			shape.points = points
			collider.shape = shape
		else:
			var shape := BoxShape3D.new()
			shape.size = _xyz(item.size).abs()
			collider.shape = shape
			collider.position = _xyz(item.center)
			if item.type == "roof":
				collider.rotation.z = -float(item.angle_y)
		_own(collider, shell, "Shape%d" % shell.get_child_count(), hangar)
	for label in ["DoorUpper", "DoorLower"]:
		var leaf: MeshInstance3D = model.find_child(label, true, false)
		assert(leaf != null)
		var body := AnimatableBody3D.new()
		# The parent mesh is sampled on physics ticks; no second deferred transform.
		body.sync_to_physics = false
		_own(body, hangar, label + "Collision", hangar)
		body.transform = leaf.transform
		var ancestor := leaf.get_parent() as Node3D
		while ancestor != hangar:
			body.transform = ancestor.transform * body.transform
			ancestor = ancestor.get_parent() as Node3D
		var shape := BoxShape3D.new()
		shape.size = Vector3(11.6, 2.55, 0.28)
		var collider := CollisionShape3D.new()
		collider.shape = shape
		collider.position = Vector3(0, -1.275, 0.15)
		_own(collider, body, "Shape", hangar)
	_save(hangar, "res://scenes/maps/small_hangar.tscn")
	hangar.free()
	var preview := Node3D.new()
	preview.name = "SmallHangarPreview"
	preview.set_script(load("res://scripts/maps/small_hangar_preview.gd"))
	_own(load("res://scenes/maps/small_hangar.tscn").instantiate(), preview, "Hangar", preview)
	var world := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("6d757c")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("acbfd0")
	env.ambient_light_energy = 0.3
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.ssao_enabled = true
	env.ssao_radius = 0.35
	env.ssao_intensity = 0.7
	world.environment = env
	_own(world, preview, "WorldEnvironment", preview)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -30, 0)
	sun.light_energy = 1.4
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 180.0
	_own(sun, preview, "Sun", preview)
	# Review-only lamps: repeated airport modules do not force dynamic lights.
	for z in [7.0, -1.0, -9.0]:
		var light := OmniLight3D.new()
		light.position = Vector3(0, 5.25, z)
		light.light_color = Color("e7ebda")
		light.light_energy = 2.5
		light.omni_range = 12.0
		_own(light, preview, "ReviewLamp%d" % preview.get_child_count(), preview)
	var camera := Camera3D.new()
	camera.position = Vector3(26, 15, 35)
	camera.rotation = Basis.looking_at(Vector3(0, 3, 1) - camera.position).get_euler()
	camera.fov = 42
	camera.current = true
	camera.far = 350
	camera.set_script(load("res://scripts/camera/free_fly_camera.gd"))
	camera.set("move_speed", 8.0)
	_own(camera, preview, "Camera3D", preview)
	var ui := CanvasLayer.new()
	_own(ui, preview, "UI", preview)
	var label := Label.new()
	label.text = "H-01  /  SMALL MILITARY HANGAR\nO  open / close    1 exterior   2 interior   3 distance\nWASD + mouse   Q/E height   Shift fast   Esc release mouse / exit"
	label.position = Vector2(24, 20)
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_shadow_color", Color.BLACK)
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	_own(label, ui, "Controls", preview)
	_save(preview, "res://scenes/preview/small_hangar_preview.tscn")
	preview.free()
	# Let the project's audio mixer release its stopped autoplay stream.
	await create_timer(0.25).timeout
	print("PASS: SMALL_HANGAR_PREPARE imported animation, 9 shell shapes, 2 moving leaf shapes, isolated preview")
	quit()
