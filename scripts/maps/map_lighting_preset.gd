class_name MapLightingPreset
extends Resource
## Mission lighting for a shared map: time of day, sun, air, cloud shading and grading.
## Applied by MapLighting; the map scene keeps its own authored default.

@export_group("Sun and Sky")
## Local hour on the map's TimeOfDay date and location.
@export_range(0.0, 23.99, 0.01) var time_of_day := 9.0
@export_range(0.0, 16.0, 0.01) var sun_energy := 2.0
@export var sun_horizon_color := Color(0.98, 0.523, 0.294)
@export_range(0.0, 16.0, 0.01) var ambient_energy := 1.75
@export_range(0.0, 1.0, 0.01) var sky_contribution := 0.5
@export var atm_horizon_light_tint := Color(0.96, 0.86, 0.74)

@export_group("Air")
@export_range(1000.0, 500000.0, 100.0, "suffix:m") var haze_distance := 45000.0
@export_range(100.0, 10000.0, 10.0, "suffix:m") var haze_height := 1500.0
@export var haze_color := Color(0.50, 0.57, 0.64)
@export_range(0.0, 2.0, 0.01) var haze_sun_scattering := 0.30
@export_range(0.0, 1.0, 0.01) var haze_sky_light := 0.45
@export_range(0.0, 8.0, 0.01) var horizon_haze := 1.0

@export_group("Clouds")
@export_range(0.0, 2.0, 0.01) var cloud_base_darkening := 1.0
@export_range(0.0, 1.0, 0.01) var cloud_shadow_darkness := 0.85

@export_group("Grading")
@export_range(0.0, 8.0, 0.01) var glow_intensity := 0.8
@export_range(0.0, 1.0, 0.01) var glow_bloom := 0.0
@export_range(0.0, 4.0, 0.01) var glow_hdr_threshold := 1.0
@export_range(0.5, 2.0, 0.01) var contrast := 1.0
@export_range(0.0, 2.0, 0.01) var saturation := 1.0
