@tool
extends Node3D
## Place the origin at the nozzle exit. Local +Z points aft, out of the engine.
## One independent material per scene instance; no lights or particle simulation.

@export_range(0.0, 1.0, 0.01) var throttle: float = 0.0:
	set(value):
		throttle = clampf(value, 0.0, 1.0) if is_finite(value) else 0.0
@export_range(0.1, 20.0, 0.1) var response_speed: float = 5.0

@export_group("Dimensions (metres)")
@export_range(0.05, 3.0, 0.01) var nozzle_radius: float = 0.45:
	set(value):
		nozzle_radius = maxf(value, 0.05)
		_dirty = true
@export_range(0.2, 15.0, 0.1) var plume_length: float = 3.8:
	set(value):
		plume_length = maxf(value, 0.2)
		_dirty = true
@export_range(0.5, 30.0, 0.1) var heat_haze_length: float = 7.0:
	set(value):
		heat_haze_length = maxf(value, 0.5)
		_dirty = true

@export_group("Appearance")
## Approximate displacement in pixels at close range; fades with distance.
@export_range(0.0, 30.0, 0.1) var heat_distortion: float = 12.0:
	set(value):
		heat_distortion = value
		_dirty = true
@export_range(0.0, 3.0, 0.05) var turbulence: float = 0.7:
	set(value):
		turbulence = value
		_dirty = true
@export_range(0.0, 5.0, 0.05) var brightness: float = 1.0:
	set(value):
		brightness = value
		_dirty = true
@export var hot_color: Color = Color(1.0, 0.67, 0.34):
	set(value):
		hot_color = value
		_dirty = true
@export var edge_color: Color = Color(0.30, 0.39, 0.72):
	set(value):
		edge_color = value
		_dirty = true
@export_range(0.0, 3.0, 0.05) var flow_speed: float = 1.0

@export_group("Afterburner")
@export var afterburner_enabled: bool = true
@export_range(0.5, 0.99, 0.01) var afterburner_start: float = 0.85

@export_group("Performance")
## Samples per covered pixel. 16 for groups, 24 default, 40 for hero close-ups.
@export_enum("Low:16", "Balanced:24", "Close-up:40") var volume_samples: int = 24:
	set(value):
		volume_samples = clampi(value, 8, 48)
		_dirty = true
## Smoothly fades over the last 25%, then skips rendering. No global quality changes.
@export_range(20.0, 1500.0, 10.0) var max_distance: float = 350.0

var _dirty: bool = true
var _power: float = 0.0
var _clock: float = 0.0
var _material: ShaderMaterial
@onready var _volume: MeshInstance3D = $Volume

func _ready() -> void:
	_material = _volume.material_override as ShaderMaterial
	_power = throttle
	_material.set_shader_parameter("phase", float(get_instance_id() % 997) / 37.0)
	_apply_configuration()
	_process(0.0)

func _apply_configuration() -> void:
	var length_m := maxf(heat_haze_length, plume_length)
	_volume.scale = Vector3(nozzle_radius * 2.4, nozzle_radius * 2.4, length_m)
	_volume.position.z = length_m * 0.5
	_material.set_shader_parameter("nozzle_radius", nozzle_radius)
	_material.set_shader_parameter("plume_length", plume_length)
	_material.set_shader_parameter("haze_length", length_m)
	_material.set_shader_parameter("distortion", heat_distortion)
	_material.set_shader_parameter("turbulence", turbulence)
	_material.set_shader_parameter("brightness", brightness)
	_material.set_shader_parameter("hot_color", hot_color)
	_material.set_shader_parameter("edge_color", edge_color)
	_material.set_shader_parameter("steps", volume_samples)
	_dirty = false

func _process(delta: float) -> void:
	if not is_instance_valid(_material):
		return
	if _dirty:
		_apply_configuration()
	_power = lerpf(_power, throttle, 1.0 - exp(-maxf(response_speed, 0.1) * delta))
	# Integrate speed instead of multiplying TIME: throttle changes cannot jump the noise.
	_clock = fmod(_clock + delta * flow_speed * lerpf(0.35, 2.8, _power), 4096.0)
	var burn := smoothstep(clampf(afterburner_start, 0.5, 0.99), 1.0, _power) if afterburner_enabled else 0.0
	var fade := 1.0
	var camera := get_viewport().get_camera_3d()
	if camera:
		var distance := camera.global_position.distance_to(global_position)
		fade = 1.0 - smoothstep(max_distance * 0.75, max_distance, distance)
	_volume.visible = _power > 0.001 and fade > 0.001
	if not _volume.visible:
		return
	_material.set_shader_parameter("power", _power)
	_material.set_shader_parameter("burn", burn)
	_material.set_shader_parameter("clock", _clock)
	_material.set_shader_parameter("distance_fade", fade)
