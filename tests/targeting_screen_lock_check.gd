extends SceneTree
## Run: godot --headless --path . --script tests/targeting_screen_lock_check.gd
## Player lock gate is the camera viewport (range still comes from lock_range, which the
## weapon controller syncs to the equipped missile). AI locks without a camera keep the
## nose cone. Selection prefers screen centre; the off-screen fallback focus stays.

const Targeting = preload("res://scripts/combat/targeting.gd")


class MockTarget extends Node3D:
	var alive := true

	func is_alive() -> bool:
		return alive


var _viewport: SubViewport
var _player: Node3D
var _lock: TargetLock
var _cam: Camera3D
var _spawned: Array = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_build_rig()
	_check_off_cone_still_locks()
	_check_edges_and_outside()
	_check_range_from_player()
	_check_range_follows_lock_range()
	_check_rotated_camera_and_optics()
	_check_aspect_ratios()
	_check_missing_camera_locks_nothing()
	_check_ai_keeps_cone()
	_check_multilock_and_selection()
	_teardown()
	root.get_node("AudioManager").queue_free()
	# Let the audio thread release stopped playback before the engine shuts down.
	await create_timer(0.5).timeout
	print("Targeting screen-lock checks passed")
	quit()


func _build_rig() -> void:
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(1280, 720)
	root.add_child(_viewport)
	_player = Node3D.new()
	_player.name = "Player"
	_viewport.add_child(_player)
	_lock = Targeting.new()
	_lock.name = "TargetLock"
	_lock.lock_time = 0.0
	_lock.lock_range = 2000.0
	_lock.select_range = 10000.0
	_player.add_child(_lock)
	_cam = Camera3D.new()
	_cam.name = "Cam"
	_cam.current = true
	_cam.fov = 70.0
	_player.add_child(_cam)
	_lock.camera_path = NodePath("../Cam")


func _teardown() -> void:
	for node in _spawned:
		if is_instance_valid(node):
			node.free()
	_spawned.clear()
	_viewport.free()


func _spawn(pos: Vector3) -> MockTarget:
	var target := MockTarget.new()
	root.add_child(target)
	target.global_position = pos
	target.add_to_group("targets")
	_spawned.append(target)
	return target


func _clear_targets() -> void:
	for node in _spawned:
		if is_instance_valid(node):
			node.free()
	_spawned.clear()
	_lock._set_target(null)


func _at_pixel(px: Vector2, dist: float) -> Vector3:
	return _cam.project_ray_origin(px) + _cam.project_ray_normal(px) * dist


func _rect() -> Rect2:
	return _cam.get_viewport().get_visible_rect()


## Visible on the camera axis while 30 degrees off the nose: outside the old 25-degree
## cone, but a valid lock that completes instantly (player lock_time is 0).
func _check_off_cone_still_locks() -> void:
	_cam.rotation.y = deg_to_rad(30.0)
	var target := _spawn(_cam.global_transform * Vector3(0, 0, -1500))
	var offset: Vector3 = target.global_position - _player.global_position
	assert((-_player.global_basis.z).angle_to(offset.normalized()) > deg_to_rad(25.0))
	assert(_lock.is_in_lock_zone(target))
	_lock._physics_process(0.1)
	assert(_lock.target == target and _lock.is_locked)
	_cam.rotation.y = 0.0
	_clear_targets()


func _check_edges_and_outside() -> void:
	var rect := _rect()
	var inside := [
		Vector2(2, 2), Vector2(rect.size.x - 3, 2),
		Vector2(2, rect.size.y - 3), Vector2(rect.size.x - 3, rect.size.y - 3),
		Vector2(rect.size.x * 0.5, 2), Vector2(rect.size.x * 0.5, rect.size.y - 3),
		Vector2(2, rect.size.y * 0.5), Vector2(rect.size.x - 3, rect.size.y * 0.5),
		rect.get_center(),
	]
	for px in inside:
		assert(_lock.is_in_lock_zone(_spawn(_at_pixel(px, 1500.0))), "pixel %s locks" % px)
	var outside := [
		Vector2(-6, rect.size.y * 0.5), Vector2(rect.size.x + 5, rect.size.y * 0.5),
		Vector2(rect.size.x * 0.5, -6), Vector2(rect.size.x * 0.5, rect.size.y + 5),
	]
	for px in outside:
		assert(not _lock.is_in_lock_zone(_spawn(_at_pixel(px, 1500.0))), "pixel %s locks nothing" % px)
	assert(not _lock.is_in_lock_zone(_spawn(Vector3(0, 0, 500))))
	var dead := _spawn(Vector3(0, 0, -1500))
	dead.alive = false
	assert(not _lock.is_in_lock_zone(dead))
	_clear_targets()


## Distance is measured from the player, not the camera: with the camera 100 m above the
## nose, a target 1999 m ahead of the player still locks although it is over 2000 m away
## from the camera itself.
func _check_range_from_player() -> void:
	_cam.position = Vector3(0, 100, 0)
	assert(_lock.is_in_lock_zone(_spawn(Vector3(0, 0, -1999))))
	assert(not _lock.is_in_lock_zone(_spawn(Vector3(0, 0, -2001))))
	_cam.position = Vector3.ZERO
	_clear_targets()


## No fixed range inside the gate: it follows lock_range, which the weapon controller
## keeps synced to the equipped missile.
func _check_range_follows_lock_range() -> void:
	var target := _spawn(Vector3(0, 0, -1500))
	assert(_lock.is_in_lock_zone(target))
	_lock.lock_range = 800.0
	assert(not _lock.is_in_lock_zone(target))
	_lock.lock_range = 5000.0
	var far := _spawn(Vector3(0, 0, -4000))
	assert(_lock.is_in_lock_zone(far))
	_lock.lock_range = 2000.0
	_clear_targets()


## The gate tracks the camera, not the nose, under rotated views and different optics:
## it always matches an independent projection of the same world points, and at least
## one probe flips when the optics change.
func _check_rotated_camera_and_optics() -> void:
	var probes := [
		Vector3(0, 0, -1500), Vector3(1200, 100, -1500), Vector3(-1600, -200, -1200),
		Vector3(0, 0, 500), Vector3(0, 0, -1900),
	]
	_cam.rotation = Vector3(deg_to_rad(-10.0), deg_to_rad(45.0), 0.0)
	_check_matches_projection(probes, "rotated")
	_cam.rotation = Vector3.ZERO
	_cam.fov = 40.0
	var narrow := _snapshot(probes)
	_cam.fov = 90.0
	var wide := _snapshot(probes)
	assert(narrow != wide, "optics change must move the gate")
	_check_matches_projection(probes, "wide fov")
	_cam.rotation = Vector3(deg_to_rad(-20.0), deg_to_rad(-30.0), 0.0)
	_cam.fov = 55.0
	_check_matches_projection(probes, "tilted narrow")
	_cam.rotation = Vector3.ZERO
	_cam.fov = 70.0
	_clear_targets()


func _check_aspect_ratios() -> void:
	# The same world point is visible in landscape, but outside a portrait viewport.
	var target := _spawn(Vector3(900, 0, -1500))
	_viewport.size = Vector2i(1600, 900)
	assert(_lock.is_in_lock_zone(target))
	_viewport.size = Vector2i(900, 1600)
	assert(not _lock.is_in_lock_zone(target))
	_clear_targets()
	for dimensions in [Vector2i(1600, 900), Vector2i(900, 1600), Vector2i(1024, 768)]:
		_viewport.size = dimensions
		_check_edges_and_outside()
	_viewport.size = Vector2i(1280, 720)


func _snapshot(probes: Array) -> Array:
	var result := []
	for pos in probes:
		result.append(_lock.is_in_lock_zone(_spawn(pos)))
	_clear_targets()
	return result


func _check_matches_projection(probes: Array, label: String) -> void:
	for pos in probes:
		var expected := _player.global_position.distance_to(pos) <= _lock.lock_range \
				and not _cam.is_position_behind(pos) \
				and _rect().has_point(_cam.unproject_position(pos))
		assert(_lock.is_in_lock_zone(_spawn(pos)) == expected, "%s probe %s" % [label, pos])
	_clear_targets()


## A configured camera that is gone locks nothing instead of falling back to the cone.
func _check_missing_camera_locks_nothing() -> void:
	var target := _spawn(Vector3(0, 0, -1500))
	assert(_lock.is_in_lock_zone(target))
	_lock.camera_path = NodePath("../Missing")
	assert(not _lock.is_in_lock_zone(target))
	assert(_lock._get_candidates().is_empty())
	_lock.camera_path = NodePath("../Cam")
	_clear_targets()


## No camera configured: the original nose cone applies, screen position is irrelevant.
func _check_ai_keeps_cone() -> void:
	var owner := Node3D.new()
	root.add_child(owner)
	var ai := Targeting.new()
	ai.lock_cone_degrees = 20.0
	ai.lock_range = 2000.0
	owner.add_child(ai)
	var ahead: Vector3 = owner.global_position + Vector3(0, 0, -1500).rotated(Vector3.UP, deg_to_rad(10.0))
	var aside: Vector3 = owner.global_position + Vector3(0, 0, -1500).rotated(Vector3.UP, deg_to_rad(30.0))
	assert(ai.is_in_lock_zone(_spawn(ahead)))
	assert(not ai.is_in_lock_zone(_spawn(aside)))
	owner.free()
	_clear_targets()


## Multi-lock only returns qualified targets within the limit; selection prefers screen
## centre; with nothing on screen the focus fallback still yields a target that cannot lock.
func _check_multilock_and_selection() -> void:
	var rect := _rect()
	var center := _spawn(_at_pixel(rect.get_center(), 1500.0))
	var edge := _spawn(_at_pixel(Vector2(rect.size.x - 10, rect.size.y * 0.5), 1500.0))
	var other := _spawn(_at_pixel(Vector2(10, rect.size.y * 0.5), 1500.0))
	var offscreen := _spawn(_at_pixel(Vector2(rect.size.x + 50, rect.size.y * 0.5), 1500.0))
	var pair := _lock.locked_targets(2)
	assert(pair.size() == 2 and pair[0] == center)
	assert(pair.has(edge) or pair.has(other))
	var all := _lock.locked_targets(9)
	assert(all.size() == 3 and not all.has(offscreen))
	assert(_lock._get_candidates()[0] == center)
	center.global_position = Vector3(0, 0, 500)
	edge.global_position = Vector3(0, 3000, 500)
	other.global_position = Vector3(3000, 0, 500)
	offscreen.global_position = Vector3(-3000, 0, 500)
	assert(_lock._get_candidates().is_empty())
	_lock.cycle_target()
	assert(_lock.target != null and _lock.target.is_alive())
	assert(not _lock.is_in_lock_zone(_lock.target))
	_clear_targets()
