extends SceneTree
## node tools/run_godot_check.cjs 30 LOG GODOT --headless --path . --script tests/dialogue_resource_lifetime_check.gd
func _initialize() -> void:
	check.call_deferred()

func check() -> void:
	await create_timer(0.5).timeout # Let autoload audio finish its startup before teardown.
	var resource = load("res://resources/dialogues/tutorial.dialogue")
	var reference: WeakRef = weakref(resource)
	var line = await resource.get_next_dialogue_line("intro")
	assert(line != null)
	for data in resource.lines.values():
		assert(not data.has("resource"), "Playback must not mutate authored data with a self-reference")
	line = null
	resource = null
	await process_frame
	assert(reference.get_ref() == null, "Dialogue resource must be released after playback")
	for audio in root.get_node("AudioManager").get_children():
		if audio is AudioStreamPlayer:
			audio.stop()
			audio.stream = null
	await create_timer(0.5).timeout
	print("PASS: dialogue playback leaves no resource cycle")
	quit()
