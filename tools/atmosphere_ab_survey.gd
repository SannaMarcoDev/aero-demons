extends SceneTree
## Read-only terrain survey. Runtime environment overrides only; no ResourceSaver.
## Godot --path . --script tools/atmosphere_ab_survey.gd --fixed-fps 30
## Headless setup/assertion check: add --headless and -- --check.
## B/C/B lower-sky color comparison: add -- --color-match (also works with --check).
## Endpoint sensitivity: -- --ground-probe; optional --no-scattering is a diagnostic control.
## Scattering regression: -- --scattering [--density=1.25]; B/B_repeat at all views.
## Tune candidates: -- --scattering --tune; 5 km/19.5 km oblique+horizon with B, G_black, G_white, U65, U100.
## After editing .comp includes: --headless --editor --script <this file> -- --reimport.
## PNGs and manifest: user://atmosphere_ab/<timestamp>/ (never overwrite a run).

const MAP := "res://scenes/maps/garda_final.tscn"
const SETTLE_FRAMES := 96
# Diagnostic lower-sky tint only; never saved to the scene or shared resources.
const CANDIDATE_GROUND := Color(0.4, 0.4, 0.4, 1.0)
# Tune-mode haze: both atmosphere_color and sampled_environment_fog_color are forced equal
# so use_environment_fog (coupled to atmosphere_simple_blend) becomes a pure blend-weight knob.
const HAZE_BLUE := Color(0.518, 0.553, 0.608, 1.0)
const CANDIDATE_GROUND_WHITE := Color.WHITE
var color_match := false
var ground_probe := false
var scattering_test := false
var tune_mode := false
var original_ground: Color
var original_atmosphere_color: Color
var original_sampled_fog_color: Color
var original_use_environment_fog: float
var original_cirrus_visible: bool
var original_cumulus_visible: bool
var map: Node3D
var camera: Camera3D
var driver: SunshineCloudsDriverGD
var dome: Node
var effectors: Array[SunshineCloudsEffector]
var frozen_clouds: Dictionary

func _initialize() -> void:
	call_deferred("reimport_shaders" if "--reimport" in OS.get_cmdline_user_args() else "survey")

func reimport_shaders() -> void:
	assert(Engine.is_editor_hint(), "--reimport requires --editor")
	var filesystem := EditorInterface.get_resource_filesystem()
	while filesystem.is_scanning():
		await process_frame
	var paths := PackedStringArray([
		"res://addons/SunshineClouds2/SunshineCloudsCompute.glsl",
		"res://addons/SunshineClouds2/SunshineCloudsPostCompute.glsl",
		"res://addons/SunshineClouds2/SunshineCloudsPostCompute.msaa.glsl"])
	filesystem.reimport_files(paths)
	for path in paths:
		var shader: RDShaderFile = load(path)
		assert(shader != null and shader.get_spirv().compile_error_compute.is_empty())
	print("PASS: reimported and compiled all three Sunshine compute entrypoints")
	quit()

func survey() -> void:
	var check := "--check" in OS.get_cmdline_user_args()
	scattering_test = "--scattering" in OS.get_cmdline_user_args()
	ground_probe = "--ground-probe" in OS.get_cmdline_user_args()
	color_match = ground_probe or "--color-match" in OS.get_cmdline_user_args()
	tune_mode = "--tune" in OS.get_cmdline_user_args()
	assert(not (scattering_test and color_match), "Use one survey mode per run")
	assert(not tune_mode or scattering_test, "--tune requires --scattering")
	if DisplayServer.get_name() == "headless" and not check:
		push_error("A/B screenshots require a graphical Forward+ renderer")
		quit(1)
		return
	seed(42137)
	map = load(MAP).instantiate()
	driver = map.get_node("SunshineCloudsDriverGD")
	# Freeze geometry/wind phase, not the renderer or its temporal convergence.
	driver.set_process(false)
	dome = map.get_node("Sky3D/SkyDome")
	original_ground = dome.ground_color
	original_cirrus_visible = dome.cirrus_visible
	original_cumulus_visible = dome.cumulus_visible
	dome.process_method = dome.MANUAL
	var boundary = map.get_node("TutorialBoundaryController")
	if not scattering_test:
		boundary.cloud_ring_count = 10 # Reconstruct historical A only for the legacy A/B/C tests.
	root.add_child(map)
	driver.set_process(false) # _ready can auto-enable a script's processing on tree entry.
	current_scene = map
	for i in 120:
		if boundary.get_return_distance() > 0.0:
			break
		await process_frame
	assert(boundary.get_return_distance() > 0.0, "Boundary must initialize before capturing baseline")
	boundary.set_physics_process(false) # No player in this diagnostic scene.
	var terrain = map.get_node("GardaTerrain")
	assert(terrain.data.get_region_locations().size() == 256)
	assert(is_equal_approx(terrain.vertex_spacing, 15.258789))
	assert(terrain.material.world_background == 0)
	assert(not map.get_node("Sky3D/TimeOfDay").game_time_enabled)
	effectors = driver.tracked_point_effectors.duplicate()
	assert(effectors.size() == (0 if scattering_test else 10))
	assert(not dome.fog_visible, "Production must not stack AtmFog over Sunshine")
	if not scattering_test:
		dome.fog_density = 0.00025
		dome.fog_start = 4000.0
		dome.fog_end = 5000.0
		dome.fog_falloff = 0.35
	var clouds := driver.clouds_resource
	assert(clouds.enabled or DisplayServer.get_name() == "headless", "Sunshine must render in graphical capture")
	if not scattering_test:
		clouds.atmospheric_density = 0.85 # Historical diagnostic, not the production preset.
	assert(is_equal_approx(clouds.fog_effect_ground, 1.0))
	var no_scattering := "--no-scattering" in OS.get_cmdline_user_args()
	assert(not no_scattering or ground_probe, "Disable scattering only in the explicit sensitivity control")
	if no_scattering:
		clouds.atmospheric_density = 0.0
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--density="):
			var value := argument.trim_prefix("--density=")
			assert(scattering_test and value.is_valid_float())
			assert(is_finite(value.to_float()) and value.to_float() >= 0.0 and value.to_float() <= 2.0)
			clouds.atmospheric_density = value.to_float()
	frozen_clouds = cloud_state()
	original_atmosphere_color = clouds.atmosphere_color
	original_sampled_fog_color = clouds.sampled_environment_fog_color
	original_use_environment_fog = clouds.use_environment_fog
	if tune_mode:
		# Driver copies Environment.fog_light_color into sampled_environment_fog_color when use_environment_fog > 0.
		# Null it so runtime color overrides stay frozen.
		driver.ambience_sample_environment = null
		print("Tune baseline: atmosphere_color=", original_atmosphere_color, " sampled_fog=", original_sampled_fog_color, " use_env=", original_use_environment_fog)
	camera = Camera3D.new()
	camera.fov = 70.0
	camera.near = 1.0
	camera.far = 100000.0
	root.add_child(camera)
	camera.make_current()
	terrain.set_camera(camera) # Viewer selection only; no terrain edits or saves.
	root.size = Vector2i(1280, 720)
	root.content_scale_size = root.size
	var views: Array[Dictionary] = []
	for altitude in [5000.0, 19500.0]:
		for view in ["oblique", "nadir", "horizon", "zenith"]:
			var direction := Vector3(0, -1, -1).normalized()
			if view == "nadir":
				direction = Vector3.DOWN
			elif view == "horizon":
				direction = Vector3.FORWARD
			elif view == "zenith":
				direction = Vector3.UP
			views.append({"name": "%05d_%s" % [int(altitude), view],
				"eye": Vector3(0, altitude, 0), "direction": direction})
	if ground_probe:
		views = [views[4], views[6]] # 19.5 km oblique/horizon: sensitivity, not a new look.
	if tune_mode:
		views = [views[4], views[6], views[0]] # 19.5 km oblique/horizon, 5 km oblique.
		print("Tune view set: ", views)
	for view in views:
		show_view(view)
		assert(camera.position.is_finite() and camera.global_basis.is_finite())
	if check:
		for variant in (["B", "C", "C_black", "C_white", "B", "A"] if color_match else ["A", "B", "A"]):
			apply_variant(variant)
		print("PASS: ", views.size(), " cameras, variant toggles, frozen Sunshine and read-only terrain setup; color_match=", color_match)
		quit()
		return
	var output := ProjectSettings.globalize_path("user://atmosphere_ab/" + Time.get_datetime_string_from_system().replace(":", "-") + "-" + str(OS.get_process_id()))
	assert(not DirAccess.dir_exists_absolute(output))
	assert(DirAccess.make_dir_recursive_absolute(output) == OK)
	var manifest := {"map": MAP, "output": output, "godot": Engine.get_version_info().string,
		"renderer": RenderingServer.get_current_rendering_method(), "size": root.size,
		"fov": camera.fov, "near": camera.near, "far": camera.far,
		"scaling_mode": root.scaling_3d_mode, "scaling_scale": root.scaling_3d_scale,
		"taa": root.use_taa, "msaa": root.msaa_3d, "settle_frames": SETTLE_FRAMES,
		"sun_transform": map.get_node("Sky3D/SunLight").global_transform,
		"sun_energy": map.get_node("Sky3D/SunLight").light_energy,
		"time_of_day": map.get_node("Sky3D/TimeOfDay").current_time,
		"bounds": boundary.get_terrain_bounds(), "regions": terrain.data.get_region_locations().size(),
		"cloud_state": frozen_clouds, "color_match": color_match,
		"original_ground": original_ground, "candidate_ground": CANDIDATE_GROUND,
		"ground_probe": ground_probe, "no_scattering_control": no_scattering,
		"scattering_test": scattering_test,
		"compute_sha256": FileAccess.get_sha256("res://addons/SunshineClouds2/SunshineCloudsCompute.glsl"),
		"post_compute_sha256": FileAccess.get_sha256("res://addons/SunshineClouds2/SunshineCloudsPostCompute.comp"),
		"tune_mode": tune_mode,
		"haze_blue": HAZE_BLUE,
		"captures": []}
	for view in views:
		show_view(view)
		# A/B repeats its first view; color tests repeat B in every view.
		var variants := ["A", "B", "A_repeat"] if view == views[0] else ["A", "B"]
		if color_match:
			variants = ["B", "C", "B_repeat"]
		if ground_probe:
			variants = ["B", "C_black", "C_white", "B_repeat"]
		if tune_mode:
			variants = ["B", "U0", "U35", "U65"]
		elif scattering_test:
			variants = ["B", "B_repeat"]
		for variant in variants:
			apply_variant(variant.trim_suffix("_repeat"))
			root.title = "Atmosphere survey — " + view.name + " / " + variant
			# ponytail: fixed 96-frame warmup; increase only if A_repeat shows history residue.
			for frame in SETTLE_FRAMES:
				await RenderingServer.frame_post_draw
			if not tune_mode:
				assert(cloud_state() == frozen_clouds, "Sunshine settings/phase changed during capture: " + str(cloud_state()) + " vs " + str(frozen_clouds))
			var image := root.get_texture().get_image()
			assert(image != null and not image.is_empty())
			assert(image.get_size() == Vector2i(1280, 720))
			var filename: String = view.name + "_" + variant + ".png"
			assert(image.save_png(output.path_join(filename)) == OK)
			manifest.captures.append({"file": filename, "view": view, "variant": variant,
				"fog_visible": dome.fog_visible, "fog_mesh_visible": dome.fog_mesh.visible,
				"ground_color": dome.ground_color,
				"cirrus_visible": dome.cirrus_visible, "cumulus_visible": dome.cumulus_visible,
				"use_environment_fog": clouds.use_environment_fog,
				"atmosphere_color": clouds.atmosphere_color,
				"sampled_environment_fog_color": clouds.sampled_environment_fog_color,
				"effectors": driver.tracked_point_effectors.size(),
				"uploaded_effector_vectors": clouds.point_effector_data.size()})
			print("Captured ", filename)
	apply_variant("B" if scattering_test or tune_mode else "A")
	var file := FileAccess.open(output.path_join("manifest.json"), FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify(manifest, "\t"))
	file.close()
	print("PASS: A/B survey saved: ", output)
	quit()

func show_view(view: Dictionary) -> void:
	camera.position = view.eye
	var direction: Vector3 = view.direction
	camera.look_at(camera.position + direction, Vector3.FORWARD if absf(direction.y) > 0.99 else Vector3.UP)

func apply_variant(variant: String) -> void:
	assert(variant in ["A", "B", "C", "C_black", "C_white", "G_black", "G_white", "U0", "U35", "U65", "U100"])
	# Reset Sunshine atmosphere blend/color to baseline before applying variant.
	var clouds := driver.clouds_resource
	clouds.use_environment_fog = original_use_environment_fog
	clouds.atmosphere_color = original_atmosphere_color
	clouds.sampled_environment_fog_color = original_sampled_fog_color
	dome.ground_color = CANDIDATE_GROUND if variant == "C" else original_ground
	dome.cirrus_visible = original_cirrus_visible
	dome.cumulus_visible = original_cumulus_visible
	if variant == "C_black" or variant == "G_black":
		dome.ground_color = Color.BLACK
	elif variant == "C_white" or variant == "G_white":
		dome.ground_color = Color.WHITE
	if tune_mode:
		# Supervisor batch 2: white ground, no SkyDome cirrus/cumulus, compare use_env blend weights.
		dome.ground_color = CANDIDATE_GROUND_WHITE
		dome.cirrus_visible = false
		dome.cumulus_visible = false
		if variant != "B":
			clouds.atmosphere_color = HAZE_BLUE
			clouds.sampled_environment_fog_color = HAZE_BLUE
		if variant == "U0":
			clouds.use_environment_fog = 0.0
		elif variant == "U35":
			clouds.use_environment_fog = 0.35
		elif variant == "U65":
			clouds.use_environment_fog = 0.65
		elif variant == "U100":
			clouds.use_environment_fog = 1.0
	assert(dome.sky_material.get_shader_parameter("ground_color").is_equal_approx(dome.ground_color))
	var enabled := variant == "A"
	map.get_node("Sky3D").fog_enabled = enabled
	dome.fog_visible = enabled
	var active_effectors: Array[SunshineCloudsEffector] = []
	if enabled:
		active_effectors.assign(effectors)
	driver.tracked_point_effectors = active_effectors
	driver.retrieve_texture_data()
	assert(dome.fog_mesh.visible == enabled)
	assert(driver.clouds_resource.point_effector_data.size() == (effectors.size() * 2 if enabled else 0))
	if not tune_mode:
		assert(cloud_state() == frozen_clouds, "A/B must not retune Sunshine")

func cloud_state() -> Dictionary:
	var clouds := driver.clouds_resource
	return {"enabled": clouds.enabled, "atmospheric_density": clouds.atmospheric_density,
		"fog_effect_ground": clouds.fog_effect_ground, "use_environment_fog": clouds.use_environment_fog,
		"atmosphere_color": clouds.atmosphere_color, "sampled_environment_fog_color": clouds.sampled_environment_fog_color,
		"current_time": clouds.current_time, "extra_large": clouds.extra_large_scale_clouds_position,
		"large": clouds.large_scale_clouds_position, "medium": clouds.medium_scale_clouds_position,
		"detail": clouds.detail_clouds_position, "lights": clouds.directional_lights_data.duplicate(),
		"floor": clouds.cloud_floor, "ceiling": clouds.cloud_ceiling}
