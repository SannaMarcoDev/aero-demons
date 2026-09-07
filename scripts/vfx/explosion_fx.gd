extends Node3D
class_name Explosion

signal finished

enum QualityLevel { LOW, MEDIUM, HIGH }

const EFFECT_DURATION := 5.8
const FIRE_SHADER := preload("res://resources/shaders/vfx/explosion_fire.gdshader")
const SMOKE_SHADER := preload("res://resources/shaders/vfx/explosion_smoke.gdshader")
const SHOCKWAVE_SHADER := preload("res://resources/shaders/vfx/explosion_shockwave.gdshader")
const MISSILE_HIT_SOUND: AudioStream = preload("res://assets/audio/sfx/weapons/missile-hit.mp3")

@export_range(0.1, 8.0, 0.05) var overall_scale := 1.0:
	set(value):
		overall_scale = maxf(value, 0.1)
		if is_node_ready():
			_apply_scale()

@export_range(0.0, 4.0, 0.05) var intensity := 1.0:
	set(value):
		intensity = clampf(value, 0.0, 4.0)
		if is_node_ready():
			_apply_appearance()

@export_range(0.0, 2.0, 0.05) var smoke_amount := 1.0:
	set(value):
		smoke_amount = clampf(value, 0.0, 2.0)
		if is_node_ready():
			_apply_quality()

@export_range(0.0, 2.0, 0.05) var sparks_amount := 1.0:
	set(value):
		sparks_amount = clampf(value, 0.0, 2.0)
		if is_node_ready():
			_apply_quality()

@export_range(0.0, 32.0, 0.1) var light_energy := 10.0:
	set(value):
		light_energy = maxf(value, 0.0)

@export_range(0.5, 40.0, 0.5) var light_range := 16.0:
	set(value):
		light_range = maxf(value, 0.5)
		if is_node_ready():
			$BlastLight.omni_range = light_range * overall_scale

@export var effect_seed := 0:
	set(value):
		effect_seed = value
		if is_node_ready():
			_apply_appearance()

@export var auto_free := true
@export var quality_level: QualityLevel = QualityLevel.HIGH:
	set(value):
		quality_level = clampi(value, QualityLevel.LOW, QualityLevel.HIGH)
		if is_node_ready():
			_apply_quality()

@onready var _emitters: Array[GPUParticles3D] = [
	$Flash, $FireCore, $FireLobes, $SecondaryLobes, $Smoke, $Sparks, $Debris, $Shockwave,
]

var _fire_materials: Array[ShaderMaterial] = []
var _smoke_material: ShaderMaterial
var _shockwave_material: ShaderMaterial
var _elapsed := 0.0
var _generation := 0
var _playing := false
var _quality_light_multiplier := 1.0


const SCENE: PackedScene = preload("res://scenes/vfx/explosion_fx.tscn")

static func spawn(parent: Node, pos: Vector3, p_scale: float = 1.0) -> Explosion:
	if parent == null:
		return null
	var instance: Explosion = SCENE.instantiate()
	instance.overall_scale = p_scale
	parent.add_child(instance)
	instance.global_position = pos
	instance.play()
	return instance

static func spawn_aircraft(parent: Node, pos: Vector3, p_scale: float = 3.0) -> Explosion:
	return spawn(parent, pos, p_scale)


func _ready() -> void:
	$AudioPlayer.stream = MISSILE_HIT_SOUND
	var audio_manager := get_node_or_null("/root/AudioManager")
	if audio_manager != null and audio_manager.has_method("setup_sfx_3d"):
		audio_manager.setup_sfx_3d($AudioPlayer, -3.0)
	else:
		$AudioPlayer.bus = &"SFX"
		$AudioPlayer.volume_db = -3.0
	_build_resources()
	_apply_scale()
	_apply_quality()
	_apply_appearance()
	$BlastLight.visible = false
	$LifetimeTimer.wait_time = EFFECT_DURATION


func play() -> void:
	stop_immediately()
	_generation += 1
	_playing = true
	_elapsed = 0.0
	$BlastLight.visible = light_energy > 0.0 and intensity > 0.0
	$BlastLight.omni_range = light_range * overall_scale
	$AudioPlayer.play()

	_burst($Flash)
	_burst($FireCore)
	_burst($FireLobes)
	_burst($Sparks)
	_burst($Debris)
	_burst($Shockwave)
	_start_delayed($SecondaryLobes, 0.08, _generation)
	_start_delayed($Smoke, 0.18, _generation)
	$LifetimeTimer.start()


func stop_immediately() -> void:
	_generation += 1
	_playing = false
	$LifetimeTimer.stop()
	$AudioPlayer.stop()
	$BlastLight.visible = false
	for emitter in _emitters:
		# restart clears particles already in flight; disabling immediately prevents a new burst.
		emitter.restart()
		emitter.emitting = false


func is_playing() -> bool:
	return _playing


func _process(delta: float) -> void:
	if not _playing:
		return
	_elapsed += delta
	var pulse := exp(-_elapsed * 10.5) + 0.09 * exp(-_elapsed * 2.2)
	$BlastLight.light_energy = light_energy * intensity * _quality_light_multiplier * pulse
	$BlastLight.visible = $BlastLight.light_energy > 0.01


func _on_lifetime_timer_timeout() -> void:
	if not _playing:
		return
	_playing = false
	$BlastLight.visible = false
	for emitter in _emitters:
		emitter.emitting = false
	emit_signal("finished")
	if auto_free:
		queue_free()


func _start_delayed(emitter: GPUParticles3D, delay: float, generation: int) -> void:
	await get_tree().create_timer(delay).timeout
	if _playing and generation == _generation:
		_burst(emitter)


func _burst(emitter: GPUParticles3D) -> void:
	if emitter.visible and emitter.amount > 0:
		emitter.emitting = true
		emitter.restart()


func _apply_scale() -> void:
	scale = Vector3.ONE * overall_scale
	if is_instance_valid($BlastLight):
		$BlastLight.omni_range = light_range * overall_scale


func _apply_quality() -> void:
	var core := 6
	var main_lobes := 20
	var secondary_lobes := 12
	var smoke := 38
	var sparks := 52
	var debris := 0
	match quality_level:
		QualityLevel.LOW:
			core = 4
			main_lobes = 12
			secondary_lobes = 7
			smoke = 18
			sparks = 24
			_quality_light_multiplier = 0.55
		QualityLevel.MEDIUM:
			core = 6
			main_lobes = 18
			secondary_lobes = 10
			smoke = 30
			sparks = 44
			_quality_light_multiplier = 0.8
		QualityLevel.HIGH:
			core = 8
			main_lobes = 26
			secondary_lobes = 18
			smoke = 54
			sparks = 78
			debris = 14
			_quality_light_multiplier = 1.0

	_set_amount($Flash, 1)
	_set_amount($FireCore, core)
	_set_amount($FireLobes, main_lobes)
	_set_amount($SecondaryLobes, secondary_lobes)
	_set_amount($Smoke, roundi(smoke * smoke_amount))
	_set_amount($Sparks, roundi(sparks * sparks_amount))
	_set_amount($Debris, debris)
	_set_amount($Shockwave, 1)


func _set_amount(emitter: GPUParticles3D, amount: int) -> void:
	# GPUParticles3D requires an allocated slot even for a disabled quality layer.
	emitter.amount = maxi(amount, 1)
	emitter.visible = amount > 0


func _apply_appearance() -> void:
	var seed_offset := float(effect_seed) * 0.173
	for material in _fire_materials:
		material.set_shader_parameter("intensity", intensity)
		material.set_shader_parameter("seed_offset", seed_offset)
	_smoke_material.set_shader_parameter("intensity", intensity)
	_smoke_material.set_shader_parameter("seed_offset", seed_offset + 13.0)
	_shockwave_material.set_shader_parameter("intensity", intensity)
	_shockwave_material.set_shader_parameter("seed_offset", seed_offset + 29.0)


func _build_resources() -> void:
	_fire_materials = [
		_setup_quad($Flash, FIRE_SHADER, 1.0),
		_setup_quad($FireCore, FIRE_SHADER, 0.0),
		_setup_quad($FireLobes, FIRE_SHADER, 0.0),
		_setup_quad($SecondaryLobes, FIRE_SHADER, 0.0),
		_setup_quad($Sparks, FIRE_SHADER, 0.0),
	]
	_smoke_material = _setup_quad($Smoke, SMOKE_SHADER, 0.0)
	_shockwave_material = _setup_quad($Shockwave, SHOCKWAVE_SHADER, 0.0)
	_setup_debris()

	_configure_flash()
	_configure_fire_core()
	_configure_fire_lobes($FireLobes, 4.5, 11.0, 2.6, 5.5)
	_configure_fire_lobes($SecondaryLobes, 2.5, 7.5, 1.4, 3.2)
	_configure_smoke()
	_configure_sparks()
	_configure_shockwave()


func _setup_quad(emitter: GPUParticles3D, shader: Shader, flash_mode: float) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("flash_mode", flash_mode)
	var mesh := QuadMesh.new()
	mesh.size = Vector2.ONE
	mesh.material = material
	emitter.draw_pass_1 = mesh
	emitter.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	emitter.visibility_aabb = AABB(Vector3(-34.0, -34.0, -34.0), Vector3(68.0, 68.0, 68.0))
	emitter.one_shot = true
	emitter.explosiveness = 1.0
	return material


func _setup_process(emitter: GPUParticles3D) -> ParticleProcessMaterial:
	var process := ParticleProcessMaterial.new()
	process.direction = Vector3.UP
	process.spread = 180.0
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 0.35
	process.angle_min = -180.0
	process.angle_max = 180.0
	emitter.process_material = process
	return process


func _configure_flash() -> void:
	var process := _setup_process($Flash)
	$Flash.lifetime = 0.08
	$Flash.randomness = 0.05
	process.initial_velocity_min = 0.1
	process.initial_velocity_max = 0.5
	process.scale_min = 4.0
	process.scale_max = 5.8
	process.scale_curve = _scale_curve([Vector2(0.0, 0.18), Vector2(0.22, 1.0), Vector2(1.0, 1.25)])


func _configure_fire_core() -> void:
	var process := _setup_process($FireCore)
	$FireCore.lifetime = 0.62
	$FireCore.randomness = 0.22
	process.emission_sphere_radius = 0.48
	process.initial_velocity_min = 0.8
	process.initial_velocity_max = 3.0
	process.damping_min = 4.0
	process.damping_max = 8.0
	process.scale_min = 2.8
	process.scale_max = 4.6
	process.scale_curve = _scale_curve([Vector2(0.0, 0.22), Vector2(0.18, 1.0), Vector2(0.58, 1.25), Vector2(1.0, 0.7)])


func _configure_fire_lobes(emitter: GPUParticles3D, speed_min: float, speed_max: float, scale_min: float, scale_max: float) -> void:
	var process := _setup_process(emitter)
	emitter.lifetime = 0.78
	emitter.randomness = 0.28
	process.emission_sphere_radius = 0.75
	process.initial_velocity_min = speed_min
	process.initial_velocity_max = speed_max
	process.damping_min = 8.0
	process.damping_max = 16.0
	process.scale_min = scale_min
	process.scale_max = scale_max
	process.scale_curve = _scale_curve([Vector2(0.0, 0.16), Vector2(0.2, 1.0), Vector2(0.68, 1.18), Vector2(1.0, 0.58)])


func _configure_smoke() -> void:
	var process := _setup_process($Smoke)
	$Smoke.lifetime = 4.45
	$Smoke.randomness = 0.2
	$Smoke.draw_order = GPUParticles3D.DRAW_ORDER_LIFETIME
	process.emission_sphere_radius = 3.6
	process.direction = Vector3.UP
	process.spread = 135.0
	process.initial_velocity_min = 1.0
	process.initial_velocity_max = 4.2
	process.gravity = Vector3(0.0, 1.65, 0.0)
	process.damping_min = 1.2
	process.damping_max = 3.5
	process.angular_velocity_min = -65.0
	process.angular_velocity_max = 65.0
	process.scale_min = 1.5
	process.scale_max = 4.2
	process.scale_curve = _scale_curve([Vector2(0.0, 0.4), Vector2(0.22, 1.0), Vector2(0.7, 2.3), Vector2(1.0, 3.1)])
	$Smoke.visibility_aabb = AABB(Vector3(-42.0, -20.0, -42.0), Vector3(84.0, 88.0, 84.0))


func _configure_sparks() -> void:
	var process := _setup_process($Sparks)
	$Sparks.lifetime = 0.95
	$Sparks.randomness = 0.45
	process.emission_sphere_radius = 0.55
	process.initial_velocity_min = 17.0
	process.initial_velocity_max = 42.0
	process.gravity = Vector3(0.0, -18.0, 0.0)
	process.damping_min = 1.0
	process.damping_max = 4.0
	process.scale_min = 0.035
	process.scale_max = 0.1
	process.scale_curve = _scale_curve([Vector2(0.0, 1.0), Vector2(0.55, 0.72), Vector2(1.0, 0.0)])
	$Sparks.visibility_aabb = AABB(Vector3(-58.0, -58.0, -58.0), Vector3(116.0, 116.0, 116.0))


func _setup_debris() -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.045, 0.035, 0.025, 1.0)
	material.metallic = 0.2
	material.roughness = 0.92
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.22, 0.16, 0.3)
	mesh.material = material
	$Debris.draw_pass_1 = mesh
	$Debris.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	$Debris.visibility_aabb = AABB(Vector3(-45.0, -55.0, -45.0), Vector3(90.0, 90.0, 90.0))
	$Debris.one_shot = true
	$Debris.explosiveness = 1.0
	$Debris.lifetime = 1.5
	$Debris.randomness = 0.3
	var process := _setup_process($Debris)
	process.emission_sphere_radius = 0.8
	process.initial_velocity_min = 7.0
	process.initial_velocity_max = 17.0
	process.gravity = Vector3(0.0, -16.0, 0.0)
	process.damping_min = 0.2
	process.damping_max = 1.2
	process.angular_velocity_min = -360.0
	process.angular_velocity_max = 360.0
	process.scale_min = 0.7
	process.scale_max = 1.7


func _configure_shockwave() -> void:
	var process := _setup_process($Shockwave)
	$Shockwave.lifetime = 0.3
	$Shockwave.randomness = 0.0
	process.initial_velocity_min = 0.0
	process.initial_velocity_max = 0.0
	process.scale_min = 0.4
	process.scale_max = 0.4
	process.scale_curve = _scale_curve([Vector2(0.0, 0.15), Vector2(1.0, 15.0)])


func _scale_curve(points: Array[Vector2]) -> CurveTexture:
	var curve := Curve.new()
	for point in points:
		curve.add_point(point)
	var texture := CurveTexture.new()
	texture.curve = curve
	return texture
