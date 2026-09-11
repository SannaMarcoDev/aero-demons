extends SceneTree
## Terrain texture review: runtime-only material + shader-override variants.
## Never saves scene/resources. Run:
## Godot --path . --script tools/terrain_texture_review.gd
## -- --check (headless OK), --view=<id>, --variant=<id>, --hold.
## --hold: Left/Right cycle views, Up/Down cycle variants, Esc quit.
## PNGs + manifest.json + generated/override shader go to
## res://subagent-artifacts/terrain-texture-review/<timestamp>/

const MAP := "res://scenes/maps/garda_final.tscn"
const OUT_ROOT := "res://subagent-artifacts/terrain-texture-review"
const SETTLE := 64
const PHASE := 12.0
const IDENTITY_MAE_GATE := 0.003
# Targets found by tools/terrain_view_probe.gd: steep mixed snow/rock/vegetation
# faces in region (-8,-8). Target y < 0 means "sample the ground at x/z".
const VIEWS := [
	{"id": "slope_close", "eye": Vector3(-120132.3, 2084.0, -114939.6),
		"target": Vector3(-120920.0, -1.0, -114800.0)},
	{"id": "slope_mid", "eye": Vector3(-117966.1, 2656.0, -115323.6),
		"target": Vector3(-120920.0, -1.0, -114800.0)},
	{"id": "valley_wide", "eye": Vector3(-114027.5, 3696.0, -116021.8),
		"target": Vector3(-121000.0, -1.0, -114300.0)},
]
# Phase-1 material-only variants, kept selectable via --variant.
const DEBUG_VARIANTS := [
	{"id": "dbg_control_texture", "props": {"show_control_texture": true}},
	{"id": "dbg_control_blend", "props": {"show_control_blend": true}},
	{"id": "dbg_colormap", "props": {"show_colormap": true}},
	{"id": "dbg_vertex_grid", "props": {"show_vertex_grid": true},
		"views": ["slope_close"]},
	{"id": "sharp_050", "params": {"blend_sharpness": 0.5}},
	{"id": "sharp_090", "params": {"blend_sharpness": 0.9}},
	{"id": "macro_var", "params": {"enable_macro_variation": true,
		"macro_variation1": Color(0.85, 0.88, 0.80),
		"macro_variation2": Color(1.15, 1.10, 1.05),
		"noise1_scale": 0.002, "noise2_scale": 0.01,
		"macro_variation_slope": 0.333}},
	{"id": "dual_scaling", "props": {"dual_scaling": true},
		"params": {"dual_scale_texture": 0, "dual_scale_reduction": 0.1,
			"dual_scale_far": 3000.0, "dual_scale_near": 500.0}},
	{"id": "nearest", "props": {"texture_filtering": 1}},
]
# Phase-2 shader-override variants: wc_blend_power / wc_warp_texels /
# wc_warp_scale / wc_colormap_strength. Default view set: close + mid.
const SLOPES := ["slope_close", "slope_mid"]
const OVERRIDE_VARIANTS := [
	{"id": "ov_identity", "override": true,
		"uniforms": {"wc_blend_power": 8.0, "wc_warp_texels": 0.0,
			"wc_warp_scale": 60.0, "wc_colormap_strength": 1.0}},
	{"id": "ov_power4", "override": true, "views": SLOPES,
		"uniforms": {"wc_blend_power": 4.0, "wc_warp_texels": 0.0,
			"wc_warp_scale": 60.0, "wc_colormap_strength": 1.0}},
	{"id": "ov_power2", "override": true, "views": SLOPES,
		"uniforms": {"wc_blend_power": 2.0, "wc_warp_texels": 0.0,
			"wc_warp_scale": 60.0, "wc_colormap_strength": 1.0}},
	{"id": "ov_warp035_s40", "override": true, "views": SLOPES,
		"uniforms": {"wc_blend_power": 8.0, "wc_warp_texels": 0.35,
			"wc_warp_scale": 40.0, "wc_colormap_strength": 1.0}},
	{"id": "ov_warp060_s60", "override": true, "views": SLOPES,
		"uniforms": {"wc_blend_power": 8.0, "wc_warp_texels": 0.6,
			"wc_warp_scale": 60.0, "wc_colormap_strength": 1.0}},
	{"id": "ov_warp060_s120", "override": true, "views": SLOPES,
		"uniforms": {"wc_blend_power": 8.0, "wc_warp_texels": 0.6,
			"wc_warp_scale": 120.0, "wc_colormap_strength": 1.0}},
	{"id": "ov_nocolor", "override": true, "views": SLOPES,
		"uniforms": {"wc_blend_power": 8.0, "wc_warp_texels": 0.0,
			"wc_warp_scale": 60.0, "wc_colormap_strength": 0.0}},
	{"id": "ov_halfcolor", "override": true, "views": SLOPES,
		"uniforms": {"wc_blend_power": 8.0, "wc_warp_texels": 0.0,
			"wc_warp_scale": 60.0, "wc_colormap_strength": 0.5}},
	{"id": "ov_combo_a", "override": true,
		"uniforms": {"wc_blend_power": 3.0, "wc_warp_texels": 0.5,
			"wc_warp_scale": 60.0, "wc_colormap_strength": 0.5}},
	{"id": "ov_combo_b", "override": true,
		"uniforms": {"wc_blend_power": 2.0, "wc_warp_texels": 0.7,
			"wc_warp_scale": 90.0, "wc_colormap_strength": 0.35}},
]
# Phase-3 default set: run on all three views.
const PHASE3_VARIANTS := [
	{"id": "ov_identity", "override": true,
		"uniforms": {"wc_blend_power": 8.0, "wc_warp_texels": 0.0,
			"wc_warp_scale": 60.0, "wc_colormap_strength": 1.0}},
	{"id": "ov_rec_a", "override": true,
		"uniforms": {"wc_blend_power": 8.0, "wc_warp_texels": 0.6,
			"wc_warp_scale": 60.0, "wc_colormap_strength": 1.0}},
	{"id": "ov_rec_b", "override": true,
		"uniforms": {"wc_blend_power": 6.0, "wc_warp_texels": 0.6,
			"wc_warp_scale": 60.0, "wc_colormap_strength": 0.75}},
	{"id": "ov_rec_c", "override": true,
		"uniforms": {"wc_blend_power": 6.0, "wc_warp_texels": 0.7,
			"wc_warp_scale": 80.0, "wc_colormap_strength": 0.75}},
	{"id": "ov_combo_a", "override": true,
		"uniforms": {"wc_blend_power": 3.0, "wc_warp_texels": 0.5,
			"wc_warp_scale": 60.0, "wc_colormap_strength": 0.5}},
]
const PROPS := ["show_control_texture", "show_control_blend", "show_colormap",
	"show_vertex_grid", "dual_scaling", "texture_filtering"]
const PARAMS := ["blend_sharpness", "enable_macro_variation", "macro_variation1",
	"macro_variation2", "noise1_scale", "noise2_scale", "macro_variation_slope",
	"dual_scale_texture", "dual_scale_reduction", "dual_scale_near",
	"dual_scale_far", "mipmap_bias", "depth_blur", "bias_distance",
	"enable_projection", "noise_texture"]
const OVERRIDE_UNIFORMS := ["wc_blend_power", "wc_warp_texels",
	"wc_warp_scale", "wc_colormap_strength"]
const SNIPPET_UNIFORMS := """
uniform float wc_blend_power : hint_range(0.5, 16.0) = 8.0;
uniform float wc_warp_texels : hint_range(0.0, 1.0) = 0.0;
uniform float wc_warp_scale : hint_range(5.0, 500.0) = 60.0;
uniform float wc_colormap_strength : hint_range(0.0, 1.0) = 1.0;
"""
const SNIPPET_WARP := """
	vec2 uv_c = uv;
	if (wc_warp_texels > 0.0) {
		vec2 wp = v_vertex.xz / wc_warp_scale;
		vec2 wn1 = vec2(texture(noise_texture, wp).r, texture(noise_texture, wp + vec2(0.37, 0.61)).r) - 0.5;
		vec2 wn2 = vec2(texture(noise_texture, wp * 5.0).r, texture(noise_texture, wp * 5.0 + vec2(0.23, 0.79)).r) - 0.5;
		uv_c += (wn1 + 0.35 * wn2) * 2.0 * wc_warp_texels;
	}
	vec2 c_index_id = floor(uv_c);
	vec2 c_weight = fract(uv_c);
	vec2 c_invert = 1.0 - c_weight;
	vec4 c_weights = vec4(c_invert.x * c_weight.y, c_weight.x * c_weight.y, c_weight.x * c_invert.y, c_invert.x * c_invert.y);
	ivec3 c_index[4];
	c_index[0] = get_index_coord(c_index_id + offsets.xy, FRAGMENT_PASS);
	c_index[1] = get_index_coord(c_index_id + offsets.yy, FRAGMENT_PASS);
	c_index[2] = get_index_coord(c_index_id + offsets.yx, FRAGMENT_PASS);
	c_index[3] = get_index_coord(c_index_id + offsets.xx, FRAGMENT_PASS);
"""
var map: Node3D
var camera: Camera3D
var terrain: Terrain3D
var material: Terrain3DMaterial
var driver: SunshineCloudsDriverGD
var override_shader: Shader
var originals := {}
var scene_override_active := false
var views: Array
var variants: Array
var view_index := 0
var variant_index := 0
var holding := false
var held_key := 0
var output: String
var manifest: Dictionary
var warnings: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func capture_timeout() -> void:
	if not holding:
		push_error("Terrain texture review did not finish within 600 seconds")
		quit(1)

func run() -> void:
	create_timer(600.0).timeout.connect(capture_timeout)
	var args := OS.get_cmdline_user_args()
	var check := "--check" in args
	views = VIEWS.duplicate(true)
	var all_variants: Array = [{"id": "baseline"}] + DEBUG_VARIANTS + OVERRIDE_VARIANTS + PHASE3_VARIANTS
	# Default run: baseline + phase-3 variants only.
	variants = all_variants.slice(0, 1) + PHASE3_VARIANTS.duplicate(true)
	for arg in args:
		if arg.begins_with("--view="):
			views = views.filter(func(view): return view.id == arg.trim_prefix("--view="))
			assert(not views.is_empty(), "Unknown view: " + arg)
		elif arg.begins_with("--variant="):
			var wanted := arg.trim_prefix("--variant=")
			variants = all_variants.filter(func(v): return v.id == wanted)
			assert(not variants.is_empty(), "Unknown variant: " + arg)
			variants = variants.duplicate(true)
		else:
			assert(arg in ["--check", "--hold"], "Unknown option: " + arg)
	assert(check or DisplayServer.get_name() != "headless", "Captures require graphical Forward+")
	root.size = Vector2i(1280, 720) if check else Vector2i(1920, 1080)
	root.content_scale_size = root.size
	map = load(MAP).instantiate()
	root.add_child(map)
	current_scene = map
	map.get_node("TutorialBoundaryController").set_physics_process(false)
	camera = Camera3D.new()
	camera.fov = 70.0
	camera.near = 2.0
	camera.far = 460000.0
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	map.add_child(camera)
	camera.make_current()
	terrain = map.get_node("GardaTerrain")
	terrain.set_camera(camera) # Read-only: only the viewing camera changes.
	material = terrain.material
	# Freeze atmosphere determinism: fixed clouds, static sky and sun.
	driver = map.get_node("SunshineCloudsDriverGD")
	var clouds: SunshineCloudsGD = driver.clouds_resource
	driver.set_process(false)
	driver.update_continuously = false
	var dome = map.get_node("Sky3D/SkyDome")
	dome.process_method = dome.MANUAL
	clouds.current_time = PHASE
	# Disabled for all captures so high-altitude views are never occluded and
	# every variant compares against the same unobstructed terrain.
	clouds.enabled = false
	# Resolve target heights and snapshot the pristine material state.
	for view in views:
		if view.target.y < 0.0:
			view.target.y = terrain.data.get_height(view.target)
		assert(view.eye.is_finite() and view.target.is_finite())
		view["ground_eye"] = terrain.data.get_height(view.eye)
		view["ground_target"] = view.target.y
		view["normal_target"] = terrain.data.get_normal(view.target)
		print("View ", view.id, ": eye=", view.eye, " ground=", view.ground_eye,
			" target=", view.target, " normal=", view.normal_target)
	for prop in PROPS:
		originals[prop] = material.get(prop)
	for param in PARAMS:
		originals[param] = material.get_shader_param(param)
	originals["shader_override"] = material.shader_override
	originals["shader_override_enabled"] = material.shader_override_enabled
	scene_override_active = originals["shader_override"] != null
	for uniform_name in OVERRIDE_UNIFORMS:
		var value = material.get_shader_param(uniform_name)
		if value == null and scene_override_active:
			# Unset params render at the shader's declared default; record that
			# so restores don't leave stale values from earlier variants.
			value = _shader_default(originals["shader_override"], uniform_name)
		originals[uniform_name] = value
	if scene_override_active:
		print("Scene override active: ", originals["shader_override"],
			" — baseline is the scene's shared patched shader; ov_rec_b parity gate applies")
	else:
		print("No scene shader override — ov_identity identity gate applies")
	print("Original material: props=", originals)
	if check:
		for view in views:
			place_view(view)
		holding = true
		for key in [KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN]:
			var event := InputEventKey.new()
			event.keycode = key
			event.pressed = true
			Input.parse_input_event(event)
			Input.flush_buffered_events()
			_process(0.0)
			event = event.duplicate()
			event.pressed = false
			Input.parse_input_event(event)
			Input.flush_buffered_events()
			_process(0.0)
		holding = false
		place_view(views[0])
		var generated := await generate_shader_code()
		if generated.is_empty():
			warnings.append("Headless run: generated shader code unavailable; override replacements untested")
		else:
			var patched := make_override_code(generated)
			assert(not patched.is_empty())
			override_shader = Shader.new()
			override_shader.code = patched
			print("Override patch applied headless: ", patched.count("\n"), " lines")
		for variant in variants:
			if variant.has("views") and not views[0].id in variant.views:
				continue
			apply_variant(variant)
		apply_variant({"id": "baseline"})
		print("PASS: ", views.size(), " finite views, ", variants.size(),
			" variants applied, viewer keys OK, warnings=", warnings)
		await finish()
		return
	output = ProjectSettings.globalize_path(OUT_ROOT + "/" +
		Time.get_datetime_string_from_system().replace(":", "-"))
	assert(DirAccess.make_dir_recursive_absolute(output) == OK)
	manifest = {"map": MAP, "godot": Engine.get_version_info().string,
		"output": output, "renderer": RenderingServer.get_current_rendering_method(),
		"size": root.size, "gpu": RenderingServer.get_video_adapter_name(),
		"settle_frames": SETTLE, "vertex_spacing": terrain.vertex_spacing,
		"clouds": "disabled (SunshineClouds compositor off, fixed time %.1f)" % PHASE,
		"identity_mae_gate": IDENTITY_MAE_GATE,
		"scene_override_active": scene_override_active,
		"views": views, "originals": originals, "captures": [], "warnings": warnings}
	place_view(views[0])
	for frame in 120:
		await RenderingServer.frame_post_draw
	# Build the runtime shader override from the generated code.
	var generated := await generate_shader_code()
	assert(not generated.is_empty(), "Generated shader code unavailable")
	var gen_file := FileAccess.open(output.path_join("generated_terrain_shader.gdshader"), FileAccess.WRITE)
	gen_file.store_string(generated)
	gen_file.close()
	var patched := make_override_code(generated)
	var patch_file := FileAccess.open(output.path_join("override_terrain_shader.gdshader.txt"), FileAccess.WRITE)
	assert(patch_file != null)
	patch_file.store_string(patched)
	patch_file.close()
	manifest["generated_shader"] = "generated_terrain_shader.gdshader"
	manifest["override_shader"] = "override_terrain_shader.gdshader.txt"
	override_shader = Shader.new()
	override_shader.code = patched
	print("Override shader built: ", patched.count("\n") + 1, " lines")
	for view in views:
		place_view(view)
		var baseline: Image
		for variant in variants:
			if variant.has("views") and not view.id in variant.views:
				continue
			apply_variant(variant)
			var t0 := Time.get_ticks_usec()
			var fps_sum := 0.0
			for frame in SETTLE:
				await RenderingServer.frame_post_draw
				fps_sum += Engine.get_frames_per_second()
			var settle_us := Time.get_ticks_usec() - t0
			var image := save_capture(view.id + "_" + variant.id, variant)
			manifest.captures[-1]["settle_us"] = settle_us
			manifest.captures[-1]["avg_frame_ms"] = settle_us / 1000.0 / SETTLE
			manifest.captures[-1]["avg_fps"] = fps_sum / SETTLE
			if variant.id == "baseline":
				baseline = image
				continue
			var mae := mean_difference(baseline, image)
			manifest.captures[-1]["mae_vs_baseline"] = mae
			print(view.id, "/", variant.id, " MAE vs baseline=", mae,
				" frame=", "%.2f" % (settle_us / 1000.0 / SETTLE), "ms")
			if mae < 0.0005:
				warnings.append(view.id + "/" + variant.id + " nearly identical to baseline (MAE %.6f)" % mae)
			if variant.id == "ov_identity" and not scene_override_active and mae >= IDENTITY_MAE_GATE:
				write_manifest()
				push_error("ov_identity diverges from baseline (MAE %.6f >= %.3f): override does not reproduce the built-in shader" % [mae, IDENTITY_MAE_GATE])
				quit(1)
				return
			# Parity gate: with the scene's shared patched shader as baseline,
			# ov_rec_b (runtime patch + rec_b uniforms) must reproduce it.
			if variant.id == "ov_rec_b" and scene_override_active and mae >= IDENTITY_MAE_GATE:
				write_manifest()
				push_error("ov_rec_b diverges from baseline (MAE %.6f >= %.3f): scene's shared shader does not match the tested runtime patch" % [mae, IDENTITY_MAE_GATE])
				quit(1)
				return
			if view.id in ["slope_close", "slope_mid"]:
				var sheet := make_sheet(baseline, image)
				var name: String = "sheet_" + view.id + "_" + variant.id + ".png"
				assert(sheet.save_png(output.path_join(name)) == OK)
				manifest.captures[-1]["sheet"] = name
		write_manifest()
	apply_variant({"id": "baseline"})
	write_manifest()
	print("PASS: terrain texture captures saved: ", output)
	if "--hold" in args:
		holding = true
		place_view(views[0])
		apply_variant(variants[0])
		print("Viewer: Left/Right views, Up/Down variants, Esc quit")
	else:
		await finish()

func place_view(view: Dictionary) -> void:
	view_index = views.find(view)
	camera.global_position = view.eye
	camera.look_at(view.target)
	camera.force_update_transform()
	assert(is_finite(view.ground_eye) and view.eye.y > view.ground_eye + 50.0,
		"Camera must stay 50 m above ground: " + view.id)
	assert(camera.is_current() and camera.global_transform.is_finite())
	assert(camera.is_position_in_frustum(view.target), "Target outside frustum: " + view.id)
	root.title = "Terrain review / " + view.id

func apply_variant(variant: Dictionary) -> void:
	variant_index = maxi(0, variants.find(variant))
	material.shader_override_enabled = false
	material.shader_override = null
	for prop in PROPS:
		material.set(prop, originals[prop])
	for param in PARAMS:
		material.set_shader_param(param, originals[param])
	if variant.get("override", false):
		# Assign before enabling: enabling with an empty slot makes Terrain3D
		# copy the generated shader into it.
		material.shader_override = override_shader
		material.shader_override_enabled = true
	else:
		# Non-override variants (incl. baseline) keep the scene's own override
		# state: the shared patched shader when the scene carries one, or the
		# built-in generated shader when it does not.
		material.shader_override = originals.get("shader_override")
		material.shader_override_enabled = originals.get("shader_override_enabled", false)
	# Restore the scene's wc_* uniform values so baseline renders identically
	# across views regardless of which override variant ran before; override
	# variants then set theirs explicitly below.
	for uniform_name in OVERRIDE_UNIFORMS:
		if originals.get(uniform_name) != null:
			material.set_shader_param(uniform_name, originals[uniform_name])
	if variant.get("override", false):
		for uniform_name in variant.uniforms:
			material.set_shader_param(uniform_name, variant.uniforms[uniform_name])
	for prop in variant.get("props", {}):
		material.set(prop, variant.props[prop])
	for param in variant.get("params", {}):
		material.set_shader_param(param, variant.params[param])
	var actual := {}
	for prop in PROPS:
		actual[prop] = material.get(prop)
	for param in PARAMS:
		actual[param] = material.get_shader_param(param)
	for uniform_name in variant.get("uniforms", {}):
		var value = material.get_shader_param(uniform_name)
		actual[uniform_name] = value
		if value == null or not _same(value, variant.uniforms[uniform_name]):
			warnings.append(variant.id + ": uniform " + uniform_name + " read back " + str(value))
	print("Variant ", variant.id, " applied")
	if manifest.has("captures"):
		manifest["variant_" + variant.id + "_actual"] = actual
	root.title = "Terrain review / " + views[view_index].id + " / " + variant.id

# Lets Terrain3D generate its shader, reads the code, restores the override
# state to clean (disabled + null). Returns "" if generation did not run.
func generate_shader_code() -> String:
	material.shader_override = null
	material.shader_override_enabled = true
	for frame in 2:
		await process_frame
	var code := ""
	if material.shader_override != null:
		code = material.shader_override.code
	if code.is_empty() and material.get_shader_rid().is_valid():
		code = RenderingServer.shader_get_code(material.get_shader_rid())
	# Restore the scene's own override state (shared patched shader, or none).
	material.shader_override_enabled = false
	material.shader_override = originals.get("shader_override")
	material.shader_override_enabled = originals.get("shader_override_enabled", false)
	return code

func _swap(haystack: String, pattern: String, replacement: String) -> String:
	assert(haystack.count(pattern) == 1, "Pattern not unique in generated shader: " + pattern.left(60))
	return haystack.replace(pattern, replacement)

# Replaces index[/weights[ with c_index[/c_weights[ inside the slice bounded by
# the two markers. Word boundaries keep t_weights[/index_normal[ intact.
func _rewire_slice(code: String, start_marker: String, end_marker: String) -> String:
	assert(code.count(start_marker) == 1, "Slice start not unique: " + start_marker.left(50))
	var i0 := code.find(start_marker)
	var i1 := code.find(end_marker, i0)
	assert(i1 != -1, "Slice end not found: " + end_marker.left(50))
	i1 += end_marker.length()
	var slice := code.substr(i0, i1 - i0)
	var rx := RegEx.new()
	assert(rx.compile("\\bindex\\[") == OK)
	slice = rx.sub(slice, "c_index[", true)
	assert(rx.compile("\\bweights\\[") == OK)
	slice = rx.sub(slice, "c_weights[", true)
	return code.substr(0, i0) + slice + code.substr(i1)

func make_override_code(code: String) -> String:
	code = _swap(code,
		"render_mode blend_mix,depth_draw_opaque,cull_back,diffuse_burley,specular_schlick_ggx,skip_vertex_transform;",
		"render_mode blend_mix,depth_draw_opaque,cull_back,diffuse_burley,specular_schlick_ggx,skip_vertex_transform;\n" + SNIPPET_UNIFORMS)
	code = _swap(code, "float sharpness = fma(56., blend_sharpness, 8.);",
		"float sharpness = wc_blend_power * fma(7., blend_sharpness, 1.);")
	code = _swap(code, "bool bilerp = region_mip < 0.0 && region_uv.z > -1.;",
		"bool bilerp = region_mip < 0.0 && region_uv.z > -1.;\n" + SNIPPET_WARP)
	# Color map bilinear block.
	code = _rewire_slice(code, "vec4 col_map[4];",
		"color_map = col_map[3];\n\t\t#endif")
	# Control map fetch block.
	code = _rewire_slice(code, "// Get index control data", "control[3]);")
	# The four accumulate_material() calls.
	code = _rewire_slice(code,
		"accumulate_material(base_ddx, base_ddy, weights[3], index[3]",
		"h[0], mat);")
	# t_weights bilinear interpolation must follow the warped weights too.
	code = _swap(code, "weights_id_0 *= weights;", "weights_id_0 *= c_weights;")
	code = _swap(code, "weights_id_1 *= weights;", "weights_id_1 *= c_weights;")
	code = _swap(code, "ALBEDO = mat.albedo_height.rgb * color_map.rgb * macrov;",
		"ALBEDO = mat.albedo_height.rgb * mix(vec3(1.0), color_map.rgb, wc_colormap_strength) * macrov;")
	return code

func make_sheet(baseline: Image, variant: Image) -> Image:
	var half := Vector2i(960, 540)
	var b_small := baseline.duplicate() as Image
	var v_small := variant.duplicate() as Image
	b_small.resize(half.x, half.y, Image.INTERPOLATE_BILINEAR)
	v_small.resize(half.x, half.y, Image.INTERPOLATE_BILINEAR)
	var crop := Rect2i(960 - 240, 620 - 135, 480, 270)
	var b_zoom := baseline.get_region(crop)
	var v_zoom := variant.get_region(crop)
	b_zoom.resize(half.x, half.y, Image.INTERPOLATE_NEAREST)
	v_zoom.resize(half.x, half.y, Image.INTERPOLATE_NEAREST)
	var sheet := Image.create(root.size.x, root.size.y, false, baseline.get_format())
	sheet.blit_rect(b_small, Rect2i(Vector2i.ZERO, half), Vector2i.ZERO)
	sheet.blit_rect(v_small, Rect2i(Vector2i.ZERO, half), Vector2i(half.x, 0))
	sheet.blit_rect(b_zoom, Rect2i(Vector2i.ZERO, half), Vector2i(0, half.y))
	sheet.blit_rect(v_zoom, Rect2i(Vector2i.ZERO, half), Vector2i(half.x, half.y))
	return sheet

# Reads a scalar uniform's declared default ("uniform float name ... = V;")
# out of shader source. Returns null when absent — only used for our own
# wc_* uniforms in the shared patched shader.
func _shader_default(shader: Shader, uniform_name: String):
	if shader == null or shader.code.is_empty():
		return null
	var rx := RegEx.new()
	if rx.compile("uniform\\s+\\w+\\s+" + uniform_name + "\\b[^;=]*=\\s*([-+0-9.eE]+)") != OK:
		return null
	var m := rx.search(shader.code)
	if m == null:
		return null
	return m.get_string(1).to_float()

func _same(a, b) -> bool:
	if a is float or b is float:
		return is_equal_approx(float(a), float(b))
	return a == b

func save_capture(id: String, variant: Dictionary) -> Image:
	var image := root.get_texture().get_image()
	assert(image != null and not image.is_empty() and image.get_size() == root.size)
	assert(image.save_png(output.path_join(id + ".png")) == OK)
	manifest.captures.append({"file": id + ".png", "view": views[view_index].id,
		"variant": variant.id, "eye": views[view_index].eye,
		"target": views[view_index].target})
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
	for candidate in [KEY_ESCAPE, KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN]:
		if Input.is_key_pressed(candidate):
			key = candidate
			break
	if key != held_key:
		match key:
			KEY_ESCAPE:
				holding = false
				finish()
			KEY_LEFT, KEY_RIGHT:
				place_view(views[posmod(view_index + (1 if key == KEY_RIGHT else -1), views.size())])
			KEY_UP, KEY_DOWN:
				var step := 1 if key == KEY_DOWN else -1
				for i in variants.size():
					var candidate: Dictionary = variants[posmod(variant_index + step * (i + 1), variants.size())]
					if not candidate.has("views") or views[view_index].id in candidate.views:
						apply_variant(candidate)
						break
	held_key = key
	return false

func finish() -> void:
	material.shader_override_enabled = false
	material.shader_override = originals.get("shader_override")
	material.shader_override_enabled = originals.get("shader_override_enabled", false)
	for uniform_name in OVERRIDE_UNIFORMS:
		if originals.get(uniform_name) != null:
			material.set_shader_param(uniform_name, originals[uniform_name])
	for prop in PROPS:
		material.set(prop, originals[prop])
	for param in PARAMS:
		material.set_shader_param(param, originals[param])
	map.queue_free()
	for frame in 3:
		await process_frame
	quit()
