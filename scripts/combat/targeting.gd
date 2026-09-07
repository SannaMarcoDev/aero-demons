extends Node
class_name TargetLock

signal target_changed(target: Node3D)
signal lock_completed(target: Node3D)
signal lock_lost()

## Group the owner is allowed to hunt. The player currently hunts the "targets" group.
@export var target_group := "targets"
@export var lock_cone_degrees := 25.0
@export var lock_range := 5000.0
@export var select_range := 15000.0
@export var select_cone_degrees := 50.0
@export var lock_time := 1.0
@export_range(0.01, 0.5, 0.01) var candidate_refresh_interval := 0.0667

var target = null
var lock_progress := 0.0
var is_locked := false
var in_lock_zone := false
var _candidate_scores: Dictionary = {}
var _candidate_snapshot: Array = []
var _candidate_snapshot_valid := false
var _candidate_refresh_remaining := 0.0


func _physics_process(delta: float) -> void:
	_candidate_refresh_remaining = maxf(_candidate_refresh_remaining - delta, 0.0)
	if not _target_alive(target):
		_set_target(_first_candidate())
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
	var candidates := _get_candidates(true)
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


## Multi-lock weapons use the same live-target, range and cone gate as the normal lock.
## This is a query rather than a second targeting state, so cycling the primary target stays intact.
func locked_targets(maximum: int, force_refresh := false) -> Array:
	if maximum <= 0:
		return []
	var locks: Array = []
	for candidate in _get_candidates(force_refresh):
		if not _target_alive(candidate) or not _in_lock_zone(candidate):
			continue
		locks.append(candidate)
		if locks.size() >= maximum:
			break
	return locks


func _get_candidates(force_refresh := false) -> Array:
	if not force_refresh and _candidate_snapshot_valid and _candidate_refresh_remaining > 0.0:
		return _candidate_snapshot
	_candidate_snapshot = _query_candidates()
	_candidate_snapshot_valid = true
	_candidate_refresh_remaining = candidate_refresh_interval
	return _candidate_snapshot


func _query_candidates() -> Array:
	var candidates: Array = []
	var aircraft := get_parent() as Node3D
	if aircraft == null:
		return candidates
	_candidate_scores.clear()
	var origin := aircraft.global_position
	var forward := -aircraft.global_basis.z.normalized()
	var max_distance_squared := select_range * select_range
	var select_cone_radians := deg_to_rad(select_cone_degrees)
	var cone_limited := select_cone_radians < PI
	var cone_cosine := cos(maxf(select_cone_radians, 0.0))
	for candidate in get_tree().get_nodes_in_group(target_group):
		if candidate == aircraft or not _target_alive(candidate):
			continue
		var offset := _target_position(candidate) - origin
		var distance_squared := offset.length_squared()
		if distance_squared <= 0.000001 or distance_squared > max_distance_squared:
			continue
		var score := forward.dot(offset / sqrt(distance_squared))
		if cone_limited and score < cone_cosine:
			continue
		candidates.append(candidate)
		_candidate_scores[candidate] = score
	candidates.sort_custom(Callable(self, "_sort_candidates"))
	_candidate_scores.clear()
	return candidates


func _sort_candidates(first, second) -> bool:
	return _candidate_scores[first] > _candidate_scores[second]


func _first_candidate():
	for candidate in _get_candidates():
		if _target_alive(candidate):
			return candidate
	return null


func _set_target(next_target) -> void:
	if target == next_target:
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


func _in_lock_zone(candidate) -> bool:
	var aircraft := get_parent() as Node3D
	if aircraft == null:
		return false
	var offset := _target_position(candidate) - aircraft.global_position
	var distance_squared := offset.length_squared()
	if distance_squared <= 0.000001 or distance_squared > lock_range * lock_range:
		return false
	var cone_radians := deg_to_rad(lock_cone_degrees)
	if cone_radians >= PI:
		return true
	var forward := -aircraft.global_basis.z.normalized()
	return forward.dot(offset / sqrt(distance_squared)) >= cos(maxf(cone_radians, 0.0))


func _target_position(candidate) -> Vector3:
	return candidate.get("global_position")
