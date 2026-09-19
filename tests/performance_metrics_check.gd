extends SceneTree

# Run in an empty project to avoid unrelated game/audio autoloads.
const Benchmark = preload("../tools/freeroam_benchmark.gd")

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var frames: Array[float] = []
	for i in range(1, 101): frames.append(float(i))
	frames.reverse()
	var summary := Benchmark.summarize_frames(frames)
	assert(summary.median_ms == 50.0)
	assert(summary.p95_ms == 95.0 and summary.p99_ms == 99.0)
	assert(summary.max_ms == 100.0)
	assert(summary["frames_over_5.0_ms"] == 95)
	assert(summary["frames_over_16.667_ms"] == 84)
	assert(summary["frames_over_50.0_ms"] == 50)
	assert(Benchmark.summarize_frames([5.0])["frames_over_5.0_ms"] == 0)
	assert(frames[0] == 100.0) # Summarizing must not reorder the timeline.
	print("PASS: frame percentiles, stutter thresholds, singleton and immutable timeline")
	quit()
