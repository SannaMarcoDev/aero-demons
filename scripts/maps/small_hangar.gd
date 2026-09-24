extends Node3D
## Reversible playback of the Blender-authored opening, with moving door collisions.
## set_open(true/false); instant=true is intended for placement and tests.
const CYCLE: StringName = &"SmallHangar"
var openness: float = 0.0
var _motion: Tween
@onready var animation: AnimationPlayer = $Model/AnimationPlayer

func _ready() -> void:
	animation.assigned_animation = CYCLE
	_apply_pose(0.0)

func set_open(open: bool, instant: bool = false) -> void:
	if _motion:
		_motion.kill()
	var target := 1.0 if open else 0.0
	if instant or is_equal_approx(openness, target):
		_apply_pose(target)
		return
	_motion = create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	_motion.tween_method(_apply_pose, openness, target, 4.0 * absf(target - openness))

func _apply_pose(value: float) -> void:
	openness = clampf(value, 0.0, 1.0)
	animation.seek(1.0 + 4.0 * openness, true)
	$DoorUpperCollision.global_transform = $Model/SmallHangar/DoorUpper.global_transform
	$DoorLowerCollision.global_transform = $Model/SmallHangar/DoorUpper/DoorLower.global_transform
