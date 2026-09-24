extends RefCounted
## Shared sampling for the standalone and in-game Garda benchmarks.
const FLIGHT_SPEED := 900.0
const GARDA_LOCATIONS := [
	{"id": "spawn", "pos": Vector3(0, 7114, 0), "pitch": -6.0, "yaw": 15.0},
	{"id": "clouds", "pos": Vector3(-60000, 3800, -10000), "pitch": -3.0, "yaw": 0.0},
	{"id": "lake", "pos": Vector3(-60000, 1200, 30000), "pitch": 2.0, "yaw": -55.0},
	{"id": "alpine", "pos": Vector3(-119420, 3400, -115080), "pitch": -24.0, "yaw": 80.0},
	{"id": "airport", "pos": Vector3(-36418, 275, 1500), "pitch": -2.0, "yaw": 0.0},
	{"id": "flight", "path_from": Vector3(-80000, 900, 60000), "path_to": Vector3(-74000, 900, 54000), "pitch": -3.0, "yaw": 0.0},
]


static func place_aircraft(player: Node3D, camera: Camera3D, loc: Dictionary, t: float) -> void:
	var basis: Basis
	var pos: Vector3
	if loc.has("path_from"):
		var a: Vector3 = loc.path_from
		var b: Vector3 = loc.path_to
		var dir := (b - a).normalized()
		pos = a.lerp(b, clampf(t, 0.0, 1.0))
		basis = Basis.looking_at(dir + Vector3(0, tan(deg_to_rad(loc.pitch)), 0))
	else:
		pos = loc.pos
		basis = Basis.from_euler(Vector3(deg_to_rad(loc.pitch), deg_to_rad(loc.yaw), 0.0))
	player.global_transform = Transform3D(basis, pos)
	player.reset_physics_interpolation()
	if t == 0.0:
		camera.snap_to_target()


static func measure(tree: SceneTree, viewport: Viewport, player: Node3D, camera: Camera3D,
		forest: Node, loc: Dictionary, warm: float, duration: float) -> Dictionary:
	var physics_enabled := player.is_physics_processing()
	player.set_physics_process(false)
	place_aircraft(player, camera, loc, 0.0)
	forest.update_center(camera.global_position)
	while not forest.built:
		await tree.process_frame
	player.set_physics_process(physics_enabled)
	await tree.create_timer(warm).timeout
	var frames: Array[float] = []
	var gpu: Array[float] = []
	var cpu: Array[float] = []
	var draws: Array[float] = []
	var prims: Array[float] = []
	var seg_len := 1.0
	if loc.has("path_from"):
		seg_len = (loc.path_from as Vector3).distance_to(loc.path_to)
	var began := Time.get_ticks_usec()
	var previous := began
	while Time.get_ticks_usec() - began < int(duration * 1000000.0):
		var elapsed := float(Time.get_ticks_usec() - began) / 1000000.0
		if loc.has("path_from"):
			place_aircraft(player, camera, loc, elapsed * FLIGHT_SPEED / seg_len)
		await tree.process_frame
		var now := Time.get_ticks_usec()
		frames.append(float(now - previous) / 1000.0)
		previous = now
		var gpu_ms := RenderingServer.viewport_get_measured_render_time_gpu(viewport.get_viewport_rid())
		var cpu_ms := RenderingServer.viewport_get_measured_render_time_cpu(viewport.get_viewport_rid())
		if gpu_ms > 0.0:
			gpu.append(gpu_ms)
		if cpu_ms > 0.0:
			cpu.append(cpu_ms)
		draws.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		prims.append(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	if frames.size() < 30:
		push_warning("Few frames at " + loc.id + ": " + str(frames.size()))
	var elapsed_ms := float(previous - began) / 1000.0
	var frame_times := frames.duplicate()
	var result := summarize_frames(frames)
	frames.sort()
	gpu.sort()
	cpu.sort()
	draws.sort()
	prims.sort()
	result["window"] = str(viewport.size)
	result["frames"] = frames.size()
	result["elapsed_ms"] = elapsed_ms
	result["fps"] = snappedf(frames.size() * 1000.0 / elapsed_ms, 0.1)
	result["gpu_median_ms"] = snappedf(gpu[gpu.size() / 2], 0.01) if not gpu.is_empty() else 0.0
	result["gpu_p99_ms"] = snappedf(gpu[mini(ceili(gpu.size() * 0.99) - 1, gpu.size() - 1)], 0.01) if not gpu.is_empty() else 0.0
	result["cpu_render_ms"] = snappedf(cpu[cpu.size() / 2], 0.01) if not cpu.is_empty() else 0.0
	result["draw_calls"] = int(draws[draws.size() / 2])
	result["primitives_k"] = int(prims[prims.size() / 2] / 1000.0)
	result["vram_mb"] = int(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0)
	result["frame_times_ms"] = frame_times
	return result


static func summarize_frames(frames: Array[float]) -> Dictionary:
	assert(not frames.is_empty())
	var ordered := frames.duplicate()
	ordered.sort()
	var summary := {}
	for percentile in [50, 90, 95, 99]:
		var key := "median_ms" if percentile == 50 else "p%d_ms" % percentile
		summary[key] = snappedf(ordered[ceili(ordered.size() * percentile / 100.0) - 1], 0.01)
	summary["max_ms"] = snappedf(ordered.back(), 0.01)
	for threshold in [5.0, 16.667, 33.333, 50.0]:
		var count := 0
		for frame_ms in ordered:
			if frame_ms > threshold:
				count += 1
		summary["frames_over_%s_ms" % str(threshold)] = count
	return summary
