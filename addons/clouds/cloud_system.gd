@tool
class_name CloudSystem
extends CompositorEffect

## Volumetric cloud system: half-res compute raymarch + composite pass.
## Attach by assigning a Compositor containing this effect to the viewport.

const RAYMARCH_SRC := "res://addons/clouds/raymarch.glsl"
const COMPOSITE_SRC := "res://addons/clouds/composite.glsl"

@export var clouds_enabled := true
var sun: DirectionalLight3D
@export var deck_base := 2000.0
@export var deck_top := 15000.0 # Bake bounds, not a shared cloud-top altitude.
@export var deck_extent := 25000.0
@export var weather_world_m := 100000.0
@export var density_scale := 0.0035
@export var max_steps := 1024
@export var light_steps := 8
@export var coverage := 1.18
@export var preset: CloudNoiseGen.Preset = CloudNoiseGen.Preset.ORIGINAL

var rd: RenderingDevice
var _raymarch_shader: RID
var _composite_shader: RID
var _raymarch_pipe: RID
var _composite_pipe: RID
var _ubo: RID
var _sampler: RID
var _screen_sampler: RID
var _cloud_tex: RID
var _cloud_size := Vector2i.ZERO
var _noise3d: RID
var _weather: RID
var _weather_lo: RID
var _shape_tex: RID
var _light_tex: RID
var _field_sampler: RID
var _field_resources: Array[RID] = []
var _field_key: Array = []

# Opt-in point query; no probe resources or readbacks until requested.
var _density_shader: RID
var _density_pipe: RID
var _density_buffer: RID
var _density_busy := false # main thread; at most one outstanding readback
var _density_callback := Callable() # main thread; settled before teardown
var _density_request_id := 0
var _density_position := Vector3.ZERO # render-thread pending request
var _density_pending_id := 0

## Latest measured GPU cost of the cloud pass, in ms. -1 until resolved.
var gpu_ms := -1.0
var last_names := ""


func _init() -> void:
	effect_callback_type = EFFECT_CALLBACK_TYPE_POST_TRANSPARENT
	access_resolved_color = false
	access_resolved_depth = false
	needs_motion_vectors = false
	needs_normal_roughness = false
	rd = RenderingServer.get_rendering_device()
	if rd == null:
		push_error("CloudSystem: RenderingDevice unavailable (not Forward+?)")
		return
	_build_pipelines()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and rd != null:
		for rid in _field_resources:
			if rid.is_valid():
				rd.free_rid(rid)
		for rid in [_raymarch_pipe, _composite_pipe, _raymarch_shader,
				_composite_shader, _ubo, _sampler, _screen_sampler,
				_cloud_tex, _noise3d, _noise3d_lo, _weather, _weather_lo,
				_density_pipe, _density_shader, _density_buffer]:
			if rid.is_valid():
				rd.free_rid(rid)


static func _compile_compute_dev(dev: RenderingDevice, path: String) -> RID:
	# Exported GLSL resources contain imported SPIR-V, not the original text.
	# Keep source compilation in the editor/tests (including dense references).
	if not FileAccess.file_exists(path):
		var imported := load(path) as RDShaderFile
		if imported == null:
			push_error("CloudSystem: missing packaged compute shader: " + path)
			return RID()
		var compiled := imported.get_spirv()
		if compiled == null or not compiled.compile_error_compute.is_empty():
			push_error("CloudSystem: invalid imported compute shader: " + path)
			return RID()
		return dev.shader_create_from_spirv(compiled)
	var raw := FileAccess.get_file_as_string(path)
	# RDShaderSource has no resource-relative include resolver. Both the
	# light bake and camera compile this exact density definition.
	raw = raw.replace('#include "density.glslinc"',
			FileAccess.get_file_as_string("res://addons/clouds/density.glslinc"))
	var lines := raw.split("\n")
	var kept := PackedStringArray()
	for l in lines:
		if not l.strip_edges().begins_with("#["):
			kept.append(l)
	var src := RDShaderSource.new()
	src.source_compute = "\n".join(kept)
	var spirv := dev.shader_compile_spirv_from_source(src)
	var err := spirv.compile_error_compute
	if not err.is_empty():
		push_error("CloudSystem shader error in %s:\n%s" % [path, err])
		return RID()
	var shader := dev.shader_create_from_spirv(spirv)
	if not shader.is_valid():
		push_error("CloudSystem: shader_create failed for %s" % path)
	return shader


func _compile_compute(path: String) -> RID:
	return _compile_compute_dev(rd, path)


func _build_pipelines() -> void:
	_raymarch_shader = _compile_compute(RAYMARCH_SRC)
	_composite_shader = _compile_compute(COMPOSITE_SRC)
	if _raymarch_shader.is_valid():
		_raymarch_pipe = rd.compute_pipeline_create(_raymarch_shader)
	if _composite_shader.is_valid():
		_composite_pipe = rd.compute_pipeline_create(_composite_shader)

	_ubo = rd.uniform_buffer_create(256)

	var ss := RDSamplerState.new()
	ss.min_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	ss.mag_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	ss.mip_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	ss.repeat_u = RenderingDevice.SAMPLER_REPEAT_MODE_REPEAT
	ss.repeat_v = RenderingDevice.SAMPLER_REPEAT_MODE_REPEAT
	ss.repeat_w = RenderingDevice.SAMPLER_REPEAT_MODE_REPEAT
	_sampler = rd.sampler_create(ss)

	var scs := RDSamplerState.new()
	scs.min_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	scs.mag_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	scs.repeat_u = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
	scs.repeat_v = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
	scs.repeat_w = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
	_screen_sampler = rd.sampler_create(scs)

	# Placeholder textures until noise_gen wires real ones.
	_noise3d = _make_volume_tex(2)
	_noise3d_lo = _make_volume_tex(2)
	_weather = _make_flat_tex()
	_weather_lo = _make_flat_tex()


var _noise3d_lo: RID


## Swap in generated noise textures (called once at startup).
## noise3d_mips: Array of PackedByteArray mip levels — [0]=full res used
## near the camera, [2]=32³ downsampled used as smooth far-field density.
var _n3d_bytes := PackedByteArray()
var _noise_mip_count := 1
var _n3d_lo_bytes := PackedByteArray()
var _weather_bytes := PackedByteArray()
var _weather_mips: Array = []
var _weather_lo_bytes := PackedByteArray()


func set_noise_textures(noise3d_mips: Array, noise_size: int,
		weather_mips: Array, weather_size: int,
		weather_lo: PackedByteArray) -> void:
	if rd == null:
		return
	_n3d_bytes.clear()
	for level in noise3d_mips:
		_n3d_bytes.append_array(level)
	_noise_mip_count = noise3d_mips.size()
	_n3d_lo_bytes = noise3d_mips[2]
	_weather_bytes = weather_mips[0]
	_weather_mips = weather_mips
	_weather_lo_bytes = weather_lo
	for rid in [_noise3d, _noise3d_lo, _weather, _weather_lo]:
		if rid.is_valid():
			rd.free_rid(rid)
	_noise3d = _make_volume_tex(noise_size, _n3d_bytes, _noise_mip_count)
	_noise3d_lo = _make_volume_tex(noise_size / 4, noise3d_mips[2])
	var fmt := RDTextureFormat.new()
	fmt.format = RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM
	fmt.width = weather_size
	fmt.height = weather_size
	fmt.mipmaps = weather_mips.size()
	fmt.usage_bits = (RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
			| RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT)
	# RD wants one byte array per LAYER with all mips concatenated
	# inside it, not one array per mip.
	var wall := PackedByteArray()
	for level in weather_mips:
		wall.append_array(level)
	_weather = rd.texture_create(fmt, RDTextureView.new(), [wall])
	var lofmt := RDTextureFormat.new()
	lofmt.format = RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM
	lofmt.width = 128
	lofmt.height = 128
	lofmt.usage_bits = (RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
			| RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT)
	_weather_lo = rd.texture_create(lofmt, RDTextureView.new(), [weather_lo])


# Static 100 km field: 64 MiB contour/bound + 64 MiB optical depth. No light
# march per pixel. This runs at startup / parameter changes, not per frame.
# ponytail: sun edits rebake; amortize updates before animating the sun.
func _bake_field(dev: RenderingDevice, ubo: RID, sampler: RID, noise: RID,
		resources: Array[RID]) -> Array[RID]:
	var shape_shader := _compile_compute_dev(dev, "res://addons/clouds/bake_shape.glsl")
	var light_shader := _compile_compute_dev(dev, "res://addons/clouds/bake_light.glsl")
	if not shape_shader.is_valid() or not light_shader.is_valid():
		for shader in [shape_shader, light_shader]:
			if shader.is_valid():
				dev.free_rid(shader)
		return []
	var shape_pipe := dev.compute_pipeline_create(shape_shader)
	var light_pipe := dev.compute_pipeline_create(light_shader)
	resources.append_array([shape_pipe, light_pipe, shape_shader, light_shader])
	var textures: Array[RID] = []
	for channel in 2:
		var fmt := RDTextureFormat.new()
		fmt.texture_type = RenderingDevice.TEXTURE_TYPE_3D
		fmt.width = 512
		fmt.height = 64
		fmt.depth = 512
		fmt.format = RenderingDevice.DATA_FORMAT_R16G16_SFLOAT
		fmt.usage_bits = (RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
				| RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT)
		var texture := dev.texture_create(fmt, RDTextureView.new(), [])
		textures.append(texture)
		resources.append(texture)
	var cells := CloudNoiseGen.make_cloud_cells(deck_base, deck_top, coverage, _weather_bytes, preset).to_byte_array()
	var cell_buffer := dev.storage_buffer_create(cells.size(), cells)
	resources.append(cell_buffer)
	var field_state := RDSamplerState.new()
	field_state.min_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	field_state.mag_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	field_state.repeat_u = RenderingDevice.SAMPLER_REPEAT_MODE_REPEAT
	field_state.repeat_v = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
	field_state.repeat_w = RenderingDevice.SAMPLER_REPEAT_MODE_REPEAT
	var field_sampler := dev.sampler_create(field_state)
	resources.append(field_sampler)
	textures.append(field_sampler) # result: shape, light, vertically-clamped sampler
	var uniform := func(type: int, binding: int, ids: Array) -> RDUniform:
		var u := RDUniform.new()
		u.uniform_type = type
		u.binding = binding
		for id in ids:
			u.add_id(id)
		return u
	var ubo_u: RDUniform = uniform.call(RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER, 0, [ubo])
	var shape_set := dev.uniform_set_create([
		ubo_u, uniform.call(RenderingDevice.UNIFORM_TYPE_IMAGE, 1, [textures[0]]),
		uniform.call(RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, 2, [cell_buffer]),
		uniform.call(RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE, 3, [sampler, noise])], shape_shader, 0)
	var light_set := dev.uniform_set_create([
		ubo_u, uniform.call(RenderingDevice.UNIFORM_TYPE_IMAGE, 1, [textures[1]]),
		uniform.call(RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE, 2, [sampler, noise]),
		uniform.call(RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE, 5, [field_sampler, textures[0]])], light_shader, 0)
	if not shape_set.is_valid() or not light_set.is_valid():
		push_error("CloudSystem: field bake bindings failed")
		return []
	# Uniform sets are invalidated/freed with their shaders and textures.
	var cl := dev.compute_list_begin()
	dev.compute_list_bind_compute_pipeline(cl, shape_pipe)
	dev.compute_list_bind_uniform_set(cl, shape_set, 0)
	dev.compute_list_dispatch(cl, 64, 16, 64)
	dev.compute_list_add_barrier(cl)
	dev.compute_list_bind_compute_pipeline(cl, light_pipe)
	dev.compute_list_bind_uniform_set(cl, light_set, 0)
	dev.compute_list_dispatch(cl, 64, 16, 64)
	dev.compute_list_end()
	return textures


func _make_volume_tex(n: int, initial: PackedByteArray = PackedByteArray(),
		mip_count: int = 1) -> RID:
	var fmt := RDTextureFormat.new()
	fmt.format = RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM
	fmt.texture_type = RenderingDevice.TEXTURE_TYPE_3D
	fmt.width = n
	fmt.height = n
	fmt.depth = n
	fmt.mipmaps = mip_count
	fmt.usage_bits = (RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
			| RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT)
	var data := initial
	if data.is_empty():
		data = PackedByteArray()
		data.resize(n * n * n * 4)
		data.fill(255)
	return rd.texture_create(fmt, RDTextureView.new(), [data])


func _make_flat_tex() -> RID:
	var fmt := RDTextureFormat.new()
	fmt.format = RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM
	fmt.width = 2
	fmt.height = 2
	fmt.usage_bits = (RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
			| RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT)
	var data := PackedByteArray()
	data.resize(16)
	data.fill(255)
	return rd.texture_create(fmt, RDTextureView.new(), [data])


func _ensure_cloud_tex(size: Vector2i) -> void:
	var half := Vector2i(maxi(1, size.x / 2), maxi(1, size.y / 2))
	if half == _cloud_size and _cloud_tex.is_valid():
		return
	if _cloud_tex.is_valid():
		rd.free_rid(_cloud_tex)
	var fmt := RDTextureFormat.new()
	fmt.format = RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT
	fmt.width = half.x
	fmt.height = half.y
	fmt.usage_bits = (RenderingDevice.TEXTURE_USAGE_STORAGE_BIT
			| RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT)
	_cloud_tex = rd.texture_create(fmt, RDTextureView.new(), [])
	_cloud_size = half


func _pack_ubo(cam_xf: Transform3D, inv_proj: Projection,
		sun_dir: Vector3, sun_col: Vector3) -> PackedFloat32Array:
	var f := PackedFloat32Array()
	_basis_to_cols(cam_xf, f)
	f.append_array([
		inv_proj.x.x, inv_proj.x.y, inv_proj.x.z, inv_proj.x.w,
		inv_proj.y.x, inv_proj.y.y, inv_proj.y.z, inv_proj.y.w,
		inv_proj.z.x, inv_proj.z.y, inv_proj.z.z, inv_proj.z.w,
		inv_proj.w.x, inv_proj.w.y, inv_proj.w.z, inv_proj.w.w,
	])
	f.append_array([cam_xf.origin.x, cam_xf.origin.y, cam_xf.origin.z, 0.0])
	f.append_array([sun_dir.x, sun_dir.y, sun_dir.z, 0.0])
	f.append_array([sun_col.x, sun_col.y, sun_col.z, 0.0])
	f.append_array([deck_base, deck_top, 0.0, weather_world_m])
	f.append_array([density_scale, float(max_steps), float(light_steps), coverage])
	return f


static func _basis_to_cols(t: Transform3D, out: PackedFloat32Array) -> void:
	out.append_array([t.basis.x.x, t.basis.x.y, t.basis.x.z, 0.0])
	out.append_array([t.basis.y.x, t.basis.y.y, t.basis.y.z, 0.0])
	out.append_array([t.basis.z.x, t.basis.z.y, t.basis.z.z, 0.0])
	out.append_array([t.origin.x, t.origin.y, t.origin.z, 1.0])


func _render_callback(cb_type: int, render_data: RenderData) -> void:
	if cb_type != EFFECT_CALLBACK_TYPE_POST_TRANSPARENT:
		return
	if rd == null or not _raymarch_pipe.is_valid() or not _composite_pipe.is_valid():
		return

	var sb := render_data.get_render_scene_buffers() as RenderSceneBuffersRD
	var sd := render_data.get_render_scene_data()
	if sb == null or sd == null:
		return
	var size := sb.get_internal_size()
	if size.x <= 0 or size.y <= 0:
		return
	_ensure_cloud_tex(size)

	for view in sb.get_view_count():
		_render_view(sb, sd, view, size)


## Render thread only. Shared by the shadow cache and cloud rendering.
func ensure_field(sun_dir: Vector3) -> bool:
	var key := [deck_base, deck_top, density_scale, coverage, sun_dir, weather_world_m, preset]
	if key == _field_key:
		return true
	var bytes := _pack_ubo(Transform3D.IDENTITY, Projection(), sun_dir, Vector3.ONE).to_byte_array()
	rd.buffer_update(_ubo, 0, bytes.size(), bytes)
	for rid in _field_resources:
		rd.free_rid(rid)
	_field_resources.clear()
	_field_key.clear()
	var field := _bake_field(rd, _ubo, _sampler, _noise3d, _field_resources)
	if field.size() != 3:
		return false
	_shape_tex = field[0]
	_light_tex = field[1]
	_field_sampler = field[2]
	_field_key = key
	return true


func _render_view(sb: RenderSceneBuffersRD, sd: RenderSceneData,
		view: int, size: Vector2i) -> void:
	var color_rid: RID = sb.get_color_layer(view)
	var depth_rid: RID = sb.get_depth_layer(view)
	var cam_xf: Transform3D = sd.get_cam_transform()
	var proj: Projection = sd.get_cam_projection()
	var inv_proj := proj.inverse()
	var inv_view := cam_xf.affine_inverse()

	var sun_dir := Vector3(0.3, 0.7, 0.3).normalized()
	var sun_col := Vector3.ONE
	if is_instance_valid(sun):
		# DirectionalLight3D shines along -Z; the sun sits at +Z.
		sun_dir = sun.global_transform.basis.z.normalized()
		var linear_color := sun.light_color.srgb_to_linear()
		sun_col = Vector3(linear_color.r, linear_color.g, linear_color.b) * sun.light_energy

	if not clouds_enabled:
		_complete_pending_density()
		return
	var f := _pack_ubo(cam_xf, inv_proj, sun_dir, sun_col)
	var bytes := f.to_byte_array()
	if not ensure_field(sun_dir):
		_complete_pending_density()
		return
	# ensure_field may use this buffer for the bake; restore the camera data.
	rd.buffer_update(_ubo, 0, bytes.size(), bytes)

	var u_ubo := RDUniform.new()
	u_ubo.uniform_type = RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER
	u_ubo.binding = 0
	u_ubo.add_id(_ubo)
	var u_img := RDUniform.new()
	u_img.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u_img.binding = 1
	u_img.add_id(_cloud_tex)
	var u_noise := RDUniform.new()
	u_noise.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	u_noise.binding = 2
	u_noise.add_id(_sampler)
	u_noise.add_id(_noise3d)
	var u_weather := RDUniform.new()
	u_weather.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	u_weather.binding = 3
	u_weather.add_id(_sampler)
	u_weather.add_id(_weather)
	var u_depth := RDUniform.new()
	u_depth.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	u_depth.binding = 4
	u_depth.add_id(_screen_sampler)
	u_depth.add_id(depth_rid)
	var u_noise_lo := RDUniform.new()
	u_noise_lo.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	u_noise_lo.binding = 5
	u_noise_lo.add_id(_field_sampler)
	u_noise_lo.add_id(_shape_tex)
	var u_weather_lo := RDUniform.new()
	u_weather_lo.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	u_weather_lo.binding = 6
	u_weather_lo.add_id(_field_sampler)
	u_weather_lo.add_id(_light_tex)

	var rm_shader: RID = _raymarch_shader
	var rm_set := UniformSetCacheRD.get_cache(rm_shader, 0,
			[u_ubo, u_img, u_noise, u_weather, u_depth, u_noise_lo, u_weather_lo])

	rd.capture_timestamp("clouds_begin")
	var cl := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(cl, _raymarch_pipe)
	rd.compute_list_bind_uniform_set(cl, rm_set, 0)
	rd.compute_list_dispatch(cl,
			(_cloud_size.x + 7) / 8, (_cloud_size.y + 7) / 8, 1)
	rd.compute_list_add_barrier(cl)

	if clouds_enabled:
		var c_img := RDUniform.new()
		c_img.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
		c_img.binding = 0
		c_img.add_id(color_rid)
		var c_tex := RDUniform.new()
		c_tex.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
		c_tex.binding = 1
		c_tex.add_id(_screen_sampler)
		c_tex.add_id(_cloud_tex)
		var c_ubo := RDUniform.new()
		c_ubo.uniform_type = RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER
		c_ubo.binding = 2
		c_ubo.add_id(_ubo)
		var c_depth := RDUniform.new()
		c_depth.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
		c_depth.binding = 3
		c_depth.add_id(_screen_sampler)
		c_depth.add_id(depth_rid)
		var cp_shader: RID = _composite_shader
		var cp_set := UniformSetCacheRD.get_cache(cp_shader, 0,
				[c_img, c_tex, c_ubo, c_depth])
		rd.compute_list_bind_compute_pipeline(cl, _composite_pipe)
		rd.compute_list_bind_uniform_set(cl, cp_set, 0)
		rd.compute_list_dispatch(cl, (size.x + 7) / 8, (size.y + 7) / 8, 1)

	rd.compute_list_end()
	rd.capture_timestamp("clouds_end")
	if _density_pending_id != 0:
		_dispatch_density_sample([u_ubo, u_noise, u_noise_lo])


## Asynchronous local extinction (1/meters), using the exact rendered density.
## Call on the main thread. False = busy/unavailable/invalid; retry later.
## A rendered frame is required. Callback receives one float on the main thread.
func request_density(world_position: Vector3, callback: Callable) -> bool:
	if rd == null or not enabled or not _raymarch_pipe.is_valid() or not _composite_pipe.is_valid() \
			or _density_busy or not world_position.is_finite() or not callback.is_valid():
		return false
	_density_busy = true
	_density_callback = callback
	_density_request_id += 1
	RenderingServer.call_on_render_thread(_queue_density_sample.bind(world_position, _density_request_id))
	return true


func _queue_density_sample(world_position: Vector3, request_id: int) -> void:
	_density_position = world_position
	_density_pending_id = request_id


func cancel_density_sample() -> void:
	var callback := _density_callback
	_density_callback = Callable()
	_density_busy = false
	_density_request_id += 1 # Ignore an already dispatched readback.
	RenderingServer.call_on_render_thread(_complete_pending_density)
	if callback.is_valid():
		callback.call(0.0)


func _complete_pending_density() -> void:
	if _density_pending_id == 0:
		return
	_finish_density_sample.call_deferred(PackedByteArray(), _density_pending_id)
	_density_pending_id = 0


func _dispatch_density_sample(uniforms: Array[RDUniform]) -> void:
	if not _density_shader.is_valid():
		_density_shader = _compile_compute("res://addons/clouds/sample_density.glsl")
		if not _density_shader.is_valid():
			_complete_pending_density()
			return
		_density_pipe = rd.compute_pipeline_create(_density_shader)
		_density_buffer = rd.storage_buffer_create(4)
	var output := RDUniform.new()
	output.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	output.binding = 1
	output.add_id(_density_buffer)
	uniforms.append(output)
	var bindings := UniformSetCacheRD.get_cache(_density_shader, 0, uniforms)
	var point := PackedFloat32Array([
		_density_position.x, _density_position.y, _density_position.z, 0.0]).to_byte_array()
	var cl := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(cl, _density_pipe)
	rd.compute_list_bind_uniform_set(cl, bindings, 0)
	rd.compute_list_set_push_constant(cl, point, point.size())
	rd.compute_list_dispatch(cl, 1, 1, 1)
	rd.compute_list_end()
	var request_id := _density_pending_id
	_density_pending_id = 0
	# The RD may outlive this effect during shutdown. A capturing lambda would
	# retain the effect until after the renderer's uniform cache is destroyed.
	var error := rd.buffer_get_data_async(_density_buffer,
		_density_readback.bind(weakref(self), request_id))
	if error != OK:
		push_error("CloudSystem: density readback failed (%s)" % error)
		_finish_density_sample.call_deferred(PackedByteArray(), request_id)


static func _density_readback(data: PackedByteArray, target: WeakRef, request_id: int) -> void:
	var effect: CloudSystem = target.get_ref()
	if effect != null:
		effect._finish_density_sample.call_deferred(data, request_id)


func _finish_density_sample(data: PackedByteArray, request_id: int) -> void:
	if request_id != _density_request_id:
		return
	var callback := _density_callback
	_density_callback = Callable()
	_density_busy = false
	if callback.is_valid():
		callback.call(data.decode_float(0) if data.size() == 4 else 0.0)


## Poll the GPU timestamp pair captured last frame and update gpu_ms.
func poll_gpu_time() -> void:
	if rd == null:
		return
	var a := -1
	var b := -1
	var names := PackedStringArray()
	for i in rd.get_captured_timestamps_count():
		var n := rd.get_captured_timestamp_name(i)
		names.append("%s=%d" % [n, rd.get_captured_timestamp_gpu_time(i)])
		if n == "clouds_begin":
			a = i
		elif n == "clouds_end":
			b = i
	last_names = " | ".join(names)
	if a >= 0 and b >= 0:
		var t0 := rd.get_captured_timestamp_gpu_time(a)
		var t1 := rd.get_captured_timestamp_gpu_time(b)
		if t1 > t0:
			# Vulkan timestamps on Godot 4.7.2 are nanoseconds (verified
			# against wall time); /1000 reported 2000+ ms for a ~2 ms pass.
			gpu_ms = (t1 - t0) / 1000000.0


## Isolated replay cost on a local RenderingDevice: replays the real
## raymarch+composite dispatches in small submit+sync batches, so wall
## time includes CPU submit/sync overhead — an A/B comparison number,
## not a hardware GPU timestamp or live frame time. Returns
## [raymarch_ms, both_ms - raymarch_ms]. Empty on failure.
func bench_gpu(cam_xf: Transform3D, proj: Projection, size: Vector2i,
		iters := 60, raymarch_path: String = RAYMARCH_SRC) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	if iters <= 0 or size.x <= 0 or size.y <= 0:
		return out
	var lrd := RenderingServer.create_local_rendering_device()
	if lrd == null or _n3d_bytes.is_empty():
		push_error("CloudSystem.bench_gpu: local RD or noise data missing")
		if lrd != null:
			lrd.free()
		return out

	var rids: Array[RID] = []
	var shader := _compile_compute_dev(lrd, raymarch_path)
	var cshader := _compile_compute_dev(lrd, COMPOSITE_SRC)
	if not shader.is_valid() or not cshader.is_valid():
		for rid in [shader, cshader]:
			if rid.is_valid():
				lrd.free_rid(rid)
		lrd.free()
		return out
	# Pipelines and shaders are freed explicitly, before the textures.
	var rm_pipe := lrd.compute_pipeline_create(shader)
	var cp_pipe := lrd.compute_pipeline_create(cshader)
	rids.append_array([rm_pipe, cp_pipe, shader, cshader])

	var ubo := lrd.uniform_buffer_create(256)
	rids.append(ubo)
	var sun_dir := Vector3(0.3, 0.7, 0.3).normalized()
	var sun_col := Vector3.ONE
	if is_instance_valid(sun):
		sun_dir = sun.global_transform.basis.z.normalized()
		var linear_color := sun.light_color.srgb_to_linear()
		sun_col = Vector3(linear_color.r, linear_color.g, linear_color.b) * sun.light_energy
	var f := _pack_ubo(cam_xf, proj.inverse(), sun_dir, sun_col)
	var bytes := f.to_byte_array()
	lrd.buffer_update(ubo, 0, bytes.size(), bytes)

	var ss := RDSamplerState.new()
	ss.min_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	ss.mag_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	ss.mip_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	ss.repeat_u = RenderingDevice.SAMPLER_REPEAT_MODE_REPEAT
	ss.repeat_v = RenderingDevice.SAMPLER_REPEAT_MODE_REPEAT
	ss.repeat_w = RenderingDevice.SAMPLER_REPEAT_MODE_REPEAT
	var samp := lrd.sampler_create(ss)
	rids.append(samp)

	var scs := RDSamplerState.new()
	scs.min_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	scs.mag_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	scs.repeat_u = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
	scs.repeat_v = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
	scs.repeat_w = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
	var screen_samp := lrd.sampler_create(scs)
	rids.append(screen_samp)

	var mk_tex := func(w: int, h: int, d: int, usage: int,
			data: PackedByteArray, mip_count: int = 1) -> RID:
		var fmt := RDTextureFormat.new()
		if d > 1:
			fmt.texture_type = RenderingDevice.TEXTURE_TYPE_3D
			fmt.depth = d
		fmt.format = RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM
		fmt.width = w
		fmt.height = h
		fmt.mipmaps = mip_count
		fmt.usage_bits = usage
		var t := lrd.texture_create(fmt, RDTextureView.new(),
				[data] if not data.is_empty() else [])
		rids.append(t)
		return t
	var mk_f16 := func(w: int, h: int) -> RID:
		var fmt := RDTextureFormat.new()
		fmt.format = RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT
		fmt.width = w
		fmt.height = h
		fmt.usage_bits = (RenderingDevice.TEXTURE_USAGE_STORAGE_BIT
				| RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT)
		var t := lrd.texture_create(fmt, RDTextureView.new(), [])
		rids.append(t)
		return t

	var S := RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
	var half := Vector2i(maxi(1, size.x / 2), maxi(1, size.y / 2))
	var cloud_t: RID = mk_f16.call(half.x, half.y)
	var color_t: RID = mk_f16.call(size.x, size.y)
	var n3d: RID = mk_tex.call(128, 128, 128, S, _n3d_bytes, _noise_mip_count)
	var n3d_lo: RID = mk_tex.call(32, 32, 32, S, _n3d_lo_bytes)
	var w_fmt := RDTextureFormat.new()
	w_fmt.format = RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM
	w_fmt.width = 1024
	w_fmt.height = 1024
	w_fmt.mipmaps = _weather_mips.size()
	w_fmt.usage_bits = S
	var w_all := PackedByteArray()
	for level in _weather_mips:
		w_all.append_array(level)
	var w_t: RID = lrd.texture_create(w_fmt, RDTextureView.new(),
			[w_all])
	rids.append(w_t)
	var w_lo_t: RID = mk_tex.call(128, 128, 1, S, _weather_lo_bytes)
	var depth_t: RID = mk_tex.call(2, 2, 1, S,
			PackedByteArray([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]))

	var bake_start := Time.get_ticks_usec()
	var field := _bake_field(lrd, ubo, samp, n3d, rids)
	if field.size() != 3:
		for r in rids:
			lrd.free_rid(r)
		lrd.free()
		return out
	lrd.submit()
	lrd.sync() # exclude one-time generation from steady-state replay timing
	print("[field-build] compile+CPU+GPU-submit/sync=%.1fms" % ((Time.get_ticks_usec() - bake_start) / 1000.0))

	var rm_u: Array[RDUniform] = []
	var mk_u := func(arr: Array, utype: int, bind: int, ids: Array) -> void:
		var u := RDUniform.new()
		u.uniform_type = utype
		u.binding = bind
		for r in ids:
			u.add_id(r)
		arr.append(u)
	mk_u.call(rm_u, RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER, 0, [ubo])
	mk_u.call(rm_u, RenderingDevice.UNIFORM_TYPE_IMAGE, 1, [cloud_t])
	mk_u.call(rm_u, RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE, 2,
			[samp, n3d])
	mk_u.call(rm_u, RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE, 3,
			[samp, w_t])
	mk_u.call(rm_u, RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE, 4,
			[screen_samp, depth_t])
	mk_u.call(rm_u, RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE, 5,
			[field[2], field[0]])
	mk_u.call(rm_u, RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE, 6,
			[field[2], field[1]])
	var cp_u: Array[RDUniform] = []
	mk_u.call(cp_u, RenderingDevice.UNIFORM_TYPE_IMAGE, 0, [color_t])
	mk_u.call(cp_u, RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE, 1,
			[screen_samp, cloud_t])
	mk_u.call(cp_u, RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER, 2, [ubo])
	mk_u.call(cp_u, RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE, 3,
			[screen_samp, depth_t])

	var rm_set := lrd.uniform_set_create(rm_u, shader, 0)
	var cp_set := lrd.uniform_set_create(cp_u, cshader, 0)
	if not rm_set.is_valid() or not cp_set.is_valid():
		push_error("CloudSystem.bench_gpu: uniform_set_create failed")
		for r in rids:
			lrd.free_rid(r)
		lrd.free()
		return out

	var run_pass := func(with_composite: bool) -> void:
		var cl := lrd.compute_list_begin()
		lrd.compute_list_bind_compute_pipeline(cl, rm_pipe)
		lrd.compute_list_bind_uniform_set(cl, rm_set, 0)
		lrd.compute_list_dispatch(cl, (half.x + 7) / 8, (half.y + 7) / 8, 1)
		if with_composite:
			lrd.compute_list_add_barrier(cl)
			lrd.compute_list_bind_compute_pipeline(cl, cp_pipe)
			lrd.compute_list_bind_uniform_set(cl, cp_set, 0)
			lrd.compute_list_dispatch(cl, (size.x + 7) / 8, (size.y + 7) / 8, 1)
		lrd.compute_list_end()

	# Warmup, then two timed loops: raymarch alone, then the full pair.
	var measure := func(with_composite: bool, count: int) -> float:
		var elapsed_usec := 0
		var completed := 0
		while completed < count:
			var batch := mini(4, count - completed)
			var start_usec := Time.get_ticks_usec()
			for i in batch:
				run_pass.call(with_composite)
			lrd.submit()
			lrd.sync()
			elapsed_usec += Time.get_ticks_usec() - start_usec
			completed += batch
		return elapsed_usec / 1000.0 / count
	measure.call(true, 4)
	var rm_ms: float = measure.call(false, iters)
	var both_ms: float = measure.call(true, iters)
	for r in rids:
		lrd.free_rid(r)
	lrd.free()
	out.append_array([rm_ms, both_ms - rm_ms])
	return out
