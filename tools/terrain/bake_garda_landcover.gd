extends SceneTree
## Offline, deterministic landscape data. Reads the DEM; never changes Terrain3D regions.
## R woodland, G cultivated lowland, BA unsigned 16-bit height (-128..4096 m).
const Development = preload("res://scripts/maps/garda_development.gd")
const SIZE := 4096
const STEP := 250000.0 / SIZE
const OUTPUT := "res://resources/terrain/garda_landcover.res"

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var map: Node3D = load("res://scenes/maps/garda_final.tscn").instantiate()
	var terrain: Terrain3D = map.get_node("GardaTerrain")
	map.remove_child(terrain)
	map.free()
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.make_current()
	terrain.set_camera(camera)
	root.add_child(terrain)
	await process_frame
	var noise := FastNoiseLite.new()
	noise.seed = 7319
	noise.frequency = 0.00065
	noise.fractal_octaves = 3
	var fine := FastNoiseLite.new()
	fine.seed = 1847
	fine.frequency = 0.003
	fine.fractal_octaves = 2
	var image := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var forest_pixels := 0
	var field_pixels := 0
	for z in SIZE:
		for x in SIZE:
			var point := Vector3((x + 0.5) * STEP - 125000.0, 0, (z + 0.5) * STEP - 125000.0)
			point.y = terrain.data.get_height(point)
			assert(is_finite(point.y), "Landcover sample outside DEM")
			var normal := terrain.data.get_normal(point)
			var broad := noise.get_noise_2d(point.x, point.z)
			var detail := fine.get_noise_2d(point.x, point.z)
			var land := smoothstep(190.0, 210.0, point.y)
			var arable := (1.0 - smoothstep(650.0, 1250.0, point.y)) * smoothstep(0.94, 0.985, normal.y)
			arable *= smoothstep(-0.28, 0.08, broad) * land
			var woodland := smoothstep(-0.35, 0.12, broad + detail * 0.35 + 0.16)
			woodland *= smoothstep(0.80, 0.91, normal.y) * (1.0 - smoothstep(1650.0, 2050.0, point.y)) * land
			woodland *= 1.0 - smoothstep(0.18, 0.55, arable)
			if Development.contains(point):
				arable = 0.0
				woodland = 0.0
			forest_pixels += int(woodland > 0.5)
			field_pixels += int(arable > 0.5)
			var encoded := roundi(clampf((point.y + 128.0) / 4224.0, 0.0, 1.0) * 65535.0)
			image.set_pixel(x, z, Color(woodland, arable, float(encoded >> 8) / 255.0, float(encoded & 255) / 255.0))
		if z % 256 == 0:
			print("LANDCOVER ROW ", z, "/", SIZE)
			await process_frame
	assert(forest_pixels > 10000 and field_pixels > 10000)
	image.generate_mipmaps()
	assert(ResourceSaver.save(image, OUTPUT, ResourceSaver.FLAG_COMPRESS) == OK)
	print("Woodland pixels: ", forest_pixels, "; agricultural pixels: ", field_pixels)
	terrain.queue_free()
	for audio in root.get_node("AudioManager").get_children():
		if audio is AudioStreamPlayer:
			audio.stop()
			audio.stream = null
	for i in 4: await process_frame
	print("PASS: GARDA LANDCOVER BAKE")
	quit()
