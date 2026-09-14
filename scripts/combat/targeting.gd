extends Node
class_name TargetLock

signal target_changed(target: Node3D)
signal lock_completed(target: Node3D)
signal lock_lost()

## Group the owner is allowed to hunt. The player currently hunts the "targets" group.
@export var target_group := "targets"
## A director-owned pilot supplies its assignment; it must not silently acquire another target.
@export var auto_acquire := true
## Optional chase camera, set only on the player's TargetLock. With a camera the lock gate is
## the viewport rectangle instead of the nose cone. Enemies leave this empty and keep the cone.
@export var camera_path := NodePath("")
@export var lock_cone_degrees := 25.0
@export var lock_range := 5000.0
@export var select_range := 15000.0
@export var select_cone_degrees := 50.0
@export var lock_time := 1.0

var target = null
var lock_progress := 0.0
var is_locked := false
var in_lock_zone := false


func _physics_process(delta: float) -> void:
	if not _target_alive(target):
		_set_target(_first_candidate() if auto_acquire else null)
	if target == null:
		in_lock_zone = false
		return

	in_lock_zone = _in_lock_zone(target)
	if not in_lock_zone:
		_release_lock()
		lock_progress = maxf(lock_progress - delta / maxf(lock_time, 0.001), 0.0)
		return
	if is_locked:
		return

	lock_progress = 1.0 if lock_time <= 0.0 else minf(lock_progress + delta / lock_time, 1.0)
	if lock_progress >= 1.0:
		is_locked = true
		lock_completed.emit(target)


func cycle_target() -> void:
	var candidates := _get_candidates()
	if candidates.is_empty():
		# Nothing in the select cone: keep a focus anyway, cycling every live enemy by distance.
		candidates = _get_alive_candidates()
	if candidates.is_empty():
		_set_target(null)
		return
	_set_target(candidates[(candidates.find(target) + 1) % candidates.size()])


func distance_to_target() -> float:
	if not _target_alive(target):
		return -1.0
	var aircraft := get_parent() as Node3D
	if aircraft == null:
		return -1.0
	return aircraft.global_position.distance_to(_target_position(target))


## Multi-lock weapons use the same live-target gate as the normal lock.
## This is a query rather than a second targeting state, so cycling the primary target stays intact.
func locked_targets(maximum: int) -> Array:
	if maximum <= 0:
		return []
	var locks: Array = []
	for candidate in _get_candidates():
		if not _in_lock_zone(candidate):
			continue
		locks.append(candidate)
		if locks.size() >= maximum:
			break
	return locks


func _get_candidates() -> Array:
	var candidates: Array = []
	var aircraft := get_parent()
	for candidate in get_tree().get_nodes_in_group(target_group):
		if candidate == aircraft:
			continue
		if not _target_alive(candidate) or _distance_to(candidate) > select_range:
			continue
		if _uses_screen_lock():
			if not _is_on_screen(candidate):
				continue
		elif select_cone_degrees < 180.0 and _target_angle(candidate) > deg_to_rad(select_cone_degrees):
			continue
		candidates.append(candidate)
	candidates.sort_custom(Callable(self, "_sort_candidates"))
	return candidates


func _sort_candidates(first, second) -> bool:
	if _uses_screen_lock():
		return _screen_distance(first) < _screen_distance(second)
	return _target_angle(first) < _target_angle(second)


func _first_candidate():
	var candidates := _get_candidates()
	if candidates.is_empty():
		candidates = _get_alive_candidates()
	return null if candidates.is_empty() else candidates[0]


## Every live enemy in the group, nearest first, ignoring the select cone and range so the
## focus never drops while hostiles remain. Locking still needs the lock cone and range.
func _get_alive_candidates() -> Array:
	var candidates: Array = []
	var aircraft := get_parent()
	for candidate in get_tree().get_nodes_in_group(target_group):
		if candidate == aircraft or not _target_alive(candidate):
			continue
		candidates.append(candidate)
	candidates.sort_custom(Callable(self, "_sort_by_distance"))
	return candidates


func _sort_by_distance(first, second) -> bool:
	return _distance_to(first) < _distance_to(second)


func _set_target(next_target) -> void:
	if target == next_target and (next_target != null or typeof(target) == TYPE_NIL):
		return
	target = next_target
	lock_progress = 0.0
	in_lock_zone = false
	_release_lock()
	if target != null:
		target_changed.emit(target)


func _release_lock() -> void:
	if not is_locked:
		return
	is_locked = false
	lock_lost.emit()


func _target_alive(candidate) -> bool:
	if candidate == null or not is_instance_valid(candidate) or not (candidate is Node3D):
		return false
	if not candidate.is_inside_tree() or not candidate.has_method("is_alive"):
		return false
	return bool(candidate.call("is_alive"))


## Shared lock gate, also read by the HUD reticle. With a camera configured the target must
## project inside the viewport; without one the nose cone applies (AI). A configured but
## unavailable camera locks nothing instead of falling back to the cone.
func is_in_lock_zone(candidate) -> bool:
	return _in_lock_zone(candidate)


func _in_lock_zone(candidate) -> bool:
	if not _target_alive(candidate):
		return false
	var aircraft := get_parent() as Node3D
	if aircraft == null:
		return false
	var offset := _target_position(candidate) - aircraft.global_position
	var distance := offset.length()
	if distance <= 0.001 or distance > lock_range:
		return false
	if _uses_screen_lock():
		return _is_on_screen(candidate)
	var forward := -aircraft.global_basis.z.normalized()
	return forward.angle_to(offset / distance) <= deg_to_rad(lock_cone_degrees)


func _uses_screen_lock() -> bool:
	return not camera_path.is_empty()


func _lock_camera() -> Camera3D:
	var camera := get_node_or_null(camera_path) as Camera3D
	if camera == null or not is_instance_valid(camera) or not camera.is_inside_tree():
		return null
	return camera


## On-screen with no padding: projected inside the viewport rectangle, ahead of the camera.
## No occlusion or silhouette checks, matching the HUD projection.
func _is_on_screen(candidate) -> bool:
	var camera := _lock_camera()
	if camera == null:
		return false
	var target_position := _target_position(candidate)
	if camera.is_position_behind(target_position):
		return false
	var viewport := camera.get_viewport()
	if viewport == null:
		return false
	return viewport.get_visible_rect().has_point(camera.unproject_position(target_position))


func _screen_distance(candidate) -> float:
	var camera := _lock_camera()
	if camera == null:
		return INF
	var target_position := _target_position(candidate)
	if camera.is_position_behind(target_position):
		return INF
	var viewport := camera.get_viewport()
	if viewport == null:
		return INF
	return camera.unproject_position(target_position).distance_to(viewport.get_visible_rect().get_center())


func _distance_to(candidate) -> float:
	var aircraft := get_parent() as Node3D
	if aircraft == null:
		return INF
	return aircraft.global_position.distance_to(_target_position(candidate))


func _target_angle(candidate) -> float:
	var aircraft := get_parent() as Node3D
	if aircraft == null:
		return INF
	var offset := _target_position(candidate) - aircraft.global_position
	if offset.length_squared() <= 0.000001:
		return INF
	return (-aircraft.global_basis.z).normalized().angle_to(offset.normalized())


func _target_position(candidate) -> Vector3:
	return candidate.get("global_position")
