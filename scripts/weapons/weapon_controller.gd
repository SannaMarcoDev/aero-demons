extends Node3D
class_name WeaponController

const Catalog = preload("res://scripts/weapons/missile_catalog.gd")
const Session = preload("res://scripts/ui/game_session.gd")

signal gun_fired()
signal missile_launched(missile: Node3D)
signal ammo_changed()
signal missile_switched(active_id: String, slot_index: int)

const BULLET_SCENE: PackedScene = preload("res://scenes/weapons/bullet.tscn")
const MISSILE_SCENE: PackedScene = preload("res://scenes/weapons/missile.tscn")
const MUZZLE_FLASH_SCENE: PackedScene = preload("res://assets/BinbunVFX/muzzle_flash/effects/short_flash/short_flash_02.tscn")
const MINIGUN_SOUND: AudioStream = preload("res://assets/audio/sfx/weapons/minigun-SFX.mp3")

@export var targeting_path: NodePath
## Physics layers the projectiles may hit: the enemy hitbox layer for the player, and back.
@export_flags_3d_physics var target_layers := 4
@export var gun_muzzle := Vector3(0.0, -0.3, -5.0)
@export var missile_pylons: Array[Vector3] = [Vector3(-3.2, -0.6, 0.5), Vector3(3.2, -0.6, 0.5)]

@export_category("Cannon")
@export var gun_fire_rate := 40.0
@export var gun_projectile_speed := 1200.0
@export var gun_gravity := 9.8
@export var gun_range := 2500.0
@export var gun_damage := 6.0
@export var gun_spread_degrees := 0.3
@export var gun_ammo_max: int = 2000

@export_category("Missile")
@export var equipped_missile_ids: Array[String] = ["STDM", "HSSTDM"]
@export var missile_cooldown := 0.6

var active_missile_slot: int = 0
var missile_ammos: Array[int] = [0, 0]

var gun_ammo: int
var equipped_missile_id: String:
	get:
		if equipped_missile_ids.is_empty():
			return "STDM"
		return equipped_missile_ids[active_missile_slot % equipped_missile_ids.size()]
	set(val):
		if equipped_missile_ids.is_empty():
			equipped_missile_ids = [val]
		else:
			equipped_missile_ids[active_missile_slot % equipped_missile_ids.size()] = val

var missile_ammo: int:
	get:
		if missile_ammos.is_empty():
			return 0
		return missile_ammos[active_missile_slot % missile_ammos.size()]
	set(val):
		if not missile_ammos.is_empty():
			missile_ammos[active_missile_slot % missile_ammos.size()] = val

var _targeting = null
var _gun_cooldown := 0.0
var _missile_cooldown := 0.0
var _missile_index := 0
var _gun_sound_remaining := 0.0
var _minigun_audio: AudioStreamPlayer3D
var _muzzle_flash: Node3D
var _muzzle_animation: AnimationPlayer


func _ready() -> void:
	_muzzle_flash = MUZZLE_FLASH_SCENE.instantiate() as Node3D
	if _muzzle_flash != null:
		_muzzle_flash.set("autoplay", false)
		_muzzle_flash.set("local_coords", true)
		_muzzle_flash.position = gun_muzzle
		_muzzle_flash.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
		_muzzle_flash.scale = Vector3.ONE * 1.4
		_muzzle_animation = _muzzle_flash.get_node_or_null("AnimationPlayer") as AnimationPlayer
		add_child(_muzzle_flash)
	_minigun_audio = AudioStreamPlayer3D.new()
	_minigun_audio.stream = MINIGUN_SOUND
	var audio_manager := get_node_or_null("/root/AudioManager")
	if audio_manager != null and audio_manager.has_method("setup_sfx_3d"):
		audio_manager.setup_sfx_3d(_minigun_audio, -10.0)
	else:
		_minigun_audio.bus = &"SFX"
		_minigun_audio.volume_db = -10.0
	_minigun_audio.finished.connect(_on_minigun_finished)
	add_child(_minigun_audio)
	if not targeting_path.is_empty():
		_targeting = get_node_or_null(targeting_path)
	# loadout scelto nel menu: sovrascrive l'export prima del reset
	if Session.selected_missiles.size() >= 2:
		equipped_missile_ids = Session.selected_missiles.duplicate()
	elif Catalog.DEFS.has(Session.selected_missile_id):
		equipped_missile_ids = [Session.selected_missile_id, "HSSTDM"]
	reset_loadout()


func _physics_process(delta: float) -> void:
	_gun_cooldown = maxf(_gun_cooldown - delta, -_gun_interval())
	_missile_cooldown = maxf(_missile_cooldown - delta, 0.0)
	_gun_sound_remaining = maxf(_gun_sound_remaining - delta, 0.0)
	if _gun_sound_remaining <= 0.0 and _minigun_audio != null:
		_minigun_audio.stop()


func reset_loadout() -> void:
	gun_ammo = maxi(gun_ammo_max, 0)
	active_missile_slot = 0
	missile_ammos.resize(equipped_missile_ids.size())
	for i in equipped_missile_ids.size():
		var id: String = equipped_missile_ids[i]
		var missile_max := int(Catalog.get_def(id)["ammo"])
		missile_ammos[i] = missile_max if missile_max < 0 else maxi(missile_max, 0)
	_gun_cooldown = 0.0
	_missile_cooldown = 0.0
	_missile_index = 0
	_sync_targeting_range()
	ammo_changed.emit()


func _gun_interval() -> float:
	return 1.0 / maxf(gun_fire_rate, 0.001)


func fire_gun() -> void:
	if gun_ammo <= 0 or _gun_cooldown > 0.0:
		return
	var muzzle_transform := _muzzle_transform(gun_muzzle)
	var direction := _spread_direction(-global_basis.z)
	var bullet := BULLET_SCENE.instantiate() as Bullet
	var scene_root := get_tree().current_scene
	if bullet == null or scene_root == null:
		return
	bullet.speed = gun_projectile_speed
	bullet.gravity = gun_gravity
	bullet.tracer_visible = gun_ammo % 2 == 0
	bullet.damage = gun_damage
	bullet.max_range = gun_range
	bullet.target_layers = target_layers
	scene_root.add_child(bullet)
	bullet.add_to_group("mission_projectiles")
	bullet.launch(muzzle_transform, direction, _inherited_velocity())
	if _muzzle_flash != null:
		_muzzle_flash.call("_reset_particles")
		if _muzzle_animation != null:
			_muzzle_animation.play(&"main")
			_muzzle_animation.seek(0.0, true)
	gun_ammo -= 1
	_gun_cooldown += _gun_interval()
	_gun_sound_remaining = maxf(_gun_sound_remaining, 0.12)
	if _minigun_audio != null and not _minigun_audio.playing:
		_minigun_audio.play()
	gun_fired.emit()
	ammo_changed.emit()


## The single gate that decides whether a missile leaves the rails right now: loaded, cooled
## down, pylon present and at least one acquired target. The HUD reads the same truth.
func can_fire_missile() -> bool:
	var def := get_equipped_def()
	if (missile_ammo >= 0 and missile_ammo < _missile_salvo_size(def)) \
			or _missile_cooldown > 0.0 or missile_pylons.is_empty():
		return false
	return not get_locked_missile_targets().is_empty()


## Standard missiles preserve the selected lock. Multi-lock types ask TargetLock for the same
## cone/range-qualified candidates, capped by their catalog entry.
func get_locked_missile_targets(force_refresh := false) -> Array:
	if _targeting == null:
		_targeting = get_node_or_null(targeting_path)
	if _targeting == null:
		return []
	var def := get_equipped_def()
	var lock_limit := maxi(int(def.get("max_locks", 1)), 1)
	if lock_limit > 1:
		if not _targeting.has_method("locked_targets"):
			return []
		var locks: Array = _targeting.call("locked_targets", lock_limit, force_refresh)
		var valid: Array = []
		for candidate in locks:
			if _valid_missile_target(candidate):
				valid.append(candidate)
		return valid
	if not bool(_targeting.get("is_locked")):
		return []
	var target = _targeting.get("target")
	return [target] if _valid_missile_target(target) else []


func equip_missile(id: String, slot: int = -1) -> bool:
	if not Catalog.DEFS.has(id):
		return false
	var target_slot := active_missile_slot if slot < 0 else slot
	if target_slot >= equipped_missile_ids.size():
		equipped_missile_ids.resize(target_slot + 1)
		missile_ammos.resize(target_slot + 1)
	equipped_missile_ids[target_slot] = id
	var missile_max := int(Catalog.get_def(id)["ammo"])
	missile_ammos[target_slot] = missile_max if missile_max < 0 else mini(missile_ammos[target_slot], missile_max)
	_sync_targeting_range()
	ammo_changed.emit()
	return true


func cycle_missile_type() -> void:
	if equipped_missile_ids.size() <= 1:
		return
	active_missile_slot = (active_missile_slot + 1) % equipped_missile_ids.size()
	_sync_targeting_range()
	missile_switched.emit(equipped_missile_id, active_missile_slot)
	ammo_changed.emit()


func get_secondary_missile_id() -> String:
	if equipped_missile_ids.size() <= 1:
		return ""
	var secondary_slot := (active_missile_slot + 1) % equipped_missile_ids.size()
	return equipped_missile_ids[secondary_slot]


func get_secondary_ammo() -> int:
	if missile_ammos.size() <= 1:
		return 0
	var secondary_slot := (active_missile_slot + 1) % missile_ammos.size()
	return missile_ammos[secondary_slot]


func get_equipped_def() -> Dictionary:
	return Catalog.get_def(equipped_missile_id)


func get_equipped_label() -> String:
	return Catalog.label(equipped_missile_id)

func fire_missile() -> void:
	if not can_fire_missile():
		return
	var def := get_equipped_def()
	var targets := get_locked_missile_targets(true)
	var scene_root := get_tree().current_scene
	if targets.is_empty() or scene_root == null:
		return
	var salvo_size := _missile_salvo_size(def)
	var missiles: Array = []
	for index in salvo_size:
		var missile := MISSILE_SCENE.instantiate() as HomingMissile
		if missile == null:
			for spawned in missiles:
				spawned.queue_free()
			return
		missiles.append(missile)

	var multi_lock := int(def.get("max_locks", 1)) > 1
	var inherited_velocity := _inherited_velocity()
	for index in missiles.size():
		var missile: HomingMissile = missiles[index]
		_apply_missile_def(missile, def)
		var muzzle_transform := _muzzle_transform(missile_pylons[(_missile_index + index) % missile_pylons.size()])
		scene_root.add_child(missile)
		missile.add_to_group("mission_projectiles")
		if multi_lock:
			missile.configure_split_payload(
				targets,
				float(def.get("split_delay", 0.4)),
				float(def.get("split_spread_degrees", 12.0)),
				float(def.get("split_straight_time", 0.35)),
				float(index) * PI / maxf(float(targets.size()), 1.0),
			)
			missile.launch(muzzle_transform, inherited_velocity, null)
		else:
			missile.launch(muzzle_transform, inherited_velocity, targets[0])
		missile_launched.emit(missile)

	if missile_ammo > 0:
		missile_ammo -= salvo_size
	_missile_index = (_missile_index + salvo_size) % missile_pylons.size()
	_missile_cooldown = missile_cooldown
	ammo_changed.emit()


func _missile_salvo_size(def: Dictionary) -> int:
	return maxi(int(def.get("salvo_size", 1)), 1)


func _valid_missile_target(candidate) -> bool:
	return (
		candidate != null
		and is_instance_valid(candidate)
		and candidate is Node3D
		and candidate.is_inside_tree()
		and candidate.has_method("is_alive")
		and bool(candidate.call("is_alive"))
	)


func _apply_missile_def(missile: HomingMissile, def: Dictionary) -> void:
	missile.missile_id = equipped_missile_id
	missile.speed = float(def["speed"])
	missile.acceleration = float(def["acceleration"])
	missile.max_turn_rate_degrees = float(def["turn_deg"])
	missile.seeker_fov_degrees = float(def.get("seeker_fov", 55.0))
	missile.max_range = float(def.get("range", 5000.0))
	missile.lifetime = float(def["lifetime"])
	missile.damage = float(def["damage"])
	missile.proximity_radius = float(def["proximity"])
	missile.burn_total = float(def["burn_total"])
	missile.burn_duration = float(def["burn_duration"])


func _sync_targeting_range() -> void:
	if _targeting == null and not targeting_path.is_empty():
		_targeting = get_node_or_null(targeting_path)
	if _targeting != null and _targeting.get("lock_range") != null:
		_targeting.set("lock_range", Catalog.range_m(equipped_missile_id))


func _on_minigun_finished() -> void:
	if _gun_sound_remaining > 0.0:
		_minigun_audio.play()


func _muzzle_transform(offset: Vector3) -> Transform3D:
	return global_transform * Transform3D(Basis.IDENTITY, offset)


## What the airframe is actually doing, which is not the nose ray during a spin dash.
func _inherited_velocity() -> Vector3:
	var parent := get_parent()
	if parent == null:
		return Vector3.ZERO
	if parent.has_method("velocity"):
		return parent.call("velocity")
	var parent_speed = parent.get("speed")
	if parent_speed == null:
		return Vector3.ZERO
	return (-global_basis.z).normalized() * float(parent_speed)


func _spread_direction(direction: Vector3) -> Vector3:
	var forward := direction.normalized()
	if forward.length_squared() <= 0.000001:
		return Vector3.FORWARD
	var right := forward.cross(Vector3.UP)
	if right.length_squared() <= 0.000001:
		right = forward.cross(Vector3.FORWARD)
	right = right.normalized()
	var up := right.cross(forward).normalized()
	var spread := sqrt(randf()) * tan(deg_to_rad(gun_spread_degrees))
	var angle := randf() * TAU
	return (forward + right * cos(angle) * spread + up * sin(angle) * spread).normalized()
