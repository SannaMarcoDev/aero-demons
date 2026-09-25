extends SceneTree
## Offline Poly Haven fir conversion: native mesh LOD simplification + unlit albedo/normal impostors.
const SOURCE := "res://subagent-artifacts/garda-lookdev/sources/fir/fir_b.gltf"
const OUT := "res://assets/environment/garda_forest"
const NORMAL_SHADER := """shader_type spatial;
render_mode unshaded, cull_disabled;
uniform sampler2D tex : source_color;
uniform vec2 uv_scale = vec2(1.0);
uniform vec2 uv_offset = vec2(0.0);
varying vec3 world_normal;
void vertex() { world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL); }
void fragment() {
 vec4 color = texture(tex, UV * uv_scale + uv_offset);
 vec3 encoded = normalize(world_normal) * 0.5 + 0.5;
 ALBEDO = mix(encoded / 12.92, pow((encoded + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), encoded));
 ALPHA = color.a; ALPHA_SCISSOR_THRESHOLD = 0.5;
}"""

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	assert(DisplayServer.get_name() != "headless")
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	assert(doc.append_from_file(SOURCE, state) == OK)
	var source: Node3D = doc.generate_scene(state)
	var model := source.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	var mesh := model.mesh as ArrayMesh
	var bounds := mesh.get_aabb()
	var scale_factor := 22.0 / bounds.size.y
	print("FIR source bounds ", bounds, " scale ", scale_factor)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1024, 1024)
	viewport.transparent_bg = true
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	viewport.add_child(source)
	model.position = -Vector3(bounds.get_center().x, bounds.position.y, bounds.get_center().z) * scale_factor
	model.scale = Vector3.ONE * scale_factor
	model.lod_bias = 1000.0
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 24.0
	viewport.add_child(camera)
	camera.make_current()
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_CLEAR_COLOR
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
	viewport.add_child(env)
	var normal_shader := Shader.new()
	normal_shader.code = NORMAL_SHADER
	var atlases: Array[Image] = []
	for normal_pass in [false, true]:
		for s in mesh.get_surface_count():
			var original := mesh.surface_get_material(s) as StandardMaterial3D
			assert(original != null)
			if normal_pass:
				var mat := ShaderMaterial.new()
				mat.shader = normal_shader
				mat.set_shader_parameter("tex", original.albedo_texture)
				mat.set_shader_parameter("uv_scale", Vector2(original.uv1_scale.x, original.uv1_scale.y))
				mat.set_shader_parameter("uv_offset", Vector2(original.uv1_offset.x, original.uv1_offset.y))
				model.set_surface_override_material(s, mat)
			else:
				var mat := original.duplicate() as StandardMaterial3D
				mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
				mat.alpha_scissor_threshold = 0.5
				model.set_surface_override_material(s, mat)
		var atlas := Image.create(2048, 2048, false, Image.FORMAT_RGBA8)
		for view in 3:
			var positions := [Vector3(0, 12, 60), Vector3(60, 12, 0), Vector3(0, 60, 0)]
			camera.position = positions[view]
			camera.look_at(Vector3(0, 12, 0), Vector3.FORWARD if view == 2 else Vector3.UP)
			for frame in 3: await process_frame
			await RenderingServer.frame_post_draw
			var image := viewport.get_texture().get_image()
			if view == 2: image.resize(512, 512, Image.INTERPOLATE_LANCZOS)
			atlas.blit_rect(image, Rect2i(Vector2i.ZERO, image.get_size()), [Vector2i(0, 512), Vector2i(1024, 512), Vector2i(0, 1536)][view])
		# Dilate RGB into transparent edges before mipmapping; alpha stays untouched.
		atlas.fix_alpha_edges()
		atlas.generate_mipmaps()
		atlases.append(atlas)
		assert(atlas.save_png(OUT + ("/garda_fir_normals.png" if normal_pass else "/garda_fir_atlas.png")) == OK)
	var far_material := ShaderMaterial.new()
	far_material.shader = load("res://resources/terrain/garda_foliage.gdshader")
	far_material.set_shader_parameter("atlas", ImageTexture.create_from_image(atlases[0]))
	far_material.set_shader_parameter("crown_normals", ImageTexture.create_from_image(atlases[1]))
	far_material.set_shader_parameter("alpha_cut", 0.4)
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.set_material(far_material)
	var quads := [
		[Vector3(-12, 0, 0), Vector3(12, 0, 0), Vector3(12, 24, 0), Vector3(-12, 24, 0)],
		[Vector3(0, 0, 12), Vector3(0, 0, -12), Vector3(0, 24, -12), Vector3(0, 24, 12)],
		[Vector3(-12, 12, 12), Vector3(12, 12, 12), Vector3(12, 12, -12), Vector3(-12, 12, -12)]
	]
	for view in 3:
		var rect: Rect2 = [Rect2(0, 0.25, 0.5, 0.5), Rect2(0.5, 0.25, 0.5, 0.5), Rect2(0, 0.75, 0.25, 0.25)][view]
		var uvs := [rect.position + Vector2(0, rect.size.y), rect.end, rect.position + Vector2(rect.size.x, 0), rect.position]
		for index in [0, 2, 1, 0, 3, 2]:
			surface.set_uv(uvs[index])
			surface.set_normal(Vector3.UP)
			surface.set_color(Color.WHITE)
			surface.add_vertex(quads[view][index])
	var far_mesh := surface.commit()
	assert(ResourceSaver.save(far_mesh, OUT + "/garda_fir_far.res", ResourceSaver.FLAG_COMPRESS) == OK)
	# Use Godot's importer simplifier; retain only vertices actually used by the chosen LOD.
	var importer: ImporterMesh = state.get_meshes()[0].mesh
	importer.generate_lods(60.0, 25.0, [])
	var near_mesh := ArrayMesh.new()
	var triangles := 0
	for s in importer.get_surface_count():
		var arrays := importer.get_surface_arrays(s)
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		for lod in importer.get_surface_lod_count(s):
			indices = importer.get_surface_lod_indices(s, lod)
			if indices.size() <= 18000: break
		var mat := mesh.surface_get_material(s).duplicate() as StandardMaterial3D
		mat.vertex_color_use_as_albedo = true
		mat.albedo_color = Color(0.915, 0.973, 0.936)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.alpha_scissor_threshold = 0.4
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		st.set_material(mat)
		for i in indices:
			if arrays[Mesh.ARRAY_NORMAL] != null: st.set_normal(arrays[Mesh.ARRAY_NORMAL][i])
			st.set_uv(arrays[Mesh.ARRAY_TEX_UV][i])
			st.set_color(Color.WHITE)
			st.add_vertex(arrays[Mesh.ARRAY_VERTEX][i] * scale_factor + model.position)
		if arrays[Mesh.ARRAY_NORMAL] == null: st.generate_normals()
		st.index()
		st.generate_tangents()
		st.commit(near_mesh)
		triangles += indices.size() / 3
	assert(ResourceSaver.save(near_mesh, OUT + "/garda_fir_near.res", ResourceSaver.FLAG_COMPRESS) == OK)
	print("FIR near triangles ", triangles, "; far triangles 6")
	viewport.queue_free()
	for audio in root.get_node("AudioManager").get_children():
		if audio is AudioStreamPlayer:
			audio.stop()
			audio.stream = null
	for i in 8: await process_frame
	print("PASS: GARDA FIR BAKE")
	quit()
