@tool
class_name CloudShadowPass
extends RefCounted

## Opt-in render-thread sun transmission cache. No camera dependency or readbacks.
## Update BEFORE frame rendering, not inside a compositor callback: material
## descriptor sets must be refreshed before any opaque/shadow draw is prepared.
## One pass per layer; materials must not be shared between different layers.
var source: CloudSystem
var resolution := 512
var materials: Array[Resource] = []
var shadows_enabled := true
## Share of ambient light and reflections also removed in cloud shadows.
var ambient_dimming := 0.0
var bake_count := 0
var texture := Texture2DArrayRD.new()
var _shader: RID
var _pipeline: RID
var _mip_shader: RID
var _mip_pipeline: RID
var _volume: RID
var _key: Array = []
var _bound_materials: Array[Resource] = []
var _active := false
var _bound_ambient := -1.0


static func material_rid(material: Resource) -> RID:
	return material.get_material_rid() if material.has_method("get_material_rid") else material.get_rid()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and source != null and source.rd != null:
		# No callable retaining this effect during engine shutdown.
		RenderingServer.call_on_render_thread(_release.bind(source.rd, texture,
			[_pipeline, _shader, _mip_pipeline, _mip_shader, _volume], _bound_materials.duplicate()))


static func _release(rd: RenderingDevice, wrapper: Texture2DArrayRD, resources: Array, receivers: Array) -> void:
	for material in receivers:
		RenderingServer.material_set_param(material_rid(material), &"cloud_shadow_enabled", false)
		RenderingServer.material_set_param(material_rid(material), &"cloud_shadow_texture", null)
	wrapper.texture_rd_rid = RID()
	for rid in resources:
		if rid.is_valid():
			rd.free_rid(rid)


func _set_active(value: bool) -> void:
	if value == _active and _bound_materials == materials:
		return
	for material in _bound_materials:
		if not materials.has(material):
			RenderingServer.material_set_param(material_rid(material), &"cloud_shadow_enabled", false)
			RenderingServer.material_set_param(material_rid(material), &"cloud_shadow_texture", null)
	for material in materials:
		RenderingServer.material_set_param(material_rid(material), &"cloud_shadow_enabled", value)
	_bound_materials = materials.duplicate()
	_active = value


func update() -> void:
	if source == null:
		return
	var sun := source.sun
	if not shadows_enabled or not source.enabled or not source.clouds_enabled or materials.is_empty() \
			or not is_instance_valid(sun) or not sun.is_visible_in_tree():
		_set_active(false)
		return
	var direction := sun.global_basis.z.normalized()
	if not direction.is_finite() or direction.y <= 0.0:
		_set_active(false)
		return
	var rd := source.rd
	if rd == null or not source.ensure_field(direction):
		_set_active(false)
		return
	var key := source._field_key + [resolution]
	var changed := key != _key
	if changed:
		if not _bake(rd):
			_set_active(false)
			return
		_key = key
		bake_count += 1
	if changed or not _active or _bound_materials != materials or ambient_dimming != _bound_ambient:
		for material in materials:
			RenderingServer.material_set_param(material_rid(material), &"cloud_shadow_texture", texture.get_rid())
			RenderingServer.material_set_param(material_rid(material), &"cloud_shadow_deck",
				Vector3(source.deck_base, source.deck_top, source.weather_world_m))
			RenderingServer.material_set_param(material_rid(material), &"cloud_shadow_sun_direction", direction)
			RenderingServer.material_set_param(material_rid(material), &"cloud_shadow_ambient", ambient_dimming)
		_bound_ambient = ambient_dimming
	_set_active(true)


func _bake(rd: RenderingDevice) -> bool:
	if not _shader.is_valid():
		_shader = CloudSystem._compile_compute_dev(rd, "res://addons/clouds/bake_shadow.glsl")
		if not _shader.is_valid():
			return false
		_pipeline = rd.compute_pipeline_create(_shader)
		_mip_shader = CloudSystem._compile_compute_dev(rd, "res://addons/clouds/shadow_mipmap.glsl")
		if _mip_shader.is_valid():
			_mip_pipeline = rd.compute_pipeline_create(_mip_shader)
	if not _pipeline.is_valid() or not _mip_pipeline.is_valid():
		return false
	if not _volume.is_valid() or rd.texture_get_format(_volume).width != resolution:
		# Detach the RenderingServer wrapper BEFORE freeing its RD texture.
		texture.texture_rd_rid = RID()
		if _volume.is_valid():
			rd.free_rid(_volume)
		var format := RDTextureFormat.new()
		format.texture_type = RenderingDevice.TEXTURE_TYPE_2D_ARRAY
		format.format = RenderingDevice.DATA_FORMAT_R16_SFLOAT
		format.width = resolution
		format.height = resolution
		format.array_layers = 129
		format.mipmaps = int(log(resolution) / log(2)) + 1
		format.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_TO_BIT
		_volume = rd.texture_create(format, RDTextureView.new(), [])
		if not _volume.is_valid():
			return false
		texture.texture_rd_rid = _volume
	var uniforms: Array[RDUniform] = []
	for entry in [
		[RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER, 0, [source._ubo]],
		[RenderingDevice.UNIFORM_TYPE_IMAGE, 1, [_volume]],
		[RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE, 2, [source._sampler, source._noise3d]],
		[RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE, 5, [source._field_sampler, source._shape_tex]],
	]:
		var uniform := RDUniform.new()
		uniform.uniform_type = entry[0]
		uniform.binding = entry[1]
		for id in entry[2]:
			uniform.add_id(id)
		uniforms.append(uniform)
	var bindings := UniformSetCacheRD.get_cache(_shader, 0, uniforms)
	if not bindings.is_valid():
		return false
	# The UBO may still contain a prior camera, but its cloud/sun settings must
	# match this bake even when only shadow resolution changed.
	var bytes := source._pack_ubo(Transform3D.IDENTITY, Projection(),
		source.sun.global_basis.z.normalized(), Vector3.ONE).to_byte_array()
	rd.buffer_update(source._ubo, 0, bytes.size(), bytes)
	var list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(list, _pipeline)
	rd.compute_list_bind_uniform_set(list, bindings, 0)
	rd.compute_list_dispatch(list, (resolution + 7) / 8, (resolution + 7) / 8, 1)
	rd.compute_list_end()
	return _bake_mipmaps(rd)


func _bake_mipmaps(rd: RenderingDevice) -> bool:
	# Godot 4.7.2 cannot create an all-array-layers single-mip storage view.
	# Downsample all layers in one dispatch, then copy into their mip level.
	# Temporary storage is released after recording; no extra steady-state VRAM.
	var format := RDTextureFormat.new()
	format.texture_type = RenderingDevice.TEXTURE_TYPE_2D_ARRAY
	format.format = RenderingDevice.DATA_FORMAT_R16_SFLOAT
	format.width = resolution / 2
	format.height = resolution / 2
	format.array_layers = 129
	format.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	var temporary := rd.texture_create(format, RDTextureView.new(), [])
	if not temporary.is_valid():
		return false
	var input := RDUniform.new()
	input.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	input.binding = 0
	input.add_id(source._sampler)
	input.add_id(_volume)
	var output := RDUniform.new()
	output.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	output.binding = 1
	output.add_id(temporary)
	var bindings := UniformSetCacheRD.get_cache(_mip_shader, 0, [input, output])
	if not bindings.is_valid():
		rd.free_rid(temporary)
		return false
	for mip in range(1, rd.texture_get_format(_volume).mipmaps):
		var size := maxi(1, resolution >> mip)
		var parameters := PackedInt32Array([size, size, mip - 1, 0]).to_byte_array()
		var list := rd.compute_list_begin()
		rd.compute_list_bind_compute_pipeline(list, _mip_pipeline)
		rd.compute_list_bind_uniform_set(list, bindings, 0)
		rd.compute_list_set_push_constant(list, parameters, 16)
		rd.compute_list_dispatch(list, (size + 7) / 8, (size + 7) / 8, 129)
		rd.compute_list_end()
		for layer in 129:
			var error := rd.texture_copy(temporary, _volume, Vector3.ZERO, Vector3.ZERO,
				Vector3(size, size, 1), 0, mip, layer, layer)
			if error != OK:
				rd.free_rid(temporary)
				return false
	rd.free_rid(temporary)
	return true
