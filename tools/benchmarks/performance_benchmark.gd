extends "res://tools/benchmarks/freeroam_benchmark.gd"
class_name AeroPerformanceBenchmark
## Standalone GPU benchmark, never writes user settings. No --fixed-fps/headless.
## -- --out=user://performance --diagnose --quick --capture --views=spawn,cruise
const Settings = preload("res://scripts/core/settings_manager.gd")
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
const PRESET_NAMES := ["custom", "low", "medium", "high", "ultra"]

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
		else:
			push_error("Unknown option " + arg)
			quit(1)
			return
	if preset_name not in PRESET_NAMES.slice(1):
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
	if combat:
		# Skip the parked intro before _ready schedules it; use the real combat reveal below.
		scene.get_node("Player").start_on_ground = false
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
	var quality := PRESET_NAMES.find(preset_name)
	settings.quality_preset = quality
	settings.merge(Settings.QUALITY_PRESETS[quality], true)
	settings.merge({"resolution": "1920x1080", "window_mode": 0, "vsync": false, "fps_limit": 0,
		"render_scale": 1.0, "upscaler": Settings.UPSCALER_OFF, "aa_mode": Settings.AA_TAA}, true)
	Settings.apply_settings(settings)
	root.size = Vector2i(1920, 1080)
	root.content_scale_size = root.size
	viewport_rid = root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(viewport_rid, true)
	# Freeze the sky for repeatable A/B captures.
	world_env.get_node("SkyDome").process_method = 2
	var locations: Array = Sampler.GARDA_LOCATIONS.duplicate(true)
	if gameplay:
		locations = locations.filter(func(loc): return loc.id in ["spawn", "cruise", "airport"])
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
	var variants := ["base", "terrain_off", "shadows_off", "hud_off", "water_off", "airport_off", "effects_off"] if diagnose else ["base"]
	for round_index in range(1 if quick else 3):
		for loc in locations:
			if not view_filter.is_empty() and loc.id not in view_filter: continue
			for variant in variants:
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
				if gameplay:
					place_aircraft(loc, 0.0)
					player.reset_flight(player.global_transform)
				var firing_timers: Array[Timer] = []
				var sample_loc: Dictionary = loc.duplicate()
				if combat:
					if not await prepare_combat():
						quit(1)
						return
					# The reveal advances the formation: measure from its actual handoff pose.
					sample_loc.pos = player.global_position
					var mission = scene.get_node("CombatHUD/MissionController")
					for weapon in ["fire_gun", "fire_missile"]:
						var timer := Timer.new()
						timer.wait_time = 0.1 if weapon == "fire_gun" else 2.0
						timer.timeout.connect(Callable(mission.weapons, weapon))
						scene.add_child(timer)
						timer.start()
						firing_timers.append(timer)
				await measure(sample_loc, {"phase": "combat" if combat else ("gameplay" if gameplay else "performance"), "round": round_index + 1, "preset": preset_name, "variant": variant_id, "ablation": variant}, 2.0 if quick else 3.5, 12.0 if combat else (3.0 if quick else 6.0))
				for timer in firing_timers: timer.queue_free()
				if combat:
					results.back()["enemies_at_start"] = 4
					results.back()["combat_start_position"] = str(sample_loc.pos)
					results.back()["enemies_remaining"] = scene.get_node("CombatHUD/MissionController").active_enemies.size()
				results.back()["effective"] = effective_parameters()
				if gameplay:
					if paused or not player.is_alive() or player.global_position.distance_to(sample_loc.pos) < 100.0:
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
		Engine.max_fps = 60 # Only visual acquisition, never the measured windows above.
		for loc in locations:
			if loc.id not in ["cruise", "alpine", "airport"]: continue
			place_aircraft(loc, 0.0)
			await create_timer(1.0).timeout
			var start := player.global_transform
			# Fixed camera poses, independent of performance and PNG I/O.
			# Translation, fast rotation, camera cut, then history convergence.
			for frame in 180:
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
		"arguments": OS.get_cmdline_user_args(), "effective": effective_parameters(),
		"debug_build": OS.is_debug_build(), "editor_binary": OS.has_feature("editor"),
		"cpu": OS.get_processor_name(), "rendering_method": RenderingServer.get_current_rendering_method(),
		"viewport": {"scale": root.scaling_3d_scale, "scaling_mode": root.scaling_3d_mode, "taa": root.use_taa,
			"screen_aa": root.screen_space_aa, "msaa": root.msaa_3d}, "gpu": RenderingServer.get_video_adapter_name(), "godot": Engine.get_version_info().string,
		"driver": RenderingServer.get_current_rendering_driver_name(), "settings": settings,
		"vsync": DisplayServer.window_get_vsync_mode(), "window": str(root.size),
		"results": results}, "\t"))
	file.close()
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

func prepare_combat() -> bool:
	var mission = scene.get_node("CombatHUD/MissionController")
	var cinematic = mission.cinematic
	paused = false
	mission.radio.stop()
	mission.hud.tutorial_panel.hide()
	mission.director.allow_player_attacks = false
	mission.director.set_physics_process(false)
	for aircraft in mission.active_enemies + cinematic.escorts:
		if is_instance_valid(aircraft): aircraft.queue_free()
	mission.active_enemies.clear()
	cinematic.escorts.clear()
	cinematic.interceptors.clear()
	if is_instance_valid(cinematic._sphere): cinematic._sphere.queue_free()
	cinematic._sphere = null
	cinematic._convoy_age = 0.0
	for projectile in get_nodes_in_group("mission_projectiles"): projectile.queue_free()
	await process_frame
	seed(20260211)
	mission.terminal = false
	mission._half_call_pending = false
	mission._begin_flight()
	mission.radio.stop()
	# Only shorten untimed dialogue; production spawn, reveal and weapon handoff stay shared.
	mission.radio.minimum_line_seconds = 0.01
	mission.radio.seconds_per_character = 0.0001
	mission.phase = mission.Phase.REVEAL
	await mission._reveal()
	mission.hud.tutorial_panel.hide()
	paused = false
	mission.phase = mission.Phase.GUN_READING
	mission._on_tutorial_confirmed()
	mission.radio.stop()
	player.invulnerable = true # Keep neutral-flight measurements alive, as in the old harness.
	player.controls_enabled = false
	if mission.active_enemies.size() != 4 or mission.director.pilots.size() != 6:
		push_error("Combat benchmark requires the current four interceptors and two wingmen")
		return false
	return true

func effective_parameters() -> Dictionary:
	var applied := {}
	applied["shadows"] = {"enabled": sun.shadow_enabled, "mode": sun.directional_shadow_mode, "distance": sun.directional_shadow_max_distance,
		"atlas_size": ProjectSettings.get_setting("rendering/lights_and_shadows/directional_shadow/size")}
	var effects := {}
	for property in ["ssao_enabled", "ssil_enabled", "ssr_enabled", "glow_enabled", "volumetric_fog_enabled", "tonemap_mode", "tonemap_exposure"]:
		effects[property] = world_env.environment.get(property)
	applied["effects"] = effects
	return applied
