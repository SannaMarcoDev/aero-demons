extends SceneTree
## Runtime-only preset comparison on the current freeroam map. Never saves resources.
## Godot --path . --script tools/horizon_preset_capture.gd --fixed-fps 30
## Add -- --check for state checks, or --preview for one view at 1280x720.
## Full-resolution PNGs and effective settings: user://horizon_presets/<unique run>/.

const LEVEL := "res://scenes/levels/freeroam.tscn"
const PRESETS := [
	{"id": "A", "name": "Attuale", "density": 1.25, "blend": 0.35, "color": Color(0.518, 0.553, 0.608), "blur": 0.0},
	{"id": "B", "name": "Foschia morbida", "density": 1.6, "blend": 0.55, "color": Color(0.55, 0.64, 0.75), "blur": 0.0},
	{"id": "C", "name": "Orizzonte piu sfumato", "density": 2.0, "blend": 0.65, "color": Color(0.55, 0.64, 0.75), "blur": 0.0},
	{"id": "D", "name": "C + blur lontano", "density": 2.0, "blend": 0.65, "color": Color(0.55, 0.64, 0.75), "blur": 0.08},
]
const SETTLE := 96
var level: Node3D
var player: Node3D
var camera: Camera3D
var map: Node3D
var driver: SunshineCloudsDriverGD
var clouds: SunshineCloudsGD
var baseline: Dictionary
var attributes: CameraAttributesPractical
var cloud_phase: Dictionary

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var check := "--check" in OS.get_cmdline_user_args()
	var preview := "--preview" in OS.get_cmdline_user_args()
	assert(check or DisplayServer.get_name() != "headless", "Captures need a graphical renderer")
	seed(42137)
	root.size = Vector2i(1280, 720) if preview or check else Vector2i(1920, 1080)
	root.content_scale_size = root.size
	level = load(LEVEL).instantiate()
	root.add_child(level)
	current_scene = level
	player = level.get_node("Player")
	camera = player.get_node("FlightCamera")
	map = level.get_node("GardaLake")
	driver = map.get_node("SunshineCloudsDriverGD")
	clouds = driver.clouds_resource
	# Stop flight immediately: the enlarged terrain may be above the old spawn.
	player.process_mode = Node.PROCESS_MODE_DISABLED
	camera.set_process(false)
	camera.set_physics_process(false)
	player.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	for child in level.get_children():
		if child is CanvasLayer:
			child.hide() # Same unobstructed comparison; no F6 label claiming "Attuale" on candidates.
	for frame in 120:
		await process_frame
	assert(map.get_node("TutorialBoundaryController").get_return_distance() > 0.0)
	map.get_node("TutorialBoundaryController").set_physics_process(false)
	driver.set_process(false)
	driver.update_continuously = false
	map.get_node("Sky3D/SkyDome").process_method = map.get_node("Sky3D/SkyDome").MANUAL
	assert(driver.ambience_sample_environment == null)
	assert(not map.get_node("Sky3D/SkyDome").fog_visible)
	assert(driver.tracked_point_effectors.is_empty())
	var original_attributes = camera.attributes
	attributes = map.get_node("Sky3D").camera_attributes.duplicate() if original_attributes == null else original_attributes.duplicate()
	camera.attributes = attributes
	baseline = {"density": clouds.atmospheric_density, "blend": clouds.use_environment_fog,
		"color": clouds.atmosphere_color, "sampled_color": clouds.sampled_environment_fog_color,
		"attributes": original_attributes, "dof": attributes.duplicate()}
	cloud_phase = phase()
	var views: Array[Dictionary] = [
		{"id": "12000", "altitude": 12000.0, "pitch": -17.0, "bank": -18.0},
		{"id": "19500", "altitude": 19500.0, "pitch": -22.0, "bank": -12.0},
	]
	if preview:
		views.resize(1)
	# Small runnable check: every candidate followed by A must restore the exact baseline.
	for preset in PRESETS:
		apply_preset(preset)
		assert(is_equal_approx(attributes.dof_blur_amount, preset.blur) if preset.id != "A" else true)
		apply_preset(PRESETS[0])
		assert(clouds.atmospheric_density == baseline.density and clouds.use_environment_fog == baseline.blend)
		assert(clouds.atmosphere_color == baseline.color and clouds.sampled_environment_fog_color == baseline.sampled_color)
		assert(attributes.dof_blur_far_enabled == baseline.dof.dof_blur_far_enabled)
	for view in views:
		place_view(view)
	if check:
		camera.attributes = original_attributes
		print("PASS: horizon candidates restore baseline; cameras finite/in-frustum; terrain read-only")
		quit()
		return
	var output := ProjectSettings.globalize_path("user://horizon_presets/" + Time.get_datetime_string_from_system().replace(":", "-") + "-" + str(OS.get_process_id()))
	assert(not DirAccess.dir_exists_absolute(output))
	assert(DirAccess.make_dir_recursive_absolute(output) == OK)
	var manifest := {"scene": LEVEL, "output": output, "size": root.size, "godot": Engine.get_version_info().string,
		"renderer": RenderingServer.get_current_rendering_method(), "settle_frames": SETTLE,
		"scaling_mode": root.scaling_3d_mode, "scaling_scale": root.scaling_3d_scale,
		"taa": root.use_taa, "msaa": root.msaa_3d, "baseline": {"density": baseline.density, "blend": baseline.blend, "color": baseline.color},
		"cloud_phase": cloud_phase, "sun_transform": map.get_node("Sky3D/SunLight").global_transform, "captures": []}
	for view in views:
		place_view(view)
		var poses: Array = PRESETS.duplicate()
		poses.append(PRESETS[0]) # A repeat tests temporal convergence and preset restoration.
		for index in poses.size():
			var preset: Dictionary = poses[index]
			apply_preset(preset)
			var suffix: String = preset.id if index < PRESETS.size() else "A_repeat"
			root.title = "Horizon presets / " + view.id + " / " + suffix
			# ponytail: fixed warmup; compare A_repeat before accepting temporal convergence.
			for frame in SETTLE:
				await RenderingServer.frame_post_draw
			assert(phase() == cloud_phase, "Cloud shape/wind phase must stay fixed")
			var image := root.get_texture().get_image()
			assert(image != null and image.get_size() == root.size)
			var filename: String = view.id + "_" + suffix + ".png"
			assert(image.save_png(output.path_join(filename)) == OK)
			manifest.captures.append({"file": filename, "preset": preset, "view": view,
				"camera_transform": camera.global_transform, "player_transform": player.global_transform,
				"fov": camera.fov, "far": camera.far, "density": clouds.atmospheric_density,
				"blend": clouds.use_environment_fog, "color": clouds.atmosphere_color,
				"dof_enabled": attributes.dof_blur_far_enabled, "dof_amount": attributes.dof_blur_amount,
				"dof_distance": attributes.dof_blur_far_distance, "dof_transition": attributes.dof_blur_far_transition})
			print("Captured ", output.path_join(filename))
	apply_preset(PRESETS[0])
	camera.attributes = original_attributes
	var file := FileAccess.open(output.path_join("manifest.json"), FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify(manifest, "\t"))
	file.close()
	print("PASS: horizon preset captures saved: ", output)
	quit()

func place_view(view: Dictionary) -> void:
	var pose := Transform3D(Basis.from_euler(Vector3(deg_to_rad(view.pitch), 0.0, deg_to_rad(view.bank))), Vector3(-4700.0, view.altitude, 850.0))
	player.reset_flight(pose)
	player.global_transform = pose
	player.reset_physics_interpolation()
	camera.snap_to_target()
	camera.force_update_transform()
	map.get_node("GardaTerrain").set_camera(camera)
	assert(camera.is_current() and camera.global_position.is_finite() and camera.global_basis.is_finite())
	assert(camera.is_position_in_frustum(player.global_position))

func apply_preset(preset: Dictionary) -> void:
	var original: bool = preset.id == "A"
	clouds.atmospheric_density = baseline.density if original else preset.density
	clouds.use_environment_fog = baseline.blend if original else preset.blend
	clouds.atmosphere_color = baseline.color if original else preset.color
	clouds.sampled_environment_fog_color = baseline.sampled_color if original else preset.color
	attributes.dof_blur_far_enabled = baseline.dof.dof_blur_far_enabled if original else preset.blur > 0.0
	attributes.dof_blur_amount = baseline.dof.dof_blur_amount if original else preset.blur
	attributes.dof_blur_far_distance = baseline.dof.dof_blur_far_distance if original else 35000.0
	attributes.dof_blur_far_transition = baseline.dof.dof_blur_far_transition if original else 45000.0
	driver.retrieve_texture_data()

func phase() -> Dictionary:
	return {"time": clouds.current_time, "extra_large": clouds.extra_large_scale_clouds_position,
		"large": clouds.large_scale_clouds_position, "medium": clouds.medium_scale_clouds_position,
		"small": clouds.detail_clouds_position, "lights": clouds.directional_lights_data.duplicate()}
