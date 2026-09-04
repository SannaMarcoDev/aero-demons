extends SceneTree

func _init():
	var file = FileAccess.open("res://terrain/masks/semantic_grid_6144x6144.bin", FileAccess.READ)
	if not file:
		print("Failed to open semantic_grid_6144x6144.bin")
		quit(1)
		return
	var buf = file.get_buffer(6144 * 6144)
	print("Loaded buffer length: ", buf.size())
	var img = Image.create_from_data(6144, 6144, false, Image.FORMAT_R8, buf)
	print("Image format: ", img.get_format(), " size: ", img.get_size())
	print("Sample at center (3072, 3072): ", img.get_pixel(3072, 3072).r8)
	quit(0)
