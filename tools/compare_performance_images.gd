extends SceneTree
## Run headlessly in an empty project (no game autoloads); all paths may be absolute.
## --headless --path EMPTY_PROJECT --script THIS_SCRIPT -- BEFORE_DIR AFTER_DIR OUTPUT_DIR

func _initialize() -> void:
	compare.call_deferred()

func compare() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 3:
		push_error("Expected BEFORE_DIR AFTER_DIR OUTPUT_DIR")
		quit(1)
		return
	var stats := {}
	var names := DirAccess.get_files_at(args[0])
	var rows := 0
	for name in names:
		if name.ends_with(".png"): rows += 1
	if rows == 0:
		push_error("No PNG captures in " + args[0])
		quit(1)
		return
	var montage := Image.create(1280, 360 * rows, false, Image.FORMAT_RGB8)
	var index := 0
	for name in names:
		if not name.ends_with(".png"): continue
		var before := Image.load_from_file(args[0].path_join(name))
		var after := Image.load_from_file(args[1].path_join(name))
		if before == null or after == null or before.get_size() != after.get_size():
			push_error("Missing/mismatched capture " + name)
			quit(1)
			return
		before.convert(Image.FORMAT_RGB8)
		after.convert(Image.FORMAT_RGB8)
		stats[name] = before.compute_image_metrics(after, false)
		before.resize(640, 360)
		after.resize(640, 360)
		montage.blit_rect(before, Rect2i(0, 0, 640, 360), Vector2i(0, index * 360))
		montage.blit_rect(after, Rect2i(0, 0, 640, 360), Vector2i(640, index * 360))
		index += 1
	if DirAccess.make_dir_recursive_absolute(args[2]) != OK or montage.save_png(args[2].path_join("comparison.png")) != OK:
		push_error("Cannot save comparison")
		quit(1)
		return
	var file := FileAccess.open(args[2].path_join("image_metrics.json"), FileAccess.WRITE)
	if file == null:
		push_error("Cannot save metrics")
		quit(1)
		return
	file.store_string(JSON.stringify(stats, "\t"))
	file.close()
	print("PASS: image comparison ", JSON.stringify(stats))
	quit()
