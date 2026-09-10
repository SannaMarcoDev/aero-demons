extends SceneTree
## Graphical standalone: Godot --path . --script tools/freeroam_benchmark.gd
## Options: --quick (1 round, short windows), --only=phase (a|b|c).
## Phase A: locations x AA/upscaling presets, 2 rotated rounds.
## Phase B: scene toggles (clouds/shadows) at key locations.
## Phase C: window resolution sweep at one location.

const WARMUP := 3.5
const MEASURE := 6.0
const ROUNDS := 2
const FLIGHT_SPEED := 900.0

var quick := false
var only := ""
var results: Array[Dictionary] = []
var scene: Node3D
var player: Node3D
var camera: Camera3D
var terrain
var sun: DirectionalLight3D
var world_env: WorldEnvironment
var viewport_rid: RID

var LOCATIONS := [
	{"id": "spawn_orizzonte", "pos": Vector3(0, 7114, 0), "pitch": -6.0, "yaw": 15.0},
	{"id": "dentro_nuvole", "pos": Vector3(-60000, 3800, -10000), "pitch": -3.0, "yaw": 0.0},
	{"id": "lago_sotto_nuvole", "pos": Vector3(-60000, 1200, 30000), "pitch": 2.0, "yaw": -55.0},
	{"id": "raso_acqua", "pos": Vector3(-70000, 650, 50000), "pitch": -1.0, "yaw": 25.0},
	{"id": "costa_monti", "pos": Vector3(-10000, 1000, -20000), "pitch": 1.0, "yaw": -75.0},
	{"id": "cime_alte", "pos": Vector3(25000, 7000, -5000), "pitch": -5.0, "yaw": -120.0},
	{"id": "nadir_terreno", "pos": Vector3(0, 1200, -10000), "pitch": -90.0, "yaw": 0.0},
	{"id": "volo_radente", "path_from": Vector3(-80000, 900, 60000), "path_to": Vector3(-74000, 900, 54000), "pitch": -3.0, "yaw": 0.0},
]

func presets() -> Array:
	return [
		{"id": "default_fxaa", "mode": Viewport.SCALING_3D_MODE_BILINEAR, "scale": 1.0, "taa": false, "ssaa": Viewport.SCREEN_SPACE_AA_FXAA},
		{"id": "no_aa", "mode": Viewport.SCALING_3D_MODE_BILINEAR, "scale": 1.0, "taa": false, "ssaa": Viewport.SCREEN_SPACE_AA_DISABLED},
		{"id": "taa", "mode": Viewport.SCALING_3D_MODE_BILINEAR, "scale": 1.0, "taa": true, "ssaa": Viewport.SCREEN_SPACE_AA_DISABLED},
		{"id": "fsr2_100", "mode": Viewport.SCALING_3D_MODE_FSR2, "scale": 1.0, "taa": false, "ssaa": Viewport.SCREEN_SPACE_AA_DISABLED},
		{"id": "fsr2_067", "mode": Viewport.SCALING_3D_MODE_FSR2, "scale": 0.67, "taa": false, "ssaa": Viewport.SCREEN_SPACE_AA_DISABLED},
		{"id": "bilinear_067", "mode": Viewport.SCALING_3D_MODE_BILINEAR, "scale": 0.67, "taa": false, "ssaa": Viewport.SCREEN_SPACE_AA_FXAA},
		{"id": "bilinear_050", "mode": Viewport.SCALING_3D_MODE_BILINEAR, "scale": 0.5, "taa": false, "ssaa": Viewport.SCREEN_SPACE_AA_FXAA},
		{"id": "ssaa_125", "mode": Viewport.SCALING_3D_MODE_BILINEAR, "scale": 1.25, "taa": false, "ssaa": Viewport.SCREEN_SPACE_AA_DISABLED},
	]

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	quick = "--quick" in args
	for a in args:
		if a.begins_with("--only="):
			only = a.get_slice("=", 1)
	call_deferred("benchmark")

func benchmark() -> void:
	assert(DisplayServer.get_name() != "headless", "Benchmark requires graphical rendering")
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	root.size = Vector2i(1920, 1080)
	scene = load("res://scenes/levels/freeroam.tscn").instantiate()
	root.add_child(scene)
	player = scene.get_node("Player")
	camera = scene.get_node("Player/FlightCamera")
	terrain = scene.get_node("GardaLake/GardaTerrain")
	sun = scene.get_node("GardaLake/Sky3D/SunLight")
	world_env = scene.get_node("GardaLake/Sky3D")
	player.set_physics_process(false)
	viewport_rid = root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(viewport_rid, true)
	apply_preset(presets()[0])
	place_aircraft(LOCATIONS[0], 0.0)
	await create_timer(8.0).timeout
	var warm := 1.5 if quick else WARMUP
	var meas := 3.0 if quick else MEASURE
	var rounds := 1 if quick else ROUNDS
	var ps := presets()
	if only in ["", "a"]:
		for r in range(rounds):
			for li in range(LOCATIONS.size()):
				for pi in range(ps.size()):
					var preset: Dictionary = ps[(pi + r) % ps.size()]
					apply_preset(preset)
					await measure(LOCATIONS[li], {"phase": "a", "round": r + 1, "preset": preset.id}, warm, meas)
	if only in ["", "b"]:
		apply_preset(ps[0])
		var toggle_locs := ["dentro_nuvole", "lago_sotto_nuvole", "costa_monti", "cime_alte"]
		var toggles := [
			{"id": "nuvole_off", "fn": set_clouds.bind(false)},
			{"id": "ombre_off", "fn": set_shadows.bind(false)},
			{"id": "nuvole_ombre_off", "fn": func(): set_clouds(false); set_shadows(false)},
		]
		for loc_id in toggle_locs:
			var loc := loc_by_id(loc_id)
			for t in toggles:
				t.fn.call()
				await measure(loc, {"phase": "b", "round": 1, "preset": "default_fxaa+" + t.id}, warm, meas)
				restore_scene()
	if only in ["", "c"]:
		apply_preset(ps[0])
		var loc := loc_by_id("lago_sotto_nuvole")
		for res in [Vector2i(1280, 720), Vector2i(2560, 1440), Vector2i(3840, 2160)]:
			root.size = res
			await measure(loc, {"phase": "c", "round": 1, "preset": "default_fxaa@%dp" % res.y}, warm, meas)
		root.size = Vector2i(1920, 1080)
	var output := "user://freeroam_benchmark_" + Time.get_datetime_string_from_system().replace(":", "-") + ".json"
	var file := FileAccess.open(output, FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify({
		"gpu": RenderingServer.get_video_adapter_name(),
		"godot": Engine.get_version_info().string,
		"window": str(root.size),
		"vsync": DisplayServer.window_get_vsync_mode(),
		"quick": quick,
		"results": results}, "\t"))
	file.close()
	print("PASS: benchmark saved: ", ProjectSettings.globalize_path(output))
	quit()

func loc_by_id(id: String) -> Dictionary:
	for l in LOCATIONS:
		if l.id == id:
			return l
	return LOCATIONS[0]

func apply_preset(p: Dictionary) -> void:
	root.use_taa = false
	root.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	if p.mode != Viewport.SCALING_3D_MODE_BILINEAR and root.scaling_3d_scale > 1.0:
		root.scaling_3d_scale = 1.0
	root.scaling_3d_mode = p.mode
	root.scaling_3d_scale = p.scale
	root.use_taa = p.taa
	root.screen_space_aa = p.ssaa

func set_clouds(on: bool) -> void:
	world_env.compositor.compositor_effects[0].enabled = on

func set_shadows(on: bool) -> void:
	sun.shadow_enabled = on

func restore_scene() -> void:
	set_clouds(true)
	set_shadows(true)

func place_aircraft(loc: Dictionary, t: float) -> void:
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

func measure(loc: Dictionary, meta: Dictionary, warm: float, meas: float) -> void:
	place_aircraft(loc, 0.0)
	await create_timer(warm).timeout
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
	while Time.get_ticks_usec() - began < int(meas * 1000000.0):
		var elapsed := float(Time.get_ticks_usec() - began) / 1000000.0
		if loc.has("path_from"):
			place_aircraft(loc, elapsed * FLIGHT_SPEED / seg_len)
		await process_frame
		var now := Time.get_ticks_usec()
		frames.append(float(now - previous) / 1000.0)
		previous = now
		var gpu_ms := RenderingServer.viewport_get_measured_render_time_gpu(viewport_rid)
		var cpu_ms := RenderingServer.viewport_get_measured_render_time_cpu(viewport_rid)
		if gpu_ms > 0.0:
			gpu.append(gpu_ms)
		if cpu_ms > 0.0:
			cpu.append(cpu_ms)
		draws.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		prims.append(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	if frames.size() < 30:
		push_warning("Few frames at " + loc.id + ": " + str(frames.size()))
	var elapsed_ms := float(previous - began) / 1000.0
	frames.sort()
	gpu.sort()
	cpu.sort()
	draws.sort()
	prims.sort()
	var n := frames.size()
	var result := meta.duplicate()
	result["location"] = loc.id
	result["window"] = str(root.size)
	result["frames"] = n
	result["fps"] = snappedf(n * 1000.0 / elapsed_ms, 0.1)
	result["median_ms"] = snappedf(frames[n / 2], 0.01)
	result["p90_ms"] = snappedf(frames[mini(ceili(n * 0.9) - 1, n - 1)], 0.01)
	result["p99_ms"] = snappedf(frames[mini(ceili(n * 0.99) - 1, n - 1)], 0.01)
	result["gpu_median_ms"] = snappedf(gpu[gpu.size() / 2], 0.01) if not gpu.is_empty() else 0.0
	result["gpu_p99_ms"] = snappedf(gpu[mini(ceili(gpu.size() * 0.99) - 1, gpu.size() - 1)], 0.01) if not gpu.is_empty() else 0.0
	result["cpu_render_ms"] = snappedf(cpu[cpu.size() / 2], 0.01) if not cpu.is_empty() else 0.0
	result["draw_calls"] = int(draws[draws.size() / 2])
	result["primitives_k"] = int(prims[prims.size() / 2] / 1000.0)
	result["vram_mb"] = int(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0)
	results.append(result)
	print(JSON.stringify(result))
