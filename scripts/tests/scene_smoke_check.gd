extends SceneTree
## Run: godot --headless --path . --script scripts/tests/scene_smoke_check.gd

func _initialize() -> void:
	call_deferred("_run_checks")


func _fail(message: String) -> void:
	printerr("FAIL: ", message)
	quit(1)


func _run_checks() -> void:
	var scene := load("res://scenes/maps/flight_playground.tscn") as PackedScene
	if scene == null or not scene.can_instantiate():
		_fail("Could not load or instantiate flight_playground.tscn")
		return

	var playground := scene.instantiate()
	if playground == null:
		_fail("flight_playground.tscn returned no root node")
		return

	var player := playground.get_node_or_null("Player") as Node3D
	var camera := playground.get_node_or_null("FlightCamera") as Camera3D
	var hud := playground.get_node_or_null("CombatHUD") as CombatHUD
	if player == null:
		_fail("FlightPlayground is missing Player")
		return
	if camera == null or camera.get_script() == null:
		_fail("FlightPlayground is missing scripted FlightCamera")
		return
	if hud == null:
		_fail("FlightPlayground is missing CombatHUD")
		return
	if player.get_node_or_null("TargetLock") == null:
		_fail("Player is missing TargetLock")
		return
	if player.get_node_or_null("WeaponController") == null:
		_fail("Player is missing WeaponController")
		return
	if hud.player_path != NodePath("../Player"):
		_fail("CombatHUD player_path is not wired to ../Player")
		return
	if hud.camera_path != NodePath("../FlightCamera"):
		_fail("CombatHUD camera_path is not wired to ../FlightCamera")
		return
	if hud.targeting_path != NodePath("../Player/TargetLock"):
		_fail("CombatHUD targeting_path is not wired to Player/TargetLock")
		return
	if hud.weapons_path != NodePath("../Player/WeaponController"):
		_fail("CombatHUD weapons_path is not wired to Player/WeaponController")
		return

	playground.free()
	print("Flight playground scene wiring: PASS")
	quit(0)
