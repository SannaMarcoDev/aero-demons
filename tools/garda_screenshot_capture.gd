extends SceneTree
## Takes screenshots of Garda Lake freeroam from multiple perspectives
## (aerial, mid-flight, lake shore, ground level, alpine peaks, airport)
## and saves them into the user's Downloads / Scaricati folder.
##
## Usage:
## node tools/run_godot_check.cjs 180 /tmp/garda_capture.log GODOT --path . --script res://tools/garda_screenshot_capture.gd

const Settings = preload("res://scripts/ui/settings_manager.gd")
const SCENE_PATH := "res://scenes/levels/freeroam.tscn"

var output: String = OS.get_environment("HOME").path_join("Scaricati")


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			output = arg.trim_prefix("--out=")
	_run.call_deferred()


func _run() -> void:
	assert(DisplayServer.get_name() != "headless", "Captures require graphical Forward+")
	DirAccess.make_dir_recursive_absolute(output)

	var scene: Node3D = load(SCENE_PATH).instantiate()
	root.add_child(scene)
	current_scene = scene

	var player := scene.get_node("Player") as Node3D
	player.set_physics_process(false)
	player.process_mode = Node.PROCESS_MODE_DISABLED
	player.hide()

	var hud := scene.get_node("CombatHUD")
	hud.hide()
	for node in scene.find_children("*", "CanvasLayer", true, false):
		node.hide()

	var boundary := scene.get_node_or_null("GardaLake/TutorialBoundaryController")
	if boundary != null:
		boundary.set_physics_process(false)

	var settings := Settings.load_settings("user://screenshot_settings.cfg")
	settings.merge(Settings.QUALITY_PRESETS[Settings.QUALITY_ULTRA], true)
	settings.merge({
		"upscaler": Settings.UPSCALER_OFF,
		"aa_mode": Settings.AA_TAA,
		"vsync": false,
		"fps_limit": 0,
		"resolution": "1920x1080",
		"window_mode": 0
	}, true)
	Settings.apply_settings(settings)
	root.size = Vector2i(1920, 1080)
	root.content_scale_size = root.size

	var camera := Camera3D.new()
	camera.far = 400000.0
	camera.near = 0.5
	camera.fov = 70.0
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	scene.add_child(camera)
	camera.make_current()

	var terrain: Terrain3D = scene.get_node("GardaLake/GardaTerrain")
	terrain.set_camera(camera)

	var sky := scene.get_node("GardaLake/Sky3D")
	sky.get_node("SkyDome").process_method = 2 # MANUAL

	var driver = scene.get_node("GardaLake/SunshineCloudsDriverGD")
	driver.set_process(false)
	driver.retrieve_texture_data()
	var clouds = driver.clouds_resource
	clouds.current_time = 0.0
	clouds.extra_large_scale_clouds_position = Vector3.ZERO
	clouds.large_scale_clouds_position = Vector3.ZERO
	clouds.medium_scale_clouds_position = Vector3.ZERO
	clouds.detail_clouds_position = Vector3.ZERO

	var forests = scene.get_node_or_null("GardaLake/Forests")
	if forests != null:
		while not forests.built:
			await process_frame

	var center := Vector3(0, terrain.data.get_height(Vector3(0, 0, -2200)), -2200)

	var views := [
		{
			"file": "garda_01_vista_aerea_alta.png",
			"pos": Vector3(-30000, 11000, 18000),
			"target": Vector3(-45000, 408, -5000),
			"desc": "Vista aerea ad alta quota (11.000m) sull'intero Lago di Garda e le Alpi"
		},
		{
			"file": "garda_02_vista_aerea_lago.png",
			"pos": Vector3(-45000, 7500, 15000),
			"target": Vector3(-45000, 408, -10000),
			"desc": "Vista aerea (7.500m) lungo l'asse del lago tra le catene montuose"
		},
		{
			"file": "garda_03_sopra_crociera.png",
			"pos": center + Vector3(0, 3300, 5500),
			"target": center + Vector3(-4000, 200, -7000),
			"desc": "Quota di crociera (3.300m) sopra valli e rilievi montuosi"
		},
		{
			"file": "garda_04_sopra_valle.png",
			"pos": center + Vector3(900, 700, 1300),
			"target": center + Vector3(-1800, 100, -2600),
			"desc": "Volo a media quota (700m) sulla vallata e boschi"
		},
		{
			"file": "garda_05_vicino_lago_riva.png",
			"pos": Vector3(-45300, 430, 40),
			"target": Vector3(-45242, 408, 0),
			"desc": "A pelo d'acqua sulla riva del lago"
		},
		{
			"file": "garda_06_vicino_lago_costa.png",
			"pos": Vector3(-54000, 460, -11000),
			"target": Vector3(-50000, 408, -10000),
			"desc": "Bassa quota sul lago verso la costa e le scogliere"
		},
		{
			"file": "garda_07_vicino_terreno_prato.png",
			"pos": center + Vector3(75, 4, 140),
			"target": center + Vector3(0, 10, 0),
			"desc": "Molto vicino al terreno su prato e vegetazione"
		},
		{
			"file": "garda_08_vicino_terreno_bosco.png",
			"pos": center + Vector3(140, 55, 220),
			"target": center + Vector3(0, 8, 0),
			"desc": "Vicino al terreno tra gli alberi e i declivi"
		},
		{
			"file": "garda_09_montagne_alpine.png",
			"pos": Vector3(-120920, 1876, -114800) + Vector3(2500, 750, -500),
			"target": Vector3(-120920, 1876, -114800),
			"desc": "Cime e crinali alpini innevati"
		},
		{
			"file": "garda_10_aeroporto_pista.png",
			"pos": Vector3(-36418, 450, 1800),
			"target": Vector3(-36418, 240, -2500),
			"desc": "Panoramica dell'aeroporto con lago sullo sfondo"
		}
	]

	for view in views:
		var pos: Vector3 = view.pos
		var target: Vector3 = view.target
		var ground_h: float = terrain.data.get_height(pos)
		if is_finite(ground_h):
			pos.y = maxf(pos.y, ground_h + 3.0)
		camera.global_position = pos
		var dir: Vector3 = (target - pos).normalized()
		var up: Vector3 = Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.99 else Vector3.FORWARD
		camera.look_at(target, up)

		if forests != null:
			forests.update_center(camera.global_position)
			while not forests.built:
				await process_frame

		# The external runner owns the deadline; never silently capture a partial forest.
		await create_timer(2.0).timeout

		await RenderingServer.frame_post_draw
		var img := root.get_texture().get_image()
		var save_path := output.path_join(view.file)
		var err := img.save_png(save_path)
		if err == OK:
			print("SAVED: ", save_path)
		else:
			push_error("Failed to save: " + save_path)

	# Clean up
	clouds.enabled = false
	sky.compositor = null
	RenderingServer.call_on_render_thread(clouds.clear_compute)
	await RenderingServer.frame_post_draw

	var audio_mgr = root.get_node_or_null("AudioManager")
	if audio_mgr != null:
		for audio in audio_mgr.get_children():
			if audio is AudioStreamPlayer:
				audio.stop()
				audio.stream = null

	scene.queue_free()
	for f in 4:
		await process_frame

	print("PASS: GARDA CAPTURES COMPLETE")
	quit()
