extends SceneTree
## Run: godot --headless --path . --script scripts/tests/missile_benchmark.gd

const MISSILE_SCENE: PackedScene = preload("res://scenes/weapons/missile.tscn")
const MISSILE_IDS := ["STDM", "HSSTDM", "BAHM", "NCGBM", "MTSM"]
const ITERATIONS := 20


func _initialize() -> void:
	call_deferred("_run")


func _launch(root_node: Node3D, missile_id: String) -> void:
	var missile := MISSILE_SCENE.instantiate() as HomingMissile
	missile.audio_enabled = false
	missile.missile_id = missile_id
	root_node.add_child(missile)
	missile.launch(Transform3D.IDENTITY, Vector3.ZERO, null)
	missile.free()


func _run() -> void:
	var root_node := Node3D.new()
	root.add_child(root_node)
	current_scene = root_node
	for missile_id in MISSILE_IDS:
		for _index in 3:
			_launch(root_node, missile_id)
	var started := Time.get_ticks_usec()
	for missile_id in MISSILE_IDS:
		for _index in ITERATIONS:
			_launch(root_node, missile_id)
	var elapsed_usec := Time.get_ticks_usec() - started
	var launches := MISSILE_IDS.size() * ITERATIONS
	print("Missile visual benchmark: %d launches, %.2f us/launch" % [launches, float(elapsed_usec) / launches])
	root_node.free()
	quit(0)
