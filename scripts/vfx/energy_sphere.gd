@tool
extends StaticBody3D
## Solid 500 m anomaly. Resize with diameter_m, not the node's scale.
## Every layer animates on the GPU from TIME, like the other shader VFX in pauses and replays.
## Flames, tendrils, arcs and the lens are visual only: the collider stays a plain sphere.

## Lens shell radius, in sphere radii: room for the EMP pulse to expand and fade.
const LENS_RADIUS := 3.4
const LAYERS := {
	^"Surface": [&"violet", &"magenta", &"ink", &"spark", &"emission_strength", &"animation_speed", &"pulse_amount", &"core_radius", &"swirl", &"pattern_scale", &"phase"],
	^"Corona": [&"violet", &"magenta", &"ink", &"emission_strength", &"animation_speed", &"phase", &"flame_height", &"flame_density", &"outer_radius", &"travel"],
	^"Tendrils": [&"violet", &"magenta", &"ink", &"emission_strength", &"animation_speed", &"phase"],
	^"Arcs": [&"violet", &"spark", &"emission_strength", &"phase", &"arc_rate"],
	^"Lens": [&"violet", &"ink", &"lens_strength", &"phase", &"lens_radius"],
}

@export_range(1.0, 5000.0, 1.0, "suffix:m") var diameter_m := 500.0:
	set(value):
		diameter_m = clampf(value, 1.0, 5000.0)
		_refresh()
## World velocity of whatever carries the sphere: the flames stream away from it.
@export var travel_velocity := Vector3.ZERO:
	set(value):
		travel_velocity = value
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
## Dark smoke of the skin, flames and tendrils.
@export_color_no_alpha var ink := Color(0.03, 0.006, 0.07):
	set(value):
		ink = value
		_refresh()
## Hot colour of the bolts, the eye rim and the sparkles.
@export_color_no_alpha var spark := Color(0.8, 0.72, 1.0):
	set(value):
		spark = value
		_refresh()
@export_range(0.0, 8.0) var emission_strength := 2.2:
	set(value):
		emission_strength = value
		_refresh()
## Radius of the black eye, in sphere radii.
@export_range(0.2, 0.7) var core_radius := 0.4:
	set(value):
		core_radius = value
		_refresh()
## Twist of the whirlpool arms.
@export_range(0.0, 4.0) var swirl := 1.6:
	set(value):
		swirl = value
		_refresh()
@export_range(0.3, 3.0) var pattern_scale := 1.0:
	set(value):
		pattern_scale = value
		_refresh()
@export_group("Motion")
@export_range(0.0, 3.0) var animation_speed := 1.0:
	set(value):
		animation_speed = value
		_refresh()
@export_range(0.0, 0.3) var pulse_amount := 0.08:
	set(value):
		pulse_amount = value
		_refresh()
@export_range(0.0, 100.0) var phase := 0.0:
	set(value):
		phase = value
		_refresh()
@export_group("Corona")
## Reach of the ink flames above the surface, in sphere radii.
@export_range(0.1, 1.0) var flame_height := 0.38:
	set(value):
		flame_height = value
		_refresh()
@export_range(0.0, 80.0) var flame_density := 34.0:
	set(value):
		flame_density = value
		_refresh()
@export_group("Discharges")
@export_range(0.0, 3.0) var arc_rate := 1.0:
	set(value):
		arc_rate = value
		_refresh()
## Background pull at the silhouette, in sphere radii.
@export_range(0.0, 0.3) var lens_strength := 0.05:
	set(value):
		lens_strength = value
		_refresh()


func _ready() -> void:
	_refresh()


func _refresh() -> void:
	if not is_node_ready():
		return
	var radius := diameter_m * 0.5
	# Flames lean further the faster the sphere travels; the corona shell grows to keep their tips.
	var lean := clampf(travel_velocity.length() / 300.0, 0.0, 0.8)
	var travel := Vector3.ZERO
	if lean > 0.0 and is_inside_tree():
		travel = (global_basis.inverse() * travel_velocity).normalized() * lean
	var outer := 1.0 + flame_height * (1.6 + 1.6 * lean)
	var values := {&"outer_radius": outer, &"travel": travel, &"lens_radius": LENS_RADIUS}
	$Surface.scale = Vector3.ONE * radius
	$Corona.scale = Vector3.ONE * radius * outer
	$Lens.scale = Vector3.ONE * radius * LENS_RADIUS
	$Tendrils.scale = Vector3.ONE * radius
	$Arcs.scale = Vector3.ONE * radius
	$Light.omni_range = radius * 6.0
	$Light.light_color = violet.lerp(magenta, 0.3).lightened(0.2)
	$CollisionShape3D.shape.radius = radius
	for path in LAYERS:
		var material: ShaderMaterial = get_node(path).material_override
		for parameter in LAYERS[path]:
			material.set_shader_parameter(parameter, values.get(parameter, get(parameter)))
