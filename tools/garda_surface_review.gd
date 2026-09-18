extends SceneTree
## Read-only, fixed-camera A/B captures. No scene, terrain or asset saves.
## godot --path . --script res://tools/garda_surface_review.gd -- --variants=baseline,native,filtered,surface
## Use --check headlessly for scene/resource checks; graphical runs require Forward+.
const MAP := "res://scenes/maps/garda_final.tscn"
const LEGACY := "res://resources/terrain/terrain_wc_override.gdshader"
const SURFACE := "res://resources/terrain/garda_surface.gdshader"
const VIEWS := [
	{"id": "alpine_near", "target": Vector3(-120920, 0, -114800), "offset": Vector3(160, 80, -30)},
	{"id": "alpine_mid", "target": Vector3(-120920, 0, -114800), "offset": Vector3(1500, 650, -280)},
	{"id": "alpine_far", "target": Vector3(-120920, 0, -114800), "offset": Vector3(6400, 2700, -1200)},
	{"id": "garda", "target": Vector3(-36418, 0, 410), "offset": Vector3(6000, 4200, 11000)},
	{"id": "lowland", "target": Vector3(0, 0, 0), "offset": Vector3(800, 650, 1000)},
	{"id": "ground", "target": Vector3(0, 0, 0), "offset": Vector3(16, 8, 22)},
	{"id": "cruise", "target": Vector3(0, 0, -5000), "offset": Vector3(0, 7000, 8000)},
	{"id": "region_seam", "target": Vector3(15625, 0, -15000), "offset": Vector3(1300, 1600, 1500)},
]

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var variants := PackedStringArray(["baseline", "native", "filtered", "surface"])
	var views := VIEWS.duplicate(true)
	var out := "res://subagent-artifacts/garda-surface/" + Time.get_datetime_string_from_system().replace(":", "-")
	for arg in args:
		if arg.begins_with("--variants="):
			variants = arg.trim_prefix("--variants=").split(",")
		elif arg.begins_with("--views="):
			var ids := arg.trim_prefix("--views=").split(",")
			views = views.filter(func(v): return v.id in ids)
		elif arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
		else:
			assert(arg == "--check", "Unknown option " + arg)
	assert(not views.is_empty())
	var check := "--check" in args
	assert(check or DisplayServer.get_name() != "headless")
	for audio in root.get_node("AudioManager").get_children():
		if audio is AudioStreamPlayer:
			audio.stop()
			audio.stream = null
	root.size = Vector2i(1920, 1080)
	root.content_scale_size = root.size
	root.use_taa = false
	root.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	root.scaling_3d_scale = 1.0
	root.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	Engine.max_fps = 0
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var map: Node3D = load(MAP).instantiate()
	map.get_node("Forests").enabled = false # Isolate the surface; legacy assets have no tree slot.
	var terrain: Terrain3D = map.get_node("GardaTerrain")
	# Native READY frees texture descriptors after uploading arrays. Keep them for A/B swaps.
	terrain.free_editor_textures = false
	var camera := Camera3D.new()
	camera.fov = 70
	camera.near = 0.5
	camera.far = 400000
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	root.add_child(camera)
	camera.make_current()
	root.add_child(map)
	current_scene = map
	map.get_node("TutorialBoundaryController").set_physics_process(false)
	var driver = map.get_node("SunshineCloudsDriverGD")
	driver.set_process(false)
	driver.update_continuously = false
	driver.clouds_resource.enabled = false
	map.get_node("Sky3D/SkyDome").process_method = 2 # MANUAL
	terrain.set_camera(camera)
	var mat := terrain.material
	var original_shader := mat.shader_override
	var original_enabled := mat.shader_override_enabled
	var original_assets := terrain.assets
	var original_parameters: Dictionary = mat.get("_shader_parameters").duplicate()
	# Dummy renderer cannot reflect custom shader uniforms; load the serialized subresource.
	var surface_noise: NoiseTexture2D = load(MAP + "::NoiseTexture2D_surface")
	assert(surface_noise != null and surface_noise.seamless and surface_noise.generate_mipmaps)
	var legacy: Terrain3DMaterial = load("res://tools/fixtures/garda_legacy_material.tres")
	var legacy_parameters: Dictionary = legacy.get("_shader_parameters")
	var legacy_assets: Terrain3DAssets = load("res://terrain/garda_final_wc_uniform_250km/wc_terrain_assets.tres")
	assert(terrain.data.get_region_locations().size() == 256)
	assert(absf(terrain.vertex_spacing * 16384.0 - 250000.0) < 0.1)
	assert(original_enabled and original_shader.resource_path == SURFACE)
	assert(original_assets.resource_path == "res://resources/terrain/garda_surface_assets.tres")
	assert("_color_maps" not in original_shader.code, "Low-resolution RGB must not drive the surface")
	assert("_control_maps" not in original_shader.code.get_slice("void fragment()", 1))
	assert(original_assets.get_texture_count() == 7)
	for id in [0, 1, 2, 3, 4]:
		var asset := original_assets.get_texture(id)
		assert(asset != null)
		for texture in [asset.albedo_texture, asset.normal_texture]:
			assert(texture != null)
			var image: Image = texture.get_image()
			assert(image != null and image.get_size() == Vector2i(2048, 2048))
			assert(image.has_mipmaps())
	var report := {"gpu": RenderingServer.get_video_adapter_name(), "renderer": RenderingServer.get_current_rendering_method(),
		"resolution": root.size, "taa": false, "clouds": false, "captures": []}
	if not check:
		assert(DirAccess.make_dir_recursive_absolute(out) == OK)
	for view in views:
		var target: Vector3 = view.target
		target.y = terrain.data.get_height(target)
		assert(is_finite(target.y))
		camera.position = target + view.offset
		camera.position.y = maxf(camera.position.y, terrain.data.get_height(camera.position) + 5.0)
		camera.look_at(target)
		camera.force_update_transform()
		print("VIEW ", view.id, " eye=", camera.position, " target=", target)
		for variant in variants:
			if variant != "surface":
				terrain.assets = legacy_assets
				mat.shader_override_enabled = false
				for parameter in legacy_parameters:
					if legacy_parameters[parameter] != null:
						mat.set_shader_param(parameter, legacy_parameters[parameter])
			match variant:
				"baseline", "filtered", "no_color":
					mat.shader_override = load(LEGACY)
					mat.shader_override_enabled = true
					for parameter in legacy_parameters:
						if legacy_parameters[parameter] != null:
							mat.set_shader_param(parameter, legacy_parameters[parameter])
					mat.set_shader_param("wc_colormap_strength", 0.75)
					if variant == "filtered":
						var shader := Shader.new()
						shader.code = mat.shader_override.code.replace("region_mip < 0.0 && region_uv.z > -1.", "region_uv.z > -1.")
						mat.shader_override = shader
					if variant == "no_color":
						mat.set_shader_param("wc_colormap_strength", 0.0)
				"native":
					mat.shader_override_enabled = false
				"surface":
					terrain.assets = original_assets
					mat.shader_override = load(SURFACE)
					mat.shader_override_enabled = true
					mat.set_shader_param("surface_noise", surface_noise)
				_:
					assert(false, "Unknown variant " + variant)
			assert(absf(terrain.data.get_height(target) - target.y) < 0.001, "Material changed geometry")
			if check:
				await process_frame
				continue
			for frame in 60:
				await RenderingServer.frame_post_draw
			var samples: Array[float] = []
			var gpu: Array[float] = []
			for frame in 120:
				var start := Time.get_ticks_usec()
				await RenderingServer.frame_post_draw
				samples.append((Time.get_ticks_usec() - start) / 1000.0)
				gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()))
			samples.sort()
			gpu.sort()
			var image := root.get_texture().get_image()
			var name: String = view.id + "_" + variant + ".png"
			assert(image.save_png(out.path_join(name)) == OK)
			report.captures.append({"file": name, "eye": camera.position, "target": target,
				"median_frame_ms": samples[60], "p95_frame_ms": samples[114], "median_gpu_ms": gpu[60]})
			print("CAPTURE ", name, " median=", samples[60], " p95=", samples[114], " GPU=", gpu[60])
	if not check:
		var file := FileAccess.open(out.path_join("report.json"), FileAccess.WRITE)
		file.store_string(JSON.stringify(report, "\t"))
		file.close()
		print("CAPTURES ", ProjectSettings.globalize_path(out))
	mat.shader_override = original_shader
	mat.shader_override_enabled = original_enabled
	terrain.assets = original_assets
	for parameter in original_parameters:
		mat.set_shader_param(parameter, original_parameters[parameter])
	# Exercise the real F6 caller, including its shader construction and restoration.
	var filter_probe = load("res://scripts/ui/freeroam_filter_toggle.gd").new()
	filter_probe.terrain_path = NodePath("../GardaTerrain")
	map.add_child(filter_probe)
	for mode in [6, 7, 0]:
		filter_probe.apply_mode(mode)
		assert(mat.shader_override == original_shader and mat.shader_override_enabled)
		if DisplayServer.get_name() != "headless":
			assert(is_equal_approx(float(mat.get_shader_param("depth_blur")), 2.0 if mode == 7 else 0.0))
		await process_frame
	filter_probe.queue_free()
	map.queue_free()
	camera.queue_free()
	for frame in 3:
		await process_frame
	print("GARDA SURFACE REVIEW PASS")
	quit()
