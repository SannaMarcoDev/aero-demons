@tool
class_name CloudAtmosphere
extends CompositorEffect

## Aerial perspective on opaque geometry, sharing CloudSystem's air settings.
## Runs after the sky, before transparents: particles and trails stay unveiled.
## With an active CloudShadowPass the haze is shadowed by the clouds too.

const SHADER_SRC := "res://addons/clouds/atmosphere.glsl"

var source: CloudSystem
## Render-thread read. Null or inactive: the air is lit as if the sky were clear.
var shadows: CloudShadowPass
var rd: RenderingDevice
var _shader: RID
var _pipeline: RID
var _ubo: RID
var _sampler: RID
var _shadow_sampler: RID
var _no_shadow: RID
var _frame := 0


func _init() -> void:
	effect_callback_type = EFFECT_CALLBACK_TYPE_POST_SKY
	rd = RenderingServer.get_rendering_device()
	if rd == null:
		return
	_shader = CloudSystem._compile_compute_dev(rd, SHADER_SRC)
	if _shader.is_valid():
		_pipeline = rd.compute_pipeline_create(_shader)
	_ubo = rd.uniform_buffer_create(256)
	_sampler = rd.sampler_create(RDSamplerState.new())
	var state := RDSamplerState.new()
	state.min_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	state.mag_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	state.mip_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	state.repeat_u = RenderingDevice.SAMPLER_REPEAT_MODE_REPEAT
	state.repeat_v = RenderingDevice.SAMPLER_REPEAT_MODE_REPEAT
	_shadow_sampler = rd.sampler_create(state)
	# Valid binding while the shadow cache is absent; pc.frame.y ignores it.
	var format := RDTextureFormat.new()
	format.texture_type = RenderingDevice.TEXTURE_TYPE_2D_ARRAY
	format.format = RenderingDevice.DATA_FORMAT_R8_UNORM
	format.width = 1
	format.height = 1
	format.usage_bits = RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
	_no_shadow = rd.texture_create(format, RDTextureView.new(), [PackedByteArray([255])])


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and rd != null:
		for rid in [_pipeline, _shader, _ubo, _sampler, _shadow_sampler, _no_shadow]:
			if rid.is_valid():
				rd.free_rid(rid)


func _render_callback(cb_type: int, render_data: RenderData) -> void:
	if cb_type != EFFECT_CALLBACK_TYPE_POST_SKY or source == null or not _pipeline.is_valid() \
			or not source.atmosphere_enabled:
		return
	var sb := render_data.get_render_scene_buffers() as RenderSceneBuffersRD
	var sd := render_data.get_render_scene_data()
	if sb == null or sd == null:
		return
	var size := sb.get_internal_size()
	if size.x <= 0 or size.y <= 0:
		return
	var lighting := source.sun_lighting()
	var bytes := source._pack_ubo(sd.get_cam_transform(), sd.get_cam_projection().inverse(),
		lighting[0], lighting[1]).to_byte_array()
	rd.buffer_update(_ubo, 0, bytes.size(), bytes)
	# The pass refreshes its cache before frame rendering, on this same thread.
	var pass_ := shadows # main thread may swap it; read once
	var shadow_live := pass_ != null and pass_._active and pass_._volume.is_valid()
	_frame = (_frame + 1) % 1024
	var frame := PackedFloat32Array([float(_frame), 1.0 if shadow_live else 0.0, 0.0, 0.0]).to_byte_array()
	for view in sb.get_view_count():
		var color := RDUniform.new()
		color.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
		color.binding = 0
		color.add_id(sb.get_color_layer(view))
		var depth := RDUniform.new()
		depth.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
		depth.binding = 1
		depth.add_id(_sampler)
		depth.add_id(sb.get_depth_layer(view))
		var params := RDUniform.new()
		params.uniform_type = RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER
		params.binding = 2
		params.add_id(_ubo)
		var shadow := RDUniform.new()
		shadow.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
		shadow.binding = 3
		shadow.add_id(_shadow_sampler)
		shadow.add_id(pass_._volume if shadow_live else _no_shadow)
		var bindings := UniformSetCacheRD.get_cache(_shader, 0, [color, depth, params, shadow])
		var list := rd.compute_list_begin()
		rd.compute_list_bind_compute_pipeline(list, _pipeline)
		rd.compute_list_bind_uniform_set(list, bindings, 0)
		rd.compute_list_set_push_constant(list, frame, frame.size())
		rd.compute_list_dispatch(list, (size.x + 7) / 8, (size.y + 7) / 8, 1)
		rd.compute_list_end()
