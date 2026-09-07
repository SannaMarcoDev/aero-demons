extends SceneTree
## Run: godot --headless --path . --script scripts/tests/targeting_benchmark.gd

const TARGET_COUNT := 256
const ITERATIONS := 500


class DummyTarget extends Node3D:
	func is_alive() -> bool:
		return true


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var owner := Node3D.new()
	root.add_child(owner)
	var targeting := TargetLock.new()
	targeting.target_group = "benchmark_targets"
	targeting.select_range = 5000.0
	targeting.select_cone_degrees = 70.0
	owner.add_child(targeting)

	for index in TARGET_COUNT:
		var target := DummyTarget.new()
		target.name = "Target%d" % index
		target.position = Vector3(
			float((index % 32) - 16) * 12.0,
			float((index / 32) % 8) * 8.0,
			-200.0 - float(index) * 4.0,
		)
		target.add_to_group("benchmark_targets")
		owner.add_child(target)

	# Warm up imports and caches before timing the same query workload.
	for _index in 20:
		targeting._query_candidates()
	var started := Time.get_ticks_usec()
	for _index in ITERATIONS:
		targeting._query_candidates()
	var elapsed_usec := Time.get_ticks_usec() - started
	var average_usec := float(elapsed_usec) / float(ITERATIONS)
	targeting._get_candidates(true)
	var cached_started := Time.get_ticks_usec()
	for _index in ITERATIONS:
		targeting._get_candidates()
	var cached_elapsed_usec := Time.get_ticks_usec() - cached_started
	var cached_average_usec := float(cached_elapsed_usec) / float(ITERATIONS)
	print("TargetLock benchmark: %d targets, %d queries, %.2f us/query raw, %.2f us/query cached" % [TARGET_COUNT, ITERATIONS, average_usec, cached_average_usec])

	owner.free()
	quit(0)
