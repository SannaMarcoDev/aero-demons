extends SceneTree

func _init():
	var a = load("res://terrain/valtellina_assets.tres")
	if not a:
		print("FAILED to load valtellina_assets.tres")
		quit(1)
		return
	print("SUCCESS: Loaded valtellina_assets.tres with ", a.texture_list.size(), " textures.")
	for t in a.texture_list:
		print("  Slot %d: %s | UV scale: %.4f | Normal depth: %.2f" % [t.id, t.name, t.uv_scale, t.normal_depth])
	quit(0)
