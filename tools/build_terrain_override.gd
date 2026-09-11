extends SceneTree
## Builds res://resources/terrain/terrain_wc_override.gdshader: the shared
## patched Terrain3D shader (sharper index blending via wc_blend_power,
## index-domain warp via wc_warp_texels/wc_warp_scale, colormap strength via
## wc_colormap_strength) used by garda_final.tscn and the WC bridge.
## Patch recipe mirrors tools/terrain_texture_review.gd; uniform defaults here
## are the recommended "rec_b" values, so the scene look is the reviewed look.
## Run headless:
## Godot --headless --path . --script tools/build_terrain_override.gd

const OUT_DIR := "res://resources/terrain"
const OUT_PATH := OUT_DIR + "/terrain_wc_override.gdshader"
const SNIPPET_UNIFORMS := """
uniform float wc_blend_power : hint_range(0.5, 16.0) = 6.0;
uniform float wc_warp_texels : hint_range(0.0, 1.0) = 0.6;
uniform float wc_warp_scale : hint_range(5.0, 500.0) = 60.0;
uniform float wc_colormap_strength : hint_range(0.0, 1.0) = 0.75;
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

func _initialize() -> void:
	call_deferred("run")

func _fail(message: String, terrain: Terrain3D) -> void:
	push_error(message)
	if is_instance_valid(terrain):
		terrain.free()
	quit(1)

func run() -> void:
	var t := Terrain3D.new()
	root.add_child(t)
	var mat: Terrain3DMaterial = t.material
	if mat == null:
		mat = Terrain3DMaterial.new()
		t.material = mat
	# Match the garda_final material settings so the generated template is the
	# same one the review tool patches.
	mat.set_world_background(0)
	mat.set_shader_param("blend_sharpness", 0.0)
	mat.set_shader_param("enable_projection", true)
	mat.shader_override = null
	mat.shader_override_enabled = true
	for frame in 3:
		await process_frame
	var code := ""
	if mat.shader_override != null:
		code = mat.shader_override.code
	if code.is_empty() and mat.get_shader_rid().is_valid():
		code = RenderingServer.shader_get_code(mat.get_shader_rid())
	if code.is_empty():
		_fail("Terrain3D generated shader code unavailable", t)
		return
	if not code.begins_with("shader_type spatial;"):
		_fail("Generated code does not start with 'shader_type spatial;': " + code.left(80), t)
		return
	var patched := make_override_code(code)
	if patched.length() <= code.length():
		_fail("make_override_code produced no usable patch (see assert errors above)", t)
		return
	assert(DirAccess.make_dir_recursive_absolute(OUT_DIR) == OK)
	var f := FileAccess.open(OUT_PATH, FileAccess.WRITE)
	if f == null:
		_fail("Cannot write " + OUT_PATH + ": " + error_string(FileAccess.get_open_error()), t)
		return
	f.store_string(patched)
	f.close()
	# Verify what landed on disk (pure text read-back).
	var verify := FileAccess.open(OUT_PATH, FileAccess.READ)
	var text := verify.get_as_text()
	verify.close()
	for needle in ["wc_blend_power", "c_index[", "wc_colormap_strength"]:
		if not text.contains(needle):
			_fail("Written shader is missing '" + needle + "'", t)
			return
	var t3d_version = t.get("version")
	if t3d_version == null:
		t3d_version = _plugin_version()
	print("PASS: wrote ", OUT_PATH, " (", text.length(), " bytes, ",
		text.count("\n") + 1, " lines)",
		"" if t3d_version == null else " — Terrain3D " + str(t3d_version))
	root.remove_child(t)
	t.free()
	quit()

# Terrain3D exposes no version property in some releases; fall back to the
# plugin.cfg "version" field.
func _plugin_version():
	var cfg := FileAccess.open("res://addons/terrain_3d/plugin.cfg", FileAccess.READ)
	if cfg == null:
		return null
	for line in cfg.get_as_text().split("\n"):
		var l := line.strip_edges()
		if l.begins_with("version"):
			return l.get_slice("=", 1).strip_edges().trim_prefix("\"").trim_suffix("\"")
	return null

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
