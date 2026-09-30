extends SceneTree
## Small deterministic/streaming regression using the actual DEM, no region writes.
func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var map: Node3D = load("res://scenes/maps/garda_final.tscn").instantiate()
	map.get_node("Forests").enabled = false
	root.add_child(map)
	var cover = map.get_node("GroundCover")
	cover.set_process(false)
	var terrain: Terrain3D = map.get_node("GardaTerrain")
	assert(cover.suitable(Vector3(0, 1000, 0), Vector3.UP))
	assert(not cover.suitable(Vector3(0, 185, 0), Vector3.UP))
	assert(not cover.suitable(Vector3(0, 2000, 0), Vector3.UP))
	assert(not cover.suitable(Vector3(0, 1000, 0), Vector3.RIGHT))
	assert(not cover.suitable(Vector3(NAN, 1000, 0), Vector3.UP))
	assert(not cover.suitable(Vector3(-36418, 235, 414), Vector3.UP))
	var key := Vector2i(-19, -80)
	var first: Array[Transform3D] = cover.make_transforms(key)
	assert(first == cover.make_transforms(key), "Ground cover must be deterministic")
	assert(not first.is_empty() and first.size() <= cover.CANDIDATES)
	for transform in first:
		assert(absf(transform.origin.y + 0.035 - terrain.data.get_height(transform.origin)) < 0.01)
		assert(cover.suitable(transform.origin + Vector3.UP * 0.035, terrain.data.get_normal(transform.origin)))
	var camera := Camera3D.new()
	map.add_child(camera)
	camera.make_current()
	camera.position = Vector3(-480, 0, -3120)
	camera.position.y = terrain.data.get_height(camera.position) + 3
	for frame in 26: cover._process(0.016)
	assert(cover.tiles.size() == 25 and cover.pending.is_empty())
	camera.position.x += 4000
	camera.position.y = terrain.data.get_height(camera.position) + 3
	for frame in 26: cover._process(0.016)
	assert(cover.tiles.size() == 25)
	for cell in cover.tiles:
		assert(absi(cell.x - cover.center.x) <= 2 and absi(cell.y - cover.center.y) <= 2)
	camera.position.y += 500
	cover._process(0.016)
	assert(not cover.visible)
	assert(cover.mesh.get_surface_count() == 1)
	assert(cover.mesh.surface_get_array_len(0) == 108)
	for audio in root.get_node("AudioManager").get_children():
		if audio is AudioStreamPlayer:
			audio.stop()
			audio.stream = null
	map.queue_free()
	for frame in 4: await process_frame
	print("PASS: GARDA GROUND COVER")
	quit()
