extends "res://scripts/camera/free_fly_camera.gd"
## Look-dev for the explosions over Riva (6 = ground impact on the terrain); never loaded by a mission.

const KIND_NAMES := ["MISSILE", "HEAVY", "NAPALM", "AIRCRAFT", "COOK_OFF", "GROUND"]
const KIND_SCALES := [1.0, 1.7, 1.25, 3.0, 1.0, 1.0]
## Viewing distance per unit of blast scale.
var view_distance := 90.0
const DRIFT_SPEED := 220.0

var kind := Explosion.Kind.MISSILE
var drift := false
@onready var _world: Node3D = $".."
@onready var _status: Label = $"../HUD/Status"


func _ready() -> void:
	super._ready()
	process_mode = Node.PROCESS_MODE_ALWAYS
	make_current()
	_show("")


func target() -> Vector3:
	var point: Vector3 = global_position - global_basis.z * view_distance * KIND_SCALES[kind]
	if kind != Explosion.Kind.GROUND:
		return point
	# Ground blasts sit on the terrain along the view ray, or under the aim point if it misses.
	var hit := _ray(global_position, global_position - global_basis.z * 20000.0)
	return hit if hit != Vector3.INF else on_ground(point)


func on_ground(point: Vector3) -> Vector3:
	var hit := _ray(point + Vector3.UP * 4000.0, point - Vector3.UP * 4000.0)
	return hit if hit != Vector3.INF else point


func _ray(from: Vector3, to: Vector3) -> Vector3:
	var hit := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from, to))
	return hit.position if not hit.is_empty() else Vector3.INF


func fire(p_kind: int, p_seed := -1, at := Vector3.INF) -> Explosion:
	kind = p_kind as Explosion.Kind
	var velocity := global_basis.x * DRIFT_SPEED if drift and kind != Explosion.Kind.GROUND else Vector3.ZERO
	var point := target() if at == Vector3.INF else at
	if kind == Explosion.Kind.GROUND:
		point = on_ground(point)
	var blast := Explosion.spawn(_world, point, KIND_SCALES[p_kind], p_kind, velocity, p_seed)
	_show("%s / %s  (seed %d)" % [KIND_NAMES[p_kind], blast.variant_name, blast.effect_seed])
	return blast


## Every variant of a family side by side.
func gallery(p_kind: int) -> void:
	var count: int = Explosion.VARIANTS[p_kind].size()
	kind = p_kind as Explosion.Kind
	var spacing: float = 34.0 * KIND_SCALES[p_kind]
	for index in count:
		fire(p_kind, seed_for(p_kind, index), target() + global_basis.x * (index - (count - 1) * 0.5) * spacing)
	_show("%s gallery: %s" % [KIND_NAMES[p_kind], ", ".join(Explosion.VARIANTS[p_kind].map(func(v): return v.name))])


## One blast repeated across the view at staggered ages, frozen when the oldest reaches its age,
## so its whole life reads in a single frame (left = youngest).
func timeline(p_kind: int, p_seed: int, ages: Array = [0.08, 0.25, 0.6, 1.2, 2.4, 4.0]) -> void:
	get_tree().paused = false
	kind = p_kind as Explosion.Kind
	var last: float = ages.max()
	var spacing: float = 26.0 * KIND_SCALES[p_kind]
	for index in ages.size():
		var at: Vector3 = target() + global_basis.x * (index - (ages.size() - 1) * 0.5) * spacing
		_fire_later(p_kind, p_seed, at, last - float(ages[index]))
	await get_tree().create_timer(last, false).timeout
	get_tree().paused = true
	_show("%s timeline, ages %s (frozen, P resumes)" % [KIND_NAMES[p_kind], str(ages)])


func seed_for(p_kind: int, variant: int) -> int:
	var candidate := 1
	while Explosion.pick_variant(p_kind, candidate) != variant:
		candidate += 1
	return candidate


func _fire_later(p_kind: int, p_seed: int, at: Vector3, delay: float) -> void:
	if delay > 0.0:
		await get_tree().create_timer(delay, false).timeout
	fire(p_kind, p_seed, at)


func _show(last: String) -> void:
	_status.text = "%s\ndrift %s  |  %.0f FPS" % [last, "%.0f m/s" % DRIFT_SPEED if drift else "off", Engine.get_frames_per_second()]


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode >= KEY_1 and event.keycode <= KEY_6:
			fire(event.keycode - KEY_1)
		elif event.keycode == KEY_R:
			fire(kind)
		elif event.keycode == KEY_G:
			gallery(kind)
		elif event.keycode == KEY_T:
			timeline(kind, randi())
		elif event.keycode == KEY_V:
			drift = not drift
			_show("")
		elif event.keycode == KEY_P:
			get_tree().paused = not get_tree().paused
		elif event.keycode == KEY_B:
			rotation_degrees.x = -28.0 if is_zero_approx(rotation_degrees.x) else 0.0
		elif event.keycode == KEY_H:
			$"../HUD".visible = not $"../HUD".visible
		else:
			super._unhandled_input(event)
	else:
		super._unhandled_input(event)
