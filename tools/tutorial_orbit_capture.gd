extends SceneTree
## Unified tutorial capture helper. Loads the real tutorial level, freezes unrelated AI,
## and captures the persisted production atmosphere against an explicit legacy baseline.
##
## Orbit mode (default): camera 60 m behind and 28 m above the plane, looking at the aircraft
## with ~25 degrees downward pitch; terrain fills the lower frame.
## Gameplay mode: -- --gameplay uses the original follow camera frozen in place.
##
## Check mode: --headless --script <this> -- --check validates roundtrip state and camera
## placement without rendering screenshots.
##
## Godot --path . --script tools/tutorial_orbit_capture.gd --fixed-fps 30 [-- --gameplay]

const LEVEL := "res://scenes/levels/tutorial.tscn"
const SETTLE_FRAMES := 96
const HAZE_BLUE := Color(0.518, 0.553, 0.608, 1.0)
const LEGACY_GROUND := Color(0.3, 0.3, 0.3, 1.0)
const LEGACY_ATMOSPHERE := Color(0.5, 0.65, 0.95, 1.0)
const LEGACY_SAMPLED := Color(0.518, 0.553, 0.608, 1.0)
const CAMERA_BACK := 60.0
const CAMERA_ABOVE := 28.0

var level: Node3D
var player: Node3D
var camera: Camera3D
var map: Node3D
var driver: SunshineCloudsDriverGD
var dome: Node
var clouds

var check_mode := false
var orbit_mode := true

var prod_ground: Color
var prod_cirrus: bool
var prod_cumulus: bool
var prod_atmosphere: Color
var prod_sampled_fog: Color
var prod_use_env: float
var prod_ambience: Environment

func _initialize() -> void:
	check_mode = "--check" in OS.get_cmdline_user_args()
	orbit_mode = not ("--gameplay" in OS.get_cmdline_user_args())
	call_deferred("run")

func run() -> void:
	if check_mode:
		await check()
	else:
		await capture()

func load_level() -> void:
	seed(42137)
	root.size = Vector2i(1280, 720)
	root.content_scale_size = root.size
	level = load(LEVEL).instantiate()
	root.add_child(level)
	current_scene = level
	for i in 120:
		await process_frame
	player = level.get_node("Player")
	camera = player.get_node("FlightCamera")
	map = level.get_node("GardaLake")
	driver = map.get_node("SunshineCloudsDriverGD")
	dome = map.get_node("Sky3D/SkyDome")
	clouds = driver.clouds_resource
	assert(player != null and camera != null and driver != null and dome != null)
	assert(not dome.fog_visible and not map.get_node("Sky3D").fog_enabled, "No AtmFog stack")
	assert(camera.is_current(), "FlightCamera is the current camera")

	# Freeze cloud/sun/wind drivers so all captures share the same phase.
	driver.set_process(false)
	driver.update_continuously = false
	dome.process_method = dome.MANUAL
	player.set_process(false)
	player.set_physics_process(false)
	camera.set_process(false)
	camera.set_physics_process(false)
	# Static diagnostic poses must not use a stale interpolated camera transform.
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	player.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF

	# Freeze unrelated AI so enemy/wingman positions do not drift between captures.
	for child in level.get_children():
		if child is Node3D and child != map and child != player:
			child.process_mode = Node.PROCESS_MODE_DISABLED

	snapshot_production()
	assert(prod_ambience == null, "ambience_sample_environment must be null so sampled_environment_fog_color is not overwritten")

func snapshot_production() -> void:
	prod_ground = dome.ground_color
	prod_cirrus = dome.cirrus_visible
	prod_cumulus = dome.cumulus_visible
	prod_atmosphere = clouds.atmosphere_color
	prod_sampled_fog = clouds.sampled_environment_fog_color
	prod_use_env = clouds.use_environment_fog
	prod_ambience = driver.ambience_sample_environment

	assert(clouds.use_environment_fog == 0.35, "Production use_environment_fog must be 0.35: " + str(clouds.use_environment_fog))
	assert(clouds.atmosphere_color.is_equal_approx(HAZE_BLUE), "Production atmosphere_color must be HAZE_BLUE")
	assert(clouds.sampled_environment_fog_color.is_equal_approx(HAZE_BLUE), "Production sampled_environment_fog_color must be HAZE_BLUE")
	assert(dome.ground_color.is_equal_approx(Color.WHITE), "Production ground_color must be white")
	assert(not dome.cirrus_visible, "Production cirrus_visible must be false")
	assert(not dome.cumulus_visible, "Production cumulus_visible must be false")

func check() -> void:
	await load_level()
	# Validate prod -> legacy -> prod roundtrip before any screenshot.
	apply_variant("prod")
	assert_variant("prod")
	apply_variant("legacy")
	assert_variant("legacy")
	apply_variant("prod")
	assert_variant("prod")

	for altitude in [2000.0, 15000.0, 19500.0]:
		place_player(altitude)
		if orbit_mode:
			set_orbit_camera(altitude)
		else:
			set_gameplay_camera()
		assert_camera(altitude)

	print("PASS: check mode — production snapshot, legacy/prod roundtrip, camera placement and frustum; orbit=", orbit_mode)
	quit()

func capture() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Capture requires a graphical Forward+ renderer")
		quit(1)
		return
	await load_level()

	var altitudes: Array = [15000.0, 19500.0] if orbit_mode else [2000.0, 15000.0, 19500.0]
	var mode_suffix := "_orbit" if orbit_mode else "_gameplay"
	var output := ProjectSettings.globalize_path("user://atmosphere_ab/" + Time.get_datetime_string_from_system().replace(":", "-") + "-" + str(OS.get_process_id()) + mode_suffix)
	assert(not DirAccess.dir_exists_absolute(output))
	assert(DirAccess.make_dir_recursive_absolute(output) == OK)

	root.size = Vector2i(1280, 720)
	root.content_scale_size = root.size

	var manifest := {"level": LEVEL, "output": output, "mode": ("orbit" if orbit_mode else "gameplay"),
		"renderer": RenderingServer.get_current_rendering_method(), "size": root.size,
		"settle_frames": SETTLE_FRAMES, "camera_back": CAMERA_BACK, "camera_above": CAMERA_ABOVE,
		"haze_blue": HAZE_BLUE, "captures": []}

	for altitude in altitudes:
		place_player(altitude)
		if orbit_mode:
			set_orbit_camera(altitude)
		else:
			set_gameplay_camera()

		# Settle the camera/level once before touching atmosphere.
		for frame in 30:
			await RenderingServer.frame_post_draw
			assert_camera(altitude)

		for variant in ["prod", "legacy"]:
			apply_variant(variant)
			assert_variant(variant)
			root.title = "Capture — " + str(int(altitude)) + "m / " + variant
			for frame in SETTLE_FRAMES:
				await RenderingServer.frame_post_draw
			assert_camera(altitude)
			var image := root.get_texture().get_image()
			assert(image != null and not image.is_empty())
			assert(image.get_size() == Vector2i(1280, 720))
			var filename: String = str(int(altitude)) + "_" + variant + ".png"
			assert(image.save_png(output.path_join(filename)) == OK)

			var screen_pos := camera.unproject_position(player.global_position)
			manifest.captures.append({"file": filename, "altitude": altitude, "variant": variant,
				"ground_color": dome.ground_color,
				"cirrus_visible": dome.cirrus_visible, "cumulus_visible": dome.cumulus_visible,
				"use_environment_fog": clouds.use_environment_fog,
				"atmosphere_color": clouds.atmosphere_color,
				"sampled_environment_fog_color": clouds.sampled_environment_fog_color,
				"camera_position": camera.global_position, "camera_basis": camera.global_basis,
				"screen_aircraft": screen_pos,
				"player_position": player.global_position})
			print("Captured ", filename)

	var file := FileAccess.open(output.path_join("manifest.json"), FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify(manifest, "\t"))
	file.close()
	print("PASS: captures saved: ", output)
	quit()

func place_player(altitude: float) -> void:
	var tf := Transform3D.IDENTITY
	tf.origin = Vector3(0.0, altitude, 0.0)
	player.global_transform = tf
	player.reset_flight(tf)

func set_orbit_camera(altitude: float) -> void:
	var cam_pos := Vector3(0.0, altitude + CAMERA_ABOVE, CAMERA_BACK)
	camera.top_level = true
	camera.current = true
	camera.global_transform = Transform3D(Basis.IDENTITY, cam_pos)
	camera.look_at(player.global_position, Vector3.UP)
	camera.reset_physics_interpolation()
	camera.force_update_transform()

func set_gameplay_camera() -> void:
	# Keep the original script and its initialized target; its processing is disabled.
	camera.snap_to_target()
	camera.force_update_transform()

func assert_camera(altitude: float) -> void:
	if not (is_equal_approx(camera.global_position.y, altitude + CAMERA_ABOVE) if orbit_mode else true):
		push_error("Orbit camera y must be altitude + " + str(CAMERA_ABOVE) + ": " + str(camera.global_position))
		quit(1)
	if not (camera.global_position.is_finite() and camera.global_basis.is_finite()):
		push_error("Camera transform must be finite: " + str(camera.global_transform))
		quit(1)
	if not camera.is_current():
		push_error("Camera must be current")
		quit(1)
	if not camera.is_position_in_frustum(player.global_position):
		push_error("Aircraft must be inside camera frustum: pos=" + str(player.global_position) + " cam=" + str(camera.global_transform))
		quit(1)
	var screen := camera.unproject_position(player.global_position)
	if not camera.get_viewport().get_visible_rect().has_point(screen):
		push_error("Aircraft must project inside viewport: " + str(screen))
		quit(1)

func apply_variant(variant: String) -> void:
	assert(variant in ["prod", "legacy"])
	# Always restore production first; this prevents state leaking from a previous variant.
	restore_production()
	if variant == "legacy":
		dome.ground_color = LEGACY_GROUND
		dome.cirrus_visible = true
		dome.cumulus_visible = false
		clouds.atmosphere_color = LEGACY_ATMOSPHERE
		clouds.sampled_environment_fog_color = LEGACY_SAMPLED
		clouds.use_environment_fog = 0.0
	driver.retrieve_texture_data()

func assert_variant(variant: String) -> void:
	assert(variant in ["prod", "legacy"])
	if variant == "prod":
		assert(dome.ground_color.is_equal_approx(prod_ground), "prod ground_color")
		assert(dome.cirrus_visible == prod_cirrus, "prod cirrus_visible")
		assert(dome.cumulus_visible == prod_cumulus, "prod cumulus_visible")
		assert(clouds.use_environment_fog == prod_use_env, "prod use_environment_fog: " + str(clouds.use_environment_fog))
		assert(clouds.atmosphere_color.is_equal_approx(prod_atmosphere), "prod atmosphere_color")
		assert(clouds.sampled_environment_fog_color.is_equal_approx(prod_sampled_fog), "prod sampled_environment_fog_color")
	else:
		assert(dome.ground_color.is_equal_approx(LEGACY_GROUND), "legacy ground_color")
		assert(dome.cirrus_visible == true, "legacy cirrus_visible")
		assert(clouds.use_environment_fog == 0.0, "legacy use_environment_fog")
		assert(clouds.atmosphere_color.is_equal_approx(LEGACY_ATMOSPHERE), "legacy atmosphere_color")
		assert(clouds.sampled_environment_fog_color.is_equal_approx(LEGACY_SAMPLED), "legacy sampled_environment_fog_color")

func restore_production() -> void:
	dome.ground_color = prod_ground
	dome.cirrus_visible = prod_cirrus
	dome.cumulus_visible = prod_cumulus
	clouds.atmosphere_color = prod_atmosphere
	clouds.sampled_environment_fog_color = prod_sampled_fog
	clouds.use_environment_fog = prod_use_env
	driver.ambience_sample_environment = prod_ambience
