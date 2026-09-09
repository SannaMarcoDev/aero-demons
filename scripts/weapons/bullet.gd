extends Node3D
class_name Bullet

const HIT_VFX_SCENE: PackedScene = preload("res://assets/BinbunVFX/impact_explosions/effects/hit/vfx_hit_02.tscn")

@export var speed := 1200.0
@export var gravity := 9.8
@export var tracer_visible := true
@export var damage := 6.0
@export var max_range := 2500.0
@export_flags_3d_physics var target_layers := 4

var velocity := Vector3.ZERO
var hit_callback := Callable()

var _distance_traveled := 0.0
var _launched := false


func launch(start_transform: Transform3D, launch_direction: Vector3, inherited_velocity: Vector3) -> void:
	global_transform = start_transform
	var direction := launch_direction.normalized()
	if direction.length_squared() <= 0.000001:
		direction = -global_basis.z
	velocity = direction * speed + inherited_velocity
	_distance_traveled = 0.0
	_launched = true
	$Tracer.visible = tracer_visible
	$Tracer.scale.z = randf_range(0.85, 1.15)
	_orient_to_velocity()


func _physics_process(delta: float) -> void:
	if not _launched:
		return
	var velocity_length := velocity.length()
	if velocity_length <= 0.001:
		queue_free()
		return
	var remaining_range := maxf(max_range - _distance_traveled, 0.0)
	var frame_velocity := velocity + Vector3.DOWN * gravity * delta * 0.5
	var displacement := frame_velocity * delta
	var travel_distance := minf(displacement.length(), remaining_range)
	if travel_distance <= 0.0:
		queue_free()
		return
	var from := global_position
	var to := from + displacement.normalized() * travel_distance
	var query := PhysicsRayQueryParameters3D.create(from, to, target_layers)
	query.collide_with_areas = true
	query.collide_with_bodies = false
	var result := get_world_3d().direct_space_state.intersect_ray(query)
	if not result.is_empty():
		global_position = result.get("position", to)
		var collider = result.get("collider")
		if collider != null and collider.has_method("apply_damage") and damage > 0.0:
			var receiver: Node = collider if collider.has_method("is_alive") else collider.get_parent()
			var alive := is_instance_valid(receiver) and (not receiver.has_method("is_alive") or bool(receiver.call("is_alive")))
			collider.call("apply_damage", damage)
			if alive and hit_callback.is_valid():
				hit_callback.call()
		var audio_manager := get_node_or_null("/root/AudioManager")
		if audio_manager != null:
			audio_manager.call("play_bullet_hit", get_parent(), global_position)
		_finish_impact()
		return
	global_position = to
	velocity += Vector3.DOWN * gravity * delta
	_distance_traveled += travel_distance
	_orient_to_velocity()
	if _distance_traveled >= max_range:
		queue_free()


func _finish_impact() -> void:
	_launched = false
	$Tracer.hide()
	if not tracer_visible:
		queue_free()
		return
	var hit_vfx := HIT_VFX_SCENE.instantiate() as Node3D
	if hit_vfx != null:
		hit_vfx.set("autoplay", false)
		hit_vfx.set("light_enable", false)
		add_child(hit_vfx)
		hit_vfx.scale = Vector3.ONE * 1.25
		hit_vfx.call("_reset_particles")
		var hit_animation := hit_vfx.get_node("AnimationPlayer") as AnimationPlayer
		hit_animation.play(&"main")
		hit_animation.seek(0.0, true)
	await get_tree().create_timer(0.8).timeout
	queue_free()


func _orient_to_velocity() -> void:
	if velocity.length_squared() <= 0.000001:
		return
	var direction := velocity.normalized()
	var up := Vector3.UP
	if absf(direction.dot(up)) > 0.98:
		up = Vector3.FORWARD
	look_at(global_position + direction, up)
