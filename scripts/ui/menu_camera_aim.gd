extends Camera3D

@export var target_position := Vector3(0.0, 0.2, 0.0)
@export var rear_position := Vector3(-5.5, 4.5, -14.5)
@export var rear_target := Vector3(-0.5, 2.7, -1)
@export var travel_duration := 2.2

var _overview_position: Vector3
var _travel := 0.0

func _ready() -> void:
	_overview_position = position
	set_view(0.0)

func set_view(progress: float) -> void:
	_travel = progress
	# Arc around the wing and tail rather than cutting through the aircraft.
	position = _overview_position.bezier_interpolate(
		Vector3(-17, 4, 5), Vector3(-14, 5, -24), rear_position, progress)
	look_at(target_position.lerp(rear_target, progress), Vector3.UP)

func travel_to(rear: bool) -> Tween:
	var tween := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_method(set_view, _travel, 1.0 if rear else 0.0, travel_duration)
	return tween

func fade_ui(ui: Control, show_ui: bool, overlay: CanvasItem = null) -> Tween:
	var tween := create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_OUT if show_ui else Tween.EASE_IN)
	tween.tween_property(ui, "modulate:a", 1.0 if show_ui else 0.0, 0.28)
	tween.tween_property(ui, "scale", Vector2.ONE if show_ui else Vector2(0.985, 0.985), 0.28)
	if overlay != null:
		tween.tween_property(overlay, "modulate:a", 1.0 if show_ui else 0.0, 0.28)
	return tween
