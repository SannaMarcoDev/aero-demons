extends Node
## Runtime-only receivers: imported assets and other worlds keep their materials.
const STANDARD := preload("res://resources/shaders/cloud_standard.gdshader")
const PBR_INCLUDE := '#include "res://addons/clouds/cloud_pbr.gdshaderinc"\n'
# ponytail: caches last until map unload; evict unused receivers if long replay scrubbing grows them.
var _materials: Dictionary = {}
var _shaders: Dictionary = {}
var _meshes: Dictionary = {}
@onready var layer: CloudLayer3D = get_parent().get_node("CloudLayer3D")


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		return
	_bind_world.call_deferred()


func _bind_world() -> void:
	if not is_inside_tree() or layer.effect == null:
		return
	var terrain: Terrain3D = get_parent().get_node("GardaTerrain")
	if not layer.register_shadow_material(terrain.material):
		push_error("Garda cloud shadows: terrain shader is not a receiver.")
	get_tree().node_added.connect(_node_added)
	for node in get_tree().current_scene.find_children("*", "GeometryInstance3D", true, false):
		_bind_geometry(node)


func _node_added(node: Node) -> void:
	if node is MeshInstance3D or node is MultiMeshInstance3D:
		# Wait for mesh assignment, aircraft setup and replay material duplication.
		_bind_geometry.call_deferred(node)


func _exit_tree() -> void:
	if get_tree().node_added.is_connected(_node_added):
		get_tree().node_added.disconnect(_node_added)
	request_ready()


func _bind_geometry(node: Node) -> void:
	if not is_inside_tree() or not is_instance_valid(node) or not node.is_inside_tree() or node.get_viewport() != get_viewport():
		return
	var mesh: Mesh
	if node is MeshInstance3D:
		mesh = node.mesh
	elif node is MultiMeshInstance3D and node.multimesh != null:
		mesh = node.multimesh.mesh
	if mesh == null:
		return
	if node.material_override != null:
		node.material_override = _receiver(node.material_override)
		return
	if node is MeshInstance3D:
		for surface in mesh.get_surface_count():
			var original: Material = node.get_active_material(surface)
			var receiver := _receiver(original)
			if receiver != original:
				node.set_surface_override_material(surface, receiver)
	else:
		# MultiMesh has no per-surface override. Clone each shared mesh only once.
		if not _meshes.has(mesh):
			var local := mesh.duplicate() as Mesh
			for surface in mesh.get_surface_count():
				local.surface_set_material(surface, _receiver(mesh.surface_get_material(surface)))
			_meshes[mesh] = local
			_meshes[local] = local
		var batch: MultiMesh = node.multimesh
		batch.mesh = _meshes[mesh]


func _receiver(original: Material) -> Material:
	if original == null:
		return null
	if _materials.has(original):
		return _materials[original]
	var result: Material = original
	if original is StandardMaterial3D and original.shading_mode == BaseMaterial3D.SHADING_MODE_PER_PIXEL:
		result = _standard_receiver(original)
	elif original is ShaderMaterial and original.shader != null:
		var code: String = original.shader.code
		if CloudLayer3D._is_shadow_material(original):
			layer.register_shadow_material(original)
		elif "unshaded" not in code and "vertex_lighting" not in code and "void light" not in code:
			if not _shaders.has(original.shader):
				var start := code.find("void fragment()")
				var end := code.find("{", start)
				var depth := 1
				if start >= 0 and end >= 0:
					end += 1
					while end < code.length() and depth > 0:
						if code[end] == "{": depth += 1
						elif code[end] == "}": depth -= 1
						end += 1
					if depth == 0:
						var assignments := "\ncloud_material_specular = SPECULAR;\ncloud_transmission = cloud_sun_transmittance((INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);\nAO *= cloud_ambient_occlusion(cloud_transmission);\n"
						code = code.insert(end - 1, assignments)
						code = code.insert(code.find(";") + 1, "\n" + PBR_INCLUDE)
						var shader := Shader.new()
						shader.code = code
						_shaders[original.shader] = shader
			if _shaders.has(original.shader):
				result = original.duplicate()
				result.shader = _shaders[original.shader]
	if result != original:
		if not layer.register_shadow_material(result):
			push_error("Garda cloud shadows: invalid receiver for " + original.resource_path)
		# Already-adapted materials may be encountered again by streaming/reparenting.
		_materials[result] = result
	_materials[original] = result
	return result


func _standard_receiver(source: StandardMaterial3D) -> ShaderMaterial:
	var code := STANDARD.code
	match source.cull_mode:
		BaseMaterial3D.CULL_DISABLED: code = code.replace("cull_back", "cull_disabled")
		BaseMaterial3D.CULL_FRONT: code = code.replace("cull_back", "cull_front")
	if source.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
		code = code.insert(code.find(";") + 1, "\n#define CLOUD_ALPHA\n")
	match source.transparency:
		BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR:
			code = code.insert(code.find(";") + 1, "\n#define CLOUD_SCISSOR\n")
		BaseMaterial3D.TRANSPARENCY_ALPHA_HASH:
			code = code.insert(code.find(";") + 1, "\n#define CLOUD_HASH\n")
		BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS:
			code = code.replace("depth_draw_opaque", "depth_prepass_alpha")
	if not _shaders.has(code):
		var shader := Shader.new()
		shader.code = code
		_shaders[code] = shader
	var result := ShaderMaterial.new()
	result.shader = _shaders[code]
	result.render_priority = source.render_priority
	result.next_pass = source.next_pass
	for parameter in ["albedo_color", "albedo_texture", "metallic", "metallic_texture", "roughness", "roughness_texture", "normal_enabled", "normal_scale", "normal_texture", "ao_enabled", "ao_texture", "ao_light_affect", "emission_enabled", "emission_texture", "alpha_scissor_threshold", "alpha_hash_scale"]:
		result.set_shader_parameter(parameter, source.get(parameter))
	for channel in ["metallic", "roughness", "ao"]:
		result.set_shader_parameter(channel + "_channel", _channel_mask(source.get(channel + "_texture_channel")))
	result.set_shader_parameter("material_specular", source.metallic_specular)
	result.set_shader_parameter("vertex_color_albedo", source.vertex_color_use_as_albedo)
	result.set_shader_parameter("uv_scale", Vector2(source.uv1_scale.x, source.uv1_scale.y))
	result.set_shader_parameter("uv_offset", Vector2(source.uv1_offset.x, source.uv1_offset.y))
	result.set_shader_parameter("emission_color", source.emission)
	result.set_shader_parameter("emission_energy", source.emission_energy_multiplier)
	result.set_shader_parameter("emission_multiply", source.emission_operator == BaseMaterial3D.EMISSION_OP_MULTIPLY)
	result.set_shader_parameter("backlight_color", source.backlight if source.backlight_enabled else Color(0, 0, 0))
	return result


func _channel_mask(channel: int) -> Vector4:
	if channel == BaseMaterial3D.TEXTURE_CHANNEL_GRAYSCALE:
		return Vector4(1.0 / 3.0, 1.0 / 3.0, 1.0 / 3.0, 0.0)
	var mask := Vector4.ZERO
	mask[channel] = 1.0
	return mask
