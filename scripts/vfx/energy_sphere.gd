@tool
extends StaticBody3D
## Solid 500 m anomaly. Resize with diameter_m, not the node's scale.
## Motion and pulsation affect energy only: mesh silhouette and collider stay spherical.

@export_range(1.0, 5000.0, 1.0, "suffix:m") var diameter_m := 500.0:
	set(value):
		diameter_m = clampf(value, 1.0, 5000.0)
		_refresh()
@export_group("Energy")
@export_color_no_alpha var violet := Color(0.38, 0.025, 0.95):
	set(value):
		violet = value
		_refresh()
@export_color_no_alpha var magenta := Color(0.85, 0.035, 0.48):
	set(value):
		magenta = value
		_refresh()
@export_range(0.0, 8.0) var emission_strength := 2.2:
	set(value):
		emission_strength = value
		_refresh()
@export_range(0.2, 0.8) var core_radius := 0.55:
	set(value):
		core_radius = value
		_refresh()
@export_range(0.003, 0.06, 0.001) var filament_width := 0.017:
	set(value):
		filament_width = value
		_refresh()
@export_range(0.3, 3.0) var pattern_scale := 1.0:
	set(value):
		pattern_scale = value
		_refresh()
@export_group("Motion")
@export_range(0.0, 2.0) var animation_speed := 0.35:
	set(value):
		animation_speed = value
		_refresh()
@export_range(0.0, 0.2) var pulse_amount := 0.055:
	set(value):
		pulse_amount = value
		_refresh()
@export_range(0.0, 100.0) var phase := 0.0:
	set(value):
		phase = value
		_refresh()
@export_group("Halo")
@export_range(0.0, 4.0) var halo_strength := 0.65:
	set(value):
		halo_strength = value
		_refresh()
@export_range(0.01, 0.4) var halo_width := 0.13:
	set(value):
		halo_width = value
		_refresh()


func _ready() -> void:
	_refresh()


func _refresh() -> void:
	if not is_node_ready():
		return
	var radius := diameter_m * 0.5
	$Surface.scale = Vector3.ONE * radius
	$Halo.scale = Vector3.ONE * radius * (1.0 + halo_width)
	$CollisionShape3D.shape.radius = radius
	for parameter in [&"violet", &"magenta", &"emission_strength", &"core_radius", &"filament_width", &"pattern_scale", &"animation_speed", &"pulse_amount", &"phase"]:
		$Surface.material_override.set_shader_parameter(parameter, get(parameter))
	for parameter in [&"violet", &"halo_strength", &"halo_width", &"animation_speed", &"pulse_amount", &"phase"]:
		$Halo.material_override.set_shader_parameter(parameter, get(parameter))
