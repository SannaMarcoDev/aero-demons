@tool
class_name CloudTransparency
extends RefCounted

## Optional viewport-local adapter. No aircraft, weapon or map dependencies.
## Runtime material instances keep their identity (animation/replay may cache them).
const VIEW_INCLUDE := '#include "res://addons/clouds/cloud_view.gdshaderinc"\n'
var texture: Texture3DRD
var _active := false
# ponytail: per-layer retention; prune on geometry exit if long sessions spawn many VFX.
var _materials: Dictionary = {}
var _shaders: Dictionary = {}
var _meshes: Dictionary = {}
var _receivers: Array[ShaderMaterial] = []


func set_active(value: bool) -> void:
	if value == _active:
		return
	_active = value
	for material in _receivers:
		material.set_shader_parameter("cloud_view_enabled", value)


func clear() -> void:
	set_active(false)
	for material in _receivers:
		material.set_shader_parameter("cloud_view_texture", null)
	_receivers.clear()
	_materials.clear()
	_shaders.clear()
	_meshes.clear()


func bind_geometry(node: GeometryInstance3D) -> void:
	if node.material_override != null:
		node.material_override = register_material(node.material_override)
	elif node is MeshInstance3D and node.mesh != null:
		for surface in node.mesh.get_surface_count():
			var original: Material = node.get_active_material(surface)
			var adapted := register_material(original)
			if adapted != original:
				node.set_surface_override_material(surface, adapted)
	elif node is GPUParticles3D:
		for index in node.draw_passes:
			var mesh: Mesh = node.get_draw_pass_mesh(index)
			if mesh != null:
				node.set_draw_pass_mesh(index, _bind_mesh(mesh))
	elif node is MultiMeshInstance3D and node.multimesh != null and node.multimesh.mesh != null:
		var adapted := _bind_mesh(node.multimesh.mesh)
		if adapted != node.multimesh.mesh:
			var batch: MultiMesh = node.multimesh
			if not batch.resource_path.is_empty():
				batch = batch.duplicate()
			batch.mesh = adapted
			node.multimesh = batch


func _bind_mesh(mesh: Mesh) -> Mesh:
	if _meshes.has(mesh):
		return _meshes[mesh]
	var result := mesh
	for surface in mesh.get_surface_count():
		var original := mesh.surface_get_material(surface)
		var adapted := register_material(original)
		if adapted != original:
			if result == mesh:
				result = mesh.duplicate()
			result.surface_set_material(surface, adapted)
	_meshes[mesh] = result
	_meshes[result] = result
	return result


## Returns a local copy only for shared assets. Call after assigning/configuring
## draw materials; shader uniforms and cached runtime references stay writable.
func register_material(original: Material) -> Material:
	if original == null:
		return null
	if _materials.has(original):
		return _materials[original]
	var material := original as ShaderMaterial
	if original is StandardMaterial3D:
		# Lit native receivers are already converted by the map's shadow adapter.
		# These two native features cover the unshaded particle/halo materials.
		if original.transparency != BaseMaterial3D.TRANSPARENCY_ALPHA or original.shading_mode != BaseMaterial3D.SHADING_MODE_UNSHADED:
			return original
		if original.blend_mode not in [BaseMaterial3D.BLEND_MODE_MIX, BaseMaterial3D.BLEND_MODE_ADD]:
			return original
		material = _unshaded_material(original)
	if material == null or material.shader == null or material.shader.get_mode() != Shader.MODE_SPATIAL:
		return original
	var code := material.shader.code
	# Cutouts/hash render in the opaque pass; screen-space overlays have no
	# geometric distance. Neither must sample a previous frame's view cache.
	if "POSITION =" in code or "#define CLOUD_SCISSOR" in code or "#define CLOUD_HASH" in code:
		return original
	if "#ifdef CLOUD_ALPHA" not in code and ("ALPHA_SCISSOR_THRESHOLD" in code or "ALPHA_HASH_SCALE" in code):
		return original
	if VIEW_INCLUDE not in code and "cloud_view_texture" not in code:
		var alpha := RegEx.new()
		alpha.compile("\\bALPHA\\s*=")
		if alpha.search(code) == null or ("#ifdef CLOUD_ALPHA" in code and "#define CLOUD_ALPHA" not in code):
			return original
		if not _shaders.has(material.shader):
			# A transient shader has no resource-relative include directory.
			var includes := RegEx.new()
			includes.compile('#include\\s+"([^"]+)"')
			for include in includes.search_all(code):
				var path := include.get_string(1)
				if not path.begins_with("res://"):
					var base := material.shader.resource_path.get_base_dir()
					if base.is_empty():
						push_warning("CloudTransparency: use absolute res:// shader includes.")
						return original
					code = code.replace(include.get_string(), '#include "%s"' % base.path_join(path).simplify_path())
			var fragment := RegEx.new()
			fragment.compile("void\\s+fragment\\s*\\(\\s*\\)\\s*\\{")
			var found := fragment.search(code)
			if found == null:
				return original
			var end := found.get_end()
			var depth := 1
			while end < code.length() and depth > 0:
				if code[end] == "{": depth += 1
				elif code[end] == "}": depth -= 1
				end += 1
			if depth != 0:
				return original
			var apply := "\nif (cloud_view_enabled) {\nvec4 cloud = cloud_view_at(SCREEN_UV, length(VERTEX));\n"
			if "blend_add" in code:
				apply += "ALBEDO *= cloud.a;\nEMISSION *= cloud.a;\n"
			elif "hint_screen_texture" in code:
				# Refraction samples the already clouded back buffer; don't fog it twice.
				apply += "ALPHA *= cloud.a;\n"
			else:
				apply += "if (cloud.a <= 0.01) { discard; }\nFOG = cloud_view_fog(cloud);\n"
			apply += "}\n"
			code = code.insert(end - 1, apply)
			code = code.insert(code.find(";") + 1, "\n" + VIEW_INCLUDE)
			var shader := Shader.new()
			shader.code = code
			_shaders[material.shader] = shader
		if not material.resource_path.is_empty():
			material = material.duplicate()
		material.shader = _shaders[material.shader]
	material.set_shader_parameter("cloud_view_texture", texture)
	material.set_shader_parameter("cloud_view_enabled", _active)
	if not _receivers.has(material):
		_receivers.append(material)
	_materials[original] = material
	_materials[material] = material
	return material


func _unshaded_material(source: StandardMaterial3D) -> ShaderMaterial:
	var code := """shader_type spatial;
render_mode unshaded, %s, %s, %s;
uniform vec4 albedo : source_color;
uniform sampler2D albedo_texture : source_color, hint_default_white;
uniform bool use_color;
uniform vec4 emission : source_color;
uniform float emission_energy;
uniform sampler2D emission_texture : source_color, hint_default_black;
void vertex() {
%s
}
void fragment() {
	vec4 color = albedo * texture(albedo_texture, UV);
	if (use_color) { color *= COLOR; }
	ALBEDO = color.rgb;
	ALPHA = color.a;
	EMISSION = (emission.rgb + texture(emission_texture, UV).rgb) * emission_energy;
}
"""
	var billboard := ""
	if source.billboard_mode != BaseMaterial3D.BILLBOARD_DISABLED:
		billboard = """float sx = length(MODEL_MATRIX[0].xyz);
float sy = length(MODEL_MATRIX[1].xyz);
float a = %s;
vec2 p = mat2(vec2(cos(a), sin(a)), vec2(-sin(a), cos(a))) * VERTEX.xy;
VERTEX = vec3(p * vec2(sx, sy), 0.0);
MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);""" % ("INSTANCE_CUSTOM.x" if source.billboard_mode == BaseMaterial3D.BILLBOARD_PARTICLES else "0.0")
	var cull: String = ["cull_back", "cull_front", "cull_disabled"][source.cull_mode]
	var depth := "depth_draw_always" if source.depth_draw_mode == BaseMaterial3D.DEPTH_DRAW_ALWAYS else "depth_draw_never"
	code = code % [depth, cull, "blend_add" if source.blend_mode == BaseMaterial3D.BLEND_MODE_ADD else "blend_mix", billboard]
	if not _shaders.has(code):
		var shader := Shader.new()
		shader.code = code
		_shaders[code] = shader
	var result := ShaderMaterial.new()
	result.shader = _shaders[code]
	result.render_priority = source.render_priority
	result.next_pass = source.next_pass
	result.set_shader_parameter("albedo", source.albedo_color)
	result.set_shader_parameter("albedo_texture", source.albedo_texture)
	result.set_shader_parameter("use_color", source.vertex_color_use_as_albedo)
	result.set_shader_parameter("emission", source.emission)
	result.set_shader_parameter("emission_texture", source.emission_texture)
	result.set_shader_parameter("emission_energy", source.emission_energy_multiplier if source.emission_enabled else 0.0)
	return result
