@tool
class_name JetThrusterVFX
extends Node3D

## High-quality real-time fighter jet thruster / afterburner VFX.
## Features layered aerodynamic geometry, analytic supersonic shock diamonds,
## ultra-hot inner core streaks, turbulent gas sheath, screen-space heat haze,
## high-speed sparks, and dynamic combustion lighting.

# ==========================================
# EXPOSED INSPECTOR PARAMETERS
# ==========================================
@export_group("Throttle")
## Normalized engine throttle (0.0 = idle, 1.0 = maximum afterburner).
@export_range(0.0, 1.0, 0.01) var throttle: float = 1.0:
	set(value):
		throttle = clampf(value, 0.0, 1.0)
		if not smooth_throttle:
			_current_throttle = throttle
		_update_vfx()

## Whether to smoothly interpolate throttle changes.
@export var smooth_throttle: bool = true
## Speed of throttle transition (higher = faster response).
@export_range(0.5, 20.0) var throttle_response_speed: float = 5.0

@export_group("Dimensions")
## Full length of the afterburner plume at 100% throttle (in meters).
@export_range(1.0, 20.0, 0.1) var exhaust_length: float = 5.5:
	set(value):
		exhaust_length = maxf(value, 0.5)
		_update_vfx()

## Maximum radius/width of the exhaust plume (in meters).
@export_range(0.1, 4.0, 0.05) var exhaust_width: float = 0.55:
	set(value):
		exhaust_width = maxf(value, 0.05)
		_update_vfx()

## Distance between the flame-holder ring and the start of the plume (0 = touching).
@export_range(0.0, 2.0, 0.01) var flame_holder_distance: float = 0.65:
	set(value):
		flame_holder_distance = clampf(value, 0.0, 2.0)
		_update_vfx()

@export_group("Animation & Energy")
## Overall HDR brightness / emission multiplier.
@export_range(0.1, 5.0, 0.05) var emission_intensity: float = 1.2:
	set(value):
		emission_intensity = maxf(value, 0.01)
		_update_vfx()

## Speed of supersonic longitudinal streaks and turbulence.
@export_range(1.0, 40.0, 0.5) var flow_speed: float = 14.0:
	set(value):
		flow_speed = maxf(value, 0.1)
		_update_vfx()

## Amount of turbulent breakup and boundary distortion.
@export_range(0.0, 2.0, 0.05) var turbulence_intensity: float = 0.85:
	set(value):
		turbulence_intensity = clampf(value, 0.0, 2.0)
		_update_vfx()

@export_group("Shock Diamonds")
## Number of periodic Mach diamonds formed in supersonic expansion.
@export_range(1.0, 12.0, 1.0) var shock_diamond_count: float = 6.0:
	set(value):
		shock_diamond_count = clampf(value, 1.0, 12.0)
		_update_vfx()

## Sharpness and contrast of Mach disc compression nodes.
@export_range(1.0, 10.0, 0.5) var shock_sharpness: float = 5.0:
	set(value):
		shock_sharpness = clampf(value, 1.0, 10.0)
		_update_vfx()

@export_group("Colors")
## Color of the incandescent white-hot core center.
@export var color_core: Color = Color(1.0, 1.0, 1.0, 1.0):
	set(value):
		color_core = value
		_update_vfx()

## Color of supersonic shock diamond nodes and hot compression discs.
@export var color_shock: Color = Color(0.4, 0.82, 1.0, 1.0):
	set(value):
		color_shock = value
		_update_vfx()

## Color of the primary exhaust plume body.
@export var color_plume: Color = Color(0.18, 0.52, 1.0, 1.0):
	set(value):
		color_plume = value
		_update_vfx()

## Color of the cooler trailing flame and outer fringes.
@export var color_tail: Color = Color(0.45, 0.15, 0.85, 1.0):
	set(value):
		color_tail = value
		_update_vfx()

@export_group("Heat Distortion & Sparks")
## Strength of screen-space heat haze shimmer.
@export_range(0.0, 0.1, 0.005) var heat_distortion_intensity: float = 0.035:
	set(value):
		heat_distortion_intensity = clampf(value, 0.0, 0.1)
		_update_vfx()

## Enable supersonic sparks/embers.
@export var sparks_enabled: bool = true:
	set(value):
		sparks_enabled = value
		if _sparks:
			_sparks.emitting = sparks_enabled and _current_throttle > 0.15

## Rate multiplier for sparks.
@export_range(0.1, 5.0, 0.1) var sparks_intensity: float = 1.0

## Multiplier for dynamic engine illumination light.
@export_range(0.0, 5.0, 0.1) var light_intensity: float = 1.0

# ==========================================
# INTERNAL NODES & STATE
# ==========================================
var _current_throttle: float = 1.0

var _flame_holder: MeshInstance3D
var _inner_core: MeshInstance3D
var _shock_diamonds: MeshInstance3D
var _plume_main: MeshInstance3D
var _plume_sheath: MeshInstance3D
var _heat_distortion: MeshInstance3D
var _sparks: GPUParticles3D
var _light: OmniLight3D

var _mat_flame_holder: ShaderMaterial
var _mat_inner_core: ShaderMaterial
var _mat_shock_diamonds: ShaderMaterial
var _mat_plume_main: ShaderMaterial
var _mat_plume_sheath: ShaderMaterial
var _mat_heat_distortion: ShaderMaterial

var _noise_tex: Texture2D

const NOISE_PATH := "res://assets/thrusters/blue_thruster/materials/thruster_noise.tres"
const SHADER_FLAME_HOLDER := "res://assets/thrusters/blue_thruster/shaders/thruster_flame_holder.gdshader"
const SHADER_INNER_CORE := "res://assets/thrusters/blue_thruster/shaders/thruster_inner_core.gdshader"
const SHADER_SHOCK_DIAMONDS := "res://assets/thrusters/blue_thruster/shaders/thruster_shock_diamonds.gdshader"
const SHADER_PLUME_MAIN := "res://assets/thrusters/blue_thruster/shaders/thruster_plume_main.gdshader"
const SHADER_PLUME_SHEATH := "res://assets/thrusters/blue_thruster/shaders/thruster_plume_sheath.gdshader"
const SHADER_HEAT_DISTORTION := "res://assets/thrusters/blue_thruster/shaders/thruster_heat_distortion.gdshader"


func _ready() -> void:
	_init_noise()
	_build_hierarchy()
	_current_throttle = throttle
	_update_vfx()


func _process(delta: float) -> void:
	if smooth_throttle and not is_equal_approx(_current_throttle, throttle):
		_current_throttle = move_toward(_current_throttle, throttle, throttle_response_speed * delta)
		_update_vfx()
	elif not smooth_throttle and not is_equal_approx(_current_throttle, throttle):
		_current_throttle = throttle
		_update_vfx()

	# High-frequency combustion light flicker
	if _light and _current_throttle > 0.05:
		var flicker := 1.0 + 0.08 * sin(Time.get_ticks_msec() * 0.05) + 0.04 * cos(Time.get_ticks_msec() * 0.083)
		var base_energy := _calc_light_energy()
		_light.light_energy = base_energy * flicker


func _init_noise() -> void:
	if ResourceLoader.exists(NOISE_PATH):
		_noise_tex = load(NOISE_PATH)


func _build_hierarchy() -> void:
	# 1. Flame Holder Disc (inside nozzle exit)
	_flame_holder = get_node_or_null("FlameHolder") as MeshInstance3D
	if not _flame_holder:
		_flame_holder = MeshInstance3D.new()
		_flame_holder.name = "FlameHolder"
		add_child(_flame_holder)
		var disc_mesh := QuadMesh.new()
		disc_mesh.size = Vector2(exhaust_width * 1.5, exhaust_width * 1.5)
		_flame_holder.mesh = disc_mesh
		_flame_holder.position = Vector3(0, 0, -flame_holder_distance)
	_flame_holder.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_flame_holder.extra_cull_margin = 4.0
	_mat_flame_holder = _ensure_material(_flame_holder, SHADER_FLAME_HOLDER)

	# Shared procedural cylinder mesh along +Z
	var plume_mesh := _create_axial_cylinder_mesh(1.0, 1.0, 32, 40)

	# 2. Inner Core Flame Needle
	_inner_core = get_node_or_null("InnerCore") as MeshInstance3D
	if not _inner_core:
		_inner_core = MeshInstance3D.new()
		_inner_core.name = "InnerCore"
		add_child(_inner_core)
		_inner_core.mesh = plume_mesh
	_inner_core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_inner_core.extra_cull_margin = 12.0
	_mat_inner_core = _ensure_material(_inner_core, SHADER_INNER_CORE)
	if _noise_tex:
		_mat_inner_core.set_shader_parameter("noise_texture", _noise_tex)

	# 3. Supersonic Shock Diamonds / Mach Discs
	_shock_diamonds = get_node_or_null("ShockDiamonds") as MeshInstance3D
	if not _shock_diamonds:
		_shock_diamonds = MeshInstance3D.new()
		_shock_diamonds.name = "ShockDiamonds"
		add_child(_shock_diamonds)
		_shock_diamonds.mesh = plume_mesh
	_shock_diamonds.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_shock_diamonds.extra_cull_margin = 12.0
	_mat_shock_diamonds = _ensure_material(_shock_diamonds, SHADER_SHOCK_DIAMONDS)

	# 4. Main Plume Envelope
	_plume_main = get_node_or_null("PlumeMain") as MeshInstance3D
	if not _plume_main:
		_plume_main = MeshInstance3D.new()
		_plume_main.name = "PlumeMain"
		add_child(_plume_main)
		_plume_main.mesh = plume_mesh
	_plume_main.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_plume_main.extra_cull_margin = 12.0
	_mat_plume_main = _ensure_material(_plume_main, SHADER_PLUME_MAIN)
	if _noise_tex:
		_mat_plume_main.set_shader_parameter("noise_texture", _noise_tex)

	# 5. Outer Turbulent Sheath
	_plume_sheath = get_node_or_null("PlumeSheath") as MeshInstance3D
	if not _plume_sheath:
		_plume_sheath = MeshInstance3D.new()
		_plume_sheath.name = "PlumeSheath"
		add_child(_plume_sheath)
		_plume_sheath.mesh = plume_mesh
	_plume_sheath.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_plume_sheath.extra_cull_margin = 12.0
	_mat_plume_sheath = _ensure_material(_plume_sheath, SHADER_PLUME_SHEATH)
	if _noise_tex:
		_mat_plume_sheath.set_shader_parameter("noise_texture", _noise_tex)

	# 6. Screen-Space Heat Haze Refraction
	_heat_distortion = get_node_or_null("HeatDistortion") as MeshInstance3D
	if not _heat_distortion:
		_heat_distortion = MeshInstance3D.new()
		_heat_distortion.name = "HeatDistortion"
		add_child(_heat_distortion)
		_heat_distortion.mesh = plume_mesh
	_heat_distortion.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_heat_distortion.extra_cull_margin = 16.0
	_mat_heat_distortion = _ensure_material(_heat_distortion, SHADER_HEAT_DISTORTION)
	_mat_heat_distortion.render_priority = -1
	if _noise_tex:
		_mat_heat_distortion.set_shader_parameter("noise_texture", _noise_tex)

	# 7. Supersonic Sparks & Embers
	_sparks = get_node_or_null("Sparks") as GPUParticles3D
	if not _sparks:
		_sparks = GPUParticles3D.new()
		_sparks.name = "Sparks"
		add_child(_sparks)
		_setup_sparks()

	# 8. Dynamic Nozzle Light
	_light = get_node_or_null("NozzleLight") as OmniLight3D
	if not _light:
		_light = OmniLight3D.new()
		_light.name = "NozzleLight"
		add_child(_light)
		_light.position = Vector3(0, 0, 1.8)
		_light.omni_attenuation = 0.85
		_light.omni_shadow_mode = OmniLight3D.SHADOW_DUAL_PARABOLOID


func _ensure_material(mesh_inst: MeshInstance3D, shader_path: String) -> ShaderMaterial:
	var mat := mesh_inst.get_surface_override_material(0) as ShaderMaterial
	if not mat:
		mat = ShaderMaterial.new()
		if ResourceLoader.exists(shader_path):
			mat.shader = load(shader_path)
		mesh_inst.set_surface_override_material(0, mat)
	return mat


func _setup_sparks() -> void:
	_sparks.amount = 28
	_sparks.lifetime = 0.15
	_sparks.explosiveness = 0.0
	_sparks.randomness = 0.25
	_sparks.local_coords = false

	var pmat := ParticleProcessMaterial.new()
	pmat.particle_flag_align_y = true
	pmat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pmat.emission_sphere_radius = exhaust_width * 0.15
	pmat.direction = Vector3(0, 0, 1)
	pmat.spread = 3.5
	pmat.initial_velocity_min = 45.0
	pmat.initial_velocity_max = 75.0
	pmat.gravity = Vector3.ZERO
	pmat.scale_min = 0.02
	pmat.scale_max = 0.05
	pmat.color = Color(2.5, 1.6, 0.7, 1.0)
	_sparks.process_material = pmat

	var draw_mat := StandardMaterial3D.new()
	draw_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	draw_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	draw_mat.albedo_color = Color(3.0, 1.8, 0.8, 1.0)

	var quad := QuadMesh.new()
	quad.size = Vector2(0.012, 0.28)
	quad.material = draw_mat
	_sparks.draw_pass_1 = quad


func _create_axial_cylinder_mesh(radius: float, length: float, radial_segments: int = 32, length_segments: int = 32) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(length_segments + 1):
		var v := float(i) / float(length_segments)
		var z := v * length
		for j in range(radial_segments + 1):
			var u := float(j) / float(radial_segments)
			var angle := u * TAU
			var cos_a := cos(angle)
			var sin_a := sin(angle)
			var normal := Vector3(cos_a, sin_a, 0.0)
			var pos := Vector3(cos_a * radius, sin_a * radius, z)
			st.set_normal(normal)
			st.set_uv(Vector2(u, v))
			st.add_vertex(pos)
	for i in range(length_segments):
		for j in range(radial_segments):
			var row1 := i * (radial_segments + 1)
			var row2 := (i + 1) * (radial_segments + 1)
			st.add_index(row1 + j)
			st.add_index(row2 + j)
			st.add_index(row1 + j + 1)

			st.add_index(row1 + j + 1)
			st.add_index(row2 + j)
			st.add_index(row2 + j + 1)
	return st.commit()


func _calc_light_energy() -> float:
	var t := _current_throttle
	# Smooth ramp from idle glow to blazing afterburner light
	var curve := lerpf(0.25, 8.5, pow(t, 1.4))
	return curve * light_intensity


func _update_vfx() -> void:
	var t := _current_throttle

	# 1. Flame Holder Disc
	if _flame_holder:
		_flame_holder.position.z = -flame_holder_distance
	if _mat_flame_holder:
		_mat_flame_holder.set_shader_parameter("throttle", t)
		_mat_flame_holder.set_shader_parameter("emission_energy", 4.0 * emission_intensity)
		_mat_flame_holder.set_shader_parameter("color_afterburner", color_shock)
		_mat_flame_holder.set_shader_parameter("color_thrust", color_plume)
		_mat_flame_holder.set_shader_parameter("color_core_hot", color_core)
	if _flame_holder and _flame_holder.mesh is QuadMesh:
		var qm := _flame_holder.mesh as QuadMesh
		qm.size = Vector2(exhaust_width * 1.5, exhaust_width * 1.5)

	# 2. Inner Core
	if _mat_inner_core:
		_mat_inner_core.set_shader_parameter("throttle", t)
		_mat_inner_core.set_shader_parameter("plume_length", exhaust_length * 0.8)
		_mat_inner_core.set_shader_parameter("plume_width", exhaust_width * 0.65)
		_mat_inner_core.set_shader_parameter("emission_energy", 4.2 * emission_intensity)
		_mat_inner_core.set_shader_parameter("flow_speed", flow_speed * 1.2)
		_mat_inner_core.set_shader_parameter("color_core", color_core)
		_mat_inner_core.set_shader_parameter("color_mid", color_shock)
		_mat_inner_core.set_shader_parameter("color_tail", color_plume)

	# 3. Shock Diamonds
	if _mat_shock_diamonds:
		_mat_shock_diamonds.set_shader_parameter("throttle", t)
		_mat_shock_diamonds.set_shader_parameter("plume_length", exhaust_length * 0.95)
		_mat_shock_diamonds.set_shader_parameter("plume_width", exhaust_width * 0.85)
		_mat_shock_diamonds.set_shader_parameter("emission_energy", 5.5 * emission_intensity)
		_mat_shock_diamonds.set_shader_parameter("shock_count", shock_diamond_count)
		_mat_shock_diamonds.set_shader_parameter("shock_sharpness", shock_sharpness)
		_mat_shock_diamonds.set_shader_parameter("flow_speed", flow_speed)
		_mat_shock_diamonds.set_shader_parameter("color_core", color_core)
		_mat_shock_diamonds.set_shader_parameter("color_shock", color_shock)
		_mat_shock_diamonds.set_shader_parameter("color_outer", color_plume)

	# 4. Main Plume Envelope
	if _mat_plume_main:
		_mat_plume_main.set_shader_parameter("throttle", t)
		_mat_plume_main.set_shader_parameter("plume_length", exhaust_length)
		_mat_plume_main.set_shader_parameter("plume_width", exhaust_width)
		_mat_plume_main.set_shader_parameter("emission_energy", 2.8 * emission_intensity)
		_mat_plume_main.set_shader_parameter("flow_speed", flow_speed)
		_mat_plume_main.set_shader_parameter("turbulence_amount", turbulence_intensity)
		_mat_plume_main.set_shader_parameter("color_nozzle", color_core)
		_mat_plume_main.set_shader_parameter("color_body", color_plume)
		_mat_plume_main.set_shader_parameter("color_tail", color_tail)

	# 5. Plume Sheath
	if _mat_plume_sheath:
		_mat_plume_sheath.set_shader_parameter("throttle", t)
		_mat_plume_sheath.set_shader_parameter("plume_length", exhaust_length * 1.15)
		_mat_plume_sheath.set_shader_parameter("plume_width", exhaust_width * 1.35)
		_mat_plume_sheath.set_shader_parameter("emission_energy", 1.4 * emission_intensity)
		_mat_plume_sheath.set_shader_parameter("flow_speed", flow_speed * 0.7)
		_mat_plume_sheath.set_shader_parameter("turbulence_amount", turbulence_intensity * 1.2)
		_mat_plume_sheath.set_shader_parameter("color_halo", color_plume)
		_mat_plume_sheath.set_shader_parameter("color_fringe", color_tail)

	# 6. Heat Distortion
	if _mat_heat_distortion:
		_mat_heat_distortion.set_shader_parameter("throttle", t)
		_mat_heat_distortion.set_shader_parameter("plume_length", exhaust_length * 1.4)
		_mat_heat_distortion.set_shader_parameter("plume_width", exhaust_width * 1.5)
		_mat_heat_distortion.set_shader_parameter("distortion_strength", heat_distortion_intensity)
		_mat_heat_distortion.set_shader_parameter("flow_speed", flow_speed * 1.1)

	# 7. Sparks
	if _sparks:
		_sparks.emitting = sparks_enabled and (t > 0.15)
		var pmat := _sparks.process_material as ParticleProcessMaterial
		if pmat:
			pmat.initial_velocity_min = lerpf(20.0, 50.0, t)
			pmat.initial_velocity_max = lerpf(30.0, 80.0, t)
			_sparks.amount = int(lerpf(12.0, 70.0, t * sparks_intensity))

	# 8. Dynamic Light
	if _light:
		_light.visible = (t > 0.02)
		_light.light_energy = _calc_light_energy()
		_light.omni_range = exhaust_length * lerpf(1.2, 2.5, t)
		# Light color shifts from warm amber at idle to brilliant blue/cyan at afterburner
		var col_idle := Color(1.0, 0.45, 0.15)
		var col_burner: Color = color_shock.lerp(color_core, 0.4)
		_light.light_color = col_idle.lerp(col_burner, smoothstep(0.2, 0.8, t))
