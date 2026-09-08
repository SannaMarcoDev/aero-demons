extends SceneTree
## Graphical standalone: Godot --path . --script tools/freeroam_filter_benchmark.gd
## 3 rotated rounds, 5 s warmup + 12 s flight per mode; no movie or fixed-fps.

func _initialize() -> void:
	call_deferred("benchmark")

func benchmark() -> void:
	assert(DisplayServer.get_name() != "headless", "Benchmark requires graphical rendering")
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	root.size = Vector2i(1920, 1080)
	# Keep the reference unfiltered even when the project default is FSR2.
	root.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	root.scaling_3d_scale = 1.0
	root.use_taa = false
	root.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	var scene = load("res://scenes/levels/tutorial.tscn").instantiate()
	root.add_child(scene)
	var player: Node3D = scene.get_node("Player")
	player.set_physics_process(false)
	var start := player.position
	var viewport := root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(viewport, true)
	var results: Array[Dictionary] = []
	for round_index in range(3):
		var modes := [0, 3, 4]
		for index in range(3):
			var mode: int = modes[(index + round_index) % 3]
			player.position = start
			scene.apply_mode(mode)
			await create_timer(5.0).timeout
			var frames: Array[float] = []
			var gpu: Array[float] = []
			var began := Time.get_ticks_usec()
			var previous := began
			while Time.get_ticks_usec() - began < 12000000:
				player.position = start + Vector3(0, 0, -180.0 * float(Time.get_ticks_usec() - began) / 1000000.0)
				await process_frame
				var now := Time.get_ticks_usec()
				frames.append(float(now - previous) / 1000.0)
				previous = now
				var gpu_ms := RenderingServer.viewport_get_measured_render_time_gpu(viewport)
				if gpu_ms > 0.0:
					gpu.append(gpu_ms)
			assert(frames.size() > 60, "Too few benchmark frames")
			var elapsed_ms := float(previous - began) / 1000.0
			frames.sort()
			gpu.sort()
			var result := {"round": round_index + 1, "mode": scene.MODES[mode],
				"frames": frames.size(), "fps": frames.size() * 1000.0 / elapsed_ms,
				"median_ms": frames[frames.size() / 2],
				"p99_ms": frames[mini(ceili(frames.size() * 0.99) - 1, frames.size() - 1)],
				"gpu_median_ms": gpu[gpu.size() / 2] if not gpu.is_empty() else 0.0}
			results.append(result)
			print(JSON.stringify(result))
	var output := "user://filter_benchmark_" + Time.get_datetime_string_from_system().replace(":", "-") + ".json"
	var file := FileAccess.open(output, FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify({"gpu": RenderingServer.get_video_adapter_name(),
		"resolution": str(root.size), "vsync": DisplayServer.window_get_vsync_mode(),
		"results": results}, "\t"))
	file.close()
	print("PASS: benchmark saved: ", ProjectSettings.globalize_path(output))
	quit()
