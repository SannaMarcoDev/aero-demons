extends SceneTree
## godot --headless --path . --script res://scenes/vfx/preview/check_jet_exhaust.gd
## Add -- --visual (without --headless) to capture all views + a heat-haze A/B check.
const EXHAUST = preload("res://scenes/vfx/jet_exhaust.tscn")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var host := Node3D.new()
	root.add_child(host)
	var a = EXHAUST.instantiate()
	var b = EXHAUST.instantiate()
	host.add_child(a)
	host.add_child(b)
	a.set_process(false)
	b.set_process(false)
	assert(a._material != b._material, "Twin engines must not share throttle state")
	assert(a._material.get_shader_parameter("flow_noise") == b._material.get_shader_parameter("flow_noise"), "Noise should be shared")
	assert(not a.get_node("Volume").visible, "Zero throttle should skip drawing")
	a.throttle = -1.0
	assert(a.throttle == 0.0)
	a.throttle = NAN
	assert(a.throttle == 0.0)
	a.throttle = 2.0
	assert(a.throttle == 1.0)
	b.throttle = 1.0
	for i in 30:
		a._process(1.0 / 30.0)
	for i in 120:
		b._process(1.0 / 120.0)
	assert(absf(a._power - b._power) < 0.00001, "Spool smoothing must be frame-rate independent")
	assert(a._power > 0.99 and a._power < 1.0)
	assert(a._material.get_shader_parameter("burn") > 0.99)
	b.throttle = 0.2
	b._process(3.0)
	assert(b._material.get_shader_parameter("burn") == 0.0)
	assert(a._material.get_shader_parameter("burn") > 0.99, "Changing B must not affect A")
	b.throttle = 0.85
	b._process(5.0)
	assert(b._material.get_shader_parameter("burn") < 0.00001, "No flame step at afterburner threshold")
	b.throttle = 0.86
	b._process(5.0)
	assert(b._material.get_shader_parameter("burn") > 0.0 and b._material.get_shader_parameter("burn") < 0.02)
	a.afterburner_enabled = false
	a._process(0.1)
	assert(a._material.get_shader_parameter("burn") == 0.0)
	a.nozzle_radius = 0.7
	a.plume_length = 9.0
	a.heat_haze_length = 4.0
	a.rotation_degrees = Vector3(22, 71, -13)
	a.position = Vector3(3, 2, 9)
	a._process(0.0)
	var volume: MeshInstance3D = a.get_node("Volume")
	assert(is_equal_approx(volume.scale.z, 9.0), "Bounds must contain the entire plume")
	assert(a.to_local(volume.to_global(Vector3(0, 0, -0.5))).length() < 0.00001, "Nozzle origin must stay at the volume's front")
	var camera := Camera3D.new()
	host.add_child(camera)
	camera.position = Vector3(0, 0, 1000)
	camera.make_current()
	a._process(0.0)
	assert(not volume.visible, "Distance culling")
	camera.position = Vector3(0, 2, 10)
	a.throttle = 0.0
	a._process(5.0)
	assert(not volume.visible, "Spool-down must finish invisible")
	host.queue_free()
	await process_frame
	print("PASS: independent instances, shared noise, clamps, smoothing, afterburner, transformed bounds, distance/off culling")
	if "--visual" in OS.get_cmdline_user_args():
		await _capture_views()
	# Let project-autoload audio release playback before this short-lived test exits.
	for player in root.find_children("*", "AudioStreamPlayer", true, false):
		player.stop()
	await create_timer(0.1).timeout
	quit()

func _capture_views() -> void:
	var preview = load("res://scenes/vfx/preview/jet_exhaust_preview.tscn").instantiate()
	root.add_child(preview)
	root.size = Vector2i(1280, 720)
	var folder := OS.get_environment("TEMP").path_join("jet_exhaust_validation")
	if OS.get_environment("TEMP").is_empty():
		folder = "user://jet_exhaust_validation"
	DirAccess.make_dir_recursive_absolute(folder)
	await create_timer(2.0).timeout
	for index in 6:
		preview.set_view(index)
		await create_timer(0.3).timeout
		await RenderingServer.frame_post_draw
		assert(root.get_texture().get_image().save_png(folder.path_join("view_%d.png" % index)) == OK)
	preview.set_view(1)
	for power in [0.0, 0.2, 0.55, 0.8, 1.0]:
		preview.slider.value = power
		await create_timer(1.8).timeout
		await RenderingServer.frame_post_draw
		assert(root.get_texture().get_image().save_png(folder.path_join("throttle_%03d.png" % int(power * 100))) == OK)
	# Freeze the same dry-thrust field: only refraction changes between these images.
	preview.slider.value = 0.8
	preview.ui.visible = false
	var effect = preview.engine.get_node("JetExhaust")
	effect.flow_speed = 0.0
	effect.brightness = 0.0
	await create_timer(2.0).timeout
	await RenderingServer.frame_post_draw
	var haze: Image = root.get_texture().get_image()
	effect.heat_distortion = 0.0
	await create_timer(0.2).timeout
	await RenderingServer.frame_post_draw
	var clear: Image = root.get_texture().get_image()
	var changed := 0
	for y in range(180, 500):
		for x in range(300, 850):
			var h := haze.get_pixel(x, y)
			var c := clear.get_pixel(x, y)
			if absf(h.r - c.r) + absf(h.g - c.g) + absf(h.b - c.b) > 0.03:
				changed += 1
	assert(changed > 100, "Heat haze must actually move background pixels, not just add glow")
	haze.save_png(folder.path_join("haze_on.png"))
	clear.save_png(folder.path_join("haze_off.png"))
	print("PASS: rendered six views, five throttle states; haze moved %d background pixels. Captures: %s" % [changed, folder])
	preview.queue_free()
	await process_frame
