class_name MapLighting
extends Node
## Applies a MapLightingPreset to a map instance of this level (Sky3D, SkyDome,
## CloudLayer3D). Place it after the map in the level tree.

const ENVIRONMENT_KEYS: Array[StringName] = [&"glow_intensity", &"glow_bloom",
	&"glow_hdr_threshold", &"adjustment_enabled", &"adjustment_contrast", &"adjustment_saturation"]

@export var map: Node3D
@export var preset: MapLightingPreset

# The Environment is a sub-resource of the map scene: restore it so a later
# mission loading the same cached map does not inherit this preset.
var _environment: Environment
var _environment_defaults := {}


func _ready() -> void:
	if map == null or preset == null:
		push_error("MapLighting: assign map and preset.")
		return
	var sky: Sky3D = map.get_node("Sky3D")
	var dome: SkyDome = sky.get_node("SkyDome")
	var clouds: CloudLayer3D = map.get_node("CloudLayer3D")

	sky.current_time = preset.time_of_day
	sky.sun_energy = preset.sun_energy
	sky.ambient_energy = preset.ambient_energy
	sky.sky_contribution = preset.sky_contribution
	dome.sun_horizon_light_color = preset.sun_horizon_color
	dome.atm_horizon_light_tint = preset.atm_horizon_light_tint

	clouds.haze_distance = preset.haze_distance
	clouds.haze_height = preset.haze_height
	clouds.haze_color = preset.haze_color
	clouds.haze_sun_scattering = preset.haze_sun_scattering
	clouds.haze_sky_light = preset.haze_sky_light
	clouds.horizon_haze = preset.horizon_haze
	clouds.base_darkening = preset.cloud_base_darkening
	clouds.shadow_darkness = preset.cloud_shadow_darkness

	_environment = sky.environment
	for key in ENVIRONMENT_KEYS:
		_environment_defaults[key] = _environment.get(key)
	_environment.glow_intensity = preset.glow_intensity
	_environment.glow_bloom = preset.glow_bloom
	_environment.glow_hdr_threshold = preset.glow_hdr_threshold
	_environment.adjustment_enabled = true
	_environment.adjustment_contrast = preset.contrast
	_environment.adjustment_saturation = preset.saturation


func _exit_tree() -> void:
	if _environment != null:
		for key in _environment_defaults:
			_environment.set(key, _environment_defaults[key])
