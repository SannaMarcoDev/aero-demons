extends Node3D
## Open the S01 door in the loaded tutorial before handing over control.
signal finished

var completed := false

func _ready() -> void:
	var player: PlayerFlight = get_node("../Player")
	player.controls_enabled = false
	var hud: CanvasLayer = get_node("../CombatHUD")
	hud.visible = false
	var hangar: Node3D = get_node("../GardaLake/Airport/SmallHangars/S01_SmallHangar")
	var overlay := CanvasLayer.new()
	overlay.layer = 100
	add_child(overlay)
	var black := ColorRect.new()
	black.color = Color.BLACK
	overlay.add_child(black)
	black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var camera := Camera3D.new()
	camera.fov = 75.0
	camera.position = hangar.to_global(Vector3(-2, 4, -10))
	add_child(camera)
	camera.look_at(hangar.to_global(Vector3(0, 2, 8)))
	camera.make_current()
	await get_tree().process_frame
	await create_tween().tween_property(black, "modulate:a", 0.0, 0.5).finished
	hangar.set_open(true)
	while hangar.openness < 0.999:
		await get_tree().process_frame
	player.get_node("FlightCamera").make_current()
	camera.queue_free()
	overlay.queue_free()
	hud.visible = true
	completed = true
	finished.emit()

func _input(_event: InputEvent) -> void:
	if not completed:
		get_viewport().set_input_as_handled()
