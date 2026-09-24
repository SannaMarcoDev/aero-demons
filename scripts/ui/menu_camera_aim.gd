extends Camera3D

@export var target_position := Vector3(0.0, 0.2, 0.0)
@export var rear_position := Vector3(-3, 6, -15)
@export var rear_target := Vector3(0, 3, 12)
@export var travel_duration := 2.2

var _overview_position: Vector3
var _travel := 0.0

func _ready() -> void:
	_overview_position = position
	set_view(0.0)
	var viewport := get_viewport() as SubViewport
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	viewport.size_changed.connect(func():
		if viewport.render_target_update_mode != SubViewport.UPDATE_ALWAYS:
			viewport.render_target_update_mode = SubViewport.UPDATE_ONCE)

func set_view(progress: float) -> void:
	_travel = progress
	# Arc around the wing and tail rather than cutting through the aircraft.
	position = _overview_position.bezier_interpolate(
		Vector3(-19, 6, 10), Vector3(-15, 7, -18), rear_position, progress)
	look_at(target_position.lerp(rear_target, progress), Vector3.UP)

func travel_to(rear: bool) -> Tween:
	var viewport := get_viewport() as SubViewport
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var tween := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_method(set_view, _travel, 1.0 if rear else 0.0, travel_duration)
	tween.finished.connect(func(): viewport.render_target_update_mode = SubViewport.UPDATE_ONCE)
	return tween

func fade_ui(ui: Control, show_ui: bool, overlay: CanvasItem = null) -> Tween:
	var tween := create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_OUT if show_ui else Tween.EASE_IN)
	tween.tween_property(ui, "modulate:a", 1.0 if show_ui else 0.0, 0.28)
	tween.tween_property(ui, "scale", Vector2.ONE if show_ui else Vector2(0.985, 0.985), 0.28)
	if overlay != null:
		tween.tween_property(overlay, "modulate:a", 1.0 if show_ui else 0.0, 0.28)
	return tween
