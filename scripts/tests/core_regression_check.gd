extends SceneTree
## Run: godot --headless --path . --script scripts/tests/core_regression_check.gd

const MissileCatalog = preload("res://scripts/weapons/missile_catalog.gd")


class DummyTarget extends Node3D:
	var alive := true

	func is_alive() -> bool:
		return alive


func _initialize() -> void:
	call_deferred("_run_checks")


func _fail(message: String) -> void:
	printerr("FAIL: ", message)
	quit(1)


func _run_checks() -> void:
	var player_scene := load("res://scenes/player/player.tscn") as PackedScene
	if player_scene == null or not player_scene.can_instantiate():
		_fail("Could not load player scene")
		return

	var scene_root := Node3D.new()
	scene_root.name = "RegressionScene"
	scene_root.process_mode = Node.PROCESS_MODE_DISABLED
	root.add_child(scene_root)
	current_scene = scene_root

	var player := player_scene.instantiate() as PlayerFlight
	if player == null:
		_fail("Could not instantiate PlayerFlight")
		return
	player.faction_group = "regression_player"
	scene_root.add_child(player)
	await process_frame
	player.process_mode = Node.PROCESS_MODE_DISABLED

	var start := Transform3D(Basis.IDENTITY, Vector3(0.0, 1000.0, 0.0))
	player.reset_flight(start)
	if not player.global_transform.is_equal_approx(start):
		_fail("reset_flight did not restore transform")
		return
	if not is_equal_approx(player.speed, player.cruise_speed) or not is_equal_approx(player.health, player.max_health):
		_fail("reset_flight did not restore speed and health")
		return
	if not player.is_alive() or player.high_g_active or player.spin_dash_active:
		_fail("reset_flight left invalid flight state")
		return

	player.speed = player.cruise_speed
	player.throttle_input = 1.0
	player.brake_input = 0.0
	player._apply_flight(1.0)
	if not is_equal_approx(player.speed, 180.0):
		_fail("full throttle speed changed unexpectedly: %f" % player.speed)
		return

	player.speed = player.max_speed - 2.0
	player._apply_flight(1.0)
	if not is_equal_approx(player.speed, player.max_speed):
		_fail("speed did not clamp at max_speed")
		return

	player.speed = player.cruise_speed
	player.throttle_input = 0.0
	player.brake_input = 1.0
	player._apply_flight(1.0)
	if not is_equal_approx(player.speed, 127.5):
		_fail("braking speed changed unexpectedly: %f" % player.speed)
		return

	player.brake_input = 0.0
	player.apply_damage(20.0)
	if not is_equal_approx(player.health, 80.0):
		_fail("health damage was not applied")
		return
	player.reset_flight(start)

	var center_target := DummyTarget.new()
	center_target.name = "CenterTarget"
	center_target.position = Vector3(0.0, 1000.0, -100.0)
	center_target.add_to_group("targets")
	scene_root.add_child(center_target)
	var near_target := DummyTarget.new()
	near_target.name = "NearTarget"
	near_target.position = Vector3(10.0, 1000.0, -100.0)
	near_target.add_to_group("targets")
	scene_root.add_child(near_target)
	var outside_target := DummyTarget.new()
	outside_target.name = "OutsideTarget"
	outside_target.position = Vector3(100.0, 1000.0, -100.0)
	outside_target.add_to_group("targets")
	scene_root.add_child(outside_target)

	var targeting := player.get_node("TargetLock") as TargetLock
	targeting.process_mode = Node.PROCESS_MODE_DISABLED
	targeting.lock_time = 0.0
	targeting.lock_range = 250.0
	targeting.select_range = 250.0
	targeting.lock_cone_degrees = 20.0
	targeting.select_cone_degrees = 60.0
	targeting._physics_process(0.1)
	if targeting.target != center_target or not targeting.is_locked:
		_fail("TargetLock did not acquire the centered target")
		return
	var locked_targets := targeting.locked_targets(6)
	if locked_targets.size() != 2 or not locked_targets.has(center_target) or not locked_targets.has(near_target):
		_fail("TargetLock multi-lock cone/range gate changed")
		return

	var weapons := player.get_node("WeaponController") as WeaponController
	weapons.process_mode = Node.PROCESS_MODE_DISABLED
	weapons.reset_loadout()
	if weapons.equipped_missile_id != "STDM" or weapons.missile_ammo != 240 or weapons.get_secondary_ammo() != 210:
		_fail("default missile loadout is incorrect")
		return
	weapons.cycle_missile_type()
	if weapons.equipped_missile_id != "HSSTDM" or weapons.missile_ammo != 210:
		_fail("missile slot cycling changed")
		return
	weapons.cycle_missile_type()
	if not weapons.equip_missile("MTSM") or weapons.equipped_missile_id != "MTSM":
		_fail("valid missile equip changed the wrong slot")
		return
	if weapons.equip_missile("NOT_A_MISSILE"):
		_fail("invalid missile id was accepted")
		return
	if MissileCatalog.range_m("MTSM") != 10000.0 or MissileCatalog.get_def("MTSM").get("max_locks", 0) != 6:
		_fail("missile catalog definition changed")
		return

	# Fire once through the real controller to cover ammo decrement and cooldown gating.
	weapons.active_missile_slot = 0
	weapons.equip_missile("STDM")
	weapons.missile_ammos[0] = 2
	var ammo_before := weapons.missile_ammo
	if not weapons.can_fire_missile():
		_fail("locked target was rejected by missile fire gate")
		return
	weapons.fire_missile()
	if weapons.missile_ammo != ammo_before - 1:
		_fail("missile ammo did not decrement after firing")
		return
	if weapons.can_fire_missile():
		_fail("missile cooldown did not gate a second launch")
		return
	for missile in get_nodes_in_group("mission_projectiles"):
		missile.free()

	center_target.free()
	near_target.free()
	outside_target.free()
	player.free()
	current_scene = null
	scene_root.free()
	await process_frame
	print("Player flight, targeting, weapons and catalog: PASS")
	quit(0)
