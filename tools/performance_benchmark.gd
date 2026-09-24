extends "res://tools/freeroam_benchmark.gd"
class_name AeroPerformanceBenchmark
## Standalone GPU benchmark, never writes user settings. No --fixed-fps/headless.
## -- --out=user://performance --diagnose --quick --capture --views=spawn,clouds
const Settings = preload("res://scripts/ui/settings_manager.gd")
var output_dir := "user://performance"
var diagnose := false
var capture := false
var capture_motion := false
var gameplay := false
var combat := false
var view_filter := PackedStringArray()
var preset_name := "ultra"
var variant_id := ""
var build_id := "unspecified"
var cloud_overrides := {}
const PRESET_NAMES := ["custom", "low", "medium", "high", "ultra"]
# Bounds for opt-in experiments; these are not another set of quality presets.
const CLOUD_BOUNDS := {"res": [0, 3], "steps": [1, 2048], "light_steps": [1, 128],
	"sun_steps": [1, 128], "lod": [0.01, 2], "blur_q": [0, 6], "blur_p": [0, 20],
	"travel": [1, 20000], "accum": [0, 0.99], "min_d": [1, 1000], "max_d": [1, 2000]}

func _initialize() -> void:
	print("PERFORMANCE BENCHMARK START: release=", not OS.is_debug_build(), " editor_binary=", OS.has_feature("editor"))
	for arg in OS.get_cmdline_user_args():
		if arg == "--quick": quick = true
		elif arg == "--diagnose": diagnose = true
		elif arg == "--capture": capture = true
		elif arg == "--profile-gpu": pass
		elif arg == "--motion": capture_motion = true
		elif arg == "--gameplay": gameplay = true
		elif arg == "--combat":
			combat = true
			gameplay = true
		elif arg.begins_with("--out="): output_dir = arg.trim_prefix("--out=")
		elif arg.begins_with("--views="): view_filter = arg.trim_prefix("--views=").split(",")
		elif arg.begins_with("--preset="): preset_name = arg.trim_prefix("--preset=")
		elif arg.begins_with("--variant="): variant_id = arg.trim_prefix("--variant=")
		elif arg.begins_with("--build="): build_id = arg.trim_prefix("--build=")
		elif arg.begins_with("--cloud="):
			var pair := arg.trim_prefix("--cloud=").split(":")
			if pair.size() != 2 or not CLOUD_BOUNDS.has(pair[0]) or not pair[1].is_valid_float():
				push_error("Invalid cloud override: " + arg)
				quit(1)
				return
			var value := pair[1].to_float()
			var bounds: Array = CLOUD_BOUNDS[pair[0]]
			if not is_finite(value) or value < bounds[0] or value > bounds[1] or (pair[0] in ["res", "steps", "light_steps", "sun_steps"] and value != floor(value)):
				push_error("Out-of-range cloud override: " + arg)
				quit(1)
				return
			cloud_overrides[pair[0]] = value
		else:
			push_error("Unknown option " + arg)
			quit(1)
			return
	if preset_name not in PRESET_NAMES.slice(1) and preset_name != "legacy":
		push_error("Unknown preset: " + preset_name)
		quit(1)
		return
	if variant_id.is_empty(): variant_id = preset_name
	benchmark.call_deferred()

func benchmark() -> void:
	if DisplayServer.get_name() == "headless" or DirAccess.make_dir_recursive_absolute(output_dir) != OK:
		push_error("GPU benchmark requires graphical rendering and a writable output directory")
		quit(1)
		return
	scene = load("res://scenes/levels/tutorial.tscn" if combat else "res://scenes/levels/freeroam.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	player = scene.get_node("Player")
	camera = player.get_node("FlightCamera")
	terrain = scene.get_node("GardaLake/GardaTerrain")
	sun = scene.get_node("GardaLake/Sky3D/SunLight")
	world_env = scene.get_node("GardaLake/Sky3D")
	player.set_physics_process(false)
	scene.get_node("GardaLake/TutorialBoundaryController").set_physics_process(false)
	var settings := Settings.load_settings("user://performance_nonexistent.cfg")
	var legacy: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tools/performance_legacy_ultra.json"))
	var quality := Settings.QUALITY_ULTRA if preset_name == "legacy" else PRESET_NAMES.find(preset_name)
	settings.quality_preset = quality
	settings.merge(legacy.settings if preset_name == "legacy" else Settings.QUALITY_PRESETS[quality], true)
	settings.merge({"resolution": "1920x1080", "window_mode": 0, "vsync": false, "fps_limit": 0,
		"render_scale": 1.0, "upscaler": Settings.UPSCALER_OFF, "aa_mode": Settings.AA_TAA}, true)
	Settings.apply_settings(settings)
	root.size = Vector2i(1920, 1080)
	root.content_scale_size = root.size
	viewport_rid = root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(viewport_rid, true)
	# Freeze weather for repeatable A/B, retaining all shader work and quality budgets.
	var driver = scene.get_node("GardaLake/SunshineCloudsDriverGD")
	driver.set_process(false)
	var clouds = driver.clouds_resource
	var cloud_parameters: Dictionary = (legacy.clouds if preset_name == "legacy" else Settings.CLOUD_PRESETS[maxi(1, int(settings.clouds_quality))]).duplicate()
	cloud_parameters.merge(cloud_overrides, true)
	if cloud_parameters.min_d > cloud_parameters.max_d:
		push_error("min_d must not exceed max_d")
		quit(1)
		return
	if settings.clouds_quality != Settings.CLOUDS_OFF:
		Settings.apply_cloud_preset(root, clouds, cloud_parameters)
	driver.retrieve_texture_data()
	reset_weather(driver, clouds)
	world_env.get_node("SkyDome").process_method = 2
	var locations: Array = Sampler.GARDA_LOCATIONS.duplicate(true)
	if gameplay:
		locations = locations.filter(func(loc): return loc.id in ["spawn", "clouds", "airport"])
		# The static runway pose would fly into airport buildings; use an actual flyover.
		for loc in locations:
			if loc.id == "airport": loc.pos.y = 500.0
	if combat:
		locations = [{"id": "combat", "pos": Vector3(-5000, 8000, 0), "pitch": 0.0, "yaw": 0.0}]
		player.start_on_ground = false
	place_aircraft(locations[0], 0.0)
	while not scene.get_node("GardaLake/Forests").built:
		await process_frame
	await create_timer(8.0).timeout
	var startup_ms := Time.get_ticks_msec()
	var variants := ["base", "clouds_off", "terrain_off", "shadows_off", "hud_off", "water_off", "airport_off", "effects_off"] if diagnose else ["base"]
	for round_index in range(1 if quick else 3):
		for loc in locations:
			if not view_filter.is_empty() and loc.id not in view_filter: continue
			for variant in variants:
				clouds.enabled = variant != "clouds_off" and settings.clouds_quality != Settings.CLOUDS_OFF
				terrain.visible = variant != "terrain_off"
				sun.shadow_enabled = variant != "shadows_off" and settings.shadows != Settings.SHADOWS_OFF
				scene.get_node("CombatHUD").visible = variant != "hud_off"
				scene.get_node("GardaLake/Water").visible = variant != "water_off"
				scene.get_node("GardaLake/Airport").visible = variant != "airport_off"
				world_env.environment.ssao_enabled = settings.ssao and variant != "effects_off"
				world_env.environment.glow_enabled = settings.glow and variant != "effects_off"
				player.set_physics_process(gameplay)
				player.controls_enabled = not gameplay # Repeatable neutral input; flight physics still run.
				scene.get_node("GardaLake/TutorialBoundaryController").set_physics_process(gameplay)
				driver.set_process(gameplay)
				if gameplay:
					place_aircraft(loc, 0.0)
					player.reset_flight(player.global_transform)
					reset_weather(driver, clouds)
				var firing_timers: Array[Timer] = []
				if combat:
					seed(20260211)
					var mission = scene.get_node("CombatHUD/MissionController")
					mission.radio.stop()
					mission.hud.tutorial_panel.hide()
					paused = false
					mission.phase = mission.Phase.COMBAT
					mission.encounter_index = 2
					for enemy in mission.active_enemies:
						if is_instance_valid(enemy): enemy.queue_free()
					mission.active_enemies.clear()
					await process_frame
					mission._spawn_encounter()
					assert(mission.active_enemies.size() == 8)
					mission.director.allow_player_attacks = true
					mission.director.set_physics_process(true)
					mission.targeting.auto_acquire = true
					mission.weapons.firing_enabled = true
					for i in 2:
						var wing = scene.get_node("Wingman%d" % (i + 1))
						wing.global_position = player.global_position + Vector3(-150 + i * 300, 20, 100)
						wing.get_node("WeaponController").firing_enabled = true
					for weapon in ["fire_gun", "fire_missile"]:
						var timer := Timer.new()
						timer.wait_time = 0.1 if weapon == "fire_gun" else 2.0
						timer.timeout.connect(Callable(mission.weapons, weapon))
						scene.add_child(timer)
						timer.start()
						firing_timers.append(timer)
				await measure(loc, {"phase": "combat" if combat else ("gameplay" if gameplay else "performance"), "round": round_index + 1, "preset": preset_name, "variant": variant_id, "ablation": variant}, 2.0 if quick else 3.5, 12.0 if combat else (3.0 if quick else 6.0))
				for timer in firing_timers: timer.queue_free()
				if combat:
					results.back()["enemies_remaining"] = scene.get_node("CombatHUD/MissionController").active_enemies.size()
				results.back()["effective"] = effective_parameters(clouds, driver)
				if gameplay:
					if paused or not player.is_alive() or player.global_position.distance_to(loc.pos) < 100.0:
						push_error("Invalid gameplay sample: destroyed, paused or stationary aircraft")
						quit(1)
						return
					results.back()["player_position"] = str(player.global_position)
				if capture and round_index == 0:
					await RenderingServer.frame_post_draw
					if root.get_texture().get_image().save_png(output_dir.path_join(loc.id + "_" + variant + ".png")) != OK:
						push_error("Cannot save benchmark capture")
						quit(1)
						return
	if capture_motion:
		player.set_physics_process(false)
		driver.set_process(false)
		Engine.max_fps = 60 # Only visual acquisition, never the measured windows above.
		for loc in locations:
			if loc.id not in ["clouds", "alpine", "airport"]: continue
			place_aircraft(loc, 0.0)
			await create_timer(1.0).timeout
			var start := player.global_transform
			# Fixed camera poses and dither phases, independent of performance and PNG I/O.
			# Translation, fast rotation, camera cut, then history convergence.
			for frame in 180:
				clouds.current_time = float(frame) * clouds.dither_speed / 60.0
				player.global_transform = start.translated(-start.basis.z * float(mini(frame, 120)) * player.cruise_speed / 60.0)
				if frame >= 60:
					player.global_basis = start.basis * Basis(Vector3.UP, deg_to_rad(float(mini(frame - 60, 60))))
				if frame >= 120:
					player.global_basis = start.basis
				camera.snap_to_target()
				await RenderingServer.frame_post_draw
				if frame % 10 == 0 or frame in [121, 122, 124, 128]:
					if root.get_texture().get_image().save_png(output_dir.path_join("motion_%s_%03d.png" % [loc.id, frame])) != OK:
						push_error("Cannot save motion capture")
						quit(1)
						return
		Engine.max_fps = 0
	var file := FileAccess.open(output_dir.path_join("results.json"), FileAccess.WRITE)
	if file == null:
		push_error("Cannot save benchmark results")
		quit(1)
		return
	file.store_string(JSON.stringify({"variant": variant_id, "build": build_id, "preset": preset_name,
		"quick": quick, "gameplay": gameplay, "combat": combat, "startup_through_warmup_ms": startup_ms,
		"arguments": OS.get_cmdline_user_args(), "effective": effective_parameters(clouds, driver),
		"debug_build": OS.is_debug_build(), "editor_binary": OS.has_feature("editor"),
		"cpu": OS.get_processor_name(), "rendering_method": RenderingServer.get_current_rendering_method(),
		"viewport": {"scale": root.scaling_3d_scale, "scaling_mode": root.scaling_3d_mode, "taa": root.use_taa,
			"screen_aa": root.screen_space_aa, "msaa": root.msaa_3d}, "gpu": RenderingServer.get_video_adapter_name(), "godot": Engine.get_version_info().string,
		"driver": RenderingServer.get_current_rendering_driver_name(), "settings": settings,
		"vsync": DisplayServer.window_get_vsync_mode(), "window": str(root.size),
		"clouds": {"resolution_scale": clouds.resolution_scale, "steps": clouds.max_step_count,
			"lighting_steps": clouds.max_lighting_steps, "coverage": clouds.clouds_coverage}, "results": results}, "\t"))
	file.close()
	world_env.compositor = null
	RenderingServer.call_on_render_thread(clouds.clear_compute)
	await RenderingServer.frame_post_draw
	scene.queue_free()
	# Retire active WAV playback before shutting down the audio server.
	for audio_player in root.get_node("AudioManager").get_children():
		if audio_player is AudioStreamPlayer:
			audio_player.stop()
			audio_player.stream = null
	await create_timer(0.1).timeout
	print("PERFORMANCE BENCHMARK PASS: ", ProjectSettings.globalize_path(output_dir))
	quit()

func effective_parameters(clouds, driver) -> Dictionary:
	var applied := {}
	for property in ["resolution_scale", "max_step_count", "max_lighting_steps", "lod_bias", "blur_quality", "blur_power", "lighting_travel_distance", "accumulation_decay", "min_step_distance", "max_step_distance", "clouds_coverage", "cloud_floor", "cloud_ceiling", "enabled"]:
		applied[property] = clouds.get(property)
	applied["scene_size"] = str(clouds.last_size)
	applied["cloud_size"] = str(clouds.last_size / int(pow(2, clouds.resolution_scale)))
	applied["driver_sun_steps"] = driver.tracked_directional_light_shadow_steps
	var light_steps := []
	for i in range(0, clouds.directional_lights_data.size(), 2):
		light_steps.append(clouds.directional_lights_data[i].w)
	applied["light_data_steps"] = light_steps
	# Hash the actually loaded bytecode, not just the source/import timestamps.
	for entry in {"march": clouds.compute_shader, "post": clouds.post_pass_compute_shader}:
		var resource = clouds.compute_shader if entry == "march" else clouds.post_pass_compute_shader
		var hash := HashingContext.new()
		hash.start(HashingContext.HASH_SHA256)
		hash.update(resource.get_spirv().bytecode_compute)
		applied[entry + "_spirv_sha256"] = hash.finish().hex_encode()
	applied["shadows"] = {"enabled": sun.shadow_enabled, "mode": sun.directional_shadow_mode, "distance": sun.directional_shadow_max_distance,
		"atlas_size": ProjectSettings.get_setting("rendering/lights_and_shadows/directional_shadow/size")}
	var effects := {}
	for property in ["ssao_enabled", "ssil_enabled", "ssr_enabled", "glow_enabled", "volumetric_fog_enabled", "tonemap_mode", "tonemap_exposure"]:
		effects[property] = world_env.environment.get(property)
	applied["effects"] = effects
	return applied

func reset_weather(driver, clouds) -> void:
	# Reset the wind accumulator as well as its published shader values between runs.
	for property in ["extra_large_clouds_pos", "large_clouds_pos", "medium_clouds_pos", "small_clouds_pos"]:
		driver.set(property, Vector3.ZERO)
	clouds.current_time = 0.0
	clouds.extra_large_scale_clouds_position = Vector3.ZERO
	clouds.large_scale_clouds_position = Vector3.ZERO
	clouds.medium_scale_clouds_position = Vector3.ZERO
	clouds.detail_clouds_position = Vector3.ZERO
