extends SceneTree
## Terrain anti-tiling review: runtime-only material + shader-override variants.
## Never saves scene/resources/terrain data. Run:
## Godot --path . --script tools/terrain_antitile_review.gd
## -- --check (headless OK), --view=<id>, --variant=<id>, --hold, --dump
## PNGs + manifest.json + generated/override shaders go to
## res://subagent-artifacts/terrain-antitile-review/<timestamp>/

const MAP := "res://scenes/maps/garda_final.tscn"
const OUT_ROOT := "res://subagent-artifacts/terrain-antitile-review"
const SETTLE := 48
const PHASE := 12.0
const IDENTITY_MAE_GATE := 0.003
# Same targets as tools/terrain_texture_review.gd (steep mixed faces).
const VIEWS := [
	{"id": "slope_close", "eye": Vector3(-120132.3, 2084.0, -114939.6),
		"target": Vector3(-120920.0, -1.0, -114800.0)},
	{"id": "slope_mid", "eye": Vector3(-117966.1, 2656.0, -115323.6),
		"target": Vector3(-120920.0, -1.0, -114800.0)},
	{"id": "valley_wide", "eye": Vector3(-114027.5, 3696.0, -116021.8),
		"target": Vector3(-121000.0, -1.0, -114300.0)},
	# ~350 m from the same steep face: seam/detail check at real range.
	{"id": "slope_near", "eye": Vector3(-120730.0, 2120.0, -114835.0),
		"target": Vector3(-120920.0, -1.0, -114800.0)},
]
# The scene shader's own wc_* defaults (build_terrain_override.gd rec_b).
const WC_SCENE := {"wc_blend_power": 6.0, "wc_warp_texels": 0.6,
	"wc_warp_scale": 60.0, "wc_colormap_strength": 0.75}
# No-op defaults for the new anti-tile uniforms (identity rendering).
const ANTITILE_NOOP := {"wc_detile_rot": 0.0, "wc_detile_shift": 0.0,
	"wc_uv_scale_mult": 1.0, "wc_uv_warp": 0.0, "wc_uv_warp_scale": 120.0,
	"wc_ms_amount": 0.0, "wc_ms_ratio": 2.4, "wc_ms_mask_scale": 300.0,
	"wc_ms_near": 0.0, "wc_ms_far": 1.0}
const VARIANTS := [
	{"id": "baseline"},
	# --- asset/material-only variants on the scene shader ---
	{"id": "detile_a", "tex": {"detile_rot": 0.15, "detile_shift": 0.5}},
	{"id": "detile_b", "tex": {"detile_rot": 0.4, "detile_shift": 1.0}},
	{"id": "uvscale_050", "tex": {"uv_mult": 0.5}},
	{"id": "uvscale_025", "tex": {"uv_mult": 0.25}},
	{"id": "macro_var", "params": {"enable_macro_variation": true,
		"macro_variation1": Color(0.85, 0.88, 0.80),
		"macro_variation2": Color(1.15, 1.10, 1.05),
		"noise1_scale": 0.002, "noise2_scale": 0.01}},
	{"id": "blur_far", "params": {"depth_blur": 14.0, "bias_distance": 700.0}},
	{"id": "dual_prop", "props": {"dual_scaling": true},
		"params": {"dual_scale_texture": 0, "dual_scale_reduction": 0.1,
			"dual_scale_far": 3000.0, "dual_scale_near": 500.0}},
	# --- patched override shader variants ---
	{"id": "ov_identity", "override": true},
	{"id": "ov_detile", "override": true,
		"uniforms": {"wc_detile_rot": 0.15, "wc_detile_shift": 0.5}},
	{"id": "ov_detile_strong", "override": true,
		"uniforms": {"wc_detile_rot": 0.4, "wc_detile_shift": 1.0}},
	{"id": "ov_warp2", "override": true,
		"uniforms": {"wc_uv_warp": 2.0, "wc_uv_warp_scale": 90.0}},
	{"id": "ov_warp5", "override": true,
		"uniforms": {"wc_uv_warp": 5.0, "wc_uv_warp_scale": 90.0}},
	{"id": "ov_warp5_s300", "override": true,
		"uniforms": {"wc_uv_warp": 5.0, "wc_uv_warp_scale": 300.0}},
	{"id": "ov_ms_fine", "override": true,
		"uniforms": {"wc_ms_amount": 0.7, "wc_ms_ratio": 2.4,
			"wc_ms_mask_scale": 300.0}},
	{"id": "ov_ms_coarse", "override": true,
		"uniforms": {"wc_ms_amount": 0.7, "wc_ms_ratio": 0.4,
			"wc_ms_mask_scale": 300.0}},
	{"id": "ov_ms_far", "override": true,
		"uniforms": {"wc_ms_amount": 1.0, "wc_ms_ratio": 0.35,
			"wc_ms_mask_scale": 800.0, "wc_ms_near": 400.0,
			"wc_ms_far": 2500.0}},
	{"id": "ov_scale050", "override": true,
		"uniforms": {"wc_uv_scale_mult": 0.5}},
	{"id": "ov_wd", "override": true,
		"uniforms": {"wc_uv_warp": 3.0, "wc_uv_warp_scale": 90.0,
			"wc_detile_rot": 0.2, "wc_detile_shift": 0.5}},
	{"id": "ov_wmd", "override": true,
		"uniforms": {"wc_uv_warp": 3.0, "wc_uv_warp_scale": 90.0,
			"wc_ms_amount": 0.6, "wc_ms_ratio": 0.4,
			"wc_ms_mask_scale": 300.0, "wc_detile_rot": 0.15,
			"wc_detile_shift": 0.5}},
	{"id": "ov_ds", "override": true, "gen": "dual",
		"params": {"dual_scale_texture": 0, "dual_scale_reduction": 0.1,
			"dual_scale_far": 3000.0, "dual_scale_near": 500.0}},
]
const PROPS := ["show_control_texture", "show_control_blend", "show_colormap",
	"show_vertex_grid", "dual_scaling", "texture_filtering"]
const PARAMS := ["blend_sharpness", "enable_macro_variation", "macro_variation1",
	"macro_variation2", "noise1_scale", "noise2_scale", "macro_variation_slope",
	"dual_scale_texture", "dual_scale_reduction", "dual_scale_near",
	"dual_scale_far", "mipmap_bias", "depth_blur", "bias_distance",
	"enable_projection", "noise_texture"]
const SNIPPET_UNIFORMS := """
uniform float wc_blend_power : hint_range(0.5, 16.0) = 6.0;
uniform float wc_warp_texels : hint_range(0.0, 1.0) = 0.6;
uniform float wc_warp_scale : hint_range(5.0, 500.0) = 60.0;
uniform float wc_colormap_strength : hint_range(0.0, 1.0) = 0.75;
uniform float wc_detile_rot : hint_range(0.0, 1.0) = 0.0;
uniform float wc_detile_shift : hint_range(0.0, 1.0) = 0.0;
uniform float wc_uv_scale_mult : hint_range(0.05, 4.0) = 1.0;
uniform float wc_uv_warp : hint_range(0.0, 60.0) = 0.0;
uniform float wc_uv_warp_scale : hint_range(5.0, 4000.0) = 120.0;
uniform float wc_ms_amount : hint_range(0.0, 1.0) = 0.0;
uniform float wc_ms_ratio : hint_range(0.05, 8.0) = 2.4;
uniform float wc_ms_mask_scale : hint_range(5.0, 8000.0) = 300.0;
uniform float wc_ms_near : hint_range(0.0, 20000.0) = 0.0;
uniform float wc_ms_far : hint_range(1.0, 40000.0) = 1.0;
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
const SNIPPET_SAMPLES := """
		vec4 alb = textureGrad(_texture_array_albedo, vec3(id_uv, float(id)), id_dd.xy, id_dd.zw);
		vec4 nrm = textureGrad(_texture_array_normal, vec3(id_uv, float(id)), id_dd.xy, id_dd.zw);
"""
const SNIPPET_SAMPLES_NEW := """
		// wc anti-tile: continuous UV domain warp (world meters), no seams.
		if (wc_uv_warp > 0.0) {
			vec2 w_uv = v_vertex.xz / wc_uv_warp_scale;
			vec2 w_off = vec2(
				texture(noise_texture, w_uv).r,
				texture(noise_texture, w_uv * 1.7 + vec2(0.31, 0.77)).r) - 0.5;
			id_uv += w_off * (wc_uv_warp * id_scale);
		}
		vec4 alb = textureGrad(_texture_array_albedo, vec3(id_uv, float(id)), id_dd.xy, id_dd.zw);
		vec4 nrm = textureGrad(_texture_array_normal, vec3(id_uv, float(id)), id_dd.xy, id_dd.zw);
		// wc anti-tile: blend a second sample at an incommensurate scale.
		if (wc_ms_amount > 0.0) {
			float ms_m = texture(noise_texture, v_vertex.xz / wc_ms_mask_scale + vec2(0.53, 0.19)).r;
			float ms_w = wc_ms_amount * smoothstep(0.25, 0.75, ms_m)
				* smoothstep(wc_ms_near, wc_ms_far, v_vertex_xz_dist);
			vec2 ms_uv = id_uv * wc_ms_ratio;
			vec4 ms_alb = textureGrad(_texture_array_albedo, vec3(ms_uv, float(id)), id_dd.xy * wc_ms_ratio, id_dd.zw * wc_ms_ratio);
			vec4 ms_nrm = textureGrad(_texture_array_normal, vec3(ms_uv, float(id)), id_dd.xy * wc_ms_ratio, id_dd.zw * wc_ms_ratio);
			alb = mix(alb, ms_alb, ms_w);
			nrm = mix(nrm, ms_nrm, ms_w);
		}
"""
var map: Node3D
var camera: Camera3D
var terrain: Terrain3D
var material: Terrain3DMaterial
var driver: SunshineCloudsDriverGD
var override_shader: Shader
var override_shader_ds: Shader
var originals := {}
var tex_originals := {}
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
		push_error("Terrain antitile review did not finish within 600 seconds")
		quit(1)

func run() -> void:
	create_timer(600.0).timeout.connect(capture_timeout)
	var args := OS.get_cmdline_user_args()
	var check := "--check" in args
	var dump := "--dump" in args
	views = VIEWS.duplicate(true)
	variants = VARIANTS.duplicate(true)
	for arg in args:
		if arg.begins_with("--view="):
			var wanted_views := arg.trim_prefix("--view=").split(",")
			views = views.filter(func(view): return view.id in wanted_views)
			assert(not views.is_empty(), "Unknown view: " + arg)
		elif arg.begins_with("--variant="):
			var wanted := arg.trim_prefix("--variant=").split(",")
			variants = variants.filter(func(v): return v.id in wanted or v.id == "baseline")
			assert(variants.size() > 1, "Unknown variant: " + arg)
		else:
			assert(arg in ["--check", "--hold", "--dump"], "Unknown option: " + arg)
	assert(check or dump or DisplayServer.get_name() != "headless", "Captures require graphical Forward+")
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
	clouds.enabled = false
	for view in views:
		if view.target.y < 0.0:
			view.target.y = terrain.data.get_height(view.target)
		assert(view.eye.is_finite() and view.target.is_finite())
		view["ground_eye"] = terrain.data.get_height(view.eye)
		view["ground_target"] = view.target.y
		print("View ", view.id, ": eye=", view.eye, " ground=", view.ground_eye,
			" target=", view.target)
	for prop in PROPS:
		originals[prop] = material.get(prop)
	for param in PARAMS:
		originals[param] = material.get_shader_param(param)
	originals["shader_override"] = material.shader_override
	originals["shader_override_enabled"] = material.shader_override_enabled
	scene_override_active = originals["shader_override"] != null
	var wc_uniforms: Array = WC_SCENE.keys() + ANTITILE_NOOP.keys()
	for uniform_name in wc_uniforms:
		var value = material.get_shader_param(uniform_name)
		if value == null and scene_override_active:
			value = _shader_default(originals["shader_override"], uniform_name)
		originals[uniform_name] = value
	print("Original material: props=", originals)
	if check:
		for view in views:
			place_view(view)
		for variant in variants:
			apply_variant(variant)
		apply_variant({"id": "baseline"})
		var generated_check := await generate_shader_code(false)
		if generated_check.is_empty():
			warnings.append("Headless run: generated shader code unavailable; override patch untested")
		else:
			var patched_check := make_override_code(generated_check, true)
			assert(not patched_check.is_empty())
			print("Override patch applied headless: ", patched_check.count("\n"), " lines")
		print("PASS: ", views.size(), " finite views, ", variants.size(),
			" variants applied, warnings=", warnings)
		await finish()
		return
	output = ProjectSettings.globalize_path(OUT_ROOT + "/" +
		Time.get_datetime_string_from_system().replace(":", "-"))
	assert(DirAccess.make_dir_recursive_absolute(output) == OK)
	manifest = {"map": MAP, "godot": Engine.get_version_info().string,
		"output": output, "renderer": RenderingServer.get_current_rendering_method(),
		"size": root.size, "gpu": RenderingServer.get_video_adapter_name(),
		"settle_frames": SETTLE, "vertex_spacing": terrain.vertex_spacing,
		"identity_mae_gate": IDENTITY_MAE_GATE,
		"scene_override_active": scene_override_active,
		"views": views, "originals": originals, "captures": [], "warnings": warnings}
	place_view(views[0])
	for frame in 120:
		await RenderingServer.frame_post_draw
	# Build the runtime shader overrides from the generated code.
	var generated := await generate_shader_code(false)
	assert(not generated.is_empty(), "Generated shader code unavailable")
	var gen_file := FileAccess.open(output.path_join("generated_terrain_shader.gdshader"), FileAccess.WRITE)
	gen_file.store_string(generated)
	gen_file.close()
	var generated_ds := await generate_shader_code(true)
	if generated_ds.is_empty():
		warnings.append("dual_scaling generated code unavailable; ov_ds uses normal patch")
	else:
		var ds_file := FileAccess.open(output.path_join("generated_terrain_shader_dual.gdshader"), FileAccess.WRITE)
		ds_file.store_string(generated_ds)
		ds_file.close()
	var patched := make_override_code(generated, true)
	var patch_file := FileAccess.open(output.path_join("override_terrain_shader.gdshader.txt"), FileAccess.WRITE)
	assert(patch_file != null)
	patch_file.store_string(patched)
	patch_file.close()
	manifest["generated_shader"] = "generated_terrain_shader.gdshader"
	manifest["override_shader"] = "override_terrain_shader.gdshader.txt"
	override_shader = Shader.new()
	override_shader.code = patched
	if not generated_ds.is_empty():
		var patched_ds := make_override_code(generated_ds, false)
		override_shader_ds = Shader.new()
		override_shader_ds.code = patched_ds
		manifest["generated_shader_dual"] = "generated_terrain_shader_dual.gdshader"
	print("Override shader built: ", patched.count("\n") + 1, " lines")
	if dump:
		write_manifest()
		print("PASS: shader dumps saved: ", output)
		await finish()
		return
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
			if variant.id == "ov_identity" and mae >= IDENTITY_MAE_GATE:
				write_manifest()
				push_error("ov_identity diverges from baseline (MAE %.6f >= %.3f): patched shader does not reproduce the scene shader" % [mae, IDENTITY_MAE_GATE])
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
	print("PASS: terrain antitile captures saved: ", output)
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
	root.title = "Terrain antitile / " + view.id

func apply_tex(tex_cfg: Dictionary) -> void:
	var count: int = terrain.assets.get_texture_count()
	for i in count:
		var t: Terrain3DTextureAsset = terrain.assets.get_texture(i)
		if t == null:
			continue
		if not tex_originals.has(i):
			tex_originals[i] = {"uv_scale": t.uv_scale,
				"detiling_rotation": t.detiling_rotation,
				"detiling_shift": t.detiling_shift}
		var orig: Dictionary = tex_originals[i]
		t.set_uv_scale(orig.uv_scale * tex_cfg.get("uv_mult", 1.0))
		t.set_detiling_rotation(tex_cfg.get("detile_rot", orig.detiling_rotation))
		t.set_detiling_shift(tex_cfg.get("detile_shift", orig.detiling_shift))

func apply_variant(variant: Dictionary) -> void:
	variant_index = maxi(0, variants.find(variant))
	material.shader_override_enabled = false
	material.shader_override = null
	for prop in PROPS:
		material.set(prop, originals[prop])
	for param in PARAMS:
		material.set_shader_param(param, originals[param])
	apply_tex(variant.get("tex", {}))
	if variant.get("override", false):
		# Assign before enabling: enabling with an empty slot makes Terrain3D
		# copy the generated shader into it.
		var shader: Shader = override_shader
		if variant.get("gen", "") == "dual" and override_shader_ds != null:
			shader = override_shader_ds
		material.shader_override = shader
		material.shader_override_enabled = true
	else:
		material.shader_override = originals.get("shader_override")
		material.shader_override_enabled = originals.get("shader_override_enabled", false)
	# Non-override variants restore the scene shader's own uniform values
	# (the file's declared defaults). Override variants reset every wc_*
	# uniform to scene defaults + no-op antitile, then apply the variant's
	# explicit uniforms on top.
	var merged := {}
	if variant.get("override", false):
		merged = WC_SCENE.duplicate()
		merged.merge(ANTITILE_NOOP, true)
		merged.merge(variant.get("uniforms", {}), true)
	else:
		for uniform_name in WC_SCENE.keys() + ANTITILE_NOOP.keys():
			if originals.get(uniform_name) != null:
				merged[uniform_name] = originals[uniform_name]
	for uniform_name in merged:
		material.set_shader_param(uniform_name, merged[uniform_name])
	for prop in variant.get("props", {}):
		material.set(prop, variant.props[prop])
	for param in variant.get("params", {}):
		material.set_shader_param(param, variant.params[param])
	var actual := {}
	for uniform_name in merged:
		var value = material.get_shader_param(uniform_name)
		actual[uniform_name] = value
	print("Variant ", variant.id, " applied")
	if manifest.has("captures"):
		manifest["variant_" + variant.id + "_actual"] = actual
	root.title = "Terrain antitile / " + views[view_index].id + " / " + variant.id

# Lets Terrain3D generate its shader, reads the code, restores the override
# state to clean (disabled + null). Returns "" if generation did not run.
func generate_shader_code(dual: bool) -> String:
	material.shader_override = null
	material.set("dual_scaling", dual)
	material.shader_override_enabled = true
	for frame in 3:
		await process_frame
	var code := ""
	if material.shader_override != null:
		code = material.shader_override.code
	if code.is_empty() and material.get_shader_rid().is_valid():
		code = RenderingServer.shader_get_code(material.get_shader_rid())
	material.set("dual_scaling", originals.get("dual_scaling", false))
	material.shader_override_enabled = false
	material.shader_override = originals.get("shader_override")
	material.shader_override_enabled = originals.get("shader_override_enabled", false)
	return code

func _swap(haystack: String, pattern: String, replacement: String, strict := true) -> String:
	var count := haystack.count(pattern)
	if count != 1:
		if strict:
			assert(false, "Pattern count %d != 1 in generated shader: %s" % [count, pattern.left(60)])
		else:
			warnings.append("Patch pattern count %d, skipped: %s" % [count, pattern.left(60)])
		return haystack
	return haystack.replace(pattern, replacement)

func _swap_all(haystack: String, pattern: String, replacement: String, expected: int, strict := true) -> String:
	var count := haystack.count(pattern)
	if count != expected:
		if strict:
			assert(false, "Pattern count %d != %d in generated shader: %s" % [count, expected, pattern.left(60)])
		else:
			warnings.append("Patch pattern count %d != %d, skipped: %s" % [count, expected, pattern.left(60)])
		return haystack
	return haystack.replace(pattern, replacement)

# Replaces index[/weights[ with c_index[/c_weights[ inside the slice bounded by
# the two markers. Word boundaries keep t_weights[/index_normal[ intact.
func _rewire_slice(code: String, start_marker: String, end_marker: String, strict := true) -> String:
	if code.count(start_marker) != 1:
		if strict:
			assert(false, "Slice start not unique: " + start_marker.left(50))
		else:
			warnings.append("Slice start not unique, skipped: " + start_marker.left(50))
		return code
	var i0 := code.find(start_marker)
	var i1 := code.find(end_marker, i0)
	if i1 == -1:
		if strict:
			assert(false, "Slice end not found: " + end_marker.left(50))
		else:
			warnings.append("Slice end not found, skipped: " + end_marker.left(50))
		return code
	i1 += end_marker.length()
	var slice := code.substr(i0, i1 - i0)
	var rx := RegEx.new()
	assert(rx.compile("\\bindex\\[") == OK)
	slice = rx.sub(slice, "c_index[", true)
	assert(rx.compile("\\bweights\\[") == OK)
	slice = rx.sub(slice, "c_weights[", true)
	return code.substr(0, i0) + slice + code.substr(i1)

func make_override_code(code: String, strict: bool) -> String:
	code = _swap(code,
		"render_mode blend_mix,depth_draw_opaque,cull_back,diffuse_burley,specular_schlick_ggx,skip_vertex_transform;",
		"render_mode blend_mix,depth_draw_opaque,cull_back,diffuse_burley,specular_schlick_ggx,skip_vertex_transform;\n" + SNIPPET_UNIFORMS, strict)
	code = _swap(code, "float sharpness = fma(56., blend_sharpness, 8.);",
		"float sharpness = wc_blend_power * fma(7., blend_sharpness, 1.);", strict)
	code = _swap(code, "bool bilerp = region_mip < 0.0 && region_uv.z > -1.;",
		"bool bilerp = region_mip < 0.0 && region_uv.z > -1.;\n" + SNIPPET_WARP, strict)
	# Color map bilinear block.
	code = _rewire_slice(code, "vec4 col_map[4];",
		"color_map = col_map[3];\n\t\t#endif", strict)
	# Control map fetch block.
	code = _rewire_slice(code, "// Get index control data", "control[3]);", strict)
	# The four accumulate_material() calls.
	code = _rewire_slice(code,
		"accumulate_material(base_ddx, base_ddy, weights[3], index[3]",
		"h[0], mat);", strict)
	# t_weights bilinear interpolation must follow the warped weights too.
	code = _swap(code, "weights_id_0 *= weights;", "weights_id_0 *= c_weights;", strict)
	code = _swap(code, "weights_id_1 *= weights;", "weights_id_1 *= c_weights;", strict)
	code = _swap(code, "ALBEDO = mat.albedo_height.rgb * color_map.rgb * macrov;",
		"ALBEDO = mat.albedo_height.rgb * mix(vec3(1.0), color_map.rgb, wc_colormap_strength) * macrov;", strict)
	# --- anti-tile extensions ---
	# Global detile added on top of any per-texture detile (assets are 0 today).
	code = _swap_all(code, "_texture_detile_array[id]",
		"( _texture_detile_array[id] + vec2(wc_detile_rot, wc_detile_shift) )", 2, strict)
	# Global UV scale multiplier (bigger/smaller tiles).
	code = _swap_all(code, "float id_scale = _texture_uv_scale_array[id];",
		"float id_scale = _texture_uv_scale_array[id] * wc_uv_scale_mult;", 2, strict)
	# UV domain warp + multiscale blend around the texture samples.
	code = _swap_all(code, SNIPPET_SAMPLES.trim_prefix("\n"),
		SNIPPET_SAMPLES_NEW, 2, strict)
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
# out of shader source. Returns null when absent.
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
	var wc_uniforms: Array = WC_SCENE.keys() + ANTITILE_NOOP.keys()
	for uniform_name in wc_uniforms:
		if originals.get(uniform_name) != null:
			material.set_shader_param(uniform_name, originals[uniform_name])
	for prop in PROPS:
		material.set(prop, originals[prop])
	for param in PARAMS:
		material.set_shader_param(param, originals[param])
	apply_tex({})
	map.queue_free()
	for frame in 3:
		await process_frame
	quit()
