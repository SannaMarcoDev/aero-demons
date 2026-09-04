extends SceneTree

func _init():
	call_deferred("_run")

func _run():
	var root_3d = Node3D.new()
	root.add_child(root_3d)

	var terrain_scene = load("res://scenes/real_terrain_valtellina.tscn").instantiate()
	root_3d.add_child(terrain_scene)
	var terrain: Terrain3D = terrain_scene.get_node("Terrain3D")

	var cam = Camera3D.new()
	cam.current = true
	root_3d.add_child(cam)
	terrain.set_camera(cam)

	# Give a few frames for Terrain3D initialization
	for f in range(5):
		await process_frame

	var data: Terrain3DData = terrain.data
	print("Region count: ", data.get_region_count())
	print("Height at (0, 0): ", data.get_height(Vector3(0, 0, 0)))
	print("Height at (4000, 4000): ", data.get_height(Vector3(4000, 0, 4000)))
	print("Height range: ", data.get_height_range())
	quit(0)
