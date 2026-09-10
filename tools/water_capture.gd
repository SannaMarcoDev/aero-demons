extends SceneTree
## Real map, production atmosphere, runtime-only A/B. Never saves scene/resources.
## godot --path . --script tools/water_capture.gd --fixed-fps 30
## -- --check (headless OK), --preview (720p), --view=shore, --motion, --hold.
## --still: check 32 consecutive frames at a fixed camera (not every jitter cycle).
## --hold: Left/Right view, Space legacy/new, Esc exit. --motion: 6 s at 30 fps;
## combine with Godot --write-movie <absolute-path.avi> for continuous review.

const MAP := "res://scenes/maps/garda_final.tscn"
const LEGACY := "res://resources/materials/barnegat_water.tres"
const PRODUCTION := "res://resources/materials/garda_water.tres"
const SETTLE := 96
const PHASE := 12.0
const VIEWS := [
	{"id": "low", "eye": Vector3(-54000, 438, -11000), "target": Vector3(-53000, 408.08, -10800)},
	{"id": "shore", "eye": Vector3(-54000, 1000, -11000), "target": Vector3(-47000, 408.08, -10000)},
	{"id": "glints", "eye": Vector3(-65000, 1300, -10000), "target": Vector3(-63000, 408.08, -10600)},
	{"id": "coast", "eye": Vector3(-55000, 1900, 5000), "target": Vector3(-48000, 408.08, 0)},
	{"id": "flight", "eye": Vector3(-30000, 12000, 20000), "target": Vector3(-30000, 408.08, 0)},
	{"id": "above", "eye": Vector3(-40000, 19500, -5000), "target": Vector3(-37000, 408.08, -10000)},
	{"id": "shore_detail", "eye": Vector3(-45300, 460, 40), "target": Vector3(-45242.31, 408.08, 0)},
	{"id": "shore_coast", "eye": Vector3(-45500, 590, 350), "target": Vector3(-45242.31, 408.08, 0)},
	{"id": "shore_shallow", "eye": Vector3(-44350, 450, 10030), "target": Vector3(-44265.75, 408.08, 10000)},
]
var map: Node3D
var camera: Camera3D
var water: MeshInstance3D
var terrain: Terrain3D
var clouds: SunshineCloudsGD
var meshes: Dictionary
var materials: Dictionary
var original_mesh: Mesh
var original_override: Material
var view_index := 0
var variant := "new"
var holding := false
var held_key := 0
var output: String
var manifest: Dictionary
var frozen_phase: Dictionary

func _initialize() -> void:
	call_deferred("run")

func capture_timeout() -> void:
	if not holding or "--check" in OS.get_cmdline_user_args():
		push_error("Water capture did not finish within 180 seconds; inspect the preceding errors")
		quit(1)

func run() -> void:
	# Assertions stop their coroutine in debug builds; fail boundedly instead of hanging.
	create_timer(180.0).timeout.connect(capture_timeout)
	var args := OS.get_cmdline_user_args()
	var check := "--check" in args
	var views: Array = VIEWS.duplicate()
	for arg in args:
		if arg.begins_with("--view="):
			views = VIEWS.filter(func(view): return view.id == arg.trim_prefix("--view="))
			assert(not views.is_empty(), "Unknown view: " + arg)
		else:
			assert(arg in ["--check", "--preview", "--motion", "--hold", "--still"], "Unknown option: " + arg)
	assert(check or DisplayServer.get_name() != "headless", "Captures require graphical Forward+")
	seed(42137)
	root.size = Vector2i(1280, 720) if "--preview" in args or check else Vector2i(1920, 1080)
	root.content_scale_size = root.size
	map = load(MAP).instantiate()
	root.add_child(map)
	current_scene = map
	map.get_node("TutorialBoundaryController").set_physics_process(false)
	camera = Camera3D.new()
	camera.fov = 70.0
	camera.near = 1.0
	camera.far = 460000.0
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	map.add_child(camera)
	camera.make_current()
	terrain = map.get_node("GardaTerrain")
	terrain.set_camera(camera) # Read-only terrain usage: only its viewing camera changes.
	water = map.get_node("Water")
	original_mesh = water.mesh
	original_override = water.material_override
	assert(water.get_script() == null and original_override == null, "No shoreline script or runtime material override")
	assert(original_mesh.material.resource_path == PRODUCTION, "Production map must use new water")
	assert(original_mesh.subdivide_width == 0 and original_mesh.subdivide_depth == 0)
	meshes.new = original_mesh
	var old_grid := PlaneMesh.new()
	old_grid.size = original_mesh.size
	old_grid.subdivide_width = 853
	old_grid.subdivide_depth = 853
	meshes.legacy = old_grid
	materials.new = load(PRODUCTION) # Test the actual material, without freezing or rewriting its shader.
	materials.legacy = capture_material(load(LEGACY))
	var driver: SunshineCloudsDriverGD = map.get_node("SunshineCloudsDriverGD")
	clouds = driver.clouds_resource
	driver.set_process(false)
	driver.update_continuously = false
	var dome = map.get_node("Sky3D/SkyDome")
	dome.process_method = dome.MANUAL
	clouds.current_time = PHASE
	clouds.extra_large_scale_clouds_position = Vector3.ZERO
	clouds.large_scale_clouds_position = Vector3.ZERO
	clouds.medium_scale_clouds_position = Vector3.ZERO
	clouds.detail_clouds_position = Vector3.ZERO
	place_view(views[0])
	for frame in 120:
		await process_frame
	driver.retrieve_texture_data()
	frozen_phase = cloud_phase()
	assert(DisplayServer.get_name() == "headless" or (clouds.enabled and clouds.effect_callback_type == CompositorEffect.EFFECT_CALLBACK_TYPE_PRE_TRANSPARENT))
	for view in VIEWS:
		place_view(view)
		for name in ["new", "legacy", "new"]:
			apply_variant(name)
			assert(water.mesh == meshes[name] and water.material_override == materials[name])
		assert(materials.legacy.get_shader_parameter("capture_time") == PHASE)
	# Contract check catches accidental return to the transparent pipeline.
	var code: String = load(PRODUCTION).shader.code
	assert(not "ALPHA" in code and not "hint_screen_texture" in code and not "hint_depth_texture" in code)
	assert("METALLIC = 0.0" in code and "filter_linear_mipmap_anisotropic" in code)
	assert(not "TIME" in code and not "shoreline_foam" in code)
	assert("NORMAL =" in code and materials.new.get_shader_parameter("wave_normal") != null, "Keep the approved ripples")
	assert(root.scaling_3d_mode == Viewport.SCALING_3D_MODE_BILINEAR and not root.use_taa)
	assert(root.screen_space_aa == Viewport.SCREEN_SPACE_AA_FXAA, "Default AA must not jitter the stationary lake")
	if check:
		# Exercise actual viewer input, including held-key suppression and wraparound.
		place_view(VIEWS[0])
		holding = true
		for key in [KEY_SPACE, KEY_LEFT, KEY_RIGHT, KEY_SPACE]:
			var expected_variant := ("legacy" if variant == "new" else "new") if key == KEY_SPACE else variant
			var expected_view := posmod(view_index + (-1 if key == KEY_LEFT else 1), VIEWS.size()) if key != KEY_SPACE else view_index
			var event := InputEventKey.new()
			event.keycode = key
			event.pressed = true
			Input.parse_input_event(event)
			Input.flush_buffered_events()
			_process(0.0)
			_process(0.0)
			assert(variant == expected_variant and view_index == expected_view, "Viewer key %s: %s/%s expected %s/%s" % [key, variant, view_index, expected_variant, expected_view])
			event = event.duplicate()
			event.pressed = false
			Input.parse_input_event(event)
			Input.flush_buffered_events()
			_process(0.0)
		holding = false
		print("PASS: foam removed, ripples preserved, non-temporal AA, A/B roundtrip, viewer keys, %d finite cameras" % VIEWS.size())
		await finish()
		return

	output = ProjectSettings.globalize_path("user://water_captures/" + Time.get_datetime_string_from_system().replace(":", "-") + "-" + str(OS.get_process_id()))
	assert(not DirAccess.dir_exists_absolute(output))
	assert(DirAccess.make_dir_recursive_absolute(output) == OK)
	manifest = {"map": MAP, "godot": Engine.get_version_info().string, "output": output,
		"renderer": RenderingServer.get_current_rendering_method(), "size": root.size,
		"scaling_mode": root.scaling_3d_mode, "scaling_scale": root.scaling_3d_scale, "taa": root.use_taa, "screen_space_aa": root.screen_space_aa,
		"settle_frames": SETTLE, "water_time": PHASE, "cloud_phase": frozen_phase,
		"water_transform": water.global_transform, "water_size": original_mesh.size,
		"new_triangles": 2, "legacy_triangles": 1458632, "captures": [],
		"shader_sha256": {"new": code.sha256_text(), "legacy": load(LEGACY).shader.code.sha256_text()},
		"material_sha256": {"new": FileAccess.get_file_as_string(PRODUCTION).sha256_text(),
			"legacy": FileAccess.get_file_as_string(LEGACY).sha256_text()},
		"gpu": RenderingServer.get_video_adapter_name(), "arguments": OS.get_cmdline_args(),
		"atmosphere": {"density": clouds.atmospheric_density, "blend": clouds.use_environment_fog,
			"color": clouds.atmosphere_color, "floor": clouds.cloud_floor, "ceiling": clouds.cloud_ceiling}}
	for view in ([] if "--motion" in args or "--still" in args else views):
		place_view(view)
		var first: Image
		var legacy: Image
		for name in ["new", "legacy", "new_repeat"]:
			apply_variant("new" if name == "new_repeat" else name)
			# ponytail: fixed warmup; new_repeat measures remaining history, not visual quality.
			for frame in SETTLE:
				await RenderingServer.frame_post_draw
			assert(cloud_phase() == frozen_phase, "Clouds or sunlight drifted")
			var image := save_capture(view.id + "_" + name)
			if name == "new":
				first = image
			elif name == "legacy":
				legacy = image
			else:
				var repeat_error := mean_difference(first, image)
				var change := mean_difference(first, legacy)
				manifest.captures[-1]["repeat_mae"] = repeat_error
				manifest.captures[-1]["comparison_new_mae"] = change
				write_manifest() # Keep failure evidence if convergence check fails.
				assert(repeat_error < 0.005, "Unsettled temporal history; inspect new_repeat")
				assert(change > 0.002, "A/B appears identical; check water visibility/material binding")
				var sheet := Image.create(root.size.x * 2, root.size.y, false, image.get_format())
				sheet.blit_rect(legacy, Rect2i(Vector2i.ZERO, root.size), Vector2i.ZERO)
				sheet.blit_rect(first, Rect2i(Vector2i.ZERO, root.size), Vector2i(root.size.x, 0))
				assert(sheet.save_png(output.path_join(view.id + "_legacy-left_new-right.png")) == OK)
				print(view.id, " repeat MAE=", repeat_error, " A/B MAE=", change)
	if "--still" in args:
		place_view(views[0])
		apply_variant("new")
		for frame in SETTLE:
			await RenderingServer.frame_post_draw
		var previous: Image
		var maximum := 0.0
		var roi := Rect2i(root.size.x / 4, root.size.y * 5 / 9, root.size.x / 2, root.size.y / 3)
		for frame in 32:
			await RenderingServer.frame_post_draw
			assert(cloud_phase() == frozen_phase)
			var image := root.get_texture().get_image().get_region(roi)
			if previous != null:
				maximum = maxf(maximum, mean_difference(previous, image))
			previous = image
			if frame == 0 or frame == 31:
				save_capture("still_%02d" % frame)
		manifest["static_max_consecutive_mae"] = maximum
		write_manifest()
		assert(maximum < 0.0001, "Stationary water jitters between consecutive frames")
		print("PASS: 32 consecutive stationary frames, max water ROI MAE=", maximum)
	if "--motion" in args:
		place_view(views[0])
		apply_variant("new")
		for frame in SETTLE:
			await RenderingServer.frame_post_draw
		for frame in 180:
			var seconds := float(frame) / 30.0
			camera.global_position = views[0].eye + Vector3(60.0, 0.0, 0.0) * seconds
			var ground: float = terrain.data.get_height(camera.global_position)
			assert(is_finite(ground) and camera.global_position.y > maxf(ground, water.global_position.y) + 5.0)
			await RenderingServer.frame_post_draw
			if frame % 30 == 0:
				save_capture("motion_%03d" % frame)
	write_manifest()
	print("PASS: water captures saved: ", output)
	if "--hold" in args:
		holding = true
		place_view(views[0])
		apply_variant("new")
		print("Viewer: Left/Right views, Space legacy/new, Esc quit")
	else:
		await finish()

func capture_material(source: ShaderMaterial) -> ShaderMaterial:
	var result := source.duplicate() as ShaderMaterial
	var shader := Shader.new()
	var time_token := RegEx.new()
	assert(time_token.compile("\\bTIME\\b") == OK)
	shader.code = time_token.sub(source.shader.code, "capture_time", true).replace(
		"shader_type spatial;", "shader_type spatial;\nuniform float capture_time = 12.0;")
	result.shader = shader # Instrument only the in-memory copy, including the legacy shader.
	result.set_shader_parameter("capture_time", PHASE)
	assert(source.shader != result.shader)
	return result

func place_view(view: Dictionary) -> void:
	view_index = VIEWS.find(view)
	camera.global_position = view.eye
	camera.look_at(view.target)
	camera.force_update_transform()
	var ground: float = terrain.data.get_height(view.eye)
	assert(is_finite(ground) and view.eye.y > maxf(ground, water.global_position.y) + 5.0)
	assert(camera.is_current() and camera.global_transform.is_finite())
	assert(camera.is_position_in_frustum(view.target))

func apply_variant(name: String) -> void:
	variant = name
	water.mesh = meshes[name]
	water.material_override = materials[name]
	if name == "legacy":
		materials.legacy.set_shader_parameter("capture_time", PHASE)
	root.title = "Water / " + VIEWS[view_index].id + " / " + name + " — Space: A/B, arrows: view"

func cloud_phase() -> Dictionary:
	return {"time": clouds.current_time, "large": clouds.large_scale_clouds_position,
		"extra_large": clouds.extra_large_scale_clouds_position, "medium": clouds.medium_scale_clouds_position,
		"detail": clouds.detail_clouds_position, "sun": map.get_node("Sky3D/SunLight").global_transform,
		"lights": clouds.directional_lights_data.duplicate()}

func save_capture(id: String) -> Image:
	var image := root.get_texture().get_image()
	assert(image != null and not image.is_empty() and image.get_size() == root.size)
	assert(image.save_png(output.path_join(id + ".png")) == OK)
	manifest.captures.append({"file": id + ".png", "variant": variant,
		"camera_transform": camera.global_transform, "fov": camera.fov, "near": camera.near, "far": camera.far,
		"water_time": materials[variant].get_shader_parameter("capture_time")})
	return image

func mean_difference(a: Image, b: Image) -> float:
	assert(a.get_size() == b.get_size())
	var total := 0.0
	var count := 0
	for y in range(0, a.get_height(), 4):
		for x in range(0, a.get_width(), 4):
			var delta := a.get_pixel(x, y) - b.get_pixel(x, y)
			total += absf(delta.r) + absf(delta.g) + absf(delta.b)
			count += 3
	return total / count

func write_manifest() -> void:
	var file := FileAccess.open(output.path_join("manifest.json"), FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify(manifest, "\t"))
	file.close()

func _process(_delta: float) -> bool:
	if not holding:
		return false
	var key := 0
	for candidate in [KEY_ESCAPE, KEY_SPACE, KEY_LEFT, KEY_RIGHT]:
		if Input.is_key_pressed(candidate):
			key = candidate
			break
	if key != held_key:
		match key:
			KEY_ESCAPE:
				holding = false
				finish()
			KEY_SPACE:
				apply_variant("legacy" if variant == "new" else "new")
			KEY_LEFT, KEY_RIGHT:
				place_view(VIEWS[posmod(view_index + (1 if key == KEY_RIGHT else -1), VIEWS.size())])
				apply_variant(variant)
	held_key = key
	return false

func finish() -> void:
	water.mesh = original_mesh
	water.material_override = original_override
	map.queue_free()
	for frame in 3:
		await process_frame
	quit()
