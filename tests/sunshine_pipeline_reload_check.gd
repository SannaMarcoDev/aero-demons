extends SceneTree
# Run with Godot --path . --script tests/sunshine_pipeline_reload_check.gd (Forward+, not headless).
# Add --rendering-driver vulkan -- --msaa to also exercise the MSAA variant.
# No map or terrain assets are loaded or saved.
var clouds: SunshineCloudsGD
var previous_pipeline: RID

func _initialize():
	call_deferred("run")

func run():
	root.size = Vector2i(256, 144)
	clouds = load("res://resources/environments/tutorial_clouds.tres")
	clouds.max_step_count = 8
	clouds.max_lighting_steps = 1
	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	world.compositor = Compositor.new()
	world.compositor.compositor_effects = [clouds]
	root.add_child(world)
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.make_current()
	var modes := [Viewport.MSAA_DISABLED]
	if OS.get_cmdline_user_args().has("--msaa"):
		modes.append(Viewport.MSAA_2X)
	for msaa in modes:
		root.msaa_3d = msaa
		for i in 30:
			await RenderingServer.frame_post_draw
		assert(clouds.enabled and clouds.postpass_pipeline.is_valid())
		assert(not clouds.postpass_bytecode.is_empty())
		# Simulate an in-place shader reimport. Holding the resource reference would miss this.
		RenderingServer.call_on_render_thread(stale_bytecode)
		for i in 4:
			await RenderingServer.frame_post_draw
		assert(clouds.postpass_pipeline != previous_pipeline, "Reimport must rebuild without a viewport resize")
		assert(clouds.postpass_bytecode == clouds.post_pass_compute_shader.get_spirv().bytecode_compute)
		# A hot-reloaded script adds this field with an empty default while GPU RIDs survive.
		RenderingServer.call_on_render_thread(stale_pipeline)
		for i in 4:
			await RenderingServer.frame_post_draw
		assert(clouds.postpass_pipeline != previous_pipeline, "Old zero-push-constant pipeline must be replaced")
		assert(not clouds.postpass_bytecode.is_empty())
		RenderingServer.call_on_render_thread(check_push_constants)
		await RenderingServer.frame_post_draw
		print("PASS: reimport, stale pipeline recovery, 16-byte push constants; MSAA=", msaa)
	world.compositor = null
	RenderingServer.call_on_render_thread(clouds.clear_compute)
	await RenderingServer.frame_post_draw
	quit()

func zero_push_shader() -> RDShaderSPIRV:
	var source := RDShaderSource.new()
	source.source_compute = "#version 450\nlayout(local_size_x=8, local_size_y=8) in;\nvoid main() {}"
	var spirv := clouds.rd.shader_compile_spirv_from_source(source)
	assert(spirv.compile_error_compute.is_empty())
	return spirv

func stale_bytecode():
	previous_pipeline = clouds.postpass_pipeline
	clouds.post_pass_compute_shader.get_spirv().bytecode_compute = zero_push_shader().bytecode_compute

func stale_pipeline():
	clouds.rd.free_rid(clouds.postpass_pipeline)
	clouds.rd.free_rid(clouds.postpass_shader)
	clouds.postpass_shader = clouds.rd.shader_create_from_spirv(zero_push_shader())
	clouds.postpass_pipeline = clouds.rd.compute_pipeline_create(clouds.postpass_shader)
	previous_pipeline = clouds.postpass_pipeline
	clouds.postpass_bytecode = PackedByteArray()

func check_push_constants():
	var list := clouds.rd.compute_list_begin()
	clouds.rd.compute_list_bind_compute_pipeline(list, clouds.postpass_pipeline)
	var params := PackedFloat32Array([0.3, 0.5, 0.0, 0.0]).to_byte_array()
	clouds.rd.compute_list_set_push_constant(list, params, params.size())
	clouds.rd.compute_list_end()
